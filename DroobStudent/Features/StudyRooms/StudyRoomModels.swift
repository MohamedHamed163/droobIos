import Foundation

// MARK: - Enums

/// Mirrors the server's `StudyRoom.Privacy` enum.
enum StudyRoomPrivacy: String, Decodable, Hashable {
    case `public` = "PUBLIC"
    case `private` = "PRIVATE"
}

/// Mirrors the server's `StudyRoom.Status` enum. CLOSED is terminal.
enum StudyRoomStatus: String, Decodable, Hashable {
    case active = "ACTIVE"
    case closed = "CLOSED"
}

/// Mirrors `StudyRoomMembership.Role`. The host is the room owner and
/// is the only member who can transfer ownership (implicitly, by leaving).
enum StudyRoomRole: String, Decodable, Hashable {
    case host = "HOST"
    case coHost = "CO_HOST"
    case member = "MEMBER"

    /// Convenience for admin-only UI: host + co-host both qualify.
    var isAdmin: Bool { self == .host || self == .coHost }
}

/// Mirrors `StudyRoomMessage.Kind`. Drives the bubble renderer choice.
///
/// The four `system*` cases are server-generated lifecycle pills (V55) —
/// "Layla joined", "Bob left", "Sara is now the host", or the combined
/// host-transfer message. They render as centred system pills, not as
/// chat bubbles. Treat them as persistent history (returned by GET
/// /messages just like text/attachment rows) rather than transient
/// socket events; the WhatsApp behaviour the product asked for.
enum StudyRoomMessageKind: String, Decodable, Hashable {
    case text = "TEXT"
    case attachment = "ATTACHMENT"
    case sharedNotes = "SHARED_NOTES"
    case systemMemberJoined = "SYSTEM_MEMBER_JOINED"
    case systemMemberLeft = "SYSTEM_MEMBER_LEFT"
    case systemHostChanged = "SYSTEM_HOST_CHANGED"
    case systemHostTransferred = "SYSTEM_HOST_TRANSFERRED"

    /// True when the kind is a server-generated lifecycle event. The
    /// chat timeline groups consecutive system rows differently from
    /// chat bubbles (centred pills, no avatar columns) so the
    /// renderer branches on this rather than enumerating each case.
    var isSystem: Bool {
        switch self {
        case .systemMemberJoined, .systemMemberLeft,
             .systemHostChanged, .systemHostTransferred:
            return true
        case .text, .attachment, .sharedNotes:
            return false
        }
    }
}

/// Reuses the same enum values as the 1:1 chat (`Message.AttachmentType`)
/// so existing bubble renderers can be shared.
enum StudyRoomAttachmentType: String, Decodable, Hashable {
    case image = "IMAGE"
    case document = "DOCUMENT"
    case voice = "VOICE"
}

// MARK: - Summary / detail

/// Compact row used by the "browse public rooms" and "my rooms" lists.
/// Compact member descriptor used by the row-level avatar stack.
struct MemberPreview: Decodable, Hashable, Identifiable {
    /// `nil` for anonymized peers in instructor-created rooms (2026-07:
    /// the backend nulls other students' ids there).
    let userId: String?
    let initials: String
    var id: String { userId ?? "anon-\(initials)" }
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case initials
    }

    init(userId: String?, initials: String) {
        self.userId = userId
        self.initials = initials
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId   = try c.decodeIfPresent(String.self, forKey: .userId)
        initials = try c.decode(String.self, forKey: .initials)
    }
}

