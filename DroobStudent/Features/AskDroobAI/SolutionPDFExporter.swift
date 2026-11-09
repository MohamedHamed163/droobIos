import Foundation
import PDFKit
import UIKit
import WebKit

/// Turns answered Ask Droob AI questions into an A4 worksheet PDF.
///
/// The sheet is drawn by the same bundle the chat already renders maths with
/// (Resources/math/ — KaTeX, marked, the fonts) loaded into an off-screen
/// WKWebView, which is then captured with `createPDF(configuration:)`. A second
/// renderer — Core Text, a server round-trip, an embedded interpreter — is what
/// makes an exported formula drift from the one the student saw on screen, so
/// there is deliberately only ever one.
///
/// The page template is Resources/math/print.html. It paginates itself into
/// fixed A4 boxes and reports where each sheet landed, because the renderer
/// never tells the document how many pages it produced but a document that
/// chooses its own page breaks already knows.
@MainActor
final class SolutionPDFExporter {

    /// One question and the answer the model gave for it.
    struct Problem {
        let question: String
        let answer: String
    }

    enum ExportError: LocalizedError {
        /// Why pagination failed, as a *value* rather than an English sentence.
        ///
        /// `layoutFailed` used to carry a raw English string ("the worksheet
        /// never finished rendering"), which `AskDroobAIViewModel.errorText`
        /// interpolated verbatim into its Arabic wrapper — a half-Arabic,
        /// half-English banner on the most common export failure. The view
        /// model now switches on this and picks the Arabic phrase itself.
        enum LayoutFailure {
            /// The 12 s `readyTimeout` fired before print.html ever paginated.
            case neverFinished
            /// The page paginated but reported zero sheets.
            case noPages
            /// A captured sheet produced a PDF with no pages.
            case emptySheet
            /// print.html reported its own exception. `detail` is a raw JS
            /// error string — developer copy, never shown to the student.
            case pageReported(String)

            /// English, developer-facing. Feeds `errorDescription` (logs and
            /// crash reports); the student-facing text comes from
            /// `AskDroobAIViewModel.Strings`, in the app's language.
            var debugDetail: String {
                switch self {
                case .neverFinished: return "the worksheet never finished rendering"
                case .noPages:       return "the worksheet produced no pages"
                case .emptySheet:    return "a sheet came back empty"
                case .pageReported(let detail): return detail
                }
            }
        }

        case nothingToExport
        case templateMissing
        case stagingFailed(Error)
        case layoutFailed(LayoutFailure)
        case captureFailed(Error)
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .nothingToExport:
                return "There are no answers to export yet."
            case .templateMissing:
                return "The worksheet template is missing from the app bundle."
            case .stagingFailed(let error):
                return "Could not prepare the worksheet: \(error.localizedDescription)"
            case .layoutFailed(let reason):
                return "Could not lay out the worksheet: \(reason.debugDetail)"
            case .captureFailed(let error):
                return "Could not render the PDF: \(error.localizedDescription)"
            case .writeFailed(let error):
                return "Could not save the PDF: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Geometry

    /// print.html lays out in CSS pixels against the 96dpi reference, where A4
    /// is 794 × 1123. The web view is pinned to exactly that width so one CSS
    /// pixel is one view point and the rects the page reports need no
    /// conversion before they are handed to `createPDF`.
    private static let sheetWidth: CGFloat = 794
    private static let sheetHeight: CGFloat = 1123

    /// A PDF point is 1/72", a CSS pixel 1/96". Captured 1:1 the file would be
    /// a 280 × 396mm page that every printer then has to shrink; the captured
    /// sheets are re-drawn through this scale so the file really is A4.
    private static let pointsPerPixel: CGFloat = 72.0 / 96.0

    /// KaTeX swaps in its own faces after first paint and the template waits
    /// for `document.fonts.ready` before it paginates, so the signal can be a
    /// second or more behind `didFinish`. Twelve seconds is far past the worst
    /// settle observed on a cold web process; past it we take whatever layout
    /// exists rather than leaving the student staring at a spinner.
    private static let readyTimeout: TimeInterval = 12

    /// Name the template posts its completion message under.
    private static let readyMessageName = "printReady"

