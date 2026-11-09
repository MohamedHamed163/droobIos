import Foundation

// MARK: - Lesson notes (multi)
//
// As of backend V43, a student may have many notes per lesson, each
// optionally anchored to a playback timestamp. The single-note semantics
// shipped in V21 have been retired — see ADR 0005 in the backend repo.

struct LessonNoteItem: Decodable, Identifiable, Equatable {
    let id: String
    let content: String
    /// Playback anchor in seconds. Mutually exclusive with the document
    /// anchor below — a note is always exactly one of (video, document) as
    /// of backend V45.
    let timestampSeconds: Int?
    /// Owning document id for PDF notes (V45). Pairs with `pinnedPage`.
    let documentId: String?
    /// Document filename, denormalised by the backend so the My Notes screen
    /// can render the source subtitle without a per-row request (V45).
    let documentTitle: String?
    /// 1-based PDF page anchor (V44). Null when the note isn't tied to a PDF.
    let pinnedPage: Int?
    /// Quoted excerpt the student highlighted in the PDF before adding the
    /// note (V44). Null when the note wasn't anchored to a passage.
    let selectedText: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, content
        case timestampSeconds = "timestamp_seconds"
        case documentId = "document_id"
        case documentTitle = "document_title"
        case pinnedPage = "pinned_page"
        case selectedText = "selected_text"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.content = try c.decode(String.self, forKey: .content)
        self.timestampSeconds = try c.decodeIfPresent(Int.self, forKey: .timestampSeconds)
        // V44/V45 fields decoded tolerantly so an older backend response
        // doesn't break the iOS decoder during a staggered rollout.
        self.documentId = try? c.decodeIfPresent(String.self, forKey: .documentId)
        self.documentTitle = try? c.decodeIfPresent(String.self, forKey: .documentTitle)
        self.pinnedPage = try? c.decodeIfPresent(Int.self, forKey: .pinnedPage)
        self.selectedText = try? c.decodeIfPresent(String.self, forKey: .selectedText)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    /// "Video" iff a video timestamp is set. Mutually exclusive with `isDocument`.
    var isVideo: Bool { timestampSeconds != nil }
    /// "Document" iff a PDF anchor is set.
    var isDocument: Bool { pinnedPage != nil }

    /// Formats the optional playback anchor as `mm:ss` for the notes list.
    /// Returns `nil` when the note isn't tied to a specific moment.
    var timestampLabel: String? {
        guard let s = timestampSeconds, s >= 0 else { return nil }
        let mm = s / 60
        let ss = s % 60
        return String(format: "%d:%02d", mm, ss)
    }
}

struct LessonNoteCreatePayload: Encodable {
    let content: String
    let timestampSeconds: Int?
    let documentId: String?
    let pinnedPage: Int?
    let selectedText: String?
    enum CodingKeys: String, CodingKey {
        case content
        case timestampSeconds = "timestamp_seconds"
        case documentId = "document_id"
        case pinnedPage = "pinned_page"
        case selectedText = "selected_text"
    }
}

/// Paginated response shape for V45's notes endpoint. Fields mirror
/// `LessonNotesPageResponse` on the backend.
struct LessonNotesPage: Decodable, Equatable {
    let items: [LessonNoteItem]
    let nextCursor: String?
    /// Total notes matching the supplied filter (not just the items on this page).
    let totalCount: Int
    /// Distinct anchor sources matching the filter — 1 for the video plus
    /// one per distinct document with at least one note.
    let sourceCount: Int

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case totalCount = "total_count"
        case sourceCount = "source_count"
    }
}

/// Filter pill in the My Notes header. The raw value is sent to the backend
/// as the `type` query parameter; values are validated server-side, so a
/// future case can be added without coordinating a release.
enum LessonNotesFilter: String, CaseIterable, Identifiable {
    case all
    case document
    case video
    var id: String { rawValue }
}

struct LessonNoteUpdatePayload: Encodable {
    let content: String
}

// MARK: - Reading progress

