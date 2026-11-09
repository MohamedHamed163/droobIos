import Foundation

// MARK: - Enrollment request models
//
// The "New Course Enrollment Flow" (ADR-0006) replaces instant paid
// enrollment with a request the instructor approves. A student opens a
// PENDING request against a published course (optional note); the
// instructor approves (→ active enrollment, no payment) or rejects.
// These types back the student-side surfaces: the Course Detail enroll
// button state machine and the instructor-profile "Pending" tab.

/// Lifecycle state of an enrollment request. Mirrors the backend
/// `EnrollmentRequestStatus` enum. Unknown wire values decode to
/// `.unknown` so a future status can't crash the list.
enum EnrollmentRequestStatus: String, Decodable, Equatable {
    case pending = "PENDING"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case cancelled = "CANCELLED"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EnrollmentRequestStatus(rawValue: raw) ?? .unknown
    }
}

/// Student-facing view of one enrollment request. Course title / cover are
/// flattened in by the backend so the row renders without a second fetch.
struct EnrollmentRequest: Decodable, Identifiable, Equatable {
    let id: String
    let courseId: String
    let courseTitleEn: String
    let courseTitleAr: String
    let courseCoverUrl: String?
    let instructorId: String
    let instructorName: String?
    let instructorTitleEn: String?
    let instructorTitleAr: String?
    let note: String?
    let status: EnrollmentRequestStatus
    let createdAt: Date
    let updatedAt: Date
    let decidedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case courseId = "course_id"
        case courseTitleEn = "course_title_en"
        case courseTitleAr = "course_title_ar"
        case courseCoverUrl = "course_cover_url"
        case instructorId = "instructor_id"
        case instructorName = "instructor_name"
        case instructorTitleEn = "instructor_title_en"
        case instructorTitleAr = "instructor_title_ar"
        case note
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case decidedAt = "decided_at"
    }

    func localizedCourseTitle(locale: String) -> String {
        L10n.localized(locale, ar: courseTitleAr, en: courseTitleEn)
    }

    func localizedInstructorTitle(locale: String) -> String? {
        L10n.localized(locale, ar: instructorTitleAr, en: instructorTitleEn)
    }

    var isPending: Bool { status == .pending }
}
