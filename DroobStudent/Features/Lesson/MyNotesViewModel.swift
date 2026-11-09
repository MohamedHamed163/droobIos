import Foundation

// MARK: - MyNotesViewModel
//
// Drives the "My Notes" screen — a per-lesson, paginated, filterable view
// of the student's notes. Separate from `LessonPlayerViewModel` for two
// reasons:
//
//   • the player VM caches a bounded window of notes (active-note callout +
//     scrubber markers); this VM owns deep pagination across potentially
//     hundreds of notes.
//   • mutations from the My Notes screen (delete, edit) need to flow back to
//     the player VM so the inline section + markers stay in sync — handled
//     here by the `onNotesMutated` callback the host wires up.

import Combine

@MainActor
final class MyNotesViewModel: ObservableObject {
    let lessonId: String

    @Published var items: [LessonNoteItem] = []
    @Published var filter: LessonNotesFilter = .all
    @Published var totalCount: Int = 0
    @Published var sourceCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var loadError: String? = nil

    /// Called whenever this VM mutates a note (edit/delete). The host wires
    /// this up to refresh the lesson player's notes cache so the inline
    /// section, active-note callout and scrubber markers stay coherent.
    var onNotesMutated: (() -> Void)? = nil

    /// Page size for the paginated endpoint. Conservative default keeps the
    /// first page fast; the user rarely needs to see 100 cards before they
    /// pick one.
    private let pageSize: Int = 20

    private var nextCursor: String? = nil
    private var isLoadingMore: Bool = false

    init(lessonId: String) {
        self.lessonId = lessonId
    }

    // MARK: - Loading

    /// Resets state and fetches the first page for the current filter. Call
    /// on appear and whenever the filter changes.
    func loadFirstPage() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        items = []
        nextCursor = nil

        await fetch(cursor: nil, replace: true)

        isLoading = false
    }

    /// Loads the next page if there is one and we're not already mid-flight.
    /// Safe to call from the row-appear handler in a `LazyVStack`.
    func loadMoreIfNeeded(currentItem: LessonNoteItem) async {
        // Only trigger near the tail so we don't spam requests as the user
        // scrolls back up.
        guard let cursor = nextCursor, !cursor.isEmpty else { return }
        guard !isLoadingMore else { return }
        guard let idx = items.firstIndex(of: currentItem) else { return }
        if idx < items.count - 3 { return }   // not within the trailing trigger window

        isLoadingMore = true
        await fetch(cursor: cursor, replace: false)
        isLoadingMore = false
    }

    /// Applies a new filter and reloads from page 1.
    func setFilter(_ newFilter: LessonNotesFilter) async {
        guard newFilter != filter else { return }
        filter = newFilter
        await loadFirstPage()
    }

    // MARK: - Mutations

    func deleteNote(_ id: String) async {
        // Optimistic remove + counts adjustment; on failure we restore.
        let snapshotItems = items
        let snapshotTotal = totalCount
        let snapshotSources = sourceCount

        items.removeAll { $0.id == id }
        // We can't recompute sourceCount precisely without a server roundtrip
        // (the deleted note might have been the last one anchored to its
        // document/video), so we just decrement total and let the next page
        // load or the next loadFirstPage correct sources.
        totalCount = max(0, totalCount - 1)

        do {
            try await LessonInteractionsAPI.deleteNote(lessonId: lessonId, noteId: id)
            onNotesMutated?()
        } catch {
            items = snapshotItems
            totalCount = snapshotTotal
            sourceCount = snapshotSources
        }
    }

    @discardableResult
    func editNote(_ id: String, content: String) async -> Bool {
        do {
            let updated = try await LessonInteractionsAPI.updateNote(
                lessonId: lessonId, noteId: id, content: content)
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx] = updated
            }
            onNotesMutated?()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Internals

    private func fetch(cursor: String?, replace: Bool) async {
        do {
            let page = try await LessonInteractionsAPI.listNotesPage(
                lessonId: lessonId,
                cursor: cursor,
                limit: pageSize,
                type: filter)
            if replace {
                items = page.items
            } else {
                items.append(contentsOf: page.items)
            }
            nextCursor = page.nextCursor
            totalCount = page.totalCount
            sourceCount = page.sourceCount
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
