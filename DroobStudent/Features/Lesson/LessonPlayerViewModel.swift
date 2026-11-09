import Foundation

// MARK: - Request models

private struct CompleteRequest: Encodable {
    let timeSpentSeconds: Int
    enum CodingKeys: String, CodingKey {
        case timeSpentSeconds = "time_spent_seconds"
    }
}

// MARK: - Response models

struct LessonCompleteApiResponse: Decodable {
    let xpEarned: Int
    let progressPct: Double
    let completedLessonCount: Int
    let courseCompleted: Bool
    let nextLessonId: String?
    let nextLessonTitleEn: String?
    let nextLessonTitleAr: String?

    enum CodingKeys: String, CodingKey {
        case xpEarned = "xp_earned"
        case progressPct = "progress_pct"
        case completedLessonCount = "completed_lesson_count"
        case courseCompleted = "course_completed"
        case nextLessonId = "next_lesson_id"
        case nextLessonTitleEn = "next_lesson_title_en"
        case nextLessonTitleAr = "next_lesson_title_ar"
    }
}

struct BookmarkApiResponse: Decodable {
    let bookmarked: Bool
}

// MARK: - ViewModel

@MainActor
final class LessonPlayerViewModel: ObservableObject {
    let courseId: String
    let lessonId: String
    let locale: String

    @Published var isBookmarked: Bool = false
    @Published var notes: [LessonNoteItem] = []
    @Published var isCompleted: Bool
    @Published var showCompleteModal: Bool = false
    @Published var completeResult: LessonCompleteApiResponse? = nil
    @Published var isTogglingBookmark: Bool = false
    @Published var isMarkingComplete: Bool = false
    @Published var isLoadingNotes: Bool = false

    init(courseId: String, lessonId: String, locale: String, alreadyCompleted: Bool) {
        self.courseId = courseId
        self.lessonId = lessonId
        self.locale = locale
        self.isCompleted = alreadyCompleted
    }

    // MARK: - Load

    /// Loads bookmark + notes side-by-side; both are independent so we don't
    /// need any cross-await ordering.
    func loadState() async {
        async let bookmarkTask: BookmarkApiResponse? = fetchBookmark()
        async let notesTask: [LessonNoteItem] = fetchNotesSafe()
        let (bookmark, fetched) = await (bookmarkTask, notesTask)
        isBookmarked = bookmark?.bookmarked ?? false
        notes = fetched
    }

    // MARK: - Bookmark

    func toggleBookmark() async {
        guard !isTogglingBookmark else { return }
        isTogglingBookmark = true
        let request = APIRequest(
            path: "/v1/student/lessons/\(lessonId)/bookmark",
            method: .POST
        )
        if let response = try? await AuthInterceptor.shared.execute(request) as BookmarkApiResponse {
            isBookmarked = response.bookmarked
        }
        isTogglingBookmark = false
    }

    // MARK: - Notes (multi)

    /// Re-fetches the notes list from the server. Errors are swallowed so the
    /// caller can call this freely after every mutation without bookkeeping.
    func refreshNotes() async {
        isLoadingNotes = true
        notes = await fetchNotesSafe()
        isLoadingNotes = false
    }

    /// Adds a video-anchored note. The optimistic prepend keeps the list
    /// snappy; on failure we drop the placeholder and silently surface the
    /// error to the caller.
    @discardableResult
    func addVideoNote(
        content: String,
        timestampSeconds: Int
    ) async -> LessonNoteItem? {
        do {
            let created = try await LessonInteractionsAPI.createVideoNote(
                lessonId: lessonId,
                content: content,
                timestampSeconds: timestampSeconds)
            notes.insert(created, at: 0)
            return created
        } catch {
            return nil
        }
    }

    /// Adds a document-anchored note. The backend's V45 XOR constraint
    /// requires both `documentId` and `pinnedPage` together — callers
    /// (the PDF reader) snapshot both at "Add Note" tap time.
    @discardableResult
    func addDocumentNote(
        content: String,
        documentId: String,
        pinnedPage: Int,
        selectedText: String? = nil
    ) async -> LessonNoteItem? {
        do {
            let created = try await LessonInteractionsAPI.createDocumentNote(
                lessonId: lessonId,
                documentId: documentId,
                pinnedPage: pinnedPage,
                content: content,
                selectedText: selectedText)
            notes.insert(created, at: 0)
            return created
        } catch {
            return nil
        }
    }

    @discardableResult
    func editNote(_ id: String, content: String) async -> LessonNoteItem? {
        do {
            let updated = try await LessonInteractionsAPI.updateNote(
                lessonId: lessonId, noteId: id, content: content)
            if let idx = notes.firstIndex(where: { $0.id == id }) {
                notes[idx] = updated
            }
            return updated
        } catch {
            return nil
        }
    }

    func deleteNote(_ id: String) async {
        // Optimistic remove — re-fetch on failure to put it back.
        let snapshot = notes
        notes.removeAll { $0.id == id }
        do {
            try await LessonInteractionsAPI.deleteNote(lessonId: lessonId, noteId: id)
        } catch {
            notes = snapshot
        }
    }

    // MARK: - Completion

    /// Records the lesson as finished.
    ///
    /// - Parameter announce: whether to raise the celebration modal. The
    ///   manual "Mark as finished" button is gone (2026-08) — completion now
    ///   fires automatically once the student has watched ~90% of the video,
    ///   at which point the video is still playing and a full-screen cover
    ///   would be an ambush. The player passes `false` there and shows the
    ///   modal itself when playback actually reaches the end.
    func markComplete(timeSpent: Int, announce: Bool = true) async {
        guard !isCompleted, !isMarkingComplete else { return }
        isMarkingComplete = true
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/lessons/\(lessonId)/complete",
            method: .POST,
            body: CompleteRequest(timeSpentSeconds: timeSpent)
        )
        if let result = try? await AuthInterceptor.shared.execute(request) as LessonCompleteApiResponse {
            isCompleted = true
            completeResult = result
            showCompleteModal = announce
        }
        isMarkingComplete = false
    }

    func markUncomplete() async {
        guard isCompleted else { return }
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/lessons/\(lessonId)/complete",
            method: .DELETE
        )
        struct Empty: Decodable {}
        _ = try? await AuthInterceptor.shared.execute(request) as Empty
        isCompleted = false
        completeResult = nil
    }

    // MARK: - Private

    private func fetchBookmark() async -> BookmarkApiResponse? {
        let request = APIRequest(path: "/v1/student/lessons/\(lessonId)/bookmark")
        return try? await AuthInterceptor.shared.execute(request)
    }

    /// Loads the *first page* of notes via the V45 paginated endpoint. The
    /// active-note callout and scrubber markers only need a bounded window
    /// of recent notes; the My Notes screen owns deep pagination separately.
    /// Errors swallowed — empty list is a safe fallback for a lesson the
    /// student hasn't taken notes on yet.
    private func fetchNotesSafe() async -> [LessonNoteItem] {
        let page = try? await LessonInteractionsAPI.listNotesPage(
            lessonId: lessonId, cursor: nil, limit: 50, type: .all)
        return page?.items ?? []
    }
}
