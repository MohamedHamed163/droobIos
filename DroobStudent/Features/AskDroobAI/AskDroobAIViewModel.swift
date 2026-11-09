import Foundation
import SwiftUI
import PhotosUI

/// ViewModel for the Ask Droob AI chat feature.
/// Uses AIProviderManager to fetch providers from backend with automatic fallback.
@MainActor
final class AskDroobAIViewModel: ObservableObject {

    // MARK: - Published State

    @Published var messages: [AskDroobMessage] = []
    @Published var inputText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showPhotoPicker = false
    @Published var showCamera = false
    @Published var showSettings = false
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var capturedImage: UIImage?
    @Published var ocrText: String?
    @Published var isProcessingOCR = false
    @Published var lastProviderUsed: String?
    /// A finished worksheet waiting to be shared. Identifiable because
    /// `.sheet(item:)` needs identity, and exporting the same thread twice
    /// legitimately produces two different files.
    struct ExportedPDF: Identifiable {
        let id = UUID()
        let url: URL
    }

    @Published var exportedPDF: ExportedPDF?
    @Published var isExporting = false

    // MARK: - Durable session state
    //
    // The transcript used to be memory-only, so a student who answered forty
    // questions and closed the app lost all of it. Everything below is what
    // makes the same transcript a row in the Library instead.

    /// The session every new message is appended to. `nil` until the first
    /// message or the first attachment; there is exactly one live session at a
    /// time and opening one from the Library makes it the live one.
    @Published private(set) var activeSessionId: String?
    /// What the student scanned, so they can see the paper and not only what was
    /// read out of it.
    @Published private(set) var sessionAttachments: [LibraryAttachment] = []
    /// Its scans were deleted to make room. The questions read from them are
    /// still in the transcript, and the card says so.
    @Published private(set) var sessionScansEvicted = false

    /// True while "New chat" is waiting to hear that the archive landed. The
    /// transcript is still on screen throughout, and the button is disabled so
    /// it cannot be asked twice.
    @Published private(set) var isArchiving = false

    private let library = AskDroobLibraryStore.shared
    /// Whether anything has changed since the last write.
    ///
    /// Without it, merely *reading* a three-week-old session rewrote its file on
    /// the way out — and both `write` and `commit` stamp `updatedAt` — so the
    /// row moved to the top of the newest-first list showing today's time.
    /// Browse five old sessions and all five claim to be from today, in browse
    /// order: the date and the ordering are the only way a student finds "the
    /// one from before the exam", and eviction reads the same field.
    private var sessionDirty = false
    private var sessionCreatedAt = Date()
    /// Derived once from the first user message and never recomputed — a row
    /// whose title changed under the student is a row they cannot recognise.
    private var sessionTitle = ""

    // MARK: - Worksheet Intake State

    @Published var showFilePicker = false
    @Published var intakeStage: IntakeStage = .idle
    /// Caps and cancellation. Deliberately not `errorMessage`: reading only the
    /// first ten pages of a twelve-page file is information, not a failure, and
    /// rendering it in red would tell the student something broke when nothing
    /// did.
    @Published var intakeNotice: String?
    /// Questions every provider refused twice. Drives the retry affordance —
    /// without it a partial failure is invisible, because a failed question
    /// deliberately leaves no assistant bubble behind.
    @Published var failedQuestions: [String] = []

    // MARK: - Review State
    //
    // Scanning "sometimes gets the question wrong and adds wrong things", so
    // nothing extracted from a worksheet is answered until the student has seen
    // it. This is a hold between reading and answering: `runBatch` below is not
    // modified by one line, it just receives a list the student has approved.

    /// One extracted question awaiting confirmation.
    ///
    /// Identity is a `UUID`, never the index: deleting row 3 must not renumber
    /// the row an open edit sheet is pointing at.
    struct ReviewQuestion: Identifiable, Equatable {
        let id: UUID
        var text: String

        init(id: UUID = UUID(), text: String) {
            self.id = id
            self.text = text
        }
    }

    /// A row the student just deleted, kept long enough to undo.
    struct DeletedReviewQuestion: Equatable {
        let index: Int
        let question: ReviewQuestion
    }

    @Published var reviewQuestions: [ReviewQuestion] = []
    @Published var showReview = false
    /// Drives the 4 s undo bar under the review header.
    @Published var reviewUndo: DeletedReviewQuestion?

    /// The page-cap / question-cap / "read on this device" / "another model read
    /// it" lines `startBatch` used to publish immediately. Held until confirm so
    /// the student reads them next to the batch-started line rather than behind
    /// a modal sheet.
    private var pendingNotices: [String] = []

    private var undoTask: Task<Void, Never>?

    private var batchTask: Task<Void, Never>?

    var isBatchRunning: Bool { intakeStage != .idle }

    /// Free-tier keys sit around 15 RPM. One question at a time with a gap
    /// holds us near 10–12 RPM; any concurrency turns a twelve-question sheet
    /// into a burst that 429s across the whole fallback chain at once and
    /// leaves the remaining questions with no provider left to try.
    private let interQuestionDelayMs: UInt64 = 1200
    private let retryDelayMs: UInt64 = 3000

    /// Gap between page-reading requests. Longer than `interQuestionDelayMs`
    /// because a vision round trip on a page is 3–6 s: at 1200 ms that is up to
    /// ~12 requests a minute, over the 10 RPM the free tier actually enforces.
    /// At 2000 ms it is ~8 RPM with headroom.
    private let readPageDelayMs: UInt64 = 2000

    /// How much of the previous page's last question is quoted to the next page.
    /// Enough for the model to recognise a question split across a page break,
    /// short enough that it never rivals the page image for attention.
    private let carryChars = 500

    /// How much of the previous element has to match, character for character,
    /// before the two are treated as one question spanning a page break. Long
    /// enough to be unique on a worksheet, short enough to survive
    /// re-transcription drift; below `minCarryKeyChars` the previous element is
    /// a stub and not worth merging.
    private let carryKeyChars = 24
    private let minCarryKeyChars = 12

    /// How much of the transcript any single request may carry.
    ///
    /// A 40-question worksheet leaves 80 turns behind — 40 questions plus 40
    /// full step-by-step solutions, tens of thousands of tokens. Shipping that
    /// whole thing would 400 the 8k-context models in the fallback chain and
    /// blow the free-tier TPM ceilings this feature is built around
    /// (`freeLimitTpm`), so a second worksheet, a retry, or the next ordinary
    /// chat message after a batch would fail on a file that works fine from a
    /// clean thread. Eight turns is four exchanges — enough for "explain that
    /// again" to make sense, bounded enough that it never dominates a request.
    private let maxHistoryTurns = 8
    private let maxHistoryChars = 6000

    /// Nothing bigger than one worksheet's answers ever reaches a provider.
    ///
    /// Trims by turn count first, then by character budget, then drops a
    /// leading assistant turn — a window that opens on a model turn is a
    /// malformed conversation, and Gemini rejects a `contents` array whose
    /// first role is `model`.
    private func boundedHistory(
        _ history: [(role: String, content: String)]
    ) -> [(role: String, content: String)] {
        var window = Array(history.suffix(maxHistoryTurns))
        while window.count > 1,
              window.reduce(0, { $0 + $1.content.count }) > maxHistoryChars {
            window.removeFirst()
        }
        while let first = window.first, first.role == "assistant" {
            window.removeFirst()
        }
        return window
    }

    /// Consecutive total failures that end a batch early.
    ///
    /// Three questions in a row that every provider refused means the chain is
    /// down or the day's free tier is spent, not that those questions were
    /// hard. Without this a dead network costs ~4.2 s of guaranteed-futile
    /// waiting per remaining question — nearly three minutes of "Answering
    /// question 7 of 40" before a single word of error appears.
    private let maxConsecutiveFailures = 3

    // MARK: - Dependencies

    private let providerManager = AIProviderManager.shared
    private var chatHistory: [(role: String, content: String)] = []

    /// Read from storage rather than the SwiftUI environment because the view
    /// model has no view context.
    ///
    /// Delegates to `AppLocaleDefault` rather than re-reading the key here:
    /// there were two hand-rolled readers of one answer, and they agreed only
    /// because `lockIfNeeded()` happens to write the key. One reader per layer —
    /// views take `\.appLocale`, everything else takes this.
    private var isArabic: Bool { AppLocaleDefault.isArabic }

    // MARK: - Computed

    var availableProviders: [AIProviderConfig] {
        providerManager.fallbackChain
    }

    var selectedProvider: AIProviderConfig? {
        providerManager.currentProvider
    }

    var isArabicInput: Bool {
        let text = inputText
        let arabicRange = text.unicodeScalars.filter {
            (0x0600...0x06FF).contains($0.value) ||
            (0x0750...0x077F).contains($0.value) ||
            (0xFB50...0xFDFF).contains($0.value) ||
            (0xFE70...0xFEFF).contains($0.value)
        }
        return Double(arabicRange.count) / Double(max(text.unicodeScalars.count, 1)) > 0.3
    }

    // MARK: - Init

    init() {
        // Reads (or rebuilds) the index once per process, off the main thread.
        library.start()
        Task {
            await providerManager.fetchProviders()
        }
    }

    // MARK: - Session plumbing

    /// The session this chat writes to, created on demand. Saving is automatic
    /// and continuous — a student never has to remember to save.
    @discardableResult
    private func ensureSession() -> String {
        if let existing = activeSessionId { return existing }
        let id = UUID().uuidString.lowercased()
        activeSessionId = id
        sessionCreatedAt = Date()
        sessionTitle = ""
        sessionAttachments = []
        sessionScansEvicted = false
        sessionDirty = false
        library.setLiveSession(id)
        return id
    }

    private var sessionSeed: LibrarySessionSeed {
        LibrarySessionSeed(
            title: sessionTitle,
            locale: isArabic ? "ar" : "en",
            createdAt: sessionCreatedAt)
    }

    /// Writes the whole transcript.
    ///
    /// `immediate` for an assistant message: an answer is 3–6 s of network and,
    /// on the free tier, a spent quota unit, so a batch killed at question 31 of
    /// 40 must restore with 30 questions and 30 answers. Coalesced for a user
    /// message: the worst case is losing one unanswered bubble inside a 400 ms
    /// window, which costs nothing to retype, and during a batch it is followed
    /// by an immediate write seconds later anyway.
    ///
    /// A no-op when nothing has changed. Every write stamps `updatedAt`, so an
    /// unconditional flush on the way out of a session the student only *read*
    /// would move it to the top of the Library dated today.
    private func persistSession(immediate: Bool) {
        guard let id = activeSessionId, sessionDirty else { return }
        sessionDirty = false
        library.persist(currentPayload(id: id), immediate: immediate)
    }

    /// The transcript exactly as it stands, ready for the store.
    private func currentPayload(id: String) -> LibrarySessionPayload {
        deriveTitleIfNeeded()
        return LibrarySessionPayload(
            id: id,
            title: sessionTitle,
            locale: isArabic ? "ar" : "en",
            createdAt: sessionCreatedAt,
            messages: messages.map {
                LibraryMessage(
                    id: $0.id.uuidString,
                    isUser: $0.role == .user,
                    text: $0.content,
                    at: $0.timestamp,
                    provider: $0.provider)
            })
    }