struct StudyRoomSummary: Decodable, Identifiable, Hashable {
    let roomId: String
    let courseId: String
    /// Bilingual title of the room's course; "" on older backends that
    /// predate the field. Read via `localizedCourseTitle(locale:)`.
    let courseTitleEn: String
    let courseTitleAr: String
    let name: String
    let description: String?
    let privacy: StudyRoomPrivacy
    /// Only populated for the host or for active members of a PRIVATE room.
    let joinCode: String?
    /// URL slug used to build the Universal-Link share string
    /// (`droob-sa.net/r/{slug}`). Defaults to "" on older backends.
    let slug: String
    let hostId: String
    let hostName: String
    let participantCount: Int
    let maxParticipants: Int
    let status: StudyRoomStatus
    let isMember: Bool
    let lastMessageAt: Date?
    let createdAt: Date
    /// First ~6 active members for the avatar stack. Empty on older
    /// backends — UI falls through to participant_count only.
    let memberPreviews: [MemberPreview]
    /// Messages-tab unread badge count.
    let unreadCount: Int
    /// Viewer's role in this room — HOST / CO_HOST / MEMBER — or `nil`
    /// when the viewer's membership is no longer active (e.g. ended
    /// rooms in the inbox where `left_at` is set).
    let myRole: StudyRoomRole?
    /// "STUDENT" | "INSTRUCTOR" (2026-07). `nil` on older backends —
    /// callers treat that as STUDENT (and hide the room from the
    /// instructor-rooms-only surfaces).
    let createdByRole: String?

    var id: String { roomId }

    /// Convenience for the instructor-rooms-only surfaces. A missing
    /// field is treated as a student room and hidden.
    var isInstructorRoom: Bool { createdByRole == "INSTRUCTOR" }

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case courseId = "course_id"
        case name, description, privacy
        case joinCode = "join_code"
        case slug
        case hostId = "host_id"
        case hostName = "host_name"
        case participantCount = "participant_count"
        case maxParticipants = "max_participants"
        case status
        case isMember = "is_member"
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
        case memberPreviews = "member_previews"
        case unreadCount = "unread_count"
        case myRole = "my_role"
        case courseTitleEn = "course_title_en"
        case courseTitleAr = "course_title_ar"
        case createdByRole = "created_by_role"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roomId           = try c.decode(String.self, forKey: .roomId)
        courseId         = try c.decode(String.self, forKey: .courseId)
        name             = try c.decode(String.self, forKey: .name)
        description      = try c.decodeIfPresent(String.self, forKey: .description)
        privacy          = try c.decode(StudyRoomPrivacy.self, forKey: .privacy)
        joinCode         = try c.decodeIfPresent(String.self, forKey: .joinCode)
        slug             = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        hostId           = try c.decode(String.self, forKey: .hostId)
        hostName         = try c.decode(String.self, forKey: .hostName)
        participantCount = try c.decode(Int.self, forKey: .participantCount)
        maxParticipants  = try c.decode(Int.self, forKey: .maxParticipants)
        status           = try c.decode(StudyRoomStatus.self, forKey: .status)
        isMember         = try c.decode(Bool.self, forKey: .isMember)
        lastMessageAt    = try c.decodeIfPresent(Date.self, forKey: .lastMessageAt)
        createdAt        = try c.decode(Date.self, forKey: .createdAt)
        memberPreviews   = try c.decodeIfPresent(
            [MemberPreview].self, forKey: .memberPreviews) ?? []
        unreadCount      = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        courseTitleEn    = try c.decodeIfPresent(String.self, forKey: .courseTitleEn) ?? ""
        courseTitleAr    = try c.decodeIfPresent(String.self, forKey: .courseTitleAr) ?? ""
        myRole           = try c.decodeIfPresent(StudyRoomRole.self, forKey: .myRole)
        createdByRole    = try c.decodeIfPresent(String.self, forKey: .createdByRole)
    }

    /// Course title in the app's current language, mirroring the
    /// `localizedTitle(locale:)` helper on the catalog models.
    func localizedCourseTitle(locale: String) -> String {
        L10n.localized(locale, ar: courseTitleAr, en: courseTitleEn)
    }
}

/// Full room view with active member roster. Returned by the join and
/// "open room" endpoints.
struct StudyRoomDetail: Decodable, Identifiable, Hashable {
    let roomId: String
    let courseId: String
    /// Bilingual title of the room's course; "" on older backends that
    /// predate the field. Read via `localizedCourseTitle(locale:)`.
    let courseTitleEn: String
    let courseTitleAr: String
    let name: String
    let description: String?
    let privacy: StudyRoomPrivacy
    let joinCode: String?
    /// URL slug; defaults to "" on older backends.
    let slug: String
    let hostId: String
    let hostName: String
    let participantCount: Int
    let maxParticipants: Int
    let status: StudyRoomStatus
    let isMember: Bool
    /// True when a host removed (kicked) the viewer from this room.
    /// Distinguishes a kick from a voluntary leave when `isMember` is
    /// false, so the chat can pick the right read-only banner. Defaults
    /// to false on older backends that predate the field.
    let wasRemoved: Bool
    /// Non-nil iff `isMember == true`.
    let myRole: StudyRoomRole?
    let lastMessageAt: Date?
    let createdAt: Date
    let members: [StudyRoomMember]
    /// "STUDENT" | "INSTRUCTOR" (2026-07). `nil` on older backends —
    /// callers treat that as STUDENT.
    let createdByRole: String?

