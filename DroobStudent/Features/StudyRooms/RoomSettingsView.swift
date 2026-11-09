import SwiftUI
import Combine

/// Room settings sheet shown from the chat header's gear button.
///
/// Single view shared by all roles — admin-only sections (View Waitlist,
/// Invite, Name / Description editing) appear only when
/// `myRole.isAdmin == true`. Tapping Done dismisses back to the chat;
/// the row navigations push deeper for All Members, Waitlist,
/// Documents.
///
/// Live state: the view holds its own `room` copy seeded by the chat
/// view-model. Edits to name/description PATCH the server then update
/// the local copy on success.
struct RoomSettingsView: View {
    @State var room: StudyRoomDetail
    /// Pre-fetched from the chat view-model's bootstrap. We re-fetch on
    /// task to pick up role changes (e.g. just promoted to co-host).
    @State private var isLoadingWaitlistCount = false
    @State private var waitlistCount: Int = 0
    @State private var documentsCount: Int = 0
    @State private var showAllMembers: Bool = false
    @State private var showWaitlist: Bool = false
    @State private var showDocuments: Bool = false
    @State private var showInvite: Bool = false
    @State private var showEditName: Bool = false
    @State private var showEditDescription: Bool = false
    @State private var errorMessage: String?
    /// Drives the leave-room sub-flow (chooser → confirm or pass-host
    /// picker → confirm). Lazily created on Leave tap.
    @StateObject private var leaveCoordinatorBox = LeaveCoordinatorBox()
    @Environment(\.dismiss) private var dismiss

    /// Called on Leave success — the parent (chat view) pops the chat
    /// stack so the user doesn't sit on a stale screen.
    var onLeft: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        header
                            .padding(.top, 12)
                            .padding(.bottom, 24)

