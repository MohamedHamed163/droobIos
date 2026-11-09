import Foundation
import SwiftUI

// MARK: - Models

struct CourseSummary: Decodable, Identifiable, Equatable {
    let id: String
    let titleEn: String
    let titleAr: String
    let subtitleEn: String?
    let subtitleAr: String?
    let coverUrl: String?
    let instructorName: String
    /// Presigned instructor avatar URL (nullable). Drives the small
    /// instructor avatar on the Explore course card; falls back to
    /// initials when nil/blank or the image fails to load.
    let instructorAvatarUrl: String?
    let priceCents: Int
    let currency: String
    let enrolled: Bool
    let categorySlug: String?
    let categoryNameEn: String?
    let categoryNameAr: String?
    /// Average rating (0…5). Optional because brand-new courses with no
    /// ratings yet have a NULL `rating_avg` on the backend.
    let ratingAvg: Double?
    let ratingCount: Int
    /// Uppercase enum string from the backend (`BEGINNER` / `INTERMEDIATE`
    /// / `ADVANCED`) or `nil` when the instructor hasn't set a level.
    let level: String?
    /// Total published lessons across all sections of the course. Drives
    /// the "{N} lessons · ★ {rating}" line on the Explore card. Server
    /// always sends this field (zero for new courses); the decoder
    /// tolerates an absent value so older fixtures and preview seeds
    /// don't have to be updated.
    let lessonCount: Int
    /// Number of students enrolled — mirrors the cached
    /// `students_count` counter the backend maintains on each course.
    /// Drives the trailing "{M} enrolled" label on the Explore card.
    let enrollmentCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case titleEn = "title_en"
        case titleAr = "title_ar"
        case subtitleEn = "subtitle_en"
        case subtitleAr = "subtitle_ar"
        case coverUrl = "cover_url"
        case instructorName = "instructor_name"
        case instructorAvatarUrl = "instructor_avatar_url"
        case priceCents = "price_cents"
        case currency
        case enrolled
        case categorySlug = "category_slug"
        case categoryNameEn = "category_name_en"
        case categoryNameAr = "category_name_ar"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case level
        case lessonCount = "lesson_count"
        case enrollmentCount = "enrollment_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        titleEn         = try c.decode(String.self, forKey: .titleEn)
        titleAr         = try c.decode(String.self, forKey: .titleAr)
        subtitleEn      = try c.decodeIfPresent(String.self, forKey: .subtitleEn)
        subtitleAr      = try c.decodeIfPresent(String.self, forKey: .subtitleAr)
        coverUrl        = try c.decodeIfPresent(String.self, forKey: .coverUrl)
        instructorName  = try c.decode(String.self, forKey: .instructorName)
        instructorAvatarUrl = try c.decodeIfPresent(String.self, forKey: .instructorAvatarUrl)
        priceCents      = try c.decode(Int.self, forKey: .priceCents)
        currency        = try c.decode(String.self, forKey: .currency)
        enrolled        = try c.decode(Bool.self, forKey: .enrolled)
        categorySlug    = try c.decodeIfPresent(String.self, forKey: .categorySlug)
        categoryNameEn  = try c.decodeIfPresent(String.self, forKey: .categoryNameEn)
        categoryNameAr  = try c.decodeIfPresent(String.self, forKey: .categoryNameAr)
        ratingAvg       = try c.decodeIfPresent(Double.self, forKey: .ratingAvg)
        ratingCount     = try c.decodeIfPresent(Int.self, forKey: .ratingCount) ?? 0
        level           = try c.decodeIfPresent(String.self, forKey: .level)
        lessonCount     = try c.decodeIfPresent(Int.self, forKey: .lessonCount) ?? 0
        enrollmentCount = try c.decodeIfPresent(Int.self, forKey: .enrollmentCount) ?? 0
    }

    /// Test/preview seed only — production decoder is the only path used at runtime.
    init(id: String, titleEn: String, titleAr: String, subtitleEn: String?, subtitleAr: String?,
         coverUrl: String?, instructorName: String, instructorAvatarUrl: String? = nil,
         priceCents: Int, currency: String,
         enrolled: Bool, categorySlug: String? = nil, categoryNameEn: String? = nil,
         categoryNameAr: String? = nil, ratingAvg: Double? = nil, ratingCount: Int = 0,
         level: String? = nil, lessonCount: Int = 0, enrollmentCount: Int = 0) {
        self.id = id; self.titleEn = titleEn; self.titleAr = titleAr
        self.subtitleEn = subtitleEn; self.subtitleAr = subtitleAr
        self.coverUrl = coverUrl; self.instructorName = instructorName
        self.instructorAvatarUrl = instructorAvatarUrl
        self.priceCents = priceCents; self.currency = currency; self.enrolled = enrolled
        self.categorySlug = categorySlug
        self.categoryNameEn = categoryNameEn
        self.categoryNameAr = categoryNameAr
        self.ratingAvg = ratingAvg
        self.ratingCount = ratingCount
        self.level = level
        self.lessonCount = lessonCount
        self.enrollmentCount = enrollmentCount
    }

    func localizedTitle(locale: String) -> String {
        L10n.localized(locale, ar: titleAr, en: titleEn)
    }

    func localizedSubtitle(locale: String) -> String? {
        L10n.localized(locale, ar: subtitleAr, en: subtitleEn)
    }

    func localizedCategoryName(locale: String) -> String? {
        L10n.localized(locale, ar: categoryNameAr, en: categoryNameEn)
    }

    var formattedPrice: String {
        CurrencyFormat.formatted(priceCents: priceCents, currency: currency)
    }
}

