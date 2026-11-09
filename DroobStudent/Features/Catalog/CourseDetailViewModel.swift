import Foundation

// MARK: - Models

/// Response from the (free) enrollment endpoint `POST /courses/{id}/subscribe`.
/// Moved here from the removed Subscribe/payment module so free enrollment
/// keeps working with payments gone.
struct EnrollmentResponse: Decodable {
    let enrollmentId: String
    let courseId: String
    let subscribedAt: String

    enum CodingKeys: String, CodingKey {
        case enrollmentId = "enrollment_id"
        case courseId = "course_id"
        case subscribedAt = "subscribed_at"
    }
}

struct CourseDetail: Decodable, Identifiable {
    let id: String
    let titleEn: String
    let titleAr: String
    let descriptionEn: String?
    let descriptionAr: String?
    let coverUrl: String?
    let instructorId: String
    let instructorName: String
    /// Presigned instructor avatar URL (nullable). Drives the instructor
    /// avatar on the course-detail instructor card; falls back to initials
    /// when nil/blank or the image fails to load.
    let instructorAvatarUrl: String?
    let priceCents: Int
    let currency: String
    let enrolled: Bool
    let lessonCount: Int
    let completedLessonCount: Int
    let totalDurationMinutes: Int
    let studentsCount: Int
    let ratingAvg: Double?
    let ratingCount: Int
    let isBestseller: Bool
    let progressPct: Double
    let nextLessonId: String?
    let nextLessonTitleEn: String?
    let nextLessonTitleAr: String?
    let categorySlug: String?
    let categoryNameEn: String?
    let categoryNameAr: String?
    let sections: [CourseSection]
    /// Star-bucket histogram + total, computed from the live `course_reviews`
    /// table on the backend. Null when the backend hasn't been re-deployed
    /// after V39 (defensive — defaults the iOS preview to an empty histogram).
    let ratingDistribution: RatingDistribution?
    /// Two-row preview that drives the inline "Ratings & Reviews" cards on
    /// the detail screen. Empty list when no reviews exist yet.
    let recentReviews: [CourseReviewItem]
    /// Two-row preview for the inline Q&A block. Empty list when the
    /// course has no questions yet. Each entry may carry an inline
    /// `instructorAnswer` shown nested under the question text.
    let recentQuestions: [CourseQuestionItem]
    /// Total question count — drives the "See all 47 questions" link
    /// at the bottom of the Q&A card. 0 when no questions exist.
    let questionsCount: Int
    /// Count of currently-ACTIVE PUBLIC study rooms in this course.
    /// Drives the "X rooms live now" badge on the Study Together card.
    /// 0 when the backend hasn't been re-deployed past V47 — the field
    /// is decoded defensively.
    let studyRoomsLiveCount: Int
    /// Up to 4 instructor-curated FAQ entries for the "Questions you
    /// may ask" block. Empty list when the instructor hasn't written
    /// any (or when the backend pre-dates V52).
    let pinnedFaqs: [PinnedFaqItem]

    enum CodingKeys: String, CodingKey {
        case id
        case titleEn = "title_en"
        case titleAr = "title_ar"
        case descriptionEn = "description_en"
        case descriptionAr = "description_ar"
        case coverUrl = "cover_url"
        case instructorId = "instructor_id"
        case instructorName = "instructor_name"
        case instructorAvatarUrl = "instructor_avatar_url"
        case priceCents = "price_cents"
        case currency
        case enrolled
        case lessonCount = "lesson_count"
        case completedLessonCount = "completed_lesson_count"
        case totalDurationMinutes = "total_duration_minutes"
        case studentsCount = "students_count"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case isBestseller = "is_bestseller"
        case progressPct = "progress_pct"
        case nextLessonId = "next_lesson_id"
        case nextLessonTitleEn = "next_lesson_title_en"
        case nextLessonTitleAr = "next_lesson_title_ar"
        case categorySlug = "category_slug"
        case categoryNameEn = "category_name_en"
        case categoryNameAr = "category_name_ar"
        case sections
        case ratingDistribution = "rating_distribution"
        case recentReviews = "recent_reviews"
        case recentQuestions = "recent_questions"
        case questionsCount = "questions_count"
        case studyRoomsLiveCount = "study_rooms_live_count"
        case pinnedFaqs = "pinned_faqs"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                     = try c.decode(String.self, forKey: .id)
        titleEn                = try c.decode(String.self, forKey: .titleEn)
        titleAr                = try c.decode(String.self, forKey: .titleAr)
        descriptionEn          = try c.decodeIfPresent(String.self, forKey: .descriptionEn)
        descriptionAr          = try c.decodeIfPresent(String.self, forKey: .descriptionAr)
        coverUrl               = try c.decodeIfPresent(String.self, forKey: .coverUrl)
        // Tolerate older fixtures that pre-date the addition of
        // instructor_id — default to empty string so the instructor
        // card just won't be tappable instead of failing to decode.
        instructorId           = try c.decodeIfPresent(String.self, forKey: .instructorId) ?? ""
        instructorName         = try c.decode(String.self, forKey: .instructorName)
        instructorAvatarUrl    = try c.decodeIfPresent(String.self, forKey: .instructorAvatarUrl)
        priceCents             = try c.decode(Int.self, forKey: .priceCents)
        currency               = try c.decode(String.self, forKey: .currency)
        enrolled               = try c.decode(Bool.self, forKey: .enrolled)
        lessonCount            = try c.decode(Int.self, forKey: .lessonCount)
        completedLessonCount   = try c.decode(Int.self, forKey: .completedLessonCount)
        totalDurationMinutes   = try c.decode(Int.self, forKey: .totalDurationMinutes)
        studentsCount          = try c.decode(Int.self, forKey: .studentsCount)
        ratingAvg              = try c.decodeIfPresent(Double.self, forKey: .ratingAvg)
        ratingCount            = try c.decode(Int.self, forKey: .ratingCount)
        isBestseller           = try c.decode(Bool.self, forKey: .isBestseller)
        progressPct            = try c.decode(Double.self, forKey: .progressPct)
        nextLessonId           = try c.decodeIfPresent(String.self, forKey: .nextLessonId)
        nextLessonTitleEn      = try c.decodeIfPresent(String.self, forKey: .nextLessonTitleEn)
        nextLessonTitleAr      = try c.decodeIfPresent(String.self, forKey: .nextLessonTitleAr)
        categorySlug           = try c.decodeIfPresent(String.self, forKey: .categorySlug)
        categoryNameEn         = try c.decodeIfPresent(String.self, forKey: .categoryNameEn)
        categoryNameAr         = try c.decodeIfPresent(String.self, forKey: .categoryNameAr)
        sections               = try c.decode([CourseSection].self, forKey: .sections)
        ratingDistribution     = try c.decodeIfPresent(RatingDistribution.self, forKey: .ratingDistribution)
        recentReviews          = try c.decodeIfPresent([CourseReviewItem].self, forKey: .recentReviews) ?? []
        recentQuestions        = try c.decodeIfPresent([CourseQuestionItem].self, forKey: .recentQuestions) ?? []
        questionsCount         = try c.decodeIfPresent(Int.self, forKey: .questionsCount) ?? 0
        studyRoomsLiveCount    = try c.decodeIfPresent(Int.self, forKey: .studyRoomsLiveCount) ?? 0
        pinnedFaqs             = try c.decodeIfPresent([PinnedFaqItem].self, forKey: .pinnedFaqs) ?? []
    }

