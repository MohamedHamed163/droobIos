import SwiftUI

// MARK: - Messages screen
//
// V47 (Study Rooms) rebuild: the Messages tab is now two surfaces
// behind a top-of-screen switcher pill.
//
//   • Chats  — 1:1 instructor threads (the legacy inbox)
//   • Rooms  — study-room memberships across all courses, with a
//              sub-filter (All / Running / Ended)
//
// Tapping any row in either surface marks it read (server +
// optimistically locally) and pushes the chat screen.
//
// The old "Announcements" sub-tab is gone — those notifications now
// live on the Notification Center surface elsewhere.

struct MessagesView: View {
    @StateObject private var viewModel = MessagingViewModel()
    @State private var top: TopTab = .chats
    @State private var roomsFilter: RoomsFilter = .all

    enum TopTab { case chats, rooms }
    enum RoomsFilter { case all, running, ended }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                headerArea
                switcherPill
                if top == .rooms {
                    roomsFilterChips
                        .padding(.top, 2)
                        .padding(.bottom, 10)
                } else {
                    Spacer().frame(height: 6)
                }
                tabContent
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            async let t: () = viewModel.loadThreads()
            async let r: () = viewModel.loadRooms()
            await t; await r
        }
        // No animations on loading-state flips: prevents the empty-state /
        // skeleton transition from causing the entire ScrollView to bounce
        // up and down on each re-render.
        .animation(nil, value: viewModel.isLoadingThreads)
        .animation(nil, value: viewModel.isLoadingRooms)
        .animation(nil, value: viewModel.threads.count)
        .animation(nil, value: viewModel.rooms.count)
        .onReceive(NotificationCenter.default.publisher(
            for: .droobStudyRoomDidChange)) { _ in
            Task { await viewModel.loadRooms() }
        }
    }

    // MARK: Header

    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.messagesScreenTitle)
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(MyCoursesPalette.accent)
                .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: Top switcher (Chats / Rooms)

    private var switcherPill: some View {
        HStack(spacing: 0) {
            switcherSegment(
                title: L10n.messagesSwitcherChats,
                icon: "bubble.left.and.bubble.right.fill",
                badge: viewModel.chatsUnreadTotal,
                selected: top == .chats) {
                top = .chats
            }
            switcherSegment(
                title: L10n.messagesSwitcherRooms,
                icon: "person.3.fill",
                badge: viewModel.roomsUnreadTotal,
                selected: top == .rooms) {
                top = .rooms
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(MyCoursesPalette.surface)
                .overlay(Capsule().stroke(MyCoursesPalette.stroke, lineWidth: 1))
        )
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func switcherSegment(title: String,
                                 icon: String,
                                 badge: Int,
                                 selected: Bool,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.system(size: 10, weight: .bold))
                        // Both branches sit on gold (a black wash over the
                        // selected gradient, solid gold when unselected), so
                        // both take the dark ink the fill was designed for —
                        // white on #C6A96B is ~1.9:1 in either theme.
                        .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(selected
                                      ? Color.black.opacity(0.18)
                                      : Color.droobGold))
                }
            }
            .foregroundColor(selected
                             ? Color(red: 0.10, green: 0.07, blue: 0.04)
                             : MyCoursesPalette.muted)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if selected {
                        Capsule().fill(LinearGradient.droobBrand)
                    } else {
                        Capsule().fill(Color.clear)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Rooms sub-filter chips

    private var roomsFilterChips: some View {
        HStack(spacing: 8) {
            filterChip(L10n.messagesRoomsFilterAll,
                       count: visibleRooms.count,
                       selected: roomsFilter == .all) { roomsFilter = .all }
            filterChip(L10n.messagesRoomsFilterRunning,
                       count: runningRooms.count,
                       selected: roomsFilter == .running) { roomsFilter = .running }
            filterChip(L10n.messagesRoomsFilterEnded,
                       count: endedRooms.count,
                       selected: roomsFilter == .ended) { roomsFilter = .ended }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    @ViewBuilder
    private func filterChip(_ label: String, count: Int,
                            selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(selected
                                         ? Color(red: 0.10, green: 0.07, blue: 0.04)
                                         : MyCoursesPalette.muted)
                }
            }
            .foregroundColor(selected
                             ? Color(red: 0.10, green: 0.07, blue: 0.04)
                             : MyCoursesPalette.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient.droobBrand)
                          : AnyShapeStyle(Color.clear))
                    .overlay(
                        Capsule().stroke(
                            selected ? Color.clear : MyCoursesPalette.stroke,
                            lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Tab content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                Group {
                    if top == .chats {
                        chatsContent
                    } else {
                        roomsContent
                    }
                }
                .transaction { $0.animation = nil }
            }
            .padding(.bottom, 40)
        }
        .droobBounceBasedOnSize()
        .scrollIndicators(.hidden)
    }

    // MARK: Chats

    @ViewBuilder
    private var chatsContent: some View {
        if viewModel.isLoadingThreads {
            rowSkeletons
        } else if let err = viewModel.threadsError {
            ErrorBanner(message: err) { Task { await viewModel.loadThreads() } }
                .padding(.horizontal, 20).padding(.top, 32)
        } else if viewModel.threads.isEmpty {
            chatsEmptyState
        } else {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.threads) { thread in
                    NavigationLink {
                        // Same full-featured chat the instructor-profile
                        // entry uses (text + voice notes + attachments).
                        // Passing the thread id routes the load through
                        // the by-thread endpoint so the unread counter is
                        // cleared on open.
                        InstructorChatView(
                            instructorId: thread.instructorId,
                            instructorName: thread.instructorName,
                            instructorAvatarUrl: thread.instructorAvatarUrl,
                            threadId: thread.threadId)
                    } label: {
                        ThreadRow(thread: thread)
                    }
                    .buttonStyle(.plain)
                    Divider().background(MyCoursesPalette.stroke).padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, 20)
            .background(MyCoursesPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
    }

    // MARK: Rooms

    @ViewBuilder
    private var roomsContent: some View {
        if viewModel.isLoadingRooms {
            rowSkeletons
        } else if let err = viewModel.roomsError {
            ErrorBanner(message: err) { Task { await viewModel.loadRooms() } }
                .padding(.horizontal, 20).padding(.top, 32)
        } else if filteredRooms.isEmpty {
            roomsEmptyState
        } else {
            LazyVStack(spacing: 0) {
                ForEach(filteredRooms) { room in
                    NavigationLink {
                        StudyRoomChatView(roomId: room.roomId)
                            .onAppear {
                                // Server-side mark-read on first tap.
                                // The chat view itself also bumps the
                                // membership when the first-page fetch
                                // runs without a `before` cursor, so
                                // this is belt-and-braces.
                                Task {
                                    try? await StudyRoomsAPI.markRead(
                                        roomId: room.roomId)
                                }
                            }
                    } label: {
                        RoomRow(room: room)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        // Optimistic local clear so the badge falls to
                        // zero the instant the user taps the row.
                        markRoomReadLocally(room.roomId)
                    })
                    Divider().background(MyCoursesPalette.stroke)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, 20)
            .background(MyCoursesPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
    }

    // MARK: Empty states

    private var chatsEmptyState: some View {
        emptyState(
            icon: "bubble.left.and.bubble.right",
            title: L10n.messagesNoChatsTitle,
            subtitle: L10n.messagesNoChatsSubtitle,
            ctaTitle: L10n.messagesNoChatsCta,
            ctaIcon: "books.vertical.fill"
        ) {
            NotificationCenter.default.post(
                name: .droobSwitchToTab,
                object: AppTab.courses)
        }
    }

    @ViewBuilder
    private var roomsEmptyState: some View {
        switch roomsFilter {
        case .all, .running:
            emptyState(
                icon: "person.3",
                title: L10n.messagesNoRoomsTitle,
                subtitle: L10n.messagesNoRoomsSubtitle,
                ctaTitle: L10n.messagesNoRoomsCta,
                ctaIcon: "books.vertical.fill"
            ) {
                NotificationCenter.default.post(
                    name: .droobSwitchToTab,
                    object: AppTab.courses)
            }
        case .ended:
            emptyState(
                icon: "lock.fill",
                title: L10n.messagesNoEndedRoomsTitle,
                subtitle: L10n.messagesNoEndedRoomsSubtitle,
                ctaTitle: nil,
                ctaIcon: nil,
                onCta: nil
            )
        }
    }

    private func emptyState(icon: String,
                            title: String,
                            subtitle: String,
                            ctaTitle: String? = nil,
                            ctaIcon: String? = nil,
                            onCta: (() -> Void)? = nil) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(MyCoursesPalette.surface).frame(width: 88, height: 88)
                    .overlay(Circle().stroke(MyCoursesPalette.stroke, lineWidth: 1))
                Image(systemName: icon).font(.system(size: 34))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if let ctaTitle, let onCta {
                Button(action: onCta) {
                    HStack(spacing: 8) {
                        if let ctaIcon {
                            Image(systemName: ctaIcon)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(ctaTitle)
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(
                        Capsule().fill(LinearGradient.droobBrand))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    // MARK: Skeletons

    private var rowSkeletons: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 12) {
                    MCSkeletonBlock(height: 44, cornerRadius: 22).frame(width: 44)
                    VStack(alignment: .leading, spacing: 8) {
                        MCSkeletonBlock(height: 13, cornerRadius: 4, width: 140)
                        MCSkeletonBlock(height: 11, cornerRadius: 3, width: 220)
                    }
                    Spacer()
                    MCSkeletonBlock(height: 11, cornerRadius: 3, width: 28)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                Divider().background(MyCoursesPalette.stroke).padding(.horizontal, 20)
            }
        }
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(MyCoursesPalette.stroke, lineWidth: 1))
        .padding(.horizontal, 20).padding(.top, 4)
    }

    // MARK: Filtering helpers

    /// 2026-07: the Rooms surface shows instructor-created rooms only.
    /// A missing `created_by_role` (older backend) is treated as a
    /// student room and hidden. Student-created rooms stay in the
    /// payload but never render.
    private var visibleRooms: [StudyRoomSummary] {
        viewModel.rooms.filter { $0.isInstructorRoom }
    }

    private var runningRooms: [StudyRoomSummary] {
        visibleRooms.filter { $0.status == .active }
    }

    private var endedRooms: [StudyRoomSummary] {
        visibleRooms.filter { $0.status == .closed }
    }

    private var filteredRooms: [StudyRoomSummary] {
        switch roomsFilter {
        case .all:     return visibleRooms
        case .running: return runningRooms
        case .ended:   return endedRooms
        }
    }

    private func markRoomReadLocally(_ roomId: String) {
        if let i = viewModel.rooms.firstIndex(where: { $0.roomId == roomId }),
           viewModel.rooms[i].unreadCount > 0 {
            viewModel.rooms[i] = viewModel.rooms[i].withUnreadCleared()
        }
    }
}

// MARK: - Notifications + StudyRoomSummary helpers

extension Notification.Name {
    /// Posted by the Messages tab's empty-state CTA. `MainTabView` listens
    /// and flips `selectedTab` accordingly.
    static let droobSwitchToTab = Notification.Name("droob.switchToTab")
    /// Posted by `CourseDetailView` when an enrollment request comes back
    /// already APPROVED (the backend auto-approves on create in testing mode),
    /// so the student is enrolled immediately. `MainTabView` listens and lands
    /// the user on the Courses tab's Enrolled segment — distinct from
    /// `droobSwitchToTab`, which forces the Explore segment.
    static let droobOpenEnrolledCourses = Notification.Name("droob.openEnrolledCourses")
    /// Posted by the room chat / settings flow whenever a room mutates
    /// (joined, left, role changed, closed). The Messages tab listens
    /// and refreshes its inbox surface so badges stay accurate.
    static let droobStudyRoomDidChange = Notification.Name("droob.studyRoomDidChange")
    /// Posted when the user exits a study room from inside the chat —
    /// after leaving, or via the "Back to course" button on the
    /// room-ended overlay. `CourseDetailView` (the only entry point that
    /// pushes the rooms flow via an `isActive` NavigationLink chain)
    /// listens and collapses that whole sub-stack in one deterministic
    /// binding flip. Bubbling `dismiss()` up through the nested
    /// `isActive` links is unreliable — the still-`true` parent bindings
    /// re-assert the links and the pop gets dropped, which is why the
    /// "Back to course" button appeared dead after quitting. Collapsing
    /// from the top avoids that race. A no-op for the Messages-tab and
    /// deep-link entry points (no listener), where a plain `dismiss()`
    /// already exits cleanly.
    static let droobExitStudyRooms = Notification.Name("droob.exitStudyRooms")
    /// Posted by the "Log in again" button on the password-reset success
    /// screen. `LoginView` (which roots the forgot-password chain via an
    /// `isActive` NavigationLink: Login → ForgotPassword → VerifyEmail →
    /// ChangePassword) listens and flips `showForgotPassword = false` to
    /// collapse the whole sub-stack back to the sign-in screen. Same
    /// rationale as `droobExitStudyRooms`: bubbling `dismiss()` up through
    /// nested `isActive` links is unreliable, so we collapse from the top.
    static let droobResetPasswordFlowDone = Notification.Name("droob.resetPasswordFlowDone")
}

private extension StudyRoomSummary {
    /// Re-stamps the summary with `unreadCount = 0`. Because the model
    /// is `Decodable`-only (no memberwise init), this re-encodes /
    /// re-decodes a single field — overhead is one tiny JSON round
    /// trip, called only on row tap.
    func withUnreadCleared() -> StudyRoomSummary {
        var copy = MutableSummary(self)
        copy.unread_count = 0
        return copy.toSummary() ?? self
    }
}

/// Mutable JSON-shape mirror of `StudyRoomSummary` used by
/// `withUnreadCleared` to mint a tweaked copy without breaking the
/// existing `Decodable`-only design of the model.
private struct MutableSummary: Codable {
    let room_id: String
    let course_id: String
    let name: String
    let description: String?
    let privacy: String
    let join_code: String?
    let slug: String
    let host_id: String
    let host_name: String
    let participant_count: Int
    let max_participants: Int
    let status: String
    let is_member: Bool
    let last_message_at: Date?
    let created_at: Date
    let member_previews: [MutablePreview]
    var unread_count: Int
    let my_role: String?
    /// 2026-07: must round-trip, or `withUnreadCleared()` would drop
    /// the field and the row would vanish from the instructor-rooms
    /// filter the instant it's tapped.
    let created_by_role: String?

    init(_ s: StudyRoomSummary) {
        self.room_id = s.roomId
        self.course_id = s.courseId
        self.name = s.name
        self.description = s.description
        self.privacy = s.privacy.rawValue
        self.join_code = s.joinCode
        self.slug = s.slug
        self.host_id = s.hostId
        self.host_name = s.hostName
        self.participant_count = s.participantCount
        self.max_participants = s.maxParticipants
        self.status = s.status.rawValue
        self.is_member = s.isMember
        self.last_message_at = s.lastMessageAt
        self.created_at = s.createdAt
        self.member_previews = s.memberPreviews.map { MutablePreview(user_id: $0.userId, initials: $0.initials) }
        self.unread_count = s.unreadCount
        self.my_role = s.myRole?.rawValue
        self.created_by_role = s.createdByRole
    }

    func toSummary() -> StudyRoomSummary? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }
        return try? decoder.decode(StudyRoomSummary.self, from: data)
    }
}