    private func deriveTitleIfNeeded() {
        guard sessionTitle.isEmpty else { return }
        if let first = messages.first(where: { $0.role == .user }) {
            sessionTitle = AskDroobLibraryStore.derivedTitle(from: first.content)
        }
        if sessionTitle.isEmpty, let attachment = sessionAttachments.first {
            sessionTitle = (attachment.name as NSString)
                .deletingPathExtension
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if sessionTitle.isEmpty, !sessionAttachments.isEmpty {
            sessionTitle = Strings.scannedWorksheetTitle(isArabic)
        }
    }

    /// Keeps the uploaded file with its session, written before intake reads a
    /// byte of it: a kill during reading then leaves the scan in the Library
    /// with an empty transcript — recoverable, and honest about what happened.
    private func storeAttachment(
        data: Data, name: String, mime: String, isPDF: Bool
    ) async {
        let id = ensureSession()
        var pages = 1
        if isPDF {
            pages = (try? await WorksheetIntake.pageCount(pdfData: data)) ?? 0
        }
        do {
            let attachment = try await library.addAttachment(
                sessionId: id, seed: sessionSeed, data: data,
                name: name, mime: mime, pages: pages)
            sessionAttachments.append(attachment)
            sessionScansEvicted = false
            sessionDirty = true
            deriveTitleIfNeeded()
            // So the row is titled from the file name even if the process dies
            // before the first question is read out of it.
            persistSession(immediate: true)
        } catch {
            // Never fatal: the questions can still be read out of the bytes in
            // memory. Only the copy on disk was lost.
            intakeNotice = Self.libraryErrorText(error, isArabic)
        }
    }

    private static func libraryErrorText(_ error: Error, _ ar: Bool) -> String {
        if let library = error as? LibraryError, case .outOfSpace = library {
            return Strings.storageFull(ar)
        }
        return Strings.saveFailed(ar)
    }

    /// The one place a thrown error becomes something a student reads.
    ///
    /// Every error type in this feature builds its `errorDescription` in
    /// English, and `error.localizedDescription` was being assigned straight to
    /// `errorMessage` on the send path, the photo paths and the export path —
    /// i.e. on every ordinary network or export failure, not some rare corner.
    /// Translating here rather than inside each `errorDescription` keeps the
    /// English text intact for logs and for `englishHidden = false`, and keeps
    /// the mapping on the main actor where the locale is already known.
    private static func errorText(_ error: Error, _ ar: Bool) -> String {
        if error is LibraryError { return libraryErrorText(error, ar) }

        if let ai = error as? AIProviderManager.AIError {
            switch ai {
            case .emptyResponse:        return Strings.errEmptyReply(ar)
            case .noVisionProvider:     return Strings.errNoVisionProvider(ar)
            case .noProvidersAvailable: return Strings.errNoProviders(ar)
            case .unsupportedProvider(let name):
                return Strings.errUnsupportedProvider(ar, name: name)
            case .invalidURL:           return Strings.errInvalidURL(ar)
            case .networkError:         return Strings.errNetwork(ar)
            case .rateLimited(let name):
                return Strings.errRateLimited(ar, name: name)
            // Server-supplied text, in whatever language the provider chose —
            // usually an English JSON fragment. A student can do nothing with
            // it, so it becomes one Arabic sentence they can act on.
            case .apiError:             return Strings.errProviderFailed(ar)
            }
        }

        // `FreeAIService.AIError` is deliberately absent from this funnel:
        // FreeAIService.swift is not in the target's Sources build phase (it has
        // a PBXBuildFile, a PBXFileReference and a group entry, but no fourth
        // entry), so it is never compiled and none of its errors can reach a
        // student. Referencing it here would not build.

        if let ocr = error as? OCRService.OCRError {
            switch ocr {
            case .invalidImage: return Strings.errInvalidImage(ar)
            }
        }

        if let export = error as? SolutionPDFExporter.ExportError {
            switch export {
            case .nothingToExport:  return Strings.errExportNothing(ar)
            case .templateMissing:  return Strings.errExportTemplateMissing(ar)
            case .stagingFailed(let inner):
                return Strings.errExportPrepare(ar, detail: errorText(inner, ar))
            case .layoutFailed(let reason):
                // The reason is a value, not a sentence, so the phrase is
                // picked here in the app's language. `pageReported` carries a
                // raw JS exception string — developer copy in any language —
                // so it collapses onto the same "never finished" wording the
                // student can act on, and the raw text stays in
                // `ExportError.errorDescription` for logs.
                let phrase: String
                switch reason {
                case .neverFinished, .pageReported:
                    phrase = Strings.errExportNeverFinished(ar)
                case .noPages:
                    phrase = Strings.errExportNoPages(ar)
                case .emptySheet:
                    phrase = Strings.errExportEmptySheet(ar)
                }
                return Strings.errExportLayout(ar, detail: phrase)
            case .captureFailed(let inner):
                return Strings.errExportRender(ar, detail: errorText(inner, ar))
            case .writeFailed(let inner):
                return Strings.errExportSave(ar, detail: errorText(inner, ar))
            }
        }

        if let intake = error as? WorksheetIntake.IntakeError {
            switch intake {
            case .tooLarge:   return Strings.errFileTooLarge(ar)
            case .encrypted:  return Strings.errEncryptedPdf(ar)
            case .unreadable: return Strings.errUnreadableFile(ar)
            case .noText:     return Strings.errNoText(ar)
            }
        }

        // Foundation and URLSession errors: these ARE localized by the system,
        // and the `AppleLanguages` lock in `AppLocaleDefault` is what makes them
        // come back in Arabic rather than the device language.
        return error.localizedDescription
    }

    // MARK: - Library

    /// Makes a stored session the live one. Refuses while work is in flight:
    /// swapping `messages` mid-batch would post the in-flight answer into the
    /// wrong transcript and corrupt the positional question↔answer pairing the
    /// exporter depends on.
    @discardableResult
    func openSession(id: String) async -> Bool {
        guard !isBatchRunning, !isLoading, !isProcessingOCR else {
            intakeNotice = Strings.busyCannotOpen(isArabic)
            return false
        }

        // The outgoing session is already in the Library; flush it so nothing
        // typed in the last 400 ms is lost on the way out. When it is not dirty
        // there is nothing of its own to write — only whatever the store is
        // still holding — and writing anyway would re-date a session that was
        // merely read.
        if activeSessionId != nil, !messages.isEmpty || !sessionAttachments.isEmpty {
            if sessionDirty {
                persistSession(immediate: true)
            } else {
                library.flushPending()
            }
        }

        let loaded: LoadedLibrarySession
        do {
            loaded = try await library.loadSession(id: id)
        } catch {
            library.markDamaged(id)
            errorMessage = Strings.openFailed(isArabic)
            return false
        }

        messages = loaded.messages.map {
            AskDroobMessage(
                id: UUID(uuidString: $0.id) ?? UUID(),
                role: $0.isUser ? .user : .assistant,
                content: $0.text,
                timestamp: $0.at,
                provider: $0.provider)
        }
        activeSessionId = loaded.id
        sessionCreatedAt = loaded.createdAt
        sessionTitle = loaded.title
        sessionAttachments = loaded.attachments
        sessionScansEvicted = loaded.scansEvicted
        // Freshly loaded is by definition identical to what is on disk, so
        // reading it and leaving writes nothing and re-dates nothing.
        sessionDirty = false

        chatHistory = boundedHistory(
            messages.map {
                (role: $0.role == .user ? "user" : "assistant", content: $0.content)
            })

        inputText = ""
        ocrText = nil
        errorMessage = nil
        intakeNotice = nil
        failedQuestions = []
        showReview = false
        reviewQuestions = []
        pendingNotices = []
        intakeStage = .idle
        isLoading = false
        lastProviderUsed = messages.last { $0.role == .assistant }?.provider

        library.setLiveSession(loaded.id)
        library.markOpened(loaded.id)
        return true
    }

    /// The "Delete everything" path: the chat empties without being archived,
    /// because its files have already gone from disk.
    func resetAfterLibraryWipe() {
        batchTask?.cancel()
        batchTask = nil
        intakeStage = .idle
        messages.removeAll()
        chatHistory.removeAll()
        errorMessage = nil
        intakeNotice = nil
        failedQuestions = []
        showReview = false
        reviewQuestions = []
        pendingNotices = []
        clearUndo()
        activeSessionId = nil
        sessionAttachments = []
        sessionScansEvicted = false
        sessionTitle = ""
        sessionDirty = false
        lastProviderUsed = nil
        library.setLiveSession(nil)
    }

    // MARK: - Send Message

    func sendMessage() {
        // `messages` has one writer at a time or none. Two in flight interleave
        // question and answer bubbles, and both exporters pair them
        // positionally, so every later pair in the thread shifts by one.
        //
        // `isProcessingOCR` too: a photo read is now a network round trip, and a
        // send that beats it home goes out with `ocrText == nil` — the photo
        // silently dropped from the request, its "Scanned Text:" preview
        // appearing afterwards attached to nothing.
        guard !isLoading, !isBatchRunning, !isProcessingOCR else { return }

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || ocrText != nil else { return }

        let displayText = trimmed.isEmpty ? (ocrText ?? "") : trimmed

        let userMessage = AskDroobMessage(
            id: UUID(),
            role: .user,
            content: displayText,
            timestamp: Date()
        )
        messages.append(userMessage)
        chatHistory.append((role: "user", content: displayText))
        ensureSession()
        sessionDirty = true
        persistSession(immediate: false)

        inputText = ""
        let currentOCR = ocrText
        ocrText = nil

        isLoading = true
        errorMessage = nil

        let historyForAPI = chatHistory

        Task {
            do {
                let (response, providerName) = try await providerManager.sendMessage(
                    text: displayText,
                    ocrText: currentOCR,
                    history: boundedHistory(Array(historyForAPI.dropLast()))
                )

                let aiMessage = AskDroobMessage(
                    id: UUID(),
                    role: .assistant,
                    content: response,
                    timestamp: Date(),
                    provider: providerName
                )
                messages.append(aiMessage)
                chatHistory.append((role: "assistant", content: response))
                lastProviderUsed = providerName
                isLoading = false
                sessionDirty = true
                persistSession(immediate: true)

            } catch {
                errorMessage = Self.errorText(error, isArabic)
                isLoading = false
            }
        }
    }

    // MARK: - Photo Handling

    func processSelectedPhoto() {
        // One read at a time: the vision leg is a 3–6 s round trip, and two of
        // them race to write `ocrText` and `inputText`.
        guard let item = selectedPhotoItem, !isProcessingOCR else { return }

        isProcessingOCR = true

        Task {
            do {
                let data = try await item.loadTransferable(type: Data.self)
                guard let imageData = data, let uiImage = UIImage(data: imageData) else {
                    isProcessingOCR = false
                    return
                }

                await storePhoto(uiImage)

                // Vision model first, on-device OCR second — the same order the
                // worksheet pages use, and for the same reason: OCR flattens
                // maths notation and handwriting even where it reads the script.
                let extractedText: String
                if let read = await readPhotoWithVision(uiImage) {
                    extractedText = read
                } else {
                    extractedText = try await OCRService.extractText(from: uiImage)
                }

                applyPhotoRead(extractedText)

                isProcessingOCR = false
                selectedPhotoItem = nil

            } catch {
                errorMessage = Strings.imageProcessFailed(
                    isArabic, detail: Self.errorText(error, isArabic))
                isProcessingOCR = false
                selectedPhotoItem = nil
            }
        }
    }

    func processCapturedPhoto() {
        guard let image = capturedImage, !isProcessingOCR else { return }

        isProcessingOCR = true

        Task {
            do {
                await storePhoto(image)

                let extractedText: String
                if let read = await readPhotoWithVision(image) {
                    extractedText = read
                } else {
                    extractedText = try await OCRService.extractText(from: image)
                }

                applyPhotoRead(extractedText)

                isProcessingOCR = false
                capturedImage = nil

            } catch {
                errorMessage = Strings.imageProcessFailed(
                    isArabic, detail: Self.errorText(error, isArabic))
                isProcessingOCR = false
                capturedImage = nil
            }
        }
    }

    /// Keeps the photograph the student took with the session it belongs to.
    ///
    /// JPEG at 0.8 rather than the original bytes: an HEIC burst frame off a
    /// modern phone is several megabytes, the vision reader sees a JPEG anyway,
    /// and the Library budget is shared with everything else.
    private func storePhoto(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let name = Strings.photoFileName(isArabic)
        await storeAttachment(data: data, name: name, mime: "image/jpeg", isPDF: false)
    }

    /// Puts a finished photo read into the composer without stepping on the
    /// student.
    ///
    /// The canned prompt fills an *empty* composer only. Reading a photo is a
    /// network round trip now rather than sub-second on-device OCR, and typing
    /// while it is in flight is the natural thing to do; overwriting what they
    /// wrote with "What is the answer to this problem?" throws their own
    /// question away seconds after they typed it.
    private func applyPhotoRead(_ extractedText: String) {
        guard !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ocrText = nil
            errorMessage = Strings.noTextInImage(isArabic)
            return
        }
        ocrText = extractedText
        if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText = Strings.photoReadPrompt(isArabic)
        }
    }

    // MARK: - Worksheet Intake

    /// Entry point for the file button: a PDF or an image holding many
    /// questions, answered one at a time into the same chat thread the camera
    /// flow writes to — so the existing export walks a 40-question batch with
    /// no change at all.
    func handlePickedFile(_ picked: PickedAttachment) {
        // `isLoading` as well as `isBatchRunning`: an ordinary reply still in
        // flight behind a slow provider will land in the middle of the batch,
        // between a worksheet question and its answer. `exportableProblems`
        // pairs strictly positionally, so from that point every question in the
        // exported PDF sits above someone else's solution, silently.
        guard !isBatchRunning, !isLoading else { return }

        showFilePicker = false
        errorMessage = nil
        intakeNotice = nil
        failedQuestions = []

        // Size first, before anything touches the bytes: a 200 MB scan would
        // otherwise be decoded before we ever got to reject it.
        guard picked.data.count <= WorksheetIntake.maxFileBytes else {
            errorMessage = Strings.errFileTooLarge(isArabic)
            return
        }

        let data = picked.data
        let name = picked.filename.lowercased()
        let isPDF = picked.contentType == "application/pdf" || name.hasSuffix(".pdf")
        let isImage = picked.isImage || picked.contentType.hasPrefix("image/")
        let displayName = picked.filename
        let mime = picked.contentType.isEmpty
            ? (isPDF ? "application/pdf" : "image/jpeg")
            : picked.contentType

        // Claimed here, synchronously, and not on `runIntake`'s first line.
        // Storing the scan first is right, but it is a PDF parse plus a 20 MB
        // atomic write with two fsyncs — up to a second and a half on a device —
        // and for that whole window `intakeStage` used to stay `.idle`. That is
        // the one flag `isBatchRunning` is derived from, so the guards on
        // `sendMessage`, on both pickers and on `openSession` were all open
        // while the screen showed nothing at all: a student who typed a question
        // and tapped send got a chat request racing the batch, and
        // `exportableProblems` pairs strictly positionally, so from the first
        // interleaved pair every question in the exported PDF sits above another
        // question's solution.
        intakeStage = .reading

        batchTask = Task { [weak self] in
            // Stored first, read second: the file is the student's, and the
            // Library must hold what they scanned even if the read never
            // finishes.
            await self?.storeAttachment(
                data: data, name: displayName, mime: mime, isPDF: isPDF)
            await self?.runIntake(data: data, isPDF: isPDF, isImage: isImage)
        }
    }

    /// Stops the batch after the question in flight. Everything already
    /// answered stays in the thread and stays exportable — a student who
    /// stops at question twelve of forty still wants those twelve.
    func cancelBatch() {
        // By the time the review sheet is up the reading task has already
        // completed, so cancelling it would do nothing and the sheet would sit
        // there with Stop apparently dead.
        if showReview {
            cancelReview()
            return
        }
        batchTask?.cancel()
    }

    /// The screen is gone; whatever it started goes with it.
    ///
    /// `batchTask = Task { [weak self] in await self?.runBatch(q) }` does not
    /// let this object go: the optional chain unwraps into a *strong*
    /// reference that lives for the whole call, which for forty questions is
    /// three to four minutes of provider round trips. Nothing else cancels it
    /// — there is no `deinit` to reach, precisely because the task keeps the
    /// object alive — so a student who confirms a review and then swipes back
    /// out of Ask Droob AI would leave the batch running invisibly: burning
    /// free-tier quota through the whole fallback chain and appending answers
    /// to an orphaned transcript that re-entering the screen replaces with a
    /// fresh, empty one. Every answer produced after the pop is unreachable
    /// and unexportable, so it is work with no possible consumer.
    ///
    /// Covers the read path (`handlePickedFile`) and `retryFailedQuestions`
    /// too — same task, same shape.
    func stopWorkOnDisappear() {
        batchTask?.cancel()
        batchTask = nil
        undoTask?.cancel()
        undoTask = nil
        intakeStage = .idle
        // Whatever the debounce is still holding goes to disk now: the screen
        // is gone and the process may follow it. Reading a session is not a
        // change, though, so when nothing is dirty this flushes the store's
        // pending payload and writes nothing else — leaving an old session's
        // date, and its place in the newest-first list, alone.
        if sessionDirty {
            persistSession(immediate: true)
        } else {
            library.flushPending()
        }
    }

    /// Re-runs only the questions that failed. Clears the list first so a
    /// second round of failures repopulates it honestly rather than appending.
    func retryFailedQuestions() {
        guard !isBatchRunning, !isLoading, !failedQuestions.isEmpty else { return }

        let retrying = failedQuestions
        failedQuestions = []
        errorMessage = nil
        intakeNotice = nil

        batchTask = Task { [weak self] in
            await self?.runBatch(retrying)
        }
    }

    /// Picks the reader, then hands over to it.
    ///
    /// A vision-capable model reads the page image itself, which is the only way
    /// Arabic, handwriting, geometry figures and real mathematical notation
    /// survive the trip — and it transcribes and splits the page in one call, so
    /// the separate segmentation stage disappears with it. On-device OCR stays,
    /// demoted to the fallback for the pages vision could not read.
    private func runIntake(data: Data, isPDF: Bool, isImage: Bool) async {
        intakeStage = .reading

        guard isPDF || isImage else {
            intakeStage = .idle
            errorMessage = Strings.errUnreadableFile(isArabic)
            return
        }

        // The registry decides which reader runs, so it has to be loaded before
        // the decision rather than lazily inside the first provider call —
        // otherwise a cold start reads every worksheet with OCR.
        if providerManager.providers.isEmpty {
            await providerManager.fetchProviders()
        }

        if Task.isCancelled {
            finishCancelled()
            return
        }

        // V0: nothing in the chain can read an image. Today's path, unchanged.
        if providerManager.visionChain.isEmpty {
            await runIntakeWithOCR(data: data, isPDF: isPDF, extraNotices: [])
        } else {
            await runIntakeWithVision(data: data, isPDF: isPDF)
        }
    }

    /// The pre-vision pipeline, intact: extract the whole file to text, then one
    /// model call to split it into questions.
    ///
    /// Runs when no provider can read an image (V0), when the network went away
    /// mid-file, and as the whole-file retry when the vision reader claimed every
    /// page was empty (V4).
    private func runIntakeWithOCR(data: Data, isPDF: Bool, extraNotices: [String]) async {
        intakeStage = .reading

        let extraction: WorksheetIntake.Extraction
        do {
            if isPDF {
                extraction = try await WorksheetIntake.extract(pdfData: data)
            } else {
                guard let image = UIImage(data: data) else {
                    throw WorksheetIntake.IntakeError.unreadable
                }
                extraction = try await WorksheetIntake.extract(image: image)
            }
        } catch {
            intakeStage = .idle
            if Task.isCancelled {
                intakeNotice = Strings.cancelled(isArabic)
            } else {
                intakeNotice = extraNotices.isEmpty ? nil : extraNotices.joined(separator: "\n")
                errorMessage = intakeErrorText(error)
            }
            return
        }

        if Task.isCancelled {
            finishCancelled()
            return
        }

        var notices = extraNotices
        if extraction.pageCapHit { notices.append(Strings.pageCapReached(isArabic)) }

        intakeStage = .segmenting
        let segmentation = await providerManager.segmentQuestions(from: extraction.text)

        if Task.isCancelled {
            finishCancelled()
            return
        }

        await startBatch(
            questions: segmentation.questions,
            capHit: segmentation.capHit,
            notices: notices)
    }

    /// One page at a time: render it once, read it with a vision model, fall back
    /// to on-device OCR for exactly the pages that failed.
    ///
    /// Per page rather than per file because a batched call that 429s or
    /// truncates loses every page at once, ten pages of questions overrun any
    /// sane output budget, and holding ten base64 pages in memory is megabytes
    /// of `String` for no gain.
    private func runIntakeWithVision(data: Data, isPDF: Bool) async {
        var total = 1
        var pageCapHit = false
        var photo: UIImage?

        if isPDF {
            do {
                let count = try await WorksheetIntake.pageCount(pdfData: data)
                guard count > 0 else { throw WorksheetIntake.IntakeError.unreadable }
                total = min(count, WorksheetIntake.maxPages)
                pageCapHit = count > WorksheetIntake.maxPages
            } catch {
                intakeStage = .idle
                if Task.isCancelled {
                    intakeNotice = Strings.cancelled(isArabic)
                } else {
                    errorMessage = intakeErrorText(error)
                }
                return
            }
        } else {
            guard let image = UIImage(data: data) else {
                intakeStage = .idle
                errorMessage = Strings.errUnreadableFile(isArabic)
                return
            }
            photo = image
        }

        var slots: [PageSlot] = []
        var carry: String?
        var visionOn = true
        var pagesReadOnDevice = 0
        var readerUsed: String?
        var visionReadAnyPage = false

        for index in 0..<total {
            if Task.isCancelled {
                finishCancelled()
                return
            }

            let pageNumber = index + 1
            intakeStage = visionOn
                ? .readingPage(current: pageNumber, total: total)
                : .reading

            // One render per page, serving whichever reader ends up using it.
            // `base64` comes back nil when the page would not fit the byte cap
            // at any quality — the image is still there, so that page degrades
            // to OCR without being rendered a second time.
            var base64: String?
            var image: UIImage?
            // A born-digital page's own text layer, read once and reused by
            // whichever fallback ends up needing it. `nil` means "not looked at
            // yet"; `""` means "looked at, and there is nothing there".
            var nativeText: String?
            if let photo {
                image = photo
                if visionOn { base64 = await WorksheetIntake.jpegBase64(photo) }
            } else if visionOn {
                if let rendered = await WorksheetIntake.pageJPEGBase64(
                    pdfData: data, index: index) {
                    image = rendered.image
                    base64 = rendered.base64
                }
            } else {
                // Vision is off for the rest of the file: no reason to spend a
                // JPEG encode on this page, and no reason to hold it to the
                // vision clamp either. The text layer comes first — a
                // born-digital page needs no bitmap at all, so the render is
                // skipped outright when it carries real text.
                let native = await WorksheetIntake.pageText(pdfData: data, index: index)
                nativeText = native
                if native.count < WorksheetIntake.minPageTextChars {
                    image = await WorksheetIntake.pageImage(pdfData: data, index: index)
                }
            }

            if Task.isCancelled {
                finishCancelled()
                return
            }

            var pageQuestions: [String]?
            if visionOn, let base64 {
                switch await readPageWithVision(
                    base64: base64, page: pageNumber, total: total, carry: carry) {
                case .questions(let questions, let provider):
                    readerUsed = provider
                    visionReadAnyPage = true
                    pageQuestions = questions
                case .pageFailed:
                    // Per-response noise. The next page may read perfectly.
                    break
                case .visionExhausted:
                    // No network, or the whole chain is rate limited. Every
                    // remaining page would fail the same way, so stop asking.
                    visionOn = false
                }
            }

            if let pageQuestions {
                append(pageQuestions, to: &slots)
                carry = pageQuestions.last.map { String($0.prefix(carryChars)) }
            } else {
                carry = nil
                pagesReadOnDevice += 1
                // The same reader `extract(pdfData:)` is: text layer first, a
                // render through Vision only for the pages that have none, and
                // the longer of the two when the layer is thin. A worksheet
                // exported from Word has perfect Arabic and perfect notation
                // sitting in `page.string`; OCRing a bitmap of it instead
                // mangles ligatures and flattens stacked fractions on a file
                // the pre-vision pipeline read exactly.
                var text = ""
                if photo == nil {
                    if let nativeText {
                        text = nativeText
                    } else {
                        text = await WorksheetIntake.pageText(
                            pdfData: data, index: index)
                    }
                }
                if text.count < WorksheetIntake.minPageTextChars, let image {
                    let recognised = ((try? await OCRService.extractText(from: image)) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if recognised.count >= text.count { text = recognised }
                }
                if !text.isEmpty { slots.append(.ocrText(text)) }
            }

            if visionOn, index < total - 1 {
                try? await Task.sleep(nanoseconds: readPageDelayMs * 1_000_000)
            }
        }

        if Task.isCancelled {
            finishCancelled()
            return
        }

        // V4: every page read cleanly and every page came back empty. A model
        // claiming there is nothing in a file the student deliberately uploaded
        // is more likely to be the model failing than the file being blank, so
        // read the whole thing on-device once before believing it.
        let visionQuestions = slots.reduce(into: 0) { count, slot in
            if case .questions(let questions) = slot { count += questions.count }
        }
        if visionReadAnyPage, pagesReadOnDevice == 0, visionQuestions == 0 {
            await runIntakeWithOCR(
                data: data,
                isPDF: isPDF,
                extraNotices: [Strings.readerFellBackToDevice(
                    isArabic, pages: total, total: total)])
            return
        }

        var notices: [String] = []
        if pageCapHit { notices.append(Strings.pageCapReached(isArabic)) }
        // Only when the reader is not the provider the student picked: a student
        // who chose "Groq (Fastest)" and sees a slower read deserves the reason.
        if let readerUsed, readerUsed != selectedProvider?.displayName {
            notices.append(Strings.readerNotice(isArabic, provider: readerUsed))
        }
        if pagesReadOnDevice > 0 {
            notices.append(Strings.readerFellBackToDevice(
                isArabic, pages: pagesReadOnDevice, total: total))
        }

        // The pages that fell back to on-device reading still need splitting,
        // and their questions belong at that page's position rather than at the
        // end — so the run is broken only where a vision-read page sits between
        // them, never per page.
        let needsSegmentation = slots.contains {
            if case .ocrText = $0 { return true }
            return false
        }
        if needsSegmentation { intakeStage = .segmenting }

        // Consecutive OCR'd pages are segmented *together*, in one call. The
        // splitter's job is identical whether the text came from one page or
        // ten, and one call per page turns the common whole-file fallback —
        // vision latched off on page 1, so every page is on-device — into ten
        // full sweeps of the five-provider chain: ten times the wait on a
        // timing-out network, ten times the ~2,200-token prompt against the
        // daily Gemini ceiling, and a split that cannot join a question running
        // over a page break because it never sees both halves at once.
        var questions: [String] = []
        var pendingOCR: [String] = []

        for slot in slots {
            if Task.isCancelled {
                finishCancelled()
                return
            }
            switch slot {
            case .questions(let pageQuestions):
                if !pendingOCR.isEmpty {
                    questions.append(contentsOf: await providerManager
                        .segmentQuestions(from: pendingOCR.joined(separator: "\n\n"))
                        .questions)
                    pendingOCR = []
                    if Task.isCancelled {
                        finishCancelled()
                        return
                    }
                }
                questions.append(contentsOf: pageQuestions)
            case .ocrText(let text):
                pendingOCR.append(text)
            }
        }
        if !pendingOCR.isEmpty {
            questions.append(contentsOf: await providerManager
                .segmentQuestions(from: pendingOCR.joined(separator: "\n\n"))
                .questions)
        }

        if Task.isCancelled {
            finishCancelled()
            return
        }

        guard !questions.isEmpty else {
            intakeStage = .idle
            intakeNotice = notices.isEmpty ? nil : notices.joined(separator: "\n")
            errorMessage = slots.isEmpty
                ? Strings.errNoText(isArabic)
                : Strings.errNoQuestions(isArabic)
            return
        }

        let capHit = questions.count > WorksheetIntake.maxQuestions
        if capHit { questions = Array(questions.prefix(WorksheetIntake.maxQuestions)) }

        await startBatch(questions: questions, capHit: capHit, notices: notices)
    }

    /// What one page contributed, kept in page order so an OCR page's questions
    /// land where that page sat rather than at the end of the sheet.
    private enum PageSlot {
        case questions([String])
        case ocrText(String)
    }

    /// Appends a page's questions, merging a question that ran over the page
    /// break into one.
    ///
    /// The model is asked to repeat the carried text verbatim, so the match is a
    /// plain prefix comparison. If it ignores the instruction nothing matches,
    /// nothing is dropped, and the student gets two partial questions — which is
    /// what the old single-segmentation path produced at the page cap boundary
    /// anyway. Never worse.
    private func append(_ questions: [String], to slots: inout [PageSlot]) {
        defer { slots.append(.questions(questions)) }

        guard
            let first = questions.first?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            case .questions(let previous)? = slots.last,
            let last = previous.last?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return }

        let key = String(last.prefix(carryKeyChars))
        guard key.count >= minCarryKeyChars, first.hasPrefix(key) else { return }
        slots[slots.count - 1] = .questions(Array(previous.dropLast()))
    }

    /// How far a page read got.
    private enum PageReadOutcome {
        case questions([String], provider: String)
        /// This page could not be read. The next one still might be.
        case pageFailed
        /// The reader is gone for the rest of this file.
        case visionExhausted
    }

    private func readPageWithVision(
        base64: String,
        page: Int,
        total: Int,
        carry: String?
    ) async -> PageReadOutcome {
        let userText = Self.pageMarker(page: page, total: total, carry: carry)

        do {
            let read = try await providerManager.readPage(
                imageBase64: base64, userText: userText)
            if let questions = read.questions {
                return .questions(questions, provider: read.providerUsed)
            }
        } catch {
            // A 200 carrying no usable content is the same situation as a reply
            // that is not a JSON array — the request was fine, the reply was
            // not — so it earns the same single retry rather than dropping
            // straight to OCR.
            guard Self.classifyReadFailure(error) == .emptyReply else {
                return await handleReadFailure(error, base64: base64, userText: userText)
            }
        }

        // V3: a 200 whose body is not a JSON array, even after the escape
        // repair. Retry the page once with the format restated — a badly
        // formatted reply is per-response noise, and latching on it would throw
        // away nine good pages because of one.
        if Task.isCancelled { return .pageFailed }
        let retryText = userText + "\n\n" + Self.notAnArrayRetry
        do {
            let read = try await providerManager.readPage(
                imageBase64: base64, userText: retryText)
            if let questions = read.questions {
                return .questions(questions, provider: read.providerUsed)
            }
            return .pageFailed
        } catch {
            return await handleReadFailure(error, base64: base64, userText: retryText)
        }
    }

    private func handleReadFailure(
        _ error: Error,
        base64: String,
        userText: String
    ) async -> PageReadOutcome {
        switch Self.classifyReadFailure(error) {
        case .offline, .noReader:
            // V1/V0: every remaining provider and every remaining page fails
            // the same way. Read the rest on-device instead of spending 2 s and
            // a round trip per page discovering that ten times over.
            return .visionExhausted

        case .rateLimited:
            // V2: sweep the chain once more after a pause. A per-minute window
            // is outlived by three seconds and is worth one retry; two full
            // sweeps of 429 means the minute's or the day's allowance is gone,
            // and nine more pages will not change that.
            try? await Task.sleep(nanoseconds: retryDelayMs * 1_000_000)
            if Task.isCancelled { return .pageFailed }
            do {
                let read = try await providerManager.readPage(
                    imageBase64: base64, userText: userText)
                if let questions = read.questions {
                    return .questions(questions, provider: read.providerUsed)
                }
                return .pageFailed
            } catch {
                return .visionExhausted
            }

        case .emptyReply, .other:
            // Whatever went wrong is about this reply, not the chain. OCR this
            // page and keep reading the next one.
            return .pageFailed
        }
    }

    private enum ReadFailure: Equatable {
        case offline
        case rateLimited
        case noReader
        /// A 200 with nothing usable in it — treated as an unparseable reply.
        case emptyReply
        case other
    }

    private static func classifyReadFailure(_ error: Error) -> ReadFailure {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .timedOut, .cannotFindHost:
                return .offline
            default:
                return .other
            }
        }
        if let aiError = error as? AIProviderManager.AIError {
            switch aiError {
            case .rateLimited:
                return .rateLimited
            case .noVisionProvider, .noProvidersAvailable:
                return .noReader
            case .networkError:
                return .offline
            case .emptyResponse:
                return .emptyReply
            default:
                return .other
            }
        }
        return .other
    }

    /// The user turn that rides with the page image: which page this is, and —
    /// when the previous page ended mid-question — enough of that question for
    /// the model to finish it here instead of starting a new one.
    ///
    /// Plain ASCII with Western digits in both languages: it is an instruction
    /// to the model, not something the student ever sees.
    private static func pageMarker(page: Int, total: Int, carry: String?) -> String {
        var text = "PAGE \(page) OF \(total)."
        guard let carry, !carry.isEmpty else { return text }
        text += """


        CONTINUED FROM THE PREVIOUS PAGE:
        <<<
        \(carry)
        >>>
        If the first question on this page is the rest of that text, make your first element
        the whole question: the text above repeated word for word, then its continuation from
        this page. Otherwise ignore the block above completely.
        """
        return text
    }

    private static let notAnArrayRetry =
        "Your last reply was not a JSON array. Reply with the JSON array only, nothing else."

    /// Reads one photograph with the same vision reader the worksheet pages use,
    /// so an Arabic problem photographed on a phone is transcribed rather than
    /// dropped. `nil` means "use on-device OCR" — no reader, no encodable image,
    /// a failed call, or a page the model found nothing in.
    private func readPhotoWithVision(_ image: UIImage) async -> String? {
        if providerManager.providers.isEmpty {
            await providerManager.fetchProviders()
        }
        guard !providerManager.visionChain.isEmpty else { return nil }
        guard let base64 = await WorksheetIntake.jpegBase64(image) else { return nil }

        let read = try? await providerManager.readPage(
            imageBase64: base64,
            userText: Self.pageMarker(page: 1, total: 1, carry: nil))
        guard let questions = read?.questions, !questions.isEmpty else { return nil }
        // Straight into the existing `ocrText` state: the chat prompt builder,
        // the send path and the export are all untouched by this.
        return questions.joined(separator: "\n\n")
    }

    private func finishCancelled() {
        intakeStage = .idle
        intakeNotice = Strings.cancelled(isArabic)
    }

    /// The last common step of every reading path: announce what was found, then
    /// hand it to the student to check.
    ///
    /// This used to call `runBatch` straight through. It now stops here and
    /// publishes the review; `confirmReview()` does what this tail used to do.
    /// Nothing downstream changed — the 1200 ms spacing, the frozen bounded
    /// history, the single chain retry, the positional question/answer pairing
    /// both exporters depend on — only *which strings* reach it.
    private func startBatch(questions: [String], capHit: Bool, notices: [String]) async {
        var notices = notices

        guard !questions.isEmpty else {
            intakeStage = .idle
            intakeNotice = notices.isEmpty ? nil : notices.joined(separator: "\n")
            errorMessage = Strings.errNoQuestions(isArabic)
            return
        }

        if capHit { notices.append(Strings.questionCapReached(isArabic)) }

        pendingNotices = notices
        reviewQuestions = questions.map { ReviewQuestion(text: $0) }
        reviewUndo = nil
        // Held on the stage, not a bare boolean: `isBatchRunning` is derived
        // from `intakeStage != .idle`, and that one derivation already blocks
        // `sendMessage`, disables both pickers, and turns Send into Stop. All
        // three are right while the sheet is up — including Stop, which here
        // means "abandon this upload".
        intakeStage = .reviewing
        showReview = true
        // The reading task is finished; nothing else is awaited on this path.
        batchTask = nil
    }

    // MARK: - Review

    /// Answers the list the student approved. Everything from here down is the
    /// unmodified batch path.
    /// Approving the sheet is where the repaired question is FIXED, not merely
    /// where it is shown.
    ///
    /// `reviewMarkdown` is what makes an extracted question renderable — bare
    /// LaTeX delimited, a whole-question span unwrapped, Arabic-Indic digits
    /// inside a formula turned Latin, one option per line — and the review card
    /// was the only surface applying it. So the student approved a typeset card
    /// and then watched the raw scan reappear in their own chat bubble and in the
    /// exported A4 sheet, options run together on one line, `\frac` printed as
    /// source. Normalised ONCE, here, so the string in `messages`, the string in
    /// `chatHistory` and the string `exportableProblems` hands the exporter are
    /// the same characters the card rendered. Every consumer downstream is a
    /// markdown surface: `MathMarkdownView` in the bubble, `richText` in
    /// `print.html`, and the plain-`Text` branch strips the one markdown-only
    /// artefact with `reviewPlainText`.
    func confirmReview() {
        guard showReview else { return }

        let questions = reviewQuestions
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(reviewMarkdown)

        showReview = false
        reviewQuestions = []
        clearUndo()

        guard !questions.isEmpty else {
            intakeStage = .idle
            intakeNotice = Strings.reviewEmptied(isArabic)
            pendingNotices = []
            return
        }

        var notices = pendingNotices
        notices.append(Strings.batchStarted(isArabic, count: questions.count))
        intakeNotice = notices.joined(separator: "\n")
        pendingNotices = []

        batchTask = Task { [weak self] in
            await self?.runBatch(questions)
        }
    }

    /// Discards the extracted list and nothing else: the chat, the history and
    /// every previously exported answer are untouched, exactly as `cancelBatch`
    /// already promises.
    func cancelReview() {
        guard showReview else { return }
        let emptied = reviewQuestions.allSatisfy {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        showReview = false
        reviewQuestions = []
        pendingNotices = []
        clearUndo()
        intakeStage = .idle
        // "You deleted them all" and "you pressed cancel" are different events
        // and the student should be told which one happened.
        intakeNotice = emptied
            ? Strings.reviewEmptied(isArabic)
            : Strings.reviewCancelled(isArabic)
    }

    func updateReviewQuestion(id: UUID, text: String) {
        guard let index = reviewQuestions.firstIndex(where: { $0.id == id }) else { return }
        // An emptied question is a deletion, with the same undo behind it.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deleteReviewQuestion(id: id)
            return
        }
        reviewQuestions[index].text = text
    }

    func deleteReviewQuestion(id: UUID) {
        guard let index = reviewQuestions.firstIndex(where: { $0.id == id }) else { return }
        let removed = reviewQuestions.remove(at: index)
        reviewUndo = DeletedReviewQuestion(index: index, question: removed)

        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.reviewUndo = nil }
        }
    }

    /// Puts the row back where it was, not on the end — the student is undoing a
    /// mistake, not appending a question.
    func undoReviewDelete() {
        guard let undo = reviewUndo else { return }
        let index = min(undo.index, reviewQuestions.count)
        reviewQuestions.insert(undo.question, at: index)
        clearUndo()
    }

    /// A scan that "adds wrong things" is the same scan that drops a question,
    /// so the review step has to cut both ways.
    @discardableResult
    func addReviewQuestion() -> ReviewQuestion {
        let question = ReviewQuestion(text: "")
        reviewQuestions.append(question)
        return question
    }

    private func clearUndo() {
        undoTask?.cancel()
        undoTask = nil
        reviewUndo = nil
    }

    /// Answers each question in turn, spaced out, against a frozen history.
    ///
    /// The history handed to the provider is the transcript as it stood
    /// *before* the batch, identical for every question in it, and windowed.
    /// Worksheet questions are independent, and letting the transcript grow
    /// would blow the token budget by question ten and make question thirty
    /// cost twenty times question one. Freezing alone is not enough: a second
    /// worksheet in the same session, or a retry run after a 40-question batch,
    /// would freeze a snapshot that already holds 80 turns — so the snapshot is
    /// bounded too. The messages are still appended to `messages` and
    /// `chatHistory`, so the thread reads normally and the exporter sees
    /// everything — only the value passed as `history` is frozen and trimmed.
    private func runBatch(_ questions: [String]) async {
        guard !questions.isEmpty else { return }

        let historyBeforeBatch = boundedHistory(chatHistory)
        var failures: [String] = []
        var answeredCount = 0
        var consecutiveFailures = 0

        for (index, question) in questions.enumerated() {
            if Task.isCancelled { break }

            intakeStage = .answering(current: index + 1, total: questions.count)

            messages.append(AskDroobMessage(
                id: UUID(), role: .user, content: question, timestamp: Date()))
            chatHistory.append((role: "user", content: question))
            ensureSession()
            sessionDirty = true
            persistSession(immediate: false)

            var answer = await ask(question, history: historyBeforeBatch)
            if Task.isCancelled { break }

            if answer == nil {
                // One retry of the whole chain. A 429 is usually a per-minute
                // window that a three-second pause outlives.
                try? await Task.sleep(nanoseconds: retryDelayMs * 1_000_000)
                if Task.isCancelled { break }
                answer = await ask(question, history: historyBeforeBatch)
                if Task.isCancelled { break }
            }

            if let answer {
                messages.append(AskDroobMessage(
                    id: UUID(), role: .assistant, content: answer.response,
                    timestamp: Date(), provider: answer.providerUsed))
                chatHistory.append((role: "assistant", content: answer.response))
                lastProviderUsed = answer.providerUsed
                answeredCount += 1
                consecutiveFailures = 0
                // Before the next network call starts, so a batch killed at
                // question 31 restores with 30 questions and 30 answers.
                sessionDirty = true
                persistSession(immediate: true)
            } else {
                // No assistant message on purpose. Both exporters pair
                // questions to answers positionally, so a user turn with
                // nothing after it is skipped — which is exactly right. A
                // failure string written here would be exported as if it were
                // a solution.
                failures.append(question)
                consecutiveFailures += 1

                // Offline, or the day's free tier is gone: every remaining
                // question would fail the same way after ~4.2 s of sleeping.
                // Stop and say so now. The untried questions join the failed
                // list, so the retry button picks up the whole remainder once
                // the student has signal again.
                if consecutiveFailures >= maxConsecutiveFailures {
                    let remaining = questions.count - (index + 1)
                    if remaining > 0 {
                        failures.append(contentsOf: questions.suffix(remaining))
                    }
                    break
                }
            }

            if index < questions.count - 1 {
                try? await Task.sleep(nanoseconds: interQuestionDelayMs * 1_000_000)
            }
        }

        let wasCancelled = Task.isCancelled
        intakeStage = .idle
        batchTask = nil
        failedQuestions = failures

        if wasCancelled {
            intakeNotice = Strings.cancelled(isArabic)
        } else if !failures.isEmpty {
            errorMessage = answeredCount == 0
                ? Strings.errAllProvidersFailed(isArabic)
                : Strings.batchPartialFailure(isArabic, failed: failures.count, total: questions.count)
        }
    }

    private func ask(
        _ question: String,
        history: [(role: String, content: String)]
    ) async -> (response: String, providerUsed: String)? {
        do {
            return try await providerManager.sendMessage(
                text: question, ocrText: nil, history: history)
        } catch {
            return nil
        }
    }

    private func intakeErrorText(_ error: Error) -> String {
        guard let intake = error as? WorksheetIntake.IntakeError else {
            return Strings.errUnreadableFile(isArabic)
        }
        switch intake {
        case .tooLarge:   return Strings.errFileTooLarge(isArabic)
        case .encrypted:  return Strings.errEncryptedPdf(isArabic)
        case .unreadable: return Strings.errUnreadableFile(isArabic)
        case .noText:     return Strings.errNoText(isArabic)
        }
    }

    // MARK: - New Chat
    //
    // Same name, both call sites unchanged, new meaning: this used to destroy
    // the thread. It now archives it to the Library, so clearing is not data
    // loss — deleting from the Library is the destructive path, and it has a
    // confirmation. No confirmation here, because a confirmation on a
    // non-destructive action teaches students to dismiss confirmations.

    func clearChat() {
        guard !isArchiving else { return }
        batchTask?.cancel()
        batchTask = nil
        intakeStage = .idle

        guard let archivedId = activeSessionId else {
            finishClear(archived: false)
            return
        }

        guard !messages.isEmpty || !sessionAttachments.isEmpty else {
            // Created but never used. A "New chat" tap on an empty chat must
            // not leave a row behind.
            library.discardIfEmpty(id: archivedId)
            finishClear(archived: false)
            return
        }

        // The one place in the feature that throws the conversation away on the
        // strength of a write, so it is the one place that waits to hear the
        // write landed. `persist` swallows failures by design — the transcript
        // stays in memory and the next message retries — but here there is no
        // next message and no in-memory copy afterwards, so a full disk used to
        // mean forty questions destroyed under the words "Saved to your
        // library."
        //
        // It runs even when nothing is dirty, because "handed to the store" is
        // not "on the disk" — a coalesced user message may still be inside the
        // 400 ms window. `touch` carries the distinction that matters instead:
        // an unchanged session is rewritten byte for byte without being
        // re-dated, so reading an old thread and tapping New chat leaves its
        // place in the newest-first list alone.
        let payload = currentPayload(id: archivedId)
        let changed = sessionDirty
        isArchiving = true
        Task {
            let saved = await library.archive(payload, touch: changed)
            isArchiving = false
            guard saved else {
                // Nothing is cleared. An archive that failed must not also be a
                // deletion, and the student can free space and try again — or
                // export the thread, which is still right there.
                errorMessage = Strings.archiveFailed(isArabic)
                return
            }
            sessionDirty = false
            finishClear(archived: true)
        }
    }

    /// Empties the screen once the transcript is safely somewhere else.
    private func finishClear(archived: Bool) {
        messages.removeAll()
        chatHistory.removeAll()
        errorMessage = nil
        failedQuestions = []
        // A review still on screen belongs to an upload that is being thrown
        // away with the thread; leaving it would confirm questions into an
        // emptied chat.
        showReview = false
        reviewQuestions = []
        pendingNotices = []
        clearUndo()

        activeSessionId = nil
        sessionAttachments = []
        sessionScansEvicted = false
        sessionTitle = ""
        sessionDirty = false
        lastProviderUsed = nil
        library.setLiveSession(nil)

        intakeNotice = archived ? Strings.savedToLibrary(isArabic) : nil
    }

    // MARK: - PDF Export

    /// Every answered question in the thread, oldest first.
    ///
    /// Pairing is positional rather than by id because the message model holds
    /// no link between a question and its answer; the transcript is strictly
    /// alternating, so an assistant turn always answers the user turn above it.
    var exportableProblems: [SolutionPDFExporter.Problem] {
        var problems: [SolutionPDFExporter.Problem] = []
        var pendingQuestion: String?

        for message in messages {
            switch message.role {
            case .user:
                pendingQuestion = message.content
            case .assistant:
                problems.append(
                    SolutionPDFExporter.Problem(
                        question: pendingQuestion ?? "",
                        answer: message.content))
                pendingQuestion = nil
            }
        }
        return problems
    }

    var canExportPDF: Bool { !exportableProblems.isEmpty }

    func exportThreadAsPDF(locale: String) {
        exportPDF(
            problems: exportableProblems,
            title: locale == "ar" ? "حلول اسأل دروب" : "Ask Droob AI Solutions",
            locale: locale,
            kind: .session)
    }

    /// Exports a single answer together with the question that prompted it — a
    /// solution sheet with no problem statement on it is not worth printing.
    ///
    /// `.singleAnswer`, so it is share-only. It used to go through the same
    /// registration as the whole-thread export, whose "at most one PDF per
    /// session" cleanup deletes every other file in the session's export
    /// directory — so saving one answer silently destroyed the forty-question
    /// sheet the student had exported an hour earlier, while the row kept its
    /// PDF badge and "Share PDF" quietly started handing the teacher a
    /// one-problem sheet.
    func exportAnswerAsPDF(_ message: AskDroobMessage, locale: String) {
        guard
            message.role == .assistant,
            let index = messages.firstIndex(where: { $0.id == message.id })
        else { return }

        let question = messages[..<index].last { $0.role == .user }?.content ?? ""
        exportPDF(
            problems: [
                SolutionPDFExporter.Problem(question: question, answer: message.content)
            ],
            title: locale == "ar" ? "حل مسألة" : "Solved Problem",
            locale: locale,
            kind: .singleAnswer)
    }

    /// One export at a time: each one spins up its own web view, and a student
    /// tapping the toolbar twice would otherwise render the thread twice over.
    private func exportPDF(
        problems: [SolutionPDFExporter.Problem],
        title: String,
        locale: String,
        kind: LibraryExportKind
    ) {
        guard !problems.isEmpty, !isExporting else { return }
        let sessionId = ensureSession()
        isExporting = true
        errorMessage = nil

        Task {
            do {
                // The sheet is written into the session's own `exports/`
                // directory, so it survives a relaunch and can be re-shared
                // without being regenerated.
                let url = try await SolutionPDFExporter.export(
                    problems: problems, title: title, locale: locale,
                    sessionId: sessionId, kind: kind)
                exportedPDF = ExportedPDF(url: url)
                persistSession(immediate: true)
            } catch {
                errorMessage = Self.errorText(error, isArabic)
            }
            isExporting = false
        }
    }

    // MARK: - The single export slot
    //
    // `isExporting` is the whole of it: one WKWebView driving KaTeX at a time.
    // The Library's re-export is a second entry point into the same renderer
    // and into the same session's `exports/` directory, so it claims the same
    // flag rather than a `@State` of its own — otherwise two runs target one
    // session, and whichever finishes second unlinks the file the first one's
    // share sheet is already holding.

    /// Claims the export slot for a caller outside this view model. `false`
    /// when one is already running.
    func beginExternalExport() -> Bool {
        guard !isExporting else { return false }
        isExporting = true
        return true
    }

    func endExternalExport() {
        isExporting = false
    }

    // MARK: - Quick Actions

    struct QuickAction: Identifiable {
        /// The icon name, not a fresh `UUID()`. `quickActions` is computed now,
        /// so a per-instance UUID would hand `ForEach` four brand-new
        /// identities on every render and rebuild the rows each time.
        var id: String { icon }
        let icon: String
        let titleAr: String
        let titleEn: String
        let prompt: String
    }

    /// Computed, not a stored `let`: the `prompt` is written straight into the
    /// visible composer and then sent verbatim to the model, so it has to
    /// follow the app locale on both counts. As a constant it was English in
    /// every locale — the student saw English in their own composer, and the
    /// model was asked, in English, for an English answer.
    var quickActions: [QuickAction] {
        let ar = isArabic
        return [
            QuickAction(
                icon: "function",
                titleAr: "حل مسألة رياضيات", titleEn: "Solve Math Problem",
                prompt: Strings.promptSolveMath(ar)),
            QuickAction(
                icon: "atom",
                titleAr: "شرح فيزياء", titleEn: "Explain Physics",
                prompt: Strings.promptExplainPhysics(ar)),
            QuickAction(
                icon: "text.book.closed",
                titleAr: "مراجعة درس", titleEn: "Review Lesson",
                prompt: Strings.promptReviewLesson(ar)),
            QuickAction(
                icon: "questionmark.circle",
                titleAr: "اسأل أي سؤال", titleEn: "Ask Any Question",
                prompt: "")
        ]
    }
}