    /// Memberwise initializer retained for preview/test seeds — production
    /// decoding always goes through `init(from:)`.
    init(id: String, titleEn: String, titleAr: String, descriptionEn: String?, descriptionAr: String?,
         coverUrl: String?, instructorId: String = "", instructorName: String, instructorAvatarUrl: String? = nil, priceCents: Int, currency: String, enrolled: Bool,
         lessonCount: Int, completedLessonCount: Int, totalDurationMinutes: Int, studentsCount: Int,
         ratingAvg: Double?, ratingCount: Int, isBestseller: Bool, progressPct: Double,
         nextLessonId: String?, nextLessonTitleEn: String?, nextLessonTitleAr: String?,
         categorySlug: String? = nil, categoryNameEn: String? = nil, categoryNameAr: String? = nil,
         sections: [CourseSection],
         ratingDistribution: RatingDistribution? = nil,
         recentReviews: [CourseReviewItem] = [],
         recentQuestions: [CourseQuestionItem] = [],
         questionsCount: Int = 0,
         studyRoomsLiveCount: Int = 0,
         pinnedFaqs: [PinnedFaqItem] = []) {
        self.id = id; self.titleEn = titleEn; self.titleAr = titleAr
        self.descriptionEn = descriptionEn; self.descriptionAr = descriptionAr
        self.coverUrl = coverUrl
        self.instructorId = instructorId
        self.instructorName = instructorName
        self.instructorAvatarUrl = instructorAvatarUrl
        self.priceCents = priceCents; self.currency = currency; self.enrolled = enrolled
        self.lessonCount = lessonCount; self.completedLessonCount = completedLessonCount
        self.totalDurationMinutes = totalDurationMinutes; self.studentsCount = studentsCount
        self.ratingAvg = ratingAvg; self.ratingCount = ratingCount
        self.isBestseller = isBestseller; self.progressPct = progressPct
        self.nextLessonId = nextLessonId; self.nextLessonTitleEn = nextLessonTitleEn; self.nextLessonTitleAr = nextLessonTitleAr
        self.categorySlug = categorySlug; self.categoryNameEn = categoryNameEn; self.categoryNameAr = categoryNameAr
        self.sections = sections
        self.ratingDistribution = ratingDistribution
        self.recentReviews = recentReviews
        self.recentQuestions = recentQuestions
        self.questionsCount = questionsCount
        self.studyRoomsLiveCount = studyRoomsLiveCount
        self.pinnedFaqs = pinnedFaqs
    }

    func localizedTitle(locale: String) -> String {
        L10n.localized(locale, ar: titleAr, en: titleEn)
    }

    func localizedDescription(locale: String) -> String? {
        L10n.localized(locale, ar: descriptionAr, en: descriptionEn)
    }

    func localizedNextLessonTitle(locale: String) -> String? {
        return L10n.localized(locale, ar: nextLessonTitleAr, en: nextLessonTitleEn)
    }

    var formattedPrice: String {
        CurrencyFormat.formatted(priceCents: priceCents, currency: currency)
    }

    var formattedHours: String {
        let h = totalDurationMinutes / 60
        let m = totalDurationMinutes % 60
        // Two groups either side of a neutral space: under the Arabic UI the
        // hours and the minutes would otherwise trade places.
        if h > 0 && m > 0 { return bidiJoin("\(h)h", "\(m)m", separator: " ") }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    var formattedStudentsCount: String {
        if studentsCount >= 1_000_000 {
            return String(format: "%.1fM", Double(studentsCount) / 1_000_000)
        }
        if studentsCount >= 1_000 {
            return String(format: "%.1fk", Double(studentsCount) / 1_000)
                .replacingOccurrences(of: ".0k", with: "k")
        }
        return "\(studentsCount)"
    }
}

/// One quiz attached to a module. A module may hold several (V76); each is its
/// own row and its own entry point into the quiz flow, keyed by `id`.
struct SectionQuiz: Decodable, Identifiable, Equatable {
    let id: String
    let titleEn: String
    let titleAr: String
    let questionCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case titleEn = "title_en"
        case titleAr = "title_ar"
        case questionCount = "question_count"
    }

