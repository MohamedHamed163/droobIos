import SwiftUI

/// In-room chat screen.
///
/// Sections (top → bottom):
///   1. Custom header — back, cover icon, room name, status, settings.
///      Status flips on participant count:
///        ≤1  → "Just you · waiting for others"
///        >1  → "● N members" (green dot)
///   2. Pinned `Studying · course — room` row; tap pops to course.
///   3. Scrolling message timeline. When empty, shows a placeholder
///      that branches on `participantCount`: "The room is all yours"
///      when the viewer is alone, "No messages yet" once others are
///      present (using the celebratory copy with others in the room
///      misled users into thinking they were the only member). For
///      PRIVATE rooms a small room-code chip sits below the Invite
///      button in both branches.
///   4. `👋 Say hi` quick chip floats above the composer.
///   5. Composer — mic (stub), text, plus (stub), send.
///
/// Live wire-up: `StudyRoomChatViewModel` subscribes to the STOMP
/// topic for this room and merges incoming events into a single
/// timeline of typed rows (`TimelineRow`) that mixes chat messages,
/// system event groups, and date separators.
struct StudyRoomChatView: View {
    let roomId: String
    /// Course title supplied by the caller. The course→rooms path knows
    /// it up front and passes it; other entry points (Messages tab, deep
    /// links) don't, so it's optional and those fall back to the fetched
    /// room's own `localizedCourseTitle`. See `displayCourseTitle`.
    let courseTitle: String?
    /// Optional override for what happens after the viewer leaves the
    /// room. The default (`nil`) just pops the chat. The "Room is ready"
    /// path injects one that unwinds past the ready screen too, so a
    /// user who leaves (and thereby closes) a freshly-created room isn't
    /// dropped back on a "Room is ready" screen for a now-dead room.
    var onLeaveRoom: (() -> Void)? = nil

    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @StateObject private var viewModel: StudyRoomChatViewModel
    @State private var composerText: String = ""
    @State private var showInvite: Bool = false
    @State private var showSettings: Bool = false
    // Attachment composer state — mirrors the 1:1 InstructorChatView
    // composer so the user experience is the same in both chat
    // surfaces (gallery sheet, in-flight upload pill, settled preview
    // with X to drop). Backed by the same `ChatAttachmentUploader` +
    // `ChatAttachmentSheet` primitives.
    @State private var showAttachmentSheet: Bool = false
    @State private var pendingAttachment: ChatAttachmentUpload? = nil
    @State private var isUploading: Bool = false
    @State private var uploadError: String? = nil
    // Voice-note recording — same flow as the 1:1 chat. Mic in the
    // composer starts the recorder; the recording bar replaces the
    // input row while the user is recording.
    @StateObject private var recorder = VoiceNoteRecorder()
    @State private var showMicPermissionAlert: Bool = false
    @State private var recordingPulse: Bool = false
    // Image-preview cover for tapping an image bubble — owned at the
    // chat level so the cover overlays the whole conversation rather
    // than just the bubble.
    @State private var previewImage: ImagePreviewItem? = nil
    // Tracks whether we've performed the one-time "land at the bottom"
    // scroll after the first page of history is built. The first
    // population jumps without animation so the timeline opens pinned
    // to the newest message; later appends (live messages) animate.
    // Without this, the initial 0→N timeline change animated a scroll
    // from the top, which for read-only / left-member history looked
    // like the view "jumping to the top" before settling.
    @State private var didInitialScroll: Bool = false
    @Environment(\.dismiss) private var dismiss

    init(roomId: String, prefetchedRoom: StudyRoomDetail? = nil,
         courseTitle: String? = nil, onLeaveRoom: (() -> Void)? = nil) {
        self.roomId = roomId
        self.courseTitle = courseTitle
        self.onLeaveRoom = onLeaveRoom
        _viewModel = StateObject(wrappedValue: StudyRoomChatViewModel(
            roomId: roomId, prefetched: prefetchedRoom))
    }

    /// Course title for the pinned "Studying · …" row. Prefers the
    /// caller-supplied title (course→rooms path), otherwise falls back
    /// to the fetched room's own localized course title so entry points
    /// that don't know it up front (Messages tab, deep links) still
    /// render the course context.
    private var displayCourseTitle: String {
        if let courseTitle, !courseTitle.isEmpty { return courseTitle }
        return viewModel.room?.localizedCourseTitle(locale: appLocale) ?? ""
    }

    /// Instructor-created room (2026-07) — student-facing invite/share
    /// affordances are hidden here; peers render as anonymized
    /// "Student N" rows. `nil`/missing decodes as a student room.
    private var isInstructorRoom: Bool {
        viewModel.room?.isInstructorRoom == true
    }

    /// Single reliable exit out of the room — used by the leave flow and
    /// the room-ended "Back to course" button. Posting
    /// `droobExitStudyRooms` lets `CourseDetailView` collapse the whole
    /// course → CreateOrJoin → RoomReady → chat `isActive` link chain in
    /// one flip; a `dismiss()` from this depth gets dropped because the
    /// parent bindings are still `true`. The closure / `dismiss()`
    /// fallback covers the Messages-tab and deep-link entry points, which
    /// have no rooms sub-stack to collapse and pop cleanly on their own.
    private func exitRoom() {
        NotificationCenter.default.post(name: .droobExitStudyRooms, object: nil)
        if let onLeaveRoom { onLeaveRoom() } else { dismiss() }
    }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(MyCoursesPalette.stroke)

