import Foundation

@MainActor
final class MyCoursesViewModel: ObservableObject {
    @Published var enrollments: [EnrolledCourse] = []
    /// PENDING enrollment requests (ADR-0006). Surfaced alongside active
    /// enrollments so an instructor the student is still waiting on appears
    /// in the grouped list even before any course is unlocked.
    @Published var pendingRequests: [EnrollmentRequest] = []
    @Published var isLoading: Bool = false
    /// False until the first load() finishes (success or error). Drives the
    /// initial skeleton so the onboarding empty state can't flash before the
    /// enrollments request has had a chance to resolve.
    @Published var hasLoaded: Bool = false
    @Published var errorMessage: String? = nil

    private var skipNetwork: Bool = false

    // MARK: - Derived state (Enrolled tab redesign)

    /// One instructor and the student's active + pending courses under them.
    /// Drives the grouped cards on the Enrolled tab.
    struct InstructorGroup: Identifiable {
        let id: String
        let name: String
        /// Presigned instructor avatar URL (nullable). Sourced from the
        /// first enrolled course under this instructor; nil for
        /// pending-only groups (enrollment requests carry no avatar).
        /// The header renders initials whenever this is nil/blank.
        var avatarUrl: String?
        let titleEn: String?
        let titleAr: String?
        var courses: [EnrolledCourse]
        var pending: [EnrollmentRequest]

        /// Active enrollments + pending requests — the number shown in the
        /// header pill.
        var totalCount: Int { courses.count + pending.count }

        func localizedTitle(locale: String) -> String? {
            L10n.localized(locale, ar: titleAr, en: titleEn)
        }
    }

    /// Top-of-screen stats bar counters.
    struct Stats {
        let total: Int
        let inProgress: Int
        let completed: Int
        let pending: Int
    }

    var stats: Stats {
        let completed = enrollments.filter { $0.isCompleted }.count
        let inProgress = enrollments.count - completed
        return Stats(
            total: enrollments.count + pendingRequests.count,
            inProgress: inProgress,
            completed: completed,
            pending: pendingRequests.count)
    }

    /// Enrollments and pending requests folded into per-instructor groups,
    /// preserving first-seen order (active instructors first, then
    /// pending-only instructors). Grouping key is the instructor id, falling
    /// back to the display name when the id is absent.
    var instructorGroups: [InstructorGroup] {
        var order: [String] = []
        var map: [String: InstructorGroup] = [:]

        for course in enrollments {
            let key = course.instructorId ?? course.instructorName
            if map[key] == nil {
                order.append(key)
                map[key] = InstructorGroup(
                    id: key,
                    name: course.instructorName,
                    avatarUrl: course.instructorAvatarUrl,
                    titleEn: course.instructorTitleEn,
                    titleAr: course.instructorTitleAr,
                    courses: [],
                    pending: [])
            } else if map[key]?.avatarUrl == nil {
                // Backfill from the first course that carries an avatar
                // (e.g. group first created from a pending request).
                map[key]?.avatarUrl = course.instructorAvatarUrl
            }
            map[key]?.courses.append(course)
        }

        for request in pendingRequests {
            let key = request.instructorId
            if map[key] == nil {
                order.append(key)
                map[key] = InstructorGroup(
                    id: key,
                    name: request.instructorName ?? request.localizedCourseTitle(locale: "en"),
                    avatarUrl: nil,
                    titleEn: request.instructorTitleEn,
                    titleAr: request.instructorTitleAr,
                    courses: [],
                    pending: [])
            }
            map[key]?.pending.append(request)
        }

        return order.compactMap { map[$0] }
    }

