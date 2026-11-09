import SwiftUI

/// Host / co-host waitlist screen for private rooms. Lists every
/// PENDING request with per-row Approve / Reject buttons and a trailing
/// "Approve all" header action.
struct WaitlistView: View {
    let roomId: String
    /// Called after each decision so the parent can refresh badges /
    /// counters (the chat header member count, settings row badge).
    var onChange: () -> Void

    @State private var entries: [WaitlistEntry] = []
    @State private var isLoading: Bool = false
    @State private var inFlight: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    headerRow

                    if isLoading && entries.isEmpty {
                        HStack {
                            ProgressView().tint(MyCoursesPalette.accent)
                            Spacer()
                        }
                        .padding(.vertical, 40)
                    } else if entries.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(L10n.studyRoomsWaitlistTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.accent)
                    Text(L10n.studyRoomsWaitlistHostView)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(MyCoursesPalette.muted)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Pieces

    private var headerRow: some View {
        HStack {
            Text(String(format: L10n.studyRoomsWaitingPeopleFmt, entries.count))
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundColor(MyCoursesPalette.muted)
            Spacer()
            if !entries.isEmpty {
                Button { Task { await approveAll() } } label: {
                    Text(L10n.studyRoomsApproveAll)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.accent)
                }
                .buttonStyle(.plain)
                .disabled(!inFlight.isEmpty)
            }
        }
    }

    private var emptyState: some View {
        Text(L10n.studyRoomsWaitlistEmpty)
            .font(.system(size: 13))
            .foregroundColor(MyCoursesPalette.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, e in
                row(e)
                if idx < entries.count - 1 {
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

    private func row(_ e: WaitlistEntry) -> some View {
        HStack(spacing: 12) {
            MemberAvatar(userId: e.userId, initials: e.userInitials, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.userName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(waitLabel(for: e))
                    .font(.system(size: 11))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            Spacer()
            if inFlight.contains(e.userId) {
                ProgressView().tint(MyCoursesPalette.accent)
            } else {
                Button { Task { await approve(e) } } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.27, green: 0.78, blue: 0.40))
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.green.opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.green.opacity(0.40),
                                                lineWidth: 1)))
                }
                .buttonStyle(.plain)
                Button { Task { await reject(e) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(MyCoursesPalette.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(MyCoursesPalette.stroke,
                                                lineWidth: 1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// "Just arrived" / "5 min wait" / "2 hr wait" — relative time
    /// since `requestedAt`.
    private func waitLabel(for e: WaitlistEntry) -> String {
        let delta = Date().timeIntervalSince(e.requestedAt)
        if delta < 60 { return L10n.studyRoomsJustArrived }
        if delta < 3600 {
            return String(format: L10n.studyRoomsMinWaitFmt, Int(delta / 60))
        }
        return String(format: L10n.studyRoomsHrWaitFmt, Int(delta / 3600))
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await StudyRoomsAPI.listWaitlist(roomId: roomId)
        } catch { errorMessage = error.localizedDescription }
    }

    private func approve(_ e: WaitlistEntry) async {
        inFlight.insert(e.userId)
        defer { inFlight.remove(e.userId) }
        do {
            try await StudyRoomsAPI.approveWaitlist(
                roomId: roomId, userId: e.userId)
            entries.removeAll { $0.userId == e.userId }
            onChange()
        } catch { errorMessage = error.localizedDescription }
    }

    private func reject(_ e: WaitlistEntry) async {
        inFlight.insert(e.userId)
        defer { inFlight.remove(e.userId) }
        do {
            try await StudyRoomsAPI.rejectWaitlist(
                roomId: roomId, userId: e.userId)
            entries.removeAll { $0.userId == e.userId }
            onChange()
        } catch { errorMessage = error.localizedDescription }
    }

    private func approveAll() async {
        // Show in-flight for every pending row at once.
        let ids = Set(entries.map { $0.userId })
        inFlight.formUnion(ids)
        defer { inFlight.subtract(ids) }
        do {
            _ = try await StudyRoomsAPI.approveAllWaitlist(roomId: roomId)
            entries.removeAll()
            onChange()
        } catch { errorMessage = error.localizedDescription }
    }
}