    // MARK: - Entry point

    /// Renders `problems` and returns a file URL inside the session's own
    /// `exports/` directory in the durable library.
    ///
    /// It used to return a URL under `temporaryDirectory`, which iOS reclaims
    /// aggressively — including, in principle, before the student opened the
    /// sheet they had just exported. Naming, the atomic write, the protection
    /// class and the lifetime are all the store's job now; this class renders
    /// and nothing else. There is no 24-hour sweep any more either: a sweep that
    /// deletes yesterday's library is precisely the bug being fixed.
    /// `kind` decides whether the sheet becomes *the* session's PDF. The
    /// whole-thread export does; the per-answer one is share-only, because a
    /// one-problem sheet replacing a forty-problem one is a silent deletion.
    static func export(
        problems: [Problem],
        title: String,
        locale: String,
        sessionId: String,
        kind: LibraryExportKind = .session
    ) async throws -> URL {
        guard !problems.isEmpty else { throw ExportError.nothingToExport }
        let data = try await SolutionPDFExporter(
            problems: problems,
            title: title,
            locale: locale
        ).run()
        return try await AskDroobLibraryStore.shared.storeExport(
            sessionId: sessionId,
            seed: LibrarySessionSeed(
                title: title, locale: locale, createdAt: Date()),
            data: data,
            title: title,
            problemCount: problems.count,
            kind: kind)
    }

    // MARK: - Instance

    private let problems: [Problem]
    private let title: String
    private let locale: String
    private let gate = ReadyGate()

    private var isArabic: Bool { locale == "ar" }

    private init(problems: [Problem], title: String, locale: String) {
        self.problems = problems
        self.title = title
        self.locale = locale
    }

    private func run() async throws -> Data {
        // Off the main actor. The first export after iOS reclaims Caches has to
        // re-copy the whole `math/` folder — mathlive.min.js alone is 823 KB,
        // plus KaTeX and its fonts — and this class is @MainActor, so that copy
        // ran on the main thread and showed up as a visible stall right after
        // the student tapped Export. Staging stays in Caches rather than moving
        // into Application Support: it is genuinely re-derivable from the app
        // bundle, and a permanent second copy would eat into the same device
        // budget the Library itself is rationing.
        let staging = try await Task.detached(priority: .userInitiated) {
            try Self.stageAssets()
        }.value
        let page = staging.appendingPathComponent("worksheet-\(UUID().uuidString).html")

        do {
            try buildHTML().write(to: page, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.stagingFailed(error)
        }
        defer { try? FileManager.default.removeItem(at: page) }

        let webView = makeWebView()
        attach(webView)
        defer { detach(webView) }

        webView.loadFileURL(page, allowingReadAccessTo: staging)
        await gate.wait(timeout: Self.readyTimeout)

        let sheets = try await sheetRects(in: webView)
        let pages = try await capture(sheets: sheets, from: webView)
        return assemble(pages)
    }

    // MARK: - Web view

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(gate, name: Self.readyMessageName)

        // print.html carries no viewport meta — on a desktop browser it is
        // simply a wide document. Without one WKWebView lays out at its default
        // 980px and scales the result to fit the view, which would report sheet
        // rects in a different unit than the one `createPDF` captures in.
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=\(Int(Self.sheetWidth)), initial-scale=1';
            (document.head || document.documentElement).appendChild(meta);
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: Self.sheetWidth, height: Self.sheetHeight),
            configuration: configuration
        )
        // The capture rects come out of the document's own coordinate space.
        // They only agree with the view's while the page has not scrolled, so
        // the scroll view is nailed to the origin for the whole export.
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentOffset = .zero
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    /// Parks the web view behind the live UI for the seconds the capture takes.
    ///
    /// A web view that is `isHidden`, zero-sized or outside the hierarchy
    /// altogether has its rendering updates throttled by the system, which
    /// surfaces as blank pages in the PDF. Full alpha is not needed — only
    /// participation in the window.
    private func attach(_ webView: WKWebView) {
        guard let window = Self.hostWindow() else { return }
        webView.alpha = 0.01
        webView.isUserInteractionEnabled = false
        window.addSubview(webView)
        window.sendSubviewToBack(webView)
    }

