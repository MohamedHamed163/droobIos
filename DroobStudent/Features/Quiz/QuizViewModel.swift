import Foundation

// MARK: - API Models

struct QuizSummary: Decodable, Identifiable {
    let id: String
    let titleEn: String
    let titleAr: String
    let descriptionEn: String
    let descriptionAr: String
    let questionCount: Int
    let timeLimitSeconds: Int
    let passMarkPct: Int
    let maxAttempts: Int
    let attemptsUsed: Int
    let bestScorePct: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case titleEn = "title_en"
        case titleAr = "title_ar"
        case descriptionEn = "description_en"
        case descriptionAr = "description_ar"
        case questionCount = "question_count"
        case timeLimitSeconds = "time_limit_seconds"
        case passMarkPct = "pass_mark_pct"
        case maxAttempts = "max_attempts"
        case attemptsUsed = "attempts_used"
        case bestScorePct = "best_score_pct"
    }
}

/// One completed past attempt shown on the "Review past grades" screen.
struct QuizAttemptSummary: Decodable, Identifiable {
    let attemptId: String
    let attemptNumber: Int
    let scorePct: Double
    let passed: Bool
    let correctCount: Int
    let totalCount: Int
    let timeSpentSeconds: Int?
    let completedAt: Date?
    var id: String { attemptId }

    enum CodingKeys: String, CodingKey {
        case attemptId = "attempt_id"
        case attemptNumber = "attempt_number"
        case scorePct = "score_pct"
        case passed
        case correctCount = "correct_count"
        case totalCount = "total_count"
        case timeSpentSeconds = "time_spent_seconds"
        case completedAt = "completed_at"
    }
}

struct QuizQuestion: Identifiable {
    let id: String
    let textEn: String
    let textAr: String
    let sectionLabel: String
    let isMultiChoice: Bool
    let options: [QuizOption]
}

struct QuizOption: Identifiable {
    let id: String
    let textEn: String
    let textAr: String
}

/// One per-question entry in the final result. Drives the
/// "QUESTION BREAKDOWN" row on the result screen.
struct QuizBreakdownEntry: Identifiable {
    let questionId: String
    let sortOrder: Int
    let outcome: String // "CORRECT" | "WRONG"
    var id: String { questionId }
}

struct QuizResult {
    let scorePct: Double
    let passed: Bool
    let correctCount: Int
    let wrongCount: Int
    let totalCount: Int
    let timeSpentSeconds: Int
    let xpEarned: Int
    let isFirstPass: Bool
    let nextLessonId: String?
    let nextLessonTitleEn: String?
    let nextLessonTitleAr: String?
    let studySuggestions: String?
    let attemptsRemaining: Int
    let breakdown: [QuizBreakdownEntry]
}

struct QuizReview {
    let attemptId: String
    let scorePct: Double
    let passed: Bool
    let correctCount: Int
    let wrongCount: Int
    let totalCount: Int
    let questions: [QuizReviewQuestion]
}

struct QuizReviewQuestion: Identifiable {
    let id: String
    let sortOrder: Int
    let textEn: String
    let textAr: String
    let sectionLabel: String
    let isMultiChoice: Bool
    let outcome: String // "CORRECT" | "WRONG" | "UNANSWERED"
    let explanationEn: String
    let explanationAr: String
    let options: [QuizReviewOption]
}

struct QuizReviewOption: Identifiable {
    let id: String
    let textEn: String
    let textAr: String
    let isCorrect: Bool
    let wasSelected: Bool
}

// MARK: - Decodable wrappers

private struct QuizStartData: Decodable {
    let attemptId: String
    let questions: [QuizQuestionRaw]
    enum CodingKeys: String, CodingKey {
        case attemptId = "attempt_id"
        case questions
    }
}

