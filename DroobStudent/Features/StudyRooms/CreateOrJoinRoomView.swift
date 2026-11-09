import SwiftUI

/// Entry point from the "Study Together" card on the course detail
/// screen. Hosts two tabs:
///
/// 1. **Create room** — form (name, description, privacy) → submit →
///    pushes `RoomReadyView` on success.
/// 2. **Join room** — browse public rooms in this course + join by
///    private code → on success jumps straight to
///    `StudyRoomChatView`.
///
/// All actions go through `StudyRoomsAPI`; the enrollment guard is
/// enforced server-side so the screen doesn't need to know.
struct CreateOrJoinRoomView: View {
    let courseId: String
    let courseTitle: String

    @State private var selectedTab: Tab = .create
    @State private var name: String = ""
    @State private var whatStudy: String = ""
    @State private var privacy: StudyRoomPrivacy = .public
    @State private var joinCode: String = ""
    @State private var searchQuery: String = ""
    /// Debounced server-side filter for the public list. Kicked off by
    /// `searchQuery` changes inside an `.onChange` modifier.
    @State private var searchDebounce: Task<Void, Never>? = nil
    /// Holds the name of the room the user is currently joining so the
    /// joining overlay can render context. Cleared on success/cancel.
    @State private var joiningRoomName: String? = nil
    @State private var joinTask: Task<Void, Never>? = nil
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    /// Pre-drafted code displayed in the form for PRIVATE rooms. Fetched
    /// from the server the first time PRIVATE is selected; if the user
    /// flips back to PUBLIC and then PRIVATE again we keep the existing
    /// draft (no second round-trip).
    @State private var draftCode: String? = nil
    @State private var isDraftingCode: Bool = false

    // Navigation to the success screen (after Create) and to the
    // chat screen (after Join). We use two separate destinations
    // because the success screen has its own "Enter the room" CTA.
    @State private var createdRoom: StudyRoomDetail?
    @State private var joinedRoom: StudyRoomDetail?
    @State private var showCreatedReady: Bool = false
    @State private var openJoinedChat: Bool = false
    /// When a PRIVATE join lands on the waitlist, we push the
    /// pending-join screen instead of the chat.
    @State private var pendingForRoom: String? = nil
    @State private var showPendingJoin: Bool = false

    @Environment(\.dismiss) private var dismiss

    enum Tab: Hashable { case create, join }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                tabBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if selectedTab == .create {
                            createBody
                        } else {
                            joinBody
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(MyCoursesPalette.danger)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                if selectedTab == .create {
                    createCta
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
            }

            // Hidden navigation links — push when the respective state flips.
            if let room = createdRoom {
                NavigationLink(isActive: $showCreatedReady) {
                    RoomReadyView(
                        room: room, courseTitle: courseTitle)
                } label: { EmptyView() }.hidden()
            }
            if let room = joinedRoom {
                NavigationLink(isActive: $openJoinedChat) {
                    StudyRoomChatView(
                        roomId: room.roomId,
                        prefetchedRoom: room,
                        courseTitle: courseTitle)
                } label: { EmptyView() }.hidden()
            }
            if let pendingName = pendingForRoom {
                NavigationLink(isActive: $showPendingJoin) {
                    PendingJoinView(
                        roomName: pendingName,
                        courseTitle: courseTitle,
                        onDismiss: {
                            showPendingJoin = false
                            pendingForRoom = nil
                        })
                } label: { EmptyView() }.hidden()
            }
        }
        .navigationTitle(L10n.studyRoomsListTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Joining-the-room overlay sits over the whole screen while a
        // join request is in flight. Cancellable via the link inside.
        .fullScreenCover(isPresented: Binding(
            get: { joiningRoomName != nil },
            set: { if !$0 { joiningRoomName = nil } })) {
            JoiningRoomView(
                roomName: joiningRoomName ?? "",
                courseTitle: courseTitle,
                onCancel: cancelJoin)
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 8) {
            tabPill(label: L10n.studyRoomsCreateTab,
                    icon: "plus",
                    tab: .create)
            tabPill(label: L10n.studyRoomsJoinTab,
                    icon: "arrow.right.to.line",
                    tab: .join)
        }
    }