// MARK: - Worksheet Intake Stage

/// Where a multi-question file has got to. `.idle` doubles as "no batch is
/// running", which is what gates the file button and turns the send button
/// into a stop button.
enum IntakeStage: Equatable {
    case idle
    /// Opening the file and counting its pages, and the whole on-device reading
    /// path — PDFKit text layer, or Vision per page.
    case reading
    /// A vision model is reading page `current` of `total`. Its own case because
    /// the vision path takes ~65–80 s on a ten-page PDF against ~15–30 s for
    /// OCR, and a flat "Reading your file…" sitting there for over a minute
    /// reads as a hang.
    case readingPage(current: Int, total: Int)
    /// The one model call that splits extracted text into separate questions.
    /// Never entered on the vision path — reading and splitting are one call
    /// there — but still the stage for every on-device fallback.
    case segmenting
    /// Extracted, not yet answered: the review sheet is up and the student is
    /// checking what the scan produced. A stage rather than a bare boolean
    /// because `isBatchRunning` — derived from `intakeStage != .idle` — already
    /// blocks `sendMessage`, disables both pickers and turns Send into Stop, and
    /// all three are exactly right while the sheet is open.
    case reviewing
    case answering(current: Int, total: Int)
}

// MARK: - Bilingual strings for the intake flow

