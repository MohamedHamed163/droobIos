import SwiftUI
import UIKit
import AVFoundation

// MARK: - Public API

extension View {
    /// Hides this view from screenshots, screen recordings, AirPlay, and
    /// iPhone Mirroring — when the protection toggle is on.
    ///
    /// Two-tier defense:
    ///   1. The app's main `UIWindow` gets its `CALayer` re-rooted as a
    ///      sublayer of a hidden `UITextField(isSecureTextEntry: true)`'s
    ///      protected canvas layer. iOS masks the canvas to black in any
    ///      captured pixel buffer, so screenshots / screen recordings /
    ///      AirPlay / iPhone-Mirroring frames never contain the protected
    ///      content. On-device rendering is unaffected (the layer hierarchy
    ///      is reorganised but the visual tree is identical).
    ///   2. A SwiftUI overlay reacts to `UIScreen.capturedDidChangeNotification`
    ///      and dims the screen with a "screen capture not allowed" notice
    ///      while `isCaptured` is true — gives on-device feedback that the
    ///      black-out happened on purpose.
    ///
    /// The policy is set centrally by an admin, delivered by
    /// `RemoteAppConfig`, and cached in `UserDefaults` under
    /// `CaptureProtectionEnvironment.storageKey`. There is no in-app toggle.
    /// The read is reactive, so a policy change picked up on the next
    /// foreground installs or unwinds the layer surgery at runtime with no
    /// restart. Until a device has heard from the server it stays blocked.
    func captureProtected() -> some View {
        modifier(CaptureProtectionModifier())
    }
}

// MARK: - Environment & defaults

/// Resolves which build we're running on and exposes the storage key plus
/// default value the rest of the app uses to read the capture policy.
///
/// This is **no longer a user preference**. Screen-capture blocking is set once
/// for the whole platform from the admin panel and delivered by
/// `RemoteAppConfig`; the app only caches and obeys it.
enum CaptureProtectionEnvironment {
    /// `UserDefaults` key holding the last policy read from the server.
    /// Written only by `RemoteAppConfig`; everything else reads it via
    /// `@AppStorage`.
    ///
    /// Deliberately NOT the old `captureProtectionEnabled` key: that held a
    /// user's personal choice, and reusing it would let someone who had turned
    /// protection off keep it off, with their old preference masquerading as
    /// company policy. A fresh key means every device starts fail-closed and
    /// then adopts whatever the server says.
    static let storageKey = "captureBlockedPolicy"

    /// True for App Store production builds. False for DEBUG runs and
    /// TestFlight (sandbox receipt) installs.
    ///
    /// Resolved once at launch so we don't pay the receipt URL lookup on
    /// every render.
    static let isProduction: Bool = {
        #if DEBUG
        return false
        #else
        let receiptName = Bundle.main.appStoreReceiptURL?.lastPathComponent
        return receiptName != "sandboxReceipt"
        #endif
    }()

    /// What to assume before the server has been heard from — a fresh install,
    /// or a device that has never been online.
    ///
    /// Blocked, deliberately. A network failure must not be the thing that
    /// unprotects course content; the opposite mistake is recoverable the
    /// moment the fetch succeeds.
    static var defaultValue: Bool { true }
}

// MARK: - Modifier
//
// Owns the @AppStorage gate plus the capture-state subscription, and
// drives the imperative layer-surgery side via `CaptureProtector`.

private struct CaptureProtectionModifier: ViewModifier {
    @AppStorage(CaptureProtectionEnvironment.storageKey)
    private var protectionEnabled: Bool = CaptureProtectionEnvironment.defaultValue

