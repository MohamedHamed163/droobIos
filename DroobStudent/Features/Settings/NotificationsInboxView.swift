import SwiftUI

/// Bell-icon inbox of in-app notifications. Renders category tabs, a
/// gradient highlight on unread rows (which fades once read), swipe-to-delete,
/// and inline action buttons for actionable kinds (security alerts, live
/// sessions). New rows arrive in realtime over STOMP.
struct NotificationsInboxView: View {
    @StateObject private var vm = NotificationsInboxViewModel()
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.openURL) private var openURL
    @AppStorage("appLocale") private var locale: String = AppLocaleDefault.code
    /// Announcement tapped open in a detail sheet (title + full body).
    @State private var presentedAnnouncement: StudentNotification?

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                SettingsScreenHeader(title: L10n.inboxTitle)
                    .padding(.top, 4)
                    .padding(.horizontal, 20)

                tabStrip

                if vm.unreadCount > 0 || !vm.notifications.isEmpty {
                    actionRow.padding(.horizontal, 20)
                }

                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await vm.load()
            vm.startRealtime()
        }
        .onDisappear { vm.stopRealtime() }
        .sheet(item: $presentedAnnouncement) { AnnouncementDetailSheet(notification: $0) }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.notifications.isEmpty {
            skeleton.padding(.horizontal, 20)
            Spacer()
        } else if let err = vm.error, vm.notifications.isEmpty {
            ErrorBanner(message: err) { Task { await vm.load() } }
                .padding(.horizontal, 20)
            Spacer()
        } else if vm.visible.isEmpty {
            emptyState
            Spacer()
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(vm.visible) { n in
                NotificationCard(
                    notification: n,
                    onTap: { handleTap(n) },
                    onAction: { action in handleAction(action, on: n) })
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { vm.delete(id: n.id) } label: {
                            Label(L10n.inboxDelete, systemImage: "trash")
                        }
                    }
                    .onAppear {
                        if n.id == vm.visible.last?.id { Task { await vm.loadMore() } }
                    }
            }

            if vm.isLoadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await vm.load() }
    }

    // MARK: - Tabs

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotificationCategoryUI.allCases) { tab in
                    let isSel = vm.selectedTab == tab
                    Button {
                        if vm.selectedTab != tab { vm.selectedTab = tab }
                    } label: {
                        HStack(spacing: 6) {
                            Text(tab.label)
                                .font(.system(size: 13, weight: .semibold))
                            if tab == .unread && vm.unreadCount > 0 {
                                Text("\(vm.unreadCount)")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(isSel ? Color.black.opacity(0.18) : Color.droobGold.opacity(0.22)))
                            }
                        }
                        .foregroundColor(isSel ? Color.black : MyCoursesPalette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            Capsule().fill(isSel ? Color.droobGold : MyCoursesPalette.surface))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var actionRow: some View {
        HStack {
            if !vm.notifications.isEmpty {
                Button(action: vm.clearAll) {
                    Text(L10n.inboxClearAll)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.danger)
                }
            }
            Spacer()
            if vm.unreadCount > 0 {
                Button(action: vm.markAllRead) {
                    Text(L10n.inboxMarkAllRead)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.accent)
                }
            }
        }
    }

    // MARK: - Empty / skeleton

    private var emptyState: some View {
        let filtered = vm.selectedTab != .all && !vm.notifications.isEmpty
        return VStack(spacing: 20) {
            InboxEmptyIllustration(showCheck: !filtered)
            VStack(spacing: 8) {
                Text(filtered ? L10n.inboxFilterEmptyTitle : L10n.inboxCaughtUpTitle)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .multilineTextAlignment(.center)
                if !filtered {
                    Text(L10n.inboxCaughtUpSubtitle)
                        .font(.system(size: 14))
                        .foregroundColor(MyCoursesPalette.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 40)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
        .padding(.bottom, 40)
    }

    private var skeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { _ in
                MCSkeletonBlock(height: 76, cornerRadius: 16)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Interactions

    private func handleTap(_ n: StudentNotification) {
        vm.markRead(id: n.id)
        let ui = NotificationKindUI.from(n.type)
        // Announcements carry their full copy in the payload — open it in a
        // detail sheet rather than deep-linking away.
        if case .announcement = ui {
            presentedAnnouncement = n
            return
        }
        if let link = ui.deepLink(n.payload), link.scheme == "droob", link.host == "courses",
           let courseId = link.pathComponents.dropFirst().first {
            authSession.pendingDeepLinkCourseId = courseId
        }
    }

    private func handleAction(_ action: InboxAction, on n: StudentNotification) {
        Task {
            let result = await vm.perform(action, on: n.id)
            if action.kind == .joinSession,
               case .string(let urlStr)? = result?["join_url"] {
                let normalized = urlStr.contains("://") ? urlStr : "https://\(urlStr)"
                if let url = URL(string: normalized) { openURL(url) }
            }
        }
    }
}

// MARK: - Empty-state illustration

/// Notifications empty-state illustration (Figma 2555-18842): a gold-tinted
/// rounded square holding a bell, with a spring-green "all clear" check badge
/// straddling the bottom-trailing corner. The badge is hidden for the
/// filtered-but-empty variant, which reuses the tile on its own.
private struct InboxEmptyIllustration: View {
    var showCheck: Bool

    // Spring-green badge gradient + glow (Figma #34C759 → #22A745, glow #30D158).
    private static let checkTop    = Color(red: 0.204, green: 0.780, blue: 0.349)
    private static let checkBottom = Color(red: 0.133, green: 0.655, blue: 0.271)
    private static let checkGlow   = Color(red: 0.188, green: 0.820, blue: 0.345)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Tile, border and bell all take the ink ramp: the tile is only a
            // 16%→2% wash on the page, so the bell is never sitting on gold.
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [MyCoursesPalette.accent.opacity(0.16),
                                 MyCoursesPalette.accent.opacity(0.02)],
                        center: .center, startRadius: 0, endRadius: 78))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(MyCoursesPalette.accent.opacity(0.30), lineWidth: 1))
                .frame(width: 108, height: 108)
                .overlay(
                    Image(systemName: "bell")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundColor(MyCoursesPalette.accent))

            if showCheck {
                ZStack {
                    Circle().fill(
                        LinearGradient(colors: [Self.checkTop, Self.checkBottom],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(MyCoursesPalette.background, lineWidth: 3))
                .shadow(color: Self.checkGlow.opacity(0.3), radius: 6, x: 0, y: 5)
                .offset(x: 6, y: 6)
            }
        }
    }
}

