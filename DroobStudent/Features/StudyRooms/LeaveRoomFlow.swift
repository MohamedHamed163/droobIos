import SwiftUI

/// The full leave-room flow: a two-stage chooser for hosts (pass vs
/// just-leave), a confirmation sheet, and a separate pass-host picker.
/// Members (non-hosts) skip straight to the confirmation.
///
/// The flow is driven from `RoomSettingsView` via the
/// `LeaveRoomCoordinator` ObservableObject below. Each sub-view is
/// dumb — it just calls back into the coordinator for the actual
/// API work and dismisses itself on completion.

// MARK: - Coordinator

/// Drives state for the leave flow. Owns:
///   - which sheet/screen is currently presented
///   - the explicit pass-host target id (if any)
///   - the in-flight Task while the leave call runs
@MainActor
final class LeaveRoomCoordinator: ObservableObject {
    enum Stage: Equatable {
        case idle
        /// Member confirmation (one-step). Also used by hosts on the
        /// "Just leave" branch.
        case confirm
        /// Host's two-option bottom sheet (pass vs just-leave).
        case choose
        /// Pass-host picker — full sheet.
        case pickHost
        /// "You're the last one here" — only path when the viewer is
        /// alone in the room. Leaving closes the room permanently.
        case lastOne
    }

    @Published var stage: Stage = .idle
    @Published var isLeaving: Bool = false
    @Published var errorMessage: String?

    let room: StudyRoomDetail
    /// Dismisses the settings full-screen cover (the layer that hosts
    /// the leave-room flow). Called after the leave sub-sheet has
    /// animated out and before the chat is popped — sequencing each
    /// dismiss explicitly avoids the iOS 16/17 presentation-controller
    /// race that crashed the app when the cover was expected to
    /// auto-unmount along with the chat pop.
    let onDismissCover: () -> Void
    /// Pops the chat view off the navigation stack. Fired last,
    /// after the cover has had time to animate away on its own frame.
    let onCompleted: () -> Void

    init(room: StudyRoomDetail,
         onDismissCover: @escaping () -> Void,
         onCompleted: @escaping () -> Void) {
        self.room = room
        self.onDismissCover = onDismissCover
        self.onCompleted = onCompleted
    }

    /// Entry point — tapped from the settings screen.
    func start() {
        // The viewer is alone — leaving will close the room. Show the
        // dedicated "You're the last one here" sheet regardless of
        // role (host or otherwise), since the consequence is the
        // same: the room closes permanently.
        if otherActiveMemberCount == 0 {
            stage = .lastOne
            return
        }
        // Host with at least one other active member → choose between
        // explicit pass and auto-pick. Members go straight to the
        // standard confirmation.
        if room.myRole == .host {
            stage = .choose
        } else {
            stage = .confirm
        }
    }

    func chooseJustLeave() { transition(to: .confirm) }
    func choosePassHost() { transition(to: .pickHost) }
    func cancel() { stage = .idle }

