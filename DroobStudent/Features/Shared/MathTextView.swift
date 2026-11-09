import SwiftUI
import WebKit

/// Renders instructor-authored text that may contain LaTeX math, using the
/// bundled KaTeX in Resources/math/ (the same assets the AI tutor uses, so this
/// works fully offline).
///
/// Unlike `MathMarkdownView` this is **math only** — the source is injected as
/// textContent, not markdown-parsed into innerHTML. Quiz text is written by
/// instructors and shown to students, so running it through a markdown parser
/// would let one user put arbitrary HTML on another user's screen.
///
/// Prefer `MathText` over this type at call sites: it falls back to a plain
/// `Text` when there is no math, which avoids paying for a WKWebView on the
/// large majority of questions that are prose only.
struct MathTextView: UIViewRepresentable {
    let source: String
    let textColor: UIColor
    let fontSize: CGFloat
    /// Right-to-left when the surrounding UI is Arabic. Maths stays LTR.
    let isRTL: Bool
    @Binding var contentHeight: CGFloat

    /// The page's color is injected as a literal hex string, so a dynamic
    /// `textColor` has to be resolved against a known interface style. Reading
    /// the scheme from the environment (rather than the ambient
    /// `UITraitCollection.current`, which is unspecified here) also makes this
    /// view a dependency of the theme, so a flip re-runs `updateUIView`.
    @Environment(\.colorScheme) private var colorScheme

    private var interfaceStyle: UIUserInterfaceStyle {
        colorScheme == .dark ? .dark : .light
    }

    func makeCoordinator() -> Coordinator { Coordinator(self, style: interfaceStyle) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "heightChanged")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator

