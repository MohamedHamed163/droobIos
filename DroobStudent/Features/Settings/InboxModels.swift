import SwiftUI

/// One row from `GET /v1/student/notifications`. The string `type` matches
/// `NotificationKind.wireType` server-side; switch on it for icon and
/// localised copy. `category` matches `NotificationCategory.wire` and drives
/// the segmented tab filter.
struct StudentNotification: Decodable, Identifiable, Equatable {
    let id: String
    let type: String
    let category: String?
    let payload: AnyJSON
    /// `var` so the inbox can apply optimistic mark-read updates.
    var readAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type, category, payload
        case readAt = "read_at"
        case createdAt = "created_at"
    }

    var isUnread: Bool { readAt == nil }
}

/// One page of the inbox from `GET /v1/student/notifications`. The server
/// applies the category/unread filter and paginates; the client appends pages
/// as the user scrolls.
struct NotificationPage: Decodable {
    let items: [StudentNotification]
    let hasMore: Bool
    let nextOffset: Int

    enum CodingKeys: String, CodingKey {
        case items
        case hasMore = "has_more"
        case nextOffset = "next_offset"
    }
}

// MARK: - Category tabs

/// Segmented filter tabs across the top of the inbox. `all`/`unread` are
/// meta-filters resolved client-side; the rest map 1:1 to the server's
/// `NotificationCategory.wire` and are pushed down as `?category=`.
enum NotificationCategoryUI: String, CaseIterable, Identifiable {
    case all, unread, messages, courses, sessions, quizzes, studyRooms

    var id: String { rawValue }

    /// `?category=` value sent to the list endpoint. `nil` → no filter
    /// (handled client-side for `all`/`unread`).
    var wire: String? {
        switch self {
        case .all, .unread: return nil
        case .messages:     return "messages"
        case .courses:      return "courses"
        case .sessions:     return "sessions"
        case .quizzes:      return "quizzes"
        case .studyRooms:   return "study_rooms"
        }
    }

    var label: String {
        switch self {
        case .all:        return L10n.inboxTabAll
        case .unread:     return L10n.inboxTabUnread
        case .messages:   return L10n.inboxTabMessages
        case .courses:    return L10n.inboxTabCourses
        case .sessions:   return L10n.inboxTabSessions
        case .quizzes:    return L10n.inboxTabQuizzes
        case .studyRooms: return L10n.inboxTabStudyRooms
        }
    }
}

// MARK: - Inline actions

/// A tappable button rendered inside a notification card. Each one POSTs to
/// `/v1/student/notifications/{id}/actions/{path}` and reports its effect.
struct InboxAction: Identifiable, Equatable {
    enum Kind: String { case joinSession = "join-session" }
    let kind: Kind
    var id: String { kind.rawValue }

    var label: String {
        switch kind {
        case .joinSession:   return L10n.inboxActionJoin
        }
    }

    /// Destructive/primary styling cue for the button.
    var isProminent: Bool { true }
}

/// Maps a `wireType` string to the user-facing copy, SF Symbol, accent and
/// inline actions shown in the inbox row. New kinds added on the backend
/// should be mirrored here; falling through to `.unknown` is a graceful
/// degrade, not an error.
enum NotificationKindUI {
    case lessonReminder, streakAlert, newLesson, courseUpdated, revisionFile,
         revisionUpdated, enrollmentApproved, qaAnswer, newCourseAlert, promotionOffer
    case quizResult, newQuiz
    case liveSessionReminder, sessionStartingNow, sessionScheduled,
         sessionCancelled, sessionRescheduled
    case newMessage, instructorReply, announcement
    case studyRoomMessage, studyRoomJoined, studyRoomEnded, studyRoomWaitlistRequest,
         studyRoomWaitlistApproved, studyRoomWaitlistRejected, studyRoomRemoved,
         studyRoomPromoted, studyRoomBecameHost
    case unknown