// MARK: - Category

struct CourseCategoryDto: Decodable, Identifiable, Equatable, Hashable {
    let id: String
    let slug: String
    let nameEn: String
    let nameAr: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, slug
        case nameEn = "name_en"
        case nameAr = "name_ar"
        case sortOrder = "sort_order"
    }

    func localizedName(locale: String) -> String {
        L10n.localized(locale, ar: nameAr, en: nameEn)
    }
}

// MARK: - Enrolled Course

struct EnrolledCourse: Decodable, Identifiable {
    let id: String
    let titleEn: String
    let titleAr: String
    let instructorId: String?
    let instructorName: String
    /// Presigned instructor avatar URL (nullable). Sourced up into the
    /// Enrolled-tab instructor group header; falls back to initials when
    /// nil/blank or the image fails to load.
    let instructorAvatarUrl: String?
    let instructorTitleEn: String?
    let instructorTitleAr: String?
    let progressPct: Double
    let completedAt: Date?
    let lastActiveAt: Date?
    let enrolledAt: Date?
    let lessonCount: Int
    let completedLessonCount: Int
    let liveSessionCount: Int
    let nextLessonId: String?
    let nextLessonTitleEn: String?
    let nextLessonTitleAr: String?
    let coverUrl: String?
    /// Total video seconds across the course's lessons. The Home
    /// "Continue Learning" card renders "{watched} / {total} watched"
    /// where watched = totalDurationSeconds × progressPct. 0 when the
    /// backend omits it (older builds) or the course has no video.
    let totalDurationSeconds: Int

    enum CodingKeys: String, CodingKey {
        case id
        case titleEn = "title_en"
        case titleAr = "title_ar"
        case instructorId = "instructor_id"
        case instructorName = "instructor_name"
        case instructorAvatarUrl = "instructor_avatar_url"
        case instructorTitleEn = "instructor_title_en"
        case instructorTitleAr = "instructor_title_ar"
        case progressPct = "progress_pct"
        case completedAt = "completed_at"
        case lastActiveAt = "last_active_at"
        case enrolledAt = "enrolled_at"
        case lessonCount = "lesson_count"
        case completedLessonCount = "completed_lesson_count"
        case liveSessionCount = "live_session_count"
        case nextLessonId = "next_lesson_id"
        case nextLessonTitleEn = "next_lesson_title_en"
        case nextLessonTitleAr = "next_lesson_title_ar"
        case coverUrl = "cover_url"
        case totalDurationSeconds = "total_duration_seconds"
    }

