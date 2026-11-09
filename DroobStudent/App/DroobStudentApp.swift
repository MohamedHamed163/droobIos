// Test comment - Telegram bot test 2026-05-30
import SwiftUI
import GoogleSignIn

@main
struct DroobStudentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authSession = AuthSession.shared
    // Observing the shared override store here means a revision bump (new
    // backend translations applied) re-evaluates the App body and re-renders
    // the whole tree — every L10n.* value is recomputed each render, so the
    // updated wording flows through without an App Store release.
    @StateObject private var localizationOverrides = LocalizationOverrides.shared
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    // Drives `.preferredColorScheme` below. The Light/Dark pill in the auth
    // chip bar and Settings write this key; until 2026-07 nothing read it, so
    // the app was pinned dark and the pill only changed its own icon.
    @AppStorage("appColorScheme") private var appColorScheme: String = AppColorSchemeDefault.code
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Before anything reads the locale — `applyInitialSemanticContent()`
        // below is the first such reader, and every `@AppStorage("appLocale")`
        // in the tree resolves later, during `body`.
        AppLocaleDefault.lockIfNeeded()
        configureGoogleSignIn()
        applyInitialSemanticContent()
    }

    /// Mirrors UIKit-backed views (UIPageViewController behind SwiftUI's
    /// `.tabViewStyle(.page)`, UITabBar, UINavigationBar) at launch so the
    /// onboarding swipe direction and splash layout match the stored locale
    /// from the very first frame. `MainTabView` refreshes this on every
    /// locale change once the user reaches the app.
    private func applyInitialSemanticContent() {
        let locale = L10n.currentLanguageCode
        let attr: UISemanticContentAttribute = locale == "ar" ? .forceRightToLeft : .forceLeftToRight
        UIView.appearance().semanticContentAttribute = attr
        UITabBar.appearance().semanticContentAttribute = attr
        UINavigationBar.appearance().semanticContentAttribute = attr
    }

    var body: some Scene {
        WindowGroup {
            // Refuse to run on macOS. "Designed for iPad" apps are listed on the
            // Mac App Store by default, and the capture protection below is iOS
            // secure-field redaction that macOS screen recording ignores — so a
            // Mac install is an unprotected copy of paid course video. Checked
            // once at launch; the value cannot change within a process.
            if ProcessInfo.processInfo.isRunningOnMac {
                MacUnsupportedView()
                    .environment(\.appLocale, appLocale)
                    .environment(\.layoutDirection, appLocale == "ar" ? .rightToLeft : .leftToRight)
                    .preferredColorScheme(appColorScheme == "light" ? .light : .dark)
            } else {
                RootView()
                    // Best-effort minimum window size on iPadOS (no-op on iPhone).
                    // Non-invasive: reads the live window's scene without owning a
                    // window, so SwiftUI keeps rendering normally.
                    .background(WindowSizeRestrictor())
                    .environmentObject(authSession)
                    .environmentObject(localizationOverrides)
                    .environment(\.appLocale, appLocale)
                    .environment(\.layoutDirection, appLocale == "ar" ? .rightToLeft : .leftToRight)
                    // Every palette in the app (MyCoursesPalette, AuthFigmaColors,
                    // the asset catalog) already resolves off the trait collection,
                    // so this one modifier is what turns light mode on everywhere.
                    .preferredColorScheme(appColorScheme == "light" ? .light : .dark)
                    // App-wide screenshot redaction: hosts the whole UI inside the
                    // secure-text-field canvas so a screenshot/capture of ANY page
                    // comes out as the "Recording not allowed" placard, not the
                    // content. Environment is applied ABOVE this, so it travels
                    // into the secure host intact. (Screen RECORDING / mirroring is
                    // already blocked app-wide by `.captureProtected()` at the root;
                    // this adds still-shot coverage everywhere, not just the video.)
                    .screenshotRedacted()
                    .onOpenURL { url in
                        print("[DeepLink] onOpenURL host=\(url.host ?? "—") path=\(url.path)")
                        if GIDSignIn.sharedInstance.handle(url) { return }
                        // `xcrun simctl openurl https://...` on the
                        // simulator (and some real-device flows) deliver
                        // Universal Links through `onOpenURL` instead of
                        // `onContinueUserActivity`. Route HTTPS URLs to the
                        // Universal-Link handler so both paths converge.
                        if url.scheme == "https" {
                            handleUniversalLink(url)
                            return
                        }
                        handleDeepLink(url)
                    }
                    // Universal-Link entry — iOS delivers `droob-sa.net/r/{slug}`
                    // taps as NSUserActivity events. We stash the slug on
                    // `AuthSession`; `RootView` consumes it once the user
                    // is authenticated and routes to the right screen.
                    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                        print("[DeepLink] onContinueUserActivity url=\(activity.webpageURL?.absoluteString ?? "nil")")
                        guard let url = activity.webpageURL else { return }
                        handleUniversalLink(url)
                    }
                    .task {
                        _ = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
                        await authSession.bootstrap()
                        PushService.shared.requestAuthorizationIfAuthenticated()
                    }
                    // Fetch DB-backed translation overrides once at launch (in
                    // parallel with auth bootstrap — this call is UNAUTHENTICATED so
                    // it works pre-login). Failures keep the bundled baseline.
                    .task {
                        await LocalizationOverrides.shared.refresh()
                    }
                    // Screen-capture policy is set centrally by an admin, not by the
                    // user. Fetched here (unauthenticated, so it works pre-login) and
                    // cached; until it lands the app stays fail-closed.
                    .task {
                        await RemoteAppConfig.refresh()
                    }
                    // Foreground heartbeat — every return to .active pings the
                    // backend so "last active" stays fresh, and re-fetches the
                    // translation overrides so wording changes land without a
                    // relaunch. Fire-and-forget: failures are silently ignored and
                    // never surface to the UI.
                    .onChange(of: scenePhase) { phase in
                        guard phase == .active else { return }
                        sendForegroundPing()
                        Task { await LocalizationOverrides.shared.refresh() }
                        Task { await RemoteAppConfig.refresh() }
                    }
            }
        }
    }

    /// POST /v1/auth/ping — authenticated no-body heartbeat. Skipped when no
    /// session exists (guest / logged out); errors are swallowed because the
    /// ping is best-effort telemetry, not a user-visible action.
    private func sendForegroundPing() {
        guard authSession.isAuthenticated else { return }
        let request = APIRequest(path: "/v1/auth/ping", method: .POST, requiresAuth: true)
        Task { try? await AuthInterceptor.shared.executeVoid(request) }
    }

    private func handleDeepLink(_ url: URL) {
        // droob://courses/<id>
        guard url.scheme == "droob",
              url.host == "courses",
              let courseId = url.pathComponents.dropFirst().first else { return }
        authSession.pendingDeepLinkCourseId = courseId
    }

    /// Resolves `https://droob-sa.net/r/{slug}` Universal Links. We only
    /// accept HTTPS on the apex domain that owns our AASA file — any
    /// other URL is silently ignored so a third party can't forge a
    /// link that drops us into a stale state.
    private func handleUniversalLink(_ url: URL) {
        guard url.scheme == "https",
              url.host == "droob-sa.net" else {
            print("[DeepLink] rejected — bad scheme/host \(url.scheme ?? "") \(url.host ?? "")")
            return
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        // Path shape: ["r", "{slug}"]
        guard parts.count == 2, parts[0] == "r" else {
            print("[DeepLink] rejected — bad path \(url.path)")
            return
        }
        let slug = parts[1]
        print("[DeepLink] stashing slug=\(slug)")
        authSession.pendingStudyRoomSlug = slug
    }

    private func configureGoogleSignIn() {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let plist = NSDictionary(contentsOf: url),
              let clientID = plist["CLIENT_ID"] as? String else {
            assertionFailure("GoogleService-Info.plist missing or has no CLIENT_ID")
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }
}

// MARK: - Window size restrictor (non-invasive)
//
// A custom UIScene `delegateClass` replaces SwiftUI's own scene handling and
// blanks the UI, so instead of a SceneDelegate we read the LIVE window's scene
// from inside the SwiftUI tree and set a best-effort minimum window size. This
// never creates or owns a window, so SwiftUI's WindowGroup keeps rendering.
// Single-window is enforced separately by `UIApplicationSupportsMultipleScenes
// = false` in Info.plist. No-op on iPhone (`sizeRestrictions` is nil there).
struct WindowSizeRestrictor: UIViewRepresentable {
    var minimumSize = CGSize(width: 480, height: 720)

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let size = minimumSize
        DispatchQueue.main.async {
            uiView.window?.windowScene?.sizeRestrictions?.minimumSize = size
        }
    }
}

