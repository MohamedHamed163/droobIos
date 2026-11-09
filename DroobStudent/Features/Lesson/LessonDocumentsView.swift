import SwiftUI
import SafariServices

// MARK: - Model

struct LessonDocumentItem: Decodable, Identifiable, Equatable {
    let id: String
    let filename: String
    let mimeType: String
    let sizeBytes: Int
    let viewUrl: String
    let requiredReading: Bool
    let pageCount: Int?
    let readTimeMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case id, filename
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case viewUrl = "view_url"
        case requiredReading = "is_required_reading"
        case pageCount = "page_count"
        case readTimeMinutes = "read_time_minutes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.filename = try c.decode(String.self, forKey: .filename)
        self.mimeType = try c.decode(String.self, forKey: .mimeType)
        self.sizeBytes = try c.decode(Int.self, forKey: .sizeBytes)
        self.viewUrl = try c.decode(String.self, forKey: .viewUrl)
        // New V43 fields — decode optionally so an older backend response
        // (pre-migration) doesn't break the iOS decoder.
        self.requiredReading = (try? c.decode(Bool.self, forKey: .requiredReading)) ?? false
        self.pageCount = try? c.decodeIfPresent(Int.self, forKey: .pageCount)
        self.readTimeMinutes = try? c.decodeIfPresent(Int.self, forKey: .readTimeMinutes)
    }

    var formattedSize: String {
        let kb = Double(sizeBytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    /// "18 pages · PDF · 12 min read" composite shown on the Required Reading
    /// card. Falls back gracefully when fields are missing.
    var metaLine: String {
        var parts: [String] = []
        if let pages = pageCount, pages > 0 {
            parts.append("\(pages) pages")
        }
        parts.append(mimeType == "application/pdf" ? "PDF" : (mimeType.split(separator: "/").last.map(String.init) ?? "DOC").uppercased())
        if let minutes = readTimeMinutes, minutes > 0 {
            parts.append("\(minutes) min read")
        }
        return parts.map(\.bidiIsolated).joined(separator: " · ")
    }
}

// MARK: - View

struct LessonDocumentsView: View {
    let courseId: String
    let lessonId: String
    let title: String
    /// Whether the lesson is already marked complete on entry. Suppresses the
    /// redundant complete call in `autoCompleteOnOpen`. Defaults to `false` so
    /// older call sites keep compiling.
    let alreadyCompleted: Bool

    @State private var documents: [LessonDocumentItem] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var safariURL: URL? = nil

    // Completion is reused from the video player's view model so document-only
    // lessons hit the exact same complete endpoint. Non-video lessons used to
    // land here with no way to be marked done at all; they now complete on
    // open (see `autoCompleteOnOpen`).
    @StateObject private var completion: LessonPlayerViewModel
    @State private var startTime: Date = Date()

    init(
        courseId: String,
        lessonId: String,
        title: String,
        alreadyCompleted: Bool = false
    ) {
        self.courseId = courseId
        self.lessonId = lessonId
        self.title = title
        self.alreadyCompleted = alreadyCompleted
        _completion = StateObject(wrappedValue: LessonPlayerViewModel(
            courseId: courseId,
            lessonId: lessonId,
            locale: "en",
            alreadyCompleted: alreadyCompleted
        ))
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView(L10n.loading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ErrorBanner(message: error) {
                    Task { await loadDocuments() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if documents.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(L10n.noDocuments)
                        .font(.droobBody)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(documents) { doc in
                    Button {
                        if let url = URL(string: doc.viewUrl) {
                            safariURL = url
                        }
                    } label: {
                        DocumentRow(document: doc)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDocuments() }
        .sheet(item: $safariURL) { url in
            SafariView(url: url)
        }
    }

    /// A document lesson has no playhead, so there is no "90% watched" moment
    /// to hang completion off the way the video player does. Opening it is the
    /// whole interaction — so opening it is what marks it done.
    ///
    /// Silent (`announce: false`): a celebration modal thrown up the instant
    /// the screen appears would cover the documents the student came to read.
    /// The view model's own guards make the repeat call after a re-open a
    /// no-op.
    private func autoCompleteOnOpen() async {
        let elapsed = Int(Date().timeIntervalSince(startTime))
        await completion.markComplete(timeSpent: elapsed, announce: false)
    }

    private func loadDocuments() async {
        isLoading = true
        errorMessage = nil
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/lessons/\(lessonId)/documents"
        )
        do {
            documents = try await AuthInterceptor.shared.execute(request)
            // Only after the lesson actually loaded — a failed fetch renders an
            // error, not the lesson, and shouldn't quietly credit the student.
            await autoCompleteOnOpen()
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let document: LessonDocumentItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 28))
                // Bare gold icon on the row's own light background — ink, so
                // it takes the adaptive accent rather than `droobPrimary`,
                // which is the raw gold in light mode.
                .foregroundColor(MyCoursesPalette.accent)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.filename)
                    .font(.droobSubheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text(document.formattedSize)
                    .font(.droobCaption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.up.right.square")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        if document.mimeType == "application/pdf" { return "doc.richtext.fill" }
        if document.mimeType.hasPrefix("image/") { return "photo.fill" }
        return "doc.fill"
    }
}

// MARK: - Safari wrapper

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}