    init(
        id: String, titleEn: String, titleAr: String,
        instructorId: String? = nil,
        instructorName: String,
        instructorAvatarUrl: String? = nil,
        instructorTitleEn: String? = nil, instructorTitleAr: String? = nil,
        progressPct: Double,
        completedAt: Date?, lastActiveAt: Date?, enrolledAt: Date?,
        lessonCount: Int, completedLessonCount: Int,
        liveSessionCount: Int = 0,
        nextLessonId: String?, nextLessonTitleEn: String?, nextLessonTitleAr: String?,
        coverUrl: String? = nil,
        totalDurationSeconds: Int = 0
    ) {
        self.id = id; self.titleEn = titleEn; self.titleAr = titleAr
        self.instructorId = instructorId
        self.instructorName = instructorName
        self.instructorAvatarUrl = instructorAvatarUrl
        self.instructorTitleEn = instructorTitleEn; self.instructorTitleAr = instructorTitleAr
        self.progressPct = progressPct
        self.completedAt = completedAt; self.lastActiveAt = lastActiveAt; self.enrolledAt = enrolledAt
        self.lessonCount = lessonCount; self.completedLessonCount = completedLessonCount
        self.liveSessionCount = liveSessionCount
        self.nextLessonId = nextLessonId; self.nextLessonTitleEn = nextLessonTitleEn; self.nextLessonTitleAr = nextLessonTitleAr
        self.coverUrl = coverUrl
        self.totalDurationSeconds = totalDurationSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try c.decode(String.self, forKey: .id)
        titleEn              = try c.decode(String.self, forKey: .titleEn)
        titleAr              = try c.decode(String.self, forKey: .titleAr)
        instructorId         = try c.decodeIfPresent(String.self, forKey: .instructorId)
        instructorName       = try c.decode(String.self, forKey: .instructorName)
        instructorAvatarUrl  = try c.decodeIfPresent(String.self, forKey: .instructorAvatarUrl)
        instructorTitleEn    = try c.decodeIfPresent(String.self, forKey: .instructorTitleEn)
        instructorTitleAr    = try c.decodeIfPresent(String.self, forKey: .instructorTitleAr)
        progressPct          = try c.decode(Double.self, forKey: .progressPct)
        completedAt          = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        lastActiveAt         = try c.decodeIfPresent(Date.self, forKey: .lastActiveAt)
        enrolledAt           = try c.decodeIfPresent(Date.self, forKey: .enrolledAt)
        lessonCount          = (try? c.decode(Int.self, forKey: .lessonCount)) ?? 0
        completedLessonCount = (try? c.decode(Int.self, forKey: .completedLessonCount)) ?? 0
        liveSessionCount     = (try? c.decode(Int.self, forKey: .liveSessionCount)) ?? 0
        nextLessonId         = try c.decodeIfPresent(String.self, forKey: .nextLessonId)
        nextLessonTitleEn    = try c.decodeIfPresent(String.self, forKey: .nextLessonTitleEn)
        nextLessonTitleAr    = try c.decodeIfPresent(String.self, forKey: .nextLessonTitleAr)
        coverUrl             = try c.decodeIfPresent(String.self, forKey: .coverUrl)
        totalDurationSeconds = (try? c.decode(Int.self, forKey: .totalDurationSeconds)) ?? 0
    }

    func localizedTitle(locale: String) -> String {
        L10n.localized(locale, ar: titleAr, en: titleEn)
    }

    func localizedInstructorTitle(locale: String) -> String? {
        return L10n.localized(locale, ar: instructorTitleAr, en: instructorTitleEn)
    }

    func localizedNextLessonTitle(locale: String) -> String? {
        return L10n.localized(locale, ar: nextLessonTitleAr, en: nextLessonTitleEn)
    }

    var isCompleted: Bool { progressPct >= 100 }
    var isInProgress: Bool { progressPct > 0 && !isCompleted }