// MARK: - Row

private struct NotificationCard: View {
    let notification: StudentNotification
    let onTap: () -> Void
    let onAction: (InboxAction) -> Void

    private var ui: NotificationKindUI { NotificationKindUI.from(notification.type) }

    /// Card headline. Announcements carry an admin-authored title in the
    /// payload; show it so each one is distinguishable instead of all reading
    /// "Announcement". Every other kind uses its localized static title.
    private var displayTitle: String {
        if case .announcement = ui,
           let t = notification.payload.string("title"), !t.isEmpty {
            return t
        }
        return ui.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(iconBg)
                        Image(systemName: ui.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(iconTint)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(displayTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(MyCoursesPalette.textPrimary)
                            Spacer(minLength: 4)
                            Text(notification.createdAt, style: .relative)
                                .font(.system(size: 11))
                                .foregroundColor(MyCoursesPalette.muted)
                        }
                        if let preview = subtitle {
                            Text(preview)
                                .font(.system(size: 12))
                                .foregroundColor(MyCoursesPalette.muted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    if notification.isUnread {
                        // Unread dot reads against the card, so: ink.
                        Circle().fill(MyCoursesPalette.accent)
                            .frame(width: 8, height: 8).padding(.top, 6)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !ui.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(ui.actions) { action in
                        Button { onAction(action) } label: { actionLabel(action) }
                            .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 50)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(notification.isUnread ? MyCoursesPalette.accent.opacity(0.35) : MyCoursesPalette.stroke,
                              lineWidth: 1))
    }

    // MARK: Inline-action button (Figma 2529-16404)

    /// Prominent actions (Join / Secure) use a left-aligned gold gradient pill
    /// with a soft drop-shadow; the join variant leads with a play glyph.
    /// Non-prominent actions (Dismiss) use a flat raised surface.
    @ViewBuilder
    private func actionLabel(_ action: InboxAction) -> some View {
        HStack(spacing: 6) {
            if action.kind == .joinSession {
                Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
            }
            Text(action.label)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .foregroundColor(action.isProminent ? Self.actionInk : MyCoursesPalette.textPrimary)
        .background(actionBackground(action))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: action.isProminent ? Self.actionGoldStart.opacity(0.3) : .clear,
                radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private func actionBackground(_ action: InboxAction) -> some View {
        if action.isProminent {
            LinearGradient(colors: [Self.actionGoldStart, Self.actionGoldEnd],
                           startPoint: .leading, endPoint: .trailing)
        } else {
            MyCoursesPalette.surfaceRaised
        }
    }

    /// Figma palette: #c6a96b → #605234 gradient, #1a1305 ink.
    private static let actionGoldStart = Color(red: 0.776, green: 0.663, blue: 0.420)
    private static let actionGoldEnd   = Color(red: 0.376, green: 0.322, blue: 0.204)
    private static let actionInk       = Color(red: 0.102, green: 0.075, blue: 0.020)

    /// Unread rows get a soft gold gradient that disappears once read.
    /// The gradient is laid *over* `surface` rather than straight onto the
    /// page: alone, a 22%→6% gold wash composited against the light page to
    /// something paler than a read card, so unread rows lost their card
    /// shape and read as less prominent than the rows they outrank.
    @ViewBuilder
    private var cardBackground: some View {
        if notification.isUnread {
            ZStack {
                MyCoursesPalette.surface
                LinearGradient(
                    colors: [Color.droobGold.opacity(0.22), Color.droobGold.opacity(0.06)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        } else {
            MyCoursesPalette.surface
        }
    }

    private var iconBg: Color {
        switch ui.accent {
        case .gold:    return MyCoursesPalette.accent.opacity(0.18)
        case .success: return MyCoursesPalette.success.opacity(0.18)
        case .danger:  return MyCoursesPalette.danger.opacity(0.18)
        case .info:    return Color(red: 0.30, green: 0.55, blue: 0.90).opacity(0.18)
        }
    }

    private var iconTint: Color {
        switch ui.accent {
        // Glyph on an 18% wash — ink, not fill.
        case .gold:    return MyCoursesPalette.accent
        case .success: return MyCoursesPalette.success
        case .danger:  return MyCoursesPalette.danger
        case .info:    return Color(red: 0.40, green: 0.62, blue: 0.95)
        }
    }

    /// One-line preview built from the payload, tailored to the kind.
    private var subtitle: String? {
        let p = notification.payload
        // `title_ar` was never read anywhere in this file — every branch below
        // took `title_en` — so notification previews were structurally English
        // whatever the app locale said. Read both, prefer the app's language,
        // fall back to the other rather than showing nothing.
        let pushTitle = L10n.localized(
            L10n.currentLanguageCode,
            ar: p.string("title_ar"),
            en: p.string("title_en"))
        switch ui {
        case .newMessage, .instructorReply, .qaAnswer:
            let who = p.string("instructor_name") ?? L10n.notifInstructor
            let snippet = p.string("preview") ?? ""
            return snippet.isEmpty ? who : bidiJoin(who, snippet, separator: ": ")
        case .announcement:
            return p.string("body") ?? p.string("preview")
        case .quizResult:
            guard let pct = p.int("score_pct") else { return nil }
            return L10n.notifScore(pct)
        case .newQuiz:
            return pushTitle ?? L10n.notifNewQuiz
        case .liveSessionReminder:
            let title = pushTitle ?? L10n.notifInboxLiveSession
            let tag = p.string("reminder_tag") ?? ""
            if tag == "15m" { return L10n.notifStartsInMinutes(title.bidiIsolated, 15) }
            if tag == "5m"  { return L10n.notifStartsInMinutes(title.bidiIsolated, 5) }
            return title
        case .sessionStartingNow:
            return pushTitle ?? L10n.notifSessionLive
        case .sessionScheduled, .sessionRescheduled, .sessionCancelled:
            return pushTitle ?? p.string("instructor_name")
        case .newCourseAlert, .promotionOffer, .enrollmentApproved, .newLesson,
             .courseUpdated, .revisionFile, .revisionUpdated:
            return pushTitle ?? p.string("course_title")
        case .lessonReminder:
            if let count = p.int("in_progress_count"), count > 1 {
                return L10n.notifCoursesInProgress(count)
            }
            return p.string("course_title") ?? L10n.notifPickUpWhereLeft
        case .streakAlert:
            if let days = p.int("streak_days") { return L10n.notifKeepStreakDays(days) }
            return L10n.notifKeepStreak
        case .studyRoomMessage, .studyRoomJoined, .studyRoomEnded,
             .studyRoomWaitlistRequest, .studyRoomWaitlistApproved,
             .studyRoomWaitlistRejected, .studyRoomRemoved, .studyRoomPromoted,
             .studyRoomBecameHost:
            return p.string("room_name") ?? p.string("actor_name")
        case .unknown:
            return nil
        }
    }
}

// MARK: - Announcement detail

/// Tapping an announcement row opens this sheet, which renders the admin's
/// full title + body and attributes the broadcast to the platform (never an
/// instructor). Read-only — there are no actions on an announcement.
private struct AnnouncementDetailSheet: View {
    let notification: StudentNotification
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        let t = notification.payload.string("title")
        return (t?.isEmpty == false ? t : nil) ?? L10n.inboxKindAnnouncementTitle
    }

    private var bodyText: String? {
        let b = notification.payload.string("body") ?? notification.payload.string("preview")
        return (b?.isEmpty == false) ? b : nil
    }

    private var sender: String {
        notification.payload.string("sender_name") ?? "Droob"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(MyCoursesPalette.accent.opacity(0.18))
                                Image(systemName: "megaphone.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(MyCoursesPalette.accent)
                            }
                            .frame(width: 48, height: 48)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(String(format: L10n.inboxAnnouncementFromFmt, sender))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(MyCoursesPalette.accent)
                                Text(notification.createdAt, style: .relative)
                                    .font(.system(size: 11))
                                    .foregroundColor(MyCoursesPalette.muted)
                            }
                            Spacer(minLength: 0)
                        }

                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(MyCoursesPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let bodyText {
                            Text(bodyText)
                                .font(.system(size: 15))
                                .foregroundColor(MyCoursesPalette.textPrimary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle(L10n.inboxKindAnnouncementTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Toolbar sits on the sheet's own (light) chrome.
                    Button(L10n.done) { dismiss() }
                        .foregroundColor(MyCoursesPalette.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
