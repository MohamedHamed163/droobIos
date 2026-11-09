import Foundation

// MARK: - Models

struct StudentThread: Decodable, Identifiable {
    let threadId: String
    let instructorId: String
    let instructorName: String
    let instructorInitials: String
    /// Presigned instructor avatar URL (nullable). Drives the inbox-row
    /// avatar; falls back to `instructorInitials` when nil/blank or the
    /// image fails to load.
    let instructorAvatarUrl: String?
    let courseId: String?
    let courseNameEn: String?
    let courseNameAr: String?
    let lastMessagePreview: String
    let lastMessageAt: Date?
    let unreadCount: Int

    var id: String { threadId }

    enum CodingKeys: String, CodingKey {
        case threadId          = "thread_id"
        case instructorId      = "instructor_id"
        case instructorName    = "instructor_name"
        case instructorInitials = "instructor_initials"
        case instructorAvatarUrl = "instructor_avatar_url"
        case courseId          = "course_id"
        case courseNameEn      = "course_name_en"
        case courseNameAr      = "course_name_ar"
        case lastMessagePreview = "last_message_preview"
        case lastMessageAt     = "last_message_at"
        case unreadCount       = "unread_count"
    }
}

struct DirectMessage: Decodable, Identifiable {
    let messageId: String
    let senderId: String
    let senderName: String
    let fromInstructor: Bool
    /// Optional once we added attachment support — a row may carry an
    /// image or document without any caption text. The bubble renders
    /// the body only when present.
    let body: String?
    let attachmentType: String?      // "IMAGE" | "DOCUMENT" | "VOICE" | nil
    let attachmentUrl: String?       // presigned GET, 4h TTL
    let attachmentName: String?
    let attachmentSizeBytes: Int64?
    /// Whole-second audio duration for VOICE rows; nil otherwise.
    let attachmentDurationSeconds: Int?
    let sentAt: Date
    let readAt: Date?

    var id: String { messageId }

    enum CodingKeys: String, CodingKey {
        case messageId      = "message_id"
        case senderId       = "sender_id"
        case senderName     = "sender_name"
        case fromInstructor = "from_instructor"
        case body
        case attachmentType      = "attachment_type"
        case attachmentUrl       = "attachment_url"
        case attachmentName      = "attachment_name"
        case attachmentSizeBytes = "attachment_size_bytes"
        case attachmentDurationSeconds = "attachment_duration_seconds"
        case sentAt = "sent_at"
        case readAt = "read_at"
    }

    /// Convenience accessor — `true` when the row carries an image
    /// (drives the image-bubble vs document-chip branch in the view).
    var isImageAttachment: Bool { attachmentType == "IMAGE" }
    var isDocumentAttachment: Bool { attachmentType == "DOCUMENT" }
    var isVoiceAttachment: Bool { attachmentType == "VOICE" }
    var hasAttachment: Bool { attachmentType != nil }
}

struct StudentNotificationItem: Decodable, Identifiable {
    let id: String
    let type: String
    let title: String
    let body: String
    let pinned: Bool
    let readAt: Date?
    let createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, type, title, body, pinned
        case readAt    = "read_at"
        case createdAt = "created_at"
    }
}

// MARK: - Messaging ViewModel (inbox list)

@MainActor
final class MessagingViewModel: ObservableObject {
    @Published var threads: [StudentThread] = []
    @Published var notifications: [StudentNotificationItem] = []
    /// Inbox of study rooms — active memberships in ACTIVE rooms + any
    /// memberships in CLOSED rooms (read-only "Ended" history). Sorted
    /// newest-activity-first by the backend.
    @Published var rooms: [StudyRoomSummary] = []
    @Published var isLoadingThreads = true
    @Published var isLoadingNotifications = true
    @Published var isLoadingRooms = true
    @Published var threadsError: String? = nil
    @Published var notificationsError: String? = nil
    @Published var roomsError: String? = nil

    func loadThreads() async {
        isLoadingThreads = true
        threadsError = nil
        do {
            let items: [StudentThread] = try await AuthInterceptor.shared.execute(
                APIRequest(path: "/v1/student/messages/threads")
            )
            threads = items
        } catch let e as DroobError {
            if case .unauthenticated(_, _) = e {
                AuthSession.shared.handleUnauthenticated()
            } else { threadsError = e.errorDescription }
        } catch { threadsError = error.localizedDescription }
        isLoadingThreads = false
    }

    func loadNotifications() async {
        isLoadingNotifications = true
        notificationsError = nil
        do {
            let items: [StudentNotificationItem] = try await AuthInterceptor.shared.execute(
                APIRequest(path: "/v1/student/messages/notifications")
            )
            notifications = items
        } catch { notificationsError = error.localizedDescription }
        isLoadingNotifications = false
    }

    /// Loads the per-user "my rooms" inbox surface for the Messages tab.
    /// The backend already includes both ACTIVE-with-active-membership
    /// rows ("Running") and CLOSED-with-any-membership rows ("Ended"),
    /// each carrying its own `unreadCount`.
    func loadRooms() async {
        isLoadingRooms = true
        roomsError = nil
        do {
            rooms = try await StudyRoomsAPI.myRooms()
        } catch let e as DroobError {
            if case .unauthenticated(_, _) = e {
                AuthSession.shared.handleUnauthenticated()
            } else { roomsError = e.errorDescription }
        } catch { roomsError = error.localizedDescription }
        isLoadingRooms = false
    }

    /// Rooms-tab badge: number of *rooms* with at least one unread
    /// message. Earlier this summed every room's `unreadCount`, which
    /// double-counted (the per-card badge already shows that number)
    /// and inflated the tab badge into the hundreds for a busy
    /// inbox — making it read as "151 unread" instead of "3 rooms
    /// with new activity."
    var roomsUnreadTotal: Int {
        // 2026-07: only instructor-created rooms render in the list, so
        // only those may contribute to the badge — a hidden student
        // room must not produce an un-clearable count.
        // Old (all rooms): rooms.reduce(0) { $0 + ($1.unreadCount > 0 ? 1 : 0) }
        rooms.reduce(0) { $0 + ($1.isInstructorRoom && $1.unreadCount > 0 ? 1 : 0) }
    }

    /// Chats-tab badge: number of *threads* with at least one unread
    /// message — same semantics as the Rooms badge.
    var chatsUnreadTotal: Int {
        threads.reduce(0) { $0 + ($1.unreadCount > 0 ? 1 : 0) }
    }
}