    static func from(_ wire: String) -> NotificationKindUI {
        switch wire {
        case "lesson_reminder":              return .lessonReminder
        case "streak_alert":                 return .streakAlert
        case "new_lesson":                   return .newLesson
        case "course_updated":               return .courseUpdated
        case "new_revision_file":            return .revisionFile
        case "revision_updated":             return .revisionUpdated
        case "enrollment_approved":          return .enrollmentApproved
        case "qa_answer":                    return .qaAnswer
        case "new_course_alert":             return .newCourseAlert
        case "promotion_offer":              return .promotionOffer
        case "quiz_result":                  return .quizResult
        case "new_quiz":                     return .newQuiz
        case "live_session_reminder":        return .liveSessionReminder
        case "session_starting_now":         return .sessionStartingNow
        case "session_scheduled":            return .sessionScheduled
        case "session_cancelled":            return .sessionCancelled
        case "session_rescheduled":          return .sessionRescheduled
        case "new_message":                  return .newMessage
        case "instructor_reply":             return .instructorReply
        case "announcement":                 return .announcement
        case "study_room_message":           return .studyRoomMessage
        case "study_room_joined":            return .studyRoomJoined
        case "study_room_ended":             return .studyRoomEnded
        case "study_room_waitlist_request":  return .studyRoomWaitlistRequest
        case "study_room_waitlist_approved": return .studyRoomWaitlistApproved
        case "study_room_waitlist_rejected": return .studyRoomWaitlistRejected
        case "study_room_removed":           return .studyRoomRemoved
        case "study_room_promoted":          return .studyRoomPromoted
        case "study_room_became_host":       return .studyRoomBecameHost
        default:                             return .unknown
        }
    }

    var systemImage: String {
        switch self {
        case .lessonReminder:            return "book.fill"
        case .streakAlert:               return "flame.fill"
        case .newLesson:                 return "play.rectangle.fill"
        case .courseUpdated:             return "arrow.triangle.2.circlepath"
        case .revisionFile, .revisionUpdated: return "doc.text.fill"
        case .enrollmentApproved:        return "checkmark.seal.fill"
        case .qaAnswer:                  return "text.bubble.fill"
        case .newCourseAlert:            return "sparkles"
        case .promotionOffer:            return "tag.fill"
        case .quizResult:                return "checkmark.circle.fill"
        case .newQuiz:                   return "list.bullet.clipboard.fill"
        case .liveSessionReminder, .sessionScheduled: return "calendar.badge.clock"
        case .sessionStartingNow:        return "video.fill"
        case .sessionCancelled:          return "calendar.badge.minus"
        case .sessionRescheduled:        return "calendar.badge.exclamationmark"
        case .newMessage, .instructorReply: return "envelope.fill"
        case .announcement:              return "megaphone.fill"
        case .studyRoomMessage:          return "bubble.left.and.bubble.right.fill"
        case .studyRoomJoined:           return "person.badge.plus"
        case .studyRoomEnded:            return "door.left.hand.closed"
        case .studyRoomWaitlistRequest:  return "hand.raised.fill"
        case .studyRoomWaitlistApproved: return "person.fill.checkmark"
        case .studyRoomWaitlistRejected: return "person.fill.xmark"
        case .studyRoomRemoved:          return "person.fill.xmark"
        case .studyRoomPromoted:         return "star.fill"
        case .studyRoomBecameHost:       return "crown.fill"
        case .unknown:                   return "bell.fill"
        }
    }