    func load() async {
        if skipNetwork { return }

        isLoading = true
        errorMessage = nil

        let request = APIRequest(path: "/v1/student/enrollments", method: .GET)

        do {
            // Pending requests load in parallel; they're supplementary, so a
            // failure there must not blank the (primary) enrollments list.
            async let pending = EnrollmentRequestService.list(status: .pending)
            let result: [EnrolledCourse] = try await AuthInterceptor.shared.execute(request)
            enrollments = result
            pendingRequests = (try? await pending) ?? []
        } catch is CancellationError {
            // Pull-to-refresh task was cancelled (user released the gesture
            // before the response arrived). Swallow silently — the next
            // refresh / .task will re-fire load() naturally.
            isLoading = false
            return
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            } else if case .network(let underlying) = error,
                      APIClient.isCancellationError(underlying) {
                // Defence-in-depth: if some path still wraps cancellation
                // as a network error, recognise it here too.
                isLoading = false
                return
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        hasLoaded = true
    }

    /// Returns a view-model pre-populated with hand-tuned mock enrollments
    /// that mirror the Figma reference (3 instructors, 5 courses, 1 pending).
    /// Used by the launch-arg preview hosts in `RootView` to render the
    /// design without a live backend.
    static func previewSeeded() -> MyCoursesViewModel {
        let vm = MyCoursesViewModel()
        vm.skipNetwork = true
        vm.hasLoaded = true
        vm.enrollments = [
            EnrolledCourse(
                id: "ux-fundamentals",
                titleEn: "UX/UI Fundamentals",
                titleAr: "أساسيات تصميم تجربة المستخدم",
                instructorId: "inst-layla",
                instructorName: "Dr. Layla Hassan",
                instructorTitleEn: "UX/UI Design · Brand Strategy",
                instructorTitleAr: "تصميم تجربة المستخدم · استراتيجية العلامة",
                progressPct: 67,
                completedAt: nil,
                lastActiveAt: Date(),
                enrolledAt: Date().addingTimeInterval(-60 * 86400),
                lessonCount: 32,
                completedLessonCount: 21,
                liveSessionCount: 0,
                nextLessonId: "lesson-motion",
                nextLessonTitleEn: "Motion Principles",
                nextLessonTitleAr: "مبادئ الحركة"
            ),
            EnrolledCourse(
                id: "figma-deep-dive",
                titleEn: "Figma Deep Dive",
                titleAr: "الغوص العميق في Figma",
                instructorId: "inst-layla",
                instructorName: "Dr. Layla Hassan",
                instructorTitleEn: "UX/UI Design · Brand Strategy",
                instructorTitleAr: "تصميم تجربة المستخدم · استراتيجية العلامة",
                progressPct: 100,
                completedAt: Date().addingTimeInterval(-10 * 86400),
                lastActiveAt: Date().addingTimeInterval(-10 * 86400),
                enrolledAt: Date().addingTimeInterval(-90 * 86400),
                lessonCount: 18,
                completedLessonCount: 18,
                liveSessionCount: 0,
                nextLessonId: nil,
                nextLessonTitleEn: nil,
                nextLessonTitleAr: nil
            ),
            EnrolledCourse(
                id: "react-mastery",
                titleEn: "React Mastery",
                titleAr: "إتقان React",
                instructorId: "inst-amr",
                instructorName: "Prof. Amr Khalid",
                instructorTitleEn: "React · Node.js",
                instructorTitleAr: "React · Node.js",
                progressPct: 42,
                completedAt: nil,
                lastActiveAt: Date(),
                enrolledAt: Date().addingTimeInterval(-45 * 86400),
                lessonCount: 48,
                completedLessonCount: 20,
                liveSessionCount: 2,
                nextLessonId: "lesson-hooks",
                nextLessonTitleEn: "Custom Hooks",
                nextLessonTitleAr: "خطافات مخصصة"
            ),
            EnrolledCourse(
                id: "nodejs-backend",
                titleEn: "Node.js Backend",
                titleAr: "خلفية Node.js",
                instructorId: "inst-amr",
                instructorName: "Prof. Amr Khalid",
                instructorTitleEn: "React · Node.js",
                instructorTitleAr: "React · Node.js",
                progressPct: 28,
                completedAt: nil,
                lastActiveAt: Date().addingTimeInterval(-2 * 86400),
                enrolledAt: Date().addingTimeInterval(-30 * 86400),
                lessonCount: 36,
                completedLessonCount: 10,
                liveSessionCount: 1,
                nextLessonId: "lesson-streams",
                nextLessonTitleEn: "Streams",
                nextLessonTitleAr: "التدفقات"
            )
        ]
        vm.pendingRequests = [
            EnrollmentRequest(
                id: "req-marketing",
                courseId: "digital-marketing",
                courseTitleEn: "Digital Marketing 2026",
                courseTitleAr: "التسويق الرقمي 2026",
                courseCoverUrl: nil,
                instructorId: "inst-sara",
                instructorName: "Prof. Sara Nasser",
                instructorTitleEn: "Digital Marketing · Growth",
                instructorTitleAr: "التسويق الرقمي · النمو",
                note: nil,
                status: .pending,
                createdAt: Date().addingTimeInterval(-3 * 86400),
                updatedAt: Date().addingTimeInterval(-3 * 86400),
                decidedAt: nil
            )
        ]
        return vm
    }
}