    @State private var isCaptured: Bool = UIScreen.main.isCaptured
    /// True when a second screen (HDMI/USB-C cable to a TV/monitor/capture
    /// card, or AirPlay mirroring) is attached — i.e. the content could be
    /// "streamed to a laptop". We blank protected content in that case too.
    @State private var externalDisplay: Bool = ExternalDisplayMonitor.isConnected
    /// Heuristic for "the physical screen is OFF while the app is running" —
    /// the exact state iPhone Mirroring leaves the phone in (locked, screen
    /// off, app driven from the Mac). There is NO API to detect iPhone
    /// Mirroring, and it does NOT set `isCaptured`, so a brightness of ~0 is
    /// the only available signal. It's a guess (a user at minimum brightness
    /// also reads near 0), so the resulting block is RECOVERABLE: it clears the
    /// instant brightness rises (`brightnessDidChangeNotification`). Threshold
    /// is conservative (effectively 0) to avoid blocking real users; raise it
    /// only if real-device testing shows mirroring leaves brightness above 0.
    @State private var screenOff: Bool = false

    private static func screenIsOff() -> Bool {
        #if targetEnvironment(simulator)
        // Brightness is meaningless in the Simulator and iPhone Mirroring
        // doesn't exist there — never trigger the screen-off block in the sim.
        return false
        #else
        return UIScreen.main.brightness <= 0.0
        #endif
    }

    func body(content: Content) -> some View {
        content
            // Screen RECORDING / AirPlay mirroring / QuickTime-USB capture and
            // a wired second display are blocked here: while `isCaptured` or
            // `externalDisplay` is true we show the opaque `capturedOverlay`,
            // so the recording/mirror captures that black overlay (and the
            // lesson player pauses via `pausePlaybackWhenCaptured`).
            //
            // STILL SHOTS are handled separately by `.screenshotRedacted()`
            // (the secure-canvas layer) on the sensitive content views — that
            // makes the screenshot itself come out as "Recording not allowed"
            // instead of a useless after-the-fact alert. We no longer flash a
            // post-screenshot banner here.
            .overlay {
                if effectiveEnabled && (isCaptured || externalDisplay || screenOff) {
                    capturedOverlay.transition(.opacity)
                }
            }
            // Screen-off heuristic (best-effort iPhone-Mirroring catch). Clears
            // automatically when brightness rises, so a dark-room false-positive
            // is recoverable, never a lockout.
            .onReceive(NotificationCenter.default.publisher(
                for: UIScreen.brightnessDidChangeNotification
            )) { _ in
                withAnimation(.easeInOut(duration: 0.18)) {
                    screenOff = Self.screenIsOff()
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIScreen.capturedDidChangeNotification
            )) { _ in
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCaptured = UIScreen.main.isCaptured
                }
            }
            // External display attach/detach (cable or AirPlay mirroring).
            .onReceive(NotificationCenter.default.publisher(
                for: UIScreen.didConnectNotification
            )) { _ in
                withAnimation(.easeInOut(duration: 0.18)) {
                    externalDisplay = ExternalDisplayMonitor.isConnected
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIScreen.didDisconnectNotification
            )) { _ in
                withAnimation(.easeInOut(duration: 0.18)) {
                    externalDisplay = ExternalDisplayMonitor.isConnected
                }
            }
            // Re-sync whenever the app returns to the foreground. iPhone
            // Mirroring (controlling the phone from a Mac, macOS Sequoia) and
            // screen recording both set `UIScreen.isCaptured`, but if the
            // session STARTED while we were backgrounded the change
            // notification fired off-screen and our state is stale — so a
            // mirrored/remote-controlled phone would otherwise show content on
            // the first frame back. Re-reading on activation closes that gap.
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )) { _ in
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCaptured = UIScreen.main.isCaptured
                    externalDisplay = ExternalDisplayMonitor.isConnected
                    screenOff = Self.screenIsOff()
                }
            }
            .onAppear { screenOff = Self.screenIsOff() }
    }

    /// Resolves the user's stored preference. The toggle is now authoritative
    /// everywhere so a user can lock/unlock protection app-wide.
    private var effectiveEnabled: Bool { protectionEnabled }

    private var capturedOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: overlayIcon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                Text(overlayTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Text(overlayMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }

    // Reason precedence: active capture (recording/AirPlay) → wired external
    // display → screen-off (best-effort iPhone-Mirroring catch).
    private var overlayIcon: String {
        if isCaptured { return "eye.slash.fill" }
        if externalDisplay { return "rectangle.on.rectangle.slash" }
        return "sun.min.fill"
    }
    private var overlayTitle: String {
        (isCaptured || externalDisplay) ? L10n.captureBlockedTitle : L10n.captureScreenOffTitle
    }
    private var overlayMessage: String {
        if isCaptured { return L10n.captureBlockedMessage }
        if externalDisplay { return L10n.captureBlockedExternalMessage }
        return L10n.captureScreenOffMessage
    }
}