    /// Title shown in the inbox row, routed through L10n for Arabic support.
    var title: String {
        switch self {
        case .lessonReminder:            return L10n.inboxKindLessonReminderTitle
        case .streakAlert:               return L10n.inboxKindStreakTitle
        case .newLesson:                 return L10n.inboxKindNewLessonTitle
        case .courseUpdated:             return L10n.inboxKindCourseUpdatedTitle
        case .revisionFile, .revisionUpdated: return L10n.inboxKindRevisionTitle
        case .enrollmentApproved:        return L10n.inboxKindEnrollmentApprovedTitle
        case .qaAnswer:                  return L10n.inboxKindInstructorReplyTitle
        case .newCourseAlert:            return L10n.inboxKindNewCourseTitle
        case .promotionOffer:            return L10n.inboxKindPromotionTitle
        case .quizResult:                return L10n.inboxKindQuizResultTitle
        case .newQuiz:                   return L10n.inboxKindNewQuizTitle
        case .liveSessionReminder:       return L10n.inboxKindLiveSessionTitle
        case .sessionStartingNow:        return L10n.inboxKindSessionStartingTitle
        case .sessionScheduled:          return L10n.inboxKindSessionScheduledTitle
        case .sessionCancelled:          return L10n.inboxKindSessionCancelledTitle
        case .sessionRescheduled:        return L10n.inboxKindSessionRescheduledTitle
        case .newMessage:                return L10n.inboxKindNewMessageTitle
        case .instructorReply:           return L10n.inboxKindInstructorReplyTitle
        case .announcement:              return L10n.inboxKindAnnouncementTitle
        case .studyRoomMessage:          return L10n.inboxKindStudyRoomMessageTitle
        case .studyRoomJoined:           return L10n.inboxKindStudyRoomJoinedTitle
        case .studyRoomEnded:            return L10n.inboxKindStudyRoomEndedTitle
        case .studyRoomWaitlistRequest:  return L10n.inboxKindStudyRoomWaitlistRequestTitle
        case .studyRoomWaitlistApproved: return L10n.inboxKindStudyRoomWaitlistApprovedTitle
        case .studyRoomWaitlistRejected: return L10n.inboxKindStudyRoomWaitlistRejectedTitle
        case .studyRoomRemoved:          return L10n.inboxKindStudyRoomRemovedTitle
        case .studyRoomPromoted:         return L10n.inboxKindStudyRoomPromotedTitle
        case .studyRoomBecameHost:       return L10n.inboxKindStudyRoomBecameHostTitle
        case .unknown:                   return L10n.inboxKindUnknownTitle
        }
    }

    /// Accent role for the icon tile (drives bg + tint colour).
    enum Accent { case gold, success, danger, info }
    var accent: Accent {
        switch self {
        case .quizResult, .streakAlert, .enrollmentApproved,
             .studyRoomWaitlistApproved, .studyRoomPromoted, .studyRoomBecameHost:
            return .success
        case .sessionCancelled, .studyRoomWaitlistRejected, .studyRoomRemoved:
            return .danger
        case .liveSessionReminder, .sessionStartingNow, .sessionScheduled, .sessionRescheduled:
            return .info
        default:
            return .gold
        }
    }

    /// Inline action buttons surfaced on the card for actionable kinds.
    var actions: [InboxAction] {
        switch self {
        case .liveSessionReminder, .sessionStartingNow, .sessionScheduled, .sessionRescheduled:
            return [InboxAction(kind: .joinSession)]
        default:
            return []
        }
    }

    /// `droob://` deep link a tap should route to, derived from the payload.
    func deepLink(_ p: AnyJSON) -> URL? {
        func url(_ s: String) -> URL? { URL(string: s) }
        switch self {
        case .newMessage, .instructorReply, .announcement:
            if let t = p.string("thread_id") { return url("droob://messages/\(t)") }
        case .liveSessionReminder, .sessionStartingNow, .sessionScheduled,
             .sessionCancelled, .sessionRescheduled:
            if let s = p.string("session_id") { return url("droob://sessions/\(s)") }
        case .quizResult, .newQuiz:
            if let q = p.string("quiz_id") { return url("droob://quizzes/\(q)") }
        case .studyRoomMessage, .studyRoomJoined, .studyRoomEnded,
             .studyRoomWaitlistRequest, .studyRoomWaitlistApproved,
             .studyRoomWaitlistRejected, .studyRoomRemoved, .studyRoomPromoted,
             .studyRoomBecameHost:
            if let r = p.string("room_id") { return url("droob://study-rooms/\(r)") }
        default:
            break
        }
        if let c = p.string("course_id") { return url("droob://courses/\(c)") }
        return nil
    }
}

// MARK: - JSON payload

/// Minimal AnyCodable variant that just decodes JSON into a Swift
/// dictionary so payload values are inspectable from the UI without us
/// minting a per-kind struct for every new payload field.
struct AnyJSON: Decodable, Equatable {
    let value: [String: AnyJSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyJSONValue].self) {
            value = dict
        } else {
            value = [:]
        }
    }

    func string(_ key: String) -> String? {
        if case .string(let s)? = value[key] { return s }
        if case .number(let n)? = value[key] {
            return n == n.rounded() ? String(Int(n)) : String(n)
        }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if case .bool(let b)? = value[key] { return b }
        return nil
    }

    func int(_ key: String) -> Int? {
        if case .number(let n)? = value[key] { return Int(n) }
        if case .string(let s)? = value[key] { return Int(s) }
        return nil
    }
}

enum AnyJSONValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        self = .null
    }
}