    /// Sheet-to-sheet transitions on the same SwiftUI host view crash
    /// iOS 16/17 when both `.sheet(isPresented:)` bindings flip in the
    /// same render frame (the dismiss + present race). The chooser
    /// lives on `RoomSettingsView` alongside three sibling `.sheet`
    /// modifiers — one per `Stage` — so a direct `stage = .pickHost`
    /// from `.choose` triggers exactly that race. Route every sheet
    /// swap through `.idle` first, give SwiftUI a runloop tick to
    /// fully tear down the outgoing sheet, then transition to the
    /// incoming one. The brief blank-screen flash is invisible at
    /// 350 ms (standard sheet dismiss is ~300 ms) and is the same
    /// pattern `runLeave` already uses for the post-leave cascade.
    private func transition(to next: Stage) {
        guard stage != next else { return }
        // Already at idle (e.g. someone re-entered the flow from
        // settings) — present directly, there's no outgoing sheet to
        // race against.
        if stage == .idle {
            stage = next
            return
        }
        stage = .idle
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            // Bail if the user cancelled or moved the state somewhere
            // else while we were waiting — never blindly clobber.
            guard let self, self.stage == .idle else { return }
            self.stage = next
        }
    }

    /// "Just leave" branch — host or member, server handles auto-pick
    /// if applicable.
    func confirmLeave() {
        guard !isLeaving else { return }
        runLeave(newHostUserId: nil)
    }

    /// Explicit pass — host picked a new host before leaving.
    func leaveWith(newHost member: StudyRoomMember) {
        guard !isLeaving else { return }
        runLeave(newHostUserId: member.userId)
    }

    private func runLeave(newHostUserId: String?) {
        isLeaving = true
        errorMessage = nil
        Task {
            do {
                try await StudyRoomsAPI.leave(
                    roomId: room.roomId,
                    newHostUserId: newHostUserId)
                isLeaving = false
                // Notify the Messages-tab inbox to refresh — the leaver
                // either fully exits (active membership ends) or the
                // room itself closes, both of which the inbox surface
                // wants to reflect immediately.
                NotificationCenter.default.post(
                    name: .droobStudyRoomDidChange, object: nil)

                // Three-phase dismiss. Earlier versions of this code
                // collapsed phases together and crashed on iOS 16/17:
                //
                //   1. The leave sub-sheet (confirm / picker / "last
                //      one here") is owned by the host's `.sheet`
                //      binding which reads `coordinator?.stage`.
                //      Setting stage = .idle starts its animated
                //      dismiss.
                //
                //   2. The settings full-screen cover that contains
                //      the leave flow is mounted on the chat view.
                //      Popping the chat (step 3) was originally
                //      expected to cascade-dismiss this cover, but
                //      iOS doesn't reliably tear down a presented
                //      `.fullScreenCover` when its presenter pops
                //      out of a `NavigationStack` — sometimes the
                //      presentation controller asserts and the app
                //      dies. Dismissing the cover *explicitly* on a
                //      clean frame removes that ambiguity.
                //
                //   3. Pop the chat off the navigation stack so the
                //      user lands back in the rooms list / inbox.
                //
                // Each phase gets its own animation frame (~350-400 ms)
                // so no two dismiss operations land on the same
                // render tick. The brief sequenced animation is the
                // exact behaviour you see when leaving a WhatsApp /
                // Telegram group from inside a settings drill-down.

                stage = .idle
                try? await Task.sleep(nanoseconds: 350_000_000)

                onDismissCover()
                try? await Task.sleep(nanoseconds: 400_000_000)

                onCompleted()
            } catch {
                isLeaving = false
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Derived helpers

    /// Members other than me — drives the "alone vs not alone"
    /// branching. The room's `members` list includes the host, so
    /// "others" is simply size − 1 (works for both host and member
    /// viewers).
    var otherActiveMemberCount: Int {
        max(0, room.members.count - 1)
    }

    /// Co-hosts in the room — drives the "auto-pick" subtitle copy
    /// (different wording when there are no co-hosts to pick from).
    var hasCoHosts: Bool {
        room.members.contains { $0.role == .coHost }
    }

    /// Ordered for the picker: co-hosts first (longest-tenured first,
    /// then regular members). Excludes the leaving host themselves.
    var passHostCandidates: [StudyRoomMember] {
        let me = room.hostId
        let nonHost = room.members.filter { $0.userId != me }
        let coHosts = nonHost.filter { $0.role == .coHost }
                             .sorted { $0.joinedAt < $1.joinedAt }
        let members = nonHost.filter { $0.role == .member }
                             .sorted { $0.joinedAt < $1.joinedAt }
        return coHosts + members
    }
}

// MARK: - Two-option bottom sheet (host)

/// Bottom sheet shown when a host with other members taps Leave.
struct LeaveRoomChooseSheet: View {
    @ObservedObject var coordinator: LeaveRoomCoordinator

    var body: some View {
        VStack(spacing: 16) {
            // Drag handle is provided by the .sheet host; just need
            // the content to breathe.
            VStack(spacing: 4) {
                Text(L10n.studyRoomsLeaveSheetTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(String(format: L10n.studyRoomsLeaveSheetSubtitleHostFmt,
                            coordinator.room.name))
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 12)

            // Option 1 — Pass host & leave
            optionCard(
                icon: "star",
                iconColor: MyCoursesPalette.accent,
                title: L10n.studyRoomsPassHostAndLeave,
                subtitle: L10n.studyRoomsPassHostSubtitleAuto,
                tint: .droobGold,
                action: { coordinator.choosePassHost() })

            // Option 2 — Just leave
            optionCard(
                icon: "arrow.right.square",
                iconColor: MyCoursesPalette.danger,
                title: L10n.studyRoomsJustLeave,
                subtitle: coordinator.hasCoHosts
                    ? L10n.studyRoomsJustLeaveSubtitle
                    : L10n.studyRoomsJustLeaveSubtitleNoCoHost,
                tint: Color(red: 0.95, green: 0.40, blue: 0.36),
                action: { coordinator.chooseJustLeave() })

            Button(L10n.studyRoomsStayInRoom) { coordinator.cancel() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
                .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func optionCard(icon: String, iconColor: Color,
                            title: String, subtitle: String,
                            tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(tint.opacity(0.35), lineWidth: 1))
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint == .droobGold
                                         ? MyCoursesPalette.textPrimary
                                         : MyCoursesPalette.danger)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(MyCoursesPalette.muted)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(MyCoursesPalette.stroke,
                                    lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Confirmation bottom sheet (member + just-leave)

/// Final "are you sure" before the API call. Member's path lands here
/// directly; host's "Just leave" path lands here after the chooser.
struct LeaveRoomConfirmSheet: View {
    @ObservedObject var coordinator: LeaveRoomCoordinator

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.95, green: 0.40, blue: 0.36)
                              .opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(MyCoursesPalette.danger)
            }
            .padding(.top, 8)

            Text(L10n.studyRoomsLeaveConfirmTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)

            HStack(spacing: 10) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.danger)
                Text(L10n.studyRoomsLeaveConfirmDetail)
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            )

            if let msg = coordinator.errorMessage {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.danger)
            }

            Button {
                coordinator.confirmLeave()
            } label: {
                HStack {
                    if coordinator.isLeaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(L10n.studyRoomsLeaveNowCta)
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.95, green: 0.40, blue: 0.36)))
            }
            .buttonStyle(.plain)
            .disabled(coordinator.isLeaving)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .padding(.top, 8)
    }
}

