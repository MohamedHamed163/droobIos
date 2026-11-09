import Foundation

/// Thin REST client for the study-rooms endpoints. Mirrors the
/// `/v1/student/study-rooms/**` surface documented in
/// `droobBackend/docs/study-rooms.md`.
///
/// Calls go through `AuthInterceptor` so the JWT refresh + retry
/// behaviour is shared with the rest of the app.
///
/// <b>Calling convention</b> — `AuthInterceptor.execute<T>` /
/// `APIClient.execute<T>` already unwrap the {@code ApiEnvelope}
/// internally and return the inner {@code data} value as {@code T}.
/// Every method here declares the inner DTO directly as the generic
/// argument — wrapping it in `ApiEnvelope<…>` would double-decode.
struct StudyRoomsAPI {

    // MARK: - Discovery

    /// PUBLIC + ACTIVE rooms in a course, newest-first. `query` is an
    /// optional case-insensitive search term matched against name +
    /// description; pass `nil` or empty for unfiltered results.
    static func listPublic(courseId: String, query: String? = nil,
                           page: Int = 0, size: Int = 20)
        async throws -> [StudyRoomSummary]
    {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(size))
        ]
        if let q = query?.trimmingCharacters(in: .whitespacesAndNewlines),
           !q.isEmpty {
            items.append(URLQueryItem(name: "q", value: q))
        }
        let req = APIRequest(
            path: "/v1/student/courses/\(courseId)/study-rooms",
            method: .GET,
            queryItems: items)
        return try await AuthInterceptor.shared.execute(req)
    }

    /// Instructor-created room for a course (2026-07). The backend
    /// returns 0..1 rooms for `kind=INSTRUCTOR`; we surface the first
    /// (or nil). This is the only room students see on the course
    /// detail — the student create/join flow is hidden.
    static func instructorRoom(courseId: String) async throws -> StudyRoomSummary? {
        let req = APIRequest(
            path: "/v1/student/courses/\(courseId)/study-rooms",
            method: .GET,
            queryItems: [URLQueryItem(name: "kind", value: "INSTRUCTOR")])
        let rooms: [StudyRoomSummary] = try await AuthInterceptor.shared.execute(req)
        return rooms.first
    }

    /// Rooms the caller is an active member of, across all courses.
    /// Also includes ended (CLOSED) rooms where the caller still has a
    /// membership row — those are read-only history surfaces in the
    /// Messages tab.
    static func myRooms() async throws -> [StudyRoomSummary] {
        let req = APIRequest(path: "/v1/student/study-rooms", method: .GET)
        return try await AuthInterceptor.shared.execute(req)
    }

    /// Idempotent "mark every message I haven't read in this room as
    /// read up to now." Bumps the membership's `last_read_at` server
    /// side; no-op for non-members. Called the moment the user opens
    /// the room from the Messages tab so the unread badge clears
    /// without waiting for the messages-list round trip.
    static func markRead(roomId: String) async throws {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/mark-read",
            method: .POST)
        struct OkBody: Decodable { let ok: Bool? }
        let _: OkBody = try await AuthInterceptor.shared.execute(req)
    }

    /// Full room detail incl. active members.
    static func detail(roomId: String) async throws -> StudyRoomDetail {
        let req = APIRequest(path: "/v1/student/study-rooms/\(roomId)", method: .GET)
        return try await AuthInterceptor.shared.execute(req)
    }

    // MARK: - Create

    struct CreateRoomBody: Encodable {
        let name: String
        let description: String?
        /// Wire-name of `StudyRoomPrivacy` (`PUBLIC` / `PRIVATE`).
        let privacy: String
        /// Pre-drafted code from the form (PRIVATE rooms only). Server
        /// honours it if still unique; otherwise transparently mints a
        /// fresh one and returns it on the response.
        let preferred_join_code: String?
    }

    static func create(
        courseId: String, name: String, description: String?,
        privacy: StudyRoomPrivacy,
        preferredJoinCode: String? = nil
    ) async throws -> StudyRoomDetail {
        let body = CreateRoomBody(
            name: name,
            description: description,
            privacy: privacy.rawValue,
            preferred_join_code: preferredJoinCode)
        let req = APIRequest(
            path: "/v1/student/courses/\(courseId)/study-rooms",
            method: .POST,
            body: body)
        return try await AuthInterceptor.shared.execute(req)
    }

    /// One-shot fetch of a candidate 6-char join code. Not reserved —
    /// concurrent creates can still snag it, but the probability is
    /// negligible (1 in ≈30M); the server transparently regenerates
    /// on collision and the final value comes back on the create
    /// response.
    static func draftJoinCode(courseId: String) async throws -> String {
        let req = APIRequest(
            path: "/v1/student/courses/\(courseId)/study-rooms/draft-code",
            method: .GET)
        struct Body: Decodable {
            let joinCode: String
            enum CodingKeys: String, CodingKey { case joinCode = "join_code" }
        }
        let body: Body = try await AuthInterceptor.shared.execute(req)
        return body.joinCode
    }

    // MARK: - Join / leave

    static func joinPublic(roomId: String) async throws -> StudyRoomDetail {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/join",
            method: .POST)
        return try await AuthInterceptor.shared.execute(req)
    }

    struct JoinByCodeBody: Encodable { let code: String }

    /// Join a room by 6-char code. PUBLIC rooms return JOINED with the
    /// detail; PRIVATE rooms return PENDING with a waitlist entry that
    /// the iOS UI surfaces as a "Waiting for host" screen.
    static func joinByCode(_ code: String) async throws -> RoomJoinResult {
        let req = APIRequest(
            path: "/v1/student/study-rooms/join-by-code",
            method: .POST,
            body: JoinByCodeBody(code: code))
        return try await AuthInterceptor.shared.execute(req)
    }

    /// Resolve a Universal Link slug to its public metadata. No auth
    /// required — the recipient may not be logged in yet.
    static func resolveSlug(_ slug: String) async throws -> StudyRoomSlugResolution {
        let req = APIRequest(
            path: "/v1/public/r/\(slug)",
            method: .GET,
            requiresAuth: false)
        return try await APIClient.shared.execute(req, accessToken: nil)
    }

    /// Join a room by URL slug — same JOINED/PENDING split as
    /// `joinByCode`. Returned to iOS as `RoomJoinResult` for branching.
    static func joinBySlug(_ slug: String) async throws -> RoomJoinResult {
        let req = APIRequest(
            path: "/v1/student/study-rooms/by-slug/\(slug)/join",
            method: .POST)
        return try await AuthInterceptor.shared.execute(req)
    }

    /// Decoded as a free-form ok envelope — the backend returns
    /// `{ok: true}` and nothing else.
    private struct OkBody: Decodable { let ok: Bool? }

    struct LeaveBody: Encodable {
        let new_host_user_id: String?
    }

    /// Leave the room. When the caller is the host, `newHostUserId`
    /// optionally specifies an explicit pass-host target; otherwise
    /// the server auto-picks (longest-tenured co-host first, then any
    /// regular member).
    static func leave(roomId: String, newHostUserId: String? = nil)
        async throws
    {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/leave",
            method: .POST,
            body: LeaveBody(new_host_user_id: newHostUserId))
        let _: OkBody = try await AuthInterceptor.shared.execute(req)
    }

    // MARK: - Messages

    static func messages(
        roomId: String, before: Date? = nil, size: Int = 50
    ) async throws -> StudyRoomMessagesPage {
        var query = [URLQueryItem(name: "size", value: String(size))]
        if let before {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            query.append(URLQueryItem(name: "before", value: iso.string(from: before)))
        }
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/messages",
            method: .GET,
            queryItems: query)
        return try await AuthInterceptor.shared.execute(req)
    }

    /// Mirrors `SendStudyRoomMessageRequest` on the backend. Any field
    /// can be nil for a text-only send; the attachment quartet travels
    /// together.
    struct SendMessageBody: Encodable {
        let body: String?
        let attachment_type: String?
        let attachment_key: String?
        let attachment_name: String?
        let attachment_size_bytes: Int?
        let attachment_duration_seconds: Int?
    }

    static func sendText(roomId: String, body: String)
        async throws -> StudyRoomMessage
    {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/messages",
            method: .POST,
            body: SendMessageBody(
                body: body, attachment_type: nil, attachment_key: nil,
                attachment_name: nil, attachment_size_bytes: nil,
                attachment_duration_seconds: nil))
        return try await AuthInterceptor.shared.execute(req)
    }

    static func sendAttachment(
        roomId: String, body: String?,
        type: StudyRoomAttachmentType, key: String, name: String?,
        sizeBytes: Int?, durationSeconds: Int?
    ) async throws -> StudyRoomMessage {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/messages",
            method: .POST,
            body: SendMessageBody(
                body: body,
                attachment_type: type.rawValue,
                attachment_key: key,
                attachment_name: name,
                attachment_size_bytes: sizeBytes,
                attachment_duration_seconds: durationSeconds))
        return try await AuthInterceptor.shared.execute(req)
    }

    struct ShareNotesBody: Encodable {
        let lesson_note_ids: [String]
        let body: String?
    }

    /// Share one or more of the caller's own lesson notes (snapshot is
    /// taken on the server so subsequent edits / deletes don't rewrite
    /// chat history).
    static func shareNotes(
        roomId: String, lessonNoteIds: [String], body: String? = nil
    ) async throws -> StudyRoomMessage {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/messages/shared-notes",
            method: .POST,
            body: ShareNotesBody(lesson_note_ids: lessonNoteIds, body: body))
        return try await AuthInterceptor.shared.execute(req)
    }

    // MARK: - Waitlist (host / co-host)

    static func listWaitlist(roomId: String) async throws -> [WaitlistEntry] {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/waitlist",
            method: .GET)
        return try await AuthInterceptor.shared.execute(req)
    }

    @discardableResult
    static func approveWaitlist(roomId: String, userId: String)
        async throws -> WaitlistEntry
    {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/waitlist/\(userId)/approve",
            method: .POST)
        return try await AuthInterceptor.shared.execute(req)
    }

    @discardableResult
    static func rejectWaitlist(roomId: String, userId: String)
        async throws -> WaitlistEntry
    {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/waitlist/\(userId)/reject",
            method: .POST)
        return try await AuthInterceptor.shared.execute(req)
    }

    @discardableResult
    static func approveAllWaitlist(roomId: String)
        async throws -> [WaitlistEntry]
    {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/waitlist/approve-all",
            method: .POST)
        return try await AuthInterceptor.shared.execute(req)
    }

    // MARK: - Admin member actions

    /// Promote a member to co-host. Host-only server-side.
    static func promoteToCoHost(roomId: String, userId: String) async throws {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/members/\(userId)/promote",
            method: .POST)
        struct OkBody: Decodable { let ok: Bool? }
        let _: OkBody = try await AuthInterceptor.shared.execute(req)
    }

    static func demoteCoHost(roomId: String, userId: String) async throws {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/members/\(userId)/demote",
            method: .POST)
        struct OkBody: Decodable { let ok: Bool? }
        let _: OkBody = try await AuthInterceptor.shared.execute(req)
    }

    static func removeMember(roomId: String, userId: String) async throws {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/members/\(userId)/remove",
            method: .POST)
        struct OkBody: Decodable { let ok: Bool? }
        let _: OkBody = try await AuthInterceptor.shared.execute(req)
    }

    // MARK: - PATCH room + documents

    struct UpdateRoomBody: Encodable {
        let name: String?
        let description: String?
    }

    /// Update editable room metadata. Either field can be nil to leave
    /// it unchanged; pass an empty string for `description` to clear.
    @discardableResult
    static func updateRoom(roomId: String,
                           name: String? = nil,
                           description: String? = nil)
        async throws -> StudyRoomDetail
    {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)",
            method: .PATCH,
            body: UpdateRoomBody(name: name, description: description))
        return try await AuthInterceptor.shared.execute(req)
    }

    static func listDocuments(roomId: String) async throws -> [RoomDocument] {
        let req = APIRequest(
            path: "/v1/student/study-rooms/\(roomId)/documents",
            method: .GET)
        return try await AuthInterceptor.shared.execute(req)
    }

    // MARK: - Attachment upload
    //
    // Multipart uploads aren't covered by the standard JSON APIRequest
    // path; the existing 1:1 chat uses a dedicated uploader. We'll wire
    // the room equivalent (`/v1/student/study-rooms/{id}/messages/attachments`)
    // through the same `ChatAttachmentUploader` once the room UI ships
    // — same payload shape, same response.
}