                        membersSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)

                        if isAdmin {
                            generalSection
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                        }

                        sharedContentSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)

                        // Only an active member of a live room can leave.
                        // A closed room (ended) or a viewer who already
                        // left / was removed both get the action rejected
                        // server-side ("you're not a member"), so hide it
                        // instead of offering a tap that's guaranteed to
                        // fail.
                        if canLeave {
                            leaveButton
                                .padding(.horizontal, 20)
                                .padding(.bottom, 40)
                        }
                    }
                }
                if let msg = errorMessage {
                    VStack { Spacer()
                        Text(msg)
                            .font(.system(size: 12))
                            .foregroundColor(MyCoursesPalette.danger)
                            .padding(.bottom, 100)
                    }
                }

                // Hidden navigation links
                NavigationLink(isActive: $showAllMembers) {
                    AllMembersView(roomId: room.roomId,
                                   canManage: isAdmin,
                                   onChange: { Task { await reloadRoom() } })
                } label: { EmptyView() }.hidden()
                NavigationLink(isActive: $showWaitlist) {
                    WaitlistView(roomId: room.roomId,
                                 onChange: { Task { await reloadWaitlist() } })
                } label: { EmptyView() }.hidden()
                NavigationLink(isActive: $showDocuments) {
                    DocumentsView(roomId: room.roomId, isRoomClosed: isClosed)
                } label: { EmptyView() }.hidden()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(MyCoursesPalette.accent)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(L10n.studyRoomsSettingsTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.studyRoomsDone) { dismiss() }
                        .foregroundColor(MyCoursesPalette.accent)
                }
            }
            .sheet(isPresented: $showInvite) {
                inviteSheetContent
            }
            .sheet(isPresented: $showEditName) {
                EditFieldSheet(
                    label: L10n.studyRoomsRoomNameLabel,
                    initial: room.name,
                    placeholder: L10n.studyRoomsRoomNamePlaceholder,
                    onSave: { newValue in await save(name: newValue) })
            }
            .sheet(isPresented: $showEditDescription) {
                EditFieldSheet(
                    label: L10n.studyRoomsWhatStudyLabel,
                    initial: room.description ?? "",
                    placeholder: L10n.studyRoomsWhatStudyPlaceholder,
                    multiline: true,
                    onSave: { newValue in await save(description: newValue) })
            }
            // Leave-room flow — chooser (host w/ others) → confirm or
            // pass-host picker → confirm. Each layer is a separate
            // .sheet bound to the coordinator's stage.
            .sheet(isPresented: Binding(
                get: { leaveCoordinatorBox.coordinator?.stage == .choose },
                set: { if !$0 { leaveCoordinatorBox.coordinator?.cancel() } })) {
                if let c = leaveCoordinatorBox.coordinator {
                    leaveChooseSheetContent(c)
                }
            }
            .sheet(isPresented: Binding(
                get: { leaveCoordinatorBox.coordinator?.stage == .confirm },
                set: { if !$0 { leaveCoordinatorBox.coordinator?.cancel() } })) {
                if let c = leaveCoordinatorBox.coordinator {
                    leaveConfirmSheetContent(c)
                }
            }
            .sheet(isPresented: Binding(
                get: { leaveCoordinatorBox.coordinator?.stage == .pickHost },
                set: { if !$0 { leaveCoordinatorBox.coordinator?.cancel() } })) {
                if let c = leaveCoordinatorBox.coordinator {
                    PassHostPickerView(coordinator: c)
                }
            }
            // "You're the last one here" — only path when the viewer
            // is alone in the room. Leaving closes the room.
            .sheet(isPresented: Binding(
                get: { leaveCoordinatorBox.coordinator?.stage == .lastOne },
                set: { if !$0 { leaveCoordinatorBox.coordinator?.cancel() } })) {
                if let c = leaveCoordinatorBox.coordinator {
                    lastOneHereSheetContent(c)
                }
            }
            .task { await reloadAll() }
        }
    }

    // Detent-tuned wrappers — kept here so the iOS 16.0 vs 16.4
    // `presentationBackground` branch lives in one place.
    @ViewBuilder
    private func leaveChooseSheetContent(_ c: LeaveRoomCoordinator) -> some View {
        if #available(iOS 16.4, *) {
            LeaveRoomChooseSheet(coordinator: c)
                .presentationDetents([.fraction(0.45)])
                .presentationDragIndicator(.visible)
                .presentationBackground(MyCoursesPalette.background)
        } else {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                LeaveRoomChooseSheet(coordinator: c)
            }
            .presentationDetents([.fraction(0.45)])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func leaveConfirmSheetContent(_ c: LeaveRoomCoordinator) -> some View {
        if #available(iOS 16.4, *) {
            LeaveRoomConfirmSheet(coordinator: c)
                .presentationDetents([.fraction(0.40)])
                .presentationDragIndicator(.visible)
                .presentationBackground(MyCoursesPalette.background)
        } else {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                LeaveRoomConfirmSheet(coordinator: c)
            }
            .presentationDetents([.fraction(0.40)])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func lastOneHereSheetContent(_ c: LeaveRoomCoordinator) -> some View {
        if #available(iOS 16.4, *) {
            LastOneHereSheet(coordinator: c)
                .presentationDetents([.fraction(0.55)])
                .presentationDragIndicator(.visible)
                .presentationBackground(MyCoursesPalette.background)
        } else {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                LastOneHereSheet(coordinator: c)
            }
            .presentationDetents([.fraction(0.55)])
            .presentationDragIndicator(.visible)
        }
    }

    /// Hidden for instructor rooms (2026-07): the instructor owns the
    /// room, so the student-facing admin affordances (name/description
    /// edit, waitlist, invite, member management) are suppressed even
    /// if the server were to hand the viewer an admin role. Leaving
    /// stays allowed.
    private var isInstructorRoom: Bool { room.isInstructorRoom }
    private var isAdmin: Bool { room.myRole?.isAdmin == true && !isInstructorRoom }
    // Old gate (pre-2026-07): private var isAdmin: Bool { room.myRole?.isAdmin == true }
    private var isHost: Bool { room.myRole == .host }
    /// A CLOSED room is terminal and read-only — leaving and uploading
    /// are both rejected server-side, so their controls are hidden.
    private var isClosed: Bool { room.status == .closed }
    /// Only an active member of an ACTIVE room can leave. Ex-members keep
    /// read-only access to the room (chat history, documents) but the
    /// backend rejects a second `leave`, so the action must not be offered.
    /// `reloadRoom()` refreshes `isMember` on `.task`, so a viewer who left
    /// in a prior session sees the updated state on re-open.
    private var canLeave: Bool { room.isMember && !isClosed }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                // Dark cover plate in both themes — see `coverIcon` in
                // CreateOrJoinRoomView: the gold glyph needs it. The
                // plate is opaque; an alpha black would composite to
                // mid-grey over the light-mode page.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(StudyRoomChrome.coverPlate)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.droobGold.opacity(0.40),
                                    lineWidth: 1))
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.droobGold)
            }
            .frame(width: 80, height: 80)

            Text(room.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)
                .multilineTextAlignment(.center)
            Text(subtitleText)
                .font(.system(size: 13))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var subtitleText: String {
        // Course title is currently not surfaced through the chat
        // view; we still want "created by you/X" so omit the course
        // segment if absent. Future: thread courseTitle through.
        if isHost {
            return L10n.studyRoomsSubtitleCreatedYou
        }
        return String(format: L10n.studyRoomsSubtitleCreatedByFmt,
                      room.hostName)
    }

    // MARK: - Sections

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(bidiJoin(L10n.studyRoomsMembersSection,
                                  "\(room.participantCount)"))
            VStack(spacing: 0) {
                row(icon: nil, content: AnyView(
                    HStack(spacing: 10) {
                        AvatarStack(
                            previews: members(prefix: 3),
                            totalCount: room.participantCount,
                            visibleLimit: 3,
                            avatarSize: 26)
                        Text(L10n.studyRoomsViewAllMembers)
                            .font(.system(size: 15))
                            .foregroundColor(MyCoursesPalette.textPrimary)
                        Spacer()
                        chevron
                    })) {
                    showAllMembers = true
                }
                if isAdmin {
                    Divider().background(MyCoursesPalette.stroke)
                    row(icon: nil, content: AnyView(
                        HStack(spacing: 10) {
                            AvatarStack(
                                previews: [],
                                totalCount: waitlistCount,
                                visibleLimit: 3,
                                avatarSize: 26)
                            Text(L10n.studyRoomsViewWaitlist)
                                .font(.system(size: 15))
                                .foregroundColor(MyCoursesPalette.textPrimary)
                            Spacer()
                            if waitlistCount > 0 {
                                Text("\(waitlistCount)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.droobGold))
                            }
                            chevron
                        })) {
                        showWaitlist = true
                    }
                    Divider().background(MyCoursesPalette.stroke)
                    row(icon: "person.crop.circle.badge.plus",
                        content: AnyView(
                        HStack {
                            Text(L10n.studyRoomsInviteToRoom)
                                .font(.system(size: 15))
                                .foregroundColor(MyCoursesPalette.textPrimary)
                            Spacer()
                        })) {
                        showInvite = true
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            )
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(L10n.studyRoomsGeneralSection)
            VStack(spacing: 0) {
                row(icon: nil, content: AnyView(
                    HStack {
                        Text(L10n.studyRoomsRoomNameLabel.capitalized)
                            .font(.system(size: 15))
                            .foregroundColor(MyCoursesPalette.textPrimary)
                        Spacer()
                        Text(room.name)
                            .font(.system(size: 13))
                            .foregroundColor(MyCoursesPalette.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        chevron
                    })) {
                    showEditName = true
                }
                Divider().background(MyCoursesPalette.stroke)
                row(icon: nil, content: AnyView(
                    HStack {
                        Text(L10n.studyRoomsWhatStudyLabel.capitalized)
                            .font(.system(size: 15))
                            .foregroundColor(MyCoursesPalette.textPrimary)
                        Spacer()
                        chevron
                    })) {
                    showEditDescription = true
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            )
        }
    }

    private var sharedContentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(L10n.studyRoomsSharedContent)
            row(icon: "doc.fill",
                content: AnyView(
                HStack {
                    Text(L10n.studyRoomsDocumentsAndFiles)
                        .font(.system(size: 15))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                    Spacer()
                    if documentsCount > 0 {
                        Text("\(documentsCount)")
                            .font(.system(size: 13))
                            .foregroundColor(MyCoursesPalette.muted)
                    }
                    chevron
                })) {
                showDocuments = true
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            )
        }
    }

    private var leaveButton: some View {
        Button {
            // Wire the coordinator with two dismiss callbacks so it
            // can sequence the teardown one layer at a time —
            //   sub-sheet → cover → chat —
            // instead of dropping them all on the same render frame.
            // An earlier attempt collapsed cover+chat into a single
            // `onLeft()` call expecting the chat-pop to also unmount
            // the cover; iOS 16/17 doesn't reliably do that for a
            // `.fullScreenCover` whose presenter is being popped out
            // of a `NavigationStack`, and the presentation controller
            // would assert. The coordinator's `runLeave` now interleaves
            // ~350-400 ms sleeps between phases so each animation
            // lands on its own frame.
            let coord = LeaveRoomCoordinator(
                room: room,
                onDismissCover: { dismiss() },
                onCompleted: onLeft)
            leaveCoordinatorBox.coordinator = coord
            coord.start()
        } label: {
            HStack {
                Image(systemName: "arrow.right.square")
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.studyRoomsLeaveRoom)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(MyCoursesPalette.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(red: 0.95, green: 0.40, blue: 0.36)
                                        .opacity(0.30), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(leaveCoordinatorBox.coordinator?.isLeaving == true)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.4)
            .foregroundColor(MyCoursesPalette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(MyCoursesPalette.textTertiary)
    }

    @ViewBuilder
    private func row(icon: String?,
                     content: AnyView,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundColor(MyCoursesPalette.muted)
                        .frame(width: 22)
                }
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func members(prefix n: Int) -> [MemberPreview] {
        // `userId` is optional (2026-07): anonymized peers in instructor
        // rooms have a null id; MemberPreview tolerates it.
        Array(room.members.prefix(n).map { m in
            MemberPreview(userId: m.userId, initials: m.initials)
        })
    }

    @ViewBuilder
    private var inviteSheetContent: some View {
        if #available(iOS 16.4, *) {
            InviteSheet(room: room)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(MyCoursesPalette.background)
        } else {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                InviteSheet(room: room)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Data

    private func reloadAll() async {
        await reloadRoom()
        await reloadWaitlist()
        await reloadDocuments()
    }

    private func reloadRoom() async {
        do {
            room = try await StudyRoomsAPI.detail(roomId: room.roomId)
        } catch {
            // Non-fatal; leave the prefetched copy in place.
        }
    }

    private func reloadWaitlist() async {
        guard isAdmin else { waitlistCount = 0; return }
        isLoadingWaitlistCount = true
        defer { isLoadingWaitlistCount = false }
        do {
            let list = try await StudyRoomsAPI.listWaitlist(roomId: room.roomId)
            waitlistCount = list.count
        } catch { /* keep prior count */ }
    }

    private func reloadDocuments() async {
        do {
            let docs = try await StudyRoomsAPI.listDocuments(roomId: room.roomId)
            documentsCount = docs.count
        } catch { /* keep prior count */ }
    }

    private func save(name: String) async {
        do {
            let updated = try await StudyRoomsAPI.updateRoom(
                roomId: room.roomId, name: name, description: nil)
            room = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(description: String) async {
        do {
            let updated = try await StudyRoomsAPI.updateRoom(
                roomId: room.roomId, name: nil, description: description)
            room = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

// MARK: - Coordinator box

/// `@StateObject` of `LeaveRoomCoordinator?` isn't possible directly
/// because `@StateObject` needs a non-optional ObservableObject. This
/// thin wrapper holds the optional coordinator and rebroadcasts its
/// changes so the settings view can drive sheets/screens from it.
///
/// History: an earlier version of this box bridged the coordinator's
/// `objectWillChange` to its own via `for await _ in
/// c.objectWillChange.values` — Combine's `AsyncPublisher`. That
/// crashed the app on every "Leave room" tap (EXC_BREAKPOINT in
/// `AsyncPublisher.Iterator.Inner.receive(_:)` — Apple's async iterator
/// has an internal demand state machine that traps when a publisher
/// emits before the iterator has had a chance to actually subscribe).
/// The button action runs synchronously: `coordinator = coord` followed
/// immediately by `coord.start()` mutates the coordinator's `stage`
/// before the `Task { for await … }` ever gets to iterate, which is
/// exactly the pattern that triggers the trap.
///
/// `sink` is the canonical Combine pattern for this — synchronous
/// delivery, no demand-state machine, no async-iterator lifecycle to
/// race against. The subscription is held in an `AnyCancellable`
/// instead of a `Task`.
@MainActor
final class LeaveCoordinatorBox: ObservableObject {
    @Published var coordinator: LeaveRoomCoordinator? {
        didSet { wireSubscriptions() }
    }
    private var cancellable: AnyCancellable?

    private func wireSubscriptions() {
        cancellable = nil
        guard let c = coordinator else { return }
        // Re-publish on every coordinator stage change so the
        // .sheet(isPresented:) bindings on the settings view re-evaluate.
        cancellable = c.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}

// MARK: - Inline edit sheet

/// Generic edit-single-field sheet — used by Name and Description.
private struct EditFieldSheet: View {
    let label: String
    let initial: String
    let placeholder: String
    var multiline: Bool = false
    var onSave: (String) async -> Void

    @State private var text: String
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    init(label: String, initial: String, placeholder: String,
         multiline: Bool = false,
         onSave: @escaping (String) async -> Void) {
        self.label = label
        self.initial = initial
        self.placeholder = placeholder
        self.multiline = multiline
        self.onSave = onSave
        _text = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text(label)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundColor(MyCoursesPalette.muted)

                    if multiline {
                        TextField(placeholder, text: $text, axis: .vertical)
                            .lineLimit(3...8)
                            .padding(14)
                            .foregroundColor(MyCoursesPalette.textPrimary)
                            .background(
                                RoundedRectangle(cornerRadius: 12,
                                                 style: .continuous)
                                    .fill(MyCoursesPalette.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12,
                                                         style: .continuous)
                                            .stroke(MyCoursesPalette.stroke,
                                                    lineWidth: 1)))
                    } else {
                        TextField(placeholder, text: $text)
                            .padding(14)
                            .foregroundColor(MyCoursesPalette.textPrimary)
                            .background(
                                RoundedRectangle(cornerRadius: 12,
                                                 style: .continuous)
                                    .fill(MyCoursesPalette.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12,
                                                         style: .continuous)
                                            .stroke(MyCoursesPalette.stroke,
                                                    lineWidth: 1)))
                    }

                    Spacer()
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.studyRoomsActionCancel) { dismiss() }
                        .foregroundColor(MyCoursesPalette.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saving
                           ? "…"
                           : L10n.studyRoomsDone) {
                        Task {
                            saving = true
                            await onSave(text)
                            saving = false
                            dismiss()
                        }
                    }
                    .foregroundColor(MyCoursesPalette.accent)
                    .disabled(saving)
                }
            }
        }
    }
}
