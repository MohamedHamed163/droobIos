import Foundation

// MARK: - Chat message model

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    var text: String
    var sources: [TutorSource]
    var sessionId: String?
    var isStreaming: Bool

    enum Role { case user, assistant }

    init(id: UUID = UUID(), role: Role, text: String, sources: [TutorSource] = [], sessionId: String? = nil, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.sources = sources
        self.sessionId = sessionId
        self.isStreaming = isStreaming
    }
}

// MARK: - Ask request body

struct AskRequest: Encodable {
    let courseId: String
    let question: String
    enum CodingKeys: String, CodingKey {
        case courseId = "course_id"
        case question
    }
}

// MARK: - Buffered response

struct TutorAnswer: Decodable {
    let answer: String
    let sources: [TutorSource]
    let sessionId: String?
    enum CodingKeys: String, CodingKey {
        case answer
        case sources
        case sessionId = "turnId"
    }

    /// Hand-rolled so an omitted `sources` array decodes as empty rather than
    /// throwing. The synthesized initializer required it, which meant an
    /// ungrounded answer — a perfectly ordinary response — failed the whole
    /// call. That went unnoticed while this screen was unreachable; it is
    /// user-facing now.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answer = try c.decodeIfPresent(String.self, forKey: .answer) ?? ""
        sources = try c.decodeIfPresent([TutorSource].self, forKey: .sources) ?? []
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
    }
}

// MARK: - Feedback request

struct FeedbackRequest: Encodable {
    let sessionId: String
    let rating: String
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case rating
    }
}