extension AskDroobAIViewModel {

    /// Bilingual ternaries at the point of use, matching what this screen
    /// already does everywhere else. Deliberately *not* `strings.xml`/`L10n`:
    /// Ask Droob AI does not use the table today, and half-migrating one
    /// feature mid-change guarantees the two halves drift.
    enum Strings {
        static func stageReading(_ ar: Bool) -> String {
            ar ? "جارٍ قراءة الملف..." : "Reading your file..."
        }
        /// The single-photo path. Its own line rather than `stageReading`
        /// because `intakeStage` stays `.idle` there — a photo is not a batch,
        /// and borrowing the batch stage would turn the send button into a stop
        /// button with nothing to stop.
        static func readingImage(_ ar: Bool) -> String {
            ar ? "جارٍ قراءة الصورة..." : "Reading the image..."
        }
        static func stageReadingPage(_ ar: Bool, current: Int, total: Int) -> String {
            ar ? "جارٍ قراءة الصفحة \(current) من \(total)"
               : "Reading page \(current) of \(total)"
        }
        /// Shown only when the page reader is not the provider the student
        /// picked for chat. Their choice still drives every answer; it just does
        /// not decide whether an Arabic worksheet can be read at all.
        static func readerNotice(_ ar: Bool, provider: String) -> String {
            ar ? "تمت قراءة الصفحات بواسطة \(provider)."
               : "Pages were read by \(provider)."
        }
        /// A notice, never the error line: the pages were read, just less well.
        static func readerFellBackToDevice(_ ar: Bool, pages: Int, total: Int) -> String {
            ar ? "تمت قراءة \(pages) من \(total) صفحات على هذا الجهاز بدلاً من القارئ الذكي، وقد تكون الدقة أقل."
               : "\(pages) of \(total) pages were read on this device instead of the AI reader, so accuracy may be lower."
        }
        static func stageSegmenting(_ ar: Bool) -> String {
            ar ? "جارٍ البحث عن الأسئلة..." : "Finding the questions..."
        }
        static func stageAnswering(_ ar: Bool, current: Int, total: Int) -> String {
            ar ? "الإجابة عن السؤال \(current) من \(total)"
               : "Answering question \(current) of \(total)"
        }
        static func batchStarted(_ ar: Bool, count: Int) -> String {
            ar ? "تم العثور على \(count) سؤالاً في ملفك"
               : "Found \(count) questions in your file"
        }
        static func filePickerButton(_ ar: Bool) -> String {
            ar ? "إرفاق ملف أو صورة بها أسئلة" : "Upload a file with questions"
        }
        static func cancelButton(_ ar: Bool) -> String {
            ar ? "إيقاف الحل" : "Stop answering"
        }
        static func cancelled(_ ar: Bool) -> String {
            ar ? "تم الإيقاف. تم حفظ كل ما تمت الإجابة عنه."
               : "Stopped. Everything answered so far is kept."
        }
        static func pageCapReached(_ ar: Bool) -> String {
            ar ? "الملف أطول من 10 صفحات. تمت قراءة أول 10 صفحات فقط."
               : "This file is longer than 10 pages. Only the first 10 pages were read."
        }
        static func questionCapReached(_ ar: Bool) -> String {
            ar ? "تم العثور على أكثر من 40 سؤالاً. سيتم حل أول 40 سؤالاً."
               : "More than 40 questions were found. The first 40 will be answered."
        }
        static func errFileTooLarge(_ ar: Bool) -> String {
            ar ? "حجم الملف أكبر من 20 ميجابايت. جرّب ملفاً أصغر."
               : "This file is larger than 20 MB. Try a smaller one."
        }
        static func errEncryptedPdf(_ ar: Bool) -> String {
            ar ? "هذا الملف محمي بكلمة مرور ولا يمكن فتحه."
               : "This PDF is password-protected and cannot be opened."
        }
        static func errUnreadableFile(_ ar: Bool) -> String {
            ar ? "تعذّر فتح هذا الملف. تأكد أنه ملف PDF أو صورة سليمة."
               : "This file could not be opened. Make sure it is a valid PDF or image."
        }
        static func errNoText(_ ar: Bool) -> String {
            ar ? "لم يتم العثور على نص في هذا الملف. جرّب صورة أوضح."
               : "No text was found in this file. Try a clearer scan."
        }
        static func errNoQuestions(_ ar: Bool) -> String {
            ar ? "لم يتم العثور على أسئلة في هذا الملف."
               : "No questions were found in this file."
        }
        static func errAllProvidersFailed(_ ar: Bool) -> String {
            ar ? "تعذّر الوصول إلى خدمة الذكاء الاصطناعي. حاول بعد قليل."
               : "Could not reach the AI service. Try again in a moment."
        }
        static func batchPartialFailure(_ ar: Bool, failed: Int, total: Int) -> String {
            ar ? "تعذّر حل \(failed) من \(total) سؤالاً."
               : "\(failed) of \(total) questions could not be answered."
        }
        static func retryUnanswered(_ ar: Bool) -> String {
            ar ? "إعادة محاولة الأسئلة غير المحلولة" : "Retry unanswered questions"
        }