                content

                // When the room has closed — or the viewer was removed by
                // a host — we swap the composer for a read-only banner.
                // Messages-tab "Ended" rows and removed-member rows both
                // route straight here, so the chat history is browsable
                // but posting is disabled.
                if isReadOnly {
                    readOnlyBanner
                } else {
                    composer
                }
            }

            // Transient toast for the moment the room flips from
            // ACTIVE → CLOSED while the user is still on the screen.
            if viewModel.closedBanner {
                closedOverlay
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Same bottom-trailing collision as the 1:1 chat: the send button
        // lands under the tab bar's AI orb, so suppress it here too.
        .hidesAiTutorOrb()
        .task { await viewModel.bootstrap() }
        // Mark this room as on-screen so a push for it is suppressed
        // (WhatsApp-style), and clear any of its tray notifications.
        .onAppear { PushService.shared.enterConversation(roomId) }
        .onDisappear { PushService.shared.leaveConversation(roomId) }
        .sheet(isPresented: $showInvite) {
            if let r = viewModel.room {
                inviteSheetContent(for: r)
            }
        }
        .sheet(isPresented: $showAttachmentSheet) {
            ChatAttachmentSheet(
                onPicked: { picked in handlePickedAttachment(picked) },
                onClose: { showAttachmentSheet = false })
        }
        .fullScreenCover(item: $previewImage) { item in
            ImagePreviewView(url: item.url) { previewImage = nil }
        }
        .alert(L10n.chatVoiceMicDeniedTitle,
               isPresented: $showMicPermissionAlert) {
            Button(L10n.chatVoiceMicDeniedOk, role: .cancel) {}
        } message: {
            Text(L10n.chatVoiceMicDeniedBody)
        }
        .fullScreenCover(isPresented: $showSettings) {
            if let r = viewModel.room {
                RoomSettingsView(room: r, onLeft: { exitRoom() })
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.droobGold.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(MyCoursesPalette.accent.opacity(0.4),
                                    lineWidth: 1))
                Image(systemName: "book.pages.fill")
                    .foregroundColor(MyCoursesPalette.accent)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(viewModel.room?.name ?? "")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .lineLimit(1)
                    // Live-bound YOU'RE HOST badge — flips on the
                    // `host_transferred` event so the user gets
                    // immediate visual feedback when they inherit
                    // the room.
                    if viewModel.myRole == .host {
                        HStack(spacing: 3) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text(L10n.studyRoomsYoureHostBadge)
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                        }
                        .foregroundColor(MyCoursesPalette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.droobGold.opacity(0.15))
                                .overlay(Capsule().stroke(
                                    MyCoursesPalette.accent.opacity(0.35),
                                    lineWidth: 1)))
                    }
                }
                statusRow
            }

            Spacer()

            // Settings — opens RoomSettingsView as a full sheet. Disabled
            // until the room detail has loaded.
            Button { showSettings = viewModel.room != nil } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(MyCoursesPalette.surface))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.room == nil)
            .opacity(viewModel.room == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// "Just you · waiting for others" when alone, otherwise
    /// "● N members" with a green dot.
    @ViewBuilder
    private var statusRow: some View {
        let count = viewModel.participantCount
        if count <= 1 {
            Text(L10n.studyRoomsHeaderJustYou)
                .font(.system(size: 11))
                .foregroundColor(MyCoursesPalette.muted)
                .lineLimit(1)
        } else {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.30, green: 0.82, blue: 0.45))
                    .frame(width: 6, height: 6)
                Text(membersString(count: count))
                    .font(.system(size: 11))
                    .foregroundColor(MyCoursesPalette.muted)
                    .lineLimit(1)
            }
        }
    }

    private func membersString(count: Int) -> String {
        count == 1
            ? L10n.studyRoomsRoomOneMember
            : String(format: L10n.studyRoomsRoomMembersFmt, count)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingInitial && viewModel.timeline.isEmpty {
            // First-paint loading — keep the pinned row and the chrome
            // visible so the screen doesn't look broken, but show a
            // centred spinner instead of the empty-room CTA (which
            // would mislead the user into thinking the room really is
            // empty before we know what's in it).
            pinnedRow
            Divider().background(MyCoursesPalette.stroke)
            VStack {
                Spacer()
                ProgressView()
                    .tint(MyCoursesPalette.accent)
                    .scaleEffect(1.1)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.timeline.isEmpty {
            // Empty room — pinned row stays under the header, then the
            // big illustration block + Invite CTA + (private only)
            // code chip.
            pinnedRow
            Divider().background(MyCoursesPalette.stroke)
            becameHostBannerOrNothing
            emptyState
                .padding(.top, 40)
            Spacer()
            // A read-only room (ended, or the viewer was removed) can't
            // be posted to — the "say hi" chip posts a message, so hide
            // it alongside the live empty-state copy.
            if !isReadOnly {
                sayHiChip
                    .padding(.bottom, 10)
            }
        } else {
            // Active room — pinned row sits above the timeline, which
            // scrolls between it and the composer.
            pinnedRow
            Divider().background(MyCoursesPalette.stroke)
            becameHostBannerOrNothing
            messageList
            // Removed members read history but can't post — hide the chip.
            if !isReadOnly {
                sayHiChip
                    .padding(.bottom, 6)
            }
        }
    }

    /// New-host banner shown after a `host_transferred` event names
    /// the viewer. Dismissable via the X; auto-dismisses on the next
    /// outbound message (see send hook).
    @ViewBuilder
    private var becameHostBannerOrNothing: some View {
        if let banner = viewModel.becameHostBanner {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.droobGold.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14))
                        .foregroundColor(MyCoursesPalette.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.studyRoomsBecameHostBannerTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                    Text(String(format: L10n.studyRoomsBecameHostBannerFmt,
                                banner.previousHostName, banner.roomName))
                        .font(.system(size: 12))
                        .foregroundColor(MyCoursesPalette.muted)
                }
                Spacer(minLength: 8)
                Button { viewModel.dismissBecameHostBanner() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(MyCoursesPalette.muted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(MyCoursesPalette.accent.opacity(0.40),
                                    lineWidth: 1)))
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Pinned row

    private var pinnedRow: some View {
        Button {
            // Pop back to the course detail. The whole study-rooms
            // stack is nested inside the course's nav controller, so
            // dismiss() unwinds to it.
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundColor(MyCoursesPalette.accent.opacity(0.75))
                Text(L10n.studyRoomsPinnedPrefix)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
                Text("·")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
                Text(displayCourseTitle)
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.muted)
                Text("—")
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.textTertiary)
                Text(viewModel.room?.name ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        // A closed room can't be joined or posted to, so every live
        // empty state (each carries an Invite CTA + join-code chip) is
        // misleading here — users think the room is live and try to
        // invite people. Show neutral read-only copy instead.
        if isRoomClosed {
            return AnyView(endedEmptyState)
        }
        // The header status row branches on `participantCount` to
        // switch between "Just you · waiting for others" and
        // "● N members"; the empty state was never updated to do the
        // same and unconditionally showed "The room is all yours" /
        // "Nobody's here yet…" even with others present, contradicting
        // the actual member list. Mirror the header's check here.
        let isAlone = viewModel.participantCount <= 1
        return AnyView(VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(MyCoursesPalette.accent.opacity(0.3), lineWidth: 1)
                    .frame(width: 110, height: 110)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.droobGold.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(MyCoursesPalette.accent.opacity(0.4),
                                    lineWidth: 1))
                    .frame(width: 64, height: 64)
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
            }
            .padding(.bottom, 8)

            if isAlone {
                // Two-tone "The room is" primary + "all yours" gold —
                // the celebratory copy that only makes sense when the
                // host is genuinely alone in the room.
                HStack(spacing: 6) {
                    Text(L10n.studyRoomEmptyLine1)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                    Text(L10n.studyRoomEmptyLine2)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(MyCoursesPalette.accent)
                }
                .accessibilityLabel(L10n.studyRoomsEmptyAlone)
            } else {
                // Others are present — the room isn't "all yours" and
                // the subtitle's "Nobody's here yet" line would be a
                // lie. Show a neutral "no messages yet" headline
                // instead, matching the standard chat empty-state
                // pattern.
                Text(L10n.studyRoomsEmptyWithOthersTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(MyCoursesPalette.accent)
                    .multilineTextAlignment(.center)
            }

            Text(isAlone
                 ? L10n.studyRoomsEmptyAloneSubtitle
                 : L10n.studyRoomsEmptyWithOthersSubtitle)
                .font(.system(size: 13))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Hidden for instructor rooms (2026-07): students don't
            // invite/share into the instructor's room — membership is
            // driven from the course detail card.
            if !isInstructorRoom {
                Button {
                    showInvite = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                        Text(L10n.studyRoomsInviteClassmates)
                            .font(.system(size: 15, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.droobGold,
                                         Color.droobGold.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                    )
                    .foregroundColor(.black)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Private rooms surface the room code under the Invite
                // CTA so the host can copy/share it without opening the
                // sheet.
                if viewModel.room?.privacy == .private,
                   let code = viewModel.room?.joinCode, !code.isEmpty {
                    RoomCodeChip(rawCode: code)
                        .padding(.top, 12)
                }
            }
        })
    }

    /// Empty state for a CLOSED room with no messages — read-only copy
    /// with no Invite CTA or join-code chip, since the room can't be
    /// joined or posted to anymore.
    private var endedEmptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(MyCoursesPalette.stroke, lineWidth: 1)
                    .frame(width: 110, height: 110)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(MyCoursesPalette.stroke,
                                    lineWidth: 1))
                    .frame(width: 64, height: 64)
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            .padding(.bottom, 8)

            Text(L10n.studyRoomsEmptyEndedTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)
                .multilineTextAlignment(.center)

            Text(L10n.studyRoomsEmptyEndedSubtitle)
                .font(.system(size: 13))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    // Top sentinel: when this scrolls into view the
                    // user has reached the oldest loaded message, so
                    // fetch the next older page. Hidden zero-height
                    // marker; the visible affordance below it is the
                    // small "loading older messages" spinner.
                    if viewModel.hasMore {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task { await viewModel.loadMore() }
                            }
                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(MyCoursesPalette.accent)
                                    .padding(.vertical, 10)
                                Spacer()
                            }
                        }
                    }
                    ForEach(viewModel.timeline) { row in
                        timelineRow(row)
                            .id(row.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .refreshable { await viewModel.refresh() }
            .onChange(of: viewModel.timeline.count) { _ in
                // Auto-scroll to the newest message on append. Skip
                // when a paging fetch was the trigger — `isLoadingMore`
                // is briefly true during the prepend, and scrolling
                // to the bottom would yank the user away from the
                // older messages they just asked to see.
                guard !viewModel.isLoadingMore,
                      let last = viewModel.timeline.last else { return }
                if didInitialScroll {
                    // Subsequent live appends animate into view.
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                } else {
                    // Initial population that happened *after* this view
                    // was already on screen (e.g. an empty room receiving
                    // its first live message). `.onAppear` couldn't catch
                    // it, so land at the bottom here instead.
                    landAtBottom(proxy, last: last.id)
                }
            }
            .onAppear {
                // `.onChange` never fires for a view's initial value, and
                // `messageList` is only inserted once `timeline` is
                // already non-empty — so the first page's 0→N change is
                // this view's initial value and the count-based scroll
                // misses it. An active room is rescued by the next live
                // socket message; a left room opens no socket, so without
                // this the read-only history opened stranded at the top.
                guard !didInitialScroll,
                      let last = viewModel.timeline.last else { return }
                landAtBottom(proxy, last: last.id)
            }
        }
    }

    /// One-time jump to the newest message when the timeline first
    /// renders. Deferred one runloop so the `LazyVStack` has committed
    /// its rows before we scroll — otherwise the target id isn't
    /// realized yet and `scrollTo` no-ops, leaving the view at the top.
    /// No animation so the conversation opens pinned to "now" instead of
    /// sliding down from the top.
    private func landAtBottom(_ proxy: ScrollViewProxy, last: String) {
        didInitialScroll = true
        DispatchQueue.main.async {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func timelineRow(_ row: TimelineRow) -> some View {
        switch row {
        case .dateSeparator(_, let label):
            HStack {
                Spacer()
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(MyCoursesPalette.surface))
                Spacer()
            }
            .padding(.vertical, 4)

        case .message(_, let message):
            // V55: SYSTEM_* kinds ship through the same /messages
            // pipeline as text/attachment/shared-notes — they're now
            // persisted rows, not transient socket pings — so they
            // reach this case alongside chat bubbles. Route them to
            // the centred system-pill renderer instead of building
            // a chat bubble for them.
            if message.kind.isSystem {
                systemEventRow(for: message)
            } else {
                StudyRoomMessageBubble(
                    message: message,
                    fromMe: viewModel.isFromMe(message),
                    isSenderHost: viewModel.isCurrentHost(message.senderId),
                    isSenderInstructor: message.senderIsInstructor,
                    senderDisplayName: senderDisplayName(message),
                    onTapImage: { url in previewImage = ImagePreviewItem(url: url) },
                    appLocale: appLocale)
            }

        }
    }

    /// Renders a SYSTEM_* persisted message as a centred pill with
    /// flanking horizontal dividers (the WhatsApp "Layla joined"
    /// pattern). Branches on `message.kind` to compose the right
    /// localized text — bold actor name + muted suffix, plus the
    /// new-host slot for HOST_TRANSFERRED — and reuses
    /// `SystemEventPill` for the chrome.
    /// Sender name as shown in the UI. Anonymized peers in instructor
    /// rooms (2026-07: `sender_anon_index` set, message not mine) get
    /// the localized "Student N" alias instead of the wire
    /// `sender_name`, so the alias follows the app language.
    private func senderDisplayName(_ message: StudyRoomMessage) -> String {
        if let idx = message.senderAnonIndex, !viewModel.isFromMe(message) {
            return String(format: L10n.studyRoomsAnonStudentFmt, idx)
        }
        return message.senderName
    }

    @ViewBuilder
    private func systemEventRow(for message: StudyRoomMessage) -> some View {
        HStack(spacing: 8) {
            joinDivider
            SystemEventPill(
                userId: message.senderAvatarKey,
                initials: message.senderInitials,
                content: systemEventContent(for: message),
                accessibilityText: systemEventAccessibilityText(for: message))
                .fixedSize(horizontal: true, vertical: false)
            joinDivider
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    /// Composes the bold-name + muted-suffix `Text` for a system pill.
    /// Reads `fromMe` (actor-is-me) and `isSubjectMe` (HOST_TRANSFERRED
    /// new-host is me) from the view-model so the rendered phrase
    /// swaps the name slot to "You" / "you're now the host" in the
    /// right viewer's chat.
    private func systemEventContent(for message: StudyRoomMessage) -> Text {
        let actorMe = viewModel.isFromMe(message)
        let actorName = actorMe
            ? L10n.studyRoomsSystemActorYou
            : senderDisplayName(message)
        let bold = Text(actorName)
            .font(SystemEventPillStyle.nameFont)
            .foregroundColor(SystemEventPillStyle.nameColor)

        switch message.kind {
        case .systemMemberJoined:
            return bold + mutedSuffix(" \(L10n.studyRoomsJoinedSuffix)")
        case .systemMemberLeft:
            return bold + mutedSuffix(" \(L10n.studyRoomsLeftSuffix)")
        case .systemHostChanged:
            // "X is now the host" / "You are now the host".
            return bold + mutedSuffix(" \(L10n.studyRoomsIsNowHostSuffix)")
        case .systemHostTransferred:
            // Combined "{prev} left · {new} is now the host". `prev`
            // is the actor (sender), `new` is the subject. We render
            // the prev name bold, the connector + " is now the
            // host" muted, with the new-host slot swapped to "You"
            // when the viewer is the new host. Build the trailing
            // span with `String(format:)` against the existing two-
            // arg / "you" formats so RTL layout stays correct.
            let subjectMe = viewModel.isSubject(message)
            let subjectName = subjectMe
                ? L10n.studyRoomsSystemActorYou
                : (message.subjectName ?? L10n.studyRoomsHostFallback)
            // The Arabic and English combined-pill templates differ
            // in conjugation between the "you are now" form and the
            // "X is now" form, so we use two separate format keys.
            let suffix: String
            if subjectMe {
                // "{prev} left · you are now the host" — the prev
                // name slot lives inside the template (verbatim
                // substitution) and the format already includes
                // the bold-equivalent leading word, so we replace
                // the leading "%@ " with an empty span and emit
                // the rest as muted. Quickest implementation:
                // strip the leading %@ token and prepend our own
                // bold name span.
                suffix = String(
                    format: L10n.studyRoomsCombinedLeftAndHostFmt,
                    "").trimmingCharacters(in: .whitespaces)
                return bold + mutedSuffix(" \(suffix)")
            } else {
                suffix = String(
                    format: L10n.studyRoomsCombinedLeftAndOtherHostFmt,
                    "", subjectName).trimmingCharacters(in: .whitespaces)
                return bold + mutedSuffix(" \(suffix)")
            }
        case .text, .attachment, .sharedNotes:
            // Non-system kinds shouldn't reach this builder, but stay
            // exhaustive so the compiler flags any future addition.
            return Text("")
        }
    }

    private func mutedSuffix(_ s: String) -> Text {
        Text(s)
            .font(SystemEventPillStyle.bodyFont)
            .foregroundColor(SystemEventPillStyle.mutedColor)
    }

    /// VoiceOver-friendly plain text for the same pill. Mirrors the
    /// `systemEventContent` switch but without the styling, so an
    /// assistive-tech user hears the same phrase a sighted user reads.
    private func systemEventAccessibilityText(for message: StudyRoomMessage) -> String {
        let actorMe = viewModel.isFromMe(message)
        let actor = actorMe
            ? L10n.studyRoomsSystemActorYou
            : senderDisplayName(message)
        switch message.kind {
        case .systemMemberJoined:
            return "\(actor) \(L10n.studyRoomsJoinedSuffix)"
        case .systemMemberLeft:
            return "\(actor) \(L10n.studyRoomsLeftSuffix)"
        case .systemHostChanged:
            return "\(actor) \(L10n.studyRoomsIsNowHostSuffix)"
        case .systemHostTransferred:
            let subjectMe = viewModel.isSubject(message)
            if subjectMe {
                return String(
                    format: L10n.studyRoomsCombinedLeftAndHostFmt, actor)
            } else {
                let subjectName = message.subjectName
                    ?? L10n.studyRoomsHostFallback
                return String(
                    format: L10n.studyRoomsCombinedLeftAndOtherHostFmt,
                    actor, subjectName)
            }
        case .text, .attachment, .sharedNotes:
            return ""
        }
    }

    /// Thin horizontal rule used on either side of a join pill so the
    /// row reads as a centred system event (`— Layla joined —`) rather
    /// than a freestanding bubble. Colour matches the Figma divider
    /// fill `rgba(84,84,88,0.3)` and the height is the same hairline
    /// used by the rest of the chat chrome. Kept fixed rather than
    /// palette-driven: a mid-grey at 30% is a visible hairline over
    /// both the light and the dark chat background.
    private var joinDivider: some View {
        Rectangle()
            .fill(Color(red: 84.0/255, green: 84.0/255, blue: 88.0/255)
                  .opacity(0.30))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Say hi + composer

    private var sayHiChip: some View {
        HStack {
            Button {
                Task { await viewModel.sendSayHi() }
            } label: {
                Text(L10n.studyRoomsSayHi)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(Color.droobGold.opacity(0.10))
                            .overlay(Capsule().stroke(
                                MyCoursesPalette.accent.opacity(0.35),
                                lineWidth: 1)))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var composer: some View {
        VStack(spacing: 6) {
            // Attachment preview / upload-in-flight pill, stacked above
            // the input row so the user always sees what's queued for
            // send. Mirrors the InstructorChatView composer.
            if let pending = pendingAttachment {
                attachmentPreviewPill(pending)
            } else if isUploading {
                uploadingPill
            }
            if let err = uploadError {
                Text(err)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(MyCoursesPalette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
            // Recording → swap the whole bar; otherwise the standard
            // input + mic / plus / send row.
            if recorder.isRecording {
                recordingBar
            } else {
                composerInputRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            MyCoursesPalette.surface
                .overlay(Rectangle()
                    .frame(height: 1)
                    .foregroundColor(MyCoursesPalette.stroke),
                    alignment: .top)
        )
    }

    /// The composer bar itself is `surface`; every control that sits
    /// *inside* it (this input pill, the "+" button, the recording bar,
    /// the uploading pill, the attachment preview) uses `surfaceNested`.
    /// They all resolved to `surface` after the light-mode conversion,
    /// so the text field flattened into the bar and lost its shape in
    /// both themes.
    private var composerInputRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField(L10n.studyRoomsComposerPlaceholder,
                          text: $composerText, axis: .vertical)
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .font(.system(size: 14))
                    .lineLimit(1...4)
                // Mic → start a voice recording. Disabled while an
                // attachment is queued (voice replaces gallery
                // attachments, doesn't stack with them) or mid-upload.
                Button {
                    Task { await startRecording() }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                }
                .buttonStyle(.plain)
                .disabled(isUploading || pendingAttachment != nil)
                .opacity(isUploading || pendingAttachment != nil ? 0.5 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(MyCoursesPalette.surfaceNested)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(MyCoursesPalette.stroke,
                                    lineWidth: 1))
            )

            // Plus → open the gallery / documents sheet.
            Button { showAttachmentSheet = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(MyCoursesPalette.surfaceNested))
            }
            .buttonStyle(.plain)
            .disabled(isUploading)
            .opacity(isUploading ? 0.5 : 1)

            Button { sendComposer() } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.droobGold,
                                         Color.droobGold.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.5)
        }
    }

    private var recordingBar: some View {
        HStack(spacing: 12) {
            Button { recorder.cancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(MyCoursesPalette.surfaceNested))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(recordingPulse ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                               value: recordingPulse)
                    .onAppear { recordingPulse = true }
                Text(formatDuration(Int(recorder.elapsed)))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(L10n.chatVoiceRecording)
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(MyCoursesPalette.surfaceNested)
            .clipShape(Capsule())

            Button {
                Task { await finishRecording() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(LinearGradient(
                        colors: [Color.droobGold, Color.droobGold.opacity(0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .buttonStyle(.plain)
        }
    }

    /// Spinner shown between picker-selection and the upload completing.
    private var uploadingPill: some View {
        HStack(spacing: 10) {
            ProgressView().tint(MyCoursesPalette.accent)
            Text(L10n.chatAttachmentUploading)
                .font(.system(size: 12))
                .foregroundColor(MyCoursesPalette.muted)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MyCoursesPalette.surfaceNested)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Settled preview row showing the queued attachment + an X to
    /// drop it before send.
    private func attachmentPreviewPill(_ pending: ChatAttachmentUpload) -> some View {
        HStack(spacing: 10) {
            if pending.attachmentType == "IMAGE",
               let url = URL(string: pending.attachmentUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: MyCoursesPalette.surface
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.droobGold.opacity(0.15))
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 16))
                        .foregroundColor(MyCoursesPalette.accent)
                }
                .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(pending.attachmentName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(1)
                Text(L10n.fileSize(pending.attachmentSizeBytes))
                    .font(.system(size: 11))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            Spacer()
            Button { pendingAttachment = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
                    .frame(width: 24, height: 24)
                    .background(MyCoursesPalette.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(MyCoursesPalette.surfaceNested)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Send enabled when there's at least one of text or attachment,
    /// and we're not mid-upload.
    private var canSend: Bool {
        let hasText = !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachment = pendingAttachment != nil
        return (hasText || hasAttachment) && !isUploading
    }

    /// Routes the composer state to either `sendText` or
    /// `sendAttachment` based on whether an upload is queued. Caption
    /// + attachment ship together when both are present.
    private func sendComposer() {
        // The act of sending implies the user has acknowledged the
        // new-host banner.
        viewModel.dismissBecameHostBanner()
        let body = composerText
        let attachment = pendingAttachment
        composerText = ""
        pendingAttachment = nil
        if let attachment {
            Task { await viewModel.sendAttachment(upload: attachment, body: body) }
        } else {
            Task { await viewModel.sendText(body) }
        }
    }

    // MARK: Attachment / voice plumbing

    private func handlePickedAttachment(_ picked: PickedAttachment) {
        showAttachmentSheet = false
        uploadError = nil
        isUploading = true
        Task {
            do {
                let upload = try await ChatAttachmentUploader.upload(
                    data: picked.data,
                    filename: picked.filename,
                    contentType: picked.contentType)
                await MainActor.run {
                    pendingAttachment = upload
                    isUploading = false
                }
            } catch {
                await MainActor.run {
                    uploadError = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    isUploading = false
                    pendingAttachment = nil
                }
            }
        }
    }

    private func startRecording() async {
        uploadError = nil
        let ok = await recorder.start()
        if !ok && recorder.permissionDenied {
            showMicPermissionAlert = true
        }
    }

    private func finishRecording() async {
        guard let recording = await recorder.stop() else { return }
        guard recording.durationSeconds > 0 else { return }
        uploadError = nil
        isUploading = true
        defer { isUploading = false }
        do {
            let upload = try await ChatAttachmentUploader.upload(
                data: recording.data,
                filename: recording.filename,
                contentType: recording.contentType)
            // Voice notes ship immediately — no caption step.
            viewModel.dismissBecameHostBanner()
            await viewModel.sendAttachment(
                upload: upload,
                body: nil,
                voiceDurationSeconds: recording.durationSeconds)
        } catch {
            uploadError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func formatDuration(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Invite sheet + closed overlay

    @ViewBuilder
    private func inviteSheetContent(for r: StudyRoomDetail) -> some View {
        if #available(iOS 16.4, *) {
            InviteSheet(room: r)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(MyCoursesPalette.background)
        } else {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                InviteSheet(room: r)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Closed-room banner

    /// `true` whenever the detail says the room is CLOSED. Drives the
    /// composer ↔ read-only-banner swap. Distinct from
    /// `viewModel.closedBanner` which is the *transient* toast for
    /// rooms that close while the chat is open.
    private var isRoomClosed: Bool {
        viewModel.room?.status == .closed || viewModel.roomClosedLive
    }

    /// `true` when a host has removed (kicked) the viewer from a room
    /// that is still ACTIVE. The viewer keeps read-only access to
    /// history (the backend grants former members read access up to
    /// their `leftAt`), but the composer is hidden. Distinct from
    /// `isRoomClosed`, which is about the *room* ending rather than this
    /// viewer being kicked, and from `didLeave` (a voluntary exit).
    private var wasRemoved: Bool {
        guard !isRoomClosed else { return false }
        // `was_removed` from the detail fetch (we opened the chat after
        // the kick) or a live `member_removed` event that named us.
        return viewModel.room?.wasRemoved == true || viewModel.removedFromRoom
    }

    /// `true` when the viewer left this still-ACTIVE room on their own —
    /// not a kick. Same read-only history access as a removal, but the
    /// banner copy is neutral ("you left") rather than "a host removed
    /// you."
    private var didLeave: Bool {
        guard !isRoomClosed, !wasRemoved else { return false }
        return viewModel.room?.isMember == false
    }

    /// Drives the composer ↔ read-only-banner swap. Read-only applies
    /// when the room has CLOSED, when the viewer was removed, or when
    /// they left — all three keep history readable but disable posting.
    private var isReadOnly: Bool {
        isRoomClosed || wasRemoved || didLeave
    }

    /// Title + subtitle for the read-only banner, picked from the three
    /// read-only states. Removal and leave share the "you can still read
    /// history" framing but differ on cause; a closed room is about the
    /// room ending for everyone.
    private var readOnlyBannerText: (title: String, subtitle: String) {
        if wasRemoved {
            return (L10n.studyRoomsRemovedBannerTitle,
                    L10n.studyRoomsRemovedBannerSubtitle)
        }
        if didLeave {
            return (L10n.studyRoomsLeftBannerTitle,
                    L10n.studyRoomsLeftBannerSubtitle)
        }
        return (L10n.studyRoomsClosedBannerTitle,
                L10n.studyRoomsClosedBannerSubtitle)
    }

    /// Persistent read-only banner used in lieu of the composer for
    /// rooms the viewer can read but not post to — because the room
    /// ended, a host removed them, or they left.
    private var readOnlyBanner: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundColor(MyCoursesPalette.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(readOnlyBannerText.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                    Text(readOnlyBannerText.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(MyCoursesPalette.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            MyCoursesPalette.surface
                .overlay(Rectangle()
                    .frame(height: 1)
                    .foregroundColor(MyCoursesPalette.stroke),
                    alignment: .top)
        )
    }

    private var closedOverlay: some View {
        ZStack {
            // Dim the dead room behind the card so it no longer reads as
            // a live, interactive screen. A black scrim is the right
            // dim in both themes — it isn't a surface.
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 26))
                    .foregroundColor(MyCoursesPalette.accent)
                Text(L10n.studyRoomsClosedBannerTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(L10n.studyRoomsClosedBannerSubtitle)
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    // Unwind out of the dead room — collapse the course
                    // rooms sub-stack (or plain pop for Messages / deep-link
                    // entry points) via the shared, race-free exit.
                    exitRoom()
                } label: {
                    Text(L10n.studyRoomsRoomEndedExit)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.droobGold))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(MyCoursesPalette.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(MyCoursesPalette.accent.opacity(0.35), lineWidth: 1))
            )
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Message bubble

private struct StudyRoomMessageBubble: View {
    let message: StudyRoomMessage
    /// Whether this message was sent by the viewer. Computed by the
    /// view-model from AuthSession instead of `message.fromMe` — the
    /// server's `from_me` field is unreliable for socket-delivered
    /// messages (one broadcast payload fans out to N subscribers, so
    /// it can't be per-recipient correct).
    let fromMe: Bool
    /// Whether the sender is the *current* host at render time —
    /// drives the small gold HOST badge next to their name. Reactive
    /// on live `host_transferred` events so a former host's old
    /// messages stop showing the badge after a transfer.
    let isSenderHost: Bool
    /// Whether the sender is the course instructor (2026-07
    /// instructor-created rooms) — drives the gold INSTRUCTOR badge,
    /// reusing the HOST badge chrome.
    let isSenderInstructor: Bool
    /// Display name for the sender — the parent substitutes the
    /// localized "Student N" alias for anonymized peers, so the
    /// bubble never renders the wire name directly.
    let senderDisplayName: String
    /// Tap on an image attachment hoists the URL up to the parent
    /// so the preview cover overlays the whole chat, not just the
    /// bubble.
    let onTapImage: (URL) -> Void
    /// Locale for the per-message clock so Arabic renders localized
    /// AM/PM markers. Threaded from the view's `appLocale`.
    let appLocale: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if fromMe { Spacer(minLength: 40) }

            if !fromMe {
                MemberAvatar(userId: message.senderAvatarKey,
                             initials: message.senderInitials,
                             size: 28)
            }

            VStack(alignment: fromMe ? .trailing : .leading,
                   spacing: 3) {
                if !fromMe {
                    HStack(spacing: 6) {
                        Text(senderDisplayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.muted)
                        if isSenderInstructor {
                            // Instructor messages keep real identity and
                            // get their own badge — same chrome as HOST.
                            Text(L10n.studyRoomsInstructorRoleBadge)
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(MyCoursesPalette.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.droobGold.opacity(0.15)))
                        } else if isSenderHost {
                            Text(L10n.studyRoomsHostRoleBadge)
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(MyCoursesPalette.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.droobGold.opacity(0.15)))
                        }
                    }
                }
                bubble
                Text(formattedClock(message.createdAt))
                    .font(.system(size: 10))
                    .foregroundColor(MyCoursesPalette.textTertiary)
                    .padding(.horizontal, 2)
            }

            if !fromMe { Spacer(minLength: 40) }
        }
    }

    /// Per-message send time, e.g. "2:45 PM". Mirrors the 1:1 chat
    /// clock format and respects the active locale for AM/PM markers.
    private func formattedClock(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: appLocale)
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }

    /// Branches on `kind`/`attachmentType` to render the right body —
    /// text, image preview, document chip, voice player, or shared
    /// notes carousel. The text and document paths share the same
    /// rounded background; image / voice use bespoke layouts so the
    /// outer bubble doesn't double-frame them.
    @ViewBuilder
    private var bubble: some View {
        switch message.kind {
        case .text:
            textBubble(message.body ?? "")
        case .sharedNotes:
            // Renders the same as a text bubble for v1; the dedicated
            // shared-notes carousel ships with the notes-sharing UI.
            textBubble(message.body ?? L10n.studyRoomSharedNotes)
        case .attachment:
            switch message.attachmentType {
            case .document, .none:
                documentChip
            case .image:
                imageBubble
            case .voice:
                voiceBubble
            }
        case .systemMemberJoined, .systemMemberLeft,
             .systemHostChanged, .systemHostTransferred:
            // Unreachable in practice — the timeline-row dispatcher
            // routes SYSTEM_* kinds to `systemEventRow` before they
            // reach this bubble builder. Kept exhaustive so the
            // compiler flags any future kind we forget to handle.
            EmptyView()
        }
    }

    /// Square thumbnail with a tap-target that hoists the URL up so
    /// the parent presents a full-screen `ImagePreviewView`. Matches
    /// the InstructorChatView image bubble exactly.
    @ViewBuilder
    private var imageBubble: some View {
        if let urlStr = message.attachmentUrl,
           let url = URL(string: urlStr) {
            Button { onTapImage(url) } label: {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: MyCoursesPalette.surface
                    default:
                        ZStack {
                            MyCoursesPalette.surface
                            ProgressView().tint(MyCoursesPalette.accent)
                        }
                    }
                }
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
                // Pin the hit region to the rounded thumbnail so a
                // tap on a neighbouring bubble can't be misrouted to
                // this button after a fullScreenCover dismiss.
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// Reuses the shared `VoiceNoteBubble` so play/pause / progress
    /// behaviour matches the 1:1 chat exactly.
    @ViewBuilder
    private var voiceBubble: some View {
        if let urlStr = message.attachmentUrl,
           let url = URL(string: urlStr) {
            VoiceNoteBubble(
                url: url,
                messageId: message.messageId,
                totalSeconds: message.attachmentDurationSeconds ?? 0,
                outgoing: fromMe)
        }
    }

    private func textBubble(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 14))
            .foregroundColor(fromMe ? Color.black : MyCoursesPalette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(bubbleBackground)
            .cornerRadius(14)
    }

    /// Document attachment chip — red file icon (`danger`, which darkens
    /// its ramp in light mode; the fixed #F26666 was picked for a dark
    /// bubble and washed out on the light one), name on top,
    /// "{pages} pages · {size}" caption, and a download glyph.
    /// Matches the figma layout from the chat-with-messages screen.
    private var documentChip: some View {
        let bytes = message.attachmentSizeBytes ?? 0
        let sizeText = L10n.fileSize(Int64(bytes))
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.85, green: 0.25, blue: 0.25)
                              .opacity(0.22))
                Image(systemName: "doc.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.danger)
            }
            .frame(width: 36, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.attachmentName ?? "Document")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(fromMe ? Color.black : MyCoursesPalette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(sizeText)
                    .font(.system(size: 11))
                    .foregroundColor(fromMe
                                     ? Color.black.opacity(0.55)
                                     : MyCoursesPalette.muted)
            }

            Spacer(minLength: 12)

            // Tap → open in Safari / system handler. We have the
            // presigned URL on the message; no separate download
            // endpoint needed.
            if let urlStr = message.attachmentUrl,
               let url = URL(string: urlStr) {
                Link(destination: url) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 20))
                        .foregroundColor(fromMe
                                         ? .black.opacity(0.7)
                                         : MyCoursesPalette.accent)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 280)
        .background(bubbleBackground)
        .cornerRadius(14)
    }

    private var bubbleBackground: some View {
        Group {
            if fromMe {
                LinearGradient(
                    colors: [Color.droobGold,
                             Color.droobGold.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            } else {
                MyCoursesPalette.surface
            }
        }
    }
}