// MARK: - ChatViewModel

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = true
    @Published var isSending: Bool = false
    @Published var errorMessage: String? = nil
    @Published var enrolledCourses: [CourseSummary] = []
    @Published var selectedCourse: CourseSummary? = nil
    @Published var isLoadingCourses: Bool = false

    private var streamingTask: Task<Void, Never>? = nil

    init(preselectedCourseId: String? = nil) {
        Task {
            await loadEnrolledCourses(selectId: preselectedCourseId)
        }
    }

    // MARK: - Load enrolled courses

    func loadEnrolledCourses(selectId: String? = nil) async {
        isLoadingCourses = true
        let request = APIRequest(path: "/v1/student/enrollments", method: .GET)
        do {
            let result: [CourseSummary] = try await AuthInterceptor.shared.execute(request)
            enrolledCourses = result
            if let id = selectId, let course = result.first(where: { $0.id == id }) {
                selectedCourse = course
            } else if selectedCourse == nil {
                selectedCourse = result.first
            }
        } catch {
            // Non-fatal: user can still see empty list
        }
        isLoadingCourses = false
    }

    // MARK: - Send

    /// Starts a turn and *keeps* the task. `cancelStreaming` had nothing to
    /// cancel before, which was harmless while this screen was unreachable;
    /// it is a live Stop button now that the multi-model ask view links here.
    func send() {
        guard !isSending else { return }
        // No-op when the previous turn already finished; it only matters if
        // one somehow outlived its Stop.
        streamingTask?.cancel()
        streamingTask = Task { [weak self] in
            await self?.performSend()
        }
    }

    private func performSend() async {
        guard let course = selectedCourse else {
            errorMessage = L10n.aiTutorErrorSelectCourse
            return
        }
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }

        inputText = ""
        errorMessage = nil
        isSending = true

        // Add user message
        messages.append(ChatMessage(role: .user, text: question))

        if isStreaming {
            await sendStreaming(courseId: course.id, question: question)
        } else {
            await sendBuffered(courseId: course.id, question: question)
        }

        isSending = false
    }

    // MARK: - Buffered

    private func sendBuffered(courseId: String, question: String) async {
        let body = AskRequest(courseId: courseId, question: question)
        let request = APIRequest(path: "/v1/ai-tutor/ask", method: .POST, body: body,
                                 headers: localeHeaders)
        do {
            let answer: TutorAnswer = try await AuthInterceptor.shared.execute(request)
            messages.append(ChatMessage(
                role: .assistant,
                text: answer.answer,
                sources: answer.sources,
                sessionId: answer.sessionId
            ))
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = error.errorDescription
                messages.append(ChatMessage(
                    role: .assistant,
                    text: L10n.aiTutorError(error.errorDescription ?? L10n.aiTutorErrorUnknown)))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Streaming

    private func sendStreaming(courseId: String, question: String) async {
        // Create placeholder assistant message
        let assistantId = UUID()
        var assistantMessage = ChatMessage(id: assistantId, role: .assistant, text: "", isStreaming: true)
        messages.append(assistantMessage)

        guard let messageIndex = messages.firstIndex(where: { $0.id == assistantId }) else { return }

        // Build request
        let body = AskRequest(courseId: courseId, question: question)

        let baseURLString = (Bundle.main.object(forInfoDictionaryKey: "DROOB_API_BASE_URL") as? String)
            ?? ProcessInfo.processInfo.environment["DROOB_API_BASE_URL"]
            ?? "http://localhost:9080"
        guard let baseURL = URL(string: baseURLString) else {
            messages[messageIndex].text = L10n.aiTutorErrorConfig
            messages[messageIndex].isStreaming = false
            return
        }

        let url = baseURL.appendingPathComponent("v1/ai-tutor/ask/stream")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // This path builds its own URLRequest, so it has to carry the app
        // language itself — otherwise the tutor answers in the *device*
        // language while the multi-model screen answers in the app's.
        for (field, value) in localeHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(body)
        } catch {
            messages[messageIndex].text = L10n.aiTutorErrorEncoding
            messages[messageIndex].isStreaming = false
            return
        }

        do {
            let bytes = try await AuthInterceptor.shared.executeBytes(for: urlRequest)
            for await event in SSEParser.stream(from: bytes) {
                // Stop was tapped: leave the loop instead of appending
                // tokens into a message the user has already dismissed.
                if Task.isCancelled { break }
                switch event {
                case .token(let chunk):
                    messages[messageIndex].text += chunk
                case .sources(let srcs):
                    messages[messageIndex].sources = srcs
                case .done(let sessionId):
                    messages[messageIndex].sessionId = sessionId
                    messages[messageIndex].isStreaming = false
                case .error(let msg):
                    messages[messageIndex].text += L10n.aiTutorStreamErrorInline(msg)
                    messages[messageIndex].isStreaming = false
                }
            }
            // Ensure streaming flag is cleared
            if messageIndex < messages.count {
                messages[messageIndex].isStreaming = false
            }
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                if messageIndex < messages.count {
                    messages[messageIndex].text = error.errorDescription ?? L10n.aiTutorErrorStream
                    messages[messageIndex].isStreaming = false
                }
            }
        } catch {
            if messageIndex < messages.count {
                messages[messageIndex].text = error.localizedDescription
                messages[messageIndex].isStreaming = false
            }
        }
    }

    // MARK: - Feedback

    func submitFeedback(sessionId: String, rating: String) async {
        let body = FeedbackRequest(sessionId: sessionId, rating: rating)
        let request = APIRequest(path: "/v1/ai-tutor/feedback", method: .POST, body: body,
                                 headers: localeHeaders)
        _ = try? await AuthInterceptor.shared.execute(request) as EmptyResponse
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        if let index = messages.indices.last, messages[index].isStreaming {
            messages[index].isStreaming = false
        }
        isSending = false
    }

    // MARK: - Headers

    /// Same rule as the multi-model screen: the tutor answers in the
    /// `Accept-Language` it is given, and the app's language is a user
    /// setting that can differ from the device's.
    private var localeHeaders: [String: String] {
        ["Accept-Language": L10n.currentLanguageCode]
    }
}

// ─────────────────────────────────────────────────────────────────────
// Multi-model AI tutor
//
// Everything below backs `AiTutorAskView` (in ChatView.swift). It lives in
// this file rather than a new one because the Xcode project has no
// filesystem-synchronized group: a new .swift file on disk is NOT compiled
// until it is hand-added to project.pbxproj, and a missing entry fails as
// "undefined symbol" at link time — invisible to a source-level type check.
// Same reasoning as the note at the bottom of L10n.swift.
// ─────────────────────────────────────────────────────────────────────