// MARK: - macOS gate

/// Shown instead of the app when it is launched on a Mac.
///
/// Droob is an iPhone/iPad app, but Apple lists "Designed for iPad" apps on the
/// Mac App Store by default, so an Apple Silicon Mac can install it without us
/// ever shipping a Mac build. That matters beyond layout: the app-wide capture
/// protection is iOS secure-text-field redaction, which macOS screen recording
/// ignores outright — a Mac install is an unprotected copy of paid course video.
///
/// Unticking Mac availability in App Store Connect stops *new* installs but
/// leaves a working copy on every Mac that already has one. This closes those
/// on their next launch.
struct MacUnsupportedView: View {
    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 54, weight: .light))
                    .foregroundColor(MyCoursesPalette.accent)
                Text(L10n.macUnsupportedTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .multilineTextAlignment(.center)
                Text(L10n.macUnsupportedBody)
                    .font(.system(size: 15))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)
        }
    }
}

extension ProcessInfo {
    /// True when this iOS build is running on an Apple Silicon Mac.
    ///
    /// `isiOSAppOnMac` is the precise test. `isMacCatalystApp` is not — it also
    /// reports true for an iOS app on Mac, so it cannot tell the two apart.
    var isRunningOnMac: Bool { isiOSAppOnMac }
}