// MARK: - External display monitor
//
// Detects a second screen — an HDMI / USB-C cable to a TV/monitor/capture
// card, or AirPlay mirroring — by inspecting connected scene roles. (A Mac
// recording via QuickTime over USB does NOT create a second screen, so that
// specific path can't be detected; AirPlay mirroring is also caught by
// `UIScreen.isCaptured`.)

enum ExternalDisplayMonitor {
    static var isConnected: Bool {
        UIApplication.shared.connectedScenes.contains { scene in
            guard let windowScene = scene as? UIWindowScene else { return false }
            let role = windowScene.session.role
            return role == .windowExternalDisplayNonInteractive
                || role.rawValue == "UIWindowSceneSessionRoleExternalDisplay"
        }
    }
}

// MARK: - Pause playback while captured
//
// The capture-protection overlay blanks the *video* layer during screen
// recording / AirPlay / QuickTime-over-USB capture (all of which set
// `UIScreen.isCaptured`). But per Apple's own `isCaptured` guidance, the
// system keeps recording the **audio** unless the app stops it — so a black
// recording would still carry the lesson's soundtrack. This modifier pauses
// the given player whenever capture or an external display is active, closing
// that audio gap. Honors the same user toggle as `captureProtected()`.

extension View {
    /// Pauses `player` while the screen is being captured/mirrored or an
    /// external display is attached (so audio isn't recorded under the black
    /// overlay). No-op when the user has turned protection off.
    func pausePlaybackWhenCaptured(_ player: AVPlayer) -> some View {
        modifier(PausePlaybackWhenCapturedModifier(player: player))
    }
}

private struct PausePlaybackWhenCapturedModifier: ViewModifier {
    let player: AVPlayer

    @AppStorage(CaptureProtectionEnvironment.storageKey)
    private var protectionEnabled: Bool = CaptureProtectionEnvironment.defaultValue

    func body(content: Content) -> some View {
        content
            .onAppear { pauseIfCompromised() }
            .onReceive(NotificationCenter.default.publisher(
                for: UIScreen.capturedDidChangeNotification)) { _ in pauseIfCompromised() }
            .onReceive(NotificationCenter.default.publisher(
                for: UIScreen.didConnectNotification)) { _ in pauseIfCompromised() }
            // Catch a mirror/recording that began while backgrounded.
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification)) { _ in pauseIfCompromised() }
    }

    private func pauseIfCompromised() {
        guard protectionEnabled else { return }
        if UIScreen.main.isCaptured || ExternalDisplayMonitor.isConnected {
            player.pause()
        }
    }
}

// MARK: - Screenshot redaction (view-scoped secure canvas)
//
// iOS cannot *prevent* a screenshot, and it reports `userDidTakeScreenshot`
// only AFTER the shot — too late to block. The only way to keep the content
// out of the captured pixels is to host it inside a
// `UITextField(isSecureTextEntry: true)`'s secure canvas: iOS omits that
// canvas from every captured buffer (screenshots, screen recordings, AirPlay,
// Mirroring), while still drawing it on the real display.
//
// We host the protected view in that canvas and put a "Recording not allowed"
// placard BEHIND it. On-device the viewer sees the real content; any capture
// records only the placard. This is VIEW-scoped (one leaf view), NOT the
// whole-window layer reparenting that black-screened the app on iOS 26.
//
// Caveat: the masking only takes effect on a real device — in the Simulator
// the content renders normally and screenshots are NOT masked.