// MARK: - Multi-model wire models

/// One model the student can pick. `name` is already localised
/// server-side off `Accept-Language` — never translate it client-side.
struct AiTutorModel: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let provider: String
    let supportsVision: Bool
    let isFastDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, provider
        case supportsVision = "supports_vision"
        case isFastDefault  = "is_fast_default"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Lenient for the same reason as the answer rows: one malformed entry in
        // the roster must not blank the entire model picker. An id-less row is
        // filtered out by the caller.
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name)
            ?? (id.isEmpty ? L10n.aiMultiUnknownModel : id)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        supportsVision = try c.decodeIfPresent(Bool.self, forKey: .supportsVision) ?? false
        isFastDefault = try c.decodeIfPresent(Bool.self, forKey: .isFastDefault) ?? false
    }
}

/// Per-model outcome of one fan-out. Anything other than `.ok` is a
/// *normal* result on free-tier upstreams, not an error — see
/// `AiTutorMultiViewModel.performAsk`.
enum AiTutorAnswerStatus: String, Decodable {
    case ok          = "OK"
    case timeout     = "TIMEOUT"
    case rateLimited = "RATE_LIMITED"
    case error       = "ERROR"

    /// An unrecognised status decodes as `.error` instead of throwing. A
    /// status the server adds later must degrade one card, never blank
    /// out the whole answer set.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AiTutorAnswerStatus(rawValue: raw.uppercased()) ?? .error
    }

    /// Short label for the failure card's badge.
    var failureLabel: String {
        switch self {
        case .ok:          return ""
        case .timeout:     return L10n.aiMultiStatusTimeout
        case .rateLimited: return L10n.aiMultiStatusRateLimited
        case .error:       return L10n.aiMultiStatusError
        }
    }

    /// One-line explanation under the badge, so a student who picked 5
    /// models and got 3 answers understands what happened to the other 2.
    var failureHint: String {
        switch self {
        case .ok:          return ""
        case .timeout:     return L10n.aiMultiStatusTimeoutHint
        case .rateLimited: return L10n.aiMultiStatusRateLimitedHint
        case .error:       return L10n.aiMultiStatusErrorHint
        }
    }

    var failureIcon: String {
        switch self {
        case .ok:          return "checkmark.circle"
        case .timeout:     return "clock.badge.exclamationmark"
        case .rateLimited: return "gauge.with.dots.needle.bottom.50percent"
        case .error:       return "exclamationmark.triangle"
        }
    }
}

struct AiTutorAnswer: Decodable, Identifiable, Equatable {
    let modelId: String
    let modelName: String
    let status: AiTutorAnswerStatus
    let answer: String?
    let latencyMs: Int?
    let isBest: Bool

    var id: String { modelId }

    /// A card is renderable only if the model both reported OK *and*
    /// actually returned prose. An OK-with-empty-body is treated as a
    /// failure card rather than a blank answer.
    var isSuccess: Bool {
        status == .ok
            && !(answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case modelId   = "model_id"
        case modelName = "model_name"
        case status, answer
        case latencyMs = "latency_ms"
        case isBest    = "is_best"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Every field here is lenient on purpose. A failed model is a *normal*
        // result in this response, and a degenerate row is most likely exactly
        // when an upstream misbehaved — so throwing here would discard all the
        // answers that DID succeed alongside it. A row with no usable id is
        // dropped by the caller instead of taking the response down with it.
        modelId = try c.decodeIfPresent(String.self, forKey: .modelId) ?? ""
        modelName = try c.decodeIfPresent(String.self, forKey: .modelName)
            ?? (modelId.isEmpty ? L10n.aiMultiUnknownModel : modelId)
        status = try c.decodeIfPresent(AiTutorAnswerStatus.self, forKey: .status) ?? .error
        answer = try c.decodeIfPresent(String.self, forKey: .answer)
        latencyMs = try c.decodeIfPresent(Int.self, forKey: .latencyMs)
        // `is_best` is null in FAST mode always, and in DEEP whenever the
        // judge model itself got rate-limited. Null means "no badge".
        isBest = try c.decodeIfPresent(Bool.self, forKey: .isBest) ?? false
    }

    /// Latency rendered with the app locale's digits and decimal
    /// separator. Nil when the server didn't report one.
    func latencyText(locale: String) -> String? {
        guard let latencyMs, latencyMs > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let seconds = Double(latencyMs) / 1000.0
        guard let text = formatter.string(from: NSNumber(value: seconds)) else { return nil }
        return L10n.aiMultiLatency(text)
    }
}

struct AiTutorMultiResponse: Decodable {
    let turnId: String?
    let mode: String
    let answers: [AiTutorAnswer]
    let bestModelId: String?
    let bestRationale: String?

