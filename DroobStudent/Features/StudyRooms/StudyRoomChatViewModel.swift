import Foundation
import SwiftUI

/// A single row in the chat timeline. Heterogeneous so date
/// separators can be interleaved between regular messages — V55
/// folded the pre-existing `joinedGroup` and `systemLine` cases into
/// the `.message` case because system events now persist as real
/// `StudyRoomMessage` rows with SYSTEM_* kinds, not transient
/// in-memory events.
enum TimelineRow: Identifiable {
    case dateSeparator(id: String, label: String)
    case message(id: String, message: StudyRoomMessage)

    var id: String {
        switch self {
        case .dateSeparator(let id, _): return "date-" + id
        case .message(let id, _):       return "msg-"  + id
        }
    }
}

/// State for the in-room chat screen. Holds raw messages + a parallel
/// `timeline` rebuilt on every change (cheap because v1 caps history
/// at one page of 50). The timeline:
///
///   • Sorts everything ascending by `createdAt`.
///   • Inserts a date separator at every day-boundary.
///   • Renders SYSTEM_* messages as centred pills (see
///     `systemEventRow` in `StudyRoomChatView`) rather than chat
///     bubbles — same data path, different renderer.
@MainActor
final class StudyRoomChatViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var room: StudyRoomDetail?
    @Published private(set) var participantCount: Int = 0
    /// Live "I am the host" state for the YOU'RE HOST header badge.
    /// Mirrors `room.myRole` on bootstrap and gets patched in by the
    /// `host_transferred` handler.
    @Published private(set) var myRole: StudyRoomRole = .member
    /// Current host's user-id, used by the bubble badge so a former
    /// host's old messages stop showing HOST after a transfer.
    @Published private(set) var currentHostId: String?
    /// Set after a `host_transferred` event names *me* as the new
    /// host. Drives the dismissable "You're now the host" banner.
    @Published var becameHostBanner: BecameHostBanner?
    @Published private(set) var messages: [StudyRoomMessage] = []
    @Published private(set) var timeline: [TimelineRow] = []
    @Published private(set) var isLoadingInitial: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var hasMore: Bool = false
    @Published var errorMessage: String?
    @Published var closedBanner: Bool = false

    /// Flips to `true` when a `member_removed` event names the current
    /// viewer — i.e. a host kicked us while the chat was open. The view
    /// swaps the composer for the read-only banner in response. History
    /// stays readable (the backend grants former members read access up
    /// to their `leftAt`); only posting is disabled. Survives until the
    /// screen is left, mirroring `closedBanner`'s lifetime.
    @Published private(set) var removedFromRoom: Bool = false

    /// Flips to `true` when a `room_closed` event arrives while the chat
    /// is open. Distinct from `closedBanner`, which is the *dismissable*
    /// toast announcing the transition: this is the permanent signal the
    /// view reads to swap the composer for the read-only "room ended"
    /// banner. Without it the room kept looking live after closing —
    /// the user could type, attach, and record into a dead room and the
    /// posts silently failed. Survives until the screen is left.
    @Published private(set) var roomClosedLive: Bool = false

    /// Drives the dismissable "You're now the host" card at the top
    /// of the chat. Carries the previous host's name so the body copy
    /// can read "{prev} left and made you host of {room}."
    struct BecameHostBanner: Hashable {
        let previousHostName: String
        let roomName: String
    }

    // MARK: - Inputs

    let roomId: String
    private var nextBefore: Date?
    private let socket = StudyRoomsSocket()

    init(roomId: String, prefetched: StudyRoomDetail? = nil) {
        self.roomId = roomId
        self.room = prefetched
        self.participantCount = prefetched?.participantCount ?? 0
        self.myRole = prefetched?.myRole ?? .member
        self.currentHostId = prefetched?.hostId
        // Seed the viewer's user-id from the auth session so the bubble
        // outgoing/incoming split is correct from the first frame —
        // independent of whatever the server stamps on `from_me`.
        self.cachedMyUserId = AuthSession.shared.currentUser?.userId
    }

    deinit {
        Task { @MainActor [socket] in socket.disconnect() }
    }

    // MARK: - Public actions

    func bootstrap() async {
        // Always refetch the detail, even when a room was prefetched.
        // The prefetch is only a seed for instant first render — its
        // status can be stale (e.g. re-entering from the "Room is ready"
        // screen after the room has since CLOSED). Trusting the stale
        // ACTIVE snapshot rendered a live composer for a dead room and
        // let sends fail silently; refreshing flips the UI to read-only.
        do {
            let detail = try await StudyRoomsAPI.detail(roomId: roomId)
            room = detail
            participantCount = detail.participantCount
            myRole = detail.myRole ?? .member
            currentHostId = detail.hostId
        } catch {
            // Keep the prefetched room (if any) so the screen still
            // renders; only surface the error when we had nothing.
            if room == nil { errorMessage = error.localizedDescription }
        }
        await loadInitial()
        // Only subscribe to live updates while we're an active member.
        // Once a member leaves (or is removed), they must stop receiving
        // room updates entirely — no live message inserts, no unread
        // bumps, no scroll-to-bottom retriggers from messages sent after
        // they left. The room stays browsable as read-only history, but
        // the socket is never opened. `isMember` is false for left /
        // removed members; the prefetch is refreshed above so this
        // reflects current server state, not a stale ACTIVE snapshot.
        if room?.isMember == true {
            await openSocket()
        }
    }

    /// Resolve a user-id to "is this person currently the host?".
    /// Used by the bubble HOST badge so it follows live transfers.
    /// Accepts an optional (2026-07): anonymized peers in instructor
    /// rooms ship `sender_id = null` and are never the host.
    func isCurrentHost(_ userId: String?) -> Bool {
        guard let userId else { return false }
        return currentHostId == userId
    }

    /// Whether a given message was sent by the viewer. Computed from
    /// the auth session's user-id rather than `message.fromMe` because
    /// the STOMP broadcast on the backend is shared across all
    /// subscribers and ships `from_me = true` (it can't be
    /// per-recipient on a fan-out). REST-fetched history has the
    /// right value, but after that bug existed every live message
    /// rendered as outgoing until the chat was reopened. Trusting our
    /// own id end-to-end makes the bubble side stable regardless of
    /// how the server stamped the flag.
    func isFromMe(_ message: StudyRoomMessage) -> Bool {
        guard let mine = cachedMyUserId, !mine.isEmpty else {
            // No id resolved yet — best to fall back to the wire flag
            // so historic REST data (which is correct) still renders
            // sensibly. The init seeds from AuthSession so this is
            // only hit in test harnesses without an auth session.
            return message.fromMe
        }
        // 2026-07: anonymized peers in instructor rooms ship
        // `sender_id = null`. Those are, by contract, OTHER students'
        // messages — the viewer's own rows always keep their real id —
        // so a nulled id is never "mine". We deliberately do NOT fall
        // back to `message.fromMe` here: the socket fan-out stamps it
        // unreliably (see doc comment above) and honouring it would
        // paint peers' bubbles as outgoing.
        guard let senderId = message.senderId else { return false }
        return senderId == mine
    }

    /// Returns `true` when the viewer matches the `subject_*` slot
    /// of a two-party system row (today: SYSTEM_HOST_TRANSFERRED,
    /// where subject = the new host). Drives the actor-is-me pronoun
    /// swap in the system pill text ("you're now the host" vs.
    /// "X is now the host"). Returns `false` for messages with no
    /// subject (i.e. every non-transfer kind) so callers can use it
    /// unconditionally.
    func isSubject(_ message: StudyRoomMessage) -> Bool {
        guard let mine = cachedMyUserId, !mine.isEmpty,
              let subject = message.subjectId, !subject.isEmpty
        else { return false }
        return subject == mine
    }

    /// Dismiss the new-host banner — close button tapped or the user
    /// sent their first message after becoming host.
    func dismissBecameHostBanner() {
        becameHostBanner = nil
    }

    func refresh() async {
        nextBefore = nil
        await loadInitial()
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, let before = nextBefore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await StudyRoomsAPI.messages(
                roomId: roomId, before: before, size: 50)
            messages.append(contentsOf: page.messages)
            nextBefore = page.nextBefore
            hasMore = page.hasMore
            rebuildTimeline()
        } catch { errorMessage = error.localizedDescription }
    }

    func sendText(_ raw: String) async {
        let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        do {
            _ = try await StudyRoomsAPI.sendText(roomId: roomId, body: body)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Sends a pre-uploaded attachment. `body` is an optional caption
    /// (image/document), `voiceDurationSeconds` is required for
    /// `.voice` and ignored otherwise.
    func sendAttachment(
        upload: ChatAttachmentUpload,
        body: String? = nil,
        voiceDurationSeconds: Int? = nil
    ) async {
        // Map the uploader's "IMAGE" / "DOCUMENT" wire string back to
        // the room-side enum. The voice case never originates from
        // the gallery sheet — it comes from the recorder flow with an
        // explicit `.voice` plus a duration.
        let type: StudyRoomAttachmentType = {
            if voiceDurationSeconds != nil { return .voice }
            return StudyRoomAttachmentType(rawValue: upload.attachmentType) ?? .document
        }()
        let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await StudyRoomsAPI.sendAttachment(
                roomId: roomId,
                body: (trimmed?.isEmpty ?? true) ? nil : trimmed,
                type: type,
                key: upload.attachmentKey,
                name: upload.attachmentName,
                sizeBytes: Int(upload.attachmentSizeBytes),
                durationSeconds: voiceDurationSeconds)
        } catch { errorMessage = error.localizedDescription }
    }

    func sendSayHi() async {
        await sendText(L10n.studyRoomsSayHiMessage)
    }

    func leaveRoom() async {
        do { try await StudyRoomsAPI.leave(roomId: roomId) }
        catch { errorMessage = error.localizedDescription }
        socket.disconnect()
    }

    // MARK: - Loading

    private func loadInitial() async {
        isLoadingInitial = true
        defer { isLoadingInitial = false }
        do {
            let page = try await StudyRoomsAPI.messages(
                roomId: roomId, before: nil, size: 50)
            messages = page.messages
            nextBefore = page.nextBefore
            hasMore = page.hasMore
            // Seed own user-id from any historical self-message.
            // (Own rows always carry a real sender id — the null case
            // only applies to anonymized peers — but stay defensive.)
            if cachedMyUserId == nil,
               let mine = page.messages.first(where: { $0.fromMe }),
               let mineId = mine.senderId {
                cachedMyUserId = mineId
            }
            rebuildTimeline()
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Live socket

    private func openSocket() async {
        do {
            try await socket.subscribe(roomId: roomId) { [weak self] event in
                Task { @MainActor in
                    self?.handle(event: event)
                }
            }
        } catch {
            // Live updates are best-effort; pull-to-refresh still works.
            print("[ChatVM] socket subscribe failed: \(error)")
        }
    }

    private func handle(event: StudyRoomEvent) {
        switch event.type {
        case "message_created":
            guard let m = event.message else { return }
            // Opportunistically learn our own user-id from the first
            // self-sent message we see — used by the host-transfer
            // banner check. Null-safe (2026-07): never clobber the
            // cache with an anonymized (nil) sender id.
            if m.fromMe, let senderId = m.senderId { cachedMyUserId = senderId }
            if !messages.contains(where: { $0.messageId == m.messageId }) {
                // Server returns newest-first; we keep that ordering
                // internally and reverse in the timeline.
                messages.insert(m, at: 0)
                // V55: lifecycle events (joined / left / host
                // transferred) ride the same `message_created`
                // envelope as chat — they're now persisted rows
                // that show up in /messages history. Patch the
                // local participant counter and host bookkeeping
                // here so the header status row + bubble HOST
                // badge stay live without a separate event type.
                applySystemSideEffects(m)
                rebuildTimeline()
            }
        case "room_closed":
            closedBanner = true
            // Permanently flip to read-only — the room has ended, so the
            // composer must be swapped for the ended banner and no further
            // posts allowed. No more live events will arrive, so drop the
            // socket too.
            roomClosedLive = true
            socket.disconnect()
        case "member_removed":
            // A host kicked someone. If it's us, flip the chat to
            // read-only on the spot — history stays browsable but the
            // composer is swapped for the removed banner. Other members'
            // removals ride the SYSTEM_* message stream for the count.
            if let removed = event.userId,
               !myUserId.isEmpty,
               removed == myUserId {
                removedFromRoom = true
            }
        // Legacy transient envelopes (`member_joined`, `member_left`,
        // `host_changed`, `host_transferred`) were removed from the
        // backend broadcast set in V55 — the same payload now ships
        // as a SYSTEM_* persisted message inside `message_created`.
        // The cases stay deleted on iOS so an older server that
        // still emits them is rendered as a no-op (forward-compat
        // is fine; the missing pills would just be invisible until
        // the room is reloaded).
        default:
            break
        }
    }

    /// Mirrors the server-side side-effects of a SYSTEM_* row so the
    /// chat VM's derived state (participantCount, currentHostId,
    /// myRole, becameHostBanner) stays in sync without an extra
    /// detail fetch on every lifecycle event.
    private func applySystemSideEffects(_ m: StudyRoomMessage) {
        switch m.kind {
        case .systemMemberJoined:
            bumpParticipantCount(by: 1)
        case .systemMemberLeft:
            bumpParticipantCount(by: -1)
        case .systemHostChanged:
            // No membership change. Update host bookkeeping so the
            // HOST badge follows the live transfer. Null-safe
            // (2026-07): compare ids only when the sender id is real —
            // `nil == nil` must not promote the viewer to host.
            currentHostId = m.senderId
            if let senderId = m.senderId, senderId == cachedMyUserId {
                myRole = .host
            } else if myRole == .host {
                // Someone else became host — demote me locally.
                myRole = .member
            }
        case .systemHostTransferred:
            // The previous host (sender) left in the same
            // transaction — decrement the counter to mirror
            // `room.decrementParticipantCount()` on the server. New
            // host is the subject.
            bumpParticipantCount(by: -1)
            if let newHostId = m.subjectId {
                currentHostId = newHostId
                if newHostId == cachedMyUserId {
                    myRole = .host
                    becameHostBanner = BecameHostBanner(
                        previousHostName: m.senderName,
                        roomName: room?.name ?? "")
                } else if myRole == .host {
                    // I used to be the host (e.g. on a flaky
                    // network where I missed my own leave-and-
                    // transfer ack) — demote locally so the badge
                    // doesn't lie.
                    myRole = .member
                }
            }
        case .text, .attachment, .sharedNotes:
            break
        }
    }

    /// Cached viewer user-id. Seeded in `init` from the AuthSession;
    /// also opportunistically re-seeded from any self-sent message we
    /// see (covers test harnesses with no auth session).
    private var cachedMyUserId: String?
    private var myUserId: String {
        if let id = cachedMyUserId { return id }
        if let id = AuthSession.shared.currentUser?.userId {
            cachedMyUserId = id
            return id
        }
        return ""
    }

    private func bumpParticipantCount(by delta: Int) {
        participantCount = max(0, participantCount + delta)
    }

    // MARK: - Timeline build
    //
    // Cheap full rebuild on every change. v1 caps to one page (50
    // messages) so the cost is bounded. When we add infinite scroll
    // for older pages we can incrementalise this.

    private func rebuildTimeline() {
        // V55 simplification: system events (joined / left / host
        // transferred) are persisted as regular StudyRoomMessage
        // rows now, so the timeline is just `messages` + day
        // separators. The earlier joinedGroup / systemLine
        // collation lived here to fold transient socket events
        // into a chronological stream; with persistence that
        // bookkeeping moves to the wire.
        var rows: [TimelineRow] = []
        var lastDay: String? = nil
        // `messages` is stored newest-first to match the server's
        // pagination cursor; flip to ascending for the timeline so
        // the bottom of the scroll view is "now".
        for m in messages.reversed() {
            let dayKey = dayKey(for: m.createdAt)
            if dayKey != lastDay {
                rows.append(.dateSeparator(id: dayKey,
                                           label: dayLabel(for: m.createdAt)))
                lastDay = dayKey
            }
            rows.append(.message(id: m.messageId, message: m))
        }
        timeline = rows
    }

    // MARK: - Date labels

    private let calendar = Calendar.current
    /// Not `static let`: a formatter cached for the process would freeze the
    /// locale it was first built with. Cheap enough per day-separator.
    private static var monthDayFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.currentLanguageCode)
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }

    private func dayKey(for date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    private func dayLabel(for date: Date) -> String {
        if calendar.isDateInToday(date) { return L10n.studyRoomsToday }
        if calendar.isDateInYesterday(date) { return L10n.studyRoomsYesterday }
        return Self.monthDayFormatter.string(from: date)
    }
}