extension View {
    /// Redacts this view from still screenshots and screen captures: the live
    /// screen shows the content, a capture shows a "Recording not allowed"
    /// placard. Honors the app-wide protection toggle. Apply to a *leaf* view
    /// with no `@EnvironmentObject` dependency (hosting re-roots the SwiftUI
    /// environment).
    func screenshotRedacted() -> some View {
        modifier(ScreenshotRedactModifier())
    }
}

private struct ScreenshotRedactModifier: ViewModifier {
    @AppStorage(CaptureProtectionEnvironment.storageKey)
    private var protectionEnabled: Bool = CaptureProtectionEnvironment.defaultValue

    func body(content: Content) -> some View {
        if protectionEnabled {
            SecureCanvasHost { content }
        } else {
            content
        }
    }
}

/// Hosts SwiftUI `content` inside a secure-text-field canvas (excluded from
/// captures) with a capture-only placard behind it.
private struct SecureCanvasHost<Content: View>: UIViewControllerRepresentable {
    @ViewBuilder var content: () -> Content
    func makeUIViewController(context: Context) -> SecureCanvasController<Content> {
        SecureCanvasController(rootView: content())
    }
    func updateUIViewController(_ controller: SecureCanvasController<Content>, context: Context) {
        controller.update(content())
    }
}

/// Secure field that never becomes first responder, so hosting content in its
/// canvas can't pop a keyboard, show a caret, or steal focus.
private final class NonFocusableSecureField: UITextField {
    override var canBecomeFirstResponder: Bool { false }
    override func caretRect(for position: UITextPosition) -> CGRect { .zero }
}

private final class SecureCanvasController<Content: View>: UIViewController {
    private let hosting: UIHostingController<Content>
    private let placard = UIHostingController(rootView: CaptureRedactedPlacard())
    private let field = NonFocusableSecureField()

    init(rootView: Content) {
        hosting = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ rootView: Content) { hosting.rootView = rootView }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        // 1. Placard — what a capture sees (sits behind the secure canvas).
        embed(placard, into: view)

        // 2. Secure field → its canvas hosts the real (capture-excluded) view.
        field.isSecureTextEntry = true
        field.borderStyle = .none
        field.textColor = .clear
        field.backgroundColor = .clear
        field.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(field)
        pin(field, into: view)
        // Force layout so UIKit instantiates the internal canvas subview
        // before we look it up (otherwise subviews is empty).
        field.setNeedsLayout(); field.layoutIfNeeded()

        // The secure canvas is the field's content host
        // (`_UITextLayoutCanvasView`). If absent (future iOS change), fall
        // back to the field itself so the content is never blank.
        let canvas = field.subviews.first ?? field
        embed(hosting, into: canvas)
    }

    private func embed(_ child: UIViewController, into parent: UIView) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        child.view.backgroundColor = .clear
        parent.addSubview(child.view)
        pin(child.view, into: parent)
        child.didMove(toParent: self)
    }

    private func pin(_ v: UIView, into parent: UIView) {
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: parent.topAnchor),
            v.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])
    }
}