    var id: String { roomId }

    /// Convenience mirror of the summary's flag — instructor rooms hide
    /// the student-facing admin/social affordances (invite, settings
    /// edit, waitlist, promote/demote/remove).
    var isInstructorRoom: Bool { createdByRole == "INSTRUCTOR" }

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case courseId = "course_id"
        case name, description, privacy
        case joinCode = "join_code"
        case slug
        case hostId = "host_id"
        case hostName = "host_name"
        case participantCount = "participant_count"
        case maxParticipants = "max_participants"
        case status
        case isMember = "is_member"
        case wasRemoved = "was_removed"
        case myRole = "my_role"
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
        case members
        case courseTitleEn = "course_title_en"
        case courseTitleAr = "course_title_ar"
        case createdByRole = "created_by_role"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roomId           = try c.decode(String.self, forKey: .roomId)
        courseId         = try c.decode(String.self, forKey: .courseId)
        name             = try c.decode(String.self, forKey: .name)
        description      = try c.decodeIfPresent(String.self, forKey: .description)
        privacy          = try c.decode(StudyRoomPrivacy.self, forKey: .privacy)
        joinCode         = try c.decodeIfPresent(String.self, forKey: .joinCode)
        slug             = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        hostId           = try c.decode(String.self, forKey: .hostId)
        hostName         = try c.decode(String.self, forKey: .hostName)
        participantCount = try c.decode(Int.self, forKey: .participantCount)
        maxParticipants  = try c.decode(Int.self, forKey: .maxParticipants)
        status           = try c.decode(StudyRoomStatus.self, forKey: .status)
        isMember         = try c.decode(Bool.self, forKey: .isMember)
        wasRemoved       = try c.decodeIfPresent(Bool.self, forKey: .wasRemoved) ?? false
        myRole           = try c.decodeIfPresent(StudyRoomRole.self, forKey: .myRole)
        lastMessageAt    = try c.decodeIfPresent(Date.self, forKey: .lastMessageAt)
        createdAt        = try c.decode(Date.self, forKey: .createdAt)
        courseTitleEn    = try c.decodeIfPresent(String.self, forKey: .courseTitleEn) ?? ""
        courseTitleAr    = try c.decodeIfPresent(String.self, forKey: .courseTitleAr) ?? ""
        members          = try c.decode([StudyRoomMember].self, forKey: .members)
        createdByRole    = try c.decodeIfPresent(String.self, forKey: .createdByRole)
    }

    /// Course title in the app's current language, mirroring the
    /// `localizedTitle(locale:)` helper on the catalog models.
    func localizedCourseTitle(locale: String) -> String {
        L10n.localized(locale, ar: courseTitleAr, en: courseTitleEn)
    }
}

/// Wire response from `joinByCode` / `joinBySlug` for PRIVATE rooms.
/// One of `room` / `waitlist` is non-nil based on `status`.
///   - `JOINED`  → `room` populated (active member).
///   - `PENDING` → `waitlist` populated (request awaiting host).
struct RoomJoinResult: Decodable {
    let status: String
    let room: StudyRoomDetail?
    let waitlist: WaitlistEntry?
}

/// One pending request to join a private room. Listed on the host's
/// waitlist screen and also returned to the requester so they see the
/// "Waiting for host" state.
struct WaitlistEntry: Decodable, Identifiable, Hashable {
    let entryId: String
    let roomId: String
    let userId: String
    let userName: String
    let userInitials: String
    let requestedAt: Date
    let status: String

    var id: String { entryId }

    enum CodingKeys: String, CodingKey {
        case entryId = "entry_id"
        case roomId = "room_id"
        case userId = "user_id"
        case userName = "user_name"
        case userInitials = "user_initials"
        case requestedAt = "requested_at"
        case status
    }
}