    /// Deterministic SF Symbol used as a course cover when no image exists.
    /// (Replaces the old emoji set — no emoji in the UI.)
    var coverSymbol: String {
        let symbols = ["graduationcap.fill", "book.fill", "paintbrush.fill",
                       "chart.bar.fill", "lightbulb.fill", "laptopcomputer",
                       "globe", "function"]
        return symbols[abs(id.hashValue) % symbols.count]
    }

    var coverColor: Color {
        let colors: [Color] = [
            Color(red: 0.20, green: 0.10, blue: 0.30),  // purple
            Color(red: 0.05, green: 0.18, blue: 0.14),  // dark green
            Color(red: 0.18, green: 0.10, blue: 0.05),  // dark brown
            Color(red: 0.08, green: 0.14, blue: 0.22),  // dark blue
            Color(red: 0.22, green: 0.11, blue: 0.04),  // burnt orange dark
        ]
        return colors[abs(id.hashValue) % colors.count]
    }
}

// MARK: - Home Dashboard

struct HomeDashboard: Decodable {
    let enrolledCount: Int
    let inProgressCount: Int
    let completedCount: Int
    let streakDays: Int
    let watchedMinutes: Int
    let continueLearning: EnrolledCourse?

    enum CodingKeys: String, CodingKey {
        case enrolledCount = "enrolled_count"
        case inProgressCount = "in_progress_count"
        case completedCount = "completed_count"
        case streakDays = "streak_days"
        case watchedMinutes = "watched_minutes"
        case continueLearning = "continue_learning"
    }
}