private struct QuizQuestionRaw: Decodable {
    let id: String
    let textEn: String
    let textAr: String
    let sectionLabel: String
    let isMultiChoice: Bool
    let options: [QuizOptionRaw]
    enum CodingKeys: String, CodingKey {
        case id, options
        case textEn = "text_en"
        case textAr = "text_ar"
        case sectionLabel = "section_label"
        case isMultiChoice = "is_multi_choice"
    }
}

private struct QuizOptionRaw: Decodable {
    let id: String
    let textEn: String
    let textAr: String
    enum CodingKeys: String, CodingKey {
        case id
        case textEn = "text_en"
        case textAr = "text_ar"
    }
}

private struct QuizResultRaw: Decodable {
    let scorePct: Double
    let passed: Bool
    let correctCount: Int
    let wrongCount: Int
    let totalCount: Int
    let timeSpentSeconds: Int
    let xpEarned: Int
    let isFirstPass: Bool
    let nextLessonId: String?
    let nextLessonTitleEn: String?
    let nextLessonTitleAr: String?
    let studySuggestions: String?
    let attemptsRemaining: Int?
    let breakdown: [BreakdownRaw]?
    enum CodingKeys: String, CodingKey {
        case scorePct = "score_pct"
        case passed
        case correctCount = "correct_count"
        case wrongCount = "wrong_count"
        case totalCount = "total_count"
        case timeSpentSeconds = "time_spent_seconds"
        case xpEarned = "xp_earned"
        case isFirstPass = "is_first_pass"
        case nextLessonId = "next_lesson_id"
        case nextLessonTitleEn = "next_lesson_title_en"
        case nextLessonTitleAr = "next_lesson_title_ar"
        case studySuggestions = "study_suggestions"
        case attemptsRemaining = "attempts_remaining"
        case breakdown
    }
}

private struct BreakdownRaw: Decodable {
    let questionId: String
    let sortOrder: Int
    let outcome: String
    enum CodingKeys: String, CodingKey {
        case questionId = "question_id"
        case sortOrder = "sort_order"
        case outcome
    }
}

private struct QuizReviewRaw: Decodable {
    let attemptId: String
    let scorePct: Double
    let passed: Bool
    let correctCount: Int
    let wrongCount: Int
    let totalCount: Int
    let questions: [ReviewQuestionRaw]
    enum CodingKeys: String, CodingKey {
        case attemptId = "attempt_id"
        case scorePct = "score_pct"
        case passed
        case correctCount = "correct_count"
        case wrongCount = "wrong_count"
        case totalCount = "total_count"
        case questions
    }
}

private struct ReviewQuestionRaw: Decodable {
    let id: String
    let sortOrder: Int
    let textEn: String
    let textAr: String
    let sectionLabel: String
    let isMultiChoice: Bool
    let outcome: String
    let explanationEn: String
    let explanationAr: String
    let options: [ReviewOptionRaw]
    enum CodingKeys: String, CodingKey {
        case id, outcome, options
        case sortOrder = "sort_order"
        case textEn = "text_en"
        case textAr = "text_ar"
        case sectionLabel = "section_label"
        case isMultiChoice = "is_multi_choice"
        case explanationEn = "explanation_en"
        case explanationAr = "explanation_ar"
    }
}

private struct ReviewOptionRaw: Decodable {
    let id: String
    let textEn: String
    let textAr: String
    let isCorrect: Bool
    let wasSelected: Bool
    enum CodingKeys: String, CodingKey {
        case id
        case textEn = "text_en"
        case textAr = "text_ar"
        case isCorrect = "is_correct"
        case wasSelected = "was_selected"
    }
}

// MARK: - Phase

enum QuizPhase {
    case intro
    case playing
    case confirmSubmit         // review-before-submit screen (Finish → here → submit)
    case finishing
    case result
    case pastGrades            // list of prior attempts (from intro)
    case reviewList
    case reviewDetail(Int) // question index
}

/// Where the review-answers flow was entered from, so the review list's
/// back button returns to the correct screen.
enum QuizReviewOrigin {
    case result      // just-finished attempt → back to result
    case pastGrades  // a past attempt → back to the past-grades list
}

// MARK: - ViewModel