/// One document attachment listed on the room's Documents screen.
struct RoomDocument: Decodable, Identifiable, Hashable {
    let messageId: String
    let name: String
    let sizeBytes: Int?
    let typeTag: String  // PDF / DOC / PPT / XLS / TXT / OTHER
    let uploaderId: String
    let uploaderName: String
    let uploadedAt: Date
    let downloadUrl: String

    var id: String { messageId }

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case name
        case sizeBytes = "size_bytes"
        case typeTag = "type_tag"
        case uploaderId = "uploader_id"
        case uploaderName = "uploader_name"
        case uploadedAt = "uploaded_at"
        case downloadUrl = "download_url"
    }
}

/// Public metadata returned by `/v1/public/r/{slug}` — enough to route
/// the user to the right course or chat without revealing private
/// room state.
struct StudyRoomSlugResolution: Decodable {
    let roomId: String
    let courseId: String
    let name: String
    let privacy: StudyRoomPrivacy
    let slug: String

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case courseId = "course_id"
        case name, privacy, slug
    }
}

struct StudyRoomMember: Decodable, Identifiable, Hashable {
    /// `nil` for anonymized peers in instructor-created rooms (2026-07:
    /// other students' identities are hidden; the server sends
    /// `name` like "Student 7" with a null id).
    let userId: String?
    let name: String
    let initials: String
    let role: StudyRoomRole
    let joinedAt: Date
    /// 2026-07 anonymization fields — `email` is always null for
    /// students; `anonIndex` is set for anonymized peers ("Student N").
    /// Both optional so pre-migration payloads still decode.
    let email: String?
    let anonIndex: Int?

    var id: String { userId ?? "anon-\(anonIndex ?? initials.hashValue)" }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name, initials, role, email
        case joinedAt = "joined_at"
        case anonIndex = "anon_index"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId    = try c.decodeIfPresent(String.self, forKey: .userId)
        name      = try c.decode(String.self, forKey: .name)
        initials  = try c.decode(String.self, forKey: .initials)
        role      = try c.decode(StudyRoomRole.self, forKey: .role)
        joinedAt  = try c.decode(Date.self, forKey: .joinedAt)
        email     = try c.decodeIfPresent(String.self, forKey: .email)
        anonIndex = try c.decodeIfPresent(Int.self, forKey: .anonIndex)
    }
}

// MARK: - Messages

struct StudyRoomMessage: Decodable, Identifiable, Hashable {
    let messageId: String
    let roomId: String
    /// `nil` for anonymized peers' messages in instructor-created rooms
    /// (2026-07). Own messages and the instructor's keep real ids.
    let senderId: String?
    let senderName: String
    let senderInitials: String
    let fromMe: Bool
    /// 2026-07 anonymization trio — all optional so old payloads still
    /// decode. `senderAnonIndex` is set on anonymized peers' messages
    /// ("Student N"); `senderIsInstructor` marks the room instructor's
    /// messages; `senderEmail` is always null for students.
    let senderAnonIndex: Int?
    let senderIsInstructor: Bool
    let senderEmail: String?
    let kind: StudyRoomMessageKind
    let body: String?
    let attachmentType: StudyRoomAttachmentType?
    /// Presigned GET URL minted at fetch time (4-hour TTL).
    let attachmentUrl: String?
    let attachmentName: String?
    let attachmentSizeBytes: Int?
    let attachmentDurationSeconds: Int?
    let sharedNotes: [SharedNote]?
    /// Target user trio — populated only for
    /// `systemHostTransferred` (the new host). Every other kind ships
    /// these as `null`. The renderer compares `subjectId` against the
    /// cached viewer id to decide between "you're now the host" and
    /// "X is now the host".
    let subjectId: String?
    let subjectName: String?
    let subjectInitials: String?
    let createdAt: Date

    var id: String { messageId }