    @ViewBuilder
    private func tabPill(label: String, icon: String, tab: Tab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = tab
                errorMessage = nil
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                        ? LinearGradient(
                            colors: [Color.droobGold,
                                     Color.droobGold.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing)
                        : LinearGradient(
                            colors: [MyCoursesPalette.surface],
                            startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected
                                ? Color.clear
                                : MyCoursesPalette.stroke,
                                lineWidth: 1))
            )
            .foregroundColor(isSelected ? Color.black : MyCoursesPalette.textPrimary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Create body

    private var createBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            coverIcon
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            field(label: L10n.studyRoomsRoomNameLabel) {
                TextField(L10n.studyRoomsRoomNamePlaceholder,
                          text: $name)
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .font(.system(size: 15))
            }

            field(label: L10n.studyRoomsWhatStudyLabel) {
                TextField(L10n.studyRoomsWhatStudyPlaceholder,
                          text: $whatStudy, axis: .vertical)
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .font(.system(size: 14))
                    .lineLimit(2...4)
            }

            privacySection
        }
    }

    private var coverIcon: some View {
        ZStack {
            // Cover art stays a dark tile in both themes — the gold
            // glyph + gold border need a dark plate to read against;
            // on a cream surface they'd wash out. `coverPlate` is
            // opaque for exactly that reason (see StudyRoomComponents).
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(StudyRoomChrome.coverPlate)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.droobGold.opacity(0.35), lineWidth: 1))
            VStack(spacing: 4) {
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(Color.droobGold)
                Text(L10n.studyRoomsCoverLabel)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2)
                    .foregroundColor(Color.droobGold.opacity(0.7))
            }
        }
        .frame(width: 110, height: 110)
    }

    private func field<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundColor(MyCoursesPalette.muted)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MyCoursesPalette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
                )
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.studyRoomsPrivacyLabel)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundColor(MyCoursesPalette.muted)

            HStack(spacing: 8) {
                privacyPill(.public,
                            label: L10n.studyRoomsPrivacyPublic,
                            icon: "globe")
                privacyPill(.private,
                            label: L10n.studyRoomsPrivacyPrivate,
                            icon: "lock.fill")
            }

            // Helper banner — colour + copy switch on privacy.
            // PUBLIC: green "Anyone in this course can join"
            // PRIVATE: purple "Hidden · passcode required to join"
            privacyHelperBanner

            // ROOM CODE preview, only when PRIVATE.
            if privacy == .private {
                roomCodePreview
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private var privacyHelperBanner: some View {
        let isPublic = privacy == .public
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isPublic ? "globe" : "lock.fill")
                .font(.system(size: 14))
                .foregroundColor(isPublic
                    ? .green.opacity(0.9)
                    : Color(red: 0.78, green: 0.55, blue: 1.0))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                if isPublic {
                    Text(L10n.studyRoomsPrivacyHelpPublic)
                        .font(.system(size: 13))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                } else {
                    Text(L10n.studyRoomsPrivateBannerTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                    Text(L10n.studyRoomsPrivateBannerSubtitle)
                        .font(.system(size: 12))
                        .foregroundColor(MyCoursesPalette.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isPublic
                    ? Color.green.opacity(0.08)
                    : Color(red: 0.45, green: 0.25, blue: 0.55).opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isPublic
                            ? Color.green.opacity(0.30)
                            : Color(red: 0.78, green: 0.55, blue: 1.0)
                                .opacity(0.35), lineWidth: 1))
        )
    }

    @ViewBuilder
    private var roomCodePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.studyRoomsCodeFieldLabel)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundColor(MyCoursesPalette.muted)

            HStack(spacing: 10) {
                if isDraftingCode || draftCode == nil {
                    ProgressView()
                        .tint(MyCoursesPalette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let code = draftCode {
                    Text(JoinCodeFormat.display(code))
                        .font(.system(size: 22, weight: .bold,
                                      design: .monospaced))
                        .foregroundColor(MyCoursesPalette.accent)
                        .tracking(2)
                    Spacer()
                    Button {
                        UIPasteboard.general.string =
                            JoinCodeFormat.display(code)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                            Text(L10n.studyRoomsInviteCopy)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(MyCoursesPalette.surface)
                                .overlay(Capsule().stroke(
                                    MyCoursesPalette.stroke,
                                    lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MyCoursesPalette.stroke,
                                    lineWidth: 1))
            )

            Text(L10n.studyRoomsCodeFieldHelper)
                .font(.system(size: 12))
                .foregroundColor(MyCoursesPalette.muted)
        }
    }

    /// Lazily fetch the draft code the first time PRIVATE is picked.
    private func ensureDraftCode() async {
        guard draftCode == nil, !isDraftingCode else { return }
        isDraftingCode = true
        defer { isDraftingCode = false }
        do {
            draftCode = try await StudyRoomsAPI.draftJoinCode(courseId: courseId)
        } catch {
            // Non-fatal — the create call will mint one server-side if
            // the form doesn't supply a preferred code. We surface the
            // problem to the user via the form's error label.
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func privacyPill(_ p: StudyRoomPrivacy,
                             label: String,
                             icon: String) -> some View {
        let isSelected = privacy == p
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { privacy = p }
            // Lazy draft-code fetch — only when PRIVATE becomes the
            // selected option and we don't already have one in hand.
            if p == .private {
                Task { await ensureDraftCode() }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                        ? LinearGradient(
                            colors: [Color.droobGold,
                                     Color.droobGold.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing)
                        : LinearGradient(
                            colors: [MyCoursesPalette.surface],
                            startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected
                                ? Color.clear
                                : MyCoursesPalette.stroke,
                                lineWidth: 1))
            )
            .foregroundColor(isSelected ? Color.black : MyCoursesPalette.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private var createCta: some View {
        Button {
            Task { await submitCreate() }
        } label: {
            HStack(spacing: 10) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(L10n.studyRoomsCreateButton)
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.droobGold,
                                 Color.droobGold.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
            )
            .foregroundColor(.black)
            .opacity((isSubmitting || !canSubmitCreate) ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting || !canSubmitCreate)
    }

    private var canSubmitCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitCreate() async {
        guard canSubmitCreate else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            // For PRIVATE rooms, pass the form's drafted code so the
            // user gets the same code they saw above (server only
            // regenerates on the very unlikely collision race).
            let preferred = privacy == .private ? draftCode : nil
            let room = try await StudyRoomsAPI.create(
                courseId: courseId,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: whatStudy.trimmingCharacters(
                    in: .whitespacesAndNewlines).nilIfEmpty,
                privacy: privacy,
                preferredJoinCode: preferred)
            createdRoom = room
            showCreatedReady = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Join body

    private var joinBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Search bar — server-side filter on name/description.
            searchField

            // 6-box code entry — primary path for private invites.
            VStack(spacing: 10) {
                Text(L10n.studyRoomsEnterCodeTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .frame(maxWidth: .infinity)
                JoinCodeInput(code: $joinCode,
                              onComplete: { _ in
                                  Task { await submitJoinByCode() }
                              })
            }
            .padding(.vertical, 6)

            // Section divider with "OR JOIN A PUBLIC ROOM" header.
            HStack(spacing: 12) {
                Rectangle().fill(MyCoursesPalette.stroke).frame(height: 1)
                Text(L10n.studyRoomsOrJoinPublic)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(MyCoursesPalette.muted)
                    .layoutPriority(1)
                Rectangle().fill(MyCoursesPalette.stroke).frame(height: 1)
            }

            PublicRoomsInlineList(
                courseId: courseId,
                searchQuery: searchQuery,
                onJoin: { room in startJoinPublic(room: room) },
                onCreateInstead: { query in
                    name = query
                    searchQuery = ""
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = .create
                    }
                })
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(MyCoursesPalette.muted)
            TextField("", text: $searchQuery, prompt:
                Text(L10n.studyRoomsSearchPlaceholder)
                    .foregroundColor(MyCoursesPalette.textTertiary))
                .foregroundColor(MyCoursesPalette.textPrimary)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(MyCoursesPalette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MyCoursesPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
        )
    }

    // MARK: - Cancellable join

    private func submitJoinByCode() async {
        // Read the raw 6-char form back out of the code-input binding.
        let raw = JoinCodeFormat.strip(joinCode)
        guard raw.count == 6 else { return }
        startJoinResult(name: L10n.studyRoomsListTitle) {
            try await StudyRoomsAPI.joinByCode(raw)
        }
    }

    private func startJoinPublic(room: StudyRoomSummary) {
        // PUBLIC rooms never go through the waitlist — straight chat.
        joinTask?.cancel()
        joiningRoomName = room.name
        errorMessage = nil
        joinTask = Task {
            do {
                let detail = try await StudyRoomsAPI.joinPublic(roomId: room.roomId)
                if Task.isCancelled { return }
                joinedRoom = detail
                joiningRoomName = nil
                openJoinedChat = true
            } catch is CancellationError {
                joiningRoomName = nil
            } catch {
                joiningRoomName = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Cancellable join path that handles the JOINED / PENDING split
    /// from {@link RoomJoinResult}. Used by code + slug entry — PUBLIC
    /// rooms lands on JOINED → chat; PRIVATE on PENDING → pending screen.
    private func startJoinResult(
            name: String,
            call: @escaping () async throws -> RoomJoinResult) {
        joinTask?.cancel()
        joiningRoomName = name
        errorMessage = nil
        joinTask = Task {
            do {
                let result = try await call()
                if Task.isCancelled { return }
                joiningRoomName = nil
                if result.status == "JOINED", let detail = result.room {
                    joinedRoom = detail
                    openJoinedChat = true
                } else if result.status == "PENDING", let wait = result.waitlist {
                    pendingForRoom = name
                    showPendingJoin = true
                    _ = wait  // not used in v1; future: show wait time
                }
            } catch is CancellationError {
                joiningRoomName = nil
            } catch {
                joiningRoomName = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelJoin() {
        joinTask?.cancel()
        joinTask = nil
        joiningRoomName = nil
    }
}

// MARK: - Public rooms list (Join tab)

/// Inline public-rooms list used inside the Join tab. Doesn't depend
/// on `StudyRoomsListView` so we don't fight the surrounding scroll
/// view's gestures. Driven by an external `searchQuery` so the parent
/// owns the search field; the list debounces and re-fetches on change.
private struct PublicRoomsInlineList: View {
    let courseId: String
    let searchQuery: String
    let onJoin: (StudyRoomSummary) -> Void
    /// Called when the user taps "Create '{query}' instead" on the
    /// no-match empty state. Parent switches to the Create tab and
    /// pre-fills the name field.
    let onCreateInstead: (String) -> Void

    @StateObject private var viewModel: StudyRoomsListViewModel
    @State private var debounce: Task<Void, Never>? = nil

    init(courseId: String, searchQuery: String,
         onJoin: @escaping (StudyRoomSummary) -> Void,
         onCreateInstead: @escaping (String) -> Void) {
        self.courseId = courseId
        self.searchQuery = searchQuery
        self.onJoin = onJoin
        self.onCreateInstead = onCreateInstead
        _viewModel = StateObject(
            wrappedValue: StudyRoomsListViewModel(courseId: courseId))
    }

    var body: some View {
        VStack(spacing: 10) {
            if !viewModel.rooms.isEmpty {
                header
            }

            if viewModel.isLoading && viewModel.rooms.isEmpty {
                HStack { ProgressView().tint(MyCoursesPalette.accent); Spacer() }
                    .padding(.vertical, 12)
            } else if viewModel.rooms.isEmpty {
                emptyState
            } else {
                ForEach(viewModel.rooms) { room in
                    StudyRoomRowCard(
                        room: room,
                        onTap: { onJoin(room) },
                        onJoin: { onJoin(room) })
                }
            }
        }
        .task { await viewModel.load() }
        .onChange(of: searchQuery) { newValue in
            debounce?.cancel()
            debounce = Task {
                try? await Task.sleep(nanoseconds: 350_000_000) // 350ms
                if Task.isCancelled { return }
                await viewModel.load(query: newValue)
            }
        }
    }

    /// "3 rooms · React Mastery" — small caption above the list.
    @ViewBuilder
    private var header: some View {
        let count = viewModel.rooms.count
        Text(count == 1
             ? String(format: L10n.studyRoomsRoomsHeaderOne, courseTitleFallback)
             : String(format: L10n.studyRoomsRoomsHeaderFmt, count, courseTitleFallback))
            .font(.system(size: 12))
            .foregroundColor(MyCoursesPalette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Falls back to "Course" when we don't have a title context — the
    /// list view doesn't currently receive courseTitle. (Parent could
    /// supply this through init if we ever want it; for now the figma's
    /// "React Mastery" label is decorative.)
    private var courseTitleFallback: String {
        "Course"
    }

    /// Differentiates between "course has no rooms yet" and "search
    /// returned nothing". The latter offers a quick path to create a
    /// room named after the search query.
    @ViewBuilder
    private var emptyState: some View {
        let q = viewModel.lastQuery
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.droobGold.opacity(0.10))
                    .frame(width: 80, height: 80)
                Image(systemName: q.isEmpty
                      ? "person.3"
                      : "minus.magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundColor(MyCoursesPalette.accent)
            }
            Text(q.isEmpty
                 ? L10n.studyRoomsNoRoomsTitle
                 : L10n.studyRoomsNoMatchTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)
            if q.isEmpty {
                Text(L10n.studyRoomsNoRoomsSubtitle)
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Text(String(format: L10n.studyRoomsNoMatchSubtitleFmt, q))
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button { onCreateInstead(q) } label: {
                    HStack {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text(String(format: L10n.studyRoomsCreateInsteadFmt, q))
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.textTertiary)
                    }
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(MyCoursesPalette.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(MyCoursesPalette.accent.opacity(0.35),
                                            lineWidth: 1)))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Small helpers

private extension String {
    /// Nil if blank, otherwise self. Lets `description` round-trip
    /// cleanly to a nullable JSON field.
    var nilIfEmpty: String? {
        let t = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
