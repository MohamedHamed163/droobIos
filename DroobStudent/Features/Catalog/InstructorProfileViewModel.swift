import Foundation
import SwiftUI

// MARK: - Models

/// Public profile payload for a single instructor. Mirrors the backend
/// `StudentInstructorProfileResponse` record — drives the figma
/// "Instructor Profile" screen (stat tiles + bio + Message CTA + their
/// courses).
struct InstructorPublicProfile: Decodable, Identifiable, Equatable {
    let id: String
    let displayName: String
    let professionalTitleEn: String?
    let professionalTitleAr: String?
    let avatarUrl: String?
    let bioEn: String?
    let bioAr: String?
    let studentsCount: Int
    let coursesCount: Int
    let ratingAvg: Double?
    let yearsExperience: Int
    let lastActiveAt: Date?
    let courses: [CourseSummary]

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case professionalTitleEn = "professional_title_en"
        case professionalTitleAr = "professional_title_ar"
        case avatarUrl = "avatar_url"
        case bioEn = "bio_en"
        case bioAr = "bio_ar"
        case studentsCount = "students_count"
        case coursesCount = "courses_count"
        case ratingAvg = "rating_avg"
        case yearsExperience = "years_experience"
        case lastActiveAt = "last_active_at"
        case courses
    }

    func localizedTitle(locale: String) -> String? {
        L10n.localized(locale, ar: professionalTitleAr, en: professionalTitleEn)
    }

    func localizedBio(locale: String) -> String? {
        L10n.localized(locale, ar: bioAr, en: bioEn)
    }

    /// Bio in the current app language, falling back to the other language
    /// when the preferred one is empty. `nil` only when both are empty —
    /// the profile hides the ABOUT section entirely in that case.
    func bestBio(locale: String) -> String? {
        localizedBio(locale: locale)
            ?? localizedBio(locale: locale == "ar" ? "en" : "ar")
    }

    /// Compact stat label: "10+ years" for veterans, "Xy" for new hires.
    /// Drives the fourth stat tile on the figma.
    var formattedYears: String {
        yearsExperience >= 10 ? "10+" : "\(yearsExperience)"
    }

    /// "Active now" if seen in the last 5 min, else "Active Xm ago"
    /// / "Xh ago" / "Xd ago" — drives the green pill under the name in
    /// the chat header. `nil` when the column hasn't been populated
    /// yet (pre-V41 logins) so iOS hides the indicator.
    func activityLabel() -> String? {
        guard let lastActiveAt else { return nil }
        let elapsed = Date().timeIntervalSince(lastActiveAt)
        if elapsed < 300 { return L10n.instructorProfileActiveNow }
        if elapsed < 3600 { return String(format: L10n.instructorProfileActiveMinFmt, Int(elapsed / 60)) }
        if elapsed < 86_400 { return String(format: L10n.instructorProfileActiveHourFmt, Int(elapsed / 3600)) }
        return String(format: L10n.instructorProfileActiveDayFmt, Int(elapsed / 86_400))
    }
}

// MARK: - View model

@MainActor
final class InstructorProfileViewModel: ObservableObject {
    let instructorId: String

    @Published var profile: InstructorPublicProfile? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    /// The caller's enrolled courses under this instructor — drives the
    /// "Enrolled" tab. Loaded lazily once the profile resolves.
    @Published var enrolledCourses: [EnrolledCourse] = []
    /// The caller's still-PENDING enrollment requests to this instructor —
    /// drives the "Pending" tab. Approved/rejected/cancelled rows are
    /// filtered out server-side (status=PENDING) and again here defensively.
    @Published var pendingRequests: [EnrollmentRequest] = []

    init(instructorId: String) {
        self.instructorId = instructorId
    }

    func load() async {
        if profile != nil { return }
        isLoading = true
        errorMessage = nil
        let request = APIRequest(path: "/v1/student/instructors/\(instructorId)")
        do {
            let result: InstructorPublicProfile =
                try await AuthInterceptor.shared.execute(request)
            profile = result
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

        // Student-scoped tabs. Failures are swallowed — the tabs degrade to
        // their empty state rather than blocking the profile header.
        await loadEnrolled()
        await loadPending()
    }

    /// Refresh the student-scoped tabs without refetching the profile header.
    /// Used when returning from the course sheet, where a pending request may
    /// have had its note edited or been withdrawn.
    func refreshStudentTabs() async {
        await loadEnrolled()
        await loadPending()
    }

    private func loadEnrolled() async {
        let request = APIRequest(
            path: "/v1/student/instructors/\(instructorId)/enrolled-courses")
        if let result: [EnrolledCourse] = try? await AuthInterceptor.shared.execute(request) {
            enrolledCourses = result
        }
    }

    private func loadPending() async {
        if let result = try? await EnrollmentRequestService.list(instructorId: instructorId) {
            pendingRequests = result.filter { $0.isPending }
        }
    }

    /// Withdraw a still-PENDING request straight from the "Pending" tab
    /// (→ CANCELLED). The row is dropped only once the server confirms, so a
    /// failure leaves the tab untouched and the caller can surface an error.
    func cancelPendingRequest(_ request: EnrollmentRequest) async -> Bool {
        do {
            _ = try await EnrollmentRequestService.cancel(requestId: request.id)
            pendingRequests.removeAll { $0.id == request.id }
            return true
        } catch {
            return false
        }
    }
}
