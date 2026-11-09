import SwiftUI
import UIKit
import WebKit

/// Identifiable wrapper so the captcha site key can drive `.sheet(item:)`.
struct CaptchaSiteKey: Identifiable, Equatable {
    let value: String
    var id: String { value }
    init(_ value: String) { self.value = value }
}

/// Bottom-sheet wrapper that renders a Cloudflare Turnstile widget in a
/// WKWebView and bridges the resulting token back to SwiftUI.
///
/// The widget is loaded from the backend's `/captcha.html` page (not
/// inline HTML) so the hostname Cloudflare sees during validation matches
/// the domain registered in the Turnstile dashboard. The page posts the
/// solved token via `window.webkit.messageHandlers.captcha.postMessage(token)`.
struct TurnstileSheet: View {
    let siteKey: String
    /// Called with the solved token on success, or `nil` if the user
    /// closed the sheet without solving (or the widget errored).
    let onComplete: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var didDeliverToken = false
    @State private var diagnostics: [String] = []

    // Theming note: this sheet is only ever presented from `LoginView`, so it
    // borrows the auth token set rather than defining a third palette. Keeping
    // it on `Color.black` would slam a near-opaque black modal over the cream
    // sign-in screen — and the Turnstile widget inside renders its own LIGHT
    // card, so the sheet would show three polarities at once.
    var body: some View {
        ZStack {
            // 0.85 preserved: over the black dark-mode page this is the exact
            // same wash as before; in light it reads as the cream page.
            AuthFigmaColors.bg.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button {
                        finish(with: nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(AuthFigmaColors.textPrimary.opacity(0.7))
                    }
                    .padding(.top, 8)
                    .padding(.trailing, 16)
                }
                Spacer()
                TurnstileWebView(
                    siteKey: siteKey,
                    onToken: { token in finish(with: token.isEmpty ? nil : token) },
                    onDiagnostic: { line in diagnostics.append(line) }
                )
                .frame(height: 460)
                .padding(.horizontal, 16)
                Text(L10n.turnstileVerifying)
                    .font(.system(size: 14))
                    .foregroundColor(AuthFigmaColors.textPrimary.opacity(0.7))
                if !diagnostics.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(diagnostics.indices, id: \.self) { i in
                                Text(diagnostics[i])
                                    .font(.system(size: 11, design: .monospaced))
                                    // Dark keeps the #FF9F0A `.orange` already
                                    // resolved to; on cream that amber is 2.1:1,
                                    // so light drops down the same hue ramp.
                                    .foregroundColor(Self.diagnosticsInk)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 200)
                    .background(Self.diagnosticsBg)
                    .padding(.horizontal, 16)
                }
                Spacer()
            }
        }
        .interactiveDismissDisabled(false)
        .onDisappear {
            // Treat sheet dismissal as cancellation if we never delivered.
            if !didDeliverToken { onComplete(nil) }
        }
    }

    /// Console panel behind the injected `console.*` output. Dark keeps the 50%
    /// black wash (which composites to pure black over the sheet canvas); on
    /// cream that same wash is a mid-grey slab that drops the warning text under
    /// 3:1, so light uses a real raised surface instead.
    private static let diagnosticsBg = adaptive(
        light: UIColor(red: 0xE8 / 255.0, green: 0xDD / 255.0, blue: 0xCA / 255.0, alpha: 1),
        dark:  UIColor(white: 0, alpha: 0.5))

    /// Diagnostic (console) text. #9A5B00 reads 4.8:1 on the light panel.
    private static let diagnosticsInk = adaptive(
        light: UIColor(red: 0x9A / 255.0, green: 0x5B / 255.0, blue: 0x00 / 255.0, alpha: 1),
        dark:  UIColor(red: 0xFF / 255.0, green: 0x9F / 255.0, blue: 0x0A / 255.0, alpha: 1))

    /// Local twin of the palette helpers elsewhere: resolves through the active
    /// `UITraitCollection`, which follows `.preferredColorScheme`.
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private func finish(with token: String?) {
        guard !didDeliverToken else { return }
        didDeliverToken = true
        onComplete(token)
        dismiss()
    }
}

private struct TurnstileWebView: UIViewRepresentable {
    let siteKey: String
    let onToken: (String) -> Void
    let onDiagnostic: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToken: onToken, onDiagnostic: onDiagnostic)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "captcha")
        userContent.add(context.coordinator, name: "diag")
        // Forward console.log / console.error from inside the WebView to
        // Swift so we can see what Turnstile is complaining about. Without
        // this the widget fails silently inside a WKWebView.
        let consoleHook = """
        (function () {
          function ship(level, args) {
            try {
              var msg = Array.prototype.map.call(args, function (a) {
                try { return typeof a === 'string' ? a : JSON.stringify(a); }
                catch (e) { return String(a); }
              }).join(' ');
              window.webkit.messageHandlers.diag.postMessage('[' + level + '] ' + msg);
            } catch (e) {}
          }
          ['log', 'warn', 'error', 'info'].forEach(function (lvl) {
            var orig = console[lvl];
            console[lvl] = function () { ship(lvl, arguments); orig.apply(console, arguments); };
          });
          window.addEventListener('error', function (e) {
            ship('uncaught', [e.message + ' @ ' + (e.filename || '?') + ':' + e.lineno]);
          });
          window.addEventListener('unhandledrejection', function (e) {
            ship('reject', [String(e.reason)]);
          });
        })();
        """
        userContent.addUserScript(WKUserScript(
            source: consoleHook,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false))
        config.userContentController = userContent
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // Turnstile's iframe (challenges.cloudflare.com) is third-party to
        // our backend host. Without a persistent data store the iframe can't
        // set the cookies it needs to track the challenge — use the default
        // persistent store rather than a non-persistent one.
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        // Left transparent deliberately: the sheet canvas behind it is now
        // theme-aware, so the widget composites onto the correct polarity in
        // both schemes. The remaining half of this — `/captcha.html`'s own
        // `color-scheme` and Turnstile's `theme` param — lives in the backend
        // repo and cannot be fixed from here.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.navigationDelegate = context.coordinator

        // Spoof a real Mobile Safari UA. WKWebView's default UA is missing
        // the "Version/X Safari/Y" segment, which Cloudflare's bot detection
        // reads as "automation" and refuses to render the interactive
        // challenge — the widget then hangs forever on "Verifying...".
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/18.5 Mobile/15E148 Safari/604.1"

        // Load /captcha.html from the backend so Turnstile sees the backend
        // hostname (which must be registered in the Cloudflare dashboard).
        let url = APIClient.publicBaseURL.appendingPathComponent("captcha.html")
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onToken: (String) -> Void
        let onDiagnostic: (String) -> Void
        init(onToken: @escaping (String) -> Void, onDiagnostic: @escaping (String) -> Void) {
            self.onToken = onToken
            self.onDiagnostic = onDiagnostic
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "captcha" {
                let token = (message.body as? String) ?? ""
                DispatchQueue.main.async { self.onToken(token) }
            } else if message.name == "diag", let line = message.body as? String {
                DispatchQueue.main.async { self.onDiagnostic(line) }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onDiagnostic("nav-fail: \(error.localizedDescription)")
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onDiagnostic("nav-fail: \(error.localizedDescription)")
        }
    }
}