        // MARK: Maths keyboard

        static func mathKeyboard(_ ar: Bool) -> String {
            ar ? "لوحة الرياضيات" : "Math keyboard"
        }
        static func mathSheetTitle(_ ar: Bool) -> String {
            ar ? "اكتب معادلة" : "Write a formula"
        }
        static func mathAddToMessage(_ ar: Bool) -> String {
            ar ? "إضافة إلى الرسالة" : "Add to message"
        }
        static func mathInsertFormula(_ ar: Bool) -> String {
            ar ? "إدراج معادلة" : "Insert formula"
        }
        /// The maths keyboard is an input mode, never a gate: when the WebView
        /// will not load the student still types, in a plain text editor.
        static func mathUnavailable(_ ar: Bool) -> String {
            ar ? "تعذّر تحميل لوحة الرياضيات. اكتب سؤالك نصاً."
               : "The maths keyboard could not load. Type your question as text."
        }
        /// Fallback substitute for the page's own Solve key, which lives inside
        /// the WebView and is gone with it.
        static func mathSolve(_ ar: Bool) -> String {
            ar ? "حل" : "Solve"
        }
        /// Word for word what mathfield.html puts under its own field when
        /// `unfilled()` is true — the native footer states the same rule, so it
        /// must not word it differently.
        static func mathFillBoxes(_ ar: Bool) -> String {
            ar ? "أكمل الفراغات في المعادلة أولاً" : "Fill in the empty boxes first"
        }