    /// Stable key for avatar colouring — falls back to the anon index
    /// when the sender id is nulled (anonymized peers), so "Student 7"
    /// keeps the same colour across messages.
    var senderAvatarKey: String {
        senderId ?? "anon-\(senderAnonIndex ?? senderInitials.hashValue)"
    }

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case roomId = "room_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case senderInitials = "sender_initials"
        case fromMe = "from_me"
        case senderAnonIndex = "sender_anon_index"
        case senderIsInstructor = "sender_is_instructor"
        case senderEmail = "sender_email"
        case kind, body
        case attachmentType = "attachment_type"
        case attachmentUrl = "attachment_url"
        case attachmentName = "attachment_name"
        case attachmentSizeBytes = "attachment_size_bytes"
        case attachmentDurationSeconds = "attachment_duration_seconds"
        case sharedNotes = "shared_notes"
        case subjectId = "subject_id"
        case subjectName = "subject_name"
        case subjectInitials = "subject_initials"
        case createdAt = "created_at"
    }

    /// Defensive default-decoder so older payloads without the
    /// subject trio (e.g. cached responses minted before V55 shipped,
    /// or a non-prod backend without the migration) still decode
    /// instead of failing the whole page.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messageId = try c.decode(String.self, forKey: .messageId)
        roomId = try c.decode(String.self, forKey: .roomId)
        senderId = try c.decodeIfPresent(String.self, forKey: .senderId)
        senderName = try c.decode(String.self, forKey: .senderName)
        senderInitials = try c.decode(String.self, forKey: .senderInitials)
        fromMe = try c.decode(Bool.self, forKey: .fromMe)
        senderAnonIndex = try c.decodeIfPresent(Int.self, forKey: .senderAnonIndex)
        senderIsInstructor = try c.decodeIfPresent(Bool.self, forKey: .senderIsInstructor) ?? false
        senderEmail = try c.decodeIfPresent(String.self, forKey: .senderEmail)
        kind = try c.decode(StudyRoomMessageKind.self, forKey: .kind)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        attachmentType = try c.decodeIfPresent(
            StudyRoomAttachmentType.self, forKey: .attachmentType)
        attachmentUrl = try c.decodeIfPresent(String.self, forKey: .attachmentUrl)
        attachmentName = try c.decodeIfPresent(String.self, forKey: .attachmentName)
        attachmentSizeBytes = try c.decodeIfPresent(Int.self,
                                                   forKey: .attachmentSizeBytes)
        attachmentDurationSeconds = try c.decodeIfPresent(
            Int.self, forKey: .attachmentDurationSeconds)
        sharedNotes = try c.decodeIfPresent([SharedNote].self,
                                            forKey: .sharedNotes)
        subjectId = try c.decodeIfPresent(String.self, forKey: .subjectId)
        subjectName = try c.decodeIfPresent(String.self, forKey: .subjectName)
        subjectInitials = try c.decodeIfPresent(String.self,
                                                forKey: .subjectInitials)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

/// One LessonNote snapshot inside a SHARED_NOTES message. `content` is
/// frozen at share time — never updated even if the original note
/// changes. `lessonNoteId` is null when the original has been deleted.
struct SharedNote: Decodable, Identifiable, Hashable {
    let id: String
    let position: Int
    let lessonNoteId: String?
    let content: String
    let lessonId: String
    let timestampSeconds: Int?
    let pinnedPage: Int?
    let documentId: String?

    enum CodingKeys: String, CodingKey {
        case id, position
        case lessonNoteId = "lesson_note_id"
        case content
        case lessonId = "lesson_id"
        case timestampSeconds = "timestamp_seconds"
        case pinnedPage = "pinned_page"
        case documentId = "document_id"
    }
}

struct StudyRoomMessagesPage: Decodable, Hashable {
    let messages: [StudyRoomMessage]
    let nextBefore: Date?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case messages
        case nextBefore = "next_before"
        case hasMore = "has_more"
    }
}

// MARK: - Live STOMP event envelope

/// Wire envelope for `/topic/study-rooms/{roomId}` broadcasts. iOS
/// branches on `type` to update the message list, member roster, or
/// pop the room when it closes.
struct StudyRoomEvent: Decodable, Hashable {
    let type: String
    let roomId: String
    let userId: String?
    let displayName: String?
    let message: StudyRoomMessage?
    let emittedAt: Date

    enum CodingKeys: String, CodingKey {
        case type
        case roomId = "room_id"
        case userId = "user_id"
        case displayName = "display_name"
        case message
        case emittedAt = "emitted_at"
    }
}