    private func detach(_ webView: WKWebView) {
        webView.stopLoading()
        // The content controller holds the handler strongly; without this the
        // gate — and through it the web view — outlives every export.
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: Self.readyMessageName)
        webView.removeFromSuperview()
    }

    private static func hostWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first
    }

    // MARK: - Layout

    private struct Layout: Decodable {
        struct Rect: Decodable {
            let x: Double
            let y: Double
            let width: Double
            let height: Double
        }
        let pages: Int
        let rects: [Rect]
        let error: String?
    }

    private func sheetRects(in webView: WKWebView) async throws -> [CGRect] {
        let script = "JSON.stringify(window.droobPrintLayout ? window.droobPrintLayout() : null)"
        let value = try? await evaluate(script, in: webView)

        guard
            let json = value as? String,
            let data = json.data(using: .utf8),
            let layout = try? JSONDecoder().decode(Layout.self, from: data)
        else {
            // Reached when the timeout fired before the page ever paginated —
            // a KaTeX parse blow-up, or a web process the system killed.
            throw ExportError.layoutFailed(.neverFinished)
        }
        if let error = layout.error, !error.isEmpty {
            throw ExportError.layoutFailed(.pageReported(error))
        }
        guard !layout.rects.isEmpty else {
            throw ExportError.layoutFailed(.noPages)
        }
        return layout.rects.map {
            CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
        }
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }

    // MARK: - Capture

    /// Captures one PDF per sheet rather than one tall PDF for the document.
    ///
    /// A single capture of the whole scroll height leaves the page breaks to
    /// WebKit, which knows nothing about the template's mastheads and folios
    /// and would slice a worked step in half. Rect-at-a-time capture makes the
    /// template's own pagination the only one that applies.
    private func capture(sheets: [CGRect], from webView: WKWebView) async throws -> [PDFPage] {
        var pages: [PDFPage] = []

        for rect in sheets {
            let data: Data
            do {
                data = try await pdfData(for: rect, from: webView)
            } catch {
                throw ExportError.captureFailed(error)
            }
            guard let document = PDFDocument(data: data), document.pageCount > 0 else {
                throw ExportError.layoutFailed(.emptySheet)
            }
            // Usually exactly one page. A problem taller than A4 is marked
            // `sheet--overflow` by the template and WebKit may split it, so
            // whatever comes back is kept in order.
            for index in 0..<document.pageCount {
                if let page = document.page(at: index) {
                    pages.append(page)
                }
            }
        }

        return pages
    }

    private func pdfData(for rect: CGRect, from webView: WKWebView) async throws -> Data {
        let configuration = WKPDFConfiguration()
        configuration.rect = rect
        return try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: configuration) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Re-draws the captured sheets at 72dpi into one document.
    ///
    /// `draw(with:to:)` replays the page's content stream, so the maths stays
    /// vector art and the text stays selectable — this is a re-scale, not a
    /// rasterisation.
    private func assemble(_ pages: [PDFPage]) -> Data {
        let scale = Self.pointsPerPixel
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            // Document metadata is user-visible: Files shows it, Preview shows
            // it, and it rides along to every share destination. "Droob" is the
            // brand and stays Latin; the descriptive half follows the sheet.
            kCGPDFContextCreator as String: isArabic ? "دروب" : "Droob",
            kCGPDFContextAuthor as String: isArabic ? "دروب — المساعد الذكي" : "Droob AI"
        ]

        let a4 = CGRect(
            x: 0,
            y: 0,
            width: Self.sheetWidth * scale,
            height: Self.sheetHeight * scale
        )
        let renderer = UIGraphicsPDFRenderer(bounds: a4, format: format)

        return renderer.pdfData { context in
            for page in pages {
                let box = page.bounds(for: .mediaBox)
                let bounds = CGRect(
                    x: 0,
                    y: 0,
                    width: box.width * scale,
                    height: box.height * scale
                )
                context.beginPage(withBounds: bounds, pageInfo: [:])

                let cg = context.cgContext
                cg.saveGState()
                // UIGraphicsPDFRenderer hands over a UIKit-flipped context;
                // PDFPage draws in PDF space (origin bottom-left), so the flip
                // is undone first or every sheet comes out upside down.
                cg.translateBy(x: 0, y: bounds.height)
                cg.scaleBy(x: 1, y: -1)
                cg.scaleBy(x: scale, y: scale)
                cg.translateBy(x: -box.origin.x, y: -box.origin.y)
                page.draw(with: .mediaBox, to: cg)
                cg.restoreGState()
            }
        }
    }

    // MARK: - Asset staging

    /// Copies Resources/math/ somewhere writable and returns that directory.
    ///
    /// `loadHTMLString(_:baseURL:)` cannot read sibling files off disk on iOS,
    /// so the filled worksheet has to sit *inside* a directory `loadFileURL`
    /// has been granted read access to — and the app bundle is read-only. The
    /// copy is made once per build and reused by every later export.
    private nonisolated static func stageAssets() throws -> URL {
        let fm = FileManager.default
        guard let bundled = Bundle.main.url(forResource: "math", withExtension: nil) else {
            throw ExportError.templateMissing
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let root: URL
        do {
            root = try fm.url(for: .cachesDirectory, in: .userDomainMask,
                              appropriateFor: nil, create: true)
                .appendingPathComponent("DroobPrintAssets", isDirectory: true)
        } catch {
            throw ExportError.stagingFailed(error)
        }
        let staged = root.appendingPathComponent(version, isDirectory: true)

        // Caches are evictable, so presence is checked rather than remembered.
        if fm.fileExists(atPath: staged.appendingPathComponent("katex.min.js").path) {
            return staged
        }
        do {
            // A previous build's copy is stale the moment the version changes.
            try? fm.removeItem(at: root)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try fm.copyItem(at: bundled, to: staged)
        } catch {
            throw ExportError.stagingFailed(error)
        }
        return staged
    }

    // MARK: - Template filling

    private func buildHTML() throws -> String {
        guard
            let templateURL = Bundle.main.url(
                forResource: "print", withExtension: "html", subdirectory: "math"),
            let template = try? String(contentsOf: templateURL, encoding: .utf8)
        else {
            throw ExportError.templateMissing
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        let counter = NumberFormatter()
        counter.locale = Locale(identifier: locale)
        counter.numberStyle = .decimal
        let count = counter.string(from: NSNumber(value: problems.count)) ?? "\(problems.count)"

        let subtitle = isArabic
            ? "\(count) من المسائل المحلولة · اسأل دروب"
            : "\(count) solved \(problems.count == 1 ? "problem" : "problems") · Ask Droob AI"

        // The disclaimer is not decoration: these solutions come from a general
        // purpose model, and the sheet outlives the chat that framed it.
        let footnote = isArabic
            ? "حلول من الذكاء الاصطناعي — راجعها مع معلمك قبل الاعتماد عليها."
            : "AI-generated solutions — check them with your teacher before relying on them."

        let labels: [String: String] = isArabic
            ? [
                "problem": "مسألة",
                "question": "السؤال",
                "steps": "الحل",
                "answer": "الإجابة النهائية",
                "pageOf": "صفحة {n} من {m}"
              ]
            : [
                "problem": "Problem",
                "question": "Question",
                "steps": "Solution",
                "answer": "Final answer",
                "pageOf": "Page {n} of {m}"
              ]

        return Self.fill(template, with: [
            "LANG": isArabic ? "ar" : "en",
            "DIR": isArabic ? "rtl" : "ltr",
            "TITLE": Self.escapeText(title),
            "SUBTITLE": Self.escapeText(subtitle),
            "DATE": Self.escapeText(formatter.string(from: Date())),
            "FOOTER_NOTE": Self.escapeText(footnote),
            "LABELS": Self.json(labels),
            "PROBLEMS": Self.json(problemsPayload())
        ])
    }

    private func problemsPayload() -> [[String: Any]] {
        problems.enumerated().map { position, problem in
            let outline = SolutionOutline.split(problem.answer)
            var entry: [String: Any] = [
                "index": position + 1,
                "question": problem.question,
                "steps": outline.steps
            ]
            if let final = outline.final {
                entry["answer"] = final
            }
            return entry
        }
    }

    /// Substitutes every `{{TOKEN}}` in a single left-to-right pass.
    ///
    /// A student's question can perfectly well contain the text "{{DATE}}", and
    /// a chain of `replacingOccurrences` would then substitute into content it
    /// had itself just inserted. One pass makes user text inert. Tokens with no
    /// value are copied through untouched, which is what lets the raw template
    /// still open in a browser.
    private static func fill(_ template: String, with values: [String: String]) -> String {
        var output = ""
        output.reserveCapacity(template.count + 4096)
        var cursor = template.startIndex

        while let open = template.range(of: "{{", range: cursor..<template.endIndex) {
            guard let close = template.range(
                of: "}}", range: open.upperBound..<template.endIndex) else { break }
            let name = String(template[open.upperBound..<close.lowerBound])
            output += template[cursor..<open.lowerBound]
            output += values[name] ?? String(template[open.lowerBound..<close.upperBound])
            cursor = close.upperBound
        }
        output += template[cursor...]
        return output
    }

    /// The template takes its strings as element text, so only the three
    /// characters that can end or open a tag need handling — and `&` first, or
    /// the entities produced by the other two get escaped a second time.
    private static func escapeText(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// JSON destined for a `<script type="application/json">` block.
    ///
    /// The HTML parser ends that element at the first `</` it sees, string
    /// literal or not, so an answer that mentions `</script>` would otherwise
    /// cut the document in half. Escaping every `<` to its JSON unicode
    /// escape ends that whole class of problem, and JSON.parse restores it.
    private static func json(_ object: Any) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: object),
            let text = String(data: data, encoding: .utf8)
        else {
            return "null"
        }
        return text.replacingOccurrences(of: "<", with: "\\u003c")
    }
}