        // MARK: Review step

        static func close(_ ar: Bool) -> String {
            ar ? "إغلاق" : "Close"
        }
        static func reviewTitle(_ ar: Bool) -> String {
            ar ? "راجع أسئلتك" : "Check your questions"
        }
        static func reviewSubtitle(_ ar: Bool) -> String {
            ar ? "صحّح ما أخطأ فيه المسح قبل أن يجيب درووب."
               : "Fix anything the scan got wrong before Droob answers."
        }
        static func reviewCount(_ ar: Bool, count: Int) -> String {
            if count == 1 {
                return ar ? "تم العثور على سؤال واحد" : "1 question found"
            }
            return ar ? "تم العثور على \(count) أسئلة" : "\(count) questions found"
        }
        static func edit(_ ar: Bool) -> String {
            ar ? "تعديل" : "Edit"
        }
        static func delete(_ ar: Bool) -> String {
            ar ? "حذف" : "Delete"
        }
        static func reviewDeleted(_ ar: Bool) -> String {
            ar ? "تم حذف السؤال" : "Question removed"
        }
        static func undo(_ ar: Bool) -> String {
            ar ? "تراجع" : "Undo"
        }
        static func reviewAdd(_ ar: Bool) -> String {
            ar ? "إضافة سؤال" : "Add a question"
        }
        static func reviewSolveAll(_ ar: Bool, count: Int) -> String {
            ar ? "حل الكل (\(count))" : "Solve all (\(count))"
        }
        static func cancel(_ ar: Bool) -> String {
            ar ? "إلغاء" : "Cancel"
        }
        static func reviewEmptyTitle(_ ar: Bool) -> String {
            ar ? "لم يتبق أي سؤال" : "No questions left"
        }
        static func reviewEmptyBody(_ ar: Bool) -> String {
            ar ? "أضف سؤالاً، أو ألغِ وارفع ملفاً آخر."
               : "Add one, or cancel and upload a different file."
        }
        static func reviewCancelled(_ ar: Bool) -> String {
            ar ? "تم الإلغاء. لم يُرسل أي شيء." : "Cancelled. Nothing was sent."
        }
        static func reviewEmptied(_ ar: Bool) -> String {
            ar ? "حذفت كل الأسئلة، لذلك لم يُرسل أي شيء."
               : "You removed every question, so nothing was sent."
        }
        /// Read out for the card as a whole, so a screen reader announces which
        /// question the pencil and the bin belong to.
        static func reviewCardA11y(_ ar: Bool, number: Int) -> String {
            ar ? "السؤال رقم \(number)" : "Question \(number)"
        }
        static func reviewEditTitle(_ ar: Bool) -> String {
            ar ? "تعديل السؤال" : "Edit question"
        }
        static func reviewEditHint(_ ar: Bool) -> String {
            ar ? "السؤال كما يجب أن يُطرح"
               : "The question, exactly as it should be asked"
        }

