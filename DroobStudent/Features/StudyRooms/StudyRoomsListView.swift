import SwiftUI

/// Browse + create entry-point for study rooms inside a course.
///
/// This is a v1 placeholder list — it loads PUBLIC + ACTIVE rooms in the
/// course and renders them as compact rows. Tapping a row will (in a
/// follow-up commit, once the room screens are designed) push the chat
/// view; for now the row navigates back to `StudyRoomDetailPlaceholderView`
/// so the wiring is testable end-to-end.
///
/// The Create-room and Join-by-code affordances live in the toolbar; the
/// full create/join UX (privacy picker, code entry sheet) will land
/// alongside the room screens.
struct StudyRoomsListView: View {
    let courseId: String
    let courseTitle: String

    @StateObject private var viewModel: StudyRoomsListViewModel
    @Environment(\.dismiss) private var dismiss

    init(courseId: String, courseTitle: String) {
        self.courseId = courseId
        self.courseTitle = courseTitle
        _viewModel = StateObject(
            wrappedValue: StudyRoomsListViewModel(courseId: courseId))
    }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            Group {
                if viewModel.isLoading && viewModel.rooms.isEmpty {
                    ProgressView()
                        .tint(MyCoursesPalette.accent)
                } else if let error = viewModel.errorMessage, viewModel.rooms.isEmpty {
                    ErrorBanner(message: error) {
                        Task { await viewModel.load() }
                    }
                    .padding(.horizontal, 20)
                } else if viewModel.rooms.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
        }
        .navigationTitle(L10n.studyRoomsListTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L10n.studyRoomsCreateCta, systemImage: "plus.circle") {
                        // create-room sheet ships with the room screens.
                    }
                    Button(L10n.studyRoomsJoinByCodeCta, systemImage: "number") {
                        // join-by-code sheet ships with the room screens.
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(MyCoursesPalette.accent)
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(viewModel.rooms) { room in
                    StudyRoomRow(room: room)
                }
            }
            .padding(20)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 36))
                .foregroundColor(MyCoursesPalette.accent.opacity(0.7))
            Text(L10n.studyRoomsEmptyTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(MyCoursesPalette.textPrimary)
            Text(L10n.studyRoomsEmptySubtitle)
                .font(.system(size: 13))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Row

private struct StudyRoomRow: View {
    let room: StudyRoomSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.droobGold.opacity(0.12))
                Image(systemName: room.privacy == .private ? "lock.fill" : "person.2.fill")
                    .foregroundColor(MyCoursesPalette.accent)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(1)
                if let desc = room.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundColor(MyCoursesPalette.muted)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 5, height: 5)
                    Text(String(format: L10n.studyRoomsParticipantsFmt,
                                room.participantCount, room.maxParticipants))
                        .font(.system(size: 11))
                        .foregroundColor(MyCoursesPalette.muted)
                }
                .padding(.top, 2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MyCoursesPalette.textTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MyCoursesPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
        )
    }
}

// MARK: - ViewModel

@MainActor
final class StudyRoomsListViewModel: ObservableObject {
    @Published private(set) var rooms: [StudyRoomSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// Last-served query; the view consults this to decide whether to
    /// render the "no rooms" empty state vs the "no matches" state.
    @Published private(set) var lastQuery: String = ""

    private let courseId: String
    /// Generation token so a late-arriving fetch can't overwrite a
    /// later query's results.
    private var requestGen: Int = 0

    init(courseId: String) {
        self.courseId = courseId
    }

    /// Fetch rooms, optionally filtered by `query`. Pass an empty
    /// string (the default) for the unfiltered list. The caller is
    /// expected to debounce upstream — this method fires the network
    /// call immediately.
    func load(query: String = "") async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let myGen = requestGen + 1
        requestGen = myGen
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await StudyRoomsAPI.listPublic(
                courseId: courseId,
                query: q.isEmpty ? nil : q)
            // Stale-response guard.
            guard requestGen == myGen else { return }
            rooms = fetched
            lastQuery = q
        } catch {
            guard requestGen == myGen else { return }
            errorMessage = error.localizedDescription
        }
        if requestGen == myGen { isLoading = false }
    }
}
