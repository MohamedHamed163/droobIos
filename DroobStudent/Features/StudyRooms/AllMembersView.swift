import SwiftUI

/// Full members list. Host is pinned at the top in its own card; the
/// other members appear in a single list below. Trailing `…` button
/// is shown only when the viewer is an admin (host or co-host).
struct AllMembersView: View {
    let roomId: String
    let canManage: Bool
    /// Called after promote / demote / remove so the parent can
    /// refresh the room detail (avatar stack, member count, roles).
    var onChange: () -> Void

    @State private var members: [StudyRoomMember] = []
    @State private var hostMember: StudyRoomMember?
    @State private var hostIsMe: Bool = false
    @State private var myRole: StudyRoomRole = .member
    @State private var pendingAction: PendingAction?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    /// Drives the action sheet for a tapped non-host member row.
    struct PendingAction: Identifiable {
        let id: String
        let member: StudyRoomMember
    }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionLabel(L10n.studyRoomsHostSection)
                    if let host = hostMember {
                        hostCard(host)
                    }

                    sectionLabel(String(
                        format: L10n.studyRoomsMembersHeaderFmt,
                        members.count))
                    membersCard
                }
                .padding(20)
            }
        }
        .navigationTitle(L10n.studyRoomsAllMembersTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(L10n.studyRoomsAllMembersTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
            }
        }
        .confirmationDialog(
            pendingAction.map {
                String(format: L10n.studyRoomsActionsForFmt,
                       $0.member.name) } ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible
        ) {
            if let p = pendingAction {
                actionButtons(for: p.member)
            }
        }
        .task { await load() }
    }

    // MARK: - Pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.4)
            .foregroundColor(MyCoursesPalette.muted)
    }

    private func hostCard(_ host: StudyRoomMember) -> some View {
        HStack(spacing: 12) {
            // `id` tolerates a null userId (2026-07 anonymized peers).
            MemberAvatar(userId: host.id,
                         initials: host.initials, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayLabel(for: host))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(L10n.studyRoomsHostCreatedRoom)
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.accent.opacity(0.85))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MyCoursesPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MyCoursesPalette.accent.opacity(0.30),
                                lineWidth: 1))
        )
    }

    private var membersCard: some View {
        VStack(spacing: 0) {
            // Keyed on `id`, not `userId` — anonymized peers (2026-07)
            // have a null userId and fall back to an anon key.
            ForEach(Array(members.enumerated()), id: \.element.id) { idx, m in
                memberRow(m)
                if idx < members.count - 1 {
                    Divider().background(MyCoursesPalette.stroke)
                        .padding(.leading, 60)
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

    private func memberRow(_ m: StudyRoomMember) -> some View {
        HStack(spacing: 12) {
            MemberAvatar(userId: m.id, initials: m.initials, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayLabel(for: m))
                    .font(.system(size: 15))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                if m.role == .coHost {
                    // `studyRoomsMakeCoHost` reads "Make co-host" —
                    // that's the action menu item that *promotes* a
                    // member, not the role label. Showing it under
                    // an *already*-co-host member's name made the
                    // row read "Aisha / Make co-host", which was
                    // both wrong tense and the wrong intent. The
                    // dedicated role-label key reads "Co-host",
                    // mirroring the "Host · created the room"
                    // subtitle pattern on the host card.
                    Text(L10n.studyRoomsCoHostRoleLabel)
                        .font(.system(size: 11))
                        .foregroundColor(MyCoursesPalette.accent.opacity(0.85))
                }
            }
            Spacer()
            // Anonymized rows (null userId, 2026-07) can't be managed —
            // there's no id to act on server-side.
            if canManage && m.userId != nil {
                Button {
                    pendingAction = PendingAction(
                        id: m.id, member: m)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(MyCoursesPalette.muted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func actionButtons(for member: StudyRoomMember) -> some View {
        // Host can promote a member to co-host (or demote a co-host),
        // and can remove anyone except themselves. Co-hosts can only
        // remove regular members (no promote/demote).
        if myRole == .host {
            if member.role == .coHost {
                Button(L10n.studyRoomsDemoteCoHost) {
                    Task { await demote(member) }
                }
            } else {
                Button(L10n.studyRoomsMakeCoHost) {
                    Task { await promote(member) }
                }
            }
        }
        Button(L10n.studyRoomsRemoveFromRoom, role: .destructive) {
            Task { await remove(member) }
        }
        Button(L10n.studyRoomsActionCancel, role: .cancel) {
            pendingAction = nil
        }
    }

    // MARK: - Data

    /// The viewer's own user-id, sourced from the auth session. The
    /// previous implementation aliased this to `hostMember?.userId`,
    /// which made the host card always read "You" regardless of who
    /// was actually viewing it.
    private var currentUserId: String {
        AuthSession.shared.currentUser?.userId ?? ""
    }

    /// Substitutes the localised "You" label for the viewer's own row
    /// in the host card AND the regular members list.
    private func displayLabel(for member: StudyRoomMember) -> String {
        member.userId == currentUserId
            ? L10n.studyRoomsHostYou
            : member.name
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let detail = try await StudyRoomsAPI.detail(roomId: roomId)
            myRole = detail.myRole ?? .member
            hostIsMe = detail.hostId == detail.members.first(where: {
                $0.role == .host })?.userId
            // Partition: host first, then everyone else.
            hostMember = detail.members.first(where: { $0.role == .host })
            members = detail.members.filter { $0.role != .host }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func promote(_ m: StudyRoomMember) async {
        guard let userId = m.userId else { return }
        do {
            try await StudyRoomsAPI.promoteToCoHost(
                roomId: roomId, userId: userId)
            await load()
            onChange()
        } catch { errorMessage = error.localizedDescription }
    }

    private func demote(_ m: StudyRoomMember) async {
        guard let userId = m.userId else { return }
        do {
            try await StudyRoomsAPI.demoteCoHost(
                roomId: roomId, userId: userId)
            await load()
            onChange()
        } catch { errorMessage = error.localizedDescription }
    }

    private func remove(_ m: StudyRoomMember) async {
        guard let userId = m.userId else { return }
        do {
            try await StudyRoomsAPI.removeMember(
                roomId: roomId, userId: userId)
            await load()
            onChange()
        } catch { errorMessage = error.localizedDescription }
    }
}