// MARK: - Pass-host picker (full sheet)

/// Full-screen modal where the leaving host picks a specific new host.
/// Co-hosts surface first (with the CO-HOST badge), regular members
/// follow.
struct PassHostPickerView: View {
    @ObservedObject var coordinator: LeaveRoomCoordinator
    @State private var selectedUserId: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        banner
                        sectionLabel(L10n.studyRoomsPassHostSectionLabel)
                        candidatesList
                        if let msg = coordinator.errorMessage {
                            Text(msg)
                                .font(.system(size: 12))
                                .foregroundColor(MyCoursesPalette.danger)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }

                VStack { Spacer(); cta }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.studyRoomsActionCancel) { dismiss() }
                        .foregroundColor(MyCoursesPalette.textPrimary)
                }
                ToolbarItem(placement: .principal) {
                    Text(L10n.studyRoomsPassHostTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.accent)
                }
            }
            .onAppear {
                // Pre-select the first co-host so the CTA has a target
                // out of the box — matches the figma's checkmark on
                // Sara Naguib.
                selectedUserId = coordinator.passHostCandidates.first?.userId
            }
        }
    }

    private var banner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 14))
                .foregroundColor(MyCoursesPalette.accent)
                .padding(.top, 1)
            (Text(String(format: L10n.studyRoomsPassHostBannerFmt,
                         coordinator.room.name))
                .foregroundColor(MyCoursesPalette.textPrimary))
            .font(.system(size: 13))
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MyCoursesPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MyCoursesPalette.accent.opacity(0.30),
                                lineWidth: 1)))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.4)
            .foregroundColor(MyCoursesPalette.muted)
    }

    private var candidatesList: some View {
        VStack(spacing: 10) {
            ForEach(coordinator.passHostCandidates, id: \.userId) { m in
                row(m)
            }
        }
    }

    @ViewBuilder
    private func row(_ m: StudyRoomMember) -> some View {
        let isSelected = selectedUserId == m.userId
        Button {
            selectedUserId = m.userId
        } label: {
            HStack(spacing: 12) {
                MemberAvatar(userId: m.id, initials: m.initials, size: 38)
                HStack(spacing: 8) {
                    Text(m.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                    if m.role == .coHost {
                        Text(L10n.studyRoomsCoHostBadge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(MyCoursesPalette.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.droobGold.opacity(0.18)))
                    }
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(isSelected
                                ? MyCoursesPalette.accent
                                : MyCoursesPalette.textTertiary, lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(MyCoursesPalette.accent)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected
                                ? MyCoursesPalette.accent.opacity(0.50)
                                : MyCoursesPalette.stroke,
                                lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cta: some View {
        let candidate = coordinator.passHostCandidates
            .first(where: { $0.userId == selectedUserId })
        Button {
            guard let c = candidate else { return }
            coordinator.leaveWith(newHost: c)
        } label: {
            HStack {
                Image(systemName: "crown.fill")
                    .font(.system(size: 13))
                if coordinator.isLeaving {
                    ProgressView().tint(.black)
                } else {
                    Text(String(format: L10n.studyRoomsMakeHostAndLeaveFmt,
                                candidate?.name ?? ""))
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.droobGold,
                                 Color.droobGold.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing)))
        }
        .buttonStyle(.plain)
        .disabled(candidate == nil || coordinator.isLeaving)
        .opacity(candidate == nil ? 0.5 : 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }
}

// MARK: - "You're the last one here" sheet

/// Shown when the viewer is the only remaining active member of the
/// room — leaving will close the room permanently, so we surface a
/// dedicated explanation + an explicit "Leave & close room" CTA.
struct LastOneHereSheet: View {
    @ObservedObject var coordinator: LeaveRoomCoordinator

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.droobGold.opacity(0.16))
                    .frame(width: 72, height: 72)
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 30))
                    .foregroundColor(MyCoursesPalette.accent)
            }
            .padding(.top, 12)

            VStack(spacing: 6) {
                Text(L10n.studyRoomsLastOneTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .multilineTextAlignment(.center)
                Text(L10n.studyRoomsLastOneSubtitle)
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.danger)
                    .padding(.top, 1)
                Text(L10n.studyRoomsLastOneDetail)
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MyCoursesPalette.stroke,
                                    lineWidth: 1)))

            if let msg = coordinator.errorMessage {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.danger)
            }

            VStack(spacing: 10) {
                // Primary "Stay" — keeps the room alive (most common
                // choice; the room only closes on the leave path).
                Button {
                    coordinator.cancel()
                } label: {
                    Text(L10n.studyRoomsLastOneStay)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14,
                                             style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Color.droobGold,
                                             Color.droobGold.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing)))
                }
                .buttonStyle(.plain)
                .disabled(coordinator.isLeaving)

                // Destructive "Leave & close room" — permanent.
                Button {
                    coordinator.confirmLeave()
                } label: {
                    HStack(spacing: 8) {
                        if coordinator.isLeaving {
                            ProgressView()
                                .tint(MyCoursesPalette.danger)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                            Text(L10n.studyRoomsLastOneLeaveAndClose)
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundColor(MyCoursesPalette.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 0.95, green: 0.40, blue: 0.36)
                                  .opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14,
                                                 style: .continuous)
                                    .stroke(Color(red: 0.95, green: 0.40,
                                                  blue: 0.36).opacity(0.35),
                                            lineWidth: 1)))
                }
                .buttonStyle(.plain)
                .disabled(coordinator.isLeaving)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .padding(.top, 4)
    }
}