    func localizedTitle(locale: String) -> String {
        L10n.localized(locale, ar: titleAr, en: titleEn)
    }
}

struct CourseSection: Decodable, Identifiable {
    let id: String
    let titleEn: String
    let titleAr: String
    let sortOrder: Int
    let lessonCount: Int
    let completedLessonCount: Int
    let status: String
    let lessons: [LessonSummary]
    /// Deprecated: the oldest quiz's id. Prefer `quizzes`, which lists every
    /// quiz on the module. Kept so older payloads still decode.
    let quizId: String?
    /// Every quiz attached to this module (V76), oldest first. Nil only when an
    /// older backend hasn't sent the field yet.
    let quizzes: [SectionQuiz]?
    /// Backend enum ("CURRICULUM" / "REVISION"). Revision sections are
    /// filtered out of the student course detail screen. Defaults to
    /// "CURRICULUM" when the backend hasn't been redeployed after V39.
    let contentType: String?

    var isRevision: Bool { contentType?.uppercased() == "REVISION" }

    /// Quizzes to render for this module, tolerating an older payload that only
    /// carried the scalar `quiz_id` (falls back to a single untitled row).
    var moduleQuizzes: [SectionQuiz] {
        if let quizzes { return quizzes }
        if let quizId { return [SectionQuiz(id: quizId, titleEn: "", titleAr: "", questionCount: 0)] }
        return []
    }

    enum CodingKeys: String, CodingKey {
        case id
        case titleEn = "title_en"
        case titleAr = "title_ar"
        case sortOrder = "sort_order"
        case lessonCount = "lesson_count"
        case completedLessonCount = "completed_lesson_count"
        case status
        case lessons
        case quizId = "quiz_id"
        case quizzes
        case contentType = "content_type"
    }

    func localizedTitle(locale: String) -> String {
        L10n.localized(locale, ar: titleAr, en: titleEn)
    }

    var isCompleted: Bool { status == "completed" }
    var isInProgress: Bool { status == "in_progress" }
    var isNotStarted: Bool { status == "not_started" }
}

// MARK: - Ratings & Reviews payloads

/// Star-bucket histogram returned alongside the detail payload.
struct RatingDistribution: Decodable, Equatable {
    let ratingAvg: Double?
    let ratingCount: Int
    let buckets: [Bucket]

    struct Bucket: Decodable, Equatable, Identifiable {
        let stars: Int
        let count: Int
        let percent: Int

        var id: Int { stars }
    }

    enum CodingKeys: String, CodingKey {
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case buckets
    }

    static let empty = RatingDistribution(
        ratingAvg: nil, ratingCount: 0,
        buckets: (1...5).reversed().map {
            Bucket(stars: $0, count: 0, percent: 0)
        })
}

/// One review card displayed on the detail screen / "See all reviews" surface.
///
/// The backend carries two timestamps:
///   - `createdAt`: the original submission timestamp (kept for any
///     future "Originally posted on …" copy).
///   - `updatedAt`: the timestamp of the latest edit. Equal to
///     `createdAt` for reviews that have never been edited, otherwise
///     bumped on every edit. The relative-time label ("3 days ago",
///     "1 min ago") reads `updatedAt` so an edited review surfaces as
///     fresh activity instead of staying frozen at its first
///     submission date.
///
/// Older backends won't ship `updated_at` yet — the decoder falls
/// back to `createdAt` so the row keeps rendering.
struct CourseReviewItem: Decodable, Identifiable, Equatable {
    let id: String
    let authorName: String
    let authorAvatarUrl: String?
    let stars: Int
    let body: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case authorName = "author_name"
        case authorAvatarUrl = "author_avatar_url"
        case stars
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        authorName      = try c.decode(String.self, forKey: .authorName)
        authorAvatarUrl = try c.decodeIfPresent(String.self,
                                                forKey: .authorAvatarUrl)
        stars           = try c.decode(Int.self, forKey: .stars)
        body            = try c.decodeIfPresent(String.self, forKey: .body)
        let created     = try c.decode(Date.self, forKey: .createdAt)
        createdAt       = created
        updatedAt       = try c.decodeIfPresent(Date.self,
                                                forKey: .updatedAt) ?? created
    }
}

// MARK: - Course Q&A

/// Single answer payload nested under a {@link CourseQuestionItem}. The
/// `isInstructor` flag drives the gold-tinted reply card treatment on
/// the iOS Q&A row — non-instructor answers (when shown elsewhere) get
/// the same chrome as the parent question.
struct CourseAnswerItem: Decodable, Identifiable, Equatable {
    let id: String
    let authorName: String
    let authorAvatarUrl: String?
    let isInstructor: Bool
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case authorName = "author_name"
        case authorAvatarUrl = "author_avatar_url"
        case isInstructor = "is_instructor"
        case body
        case createdAt = "created_at"
    }
}