// MARK: - HomeViewModel

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var dashboard: HomeDashboard? = nil
    @Published var recentEnrollments: [EnrolledCourse] = []
    @Published var featuredCourses: [CourseSummary] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            let dash: HomeDashboard = try await AuthInterceptor.shared.execute(
                APIRequest(path: "/v1/student/dashboard", method: .GET)
            )
            dashboard = dash

            let enrollments: [EnrolledCourse] = try await AuthInterceptor.shared.execute(
                APIRequest(path: "/v1/student/enrollments", method: .GET)
            )
            recentEnrollments = Array(enrollments.prefix(2))

            if enrollments.isEmpty {
                let page: SpringPage<CourseSummary> = try await AuthInterceptor.shared.execute(
                    APIRequest(path: "/v1/student/courses", method: .GET,
                               queryItems: [URLQueryItem(name: "page", value: "0"),
                                            URLQueryItem(name: "size", value: "3")])
                )
                featuredCourses = page.content
            }
        } catch let error where APIClient.isCancellationError(error) {
            isLoading = false
            return
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Student Progress

struct StudentProgress: Decodable {
    let learningScore: Int
    let cohortPercentile: Int
    let xpThisWeek: Int
    let streakDays: Int
    let watchTimeHours: Int
    let lessonsCompleted: Int
    let certificatesCount: Int
    let courseProgress: [CourseProgressItem]

    struct CourseProgressItem: Decodable, Identifiable {
        let courseId: String
        let titleEn: String
        let titleAr: String
        let pct: Int
        var id: String { courseId }
        enum CodingKeys: String, CodingKey {
            case courseId = "course_id"
            case titleEn = "title_en"
            case titleAr = "title_ar"
            case pct
        }
    }

    enum CodingKeys: String, CodingKey {
        case learningScore = "learning_score"
        case cohortPercentile = "cohort_percentile"
        case xpThisWeek = "xp_this_week"
        case streakDays = "streak_days"
        case watchTimeHours = "watch_time_hours"
        case lessonsCompleted = "lessons_completed"
        case certificatesCount = "certificates_count"
        case courseProgress = "course_progress"
    }
}

@MainActor
final class ProgressViewModel: ObservableObject {
    @Published var progress: StudentProgress? = nil
    @Published var isLoading = true
    @Published var error: String? = nil

    func load() async {
        isLoading = true
        error = nil
        do {
            let p: StudentProgress = try await AuthInterceptor.shared.execute(
                APIRequest(path: "/v1/student/progress")
            )
            progress = p
        } catch let e where APIClient.isCancellationError(e) {
            isLoading = false
            return
        } catch let e as DroobError {
            if case .unauthenticated(_, _) = e {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                error = e.errorDescription
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - SpringPage

struct SpringPage<T: Decodable>: Decodable {
    let content: [T]
    let totalElements: Int
    let totalPages: Int
    let number: Int
    let size: Int

    var hasNextPage: Bool { number < totalPages - 1 }
}

// MARK: - CatalogViewModel

@MainActor
final class CatalogViewModel: ObservableObject {
    @Published var courses: [CourseSummary] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String? = nil
    @Published var hasNextPage: Bool = false
    @Published var categories: [CourseCategoryDto] = []
    @Published private(set) var selectedCategorySlug: String? = nil
    /// Uppercase enum string (`BEGINNER` / `INTERMEDIATE` / `ADVANCED`) or
    /// `nil` for "All Levels". Sent as the `level` query param so the
    /// filter narrows pages server-side instead of just the loaded slice.
    @Published private(set) var selectedLevel: String? = nil
    /// Uppercase wire token sent as the `sort` query param
    /// (`RECENT` / `POPULAR` / `RATING` / `PRICE_ASC` / `PRICE_DESC`).
    /// Defaults to `RECENT` so the first page load matches the backend
    /// default ordering — keeps server logs self-describing.
    @Published private(set) var selectedSort: String = "RECENT"

    private var currentPage: Int = 0
    private let pageSize: Int = 20

    /// Loads page 0 with the currently-selected category filter. Pass a new
    /// `category` to switch filters; passing `nil` clears the filter back to "All".
    func loadInitial(category: String? = nil) async {
        selectedCategorySlug = category
        await fetchPage(0)
    }

    /// Updates the server-side level filter and reloads from page 0. Pass
    /// `nil` to clear back to "All Levels". A no-op when the requested
    /// value matches the current selection so re-applying the same filter
    /// doesn't re-fetch.
    func applyLevelFilter(_ level: String?) async {
        if selectedLevel == level { return }
        selectedLevel = level
        await fetchPage(0)
    }

    /// Updates the server-side sort and reloads from page 0. No-op when
    /// the requested sort already matches the current selection — the
    /// sort sheet re-fires `onSelect` on every tap so we filter the
    /// dupes here rather than at the call site.
    func applySort(_ sort: String) async {
        if selectedSort == sort { return }
        selectedSort = sort
        await fetchPage(0)
    }

    func loadCategories() async {
        // Categories are platform-curated and rarely change; hold the cached
        // list across re-entries so the chip row doesn't flicker on
        // re-entering the Explore tab.
        if !categories.isEmpty { return }
        let request = APIRequest(path: "/v1/student/categories", method: .GET)
        do {
            let cats: [CourseCategoryDto] = try await AuthInterceptor.shared.execute(request)
            categories = cats
        } catch {
            // Silent failure — chip row simply won't render; "All" filter still works.
        }
    }

    func loadMore() async {
        guard hasNextPage, !isLoadingMore else { return }
        await fetchPage(currentPage + 1)
    }

    private func fetchPage(_ page: Int) async {
        if page == 0 {
            isLoading = true
            errorMessage = nil
        } else {
            isLoadingMore = true
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "size", value: "\(pageSize)")
        ]
        if let slug = selectedCategorySlug, !slug.isEmpty {
            queryItems.append(URLQueryItem(name: "category", value: slug))
        }
        if let lvl = selectedLevel, !lvl.isEmpty {
            queryItems.append(URLQueryItem(name: "level", value: lvl))
        }
        queryItems.append(URLQueryItem(name: "sort", value: selectedSort))
        let request = APIRequest(
            path: "/v1/student/courses",
            method: .GET,
            queryItems: queryItems
        )

        do {
            let result: SpringPage<CourseSummary> = try await AuthInterceptor.shared.execute(request)
            if page == 0 {
                courses = result.content
            } else {
                courses.append(contentsOf: result.content)
            }
            currentPage = result.number
            hasNextPage = result.hasNextPage
        } catch let error where APIClient.isCancellationError(error) {
            // Pull-to-refresh task cancelled — silently bail.
            isLoading = false
            isLoadingMore = false
            return
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        isLoadingMore = false
    }
}

/// Two-level Optional used by `HomeDashboardViewModel.loadNextSession` to
/// distinguish "fetch failed → keep cached value" (outer nil) from
/// "fetch succeeded but no upcoming session → clear cached value"
/// (outer `.some`, inner `nil`).
struct OptionalLoad<T> {
    let value: T
}

/// One row in the home-screen "Recommended for you" rail. Wraps a
/// `CourseSummary` with the prerequisite course the student already
/// owns that drove the recommendation, so the card's "Because you
/// enrolled in {X}" pill can render on first paint.
///
/// The reason fields are optional because the backend leaves them
/// null if the prereq is unpublished between the ranking and reason
/// queries — the card hides the pill in that case rather than showing
/// a broken phrase.
struct RecommendedCourse: Decodable, Identifiable, Equatable {
    let course: CourseSummary
    let reasonCourseId: String?
    let reasonCourseTitleEn: String?
    let reasonCourseTitleAr: String?

    /// `Identifiable` is sourced from the wrapped course so SwiftUI's
    /// `ForEach` reuses cells correctly across reorders.
    var id: String { course.id }

    enum CodingKeys: String, CodingKey {
        case course
        case reasonCourseId = "reason_course_id"
        case reasonCourseTitleEn = "reason_course_title_en"
        case reasonCourseTitleAr = "reason_course_title_ar"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.course = try c.decode(CourseSummary.self, forKey: .course)
        self.reasonCourseId = try c.decodeIfPresent(String.self, forKey: .reasonCourseId)
        self.reasonCourseTitleEn = try c.decodeIfPresent(String.self, forKey: .reasonCourseTitleEn)
        self.reasonCourseTitleAr = try c.decodeIfPresent(String.self, forKey: .reasonCourseTitleAr)
    }

    /// Preview/test seed.
    init(course: CourseSummary,
         reasonCourseId: String? = nil,
         reasonCourseTitleEn: String? = nil,
         reasonCourseTitleAr: String? = nil) {
        self.course = course
        self.reasonCourseId = reasonCourseId
        self.reasonCourseTitleEn = reasonCourseTitleEn
        self.reasonCourseTitleAr = reasonCourseTitleAr
    }

    func localizedReasonTitle(locale: String) -> String? {
        L10n.localized(locale, ar: reasonCourseTitleAr, en: reasonCourseTitleEn)
    }
}

// MARK: - Home aggregate payload (GET /v1/student/home)

/// Header block of the Home screen.
struct HomeGreeting: Decodable, Equatable {
    let firstName: String
    let displayName: String
    let initials: String
    let avatarUrl: String?
    let unreadNotificationsCount: Int

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case displayName = "display_name"
        case initials
        case avatarUrl = "avatar_url"
        case unreadNotificationsCount = "unread_notifications_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstName = (try? c.decode(String.self, forKey: .firstName)) ?? ""
        displayName = (try? c.decode(String.self, forKey: .displayName)) ?? ""
        initials = (try? c.decode(String.self, forKey: .initials)) ?? ""
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        unreadNotificationsCount = (try? c.decode(Int.self, forKey: .unreadNotificationsCount)) ?? 0
    }

    init(firstName: String, displayName: String, initials: String,
         avatarUrl: String? = nil, unreadNotificationsCount: Int = 0) {
        self.firstName = firstName; self.displayName = displayName
        self.initials = initials; self.avatarUrl = avatarUrl
        self.unreadNotificationsCount = unreadNotificationsCount
    }
}

/// The "Next Session" card payload — `can_join` mirrors the 15-min-before-start
/// window the backend evaluates.
struct HomeNextSession: Decodable, Identifiable, Equatable {
    let id: String
    let titleEn: String
    let titleAr: String
    let startsAt: Date
    let durationMinutes: Int
    let joinUrl: String?
    let status: String
    let instructorName: String
    let canJoin: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case titleEn = "title_en"
        case titleAr = "title_ar"
        case startsAt = "starts_at"
        case durationMinutes = "duration_minutes"
        case joinUrl = "join_url"
        case status
        case instructorName = "instructor_name"
        case canJoin = "can_join"
    }

    func localizedTitle(locale: String) -> String { L10n.localized(locale, ar: titleAr, en: titleEn) }
    var isLive: Bool { status == "LIVE" }
}

/// One-shot payload for the redesigned Home screen.
struct StudentHomePayload: Decodable {
    let greeting: HomeGreeting
    let continueLearning: [EnrolledCourse]
    let recommendedCourses: [RecommendedCourse]
    let exploreInstructors: [StudentInstructorSummary]
    let nextSession: HomeNextSession?

    enum CodingKeys: String, CodingKey {
        case greeting
        case continueLearning = "continue_learning"
        case recommendedCourses = "recommended_courses"
        case exploreInstructors = "explore_instructors"
        case nextSession = "next_session"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        greeting = try c.decode(HomeGreeting.self, forKey: .greeting)
        continueLearning = (try? c.decode([EnrolledCourse].self, forKey: .continueLearning)) ?? []
        recommendedCourses = (try? c.decode([RecommendedCourse].self, forKey: .recommendedCourses)) ?? []
        exploreInstructors = (try? c.decode([StudentInstructorSummary].self, forKey: .exploreInstructors)) ?? []
        nextSession = try c.decodeIfPresent(HomeNextSession.self, forKey: .nextSession)
    }
}

// MARK: - HomeDashboardViewModel

@MainActor
final class HomeDashboardViewModel: ObservableObject {
    @Published var greeting: HomeGreeting?
    @Published var enrollments: [EnrolledCourse] = []
    @Published var instructors: [StudentInstructorSummary] = []
    @Published var homeNextSession: HomeNextSession?
    /// Home "Recommended for you" rail. Sourced from
    /// `/v1/student/recommendations`, which ranks PUBLISHED courses by
    /// how many of the student's enrolled courses appear in the
    /// candidate's instructor-declared prerequisite list (match ratio).
    /// Each row also carries the prereq the student already owns that
    /// drove the match, so the card pill ("Because you enrolled in
    /// {X}") renders on first paint without a follow-up request. The
    /// backend returns an empty list for accounts with no enrollments
    /// — the rail hides itself in that case rather than degrading to
    /// a generic "popular" fallback.
    @Published var recommended: [RecommendedCourse] = []
    @Published var unreadNotifications = 0
    @Published var isLoading = true
    /// Tracks whether the first successful load happened. Pull-to-refresh
    /// avoids flashing the skeleton (and avoids overwriting state with the
    /// empty defaults) on subsequent invocations.
    private var hasLoadedOnce = false

    func load() async {
        // One aggregate call powers the whole Home screen (GET
        // /v1/student/home). On the first call we flash the skeleton; on
        // pull-to-refresh we keep the populated layout. On failure we leave
        // whatever was last shown rather than flipping to the empty state.
        if !hasLoadedOnce { isLoading = true }

        let payload: StudentHomePayload? = try? await AuthInterceptor.shared.execute(
            APIRequest(path: "/v1/student/home"))

        if let payload {
            greeting = payload.greeting
            unreadNotifications = payload.greeting.unreadNotificationsCount
            enrollments = payload.continueLearning
            recommended = payload.recommendedCourses
            instructors = payload.exploreInstructors
            homeNextSession = payload.nextSession
        }

        isLoading = false
        hasLoadedOnce = true
    }

    /// In-progress courses for the "Continue Learning" carousel. The backend
    /// already filters to non-complete enrollments, freshest first.
    var continueCourses: [EnrolledCourse] { enrollments }
    var courseCount: Int { enrollments.count }
}