@MainActor
final class QuizViewModel: ObservableObject {
    let courseId: String
    let quizId: String
    let sectionId: String

    // Intro
    @Published var summary: QuizSummary? = nil
    @Published var isLoadingSummary = true
    @Published var summaryError: String? = nil
    @Published var isStarting = false

    // Phase
    @Published var phase: QuizPhase = .intro

    // Active quiz
    @Published var questions: [QuizQuestion] = []
    @Published var attemptId: String? = nil
    @Published var currentIndex: Int = 0
    /// questionId → set of currently-selected optionIds. This is local UI state
    /// only: selecting an option never records it. An answer is recorded only
    /// when the student taps "Submit answer".
    @Published var selectionsByQuestion: [String: Set<String>] = [:]
    /// questionIds whose answer the student explicitly submitted (and which were
    /// therefore persisted to the backend). Skipping leaves a question out of
    /// this set even when an option is still visually selected, so a skipped
    /// question is never scored as answered.
    @Published var submittedQuestions: Set<String> = []

    // Start timestamp (wall-clock seconds counted client-side, sent on complete)
    private var startedAt: Date? = nil

    // Results
    @Published var quizResult: QuizResult? = nil
    @Published var review: QuizReview? = nil
    @Published var isLoadingReview = false

    // Past grades (prior attempts)
    @Published var pastAttempts: [QuizAttemptSummary] = []
    @Published var isLoadingAttempts = false
    @Published var attemptsError: String? = nil
    /// Drives where the review-list back button returns.
    @Published var reviewOrigin: QuizReviewOrigin = .result

    // First-name for headline; nil → no name in headline.
    let firstName: String?

    init(courseId: String, quizId: String, sectionId: String, displayName: String?) {
        self.courseId = courseId
        self.quizId = quizId
        self.sectionId = sectionId
        if let dn = displayName?.trimmingCharacters(in: .whitespaces), !dn.isEmpty {
            self.firstName = dn.split(separator: " ").first.map(String.init)
        } else {
            self.firstName = nil
        }
    }

    var currentQuestion: QuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    func selection(for questionId: String) -> Set<String> {
        selectionsByQuestion[questionId] ?? []
    }

    /// A question is "answered" only once its answer has been explicitly
    /// submitted. A bare selection that was skipped does not count.
    func isAnswered(_ questionId: String) -> Bool {
        submittedQuestions.contains(questionId)
    }

    /// Jump directly to a question by index — used for free back/forth
    /// navigation (swipe paging + tappable numbered circles). Clamps to the
    /// valid range so out-of-bounds taps are ignored.
    func goToQuestion(_ index: Int) {
        guard index >= 0, index < questions.count, index != currentIndex else { return }
        currentIndex = index
    }

    var answeredCount: Int {
        questions.filter { isAnswered($0.id) }.count
    }
    var unansweredCount: Int { questions.count - answeredCount }
    var allAnswered: Bool { unansweredCount == 0 }

    /// 0-based indices of the questions still unanswered (not yet submitted), in
    /// order — drives the "Jump back to" pills on the review screen.
    var unansweredIndices: [Int] {
        questions.indices.filter { !isAnswered(questions[$0].id) }
    }

    // MARK: - Load summary