/// What a screen capture sees in place of the protected content.
private struct CaptureRedactedPlacard: View {
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Text(L10n.captureBlockedTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(L10n.captureBlockedMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

// MARK: - Window protector
//
// Installs and (when toggled off) uninstalls the secure-field canvas
// layer as the parent of the app's main window layer. `protectMainWindow`
// and `unprotectMainWindow` are idempotent — calling either twice is
// safe.

private final class CaptureProtector {
    static let shared = CaptureProtector()

    private var protectedWindow: UIWindow?
    private var secureField: UITextField?
    /// The superlayer of `window.layer` before surgery — captured so
    /// `unprotectMainWindow` can put the window layer back exactly
    /// where the system had originally placed it.
    private var originalWindowSuperlayer: CALayer?

    func protectMainWindow() {
        guard protectedWindow == nil,
              let window = activeKeyWindow(),
              let originalSuperlayer = window.layer.superlayer else { return }

        let field = UITextField()
        field.isSecureTextEntry = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.alpha = 0
        field.isUserInteractionEnabled = false
        field.tintColor = .clear
        window.addSubview(field)
        // Size the field to fill the window so the secure canvas has a
        // non-zero frame; a 0×0 canvas can clip its sublayers (including
        // the re-rooted window layer) on some iOS versions and produce a
        // black screen.
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: window.topAnchor),
            field.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            field.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: window.trailingAnchor),
        ])

        // Force a layout pass. Without this, UIKit hasn't yet
        // instantiated the field's internal `_UITextLayoutCanvasView`,
        // so `field.layer.sublayers` is nil / empty and the canvas
        // lookup below silently fails. This is the actual cause of
        // screenshots staying unblocked after a runtime toggle: the
        // surgery never ran.
        field.setNeedsLayout()
        field.layoutIfNeeded()

        // Resolve the protected canvas layer. `_UITextLayoutCanvasView`
        // (or any class whose name contains "Canvas") is the subview
        // whose layer iOS treats as the secure content host. Looking it
        // up by class name is more durable than blind sublayer-index
        // access — Apple has rearranged the internal layer order across
        // iOS releases.
        guard let canvasLayer = resolveCanvasLayer(in: field) else {
            field.removeFromSuperview()
            return
        }
        // Belt-and-braces: prevent the canvas from clipping its
        // sublayers in case its bounds end up smaller than the
        // window's content.
        canvasLayer.masksToBounds = false

        // Layer surgery: hoist `field.layer` to be a sibling of where
        // `window.layer` used to live, then re-root `window.layer`
        // under the protected canvas. The on-screen render path is
        // unchanged; only the layer ancestor of `window.layer` shifts,
        // which is what iOS checks when deciding whether to black out
        // captured frames (screenshots, recordings, AirPlay, iPhone
        // Mirroring).
        originalSuperlayer.addSublayer(field.layer)
        canvasLayer.addSublayer(window.layer)

        protectedWindow = window
        secureField = field
        originalWindowSuperlayer = originalSuperlayer
    }

    /// Finds the protected canvas layer inside a secure text field.
    ///
    /// Tries (in order):
    ///   1. A subview whose class name contains "Canvas" — matches the
    ///      private `_UITextLayoutCanvasView` UIKit uses for the secure
    ///      content host on iOS 13+.
    ///   2. The first sublayer of the field's layer — most common
    ///      single-canvas layout.
    ///   3. The last sublayer of the field's layer — fallback for
    ///      older iOS versions.
    private func resolveCanvasLayer(in field: UITextField) -> CALayer? {
        for subview in field.subviews {
            if String(describing: type(of: subview)).contains("Canvas") {
                return subview.layer
            }
        }
        if let first = field.layer.sublayers?.first { return first }
        return field.layer.sublayers?.last
    }

    /// Reverses the surgery from `protectMainWindow`. Moves the window
    /// layer back to its original superlayer and tears down the secure
    /// text field. Safe to call when no protection is installed.
    func unprotectMainWindow() {
        guard let window = protectedWindow,
              let field = secureField,
              let originalSuperlayer = originalWindowSuperlayer else { return }

        // Re-parent the window layer first so the screen never has an
        // orphan window layer (which would blank the display for a
        // frame). Then tear down the secure field.
        originalSuperlayer.addSublayer(window.layer)
        field.layer.removeFromSuperlayer()
        field.removeFromSuperview()

        protectedWindow = nil
        secureField = nil
        originalWindowSuperlayer = nil
    }

    /// Picks the foreground active scene's key window. Returns nil during
    /// the brief launch window before any scene is connected.
    private func activeKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }
    }
}