// MARK: - Ready gate

/// Bridges the template's `printReady` message into async/await.
///
/// KaTeX renders asynchronously and the page only paginates once
/// `document.fonts.ready` resolves — capturing on `didFinish` would snapshot
/// half-typeset maths. The deadline exists because a page that throws while
/// paginating never posts anything, and an export that hangs forever is worse
/// than one that fails.
@MainActor
private final class ReadyGate: NSObject, WKScriptMessageHandler {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait(timeout: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard !opened else {
                continuation.resume()
                return
            }
            self.continuation = continuation
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                self.open()
            }
        }
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated { open() }
    }

    /// Resumes at most once: the page's message and the deadline race each
    /// other, and on a slow device both land.
    private func open() {
        guard !opened else { return }
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - Answer shaping

/// Splits one markdown answer into the numbered steps and boxed final answer
/// the worksheet template lays out.
///
/// The shape is recovered here instead of being demanded from the model: the
/// fallback chain runs across five providers and the smaller ones quietly
/// ignore "reply as JSON", which would turn a formatting instruction into an
/// export that fails on some providers and not others.
private enum SolutionOutline {

    /// How a model introduces its conclusion, in both languages the app runs in.
    private static let answerMarkers = [
        "final answer", "the answer is", "answer:", "result:",
        "الإجابة النهائية", "الجواب النهائي", "الإجابة:", "الجواب:", "الناتج النهائي"
    ]

    static func split(_ answer: String) -> (steps: [String], final: String?) {
        let lines = answer
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        let breakable = breakableLines(in: lines)

        var body = lines
        var final: String?

        if let start = finalAnswerStart(in: lines, breakable: breakable) {
            final = strippedMarker(from: Array(lines[start...]).joined(separator: "\n"))
            body = Array(lines[..<start])
        }

        var steps = groupSteps(in: body, breakable: breakable)
        if steps.isEmpty {
            let whole = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            // An answer that is nothing but its conclusion still needs a body,
            // or the sheet shows a numbered problem with no working at all.
            if whole.isEmpty, let final {
                steps = [final]
            } else if !whole.isEmpty {
                steps = [whole]
            }
        }
        return (steps, final)
    }

    /// Marks the lines it is safe to cut at.
    ///
    /// A display formula and a fenced block both span several lines, and
    /// splitting inside one leaves KaTeX an unterminated `$$` — which it
    /// renders as literal dollar signs across two steps.
    private static func breakableLines(in lines: [String]) -> [Bool] {
        var flags = [Bool](repeating: true, count: lines.count)
        var inMath = false
        var inFence = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            flags[index] = !inMath && !inFence

            if trimmed.hasPrefix("```") {
                inFence.toggle()
                flags[index] = false
                continue
            }
            if inFence { continue }

            let fences = countOccurrences(of: "$$", in: line)
            if fences % 2 == 1 {
                inMath.toggle()
                flags[index] = flags[index] && !inMath
            }
        }
        return flags
    }

    private static func finalAnswerStart(in lines: [String], breakable: [Bool]) -> Int? {
        for index in stride(from: lines.count - 1, through: 0, by: -1) where breakable[index] {
            let plain = stripEmphasis(lines[index]).lowercased()
            guard !plain.isEmpty else { continue }
            if answerMarkers.contains(where: { plain.hasPrefix($0) }) {
                return index
            }
        }
        return nil
    }

    private static func groupSteps(in lines: [String], breakable: [Bool]) -> [String] {
        var steps: [String] = []
        var current: [String] = []

        func flush() {
            let text = current.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { steps.append(text) }
            current = []
        }

        for (index, line) in lines.enumerated() {
            let starts = index < breakable.count && breakable[index] && isStepOpener(line)
            if starts && !current.isEmpty { flush() }
            current.append(line)
        }
        flush()

        // One "step" means nothing was recognised as a walk-through; blank-line
        // blocks are the next best guess before giving up and shipping the blob.
        if steps.count <= 1 {
            steps = blankLineBlocks(in: lines, breakable: breakable)
        }
        return steps
    }

    private static func blankLineBlocks(in lines: [String], breakable: [Bool]) -> [String] {
        var blocks: [String] = []
        var current: [String] = []

        for (index, line) in lines.enumerated() {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank && index < breakable.count && breakable[index] {
                let text = current.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { blocks.append(text) }
                current = []
            } else {
                current.append(line)
            }
        }
        let tail = current.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { blocks.append(tail) }
        return blocks
    }

    /// True for "1." / "2)" openers and for markdown headings — the two ways
    /// every provider in the chain marks the start of a step. Deliberately not
    /// bullets: models bullet the givens of a problem as often as the working.
    private static func isStepOpener(_ line: String) -> Bool {
        var rest = Substring(line)
        var indent = 0
        while let first = rest.first, first == " " || first == "\t" {
            indent += 1
            rest.removeFirst()
        }
        guard indent <= 3, !rest.isEmpty else { return false }

        if rest.hasPrefix("#") { return true }

        var digits = 0
        while let first = rest.first, first.isNumber, digits < 2 {
            digits += 1
            rest.removeFirst()
        }
        guard digits > 0, let separator = rest.first, separator == "." || separator == ")" else {
            return false
        }
        rest.removeFirst()
        return rest.isEmpty || rest.first == " "
    }

    /// Drops the "Final answer:" opener so the boxed label is not printed twice.
    private static func strippedMarker(from text: String) -> String {
        var head = text
        var tail = ""
        if let newline = text.firstIndex(of: "\n") {
            head = String(text[..<newline])
            tail = String(text[text.index(after: newline)...])
        }

        var plain = stripEmphasis(head)
        let lowered = plain.lowercased()
        for marker in answerMarkers where lowered.hasPrefix(marker) {
            plain = String(plain.dropFirst(marker.count))
            break
        }
        plain = plain.trimmingCharacters(in: CharacterSet(charactersIn: " :：-—*"))

        let joined = tail.isEmpty ? plain : "\(plain)\n\(tail)"
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Markdown emphasis and heading marks are stripped only for *matching* —
    /// the text handed to the template keeps its formatting.
    private static func stripEmphasis(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*_>` "))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func countOccurrences(of needle: String, in text: String) -> Int {
        var count = 0
        var cursor = text.startIndex
        while let found = text.range(of: needle, range: cursor..<text.endIndex) {
            count += 1
            cursor = found.upperBound
        }
        return count
    }
}