    enum CodingKeys: String, CodingKey {
        case turnId        = "turn_id"
        case mode, answers
        case bestModelId   = "best_model_id"
        case bestRationale = "best_rationale"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Optional like every other field here: `turn_id` only feeds the
        // fire-and-forget rating call (`rate` guards on it), so a missing or
        // null one must not throw away a complete set of answers.
        turnId = try c.decodeIfPresent(String.self, forKey: .turnId)
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? ""
        // Drop rows the server could not identify. Decoding is lenient so one
        // degenerate row cannot throw away the answers that succeeded, and this
        // is where such a row is discarded — an answer with no model id has
        // nothing to label a card with and nothing to rate against.
        answers = (try c.decodeIfPresent([AiTutorAnswer].self, forKey: .answers) ?? [])
            .filter { !$0.modelId.isEmpty }
        bestModelId = try c.decodeIfPresent(String.self, forKey: .bestModelId)
        bestRationale = try c.decodeIfPresent(String.self, forKey: .bestRationale)
    }
}

struct AiTutorMultiAskRequest: Encodable {
    let courseId: String
    let question: String
    let mode: String
    let modelIds: [String]
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case courseId = "course_id"
        case question, mode
        case modelIds = "model_ids"
        case imageUrl = "image_url"
    }
}

struct AiTutorMultiRateRequest: Encodable {
    let turnId: String
    let modelId: String
    let rating: String

    enum CodingKeys: String, CodingKey {
        case turnId  = "turn_id"
        case modelId = "model_id"
        case rating
    }
}

// MARK: - Ask mode

enum AiTutorAskMode: String, CaseIterable, Identifiable {
    case fast = "FAST"
    case deep = "DEEP"

    var id: String { rawValue }

    var label: String {
        self == .fast ? L10n.aiMultiModeFast : L10n.aiMultiModeDeep
    }

    var hint: String {
        self == .fast ? L10n.aiMultiModeFastHint : L10n.aiMultiModeDeepHint
    }

    /// Upper bound on hand-picked models. FAST is a single-model path by
    /// definition; DEEP caps hand-picking at 3 (past that the student is
    /// really asking for "Compare all").
    var maxPickedModels: Int { self == .fast ? 1 : 3 }

    /// Rough worst case, used *only* to give the waiting bar a
    /// determinate feel. It never times the request out — the request's
    /// own deadline does that.
    var expectedSeconds: Double { self == .fast ? 8 : 30 }

    /// Client-side deadline for one ask, passed as `APIRequest.timeout`.
    /// `/multi/ask` is not streamed — nothing arrives until the whole
    /// fan-out finishes — so this has to clear the server's worst case
    /// (`expectedSeconds`) with room for a slow network, not sit on it.
    /// The shared session's 30 s would kill a legitimate DEEP answer.
    var requestTimeout: TimeInterval { self == .fast ? 45 : 90 }
}

// MARK: - AiTutorMultiViewModel

@MainActor
final class AiTutorMultiViewModel: ObservableObject {
    let courseId: String

    // Composer state
    @Published var question: String = ""
    @Published private(set) var mode: AiTutorAskMode = .fast
    @Published private(set) var compareAll: Bool = false
    /// Ordered so "first pick wins" when the cap shrinks (Deep → Fast).
    @Published private(set) var selectedModelIds: [String] = []

    // Roster
    @Published private(set) var models: [AiTutorModel] = []
    @Published private(set) var isLoadingModels = false
    @Published private(set) var modelsError: String?