/// Mirrors the backend ReadingProgressResponse. `pageCount` is null when the
/// backend hasn't extracted the page count (non-PDF or extraction failed) —
/// in that case the iOS progress bar collapses to a neutral state.
struct ReadingProgressState: Decodable, Equatable {
    let documentId: String
    let currentPage: Int
    let maxPageReached: Int
    let pageCount: Int?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case currentPage = "current_page"
        case maxPageReached = "max_page_reached"
        case pageCount = "page_count"
        case completedAt = "completed_at"
    }

    var progressFraction: Double {
        guard let total = pageCount, total > 0 else { return 0 }
        return min(1.0, Double(maxPageReached) / Double(total))
    }
}

struct ReadingProgressPayload: Encodable {
    let currentPage: Int
    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
    }
}

// MARK: - API helper
//
// Thin shim around APIClient/AuthInterceptor so the lesson-player view model
// doesn't have to spell out the same path-and-body recipes for each call.

enum LessonInteractionsAPI {

    // ── Notes ────────────────────────────────────────────────────────────

    /// Cursor-paginated notes listing (V45). The first page is fetched with
    /// `cursor == nil`; subsequent pages re-send `LessonNotesPage.nextCursor`
    /// until it comes back null.
    ///
    /// `type` defaults to `.all` — pass `.video` or `.document` to filter.
    static func listNotesPage(
        lessonId: String,
        cursor: String? = nil,
        limit: Int = 20,
        type: LessonNotesFilter = .all
    ) async throws -> LessonNotesPage {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "type",  value: type.rawValue)
        ]
        if let cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let req = APIRequest(
            path: "/v1/student/lessons/\(lessonId)/notes",
            queryItems: items)
        return try await AuthInterceptor.shared.execute(req)
    }

    /// Creates a video-anchored note.
    static func createVideoNote(
        lessonId: String,
        content: String,
        timestampSeconds: Int
    ) async throws -> LessonNoteItem {
        let req = APIRequest(
            path: "/v1/student/lessons/\(lessonId)/notes",
            method: .POST,
            body: LessonNoteCreatePayload(
                content: content,
                timestampSeconds: timestampSeconds,
                documentId: nil,
                pinnedPage: nil,
                selectedText: nil))
        return try await AuthInterceptor.shared.execute(req)
    }

    /// Creates a document-anchored note. `documentId` + `pinnedPage` are
    /// required by the backend's V45 XOR constraint — sending one without
    /// the other yields a 400.
    static func createDocumentNote(
        lessonId: String,
        documentId: String,
        pinnedPage: Int,
        content: String,
        selectedText: String? = nil
    ) async throws -> LessonNoteItem {
        let req = APIRequest(
            path: "/v1/student/lessons/\(lessonId)/notes",
            method: .POST,
            body: LessonNoteCreatePayload(
                content: content,
                timestampSeconds: nil,
                documentId: documentId,
                pinnedPage: pinnedPage,
                selectedText: selectedText))
        return try await AuthInterceptor.shared.execute(req)
    }

    static func updateNote(lessonId: String, noteId: String, content: String) async throws -> LessonNoteItem {
        let req = APIRequest(
            path: "/v1/student/lessons/\(lessonId)/notes/\(noteId)",
            method: .PUT,
            body: LessonNoteUpdatePayload(content: content))
        return try await AuthInterceptor.shared.execute(req)
    }

    static func deleteNote(lessonId: String, noteId: String) async throws {
        struct Empty: Decodable {}
        let req = APIRequest(
            path: "/v1/student/lessons/\(lessonId)/notes/\(noteId)",
            method: .DELETE)
        _ = try await AuthInterceptor.shared.execute(req) as Empty
    }

    // ── Reading progress ─────────────────────────────────────────────────

    static func getReadingProgress(lessonId: String, documentId: String) async throws -> ReadingProgressState {
        let req = APIRequest(path: "/v1/student/lessons/\(lessonId)/documents/\(documentId)/reading-progress")
        return try await AuthInterceptor.shared.execute(req)
    }

    static func putReadingProgress(lessonId: String, documentId: String, currentPage: Int) async throws -> ReadingProgressState {
        let req = APIRequest(
            path: "/v1/student/lessons/\(lessonId)/documents/\(documentId)/reading-progress",
            method: .PUT,
            body: ReadingProgressPayload(currentPage: currentPage))
        return try await AuthInterceptor.shared.execute(req)
    }
}