        // MARK: The formula chips in the edit sheet
        //
        // A question is prose PLUS maths, and only the maths goes to the keypad.
        // These name that split for the student.

        static func editFormulasHeading(_ ar: Bool) -> String {
            ar ? "المعادلات في هذا السؤال" : "Formulas in this question"
        }
        static func editNewFormula(_ ar: Bool) -> String {
            ar ? "+ معادلة جديدة" : "+ New formula"
        }
        static func editFormulaChipA11y(_ ar: Bool) -> String {
            ar ? "تعديل هذه المعادلة" : "Edit this formula"
        }
        static func editNoFormula(_ ar: Bool) -> String {
            ar ? "لا توجد معادلة في هذا السؤال بعد."
               : "This question has no formula yet."
        }
        static func editPreviewHeading(_ ar: Bool) -> String {
            ar ? "معاينة" : "Preview"
        }
        static func save(_ ar: Bool) -> String {
            ar ? "حفظ" : "Save"
        }
        static func stageReviewing(_ ar: Bool) -> String {
            ar ? "بانتظار مراجعتك" : "Waiting for you to review"
        }

        // MARK: Library
        //
        // Inline bilingual constants, matching the rest of this feature. Ask
        // Droob AI does not use the string table today, and half-migrating one
        // feature guarantees the two halves drift.

        static func libraryTitle(_ ar: Bool) -> String {
            ar ? "المكتبة" : "Library"
        }
        static func libraryOpenA11y(_ ar: Bool) -> String {
            ar ? "فتح المكتبة" : "Open library"
        }
        static func emptyTitle(_ ar: Bool) -> String {
            ar ? "لا يوجد شيء محفوظ بعد" : "Nothing saved yet"
        }
        static func emptyBody(_ ar: Bool) -> String {
            ar ? "تُحفظ محادثاتك مع درووب هنا تلقائياً. اطرح سؤالاً أو ارفع ورقة أسئلة لتبدأ واحدة."
               : "Your conversations with Droob are saved here automatically. Ask a question or upload a worksheet to start one."
        }
        /// Arabic has five plural forms and none of them is "%d questions".
        static func questionCount(_ ar: Bool, count: Int) -> String {
            guard ar else {
                if count == 0 { return "No questions" }
                if count == 1 { return "1 question" }
                return "\(count) questions"
            }
            switch count {
            case 0: return "لا أسئلة"
            case 1: return "سؤال واحد"
            case 2: return "سؤالان"
            case 3...10: return "\(number(count, ar)) أسئلة"
            default: return "\(number(count, ar)) سؤالاً"
            }
        }
        /// Kept Latin in both locales: it is a file format, and the file really
        /// is called `.pdf`.
        static let pdfBadge = "PDF"
        static func untitledSession(_ ar: Bool) -> String {
            ar ? "جلسة بلا عنوان" : "Untitled session"
        }
        static func scannedWorksheetTitle(_ ar: Bool) -> String {
            ar ? "ورقة أسئلة ممسوحة" : "Scanned worksheet"
        }
        static func damagedRow(_ ar: Bool) -> String {
            ar ? "تعذّرت قراءتها" : "Couldn't be read"
        }
        static func open(_ ar: Bool) -> String {
            ar ? "فتح" : "Open"
        }
        static func sharePdf(_ ar: Bool) -> String {
            ar ? "مشاركة ملف PDF" : "Share PDF"
        }

        // MARK: Reading the exported sheet

        /// The viewer's title. `.lineLimit(1)` beside two toolbar buttons, and
        /// Arabic runs ~30% longer than English — this one is short by design.
        static func previewTitle(_ ar: Bool) -> String {
            ar ? "ملف الحلول" : "Solution sheet"
        }
        static func libraryOpenPdf(_ ar: Bool) -> String {
            ar ? "فتح ملف الحلول" : "Open solution sheet"
        }
        static func previewShareA11y(_ ar: Bool) -> String {
            ar ? "مشاركة ملف الحلول" : "Share the solution sheet"
        }
        static func reExport(_ ar: Bool) -> String {
            ar ? "إعادة تصدير PDF" : "Re-export PDF"
        }
        static func moreA11y(_ ar: Bool) -> String {
            ar ? "المزيد" : "More"
        }
        static func deleteOneTitle(_ ar: Bool) -> String {
            ar ? "حذف هذه الجلسة؟" : "Delete this session?"
        }
        static func deleteOneBody(_ ar: Bool) -> String {
            ar ? "ستُحذف أسئلتها وإجاباتها والملفات الممسوحة وملف PDF المُصدَّر من هذا الجهاز. لا يمكن التراجع عن ذلك."
               : "Its questions, answers, scans and exported PDF will be removed from this device. This can't be undone."
        }
        static func deleteAllAction(_ ar: Bool) -> String {
            ar ? "حذف كل شيء" : "Delete everything"
        }
        static func deleteAllTitle(_ ar: Bool) -> String {
            ar ? "حذف كل الجلسات؟" : "Delete all sessions?"
        }
        static func deleteAllBody(_ ar: Bool, count: Int, size: String) -> String {
            ar ? "ستُحذف كل الجلسات (\(number(count, true))) بحجم \(size) من هذا الجهاز. لا يمكن التراجع عن ذلك."
               : "All \(count) sessions (\(size)) will be removed from this device. This can't be undone."
        }
        static func deleteConfirm(_ ar: Bool) -> String {
            ar ? "حذف" : "Delete"
        }
        static func deleteAllConfirm(_ ar: Bool) -> String {
            ar ? "حذف الكل" : "Delete all"
        }
        static func footerUsage(
            _ ar: Bool, count: Int, used: String, budget: String
        ) -> String {
            ar ? "\(number(count, true)) جلسة · \(used) من \(budget)"
               : "\(count) sessions · \(used) of \(budget)"
        }
        static func footerLocalOnly(_ ar: Bool) -> String {
            ar ? "محفوظة على هذا الجهاز فقط." : "Saved on this device only."
        }
        /// A warning is cheaper than an apology.
        static func nearlyFull(_ ar: Bool) -> String {
            ar ? "مكتبتك أوشكت على الامتلاء. ستُحذف أقدم الجلسات لإفساح المجال."
               : "Your library is nearly full. The oldest sessions will be removed to make room."
        }
        static func evictedPdfs(_ ar: Bool, count: Int) -> String {
            ar ? "لم تعد هناك مساحة كافية، فحُذف \(number(count, true)) من ملفات PDF المصدَّرة القديمة. يمكنك تصديرها من جديد من داخل الجلسة."
               : "Space was low, so \(count) older exported PDFs were removed. You can export them again from the session."
        }
        static func evictedScans(_ ar: Bool, count: Int) -> String {
            ar ? "حُذف \(number(count, true)) من الملفات الممسوحة القديمة. أسئلتها وإجاباتها ما زالت هنا."
               : "\(count) older scans were removed. Their questions and answers are still here."
        }
        static func evictedSessions(_ ar: Bool, count: Int) -> String {
            ar ? "حُذف \(number(count, true)) من أقدم الجلسات لإفساح المجال."
               : "\(count) of the oldest sessions were deleted to make room."
        }
        static func dismiss(_ ar: Bool) -> String {
            ar ? "إخفاء" : "Dismiss"
        }
        static func savedToLibrary(_ ar: Bool) -> String {
            ar ? "حُفظت في مكتبتك." : "Saved to your library."
        }
        /// Red, unlike `saveFailed`: nothing was cleared and the student has to
        /// act, so it says both.
        static func archiveFailed(_ ar: Bool) -> String {
            ar ? "تعذّر حفظ هذه المحادثة في مكتبتك، لذلك لم يتم مسحها. أفرغ بعض المساحة وحاول مرة أخرى."
               : "This conversation couldn't be saved to your library, so it wasn't cleared. Free up some space and try again."
        }
        static func exportBusy(_ ar: Bool) -> String {
            ar ? "جارٍ تجهيز ملف PDF بالفعل. انتظر حتى ينتهي."
               : "A PDF is already being prepared. Wait for it to finish."
        }
        static func newChatA11y(_ ar: Bool) -> String {
            ar ? "محادثة جديدة" : "New chat"
        }
        static func busyCannotOpen(_ ar: Bool) -> String {
            ar ? "أنهِ الأسئلة الجارية أو أوقفها أولاً."
               : "Finish or stop the questions in progress first."
        }
        static func openFailed(_ ar: Bool) -> String {
            ar ? "تعذّرت قراءة هذه الجلسة." : "This session couldn't be read."
        }
        static func noExportYet(_ ar: Bool) -> String {
            ar ? "لا يوجد ملف PDF مُصدَّر لهذه الجلسة بعد."
               : "This session has no exported PDF yet."
        }
        static func scanHeader(_ ar: Bool, count: Int) -> String {
            if count <= 1 { return ar ? "الملف الممسوح" : "Scanned file" }
            return ar ? "الملفات الممسوحة (\(number(count, true)))"
                      : "Scanned files (\(count))"
        }
        static func scanEvicted(_ ar: Bool) -> String {
            ar ? "حُذف الملف الممسوح لتوفير المساحة. الأسئلة المقروءة منه ما زالت هنا."
               : "The scan was removed to save space. The questions read from it are still here."
        }
        static func viewScan(_ ar: Bool) -> String {
            ar ? "عرض الملف الممسوح" : "View scan"
        }
        static func storageFull(_ ar: Bool) -> String {
            ar ? "لا توجد مساحة كافية على هذا الجهاز لحفظ ذلك."
               : "There isn't enough space on this device to save that."
        }
        static func saveFailed(_ ar: Bool) -> String {
            ar ? "تعذّر الحفظ في مكتبتك." : "Couldn't save to your library."
        }
        static func yesterday(_ ar: Bool) -> String {
            ar ? "أمس" : "Yesterday"
        }