    // In-flight ask
    @Published private(set) var isAsking = false
    @Published private(set) var pendingModelNames: [String] = []
    @Published private(set) var elapsed: Double = 0

    // Result
    @Published private(set) var answers: [AiTutorAnswer] = []
    @Published private(set) var bestModelId: String?
    @Published private(set) var bestRationale: String?
    @Published private(set) var turnId: String?
    @Published private(set) var ratings: [String: String] = [:]

    // Photo attachment
    @Published private(set) var imageData: Data?
    @Published private(set) var imageUrl: String?
    @Published private(set) var isUploadingImage = false

    @Published var errorMessage: String?

    private var askTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    init(courseId: String) {
        self.courseId = courseId
    }

    // MARK: Derived state

    var hasImage: Bool { imageData != nil }

    /// Number of successfully-answered cards, for the "N of M answered"
    /// summary. Failed cards stay in `answers` on purpose.
    var okCount: Int { answers.filter(\.isSuccess).count }

    /// True for the card the judge picked. Falls back to the per-answer
    /// flag when the server sent `best_model_id` only, and is false for
    /// every card when both are null (FAST, or a rate-limited judge) —
    /// which is exactly "render no badge".
    func isWinner(_ answer: AiTutorAnswer) -> Bool {
        if let bestModelId { return answer.modelId == bestModelId }
        return answer.isBest
    }

    /// Headline for the waiting state. With no named models — DEEP with no
    /// picks, or a roster that never loaded — the server chooses and we
    /// don't know the count, so say that rather than claim "1 model".
    var waitingTitle: String {
        pendingModelNames.isEmpty
            ? L10n.aiMultiWaitingTitleUnknown
            : L10n.aiMultiWaitingTitle(pendingModelNames.count)
    }

    /// 0…0.95. Deliberately never reaches 1 while we're still waiting, so
    /// the bar reads "still working" rather than "finished but stuck".
    var waitingProgress: Double {
        min(elapsed / mode.expectedSeconds, 0.95)
    }

    /// One-line description of the current model choice, shown on the
    /// row that opens the picker.
    var modelSummary: String {
        if mode == .deep, compareAll { return L10n.aiMultiModelsCompareAll }
        if selectedModelIds.isEmpty { return L10n.aiMultiModelsAuto }
        if selectedModelIds.count == 1,
           let picked = models.first(where: { $0.id == selectedModelIds[0] }) {
            return picked.name
        }
        return L10n.aiMultiModelsSelected(selectedModelIds.count)
    }

    var canAsk: Bool {
        !isAsking
            && !isUploadingImage
            && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isSelectionAtCap: Bool {
        selectedModelIds.count >= mode.maxPickedModels
    }

    func isSelected(_ model: AiTutorModel) -> Bool {
        selectedModelIds.contains(model.id)
    }

    // MARK: Selection

    func setMode(_ newMode: AiTutorAskMode) {
        guard newMode != mode else { return }
        mode = newMode
        if newMode == .fast {
            // "Compare all" is a DEEP-only affordance, and FAST asks one
            // model — keep the student's first pick and drop the rest.
            compareAll = false
            selectedModelIds = Array(selectedModelIds.prefix(mode.maxPickedModels))
        }
    }

    func setCompareAll(_ on: Bool) {
        guard mode == .deep else { return }
        compareAll = on
        if on { selectedModelIds = [] }
    }

    func toggle(_ model: AiTutorModel) {
        if let index = selectedModelIds.firstIndex(of: model.id) {
            selectedModelIds.remove(at: index)
            return
        }
        if selectedModelIds.count >= mode.maxPickedModels {
            // FAST is single-select: tapping another row should swap, which
            // is what a radio-style list feels like. DEEP holds at the cap.
            if mode == .fast { selectedModelIds = [model.id] }
            compareAll = false
            return
        }
        selectedModelIds.append(model.id)
        compareAll = false
    }

    // MARK: Roster

    func loadModels() async {
        isLoadingModels = true
        modelsError = nil
        let request = APIRequest(
            path: "/v1/ai-tutor/multi/models",
            method: .GET,
            // A photo narrows the roster to models that can actually read it.
            queryItems: [URLQueryItem(name: "with_vision",
                                      value: hasImage ? "true" : "false")],
            headers: localeHeaders)
        do {
            // Same leniency contract as the answer rows: decoding never throws
            // on a malformed entry, so an unusable one is filtered here rather
            // than blanking the whole picker.
            let decoded: [AiTutorModel] = try await AuthInterceptor.shared.execute(request)
            models = decoded.filter { !$0.id.isEmpty }
            pruneSelection()
        } catch is CancellationError {
            // Screen went away mid-load; nothing to report.
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                AuthSession.shared.handleUnauthenticated()
            } else {
                modelsError = error.errorDescription ?? L10n.aiMultiModelsError
            }
        } catch {
            modelsError = L10n.aiMultiModelsError
        }
        isLoadingModels = false
    }