private struct MutablePreview: Codable {
    /// Optional (2026-07): anonymized peers have a null user_id.
    let user_id: String?
    let initials: String
}

// MARK: - Thread row (legacy chats list)

private struct ThreadRow: View {
    let thread: StudentThread

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if thread.unreadCount > 0 {
                // Unread rail: 3pt of gold against the row surface, so it
                // needs the ink ramp to stay visible on the light card.
                Rectangle()
                    .fill(MyCoursesPalette.accent)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            } else {
                Rectangle().fill(Color.clear).frame(width: 3)
            }

            AvatarCircle(initials: thread.instructorInitials, size: 44,
                         avatarUrl: thread.instructorAvatarUrl)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.instructorName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                    Spacer()
                    Text(relativeTime(thread.lastMessageAt))
                        .font(.system(size: 11))
                        .foregroundColor(MyCoursesPalette.muted)
                    if thread.unreadCount > 0 {
                        unreadBadge(thread.unreadCount)
                    }
                }
                Text(thread.lastMessagePreview.isEmpty ? L10n.messagesPreviewEmpty : thread.lastMessagePreview)
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return L10n.messagesNow }
        if diff < 3600 { return L10n.messagesMinutesAgo(diff / 60) }
        if diff < 86400 { return L10n.messagesHoursAgo(diff / 3600) }
        // `.locale(...)` is not optional here: without it `formatted` resolves
        // against the DEVICE, so an English phone printed "Sep 12" on every
        // conversation row of an Arabic-only app.
        return date.formatted(
            .dateTime.month(.abbreviated).day()
                .locale(Locale(identifier: L10n.currentLanguageCode)))
    }
}

