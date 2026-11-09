import SwiftUI
import WebKit

/// Renders assistant messages as markdown + KaTeX via a local WKWebView.
///
/// All assets (katex.min.js, auto-render.min.js, marked.min.js, KaTeX fonts)
/// are bundled inside Resources/math/ so the view works fully offline.
/// The WebView loads math.html once and then the Swift side injects the
/// markdown string via `droobRender(src)`, keeping re-renders cheap.
struct MathMarkdownView: UIViewRepresentable {
    let markdown: String
    let textColor: UIColor
    let backgroundColor: UIColor
    /// Base direction of the *prose*. `math.html` declares none, so without
    /// this the paragraph runs at bidi level 0 and an Arabic sentence with a
    /// formula in it — "أوجد قيمة $x$ إذا كان $2x+3=11$" — is reordered
    /// back-to-front and left-aligned, while the prose-only card beside it is
    /// right-aligned by the app's own layout direction. The formulas
    /// themselves stay LTR either way: `.katex` is `unicode-bidi: isolate`.
    ///
    /// Defaulted so the call sites that are always LTR need not say so.
    var isRTL: Bool = false
    @Binding var contentHeight: CGFloat
    /// Set to `true` when this view can no longer render and the caller must
    /// show the source as plain text instead.
    ///
    /// A WKWebView is a whole web content process. One per chat bubble was
    /// affordable; the review sheet puts one on every maths card of a
    /// 29-question worksheet, and WebKit jettisons content processes under
    /// memory pressure. Without this the page never comes back: `pageReady`
    /// stays false, no render is retried, and the card is a permanently blank
    /// strip on the one screen whose job is to let the student correct the scan
    /// before spending it. Cleared again if the reload succeeds.
    ///
    /// Optional so the call sites that have no fallback need not say so.
    var renderFailed: Binding<Bool>?
    /// Read purely so a light/dark flip invalidates this representable: the
    /// colours above are dynamic UIColors whose *values* change without the
    /// `markdown` string changing at all.
    @Environment(\.colorScheme) private var colorScheme

    /// `dir` value the page body is given.
    var direction: String { isRTL ? "rtl" : "ltr" }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

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
        // The rendered body carries its colours as an inline hex style, so a
        // scheme change has to re-render even though the markdown is
        // identical — otherwise the SwiftUI card flips at sunset and the
        // KaTeX body keeps the stale hex (near-black ink on a dark card).
        let traits = UITraitCollection(
            userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let resolvedText = textColor.resolvedColor(with: traits)
        let resolvedBackground = backgroundColor.resolvedColor(with: traits)
        let colorsChanged = coord.appliedTextColor != resolvedText
            || coord.appliedBackgroundColor != resolvedBackground
        let directionChanged = coord.appliedDirection != direction

        if coord.pendingMarkdown != markdown || !coord.initialRenderDone
            || colorsChanged || directionChanged {
            coord.pendingMarkdown = markdown
            coord.appliedDirection = direction
            coord.applyColors(textColor: resolvedText, backgroundColor: resolvedBackground)
            if coord.pageReady {
                coord.render(in: webView)
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let parent: MathMarkdownView
        var pendingMarkdown: String = ""
        var pageReady = false
        var initialRenderDone = false
        /// Colours the body was last given, already resolved for a concrete
        /// trait — kept so `updateUIView` can tell a scheme flip apart from
        /// a no-op update.
        private(set) var appliedTextColor: UIColor = .label
        private(set) var appliedBackgroundColor: UIColor = .secondarySystemBackground
        /// `dir` the body was last given. Seeded from the parent so the first
        /// render is never treated as a direction change.
        var appliedDirection: String

        init(_ parent: MathMarkdownView) {
            self.parent = parent
            self.appliedDirection = parent.direction
        }

        func applyColors(textColor: UIColor, backgroundColor: UIColor) {
            self.appliedTextColor = textColor
            self.appliedBackgroundColor = backgroundColor
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageReady = true
            reportFailure(false)
            applyColors(
                textColor: parent.textColor.resolvedColor(with: webView.traitCollection),
                backgroundColor: parent.backgroundColor.resolvedColor(with: webView.traitCollection))
            render(in: webView)
        }

        // MARK: Failure

        /// Whether the one permitted reload has already been spent, so a page
        /// whose process dies repeatedly settles on the text fallback instead
        /// of looping.
        private var reloadSpent = false

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            pageReady = false
            reportFailure(true)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            pageReady = false
            reportFailure(true)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            pageReady = false
            initialRenderDone = false
            reportFailure(true)
            // Reloading is the documented recovery from a jettisoned content
            // process. If it lands, `didFinish` re-renders and clears the flag;
            // if it does not, the caller is already showing the source.
            guard !reloadSpent else { return }
            reloadSpent = true
            webView.reload()
        }

        private func reportFailure(_ failed: Bool) {
            guard let binding = parent.renderFailed else { return }
            DispatchQueue.main.async {
                if binding.wrappedValue != failed { binding.wrappedValue = failed }
            }
        }

        func render(in webView: WKWebView) {
            let fg = appliedTextColor.hexString
            let bg = appliedBackgroundColor.hexString
            let src = pendingMarkdown
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")

            // Base direction of the prose. Set before the render so the very
            // first layout is already correct — a reflow after KaTeX has laid
            // out would report a stale height.
            let js = """
            document.body.style.color = '\(fg)';
            document.body.style.background = '\(bg)';
            document.body.setAttribute('dir', '\(appliedDirection)');
            if (typeof droobRender === 'function') {
              droobRender('\(src)');
            }
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
            initialRenderDone = true
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "heightChanged" else { return }
            let h: CGFloat
            if let n = message.body as? NSNumber {
                h = CGFloat(n.doubleValue)
            } else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.contentHeight = max(20, h)
            }
        }
    }
}

private extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x",
                      Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