    /// Drops selections the current roster no longer offers (which happens
    /// the moment a photo shrinks the list to vision-capable models) and
    /// re-applies the cap.
    private func pruneSelection() {
        let available = Set(models.map(\.id))
        selectedModelIds = selectedModelIds.filter { available.contains($0) }
        if selectedModelIds.count > mode.maxPickedModels {
            selectedModelIds = Array(selectedModelIds.prefix(mode.maxPickedModels))
        }
    }

    // MARK: Ask

    func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = L10n.aiMultiErrorEmptyQuestion
            return
        }
        guard !isAsking, !isUploadingImage else { return }

        let ids = effectiveModelIds()
        errorMessage = nil
        answers = []
        bestModelId = nil
        bestRationale = nil
        turnId = nil
        ratings = [:]
        pendingModelNames = plannedModelNames(ids: ids)
        elapsed = 0
        isAsking = true
        startTicker()

        askTask = Task { [weak self] in
            await self?.performAsk(text: text, modelIds: ids)
        }
    }

    func cancelAsk() {
        askTask?.cancel()
        askTask = nil
        finishAsking()
    }

    private func performAsk(text: String, modelIds ids: [String]) async {
        let body = AiTutorMultiAskRequest(
            courseId: courseId,
            question: text,
            mode: mode.rawValue,
            modelIds: ids,
            imageUrl: imageUrl)
        let request = APIRequest(
            path: "/v1/ai-tutor/multi/ask",
            method: .POST,
            body: body,
            headers: localeHeaders,
            timeout: mode.requestTimeout)
        do {
            let result: AiTutorMultiResponse = try await AuthInterceptor.shared.execute(request)
            guard !Task.isCancelled else { finishAsking(); return }
            turnId = result.turnId
            bestModelId = result.bestModelId
            bestRationale = result.bestRationale
            // Partial failure is the NORMAL case on free-tier upstreams: a
            // DEEP fan-out routinely comes back 8 OK / 2 failed. Every card
            // is kept — a student who picked 5 models and saw 3 cards would
            // reasonably conclude the app is broken. We only reorder: the
            // winner first, then the answers that worked, then the failures.
            answers = result.answers.enumerated()
                .sorted { lhs, rhs in
                    let lw = isWinner(lhs.element), rw = isWinner(rhs.element)
                    if lw != rw { return lw }
                    if lhs.element.isSuccess != rhs.element.isSuccess {
                        return lhs.element.isSuccess
                    }
                    // Stable within a bucket — keep the server's order.
                    return lhs.offset < rhs.offset
                }
                .map(\.element)
            if answers.isEmpty { errorMessage = L10n.aiMultiErrorAllFailed }
        } catch is CancellationError {
            // Student hit Stop — no banner, they know.
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                AuthSession.shared.handleUnauthenticated()
            } else if case .serverError = error {
                // The backend answers 503 only when NOTHING succeeded; that
                // is the one shape that's genuinely an error.
                errorMessage = L10n.aiMultiErrorAllFailed
            } else {
                errorMessage = error.errorDescription ?? L10n.aiMultiErrorGeneric
            }
        } catch {
            errorMessage = L10n.aiMultiErrorGeneric
        }
        finishAsking()
    }

    private func finishAsking() {
        isAsking = false
        pendingModelNames = []
        tickTask?.cancel()
        tickTask = nil
    }

    /// Drives the waiting bar. The endpoint is not streamed — every answer
    /// lands at once — so there is no real progress to report; this gives
    /// the wait a determinate *feel* without a 30-second blocking spinner.
    ///
    /// Ticks at 2 Hz, not 10: `elapsed` is `@Published` on the view's
    /// `@StateObject`, so every write re-evaluates the whole body —
    /// including the composer's live `TextField` — and the bar it feeds
    /// spans 30 s, where 2 Hz is visually identical to 10 Hz.
    private func startTicker() {
        tickTask?.cancel()
        let started = Date()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !Task.isCancelled else { return }
                self.elapsed = Date().timeIntervalSince(started)
            }
        }
    }

    /// Empty means "let the server decide".
    private func effectiveModelIds() -> [String] {
        switch mode {
        case .fast:
            return Array(selectedModelIds.prefix(mode.maxPickedModels))
        case .deep:
            guard compareAll else {
                // No explicit picks means "let Droob choose" — which is what
                // the model-summary row says, and what FAST already does.
                // Falling through to the whole roster here fanned out to
                // every model a student never asked for, burning free-tier
                // quota on the slowest path. Full fan-out is "Compare all",
                // an explicit choice.
                return Array(selectedModelIds.prefix(mode.maxPickedModels))
            }
            // "Compare all" — send the roster explicitly rather than an empty
            // array, so the waiting state can name every model we're actually
            // asking. Falls back to server choice if the roster never loaded.
            return models.map(\.id)
        }
    }

    private func plannedModelNames(ids: [String]) -> [String] {
        if ids.isEmpty {
            // Server picks. In FAST we can still name the advertised default;
            // otherwise we say nothing rather than invent model names.
            if mode == .fast, let fast = models.first(where: \.isFastDefault) {
                return [fast.name]
            }
            return []
        }
        return ids.compactMap { id in models.first(where: { $0.id == id })?.name }
    }

    // MARK: Rating

    func rate(modelId: String, rating: String) async {
        guard let turnId else { return }
        // Light the thumb immediately — feedback is fire-and-forget and a
        // failed rating isn't worth an error banner over the answer.
        ratings[modelId] = rating
        let request = APIRequest(
            path: "/v1/ai-tutor/multi/rate",
            method: .POST,
            body: AiTutorMultiRateRequest(
                turnId: turnId, modelId: modelId, rating: rating),
            headers: localeHeaders)
        try? await AuthInterceptor.shared.executeVoid(request)
    }

    // MARK: Photo

    func attach(_ picked: PickedAttachment) async {
        guard picked.isImage else {
            errorMessage = L10n.aiMultiPhotoNotImage
            return
        }
        imageData = picked.data
        imageUrl = nil
        isUploadingImage = true
        errorMessage = nil
        do {
            // Reuses the app's existing attachment upload — the same path the
            // instructor-chat composer uses. It returns a presigned URL,
            // which is exactly the `image_url` the ask endpoint wants, so
            // there is no new upload endpoint to invent here.
            let upload = try await ChatAttachmentUploader.upload(
                data: picked.data,
                filename: picked.filename,
                contentType: picked.contentType)
            imageUrl = upload.attachmentUrl
        } catch let error as ChatAttachmentUploader.UploadError {
            imageData = nil
            errorMessage = error.errorDescription
        } catch let error as DroobError {
            imageData = nil
            if case .unauthenticated(_, _) = error {
                AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = error.errorDescription ?? L10n.aiMultiErrorGeneric
            }
        } catch {
            imageData = nil
            errorMessage = L10n.aiMultiErrorGeneric
        }
        isUploadingImage = false
        // Re-fetch with the vision filter flipped to match the new state.
        await loadModels()
    }

    func removeImage() async {
        imageData = nil
        imageUrl = nil
        await loadModels()
    }

    // MARK: Headers

    /// The AI tutor endpoints localise both the model names and the
    /// answers off `Accept-Language`, and the app's language is a user
    /// setting that can differ from the device's.
    private var localeHeaders: [String: String] {
        ["Accept-Language": L10n.currentLanguageCode]
    }
}