@ViewBuilder
private func unreadBadge(_ count: Int) -> some View {
    Text("\(min(count, 99))")
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.droobGold))
}

// MARK: - Room row (study rooms list)

private struct RoomRow: View {
    let room: StudyRoomSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if room.unreadCount > 0 && room.status == .active {
                // Same unread rail as ThreadRow — ink, not fill.
                Rectangle()
                    .fill(MyCoursesPalette.accent)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            } else {
                Rectangle().fill(Color.clear).frame(width: 3)
            }

            // Cover tile — matches the StudyRoomRowCard's gold square.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(room.status == .active
                          ? MyCoursesPalette.accent.opacity(0.14)
                          : MyCoursesPalette.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(room.status == .active
                                    ? MyCoursesPalette.accent.opacity(0.40)
                                    : MyCoursesPalette.stroke,
                                    lineWidth: 1))
                // The tile is a 14% wash, not a gold plate — its glyph is ink.
                Image(systemName: room.status == .active
                      ? "book.pages.fill" : "lock.fill")
                    .foregroundColor(room.status == .active
                                     ? MyCoursesPalette.accent
                                     : MyCoursesPalette.textTertiary)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(room.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(room.status == .active
                                         ? MyCoursesPalette.textPrimary
                                         : MyCoursesPalette.muted)
                        .lineLimit(1)
                    statusPill
                    if room.myRole == .host {
                        rolePill(L10n.messagesHostBadgeShort)
                    } else if room.myRole == .coHost {
                        rolePill(L10n.messagesCoHostBadgeShort)
                    }
                    Spacer()
                    Text(relativeTime(room.lastMessageAt ?? room.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(MyCoursesPalette.muted)
                    if room.unreadCount > 0 && room.status == .active {
                        unreadBadge(room.unreadCount)
                    }
                }
                HStack(spacing: 8) {
                    if !room.memberPreviews.isEmpty {
                        AvatarStack(
                            previews: room.memberPreviews,
                            totalCount: room.participantCount,
                            visibleLimit: 4,
                            avatarSize: 18)
                    }
                    Text(memberCountText)
                        .font(.system(size: 12))
                        .foregroundColor(MyCoursesPalette.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    private var statusPill: some View {
        Group {
            if room.status == .active {
                HStack(spacing: 4) {
                    Circle()
                        .fill(MyCoursesPalette.success)
                        .frame(width: 5, height: 5)
                    Text(L10n.messagesRoomStatusLive)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                        .foregroundColor(MyCoursesPalette.success)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(MyCoursesPalette.success.opacity(0.14)))
            } else {
                Text(L10n.messagesRoomStatusEnded)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(MyCoursesPalette.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(MyCoursesPalette.surfaceRaised))
            }
        }
    }

    @ViewBuilder
    private func rolePill(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundColor(MyCoursesPalette.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(MyCoursesPalette.accent.opacity(0.15)))
    }

    private var memberCountText: String {
        if room.participantCount == 1 {
            return L10n.studyRoomsRoomOneMember
        }
        return String(format: L10n.studyRoomsRoomMembersFmt, room.participantCount)
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return L10n.studyRoomsAgoNow }
        if diff < 3600 {
            return String(format: L10n.studyRoomsAgoMinFmt, diff / 60)
        }
        if diff < 86400 {
            return String(format: L10n.studyRoomsAgoHourFmt, diff / 3600)
        }
        return date.formatted(
            .dateTime.month(.abbreviated).day().locale(Locale(identifier: L10n.currentLanguageCode)))
    }
}

// MARK: - Avatar Circle

struct AvatarCircle: View {
    let initials: String
    let size: CGFloat
    /// Presigned avatar URL. When non-nil/non-blank the image loads over
    /// the gradient-initials disc and replaces it on `.success`; every
    /// other phase (loading, failure) leaves the initials showing.
    /// Defaults to nil so existing initials-only call sites are unchanged.
    var avatarUrl: String? = nil

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.droobGold.opacity(0.9), Color(red: 0.42, green: 0.33, blue: 0.17)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Text(initials)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.03))
            if let url = avatarUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.clear
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