/// One row in the iOS Q&A list.
///
/// `instructorAnswers` holds every instructor reply (oldest-first) — the
/// full Q&A screen renders the whole thread, so a question with more than
/// one instructor reply must show all of them.
///
/// `instructorAnswer` is the single most-recent reply, kept for the inline
/// preview card on the course-detail screen which only shows one reply.
/// Older backends that don't yet send `instructor_answers` decode to an
/// empty array, so callers fall back to the singular field.
struct CourseQuestionItem: Decodable, Identifiable, Equatable {
    let id: String
    let authorName: String
    let authorAvatarUrl: String?
    let body: String
    let upvotesCount: Int
    let createdAt: Date
    let instructorAnswer: CourseAnswerItem?
    let instructorAnswers: [CourseAnswerItem]

    enum CodingKeys: String, CodingKey {
        case id
        case authorName = "author_name"
        case authorAvatarUrl = "author_avatar_url"
        case body
        case upvotesCount = "upvotes_count"
        case createdAt = "created_at"
        case instructorAnswer = "instructor_answer"
        case instructorAnswers = "instructor_answers"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        authorName = try c.decode(String.self, forKey: .authorName)
        authorAvatarUrl = try c.decodeIfPresent(String.self, forKey: .authorAvatarUrl)
        body = try c.decode(String.self, forKey: .body)
        upvotesCount = try c.decode(Int.self, forKey: .upvotesCount)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        instructorAnswer = try c.decodeIfPresent(CourseAnswerItem.self, forKey: .instructorAnswer)
        instructorAnswers = try c.decodeIfPresent([CourseAnswerItem].self, forKey: .instructorAnswers) ?? []
    }
}

// MARK: - Pinned FAQs ("Questions you may ask")

/// One row in the instructor-curated FAQ block. The instructor types
/// both the question and the answer; the avatar/name shown alongside
/// the answer on the detail screen comes from the course's instructor
/// profile, not from this payload.
struct PinnedFaqItem: Decodable, Identifiable, Equatable {
    let id: String
    let question: String
    let answer: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id, question, answer, position
    }
}

// MARK: - Currency formatter
//
// Single source of truth for course-price display strings. Standardised on
// "<amount> SAR" so the iOS surface stays consistent regardless of locale —
// previously some screens fell back to the iOS 18.4 `saudiriyalsign` SF
// Symbol while others rendered plain "<amount> SAR", which looked like
// "two different currencies" in the same tab.

enum CurrencyFormat {
    /// "<amount> <currency>" or `L10n.free` when the price is zero.
    /// `currency` is the wire-side enum string (typically `"SAR"`).
    static func formatted(priceCents: Int, currency: String) -> String {
        if priceCents == 0 { return L10n.free }
        return L10n.price(cents: priceCents, currency: currency)
    }
}

struct LessonSummary: Decodable, Identifiable {
    let id: String
    let titleEn: String
    let titleAr: String
    let sortOrder: Int
    let type: String  // "video" | "text"
    let durationSeconds: Int?
    let completed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case titleEn = "title_en"
        case titleAr = "title_ar"
        case sortOrder = "sort_order"
        case type
        case durationSeconds = "duration_seconds"
        case completed
    }

    var isVideo: Bool { type == "video" }

    func localizedTitle(locale: String) -> String {
        L10n.localized(locale, ar: titleAr, en: titleEn)
    }
}

// MARK: - CourseDetailViewModel

@MainActor
final class CourseDetailViewModel: ObservableObject {
    @Published var course: CourseDetail? = nil
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    @Published var isEnrolled: Bool = false
    /// The caller's open PENDING request for this course, if any. Drives the
    /// "Request Pending" enroll-button state and the manage (edit-note /
    /// cancel) sheet. Nil when not requested, or once enrolled/decided.
    @Published var pendingRequest: EnrollmentRequest? = nil
    @Published var isEnrolling: Bool = false
    /// The instructor-created study room for this course (2026-07), if
    /// one exists. Drives the "Study Together" card — the card only
    /// renders when this is non-nil, and tapping it joins + opens the
    /// room chat directly (the student create/join flow is hidden).
    @Published var instructorRoom: StudyRoomSummary? = nil
    /// Flips to true (once) when background polling discovers the instructor
    /// approved the pending request. Hosts observe this to auto-route the
    /// student to the course page without a manual refresh. By the time it
    /// flips, the course/enrollment state has already been refreshed — see
    /// `handleApprovalDiscovered`.
    @Published var approvalDetected: Bool = false
    /// Terminal decision discovered by polling that is *not* an approval —
    /// REJECTED or CANCELLED. Drives an inline notice on the enroll card and
    /// never routes anywhere. Nil while pending, or once approved.
    @Published var requestDecision: EnrollmentRequestStatus? = nil
    /// True once the poll loop hit its ceiling and gave up (see
    /// `approvalPollCeiling`). Hosts swap the "Awaiting approval" subtitle for
    /// a manual "Check now" affordance, which calls `checkApprovalNow()`.
    @Published var approvalPollGaveUp: Bool = false

    // MARK: Approval-poll internals

    private var approvalPollTask: Task<Void, Never>? = nil
    /// The in-flight "screen came back" work. Held (rather than fired and
    /// forgotten) so `suspendApprovalPolling` can cancel a resume that was
    /// enqueued before it — see `requestResumeApprovalPolling`.
    private var approvalResumeTask: Task<Void, Never>? = nil
    /// Bumped on every start/stop. A poll task only clears the shared handle
    /// when it still owns it, so a cancelled loop's teardown can't orphan the
    /// loop that replaced it.
    private var approvalPollGeneration: Int = 0
    /// Set by the host view: true only while this screen is on-screen AND the
    /// app is in the foreground. Polling is gated on it — a timer still firing
    /// behind a backgrounded app drains battery and burns cellular data for a
    /// screen nobody is looking at.
    private var isScreenActive: Bool = false
    /// Rule: never stack requests. True while a poll round-trip is open, so a
    /// tick that fires over a slow response skips instead of piling on.
    private var isApprovalPollInFlight: Bool = false
    /// One-shot latch on the auto-navigation. A late in-flight response landing
    /// after we already routed must not route a second time or pop the stack.
    private var didAnnounceApproval: Bool = false

