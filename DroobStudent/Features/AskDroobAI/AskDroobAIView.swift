import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import WebKit

/// Ask Droob AI — the main chat interface.
/// Fetches providers from backend, shows model picker, auto-fallback on rate limit.
struct AskDroobAIView: View {
    @StateObject private var viewModel = AskDroobAIViewModel()
    @Environment(\.appLocale) private var locale
    @Environment(\.dismiss) private var dismiss
    /// An iPad form sheet is ~540 pt wide, under the component's 700 px
    /// breakpoint, so a plain `.sheet` there would silently present the phone
    /// keypad layout. Regular width gets the full screen instead.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: Maths keyboard host state
    //
    // The draft lives here, on the screen, not in the view model: it is
    // transient composer text, and putting it in the view model would make it
    // survive `clearChat()`.
    @State private var showMathSheet = false
    @State private var mathDraft = ""
    /// The Library. A sheet rather than a push — see `AskDroobLibraryView`.
    @State private var showLibrary = false
    /// A stored scan being read back through Quick Look.
    @State private var scanPreview: LibraryShareItem?

    private typealias S = AskDroobAIViewModel.Strings
    private var isArabic: Bool { locale == "ar" }
    private var regularWidth: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack(spacing: 0) {
            providerBar
            Divider().overlay(Color.droobGold.opacity(0.3))

            if viewModel.messages.isEmpty && viewModel.sessionAttachments.isEmpty
                && !viewModel.sessionScansEvicted {
                emptyState
            } else {
                messagesList
            }

            statusArea

            Divider().overlay(Color.droobGold.opacity(0.3))
            inputBar
        }
        .navigationTitle(S.chatTitle(isArabic))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A way out. The hub is presented as a .fullScreenCover from
            // RootView, which supplies no dismiss affordance of its own — so
            // without this the student is stranded in the AI section. The
            // course and lesson entry points push instead and get a system
            // back button, and `dismiss()` is correct for a push too, so one
            // control serves all three presentations.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .foregroundColor(.droobGold)
                }
                .accessibilityLabel(locale == "ar" ? "رجوع" : "Back")
            }

            // Leading→trailing: Library · Export · New chat. The bin is gone:
            // clearing archives to the Library now, and deleting from the
            // Library is the destructive path.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showLibrary = true
                } label: {
                    Image(systemName: "books.vertical")
                        .foregroundColor(.droobGold)
                }
                // Not while this screen is rendering a sheet of its own. The
                // Library's Re-export drives the same single WKWebView-backed
                // renderer into the same session's `exports/` directory, and the
                // finished share sheet would land on top of the Library anyway —
                // UIKit drops the second of two simultaneous presentations.
                .disabled(viewModel.isExporting)
                .accessibilityLabel(
                    AskDroobAIViewModel.Strings.libraryOpenA11y(isArabic))
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.exportThreadAsPDF(locale: locale)
                } label: {
                    if viewModel.isExporting {
                        ProgressView().tint(.droobGold)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.droobGold)
                    }
                }
                // `isBatchRunning` as well: an export started mid-read lands
                // its share sheet on screen just as the read finishes and the
                // review wants to present, and UIKit drops the second of two
                // simultaneous presentations. The thread is also incomplete
                // until the batch ends, so there is nothing here worth racing
                // for.
                .disabled(
                    !viewModel.canExportPDF
                        || viewModel.isExporting
                        || viewModel.isBatchRunning)
                .accessibilityLabel(
                    locale == "ar" ? "تصدير كل الحلول كملف PDF" : "Export all as PDF")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.clearChat()
                } label: {
                    if viewModel.isArchiving {
                        ProgressView().tint(.droobGold)
                    } else {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(.droobGold)
                    }
                }
                // Clearing now waits for the archive to land before it empties
                // the screen, so the button reports that wait rather than
                // accepting a second tap during it.
                .disabled(viewModel.isArchiving)
                .accessibilityLabel(
                    AskDroobAIViewModel.Strings.newChatA11y(isArabic))
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .photosPicker(
            isPresented: $viewModel.showPhotoPicker,
            selection: $viewModel.selectedPhotoItem,
            matching: .images
        )
        .fullScreenCover(isPresented: $viewModel.showCamera) {
            CameraView(image: $viewModel.capturedImage)
        }
        // Same UIDocumentPicker bridge the chat composer and Study Rooms use,
        // narrowed to what a worksheet can actually be.
        .sheet(isPresented: $viewModel.showFilePicker) {
            DocumentPicker(
                onPicked: { viewModel.handlePickedFile($0) },
                contentTypes: [.pdf, .image])
        }
        // A finished export opens in a viewer, not in the OS share sheet: the
        // student made this sheet and had never once seen it. Sharing is the
        // secondary action from inside the viewer, and it is the same
        // `ActivityShareSheet` the lesson PDF reader ships, so Save-to-Files
        // behaves the same wherever the app hands over a file.
        .sheet(item: $viewModel.exportedPDF) { export in
            SolutionPreviewSheet(url: export.url, isArabic: isArabic) {
                viewModel.exportedPDF = nil
            }
        }
        // Its own `NavigationStack`: two of this screen's three hosts present it
        // inside a `NavigationLink` background, where a push would silently do
        // nothing.
        .sheet(isPresented: $showLibrary) {
            NavigationStack {
                AskDroobLibraryView(viewModel: viewModel)
            }
        }
        .sheet(item: $scanPreview) { item in
            QuickLookPreview(url: item.url).ignoresSafeArea()
        }
        // The maths keyboard. A modal rather than an inline swap: the component
        // is a field *plus* a four-layer keypad that needs ~60% of the screen
        // and owns its own scrolling, and inline it would fight the IME and the
        // chat list for height on every keystroke.
        .droobAdaptiveSheet(
            isPresented: $showMathSheet,
            regularWidth: regularWidth,
            detents: [.fraction(0.75), .large]
        ) {
            MathKeyboardSheet(
                draft: $mathDraft,
                isArabic: isArabic,
                onAdd: { value, isLatex in
                    insertFormulaIntoComposer(value, isLatex: isLatex)
                    closeMathSheet()
                },
                // The page's Solve key in this host means: insert and send.
                onSubmit: { value, isLatex in
                    insertFormulaIntoComposer(value, isLatex: isLatex)
                    closeMathSheet()
                    viewModel.sendMessage()
                },
                onClose: { showMathSheet = false })
        }
        // The review step. Opens `.large` rather than 0.75 — the list is long.
        .droobAdaptiveSheet(
            isPresented: reviewPresented,
            regularWidth: regularWidth,
            detents: [.large]
        ) {
            ReviewSheetView(viewModel: viewModel, locale: locale)
        }
        // A batch outlives this screen otherwise — see `stopWorkOnDisappear`.
        .onDisappear {
            // Not while one of this screen's own modals is on top. In regular
            // width `droobAdaptiveSheet` presents through `.fullScreenCover`,
            // and a cover can fire the presenter's `onDisappear`; cancelling
            // there would throw away a review the student is still reading.
            guard !showMathSheet,
                  !showLibrary,
                  scanPreview == nil,
                  !viewModel.showReview,
                  !viewModel.showCamera,
                  !viewModel.showFilePicker,
                  viewModel.exportedPDF == nil
            else { return }
            viewModel.stopWorkOnDisappear()
        }
        .onChange(of: viewModel.selectedPhotoItem) { _ in
            viewModel.processSelectedPhoto()
        }
        .onChange(of: viewModel.capturedImage) { image in
            if image != nil {
                viewModel.processCapturedPhoto()
            }
        }
    }

    // MARK: - Maths keyboard plumbing

    /// Dismissal of the review sheet is never destructive of anything but the
    /// extracted list, so every way out of it — Cancel, ✕, swipe-down — is the
    /// same call.
    private var reviewPresented: Binding<Bool> {
        Binding(
            // Held back while the share sheet is up. UIKit refuses a second
            // simultaneous presentation and simply drops it, and nothing
            // re-tries it, which would strand `intakeStage` at `.reviewing`:
            // spinner on screen, every input disabled, and the extracted
            // questions reachable only by pressing Stop, which throws them
            // away. Deferring instead makes the dismissal of the share sheet
            // flip this binding and present the review then.
            get: { viewModel.showReview && viewModel.exportedPDF == nil },
            set: { presented in
                guard !presented else { return }
                // A deferral is not a dismissal: only the student closing the
                // sheet discards the list.
                guard viewModel.exportedPDF == nil else { return }
                viewModel.cancelReview()
            })
    }

    /// The mathfield always produces LaTeX for something else: it composes a
    /// formula, and the prose around it stays in the ordinary text field.
    ///
    /// `$…$` — single dollars, the inline delimiter `MathMarkdownView`,
    /// `print.html` and the tutor system prompt all already agree on. But only
    /// when the value really is LaTeX: in the plain-text fallback the student is
    /// typing a sentence, and wrapping a sentence in dollars hands it to KaTeX.
    private func insertFormulaIntoComposer(_ value: String, isLatex: Bool) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isLatex && mathHasUnfilledBox(trimmed) { return }
        let addition = isLatex ? "$" + trimmed + "$" : trimmed

        if viewModel.inputText.isEmpty {
            viewModel.inputText = addition
        } else if let last = viewModel.inputText.last, !last.isWhitespace {
            viewModel.inputText += " " + addition
        } else {
            viewModel.inputText += addition
        }
    }

    private func closeMathSheet() {
        showMathSheet = false
        mathDraft = ""
    }

    // MARK: - Provider Bar

    private var providerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Auto mode (uses fallback chain)
                Button {
                    // Default: use first available
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                        Text(S.providerAuto(isArabic))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [.droobGold, .droobDarkBrown],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }

                // Individual providers
                ForEach(viewModel.availableProviders) { provider in
                    Button {
                        // Provider selection would go here
                    } label: {
                        HStack(spacing: 4) {
                            if provider.supportsVision {
                                Image(systemName: "camera.fill")
                                    .font(.caption2)
                            }
                            Text(provider.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .foregroundColor(.primary)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.droobGold.opacity(0.2), .droobDarkBrown.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)

                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 44))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.droobGold, .droobDarkBrown],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 8) {
                    Text(S.emptyHeadline(isArabic))
                        .font(.title2.bold())

                    Text(S.emptySubtitle(isArabic))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Provider count
                if !viewModel.availableProviders.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(S.modelsConnected(
                            isArabic, count: viewModel.availableProviders.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Quick actions
                VStack(spacing: 12) {
                    ForEach(viewModel.quickActions) { action in
                        Button {
                            if !action.prompt.isEmpty {
                                viewModel.inputText = action.prompt
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: action.icon)
                                    .font(.title3)
                                    .foregroundColor(.droobGold)
                                    .frame(width: 32)

                                Text(locale == "ar" ? action.titleAr : action.titleEn)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal)

                // Photo button
                Button {
                    viewModel.showCamera = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text(S.scanProblem(isArabic))
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [.droobGold, .droobDarkBrown],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .disabled(viewModel.isBatchRunning)

                // Whole-worksheet entry point, alongside the single-problem
                // one, so the two are discoverable together rather than the
                // file button hiding in the input bar.
                Button {
                    viewModel.showFilePicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                        Text(locale == "ar"
                             ? "رفع ورقة أسئلة"
                             : "Upload a Question Sheet")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.droobGold)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                // `isLoading` too: a worksheet started while an ordinary reply
                // is still in flight interleaves the two writers of `messages`
                // and mis-pairs every later question with someone else's
                // answer in the exported PDF.
                .disabled(viewModel.isBatchRunning || viewModel.isLoading)
                .accessibilityLabel(viewModel.filePickerLabel(locale: locale))

                Spacer()
            }
        }
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    scanCard

                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(
                            message: message,
                            // Same reason the toolbar export is gated: the
                            // per-answer control had no disabled state at all,
                            // so it was the one way to get a share sheet on
                            // screen while a worksheet was still being read.
                            exportDisabled: viewModel.isBatchRunning || viewModel.isExporting,
                            onSaveAsPDF: { viewModel.exportAnswerAsPDF(message, locale: locale) }
                        )
                        .id(message.id)
                    }

                    if viewModel.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.droobGold)
                            Text(S.thinking(isArabic))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 16)
                        .id("loading")
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _ in
                withAnimation {
                    if let last = viewModel.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    } else if viewModel.isLoading {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isLoading) { _ in
                withAnimation {
                    if viewModel.isLoading {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Scan card
    //
    // A student who reopens a worksheet session wants to see the paper, not only
    // what was read out of it. Pinned above the first message so it reads as
    // context for the whole thread rather than as one more bubble in it.

    @ViewBuilder
    private var scanCard: some View {
        if viewModel.sessionScansEvicted && viewModel.sessionAttachments.isEmpty {
            Text(AskDroobAIViewModel.Strings.scanEvicted(isArabic))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if !viewModel.sessionAttachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(AskDroobAIViewModel.Strings.scanHeader(
                    isArabic, count: viewModel.sessionAttachments.count))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.droobGold)

                ForEach(viewModel.sessionAttachments) { attachment in
                    HStack(spacing: 10) {
                        Image(systemName: attachment.isPDF ? "doc.richtext" : "photo")
                            .foregroundColor(.droobGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(AskDroobAIViewModel.Strings.size(
                                attachment.bytes, isArabic))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button {
                            scanPreview = LibraryShareItem(url: attachment.url)
                        } label: {
                            Text(AskDroobAIViewModel.Strings.viewScan(isArabic))
                                .font(.caption.weight(.medium))
                                .foregroundColor(.droobGold)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Status Area (error + OCR preview + provider indicator)

    @ViewBuilder
    private var statusArea: some View {
        if viewModel.isExporting {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(.droobGold)
                Text(locale == "ar" ? "جارٍ تجهيز ملف PDF..." : "Preparing PDF...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }

        // A single photo being read. `stageText` cannot cover this — a photo
        // leaves `intakeStage` at `.idle` — and without a line here the screen
        // is completely blank for the 3–6 s the vision read takes, which reads
        // as the camera sheet having dismissed to nothing.
        if viewModel.isProcessingOCR {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(.droobGold)
                Text(viewModel.readingImageLabel(locale: locale))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 4)
        }

        // Batch progress. Plain HStack inside the status area, so it inherits
        // the app's layout direction and needs no manual RTL mirroring.
        if let stage = viewModel.stageText(locale: locale) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(.droobGold)
                Text(stage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 4)
        }

        // Caps and cancellation: true, useful, and not a failure — so
        // secondary, never red.
        if let notice = viewModel.intakeNotice {
            Text(notice)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 2)
        }

        if let error = viewModel.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal)
                .padding(.vertical, 4)
        }

        // The only way a student learns *which* questions failed: a failed
        // question deliberately leaves no assistant bubble, so without this
        // the gap in the thread is the whole message.
        if !viewModel.failedQuestions.isEmpty
            && !viewModel.isBatchRunning
            && !viewModel.isLoading {
            Button {
                viewModel.retryFailedQuestions()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text(viewModel.retryLabel(locale: locale))
                }
                .font(.caption.weight(.medium))
                .foregroundColor(.droobGold)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 4)
        }

        if viewModel.ocrText != nil {
            ocrPreview
        }

        if let provider = viewModel.lastProviderUsed {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                Text(S.viaProvider(isArabic, provider: provider))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - OCR Preview

    private var ocrPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.text.viewfinder")
                    .font(.caption)
                    .foregroundColor(.droobGold)
                Text(S.scannedText(isArabic))
                    .font(.caption.bold())
                    .foregroundColor(.droobGold)
            }

            Text(viewModel.ocrText ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.showCamera = true
            } label: {
                Image(systemName: "camera.fill")
                    .font(.title3)
                    .foregroundColor(.droobGold)
            }
            // `isProcessingOCR` as well: a second photo picked while the first
            // is still being read races it for `ocrText`.
            .disabled(viewModel.isBatchRunning || viewModel.isProcessingOCR)

            Button {
                viewModel.showPhotoPicker = true
            } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.title3)
                    .foregroundColor(.droobGold)
            }
            .disabled(viewModel.isBatchRunning || viewModel.isProcessingOCR)

            // Third icon: a whole worksheet rather than one problem.
            Button {
                viewModel.showFilePicker = true
            } label: {
                Image(systemName: "doc.badge.plus")
                    .font(.title3)
                    .foregroundColor(.droobGold)
            }
            .disabled(
                viewModel.isBatchRunning
                    || viewModel.isLoading
                    || viewModel.isProcessingOCR)
            .accessibilityLabel(viewModel.filePickerLabel(locale: locale))

            // Fourth icon: type the maths instead of scanning it. Same disabled
            // condition as the file button — a formula composed into the
            // composer mid-batch would be sent into an interleaved thread.
            Button {
                showMathSheet = true
            } label: {
                Image(systemName: "function")
                    .font(.title3)
                    .foregroundColor(.droobGold)
            }
            .disabled(
                viewModel.isBatchRunning
                    || viewModel.isLoading
                    || viewModel.isProcessingOCR)
            .accessibilityLabel(S.mathInsertFormula(isArabic))
            .accessibilityLabel(AskDroobAIViewModel.Strings.mathKeyboard(isArabic))

            TextField(
                locale == "ar" ? "اكتب سؤالك هنا..." : "Type your question...",
                text: $viewModel.inputText,
                axis: .vertical
            )
            .lineLimit(1...5)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // During a batch this same control is the only way out, so it
            // becomes stop rather than growing a second button the student
            // has to find.
            Button {
                if viewModel.isBatchRunning {
                    viewModel.cancelBatch()
                } else {
                    viewModel.sendMessage()
                }
            } label: {
                if viewModel.isBatchRunning {
                    Image(systemName: "stop.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                } else if viewModel.isLoading || viewModel.isProcessingOCR {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .frame(width: 36, height: 36)
            .background(
                sendButtonEnabled
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [.droobGold, .droobDarkBrown],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                      )
                    : AnyShapeStyle(Color.gray)
            )
            .clipShape(Circle())
            .disabled(!sendButtonEnabled)
            .accessibilityLabel(
                viewModel.isBatchRunning
                    ? viewModel.cancelLabel(locale: locale)
                    : (locale == "ar" ? "إرسال" : "Send"))
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// Stop is always tappable — a student who wants out of a 40-question
    /// batch must not be blocked by the rules that govern sending.
    private var sendButtonEnabled: Bool {
        if viewModel.isBatchRunning { return true }
        // A send during a photo read would go out with `ocrText` still nil, so
        // the photo the student just took is dropped from the request and its
        // preview turns up afterwards attached to nothing.
        if viewModel.isLoading || viewModel.isProcessingOCR { return false }
        let hasText = !viewModel.inputText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || viewModel.ocrText != nil
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: AskDroobMessage
    /// True while another presentation owns the screen — a running batch, or
    /// an export already rendering. Two sheets cannot be presented at once.
    var exportDisabled: Bool = false
    /// Fires the per-answer export. Passed for every bubble; only assistant
    /// bubbles show the control, since a student's own question is not a
    /// worksheet.
    var onSaveAsPDF: (() -> Void)?

    @Environment(\.appLocale) private var locale

    /// Height reported back by the maths web view, which has to size itself.
    @State private var mathHeight: CGFloat = 20

    /// True when the text holds a complete `$…$` span the plain `Text` view
    /// cannot render.
    ///
    /// The shared checker from `Features/Shared/MathTextView.swift`, not
    /// `content.contains("$")`: a single dollar is true for "50$" and used to
    /// spin up a WKWebView for a bubble with no maths in it at all.
    private var hasMath: Bool {
        containsMath(message.content)
    }

    /// A student who types `$\int x\,dx$` with the maths keyboard must not read
    /// raw LaTeX back in their own bubble. The renderer takes one background
    /// colour, not a gradient, so a math-bearing user bubble is a flat dark
    /// brown; every other user bubble keeps the gradient.
    private var mathTextColor: UIColor {
        message.role == .user ? .white : .label
    }

    private var mathBackgroundColor: UIColor {
        message.role == .user
            ? UIColor(Color.droobDarkBrown)
            : .secondarySystemBackground
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if hasMath {
                    // Renders markdown + KaTeX. Without this the student reads
                    // the raw source — "$$\\frac{d}{dx}$$" — instead of the formula.
                    MathMarkdownView(
                        markdown: message.content,
                        textColor: mathTextColor,
                        backgroundColor: mathBackgroundColor,
                        // `math.html` declares no `dir`. Without this an
                        // Arabic sentence with a formula in it lays out at
                        // bidi level 0 — its clauses swap round and the bubble
                        // is left-aligned beside right-aligned prose bubbles.
                        isRTL: locale == "ar",
                        contentHeight: $mathHeight
                    )
                    .frame(height: max(20, mathHeight))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(mathBackgroundColor))
                    )
                } else {
                // A batch question is stored exactly as the review card
                // approved it, which is markdown — and the one markdown-only
                // artefact in it, the `\)` that stops CommonMark renumbering
                // the options, is a literal backslash to `Text`.
                Text(reviewPlainText(message.content))
                    .font(.subheadline)
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .padding(12)
                    .background(
                        message.role == .user
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [.droobGold, .droobDarkBrown],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                              )
                            : AnyShapeStyle(Color(.systemGray6))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                if message.role == .assistant, let action = onSaveAsPDF {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.doc")
                            Text(locale == "ar" ? "حفظ كـ PDF" : "Save as PDF")
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundColor(exportDisabled ? .secondary : .droobGold)
                    }
                    .buttonStyle(.plain)
                    .disabled(exportDisabled)
                    .padding(.leading, 4)
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Adaptive sheet presentation

/// Presents the same content as a detented sheet on compact width and full
/// screen on regular width.
///
/// Both presentations are attached unconditionally, each with a derived
/// binding, rather than branching on the size class in the view tree: a
/// `_ConditionalContent` branch flip on rotation changes view identity and
/// would take `@StateObject private var viewModel` — the whole chat — with it.
private struct DroobAdaptiveSheet<SheetBody: View>: ViewModifier {
    @Binding var isPresented: Bool
    let regularWidth: Bool
    let detents: Set<PresentationDetent>
    let sheetBody: () -> SheetBody

    private var compact: Binding<Bool> {
        Binding(
            get: { isPresented && !regularWidth },
            set: { if !$0 && isPresented { isPresented = false } })
    }

    private var regular: Binding<Bool> {
        Binding(
            get: { isPresented && regularWidth },
            set: { if !$0 && isPresented { isPresented = false } })
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: compact) {
                sheetBody()
                    .presentationDetents(detents)
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: regular) {
                sheetBody()
            }
    }
}

extension View {
    func droobAdaptiveSheet<SheetBody: View>(
        isPresented: Binding<Bool>,
        regularWidth: Bool,
        detents: Set<PresentationDetent>,
        @ViewBuilder sheet: @escaping () -> SheetBody
    ) -> some View {
        modifier(
            DroobAdaptiveSheet(
                isPresented: isPresented,
                regularWidth: regularWidth,
                detents: detents,
                sheetBody: sheet))
    }
}

// MARK: - Maths keyboard asset hosting

/// Serves `Resources/math/` to the mathfield WebView over a real origin.
///
/// **Why this exists at all.** MathLive fetches its own fonts —
/// `new FontFace(family, "url(<dir>/<face>.woff2)").load()` — and the CSS Font
/// Loading API applies CORS. Loaded with `loadFileURL` the page's origin is
/// null, the fetch is blocked, and the field falls back to a system face with
/// the wrong metrics (visibly misaligned fractions and radicals). A custom
/// scheme gives the page a real origin, and every response below carries
/// `Access-Control-Allow-Origin` because WebKit applies CORS to fetches from a
/// custom-scheme origin too.
final class DroobMathAssetHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "droob-math"
    static let entryURL = URL(string: "droob-math://assets/math/mathfield.html")!

    /// WebKit raises if a task that was stopped is later completed, and the
    /// bytes are read off the main thread, so the two can race.
    private let taskLock = DispatchQueue(label: "sa.droob.mathfield.schemetask")
    private var stoppedTasks = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask)
        taskLock.sync { _ = stoppedTasks.remove(key) }

        guard
            let url = urlSchemeTask.request.url,
            let resources = Bundle.main.resourceURL,
            let root = Bundle.main.url(forResource: "math", withExtension: nil)
        else {
            fail(urlSchemeTask, key: key)
            return
        }

        // `droob-math://assets/math/fonts/KaTeX_Main-Regular.woff2`
        //  → <bundle>/math/fonts/KaTeX_Main-Regular.woff2
        let relative = String(url.path.drop(while: { $0 == "/" }))
        let resolved = resources.appendingPathComponent(relative).standardizedFileURL
        let rootPath = root.standardizedFileURL.path

        // Traversal: `..` segments are already collapsed by
        // `standardizedFileURL`, so a prefix test is the whole check.
        guard resolved.path == rootPath || resolved.path.hasPrefix(rootPath + "/") else {
            fail(urlSchemeTask, key: key)
            return
        }

        // MathLive's fonts-directory resolver issues `fetch(<script src>,
        // {method:"HEAD"})` before it builds any font URL. Answer it with
        // headers and no body.
        let isHead = (urlSchemeTask.request.httpMethod ?? "GET").uppercased() == "HEAD"
        let mimeType = Self.mimeType(forExtension: resolved.pathExtension.lowercased())

        // `mathlive.min.js` is 823 KB; reading it on the main thread is a
        // visible stall the moment the sheet opens.
        DispatchQueue.global(qos: .userInitiated).async {
            let data = try? Data(contentsOf: resolved, options: .mappedIfSafe)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !self.isStopped(key) else {
                    self.forget(key)
                    return
                }
                guard
                    let data,
                    let response = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Content-Type": mimeType,
                            "Content-Length": String(data.count),
                            "Access-Control-Allow-Origin": "*",
                            "Cache-Control": "no-store"
                        ])
                else {
                    self.fail(urlSchemeTask, key: key)
                    return
                }

                urlSchemeTask.didReceive(response)
                if !isHead, !self.isStopped(key) { urlSchemeTask.didReceive(data) }
                if !self.isStopped(key) { urlSchemeTask.didFinish() }
                self.forget(key)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask)
        taskLock.sync { _ = stoppedTasks.insert(key) }
    }

    private func isStopped(_ key: ObjectIdentifier) -> Bool {
        taskLock.sync { stoppedTasks.contains(key) }
    }

    private func forget(_ key: ObjectIdentifier) {
        taskLock.sync { _ = stoppedTasks.remove(key) }
    }

    private func fail(_ task: WKURLSchemeTask, key: ObjectIdentifier) {
        guard !isStopped(key) else {
            forget(key)
            return
        }
        task.didFailWithError(URLError(.badURL))
        forget(key)
    }

    private static func mimeType(forExtension ext: String) -> String {
        switch ext {
        case "html", "htm":  return "text/html; charset=utf-8"
        case "js", "mjs":    return "text/javascript; charset=utf-8"
        case "css":          return "text/css; charset=utf-8"
        case "json", "map":  return "application/json; charset=utf-8"
        case "woff2":        return "font/woff2"
        case "woff":         return "font/woff"
        case "ttf":          return "font/ttf"
        case "otf":          return "font/otf"
        case "svg":          return "image/svg+xml"
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "txt":          return "text/plain; charset=utf-8"
        default:             return "application/octet-stream"
        }
    }
}

/// Hosts `Resources/math/mathfield.html` — the Symbolab-style keypad — and
/// bridges its two events back to SwiftUI.
struct MathFieldWebView: UIViewRepresentable {
    /// Seeded once, when the page reports ready. Never re-applied on every
    /// keystroke: `setValue` would fight the student's caret.
    let initialLatex: String
    let isArabic: Bool
    @Binding var latex: String
    var onSubmit: (String) -> Void
    @Binding var unavailable: Bool
    @Environment(\.colorScheme) private var colorScheme

    static let messageName = "droobMath"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(
            context.coordinator.assetHandler,
            forURLScheme: DroobMathAssetHandler.scheme)
        config.userContentController.add(context.coordinator, name: Self.messageName)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // The page keeps its own vertical scrolling — the pad can exceed a
        // short phone — but must never rubber-band against the sheet.
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = false

        context.coordinator.armWatchdog()
        // NOT `loadFileURL`: that is the null-origin case that breaks the fonts.
        webView.load(URLRequest(url: DroobMathAssetHandler.entryURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyThemeAndLanguageIfReady(to: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.disarmWatchdog()
        webView.stopLoading()
        webView.navigationDelegate = nil
        // The content controller retains its handlers — the same leak
        // `SolutionPDFExporter.detach` already documents for `printReady`.
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: messageName)
    }

    /// LaTeX is nothing but backslashes; it is never concatenated into JS.
    static func jsString(_ value: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
            let encoded = String(data: data, encoding: .utf8),
            encoded.count > 2
        else { return "\"\"" }
        return String(encoded.dropFirst().dropLast())
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MathFieldWebView
        let assetHandler = DroobMathAssetHandler()

        private var isReady = false
        private var hasFailed = false
        private var watchdog: DispatchWorkItem?
        private var appliedTheme: String?
        private var appliedLanguage: String?

        init(_ parent: MathFieldWebView) {
            self.parent = parent
        }

        /// A WebView old enough to choke on MathLive's syntax still fires
        /// `didFinish`, and a WebView that never gets that far fires nothing at
        /// all. Four seconds covers both.
        func armWatchdog() {
            disarmWatchdog()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.isReady else { return }
                self.markUnavailable()
            }
            watchdog = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
        }

        func disarmWatchdog() {
            watchdog?.cancel()
            watchdog = nil
        }

        private func markUnavailable() {
            guard !hasFailed else { return }
            hasFailed = true
            disarmWatchdog()
            parent.unavailable = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Not `didFinish` alone: the page can load and still be blank, with
            // `window.droobMath` undefined.
            let probe = """
            !!(window.droobMath && document.documentElement.getAttribute("data-ready") === "1")
            """
            webView.evaluateJavaScript(probe) { [weak self] value, _ in
                guard let self else { return }
                let ready = (value as? NSNumber)?.boolValue
                    ?? (value as? Bool)
                    ?? ((value as? String) == "true")
                guard ready else {
                    self.markUnavailable()
                    return
                }
                self.isReady = true
                self.disarmWatchdog()
                self.applyInitialState(to: webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            markUnavailable()
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            markUnavailable()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            markUnavailable()
        }

        /// `setLanguage` redraws the pad, so `setValue` follows it.
        private func applyInitialState(to webView: WKWebView) {
            let theme = parent.colorScheme == .dark ? "dark" : "light"
            let language = parent.isArabic ? "ar" : "en"
            appliedTheme = theme
            appliedLanguage = language

            let js = """
            window.droobMath.setTheme('\(theme)');
            window.droobMath.setLanguage('\(language)');
            window.droobMath.setValue(\(MathFieldWebView.jsString(parent.initialLatex)));
            window.droobMath.focus();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func applyThemeAndLanguageIfReady(to webView: WKWebView) {
            guard isReady else { return }
            let theme = parent.colorScheme == .dark ? "dark" : "light"
            let language = parent.isArabic ? "ar" : "en"

            var js = ""
            if theme != appliedTheme {
                appliedTheme = theme
                js += "window.droobMath.setTheme('\(theme)');"
            }
            if language != appliedLanguage {
                appliedLanguage = language
                js += "window.droobMath.setLanguage('\(language)');"
                js += "window.droobMath.setValue(\(MathFieldWebView.jsString(parent.latex)));"
            }
            guard !js.isEmpty else { return }
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard
                message.name == MathFieldWebView.messageName,
                let body = message.body as? [String: Any],
                let kind = body["kind"] as? String,
                let latex = body["latex"] as? String
            else { return }

            switch kind {
            case "change":
                parent.latex = latex
            case "submit":
                parent.onSubmit(latex)
            default:
                break
            }
        }
    }
}

// MARK: - Maths keyboard sheet

/// True while MathLive still holds an unfilled `#0` box.
///
/// This is `unfilled()` from mathfield.html — `v.indexOf("\\placeholder") !== -1`
/// — restated on the host side, deliberately, rather than asked of the page.
/// The page's own gate governs only the page's own Solve key: it disables it
/// and shows "Fill in the empty boxes first". Every *native* control that
/// commits the draft sits outside the WebView, and the `change` event has
/// already published the placeholder-bearing LaTeX by then. Without this
/// check, tapping the `∫ᵃᵇ` key and then "Add to message" writes
/// `$\int_{\placeholder{}}^{\placeholder{}} \placeholder{} \,d\placeholder{}$`
/// into the composer: KaTeX has no `\placeholder` macro, so the student's own
/// bubble renders as a red parse error, and the provider is asked to integrate
/// nothing.
///
/// Restated rather than round-tripped because the value is already here — the
/// host holds the same string the page would test — and an async
/// `evaluateJavaScript` cannot gate a synchronous `.disabled`.
private func mathHasUnfilledBox(_ latex: String) -> Bool {
    latex.contains("\\placeholder")
}

/// Whether a value typed into the keypad's plain-text fallback is still maths.
///
/// The fallback is what the sheet becomes when the WebView will not load, and it
/// is seeded with the LaTeX of the span the student tapped — so its Add button
/// reports `isLatex: false` for a field that usually contains a formula. Prose
/// is what the flag exists to protect against, and prose is what a non-ASCII
/// letter proves: "نصف" typed over `\frac{1}{2}` must not be handed to KaTeX. A
/// value already carrying a `$` is left alone too, so nothing here can raise the
/// number of unpairable dollars in the question.
private func reviewLooksLikeLatex(_ value: String) -> Bool {
    guard !value.contains("$") else { return false }
    return !value.contains { $0.isLetter && !$0.isASCII }
}

/// The keypad's chrome. The primary action is the page's own Solve key, which
/// lives inside the component; the secondary "Add to message" lives out here,
/// so it has to apply the same unfilled-box rule itself.
struct MathKeyboardSheet: View {
    @Binding var draft: String
    let isArabic: Bool
    /// Secondary: insert and close.
    ///
    /// The `Bool` is `isLatex`, and it is not cosmetic. When the WebView will
    /// not load, this sheet becomes a plain text field — and a student who types
    /// an Arabic sentence into it must not have that sentence wrapped in `$…$`
    /// and handed to KaTeX, which renders it as a red parse error. `true` only
    /// when the value came out of MathLive.
    var onAdd: (String, Bool) -> Void
    /// The page's Solve key: insert and commit.
    var onSubmit: (String, Bool) -> Void
    var onClose: () -> Void

    /// When the WebView will not load, the keyboard degrades to a plain text
    /// editor. It is an input mode, never a gate: there is no path here that
    /// ends in a blank screen or a disabled Send.
    @State private var unavailable = false

    private typealias S = AskDroobAIViewModel.Strings

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The same condition the page puts on its own Solve key.
    private var hasUnfilledBox: Bool { mathHasUnfilledBox(draft) }

    /// What every native commit control here is gated on.
    private var canCommit: Bool { !trimmedDraft.isEmpty && !hasUnfilledBox }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(S.mathSheetTitle(isArabic))
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel(S.close(isArabic))
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider()

            if unavailable {
                VStack(alignment: .leading, spacing: 10) {
                    Text(S.mathUnavailable(isArabic))
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField(S.mathSheetTitle(isArabic), text: $draft, axis: .vertical)
                        .lineLimit(4...12)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer(minLength: 0)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                MathFieldWebView(
                    initialLatex: draft,
                    isArabic: isArabic,
                    latex: $draft,
                    // Anything arriving from the page is LaTeX by construction.
                    onSubmit: { onSubmit($0, true) },
                    unavailable: $unavailable
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                // The page shows this under its own field; repeating it here
                // is what makes the disabled button legible rather than
                // mysterious, and it is the only explanation the fallback
                // editor ever gets.
                if hasUnfilledBox {
                    Text(S.mathFillBoxes(isArabic))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button {
                        onAdd(draft, !unavailable)
                    } label: {
                        // "إضافة إلى الرسالة" and "حل" share one row in the
                        // fallback state, and neither had a line limit.
                        Text(S.mathAddToMessage(isArabic))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundColor(canCommit ? .droobGold : .secondary)
                    }
                    .buttonStyle(.plain)
                    // Not `trimmedDraft.isEmpty` alone: a draft still holding
                    // an unfilled `#0` box is non-empty and would commit
                    // `\placeholder{}` into the composer.
                    .disabled(!canCommit)

                    Spacer()

                    // Only in the fallback: the page's Solve key went with the
                    // WebView, and the student must still be able to commit.
                    if unavailable {
                        Button {
                            // The page is gone, so whatever is in the field was
                            // typed as text, not composed as a formula.
                            onSubmit(draft, false)
                        } label: {
                            Text(S.mathSolve(isArabic))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(
                                    canCommit
                                        ? AnyShapeStyle(LinearGradient.droobBrand)
                                        : AnyShapeStyle(Color.gray))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canCommit)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Review sheet

/// Everything the scan produced, before a single question is spent.
struct ReviewSheetView: View {
    @ObservedObject var viewModel: AskDroobAIViewModel
    let locale: String

    @State private var editing: AskDroobAIViewModel.ReviewQuestion?

    private typealias S = AskDroobAIViewModel.Strings
    private var isArabic: Bool { locale == "ar" }

    /// What `confirmReview` will actually send: a row left blank is dropped.
    private var sendableCount: Int {
        viewModel.reviewQuestions
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if viewModel.reviewUndo != nil { undoBar }

            Divider()

            if viewModel.reviewQuestions.isEmpty {
                emptyState
            } else {
                questionList
            }

            Divider()
            footer
        }
        .background(Color(.systemBackground))
        .sheet(item: $editing) { question in
            ReviewEditSheet(
                initialText: question.text,
                isArabic: isArabic,
                onSave: { text in
                    viewModel.updateReviewQuestion(id: question.id, text: text)
                    editing = nil
                },
                onClose: {
                    // An untouched blank row added by "+ Add a question" is
                    // noise; drop it rather than leaving an empty card.
                    if question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        viewModel.deleteReviewQuestion(id: question.id)
                    }
                    editing = nil
                })
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(S.reviewTitle(isArabic))
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.cancelReview()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel(S.close(isArabic))
            }

            Text(S.reviewSubtitle(isArabic))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(S.reviewCount(isArabic, count: viewModel.reviewQuestions.count))
                .font(.caption2.weight(.medium))
                .foregroundColor(.droobGold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var undoBar: some View {
        HStack {
            Text(S.reviewDeleted(isArabic))
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button {
                viewModel.undoReviewDelete()
            } label: {
                Text(S.undo(isArabic))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.droobGold)
                    // The recovery path for a mis-tapped delete cannot itself
                    // be a 15 pt target that vanishes in four seconds.
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .background(Color(.secondarySystemBackground))
    }

    /// A `List` rather than a `LazyVStack`: it is UIKit-backed and disposes the
    /// rows that scroll away, which is what keeps a 40-question review from
    /// holding 40 live WKWebViews at once.
    private var questionList: some View {
        List {
            ForEach(Array(viewModel.reviewQuestions.enumerated()), id: \.element.id) { pair in
                ReviewQuestionCard(
                    index: pair.offset + 1,
                    question: pair.element,
                    isArabic: isArabic,
                    onEdit: { editing = pair.element },
                    onDelete: { viewModel.deleteReviewQuestion(id: pair.element.id) }
                )
                .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            addButton
                .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 20, trailing: 14))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// A scan that "adds wrong things" is the same scan that drops a question.
    private var addButton: some View {
        Button {
            let added = viewModel.addReviewQuestion()
            editing = added
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text(S.reviewAdd(isArabic))
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(.droobGold)
        }
        .buttonStyle(.borderless)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(S.reviewEmptyTitle(isArabic))
                .font(.subheadline.weight(.semibold))
            Text(S.reviewEmptyBody(isArabic))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            addButton
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var footer: some View {
        HStack {
            Button {
                viewModel.cancelReview()
            } label: {
                Text(S.cancel(isArabic))
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                viewModel.confirmReview()
            } label: {
                // "حل الكل (٤٠)" beside Cancel on one row, neither with a
                // line limit. At count >= 10 the Arabic label is at its longest.
                Text(S.reviewSolveAll(isArabic, count: sendableCount))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        sendableCount == 0
                            ? AnyShapeStyle(Color.gray)
                            : AnyShapeStyle(LinearGradient.droobBrand))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(sendableCount == 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

/// One extracted question, rendered through the same renderer the chat uses.
private struct ReviewQuestionCard: View {
    let index: Int
    let question: AskDroobAIViewModel.ReviewQuestion
    let isArabic: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var mathHeight: CGFloat = 20
    /// The card's WKWebView died — jettisoned content process, or a page that
    /// would not load. 29 cards is 29 web content processes, so this is not
    /// hypothetical, and a blank card on the correction screen is the worst
    /// possible failure: the student cannot read the question they are about
    /// to spend.
    @State private var renderFailed = false

    private typealias S = AskDroobAIViewModel.Strings

    /// The question as markdown the chat's renderer can typeset: delimiters
    /// normalised, a damaged span unwrapped, bare LaTeX wrapped, options one
    /// per line. A pure scan over a string that is at most a few hundred
    /// characters — cheaper than the layout pass that asks for it.
    private var rendered: String { reviewMarkdown(question.text) }

    /// The same string for the branches that are not markdown surfaces: the
    /// `\)` step 6 puts in front of a numeric option marker is invisible to
    /// `marked` and a literal backslash to `Text`.
    private var plain: String { reviewPlainText(rendered) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // `.buttonStyle(.borderless)` makes the hit area the label bounds,
            // and a `.subheadline` SF Symbol is about 16 pt square. Two of
            // those 14 pt apart, one of them destructive, is a tap on the
            // pencil that lands on the trash — and the only recovery is a
            // 4 s undo bar. The component this feature ships sets
            // `--tap: 44px` (mathfield.html) for the same reason; the frame +
            // content shape below is that floor, stated natively. The row is
            // laid out on the *frames*, so the two targets no longer abut.
            HStack(spacing: 4) {
                Text("\(index)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.droobGold)
                    .accessibilityLabel(S.reviewCardA11y(isArabic, number: index))

                Spacer()

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundColor(.droobGold)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(S.edit(isArabic))

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(S.delete(isArabic))
            }

            // Gated on the NORMALISED string, not the raw one. After
            // normalisation a card that has maths always carries `$…$`, so the
            // gate opens exactly when it should — and a genuinely prose-only
            // question still costs no WKWebView.
            if containsMath(rendered), !renderFailed {
                MathMarkdownView(
                    markdown: rendered,
                    textColor: .label,
                    backgroundColor: .secondarySystemBackground,
                    // An Arabic worksheet question is Arabic prose with LTR
                    // formulas in it; the page needs the base direction or the
                    // clauses come back reordered and the card mis-aligned
                    // against its prose-only neighbours.
                    isRTL: isArabic,
                    contentHeight: $mathHeight,
                    renderFailed: $renderFailed
                )
                .frame(height: max(20, mathHeight))
            } else {
                // Raw source, but readable and correctable — never a blank card.
                Text(plain)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground)))
    }
}

/// One formula the student can reach with the keypad.
private struct ReviewFormulaChip: Identifiable {
    /// Character offsets into the field text, delimiters included when there
    /// are any. Offsets rather than `String.Index`, because the range has to
    /// survive the presentation of a modal sheet and an index taken from one
    /// value of a `String` is undefined against another.
    let range: Range<Int>
    /// The interior, dollars stripped. This — and only this — crosses the
    /// bridge into MathLive.
    let latex: String
    /// `false` for a bare run the extraction never delimited. Tapping one
    /// delimits it first, so the keypad always edits a real span.
    let isDelimited: Bool

    var id: Int { range.lowerBound }
}

/// Editing one question.
///
/// The whole question stays in a native `TextField` and the maths keyboard edits
/// **one `$…$` span at a time**, chosen from the chip row. That split is the
/// point: MathLive is a formula editor, Arabic prose typed into it becomes
/// `\text{}` and its caret model fights RTL, while the system Arabic IME in a
/// `TextField` already works. The pencil's job is "fix this misread `\frac`
/// with the ∫ √ xⁿ keypad", which is a job about one span, not about the
/// sentence — so prose never crosses the bridge in either direction.
struct ReviewEditSheet: View {
    let isArabic: Bool
    var onSave: (String) -> Void
    var onClose: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var text: String
    @State private var showMath = false
    @State private var mathDraft = ""
    /// The span the keypad was opened on. `nil` is "+ معادلة جديدة", which
    /// appends — today's behaviour, kept.
    @State private var editingRange: Range<Int>?
    /// The debounced copy the preview renders, so a WKWebView is not re-rendered
    /// on every keystroke.
    @State private var previewSource: String
    @State private var previewHeight: CGFloat = 20
    /// The preview's WebView died; the sheet keeps working on the source.
    @State private var previewFailed = false

    private typealias S = AskDroobAIViewModel.Strings

    init(
        initialText: String,
        isArabic: Bool,
        onSave: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        _text = State(initialValue: initialText)
        _previewSource = State(initialValue: initialText)
        self.isArabic = isArabic
        self.onSave = onSave
        self.onClose = onClose
    }

    /// Recomputed from the CURRENT field text every time the row is laid out.
    /// A range captured when the sheet opened would already have moved by the
    /// time the student edits a word of the prose first.
    private var chips: [ReviewFormulaChip] {
        let chars = Array(text)
        var out: [ReviewFormulaChip] = []

        for range in reviewMathSpans(text) where range.upperBound <= chars.count {
            let raw = Array(chars[range])
            let strip = (raw.count >= 4 && raw[0] == "$" && raw[1] == "$") ? 2 : 1
            guard raw.count > strip * 2 else { continue }
            out.append(ReviewFormulaChip(
                range: range,
                latex: String(raw.dropFirst(strip).dropLast(strip)),
                isDelimited: true))
        }
        for range in reviewBareLatexRuns(text) where range.upperBound <= chars.count {
            out.append(ReviewFormulaChip(
                range: range,
                latex: String(chars[range]),
                isDelimited: false))
        }
        return out.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private var previewMarkdown: String { reviewMarkdown(previewSource) }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(S.reviewEditTitle(isArabic))
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel(S.close(isArabic))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(S.reviewEditHint(isArabic), text: $text, axis: .vertical)
                        .lineLimit(4...14)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)

                    formulaRow
                    preview
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button {
                    onSave(text)
                } label: {
                    Text(S.save(isArabic))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(LinearGradient.droobBrand)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        // Debounced, and deliberately not with `try?`: a cancelled sleep means
        // the student typed again, and publishing the stale text there would
        // make the preview lag one keystroke behind for ever.
        .task(id: text) {
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
            } catch {
                return
            }
            previewSource = text
        }
        // In this host Solve and "Add to message" collapse into the same
        // action. Both stay visible so the component is not re-skinned per host.
        .droobAdaptiveSheet(
            isPresented: $showMath,
            regularWidth: horizontalSizeClass == .regular,
            detents: [.fraction(0.75), .large]
        ) {
            MathKeyboardSheet(
                draft: $mathDraft,
                isArabic: isArabic,
                onAdd: { commitFormula($0, isLatex: $1) },
                onSubmit: { commitFormula($0, isLatex: $1) },
                onClose: {
                    showMath = false
                    editingRange = nil
                    mathDraft = ""
                })
        }
    }

    // MARK: The chip row

    @ViewBuilder
    private var formulaRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(S.editFormulasHeading(isArabic))
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            let items = chips
            if items.isEmpty {
                Text(S.editNoFormula(isArabic))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { chip in
                        Button {
                            edit(chip)
                        } label: {
                            Text(chipLabel(chip.latex))
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .foregroundColor(.droobGold)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 34)
                                .background(
                                    Capsule().stroke(
                                        Color.droobGold.opacity(chip.isDelimited ? 0.7 : 0.35),
                                        lineWidth: 1))
                                // A formula is always left-to-right, even in an
                                // Arabic sheet: `x^2` must not read `2^x`.
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(S.editFormulaChipA11y(isArabic))
                    }

                    Button {
                        editingRange = nil
                        mathDraft = ""
                        showMath = true
                    } label: {
                        Text(S.editNewFormula(isArabic))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .foregroundColor(.droobGold)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(Color.droobGold.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The chip's face: the formula without its LaTeX scaffolding, short enough
    /// to sit in a row of them.
    private func chipLabel(_ latex: String) -> String {
        var stripped = ""
        for c in latex where c != "\\" && c != "{" && c != "}" {
            stripped.append(c)
        }
        let squashed = stripped.split(separator: " ").joined(separator: " ")
        let shown = squashed.isEmpty ? latex : squashed
        return shown.count <= 18 ? shown : String(shown.prefix(18)) + "…"
    }

    // MARK: The preview

    @ViewBuilder
    private var preview: some View {
        if containsMath(previewMarkdown) {
            VStack(alignment: .leading, spacing: 6) {
                Text(S.editPreviewHeading(isArabic))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Group {
                    if previewFailed {
                        // Same rule as the card: the source, not a blank box.
                        Text(reviewPlainText(previewMarkdown))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        MathMarkdownView(
                            markdown: previewMarkdown,
                            textColor: .label,
                            backgroundColor: .secondarySystemBackground,
                            isRTL: isArabic,
                            contentHeight: $previewHeight,
                            renderFailed: $previewFailed
                        )
                        .frame(height: max(20, previewHeight))
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Opening and committing

    private func edit(_ chip: ReviewFormulaChip) {
        if chip.isDelimited {
            editingRange = chip.range
        } else {
            // Delimit the run in place first, so what the keypad edits and what
            // it replaces are the same span. Inserting from the back keeps the
            // lower offset valid.
            var chars = Array(text)
            guard chip.range.upperBound <= chars.count else { return }
            chars.insert("$", at: chip.range.upperBound)
            chars.insert("$", at: chip.range.lowerBound)
            text = String(chars)
            editingRange = chip.range.lowerBound..<(chip.range.upperBound + 2)
        }
        mathDraft = chip.latex
        showMath = true
    }

    /// Replaces exactly the span the chip opened, or appends when the student
    /// asked for a new formula.
    ///
    /// `isLatex` is false when the WebView died and the sheet degraded to a
    /// plain text field: a sentence typed there is prose, not a formula, and
    /// wrapping it in dollars would hand Arabic to KaTeX. It is NOT, on its own,
    /// permission to drop the delimiters off the span being replaced — that
    /// field is seeded with the chip's own LaTeX, so the ordinary fallback case
    /// is a student fixing `\frac{\sqrt{2}}{2}` by hand, and replacing
    /// `$\frac{\sqrt{2}}{2}$` with an undelimited copy would silently un-typeset
    /// a formula they never touched, in the bubble and in the exported sheet
    /// both. When the target is a span, `reviewLooksLikeLatex` decides: a value
    /// still made of maths keeps the delimiters the span already carried,
    /// however wide they were; a value holding prose replaces the whole span.
    private func commitFormula(_ value: String, isLatex: Bool) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = editingRange
        showMath = false
        editingRange = nil
        mathDraft = ""

        guard !trimmed.isEmpty else { return }
        // The keypad's own Solve key is already gated on this; stated again
        // where the value lands, because this is the one step that exists to
        // make a question correct before it is spent.
        if isLatex && mathHasUnfilledBox(trimmed) { return }

        var chars = Array(text)
        if let range, range.lowerBound <= range.upperBound, range.upperBound <= chars.count {
            // `edit(_:)` only ever points this at a delimited span — a bare run
            // is delimited in place first — so the delimiters are read back off
            // the text rather than assumed, and a `$$…$$` block stays display.
            let existing = Array(chars[range])
            let delimiter = (existing.count >= 4 && existing[0] == "$" && existing[1] == "$")
                ? "$$"
                : "$"
            let keepDelimited = isLatex || reviewLooksLikeLatex(trimmed)
            let replacement = keepDelimited ? delimiter + trimmed + delimiter : trimmed
            chars.replaceSubrange(range, with: Array(replacement))
            text = String(chars)
            return
        }

        let replacement = isLatex ? "$" + trimmed + "$" : trimmed

        if text.isEmpty {
            text = replacement
        } else if let last = text.last, !last.isWhitespace {
            text += " " + replacement
        } else {
            text += replacement
        }
    }
}

// MARK: - Reading the exported sheet

/// The solutions PDF, in the app, before it goes anywhere.
///
/// Reuse rather than a new reader, and `QuickLookPreview` rather than
/// `LessonPDFReaderView`. `QLPreviewController` already ships in this feature —
/// `AskDroobLibraryView.swift` shows stored scans through it — renders a PDF
/// natively with paging, zoom and text selection, and costs nothing to keep.
/// `LessonPDFReaderView` is 1600 lines welded to `LessonPlayerViewModel`, lesson
/// notes and the backend reading-progress endpoint; a locally generated
/// solutions sheet has no lesson, no document id and no progress to report, so
/// reusing it would mean fabricating three ids to satisfy an `init`.
///
/// Lives inside this file on purpose: `project.pbxproj` is objectVersion 56 with
/// no filesystem-synchronised groups, so a new `.swift` file has to be
/// registered in four places or it compiles to nothing, silently.
struct SolutionPreviewSheet: View {
    let url: URL
    let isArabic: Bool
    var onClose: () -> Void

    @State private var share: LibraryShareItem?

    private typealias S = AskDroobAIViewModel.Strings

    var body: some View {
        NavigationStack {
            QuickLookPreview(url: url)
                .ignoresSafeArea()
                .navigationTitle(S.previewTitle(isArabic))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(S.close(isArabic)) { onClose() }
                            .foregroundColor(.droobGold)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            share = LibraryShareItem(url: url)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.droobGold)
                        }
                        .accessibilityLabel(S.previewShareA11y(isArabic))
                    }
                }
                .sheet(item: $share) { item in
                    ActivityShareSheet(activityItems: [item.url])
                }
        }
    }
}

// MARK: - Preview

struct AskDroobAIView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AskDroobAIView()
        }
    }
}