    func loadSummary() async {
        isLoadingSummary = true
        summaryError = nil
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/quizzes/\(quizId)"
        )
        do {
            let s: QuizSummary = try await AuthInterceptor.shared.execute(request)
            summary = s
        } catch {
            summaryError = (error as? DroobError)?.errorDescription ?? error.localizedDescription
        }
        isLoadingSummary = false
    }

    // MARK: - Start quiz

    func startQuiz() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/quizzes/\(quizId)/start",
            method: .POST
        )
        do {
            let data: QuizStartData = try await AuthInterceptor.shared.execute(request)
            attemptId = data.attemptId
            questions = data.questions.map { q in
                QuizQuestion(
                    id: q.id,
                    textEn: q.textEn,
                    textAr: q.textAr,
                    sectionLabel: q.sectionLabel,
                    isMultiChoice: q.isMultiChoice,
                    options: q.options.map {
                        QuizOption(id: $0.id, textEn: $0.textEn, textAr: $0.textAr)
                    }
                )
            }
            currentIndex = 0
            selectionsByQuestion = [:]
            submittedQuestions = []
            quizResult = nil
            review = nil
            startedAt = Date()
            phase = .playing
        } catch {
            summaryError = (error as? DroobError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Selection

    /// Toggle an option for the current question. Single-choice questions
    /// replace any prior selection; multi-choice questions toggle. This only
    /// updates local UI state — nothing is recorded until the student taps
    /// "Submit answer".
    func toggle(optionId: String, for question: QuizQuestion) {
        var current = selection(for: question.id)
        if question.isMultiChoice {
            if current.contains(optionId) {
                current.remove(optionId)
            } else {
                current.insert(optionId)
            }
        } else {
            current = [optionId]
        }
        selectionsByQuestion[question.id] = current
    }

    private func persistSelection(questionId: String, optionIds: [String]) {
        guard let attemptId else { return }
        struct Body: Encodable {
            let questionId: String
            let optionIds: [String]
            enum CodingKeys: String, CodingKey {
                case questionId = "question_id"
                case optionIds = "option_ids"
            }
        }
        let request = APIRequest(
            path: "/v1/student/attempts/\(attemptId)/answer",
            method: .POST,
            body: Body(questionId: questionId, optionIds: optionIds)
        )
        Task.detached { [request] in
            _ = try? await AuthInterceptor.shared.executeVoid(request)
        }
    }

    // MARK: - Submit / skip per question

    /// Record the current question's selected answer, then advance. This is the
    /// only path that persists an answer to the backend — selecting an option
    /// alone never records it. No-op when nothing is selected.
    func submitCurrentAnswer() {
        guard let question = currentQuestion else { return }
        let optionIds = Array(selection(for: question.id))
        guard !optionIds.isEmpty else { return }
        submittedQuestions.insert(question.id)
        persistSelection(questionId: question.id, optionIds: optionIds)
        advanceAfterAnswering()
    }

    /// Move past the current question without recording an answer. Any answer
    /// previously submitted for this question is left untouched.
    func skipCurrent() {
        advanceAfterAnswering()
    }

    /// After a submit/skip, go to the next question — or to the
    /// review-before-submit screen once the last question has been handled.
    private func advanceAfterAnswering() {
        if currentIndex >= questions.count - 1 {
            phase = .confirmSubmit
        } else {
            currentIndex += 1
        }
    }

    // MARK: - Navigation during play

    /// Review screen "Go back" → return to play at the question last viewed.
    func backToPlayFromConfirm() {
        phase = .playing
    }

    /// Review screen "Jump back to · Question N" pill → open that question.
    func jumpToQuestion(_ index: Int) {
        goToQuestion(index)
        phase = .playing
    }

    // MARK: - Finish

    func finishQuiz() async {
        phase = .finishing
        guard let attemptId else { return }

        let elapsed = startedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0

        struct CompleteBody: Encodable {
            let timeSpentSeconds: Int
            enum CodingKeys: String, CodingKey { case timeSpentSeconds = "time_spent_seconds" }
        }
        let request = APIRequest(
            path: "/v1/student/attempts/\(attemptId)/complete",
            method: .POST,
            body: CompleteBody(timeSpentSeconds: elapsed)
        )

        // Show the "Finishing your quiz…" overlay for at least 600ms so it
        // never flashes by — the design relies on the small dwell.
        async let raw: QuizResultRaw = AuthInterceptor.shared.execute(request)
        async let _: Void = Task.sleep(nanoseconds: 600_000_000)

        do {
            let r = try await raw
            quizResult = QuizResult(
                scorePct: r.scorePct,
                passed: r.passed,
                correctCount: r.correctCount,
                wrongCount: r.wrongCount,
                totalCount: r.totalCount,
                timeSpentSeconds: r.timeSpentSeconds,
                xpEarned: r.xpEarned,
                isFirstPass: r.isFirstPass,
                nextLessonId: r.nextLessonId,
                nextLessonTitleEn: r.nextLessonTitleEn,
                nextLessonTitleAr: r.nextLessonTitleAr,
                studySuggestions: r.studySuggestions,
                attemptsRemaining: r.attemptsRemaining ?? 0,
                breakdown: (r.breakdown ?? []).map {
                    QuizBreakdownEntry(questionId: $0.questionId, sortOrder: $0.sortOrder, outcome: $0.outcome)
                }
            )
            phase = .result
        } catch {
            // Show error inline on the result screen by setting a zero result.
            summaryError = (error as? DroobError)?.errorDescription ?? error.localizedDescription
            phase = .playing
        }
    }

    // MARK: - Review

    func loadReview() async {
        guard let attemptId else { return }
        isLoadingReview = true
        defer { isLoadingReview = false }
        let request = APIRequest(
            path: "/v1/student/attempts/\(attemptId)/review"
        )
        do {
            let raw: QuizReviewRaw = try await AuthInterceptor.shared.execute(request)
            review = QuizReview(
                attemptId: raw.attemptId,
                scorePct: raw.scorePct,
                passed: raw.passed,
                correctCount: raw.correctCount,
                wrongCount: raw.wrongCount,
                totalCount: raw.totalCount,
                questions: raw.questions.map { q in
                    QuizReviewQuestion(
                        id: q.id,
                        sortOrder: q.sortOrder,
                        textEn: q.textEn,
                        textAr: q.textAr,
                        sectionLabel: q.sectionLabel,
                        isMultiChoice: q.isMultiChoice,
                        outcome: q.outcome,
                        explanationEn: q.explanationEn,
                        explanationAr: q.explanationAr,
                        options: q.options.map {
                            QuizReviewOption(
                                id: $0.id,
                                textEn: $0.textEn,
                                textAr: $0.textAr,
                                isCorrect: $0.isCorrect,
                                wasSelected: $0.wasSelected)
                        }
                    )
                }
            )
        } catch {
            summaryError = (error as? DroobError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Past grades

    /// Loads the student's prior completed attempts and shows the past-grades
    /// list. Reached from the intro screen's "Review past grades" CTA.
    func openPastGrades() async {
        isLoadingAttempts = true
        attemptsError = nil
        phase = .pastGrades
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/quizzes/\(quizId)/attempts"
        )
        do {
            let attempts: [QuizAttemptSummary] = try await AuthInterceptor.shared.execute(request)
            pastAttempts = attempts
        } catch {
            attemptsError = (error as? DroobError)?.errorDescription ?? error.localizedDescription
        }
        isLoadingAttempts = false
    }

    /// Drill into the full per-question review of a specific past attempt.
    func openAttemptReview(attemptId: String) async {
        self.attemptId = attemptId
        reviewOrigin = .pastGrades
        await loadReview()
        phase = .reviewList
    }

    func openReviewList() async {
        reviewOrigin = .result
        await loadReview()
        phase = .reviewList
    }
    func openReviewDetail(_ index: Int) { phase = .reviewDetail(index) }
    /// Back from the review list, honouring where it was opened from.
    func backFromReviewList() {
        switch reviewOrigin {
        case .result:     phase = .result
        case .pastGrades: phase = .pastGrades
        }
    }
    func backToResult() { phase = .result }
    func backToReviewList() { phase = .reviewList }
    func backToIntroFromPastGrades() { phase = .intro }
    func backToIntro() {
        phase = .intro
        questions = []
        attemptId = nil
        currentIndex = 0
        selectionsByQuestion = [:]
        submittedQuestions = []
        quizResult = nil
        review = nil
        startedAt = nil
    }

    // Retake → start fresh attempt, skip intro.
    func retake() async {
        await startQuiz()
    }
}