        // MARK: Chat chrome
        //
        // These replaced hardcoded English literals in `AskDroobAIView`. Same
        // bilingual shape as everything above, so the English wording is kept
        // rather than deleted and comes straight back with the flag.

        static func chatTitle(_ ar: Bool) -> String {
            ar ? "اسأل دروب" : "Ask Droob AI"
        }
        static func emptyHeadline(_ ar: Bool) -> String {
            ar ? "اسأل دروب" : "Ask Droob AI"
        }
        static func emptySubtitle(_ ar: Bool) -> String {
            ar ? "أقدر أساعدك في الرياضيات والفيزياء والكيمياء وغيرها!"
               : "I can help you with Math, Physics, Chemistry, and more!"
        }
        /// Arabic counts models the way it counts everything else — five forms,
        /// not "%d models".
        static func modelsConnected(_ ar: Bool, count: Int) -> String {
            guard ar else {
                return count == 1 ? "1 AI model connected" : "\(count) AI models connected"
            }
            switch count {
            case 0: return "لا نماذج ذكاء اصطناعي متصلة"
            case 1: return "نموذج ذكاء اصطناعي واحد متصل"
            case 2: return "نموذجا ذكاء اصطناعي متصلان"
            case 3...10: return "\(number(count, true)) نماذج ذكاء اصطناعي متصلة"
            default: return "\(number(count, true)) نموذجاً للذكاء الاصطناعي متصلاً"
            }
        }
        static func scanProblem(_ ar: Bool) -> String {
            ar ? "امسح مسألة" : "Scan a Problem"
        }
        static func thinking(_ ar: Bool) -> String {
            ar ? "جارٍ التفكير…" : "Thinking..."
        }
        /// Auto mode in the provider strip.
        static func providerAuto(_ ar: Bool) -> String {
            ar ? "تلقائي" : "Auto"
        }
        /// Provider *names* stay Latin on purpose — "Gemini" and "Mistral" are
        /// product names, not words, and transliterating them would make the
        /// model the student picked unrecognisable.
        static func viaProvider(_ ar: Bool, provider: String) -> String {
            ar ? "عبر \(provider)" : "via \(provider)"
        }
        static func scannedText(_ ar: Bool) -> String {
            ar ? "النص الممسوح:" : "Scanned Text:"
        }
        /// Fills an empty composer after a photo read. This string is both shown
        /// to the student AND sent verbatim to the model, so an English default
        /// steered the whole answer into English.
        static func photoReadPrompt(_ ar: Bool) -> String {
            ar ? "ما حل هذه المسألة؟" : "What is the answer to this problem?"
        }
        static func imageProcessFailed(_ ar: Bool, detail: String) -> String {
            ar ? "تعذّرت معالجة الصورة: \(detail)"
               : "Could not process the image: \(detail)"
        }
        static func noTextInImage(_ ar: Bool) -> String {
            ar ? "لم يُعثر على نص في الصورة. جرّب صورة أوضح."
               : "No text found in the image. Try a clearer photo."
        }
        /// The name a stored photograph is filed under.
        static func photoFileName(_ ar: Bool) -> String {
            ar ? "صورة.jpg" : "photo.jpg"
        }

        // MARK: Quick-action prompts
        //
        // The *prompt* is written into the visible composer and then sent to the
        // model, so it has to be Arabic on both counts — an English prompt both
        // showed English to the student and asked the model for an English
        // answer.

        static func promptSolveMath(_ ar: Bool) -> String {
            ar ? "ساعدني في حل مسألة الرياضيات هذه خطوة بخطوة:"
               : "Help me solve this math problem step by step:"
        }
        static func promptExplainPhysics(_ ar: Bool) -> String {
            ar ? "اشرح لي مفهوم الفيزياء هذا بوضوح مع أمثلة:"
               : "Explain this physics concept clearly with examples:"
        }
        static func promptReviewLesson(_ ar: Bool) -> String {
            ar ? "ساعدني في مراجعة وتلخيص هذه المفاهيم الأساسية:"
               : "Help me review and summarize these key concepts:"
        }

        // MARK: Error taxonomies
        //
        // `AIError`, `OCRError` and `ExportError` build their messages in code
        // and land in `errorMessage`, which renders red on screen. They were the
        // one path where an ordinary network failure printed English into an
        // Arabic-only app.

        static func errEmptyReply(_ ar: Bool) -> String {
            ar ? "لم يرسل مساعد الذكاء الاصطناعي أي رد."
               : "The AI service returned an empty reply."
        }
        static func errNoVisionProvider(_ ar: Bool) -> String {
            ar ? "لا يتوفّر مساعد قادر على قراءة صور الصفحات."
               : "No AI provider available that can read a page image."
        }
        static func errNoProviders(_ ar: Bool) -> String {
            ar ? "لا يتوفّر أي مساعد ذكاء اصطناعي الآن. حاول مرة أخرى لاحقاً."
               : "No AI providers available. Please try again later."
        }
        static func errUnsupportedProvider(_ ar: Bool, name: String) -> String {
            ar ? "المزوّد \(name) غير مدعوم بعد."
               : "Provider \(name) is not supported yet."
        }
        static func errInvalidURL(_ ar: Bool) -> String {
            ar ? "رابط الخدمة غير صالح." : "Invalid API URL"
        }
        static func errNetwork(_ ar: Bool) -> String {
            ar ? "خطأ في الشبكة. تحقّق من اتصالك."
               : "Network error. Check your connection."
        }
        static func errRateLimited(_ ar: Bool, name: String) -> String {
            ar ? "تم تجاوز حد الاستخدام لدى \(name). جارٍ تجربة مزوّد آخر…"
               : "Rate limited by \(name). Trying next provider..."
        }
        static func errNoAPIKey(_ ar: Bool, name: String) -> String {
            ar ? "لا يوجد مفتاح مُهيّأ للمزوّد \(name)."
               : "No API key configured for \(name)."
        }
        static func errParseFailed(_ ar: Bool) -> String {
            ar ? "تعذّرت قراءة رد مساعد الذكاء الاصطناعي."
               : "Could not parse AI response"
        }
        static func errProviderFailed(_ ar: Bool) -> String {
            ar ? "تعذّر على مساعد الذكاء الاصطناعي الرد الآن. حاول مرة أخرى."
               : "The AI service couldn't answer right now. Please try again."
        }
        static func errInvalidImage(_ ar: Bool) -> String {
            ar ? "تعذّرت معالجة الصورة." : "Could not process the image"
        }
        static func errExportNothing(_ ar: Bool) -> String {
            ar ? "لا توجد إجابات لتصديرها بعد." : "There are no answers to export yet."
        }
        static func errExportTemplateMissing(_ ar: Bool) -> String {
            ar ? "قالب ورقة الحلول غير موجود في التطبيق."
               : "The worksheet template is missing from the app bundle."
        }
        static func errExportPrepare(_ ar: Bool, detail: String) -> String {
            ar ? "تعذّر تجهيز ورقة الحلول: \(detail)"
               : "Could not prepare the worksheet: \(detail)"
        }
        static func errExportLayout(_ ar: Bool, detail: String) -> String {
            ar ? "تعذّر ترتيب ورقة الحلول: \(detail)"
               : "Could not lay out the worksheet: \(detail)"
        }
        static func errExportRender(_ ar: Bool, detail: String) -> String {
            ar ? "تعذّر إنشاء ملف PDF: \(detail)"
               : "Could not render the PDF: \(detail)"
        }
        static func errExportSave(_ ar: Bool, detail: String) -> String {
            ar ? "تعذّر حفظ ملف PDF: \(detail)"
               : "Could not save the PDF: \(detail)"
        }
        static func errExportNeverFinished(_ ar: Bool) -> String {
            ar ? "لم تكتمل معالجة ورقة الحلول"
               : "the worksheet never finished rendering"
        }
        static func errExportNoPages(_ ar: Bool) -> String {
            ar ? "لم تُنتج ورقة الحلول أي صفحات"
               : "the worksheet produced no pages"
        }
        static func errExportEmptySheet(_ ar: Bool) -> String {
            ar ? "عادت إحدى الصفحات فارغة" : "a sheet came back empty"
        }

        // MARK: Locale-aware numbers and sizes
        //
        // Arabic rows show Arabic-Indic digits, matching what the exported sheet
        // already does for its own subtitle.

        static func number(_ value: Int, _ ar: Bool) -> String {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: ar ? "ar" : "en_US_POSIX")
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }

        static func size(_ bytes: Int64, _ ar: Bool) -> String {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: ar ? "ar" : "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 0

            let megabytes = Double(bytes) / (1024 * 1024)
            if megabytes < 0.1 {
                formatter.maximumFractionDigits = 0
                let kilobytes = max(Double(bytes) / 1024, bytes > 0 ? 1 : 0)
                let text = formatter.string(from: NSNumber(value: kilobytes))
                    ?? "\(Int(kilobytes))"
                return ar ? "\(text) ك.ب" : "\(text) KB"
            }
            formatter.maximumFractionDigits = megabytes < 10 ? 1 : 0
            let text = formatter.string(from: NSNumber(value: megabytes))
                ?? "\(Int(megabytes))"
            return ar ? "\(text) م.ب" : "\(text) MB"
        }

        /// The row's date line: today → time only, yesterday → §7.43, this week
        /// → the weekday, older → `d MMM yyyy`. Formatted in the *session's*
        /// locale, so an Arabic session keeps Arabic month names wherever the
        /// app happens to be.
        static func rowDate(_ date: Date, locale: String) -> String {
            let ar = locale == "ar"
            let calendar = Calendar.current
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: ar ? "ar" : "en_US")

            if calendar.isDateInToday(date) {
                formatter.dateStyle = .none
                formatter.timeStyle = .short
                return formatter.string(from: date)
            }
            if calendar.isDateInYesterday(date) {
                return yesterday(ar)
            }
            if let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: date),
                to: calendar.startOfDay(for: Date())).day, days < 7, days >= 0 {
                formatter.dateFormat = "EEEE"
                return formatter.string(from: date)
            }
            formatter.dateFormat = "d MMM yyyy"
            return formatter.string(from: date)
        }
    }

    /// The progress line for the current stage, or `nil` when idle. Western
    /// digits in both languages, matching the exporter's existing
    /// `"N مسائل محلولة"` subtitle.
    func stageText(locale: String) -> String? {
        let ar = locale == "ar"
        switch intakeStage {
        case .idle:
            return nil
        case .reading:
            return Strings.stageReading(ar)
        case .readingPage(let current, let total):
            return Strings.stageReadingPage(ar, current: current, total: total)
        case .segmenting:
            return Strings.stageSegmenting(ar)
        case .reviewing:
            return Strings.stageReviewing(ar)
        case .answering(let current, let total):
            return Strings.stageAnswering(ar, current: current, total: total)
        }
    }

    func readingImageLabel(locale: String) -> String {
        Strings.readingImage(locale == "ar")
    }

    func filePickerLabel(locale: String) -> String {
        Strings.filePickerButton(locale == "ar")
    }

    func cancelLabel(locale: String) -> String {
        Strings.cancelButton(locale == "ar")
    }

    func retryLabel(locale: String) -> String {
        Strings.retryUnanswered(locale == "ar")
    }
}

// MARK: - Chat Message Model

struct AskDroobMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    /// Which model produced this answer. `var` with a default rather than `let`
    /// with one: a `let` with a default is excluded from the memberwise
    /// initialiser altogether, which would break every existing construction
    /// site instead of leaving them untouched. Absent on user turns.
    var provider: String? = nil

    enum MessageRole {
        case user
        case assistant
    }
}