    // MARK: Approval-poll tuning
    //
    // One named constant per knob — the cadence in particular must never be
    // spelled out at a call site.

    /// How often a PENDING request is re-checked while the student is looking
    /// at the course. `GET /enrollment-request` is a single indexed row read,
    /// deliberately cheap, so a 3 s cadence is affordable and makes an
    /// approval land as close to instantly as polling gets.
    static let approvalPollInterval: TimeInterval = 3

    /// Hard ceiling on one continuous foreground polling run. An instructor may
    /// take a day to decide, and a phone parked on this screen must not hold a
    /// 3 s network loop open until the battery dies — so we stop after ~10
    /// minutes and hand the student a manual refresh instead. The budget is
    /// per foreground run: it resets every time the screen comes back.
    static let approvalPollCeiling: TimeInterval = 10 * 60

    /// Ceiling on the consecutive-failure backoff, in doublings. 3 s → 48 s.
    private static let approvalPollMaxBackoffDoublings: Int = 4

    let courseId: String
    private var skipNetwork: Bool = false
    /// Pre-login preview mode: load the course via the tokenless public
    /// endpoint and never bounce the viewer to the login screen on 401.
    /// The hosting view routes the enroll CTA to sign-in instead.
    let isGuest: Bool

    init(courseId: String, guest: Bool = false) {
        self.courseId = courseId
        self.isGuest = guest
    }

    deinit {
        approvalPollTask?.cancel()
        approvalResumeTask?.cancel()
    }