        if let mathDir = Bundle.main.url(forResource: "math", withExtension: nil),
           let htmlURL = Bundle.main.url(forResource: "math", withExtension: "html", subdirectory: "math") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: mathDir)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        let style = interfaceStyle
        if coord.pendingSource != source || !coord.initialRenderDone || coord.pendingStyle != style {
            coord.pendingSource = source
            coord.pendingStyle = style
            if coord.pageReady { coord.render(in: webView) }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let parent: MathTextView
        var pendingSource: String = ""
        /// Interface style the injected hex was last resolved for.
        var pendingStyle: UIUserInterfaceStyle
        var pageReady = false
        var initialRenderDone = false

        init(_ parent: MathTextView, style: UIUserInterfaceStyle) {
            self.parent = parent
            self.pendingSource = parent.source
            self.pendingStyle = style
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageReady = true
            render(in: webView)
        }

        func render(in webView: WKWebView) {
            // Resolve explicitly: `getRed` on a dynamic UIColor outside a trait
            // context returns whichever style happened to be current when the
            // color was built, which would freeze the page at the old theme.
            let fg = parent.textColor
                .resolvedColor(with: UITraitCollection(userInterfaceStyle: pendingStyle))
                .mathHexString
            // JSON-encode the source so quotes, backslashes and newlines survive
            // the trip into JS intact — LaTeX is mostly backslashes.
            let encoded = String(
                data: (try? JSONSerialization.data(
                    withJSONObject: [pendingSource],
                    options: [])) ?? Data(),
                encoding: .utf8) ?? "[\"\"]"

            // Arabic prose must flow right-to-left; the formulas inside it stay
            // left-to-right (math.html isolates `.katex`).
            let dir = parent.isRTL ? "rtl" : "ltr"
            let js = """
            document.body.style.color = '\(fg)';
            document.body.style.background = 'transparent';
            document.body.style.fontSize = '\(parent.fontSize)px';
            document.body.setAttribute('dir', '\(dir)');
            if (typeof droobRenderMath === 'function') {
              droobRenderMath(\(encoded)[0]);
            }
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
            initialRenderDone = true
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "heightChanged", let n = message.body as? NSNumber else { return }
            let h = CGFloat(n.doubleValue)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if abs(self.parent.contentHeight - h) > 0.5 {
                    self.parent.contentHeight = max(16, h)
                }
            }
        }
    }
}

/// True when the string contains a complete `$…$` or `$$…$$` span.
///
/// Used to keep the WebView off screens that don't need it — a question with
/// four prose options would otherwise spin up five web views.
func containsMath(_ s: String) -> Bool {
    var idx = s.startIndex
    var openDelimiter = false
    while idx < s.endIndex {
        let c = s[idx]
        if c == "\\" {
            idx = s.index(idx, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
            continue
        }
        if c == "$" {
            if openDelimiter { return true }
            openDelimiter = true
        }
        idx = s.index(after: idx)
    }
    return false
}

/// Strips `$` delimiters for places that must stay a single truncated line of
/// plain text (list summaries), where a rendered WebView can't be laid out.
/// The full formula still renders on the detail screen.
func mathPlainText(_ s: String) -> String {
    var out = ""
    var idx = s.startIndex
    while idx < s.endIndex {
        let c = s[idx]
        if c == "\\", let next = s.index(idx, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex,
           s[next] == "$" {
            out.append("$")
            idx = s.index(after: next)
            continue
        }
        if c != "$" { out.append(c) }
        idx = s.index(after: idx)
    }
    return out
}

/// Drop-in replacement for `Text` on instructor-authored strings.
///
/// Renders with KaTeX only when the string actually contains math; otherwise it
/// is an ordinary `Text` with no WebView cost.
struct MathText: View {
    let source: String
    var font: Font = .system(size: 16)
    var fontSize: CGFloat = 16
    var weight: Font.Weight = .regular
    var color: Color = MyCoursesPalette.textPrimary
    var alignment: TextAlignment = .leading
    var isRTL: Bool = false

    @State private var height: CGFloat = 16

    var body: some View {
        if containsMath(source) {
            MathTextView(
                source: source,
                textColor: UIColor(color),
                fontSize: fontSize,
                isRTL: isRTL,
                contentHeight: $height
            )
            .frame(height: height)
        } else {
            Text(source)
                .font(font.weight(weight))
                .foregroundColor(color)
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension UIColor {
    var mathHexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Review-sheet normalisation
//
// An extracted question is MIXED content: prose in Arabic or English, LaTeX,
// and answer markers `a) b) c)` that belong to neither. The only correct
// renderer for that is the markdown+KaTeX one the chat bubbles already use,
// which typesets the `$…$` spans and leaves everything else as text. What the
// review card was missing is not a renderer — it is a guarantee about the
// string handed to one, and that guarantee is this function.
//
// It repairs, on the host, the three things a model gets wrong often enough to
// be seen on a real device:
//
//   * a question with no delimiters at all — `sin^{-1}(\frac{\sqrt{2}}{2})` —
//     which fails the `containsMath` gate and is printed as raw source;
//   * a question wrapped in ONE pair of dollars from the stem to the last
//     option, which KaTeX then typesets as a single formula with the option
//     markers absorbed into it as maths-mode italics;
//   * options separated by a soft newline, which CommonMark renders as a space,
//     so the whole question arrives as one run-on line.
//
// A character scan, never a regex: this is entirely about braces, and the
// Android twin has to be byte-comparable with it under ICU, where a bare `}` is
// a runtime pattern error. `repairLatexEscapes` in OCRService.swift already set
// that precedent.

/// Arabic-Indic and Extended Arabic-Indic digits, and their Western twins.
///
/// KaTeX has no glyph for ٠١٢٣ and neither does the copy of it inside
/// `print.html`, so ONE of these inside a `$…$` span turns the whole formula
/// into a red parse error on screen and a broken line in the exported PDF.
/// Prose digits are never touched — a year or a page number stays as the sheet
/// wrote it.
private let reviewArabicIndicDigits: [Character: Character] = [
    "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
    "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
    "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
    "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"
]

private func reviewWesternDigits(_ chars: [Character]) -> [Character] {
    chars.map { reviewArabicIndicDigits[$0] ?? $0 }
}

private func reviewIsASCIILetter(_ c: Character) -> Bool {
    c.isASCII && c.isLetter
}

private func reviewIsASCIIAlnum(_ c: Character) -> Bool {
    c.isASCII && (c.isLetter || c.isNumber)
}

/// Everything a bare maths run may be built from, apart from the grouping
/// characters, which are counted rather than merely accepted.
private let reviewMathPunctuation: Set<Character> = [
    "\\", "{", "}", "^", "_", "(", ")", "[", "]",
    "+", "-", "*", "/", "=", "<", ">", ",", ".", "|", "!"
]

private func reviewIsMathChar(_ c: Character) -> Bool {
    if reviewIsASCIIAlnum(c) { return true }
    if reviewArabicIndicDigits[c] != nil { return true }
    return reviewMathPunctuation.contains(c)
}

/// What a `^` or `_` has to sit behind before it is read as an exponent rather
/// than as an underscore in ordinary text.
private func reviewIsRunAnchor(_ c: Character) -> Bool {
    reviewIsASCIIAlnum(c) || c == ")" || c == "}"
}

/// An operator or relation — the characters that make a space around them part
/// of a formula rather than the end of one.
///
/// Two letters either side of a space is prose, in any language: without this
/// `my_name is not maths` is one long maths run, because `_` triggers and every
/// character after it is a letter or a space.
private let reviewMathOperators: Set<Character> = [
    "+", "-", "*", "/", "=", "<", ">", "^", "_", "|", "!"
]

// MARK: Step 2 — alternative delimiters

/// `\( \)` → `$`, `\[ \]` → `$$`. Two prompts historically permitted these and
/// neither renderer has ever supported them, so they arrive as visible
/// backslashes. A `\\` is copied as a pair so it can never be misread as the
/// opening half of one.
private func reviewNormalizeDelimiters(_ chars: [Character]) -> [Character] {
    var out: [Character] = []
    out.reserveCapacity(chars.count)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        guard c == "\\", i + 1 < chars.count else {
            out.append(c)
            i += 1
            continue
        }
        switch chars[i + 1] {
        case "(", ")":
            out.append("$")
        case "[", "]":
            out.append("$")
            out.append("$")
        default:
            out.append(c)
            out.append(chars[i + 1])
        }
        i += 2
    }
    return out
}

// MARK: Step 5a — answer-option markers

/// Which of the three marker terminators the question is allowed to split on.
///
/// `1)` is unambiguous; `5.` and `1-` are not. "أوجد قيمة x عندما y = 5. ثم
/// احسب المشتقة" has a digit after a space and a full stop after it, which is
/// character-for-character an option marker — and splitting there cuts a
/// sentence in half. What tells the two apart is not the marker, it is the
/// SERIES: options come in twos and threes, a sentence-medial number comes
/// alone. So a terminator is enabled only once the whole question shows at
/// least two markers using it.
private struct ReviewMarkerTerminators {
    let paren: Bool
    let period: Bool
    let dash: Bool

    /// What the counting pass itself uses: everything, so it can count.
    static let all = ReviewMarkerTerminators(paren: true, period: true, dash: true)

    func allows(_ c: Character) -> Bool {
        switch c {
        case ")": return paren
        case ".": return period
        case "-": return dash
        default: return false
        }
    }
}

/// Length of an option marker starting at `j`, or `nil`.
///
/// A marker is: an optional `(`, one of `a…e` / `A…E` / `أ ب ج د هـ` / `1…5`,
/// then one of the ENABLED terminators, then whitespace or the end of the prose
/// segment. The caller checks that the position is preceded by whitespace, which
/// is what keeps `f(a)` and `\frac{a}{b}` out of it.
private func reviewOptionMarkerLength(
    _ chars: [Character],
    at j: Int,
    allowing terminators: ReviewMarkerTerminators
) -> Int? {
    let n = chars.count
    var k = j
    guard k < n else { return nil }
    if chars[k] == "(" { k += 1 }
    guard k < n else { return nil }

    let c = chars[k]
    if "abcdeABCDE12345".contains(c) {
        k += 1
    } else if "أبجده".contains(c) {
        k += 1
        // هـ is two characters: the letter and a tatweel.
        if k < n, chars[k] == "\u{0640}" { k += 1 }
    } else {
        return nil
    }

    guard k < n, terminators.allows(chars[k]) else { return nil }
    k += 1
    // The end of a prose segment counts: `a) $\frac{\pi}{4}$` puts a span there.
    if k < n, !chars[k].isWhitespace { return nil }
    return k - j
}

/// The terminators `chars` has earned, by showing two or more markers using
/// each one. Computed over the WHOLE question, never per prose segment: in
/// `$stem$\na) $x$\nb) $y$` the tokeniser hands step 5a two segments holding one
/// marker apiece, and a per-segment count would disqualify a real option list.
private func reviewMarkerTerminators(_ chars: [Character]) -> ReviewMarkerTerminators {
    var paren = 0
    var period = 0
    var dash = 0
    var i = 0
    while i < chars.count {
        if chars[i] == "\\", i + 1 < chars.count { i += 2; continue }
        let boundary = (i == 0) || chars[i - 1].isWhitespace
        if boundary, let length = reviewOptionMarkerLength(chars, at: i, allowing: .all) {
            // `length` ends one past the terminator, which is therefore its
            // last character.
            switch chars[i + length - 1] {
            case ")": paren += 1
            case ".": period += 1
            case "-": dash += 1
            default: break
            }
            i += length
            continue
        }
        i += 1
    }
    return ReviewMarkerTerminators(paren: paren >= 2, period: period >= 2, dash: dash >= 2)
}

/// True when a marker sits anywhere at a whitespace boundary. Used by step 3 to
/// tell a whole-question span apart from an ordinary display formula.
private func reviewContainsOptionMarker(
    _ chars: [Character],
    allowing terminators: ReviewMarkerTerminators
) -> Bool {
    var i = 0
    while i < chars.count {
        if chars[i] == "\\", i + 1 < chars.count { i += 2; continue }
        let boundary = (i == 0) || chars[i - 1].isWhitespace
        if boundary, reviewOptionMarkerLength(chars, at: i, allowing: terminators) != nil {
            return true
        }
        i += 1
    }
    return false
}

// MARK: Step 3 — unwrap a damaged span

/// Index of a closing `$` that may sit on a LATER line than its opener.
///
/// Deliberately looser than `reviewFindCloser`: this is the only place that
/// wants to SEE the spans neither renderer can honour, so it can take them
/// apart. Everywhere else an inline span still has to close on its own line.
private func reviewFindLooseCloser(_ chars: [Character], from: Int) -> Int? {
    var i = from
    let n = chars.count
    while i < n {
        if chars[i] == "\\", i + 1 < n { i += 2; continue }
        if chars[i] == "$" { return i }
        i += 1
    }
    return nil
}

/// Card 2 in the bug report: the model opened one `$` before the stem and closed
/// it after the last option, so KaTeX typeset the entire question as a single
/// formula and the markers became italics inside it. Undo that before anything
/// else looks at the string.
///
/// Every inline span is examined, not only one that happens to be the entire
/// trimmed string — four words of Arabic in front of the opening `$`, or a
/// single full stop after the closing one, is the same defect and used to walk
/// straight past the guard. The test is what is INSIDE the dollars:
///
///  * an option marker — the span swallowed the answers, so it is a
///    whole-question wrap and both delimiters go;
///  * a newline — no renderer this app ships honours it. `maskMath`'s inline
///    branch is `\$[^$\n]+?\$` on both the screen and in `print.html`, so such a
///    span is never typeset anyway; unwrapping lets step 5b re-wrap the real
///    formulas on each line, which is strictly more than KaTeX would have done.
///
/// Anything else is a legitimate span and is copied through byte-for-byte.
private func reviewUnwrapDamagedSpans(_ chars: [Character]) -> [Character] {
    guard chars.contains("$") else { return chars }
    let terminators = reviewMarkerTerminators(chars)

    var out: [Character] = []
    out.reserveCapacity(chars.count)
    var i = 0
    let n = chars.count

    while i < n {
        let c = chars[i]
        if c == "\\", i + 1 < n {
            out.append(c)
            out.append(chars[i + 1])
            i += 2
            continue
        }
        guard c == "$" else {
            out.append(c)
            i += 1
            continue
        }

        // A `$$…$$` block is allowed to cross lines and is left alone.
        if i + 1 < n, chars[i + 1] == "$" {
            if let close = reviewFindCloser(chars, from: i + 2, display: true) {
                out.append(contentsOf: chars[i..<(close + 2)])
                i = close + 2
                continue
            }
            out.append(c)
            i += 1
            continue
        }

        if let close = reviewFindLooseCloser(chars, from: i + 1) {
            let interior = Array(chars[(i + 1)..<close])
            if interior.contains("\n") || reviewContainsOptionMarker(interior, allowing: terminators) {
                out.append(contentsOf: interior)
            } else {
                out.append(contentsOf: chars[i..<(close + 1)])
            }
            i = close + 1
            continue
        }

        // An unpairable `$`. Left exactly where it is — step 5b sees it and
        // stops wrapping rather than adding a second delimiter beside it.
        out.append(c)
        i += 1
    }
    return out
}

// MARK: Step 4 — tokenising

private struct ReviewSegment {
    /// `false` for everything outside the delimiters — steps 5a and 5b touch
    /// only those. `true` for a complete span, delimiters included, copied
    /// through byte-for-byte apart from step 5c.
    let isSpan: Bool
    let body: [Character]
    /// Where this segment starts in the string the tokeniser was given, so a
    /// caller can map a position inside it back without searching.
    let offset: Int
}

/// Index of the closing delimiter, or `nil` when there is none.
///
/// An INLINE span must close on the line it opened on: that is what makes a lone
/// `$` in "السعر $50 فقط" a currency sign rather than the start of a formula
/// that swallows the rest of the question, and it is what keeps this function's
/// output matching `maskMath`'s inline branch, `\$[^$\n]+?\$`. A DISPLAY span
/// may cross lines, because `maskMath`'s display branch and KaTeX's auto-render
/// both let it — and a `$$…$$` block cut in half here would leave a stray `$` in
/// the output.
private func reviewFindCloser(_ chars: [Character], from: Int, display: Bool) -> Int? {
    var i = from
    let n = chars.count
    while i < n {
        let c = chars[i]
        if c == "\n" && !display { return nil }
        if c == "\\", i + 1 < n { i += 2; continue }
        if c == "$" {
            guard display else { return i }
            if i + 1 < n, chars[i + 1] == "$" { return i }
            i += 1
            continue
        }
        i += 1
    }
    return nil
}

private func reviewTokenize(_ chars: [Character]) -> [ReviewSegment] {
    var segments: [ReviewSegment] = []
    var prose: [Character] = []
    var proseStart = 0
    var i = 0
    let n = chars.count

    while i < n {
        let c = chars[i]
        if c == "\\", i + 1 < n {
            if prose.isEmpty { proseStart = i }
            prose.append(c)
            prose.append(chars[i + 1])
            i += 2
            continue
        }
        if c == "$" {
            let display = (i + 1 < n && chars[i + 1] == "$")
            let openLength = display ? 2 : 1
            if let close = reviewFindCloser(chars, from: i + openLength, display: display) {
                if !prose.isEmpty {
                    segments.append(ReviewSegment(isSpan: false, body: prose, offset: proseStart))
                    prose = []
                }
                segments.append(ReviewSegment(
                    isSpan: true,
                    body: Array(chars[i..<(close + openLength)]),
                    offset: i))
                i = close + openLength
                proseStart = i
                continue
            }
        }
        if prose.isEmpty { proseStart = i }
        prose.append(c)
        i += 1
    }

    if !prose.isEmpty {
        segments.append(ReviewSegment(isSpan: false, body: prose, offset: proseStart))
    }
    return segments
}

// MARK: Step 5a — one option per line

/// True when nothing but horizontal whitespace separates the tail of `out` from
/// a line break. `fallback` answers the question for an empty buffer.
private func reviewEndsAtLineStart(_ out: [Character], fallback: Bool) -> Bool {
    var i = out.count - 1
    while i >= 0 {
        let c = out[i]
        if c == "\n" { return true }
        if c == " " || c == "\t" {
            i -= 1
            continue
        }
        return false
    }
    return fallback
}

private func reviewSplitOptions(
    _ body: [Character],
    atLineStart: Bool,
    allowing terminators: ReviewMarkerTerminators
) -> [Character] {
    var out: [Character] = []
    out.reserveCapacity(body.count + 8)
    var i = 0
    let n = body.count

    while i < n {
        let c = body[i]
        // An escape travels as a pair, so `\)` can never be read as a marker.
        if c == "\\", i + 1 < n {
            out.append(c)
            out.append(body[i + 1])
            i += 2
            continue
        }
        let boundary = (i == 0) || body[i - 1].isWhitespace
        if boundary, let length = reviewOptionMarkerLength(body, at: i, allowing: terminators) {
            if !reviewEndsAtLineStart(out, fallback: atLineStart) {
                while let last = out.last, last == " " || last == "\t" { out.removeLast() }
                out.append("\n")
            }
            out.append(contentsOf: body[i..<(i + length)])
            i += length
            continue
        }
        out.append(c)
        i += 1
    }
    return out
}

// MARK: Step 5b — wrapping bare LaTeX

/// LaTeX commands that are meaningless without an argument. `\alpha` alone is a
/// formula and should be wrapped; `\frac` alone is `ParseError: Expected group`,
/// which KaTeX paints as a red box — and `.katex-error` carries no `.katex`
/// class, so it is not covered by the `unicode-bidi: isolate` rule in math.html
/// and gets bidi-reordered inside an Arabic card on top of being wrong.
private let reviewArgumentCommands: Set<String> = [
    "frac", "dfrac", "tfrac", "cfrac", "binom", "dbinom", "tbinom",
    "sqrt", "root", "overline", "underline", "overrightarrow", "overleftarrow",
    "vec", "hat", "bar", "tilde", "dot", "ddot", "widehat", "widetilde",
    "text", "textbf", "textit", "textrm", "mathbb", "mathbf", "mathrm",
    "mathcal", "mathfrak", "mathit", "mathsf", "mathtt", "operatorname",
    "left", "right", "begin", "end", "overset", "underset", "stackrel",
    "boxed", "color", "textcolor", "substack", "xrightarrow", "xleftarrow", "not"
]

/// True when the ASCII letters ending at `i` are the name of a control
/// sequence — i.e. walking back over them lands on a backslash.
private func reviewEndsControlSequence(_ body: [Character], before i: Int, limit: Int) -> Bool {
    var k = i - 1
    while k >= limit, reviewIsASCIILetter(body[k]) { k -= 1 }
    return k >= limit && k < i - 1 && body[k] == "\\"
}

/// Whether a run is worth handing to KaTeX at all.
///
/// Step 5b's promise is that a card either shows typeset maths or shows the
/// source it was given. A run KaTeX rejects breaks both halves: the student
/// loses the text AND gets a red error. These are the three shapes the forward
/// scan can legitimately produce that KaTeX cannot parse.
private func reviewIsRenderableRun(_ body: [Character], _ range: Range<Int>) -> Bool {
    let run = Array(body[range])
    guard let last = run.last else { return false }

    // `أوجد قيمة x^ ثم y` → `x^`, `احسب V_الكلي` → `V_`: a script with nothing
    // to raise. A trailing lone `\` is the same class.
    if last == "^" || last == "_" || last == "\\" { return false }

    // `أكمل: x___` → `x___`: "Double subscript".
    var k = 0
    while k + 1 < run.count {
        let a = run[k]
        let b = run[k + 1]
        if (a == "^" || a == "_") && (b == "^" || b == "_") { return false }
        k += 1
    }

    // A bare `\frac` / `\sqrt` / `\left` whose argument the scan could not
    // reach. `\alpha`, `\pi`, `\int`, `\sum` are complete on their own and stay.
    if run.first == "\\", run.dropFirst().allSatisfy(reviewIsASCIILetter) {
        if reviewArgumentCommands.contains(String(run.dropFirst())) { return false }
    }
    return true
}

/// Extent of a maths run whose trigger is at `trigger`, or `nil` when it cannot
/// be wrapped safely.
///
/// `backward` is set for a `^` / `_` trigger, where the base of the exponent is
/// behind it: `sin^{-1}(…)` has to open its span before `sin`, not after it.
/// `limit` is the first index the backward walk may reach — never inside a run
/// that has already been wrapped.
private func reviewMathRun(
    _ body: [Character],
    trigger: Int,
    backward: Bool,
    limit: Int
) -> Range<Int>? {
    let n = body.count
    var start = trigger

    if backward {
        var k = trigger - 1
        if k >= limit, body[k] == ")" || body[k] == "}" {
            let close = body[k]
            let open: Character = (close == ")") ? "(" : "{"
            var depth = 0
            var j = k
            var opened = -1
            while j >= limit {
                if body[j] == close {
                    depth += 1
                } else if body[j] == open {
                    depth -= 1
                    if depth == 0 { opened = j; break }
                }
                j -= 1
            }
            if opened >= 0 { k = opened - 1 }
        }
        while k >= limit, reviewIsASCIIAlnum(body[k]) { k -= 1 }
        start = max(k + 1, limit)
    }
    guard start <= trigger else { return nil }

    var end = start
    var braces = 0
    var parens = 0
    var brackets = 0
    var i = start

    forward: while i < n {
        let c = body[i]
        if c == "\n" || c == "?" || c == "؟" || c == "$" { break }
        // A non-ASCII letter is prose, in any script. Arabic-Indic digits are
        // not letters and are allowed through — step 5c converts them.
        if c.isLetter && !c.isASCII { break }

        switch c {
        case "\\":
            guard i + 1 < n else { break forward }
            // `\(` `\)` `\[` `\]` are delimiters, not content. Step 2 has
            // already rewritten them for the renderer, but the editor asks for
            // these runs against the UNnormalised field text, where a run that
            // swallowed a closing `\)` would hand the keypad a stray delimiter.
            if "()[]".contains(body[i + 1]) { break forward }
            if reviewIsASCIILetter(body[i + 1]) {
                var j = i + 1
                while j < n, reviewIsASCIILetter(body[j]) { j += 1 }
                i = j
                end = i
                continue
            }
            // `\,` `\{` `\}` `\\` and the rest of the single-character escapes.
            i += 2
            end = i
            continue
        case "{":
            braces += 1
        case "}":
            if braces == 0 { break forward }
            braces -= 1
        case "(":
            parens += 1
        case ")":
            if parens == 0 { break forward }
            parens -= 1
        case "[":
            brackets += 1
        case "]":
            if brackets == 0 { break forward }
            brackets -= 1
        case " ", "\t":
            if braces > 0 || parens > 0 || brackets > 0 {
                i += 1
                end = i
                continue
            }
            // Outside every group a space belongs to the formula only when an
            // operator, a digit or a command sits on one side of it — "x = 2",
            // "\int_0^1 x", "\frac{1}{2} \times 3". A space with a plain letter
            // on both sides is the gap between two words.
            var j = i
            while j < n, body[j] == " " || body[j] == "\t" { j += 1 }
            guard j < n, i > start else { break forward }
            let before = body[i - 1]
            let after = body[j]
            // `\frac {1}{2}` and `\sqrt (x+1)`: a command followed by its
            // argument group, with the space TeX itself ignores. Without this
            // the run ends on the bare command name and step 5b ships `$\frac$`
            // — a red KaTeX error where readable source stood.
            let argumentFollowsCommand =
                (after == "{" || after == "(" || after == "[")
                && reviewIsASCIILetter(before)
                && reviewEndsControlSequence(body, before: i, limit: start)
            let joins =
                reviewMathOperators.contains(before)
                || (before.isASCII && before.isNumber)
                || reviewMathOperators.contains(after)
                || (after.isASCII && after.isNumber)
                || (after == "\\" && j + 1 < n && reviewIsASCIILetter(body[j + 1]))
                || argumentFollowsCommand
            guard
                joins,
                !(after.isLetter && !after.isASCII),
                reviewIsMathChar(before) || before == "\\",
                reviewIsMathChar(after)
            else { break forward }
            i = j
            continue
        default:
            guard reviewIsMathChar(c) else { break forward }
        }
        i += 1
        end = i
    }

    // Raw text on screen beats a red KaTeX error, and an unbalanced brace is a
    // guaranteed red error.
    guard braces == 0 else { return nil }

    while end > start {
        let last = body[end - 1]
        if last.isWhitespace || last == "." || last == "," || last == ";" || last == ":" {
            end -= 1
            continue
        }
        break
    }
    guard end > start, end > trigger else { return nil }
    guard reviewIsRenderableRun(body, start..<end) else { return nil }
    return start..<end
}

private func reviewWrapBareLatex(_ body: [Character]) -> [Character] {
    var out: [Character] = []
    out.reserveCapacity(body.count + 16)
    var i = 0
    // First index a backward walk may reach: never into an already-wrapped run.
    var limit = 0
    let n = body.count

    while i < n {
        let c = body[i]

        if c == "\\", i + 1 < n, reviewIsASCIILetter(body[i + 1]) {
            if let run = reviewMathRun(body, trigger: i, backward: false, limit: limit) {
                out.append("$")
                out.append(contentsOf: reviewWesternDigits(Array(body[run])))
                out.append("$")
                i = run.upperBound
                limit = run.upperBound
                continue
            }
            out.append(c)
            out.append(body[i + 1])
            i += 2
            continue
        }

        if c == "^" || c == "_", i > 0, reviewIsRunAnchor(body[i - 1]),
           let run = reviewMathRun(body, trigger: i, backward: true, limit: limit),
           i - run.lowerBound <= out.count {
            out.removeLast(i - run.lowerBound)
            out.append("$")
            out.append(contentsOf: reviewWesternDigits(Array(body[run])))
            out.append("$")
            i = run.upperBound
            limit = run.upperBound
            continue
        }

        out.append(c)
        i += 1
    }
    return out
}

// MARK: Step 6 — hard breaks

/// `marked` runs with CommonMark defaults on every surface this app shares with
/// the chat and the exported PDF, so a single newline is a SOFT break and the
/// options come out on one line. Two trailing spaces is the hard break, applied
/// here rather than by flipping `breaks: true` in `math.html` — that page is
/// shared with the tutor's own answers.
private func reviewHardBreaks(_ chars: [Character]) -> [Character] {
    var out: [Character] = []
    out.reserveCapacity(chars.count + 16)

    // Span-aware, so a `$$…$$` block that legitimately runs over two lines is
    // copied through rather than having two spaces and a CommonMark escape
    // pushed into the middle of its LaTeX.
    for segment in reviewTokenize(chars) {
        guard !segment.isSpan else {
            out.append(contentsOf: segment.body)
            continue
        }
        reviewAppendWithHardBreaks(segment.body, into: &out)
    }
    return out
}

private func reviewAppendWithHardBreaks(_ body: [Character], into out: inout [Character]) {
    var i = 0
    let n = body.count

    while i < n {
        let c = body[i]
        guard c == "\n" else {
            out.append(c)
            i += 1
            continue
        }

        while let last = out.last, last == " " || last == "\t" { out.removeLast() }
        if let last = out.last, last != "\n" {
            out.append(" ")
            out.append(" ")
        }
        out.append("\n")
        i += 1

        // `1)` at the head of a line is an ordered list to CommonMark, which
        // renumbers it — option c) of question 3 would be printed as "1.".
        // Escaping the delimiter keeps the marker as the sheet wrote it.
        var j = i
        var digits: [Character] = []
        while j < n, body[j].isASCII, body[j].isNumber {
            digits.append(body[j])
            j += 1
        }
        if !digits.isEmpty, j < n, body[j] == ")" || body[j] == "." {
            out.append(contentsOf: digits)
            out.append("\\")
            out.append(body[j])
            i = j + 1
        }
    }
}

// MARK: The normaliser

/// True when a `$` survives in prose that the tokeniser could not pair.
///
/// This is the veto on step 5b. Both renderers pair dollars positionally and
/// neither counts: `maskMath` is `\$[^$\n]+?\$` and KaTeX's auto-render walks
/// left to right. So a wrapper dollar added ANYWHERE in a string that already
/// carries an odd one pairs with the stray rather than with its own partner —
/// `السعر $50 ثم احسب \frac{1}{2}` becomes `…$50 ثم احسب $\frac{1}{2}$`, KaTeX
/// is handed `$50 ثم احسب $` and paints a red error, and the fraction is
/// printed as raw source beside it. Leaving the string alone costs nothing: it
/// then fails `containsMath` and the card is the readable plain text it was
/// before this file existed.
private func reviewHasStrayDollar(_ segments: [ReviewSegment]) -> Bool {
    for segment in segments where !segment.isSpan {
        var i = 0
        let body = segment.body
        while i < body.count {
            if body[i] == "\\", i + 1 < body.count { i += 2; continue }
            if body[i] == "$" { return true }
            i += 1
        }
    }
    return false
}

/// Turns one extracted question into markdown the chat's renderer can typeset.
///
/// Six ordered steps, the same order and the same result as the Kotlin twin:
/// line endings, alternative delimiters, unwrap a damaged span, tokenise,
/// per-prose option splitting and bare-LaTeX wrapping (plus Arabic-Indic digits
/// inside spans), hard breaks.
///
/// **Invariant the rest of the design relies on:** no INLINE `$…$` span this
/// produces ever contains a newline. That is what keeps `maskMath`'s inline
/// branch — `\$[^$\n]+?\$` — matching exactly what KaTeX's auto-render will
/// later match. Do not widen that regex. A `$$…$$` block may cross lines, which
/// `maskMath`'s display branch already allows, and step 6 copies those through
/// untouched rather than pushing a hard break into their LaTeX.
///
/// **Second invariant:** this never increases the number of unpairable `$` in
/// the string. Step 3 removes the ones it can account for and
/// `reviewHasStrayDollar` switches step 5b off when any remain.
func reviewMarkdown(_ raw: String) -> String {
    guard !raw.isEmpty else { return raw }

    let unified = raw
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")

    let normalized = reviewUnwrapDamagedSpans(reviewNormalizeDelimiters(Array(unified)))
    let terminators = reviewMarkerTerminators(normalized)
    let segments = reviewTokenize(normalized)
    let mayWrap = !reviewHasStrayDollar(segments)

    var assembled: [Character] = []
    assembled.reserveCapacity(normalized.count + 32)

    for segment in segments {
        if segment.isSpan {
            assembled.append(contentsOf: reviewWesternDigits(segment.body))
            continue
        }
        let atLineStart = reviewEndsAtLineStart(assembled, fallback: true)
        let split = reviewSplitOptions(
            segment.body, atLineStart: atLineStart, allowing: terminators)
        if split.first == "\n" {
            while let last = assembled.last, last == " " || last == "\t" {
                assembled.removeLast()
            }
        }
        assembled.append(contentsOf: mayWrap ? reviewWrapBareLatex(split) : split)
    }

    let result = String(reviewHardBreaks(assembled))
    // Never a blank card. If the scan somehow ate the question, the student sees
    // the raw text — which is what they saw before this function existed.
    if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return raw
    }
    return result
}

/// The same normalised question with the two artefacts that mean something only
/// to a markdown parser taken back out.
///
/// `reviewMarkdown`'s output is markdown, and every surface that renders it is a
/// markdown surface EXCEPT the cheap `Text` branch each card falls to when the
/// question turned out to hold no maths. `marked` prints `1\)` as `1)`; SwiftUI's
/// `Text(_: String)` prints it as `1\)`, so a prose-only multiple-choice card —
/// the one kind that had nothing wrong with it — grew a backslash on every
/// option. Two trailing spaces are the CommonMark hard break and are invisible
/// in a `Text`, but they are dropped here too so the two branches agree
/// character for character.
///
/// Reverses exactly what step 6 inserts and nothing else: a line-leading run of
/// digits, a backslash, and `)` or `.`. Step 2 has already turned every real
/// `\)` in the source into a `$`, so there is nothing else this can hit.
func reviewPlainText(_ rendered: String) -> String {
    guard !rendered.isEmpty else { return rendered }
    let chars = Array(rendered)
    var out: [Character] = []
    out.reserveCapacity(chars.count)
    var i = 0
    let n = chars.count
    var atLineStart = true

    while i < n {
        if atLineStart {
            var j = i
            while j < n, chars[j].isASCII, chars[j].isNumber { j += 1 }
            if j > i, j + 1 < n, chars[j] == "\\", chars[j + 1] == ")" || chars[j + 1] == "." {
                out.append(contentsOf: chars[i..<j])
                out.append(chars[j + 1])
                i = j + 2
                atLineStart = false
                continue
            }
        }
        let c = chars[i]
        if c == "\n" {
            while let last = out.last, last == " " || last == "\t" { out.removeLast() }
            out.append("\n")
            atLineStart = true
        } else {
            out.append(c)
            atLineStart = false
        }
        i += 1
    }
    while let last = out.last, last == " " || last == "\t" { out.removeLast() }
    return String(out)
}

// MARK: - What the editor's formula chips are built from
//
// Both of these return CHARACTER OFFSETS, not `String.Index`. The editor holds
// a range across the presentation of a modal sheet, and an index taken from one
// value of a `String` and applied to another is undefined; an offset is not.

/// Every `$…$` / `$$…$$` span in `text`, delimiters included.
///
/// Recomputed at the moment a chip is tapped — never stored when the sheet
/// opened, because the student may have edited the prose in between and every
/// later range would have moved.
func reviewMathSpans(_ text: String) -> [Range<Int>] {
    let chars = Array(text)
    var ranges: [Range<Int>] = []
    var i = 0
    let n = chars.count

    while i < n {
        let c = chars[i]
        if c == "\\", i + 1 < n { i += 2; continue }
        if c == "$" {
            let display = (i + 1 < n && chars[i + 1] == "$")
            let openLength = display ? 2 : 1
            if let close = reviewFindCloser(chars, from: i + openLength, display: display) {
                ranges.append(i..<(close + openLength))
                i = close + openLength
                continue
            }
        }
        i += 1
    }
    return ranges
}

/// Every bare-LaTeX run `reviewMarkdown` would wrap but that the text has not
/// delimited itself.
///
/// This is what lets the keypad reach an undelimited question — the exact case
/// that put a raw `\frac{\sqrt{2}}{2}` on a student's screen. Delimiting one run
/// shifts every offset after it, so the caller rewrites the field and asks
/// again rather than trusting a second range from the same list.
func reviewBareLatexRuns(_ text: String) -> [Range<Int>] {
    let chars = Array(text)
    var found: [Range<Int>] = []

    for segment in reviewTokenize(chars) where !segment.isSpan {
        let body = segment.body
        let offset = segment.offset
        var i = 0
        var limit = 0
        while i < body.count {
            let c = body[i]
            if c == "\\", i + 1 < body.count, reviewIsASCIILetter(body[i + 1]) {
                if let run = reviewMathRun(body, trigger: i, backward: false, limit: limit) {
                    found.append((offset + run.lowerBound)..<(offset + run.upperBound))
                    limit = run.upperBound
                    i = run.upperBound
                    continue
                }
                i += 2
                continue
            }
            if c == "^" || c == "_", i > 0, reviewIsRunAnchor(body[i - 1]),
               let run = reviewMathRun(body, trigger: i, backward: true, limit: limit) {
                found.append((offset + run.lowerBound)..<(offset + run.upperBound))
                limit = run.upperBound
                i = run.upperBound
                continue
            }
            i += 1
        }
    }
    return found
}