    func load() async {
        if skipNetwork { return }

        isLoading = true
        errorMessage = nil

        let request = APIRequest(path: "/v1/student/courses/\(courseId)")

        do {
            // Guests load the course through the tokenless public path so the
            // catalog/detail is browsable before sign-in.
            let detail: CourseDetail = isGuest
                ? try await AuthInterceptor.shared.executePublic(request)
                : try await AuthInterceptor.shared.execute(request)
            course = detail
            isEnrolled = detail.enrolled
            await loadPendingRequest()
            await loadInstructorRoom()
            syncApprovalPolling()
        } catch let error as DroobError {
            // Never bounce a guest to the login gate — they're previewing.
            if case .unauthenticated(_, _) = error, !isGuest {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Best-effort fetch of the instructor-created room (2026-07). Only
    /// meaningful for enrolled students — the backend gates the endpoint
    /// on enrollment — so guests / non-enrolled viewers skip it. A
    /// failure just leaves the "Study Together" card hidden.
    private func loadInstructorRoom() async {
        if skipNetwork { return }
        guard !isGuest, isEnrolled else { instructorRoom = nil; return }
        instructorRoom = try? await StudyRoomsAPI.instructorRoom(courseId: courseId)
    }

    /// Re-reads the detail payload. Returns `true` only when the local model
    /// actually changed hands — callers that are about to navigate off it (the
    /// approval route) must know the difference between "refreshed" and "asked
    /// and got nothing", because pushing off a stale model lands on a 403.
    @discardableResult
    func refreshEnrollmentState() async -> Bool {
        if skipNetwork { return true }
        let request = APIRequest(path: "/v1/student/courses/\(courseId)")
        guard let detail = try? await AuthInterceptor.shared.execute(request) as CourseDetail
        else { return false }
        course = detail
        isEnrolled = detail.enrolled
        await loadPendingRequest()
        return true
    }

    // MARK: - Enrollment requests (ADR-0006)

    // MARK: Approval polling
    //
    // While the student sits on a PENDING request they have no way of knowing
    // the instructor let them in — nothing pushes. So we poll
    // `GET /v1/student/courses/{id}/enrollment-request` every
    // `approvalPollInterval`, and the moment the row reads APPROVED we refresh
    // the enrollment state and let the host route into the course.
    //
    // The loop only ever runs when all of the following hold:
    //   • there is an open PENDING request (never for a decided one, and never
    //     when the student has no request at all),
    //   • the screen is on-screen and the app is in the foreground,
    //   • this is a real session (not the guest preview, not a seeded preview),
    //   • we have not already routed on an approval.

    /// Everything that must be true for a poll tick to be worth making.
    private var shouldPollForApproval: Bool {
        pendingRequest?.isPending == true
            && !isEnrolled
            && !isGuest
            && !skipNetwork
            && isScreenActive
            && !didAnnounceApproval
    }

    /// Reconcile the loop with the current state. Every mutation that can open
    /// or close a PENDING request funnels through here, so it is safe (and
    /// expected) to call repeatedly — it starts at most one loop and tears the
    /// loop down the instant there is nothing left to poll for.
    func syncApprovalPolling() {
        guard shouldPollForApproval else { stopApprovalPolling(); return }
        startApprovalPolling()
    }

    /// Host hook: the screen appeared, or the app came back to the foreground.
    ///
    /// Synchronous on purpose, and it owns the task that does the awaiting.
    /// `suspendApprovalPolling()` is synchronous too, so the two are ordered by
    /// the order the hosts call them, and a suspend cancels a resume that was
    /// enqueued but has not run yet. When the hosts owned the task instead
    /// (`Task { await resume() }` at the call site) a resume queued moments
    /// before the app backgrounded would execute *after* the suspend, flip
    /// `isScreenActive` back on and leave a 3 s network loop running behind a
    /// backgrounded app.
    func requestResumeApprovalPolling() {
        approvalResumeTask?.cancel()
        approvalResumeTask = Task { [weak self] in
            await self?.resumeApprovalPolling()
        }
    }

    /// Does an immediate catch-up poll before restarting the loop — approval
    /// very often happens while the app is backgrounded, and making the student
    /// stare at "Pending" for a further full tick after they reopen the app is
    /// exactly the lag this feature exists to remove.
    ///
    /// Only ever reached through `requestResumeApprovalPolling()`, which is
    /// what makes the cancellation check below load-bearing: a suspend that
    /// landed after this was enqueued has already cancelled us, and must not be
    /// undone by a resume that only now got a chance to run.
    private func resumeApprovalPolling() async {
        guard !Task.isCancelled else { return }
        isScreenActive = true
        guard shouldPollForApproval else { stopApprovalPolling(); return }
        // Drop any loop left suspended from the previous foreground run so the
        // catch-up poll can't race a stale tick.
        stopApprovalPolling()
        // Anything other than "still pending" means the catch-up poll already
        // settled it (or the request is gone) — nothing left to loop over.
        guard case .stillPending = await pollApprovalOnce() else { return }
        // A suspend may have landed while that round-trip was open;
        // `startApprovalPolling` re-reads `shouldPollForApproval`, which is
        // already false once `isScreenActive` has been cleared.
        startApprovalPolling()
    }

    /// Host hook: the screen went away, or the app left the foreground
    /// (`.background` *and* `.inactive` — an app in the switcher is not a
    /// screen the student is reading).
    func suspendApprovalPolling() {
        // Cancel first: a resume enqueued before this call must not run after
        // it and turn `isScreenActive` back on behind our back.
        approvalResumeTask?.cancel()
        approvalResumeTask = nil
        isScreenActive = false
        stopApprovalPolling()
    }

    /// Manual "check now", offered after the ceiling stopped the loop. Polls
    /// once and restarts the loop (with a fresh ceiling) if still pending.
    ///
    /// Goes through `requestResumeApprovalPolling()` so a tap racing a
    /// backgrounding is ordered like every other resume. It deliberately does
    /// *not* clear `approvalPollGaveUp` up front — `startApprovalPolling()`
    /// clears it, and only once a loop is genuinely running again. Clearing it
    /// here took the "Check now" affordance away the moment it was tapped, so a
    /// retry that hit a flaky network left the student on a card with no way
    /// back.
    func checkApprovalNow() async {
        requestResumeApprovalPolling()
        await approvalResumeTask?.value
    }

    private func startApprovalPolling() {
        guard shouldPollForApproval else { return }
        guard approvalPollTask == nil else { return }   // never run two loops
        approvalPollGaveUp = false
        approvalPollGeneration &+= 1
        let generation = approvalPollGeneration
        let deadline = Date().addingTimeInterval(Self.approvalPollCeiling)

        approvalPollTask = Task { [weak self] in
            defer { self?.clearApprovalPollTask(generation: generation) }
            var consecutiveFailures = 0
            while !Task.isCancelled {
                let delay = Self.approvalPollDelay(
                    consecutiveFailures: consecutiveFailures)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled, let vm = self else { return }
                // Checked after the sleep so a loop that was suspended and
                // resumed doesn't inherit a stale deadline.
                if Date() >= deadline {
                    vm.approvalPollGaveUp = true
                    return
                }
                switch await vm.pollApprovalOnce() {
                case .stillPending:
                    consecutiveFailures = 0
                case .skipped:
                    break                      // request still open; don't stack
                case .transientFailure:
                    consecutiveFailures += 1   // swallowed: no toast, no banner
                case .settled:
                    return
                }
            }
        }
    }

    private func stopApprovalPolling() {
        approvalPollTask?.cancel()
        approvalPollTask = nil
        // Invalidate the running task's teardown so it can't null out a loop
        // started after it was cancelled.
        approvalPollGeneration &+= 1
    }

    private func clearApprovalPollTask(generation: Int) {
        guard generation == approvalPollGeneration else { return }
        approvalPollTask = nil
    }

    /// Base cadence, doubled per consecutive failure and capped, so a flapping
    /// network degrades into an occasional retry rather than a tight retry loop.
    private static func approvalPollDelay(consecutiveFailures: Int) -> TimeInterval {
        let doublings = min(consecutiveFailures, approvalPollMaxBackoffDoublings)
        return approvalPollInterval * pow(2, Double(doublings))
    }

    /// Outcome of one poll tick.
    private enum ApprovalPollOutcome {
        /// Still PENDING — keep going at the base cadence.
        case stillPending
        /// A previous round-trip was still open; this tick made no request.
        case skipped
        /// Offline / 5xx / decode hiccup. Swallowed on purpose: a poll is a
        /// background nicety and must never paint an error over a readable
        /// screen, let alone once every tick.
        case transientFailure
        /// Terminal — approved, rejected, cancelled, or the request is gone.
        case settled
    }

    /// One poll tick. Never throws and never touches `errorMessage`.
    @discardableResult
    private func pollApprovalOnce() async -> ApprovalPollOutcome {
        guard !isApprovalPollInFlight else { return .skipped }
        isApprovalPollInFlight = true
        defer { isApprovalPollInFlight = false }

        let latest: EnrollmentRequest?
        do {
            latest = try await EnrollmentRequestService.latest(courseId: courseId)
        } catch {
            // Cancellation is teardown, not a network failure — don't back off.
            if APIClient.isCancellationError(error) { return .settled }
            // A 401 that survived the interceptor's refresh is not transient:
            // the session is gone and every later tick will fail identically.
            // Take the app's normal unauthenticated path, exactly like every
            // other call — silently backing off here left the student watching
            // a "waiting for approval" card while logged out.
            if let droob = error as? DroobError, case .unauthenticated(_, _) = droob {
                AuthSession.shared.handleUnauthenticated()
                return .settled
            }
            return .transientFailure
        }

        // 404 → the student has no request for this course. A normal answer,
        // not an error: there is simply nothing left to poll.
        guard let latest else {
            pendingRequest = nil
            return .settled
        }

        switch latest.status {
        case .pending:
            // Keep the local copy fresh so an edited note stays in sync.
            pendingRequest = latest
            return .stillPending
        case .approved:
            // Only terminal once the local model has actually caught up. If the
            // refresh failed we are still approved but not yet safe to route
            // off, so report a failure and let the backoff try again rather
            // than announcing into a screen that would 403.
            return await handleApprovalDiscovered() ? .settled : .transientFailure
        case .rejected, .cancelled:
            // Stop and reflect it in the UI. Explicitly no navigation.
            pendingRequest = nil
            requestDecision = latest.status
            return .settled
        case .unknown:
            // A status this build doesn't recognise is still a decision — the
            // row will never read PENDING again, so stop rather than spin.
            pendingRequest = nil
            return .settled
        }
    }

    /// APPROVED. Refresh the course/enrollment state *first* so the local model
    /// says "enrolled" before anyone navigates — pushing into the course off a
    /// stale model lands on a screen that immediately 403s. Only then announce
    /// it, exactly once.
    ///
    /// Returns `false` when the refresh didn't land, i.e. the hosts must not
    /// route yet. Forcing `isEnrolled = true` on a failed refresh (on the
    /// grounds that the approval is authoritative) papered over exactly the
    /// case this guard exists for: `course` kept its stale `enrolled == false`
    /// payload and the push handed `CurriculumView` a model the backend
    /// disagrees with. The approval row isn't going anywhere — the caller
    /// retries on the next tick, which is cheap and always converges (the
    /// backend creates the enrollment in the same transaction as the approval).
    private func handleApprovalDiscovered() async -> Bool {
        guard await refreshEnrollmentState(), isEnrolled else { return false }
        pendingRequest = nil
        requestDecision = nil
        guard !didAnnounceApproval else { return true }
        didAnnounceApproval = true
        approvalPollGaveUp = false
        approvalDetected = true
        return true
    }

    /// Fetch the caller's open PENDING request for this course (if any) via the
    /// same single-row endpoint the poll uses. An approved request shows up as
    /// `enrolled` on the detail payload, so we only look when not enrolled.
    /// Best-effort — a failure just leaves the button in "Request to Enroll".
    private func loadPendingRequest() async {
        if skipNetwork { return }
        // Guests have no account, hence no enrollment requests to look up.
        guard !isGuest else { pendingRequest = nil; return }
        guard !isEnrolled else { pendingRequest = nil; return }
        // Only overwrite local state on a definite answer: a 404 (nil) means
        // "no request, clear it", a throw means "couldn't ask, keep what we
        // had" — collapsing the two would drop a pending request offline.
        let latest: EnrollmentRequest?
        do {
            latest = try await EnrollmentRequestService.latest(courseId: courseId)
        } catch {
            return
        }
        pendingRequest = latest?.isPending == true ? latest : nil
        if let status = latest?.status, status == .rejected || status == .cancelled {
            requestDecision = status
        } else {
            // Pending again (or approved) — drop any stale decision notice.
            requestDecision = nil
        }
    }

    /// Open an enrollment request for this course. Normally this creates a
    /// PENDING request (`.requestSent` → the sheet shows its "Request Sent"
    /// confirmation). When the backend auto-approves on create (testing mode),
    /// the response comes back APPROVED: the student is enrolled immediately, so
    /// we flip local enrolled state, drop any pending state, and report
    /// `.autoEnrolled` so the host can route to the Courses tab instead of
    /// showing a misleading "Request Sent" screen.
    func requestEnrollment(note: String?) async -> RequestEnrollmentResult {
        if skipNetwork {
            let now = Date()
            pendingRequest = EnrollmentRequest(
                id: "preview-req",
                courseId: courseId,
                courseTitleEn: course?.titleEn ?? "",
                courseTitleAr: course?.titleAr ?? "",
                courseCoverUrl: course?.coverUrl,
                instructorId: "preview",
                instructorName: course?.instructorName,
                instructorTitleEn: nil,
                instructorTitleAr: nil,
                note: note,
                status: .pending,
                createdAt: now,
                updatedAt: now,
                decidedAt: nil)
            return .requestSent
        }
        do {
            let created = try await EnrollmentRequestService.create(
                courseId: courseId, note: note)
            if created.status == .approved {
                // Auto-approved: there is no PENDING request to manage, the
                // student now has access. Refresh the detail in the background
                // so the button flips to "Continue learning" if they come back.
                pendingRequest = nil
                isEnrolled = true
                Task { await refreshEnrollmentState() }
                return .autoEnrolled
            }
            pendingRequest = created
            // A fresh request clears any notice left by an earlier decision.
            requestDecision = nil
            syncApprovalPolling()
            return .requestSent
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = error.errorDescription
            }
            return .failed
        } catch {
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    /// Edit the note on the current PENDING request. No-op when there's no
    /// pending request to edit.
    func editPendingNote(note: String?) async -> Bool {
        guard let pending = pendingRequest else { return false }
        if skipNetwork { return true }
        do {
            pendingRequest = try await EnrollmentRequestService.editNote(
                requestId: pending.id, note: note)
            return true
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = error.errorDescription
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Withdraw the current PENDING request (→ CANCELLED). Clears the
    /// pending state on success so the button falls back to "Request to
    /// Enroll" (the student may re-request).
    func cancelPendingRequest() async -> Bool {
        guard let pending = pendingRequest else { return false }
        if skipNetwork {
            pendingRequest = nil
            return true
        }
        do {
            _ = try await EnrollmentRequestService.cancel(requestId: pending.id)
            pendingRequest = nil
            syncApprovalPolling()
            return true
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = error.errorDescription
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Free enrollment — the app has no payment. Hits `/subscribe` (which
    /// simply enrolls the student) and refreshes state so the UI flips to
    /// "Continue learning".
    func enroll() async {
        if skipNetwork { isEnrolled = true; return }
        isEnrolling = true
        defer { isEnrolling = false }
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/subscribe", method: .POST)
        do {
            _ = try await AuthInterceptor.shared.execute(request) as EnrollmentResponse
            await refreshEnrollmentState()
        } catch let e as DroobError {
            if case .unauthenticated(_, _) = e {
                AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = e.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Wire body for `POST /v1/student/courses/{id}/reviews`. Mirrors
    /// the Java `SubmitReviewRequest` record: stars in 1–5, optional
    /// free-text body (server caps at 2000 chars; client-side we trim
    /// blank to nil so empty editors don't poison the histogram).
    private struct SubmitReviewBody: Encodable {
        let stars: Int
        let body: String?
    }

    /// Upsert the current user's review for this course. Returns `true`
    /// on success so the rate sheet can swap to the thank-you state.
    /// On success we re-fetch the detail payload so the histogram, the
    /// recent-reviews preview, and the cached aggregates update without
    /// a manual reload from the user.
    func submitReview(stars: Int, body: String?) async -> Bool {
        if skipNetwork { return true }
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/reviews",
            method: .POST,
            body: SubmitReviewBody(stars: stars, body: body))
        do {
            _ = try await AuthInterceptor.shared.execute(request) as CourseReviewItem
            await refreshEnrollmentState()
            return true
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = error.errorDescription
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Returns a view-model pre-populated with the Figma reference course so
    /// the launch-arg preview hosts can render without a live backend.
    static func previewSeeded() -> CourseDetailViewModel {
        let vm = CourseDetailViewModel(courseId: "ux-fundamentals")
        vm.skipNetwork = true
        vm.isLoading = false
        vm.isEnrolled = true

        let module1 = CourseSection(
            id: "m1",
            titleEn: "Design Thinking",
            titleAr: "التفكير التصميمي",
            sortOrder: 0,
            lessonCount: 5,
            completedLessonCount: 5,
            status: "completed",
            lessons: [], quizId: nil, quizzes: nil, contentType: "CURRICULUM"
        )
        let module2 = CourseSection(
            id: "m2",
            titleEn: "Research Methods",
            titleAr: "طرق البحث",
            sortOrder: 1,
            lessonCount: 6,
            completedLessonCount: 6,
            status: "completed",
            lessons: [], quizId: nil, quizzes: nil, contentType: "CURRICULUM"
        )
        let module3 = CourseSection(
            id: "m3",
            titleEn: "Interaction Design",
            titleAr: "تصميم التفاعل",
            sortOrder: 2,
            lessonCount: 6,
            completedLessonCount: 4,
            status: "in_progress",
            lessons: [], quizId: nil, quizzes: nil, contentType: "CURRICULUM"
        )
        let module4 = CourseSection(
            id: "m4",
            titleEn: "Visual Systems",
            titleAr: "الأنظمة البصرية",
            sortOrder: 3,
            lessonCount: 8,
            completedLessonCount: 0,
            status: "not_started",
            lessons: [], quizId: nil, quizzes: nil, contentType: "CURRICULUM"
        )

        vm.course = CourseDetail(
            id: "ux-fundamentals",
            titleEn: "UX/UI Fundamentals: Design with Intention",
            titleAr: "أساسيات تصميم تجربة المستخدم: التصميم بنية",
            descriptionEn: nil,
            descriptionAr: nil,
            coverUrl: nil,
            instructorName: "Dr. Layla Hassan",
            priceCents: 0,
            currency: "SAR",
            enrolled: true,
            lessonCount: 32,
            completedLessonCount: 27,
            totalDurationMinutes: 18 * 60,
            studentsCount: 1240,
            ratingAvg: 4.8,
            ratingCount: 512,
            isBestseller: true,
            progressPct: 84,
            nextLessonId: "lesson-motion",
            nextLessonTitleEn: "Motion Principles",
            nextLessonTitleAr: "مبادئ الحركة",
            sections: [module1, module2, module3, module4],
            pinnedFaqs: [
                PinnedFaqItem(
                    id: "f1",
                    question: "Do I need prior design experience?",
                    answer: "No — the course starts from first principles.",
                    position: 0),
                PinnedFaqItem(
                    id: "f2",
                    question: "Will I get a certificate when I finish?",
                    answer: "Yes — you'll receive a verified certificate of completion once you finish all modules and pass the final quiz.",
                    position: 1),
                PinnedFaqItem(
                    id: "f3",
                    question: "What software do I need?",
                    answer: "Figma is recommended (free plan is enough), but any vector design tool works.",
                    position: 2),
            ]
        )
        return vm
    }
}
