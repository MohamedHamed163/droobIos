import SwiftUI
import AVFoundation
import UIKit

// MARK: - Dynamic watermark (always-on, zero ML cost)
//
// The primary deterrent. Renders the authenticated user's account label
// (email / id) at low opacity and slowly drifts it around the frame so a
// screen recording always carries the leaker's identity. Pure UI — never
// touches the camera, never interrupts playback, never intercepts touches.

struct PresenceWatermark: View {
    let label: String
    let opacity: Double
    let moveInterval: TimeInterval
    /// Type size of the mark. Defaults to the inline-player size; callers
    /// showing the video full-screen pass a larger value, because fullscreen
    /// is when a second camera actually gets pointed at the screen and the
    /// deterrent has to be unmistakably part of the frame.
    var fontSize: CGFloat = 13

    @State private var anchor: UnitPoint = .center

    var body: some View {
        GeometryReader { geo in
            Text(label)
                .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .opacity(opacity)
                .shadow(color: .black.opacity(0.35), radius: 1)
                .rotationEffect(.degrees(-20))
                .position(x: geo.size.width * anchor.x,
                          y: geo.size.height * anchor.y)
                .allowsHitTesting(false)
                .onReceive(Timer.publish(every: moveInterval, on: .main, in: .common).autoconnect()) { _ in
                    withAnimation(.easeInOut(duration: 1.4)) {
                        anchor = Self.nextAnchor()
                    }
                }
                .onAppear { anchor = Self.nextAnchor() }
        }
        .allowsHitTesting(false)
    }

    /// Random point kept within 12–88% of each axis so the label never clips
    /// the frame edges.
    private static func nextAnchor() -> UnitPoint {
        UnitPoint(x: .random(in: 0.12...0.88), y: .random(in: 0.12...0.88))
    }
}

// MARK: - Block overlay (recoverable)
//
// Soft, never a hard stop. Each blocking `PresenceState` maps to its own copy
// so the student understands *why* the screen paused (and that it isn't a
// bug). Tapping anywhere resumes via `onContinue`.

struct PresenceBlockOverlay: View {
    let state: PresenceState
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            // Low-light gets a translucent scrim (the detector just can't
            // see); genuine violations get a near-opaque black-out.
            (state == .lowLight ? Color.black.opacity(0.72) : Color.black.opacity(0.94))
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(state == .lowLight ? .yellow.opacity(0.9) : Color.droobGold)

                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: onContinue) {
                    Text(L10n.presenceGuardContinue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                        .padding(.horizontal, 28)
                        .frame(height: 44)
                        .background(LinearGradient.droobBrand)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onContinue)
        .transition(.opacity)
    }

    private var iconName: String {
        switch state {
        case .multipleFaces:  return "person.2.fill"
        case .wrongPerson:    return "person.crop.circle.badge.questionmark"
        case .lowLight:       return "lightbulb.slash"
        case .noFace:         return "eye.slash.fill"
        case .recordingDevice:return "video.slash.fill"
        case .ok:             return "checkmark"
        }
    }

    private var title: String {
        switch state {
        case .multipleFaces:  return L10n.presenceGuardMultipleTitle
        case .wrongPerson:    return L10n.presenceGuardWrongPersonTitle
        case .lowLight:       return L10n.presenceGuardLowLightTitle
        case .noFace:         return L10n.presenceGuardNoFaceTitle
        case .recordingDevice:return L10n.presenceGuardRecordingTitle
        case .ok:             return ""
        }
    }

    private var message: String {
        switch state {
        case .multipleFaces:  return L10n.presenceGuardMultipleMessage
        case .wrongPerson:    return L10n.presenceGuardWrongPersonMessage
        case .lowLight:       return L10n.presenceGuardLowLightMessage
        case .noFace:         return L10n.presenceGuardNoFaceMessage
        case .recordingDevice:return L10n.presenceGuardRecordingMessage
        case .ok:             return ""
        }
    }
}

// MARK: - Live status HUD
//
// A small, always-visible chip while the camera is monitoring, so the
// protection is transparent (not mysterious): live face count + a recording-
// device indicator. Non-interactive; never intercepts taps.

struct PresenceHUD: View {
    let faceCount: Int
    let phoneSuspected: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Live "monitoring" pulse dot.
            Circle().fill(Color.green).frame(width: 6, height: 6)

            HStack(spacing: 4) {
                Image(systemName: faceIcon)
                    .font(.system(size: 11, weight: .bold))
                Text("\(faceCount)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            .foregroundColor(faceColor)

            if phoneSuspected {
                Rectangle().fill(Color.white.opacity(0.25))
                    .frame(width: 1, height: 12)
                HStack(spacing: 4) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(L10n.presenceHudRecording)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.55))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .allowsHitTesting(false)
    }

    private var faceIcon: String {
        switch faceCount {
        case 0:  return "magnifyingglass"
        case 1:  return "person.fill"
        default: return "person.2.fill"
        }
    }
    private var faceColor: Color {
        switch faceCount {
        case 0:  return .yellow
        case 1:  return .green
        default: return .red
        }
    }
}

// MARK: - Transient alert banner
//
// Slides in from the top for notable, NON-blocking events (a second face
// appears, a recording device is suspected) — a heads-up that doesn't pause
// playback. Hard violations still get the full `PresenceBlockOverlay`.

struct PresenceAlertBanner: View {
    enum Kind: Equatable {
        case multipleFaces(Int)
        case phone
    }
    let kind: Kind

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        .allowsHitTesting(false)
    }

    private var icon: String {
        switch kind {
        case .multipleFaces: return "person.2.fill"
        case .phone:         return "video.slash.fill"
        }
    }
    private var text: String {
        switch kind {
        case .multipleFaces(let n): return String(format: L10n.presenceAlertMultipleFmt, n)
        case .phone:                return L10n.presenceAlertPhone
        }
    }
    private var tint: Color {
        switch kind {
        case .multipleFaces: return Color.orange.opacity(0.95)
        case .phone:         return Color.red.opacity(0.95)
        }
    }
}

// MARK: - Privacy screen (cosmetic side-dim)
//
// Darkens the left/right edges so the readable area is a central strip — a
// visual "privacy filter" treatment. IMPORTANT: this is cosmetic. Software
// can't physically limit a screen's viewing angle (that needs a hardware
// privacy film), so an off-axis camera still sees the lit pixels. The real
// off-axis defense is the watermark + presence guard + FairPlay/HDCP.

struct PresencePrivacyScreen: View {
    let strength: Double

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(strength),       location: 0.00),
                .init(color: .black.opacity(strength * 0.35), location: 0.14),
                .init(color: .clear,                          location: 0.30),
                .init(color: .clear,                          location: 0.70),
                .init(color: .black.opacity(strength * 0.35), location: 0.86),
                .init(color: .black.opacity(strength),        location: 1.00),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Gyro parallax privacy layer
//
// A depth-style ("3D") dark layer driven by the gyro. A soft clear "window"
// stays toward the front (shifts opposite the device tilt), over an
// increasingly dark field — so when the phone is tilted off-axis the readable
// area slides away and the whole frame darkens. Driven by `PrivacyTiltMonitor`.
// (Software approximation — it dims by device tilt; it cannot physically
// redirect the display's light like a hardware privacy film.)

struct PrivacyParallaxLayer: View {
    let level: Double   // 0…1 overall obscure
    let tiltX: Double   // −1…1 roll
    let tiltY: Double   // −1…1 pitch

    var body: some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height)
            ZStack {
                // Directional dark gradient with a clear center that tracks the
                // front (moves opposite the tilt) → off-axis = dark.
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.9),
                    ]),
                    center: UnitPoint(x: 0.5 - tiltX * 0.55, y: 0.5 - tiltY * 0.55),
                    startRadius: r * 0.16,
                    endRadius: r * 0.85
                )
                .opacity(level)

                // Uniform dim that ramps with how far off-axis the phone is.
                Color.black.opacity(level * 0.55)
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Camera-required gate
//
// Covers the protected video when the user hasn't granted camera access, so a
// lesson can't be watched with the presence guard disabled.

struct PresenceCameraRequiredView: View {
    let onGrant: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(Color.droobGold)
                Text(L10n.presenceCameraRequiredTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(L10n.presenceCameraRequiredMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(action: onGrant) {
                    Text(L10n.presenceCameraRequiredButton)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                        .padding(.horizontal, 24)
                        .frame(height: 44)
                        .background(LinearGradient.droobBrand)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
        }
        .transition(.opacity)
    }
}

// MARK: - Per-layer privacy toggles (testing panel)
//
// Each privacy layer can be switched on/off independently so it can be tested
// in isolation on the real video. Persisted in UserDefaults; the modifier
// reads the same keys via @AppStorage so changes apply live.

enum PrivacyToggleKey {
    static let watermark = "privacy.toggle.watermark"
    static let sideDim = "privacy.toggle.sideDim"
    static let tiltDim = "privacy.toggle.tiltDim"
    static let cameraPresence = "privacy.toggle.cameraPresence"
    static let phoneDetection = "privacy.toggle.phoneDetection"
}

struct PrivacyTogglePanel: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrivacyToggleKey.watermark) private var watermark = true
    @AppStorage(PrivacyToggleKey.sideDim) private var sideDim = true
    @AppStorage(PrivacyToggleKey.tiltDim) private var tiltDim = true
    @AppStorage(PrivacyToggleKey.cameraPresence) private var cameraPresence = true
    @AppStorage(PrivacyToggleKey.phoneDetection) private var phoneDetection = true
    @AppStorage(CaptureProtectionEnvironment.storageKey)
    private var screenRecord = CaptureProtectionEnvironment.defaultValue

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.guardSectionOverlay) {
                    Toggle(isOn: $watermark) { Label(L10n.guardWatermark, systemImage: "signature") }
                    Toggle(isOn: $sideDim) { Label(L10n.guardSideDim, systemImage: "rectangle.lefthalf.inset.filled") }
                    Toggle(isOn: $tiltDim) { Label(L10n.guardTiltDim, systemImage: "rotate.3d") }
                }
                Section(L10n.guardSectionCamera) {
                    Toggle(isOn: $cameraPresence) { Label(L10n.guardPresence, systemImage: "person.crop.rectangle") }
                    Toggle(isOn: $phoneDetection) { Label(L10n.guardPhoneRec, systemImage: "video.slash") }
                }
                Section(L10n.guardSectionAppWide) {
                    Toggle(isOn: $screenRecord) { Label(L10n.guardBlockRecording, systemImage: "eye.slash") }
                }
                Section {
                    Text(L10n.guardLayersHint)
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle(L10n.guardLayersTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L10n.done) { dismiss() } } }
        }
    }
}

// MARK: - View modifier — the one-line integration point
//
// Wraps the video with the watermark (always) and the guard pipeline +
// block overlay (gated on consent). Owns the engine's lifecycle so the host
// player only has to call `.viewerPresenceGuard(...)`.

private struct ViewerPresenceGuardModifier: ViewModifier {
    let player: AVPlayer
    let userId: String
    let userLabel: String
    let config: PresenceGuardConfig

    @StateObject private var guardEngine: ViewerPresenceGuard
    @StateObject private var tilt: PrivacyTiltMonitor
    @ObservedObject private var consent = PresenceConsentStore.shared
    @State private var showConsent = false
    @State private var activeBanner: PresenceAlertBanner.Kind?
    @State private var bannerDismiss: DispatchWorkItem?
    @Environment(\.openURL) private var openURL

    // Per-layer privacy toggles (live, persisted). Tested via the in-video panel.
    @AppStorage(PrivacyToggleKey.watermark) private var tWatermark = true
    @AppStorage(PrivacyToggleKey.sideDim) private var tSideDim = true
    @AppStorage(PrivacyToggleKey.tiltDim) private var tTiltDim = true
    @AppStorage(PrivacyToggleKey.cameraPresence) private var tCameraPresence = true
    @AppStorage(PrivacyToggleKey.phoneDetection) private var tPhoneDetection = true
    @State private var showPrivacyPanel = false

    /// Show the camera-required gate: protection wants the camera, the user
    /// has already answered the consent screen, and access still isn't usable.
    private var showCameraGate: Bool {
        config.requireCameraToView
            && consent.hasDecided
            && !consent.cameraUsable
            && !showConsent
    }

    init(player: AVPlayer, userId: String, userLabel: String, config: PresenceGuardConfig) {
        self.player = player
        self.userId = userId
        self.userLabel = userLabel
        self.config = config
        _guardEngine = StateObject(wrappedValue: ViewerPresenceGuard(config: config))
        _tilt = StateObject(wrappedValue: PrivacyTiltMonitor(
            startDegrees: config.tiltPrivacyStartDegrees,
            fullDegrees: config.tiltPrivacyFullDegrees))
    }

    func body(content: Content) -> some View {
        content
            // Always-on deterrent — independent of camera consent.
            .overlay {
                if tWatermark {
                    PresenceWatermark(label: userLabel,
                                      opacity: config.watermarkOpacity,
                                      moveInterval: config.watermarkMoveIntervalSec)
                }
            }
            // Cosmetic "privacy screen" side dim.
            .overlay {
                if config.privacyDimEnabled && tSideDim {
                    PresencePrivacyScreen(strength: config.privacyDimStrength)
                }
            }
            // Live status HUD (face count + recording indicator).
            .overlay(alignment: .topLeading) {
                if guardEngine.isMonitoring && !guardEngine.isBlocked {
                    PresenceHUD(faceCount: guardEngine.faceCount,
                                phoneSuspected: guardEngine.phoneSuspected)
                        .padding(.top, 92)
                        .padding(.leading, 16)
                        .transition(.opacity)
                }
            }
            // Transient, non-blocking alert banner.
            .overlay(alignment: .top) {
                if let kind = activeBanner {
                    PresenceAlertBanner(kind: kind)
                        .padding(.top, 92)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // Gyro/accelerometer privacy dim — obscures the video as the phone
            // is tilted away from head-on (real device only; no-op in Simulator).
            .overlay {
                if config.tiltPrivacyEnabled && tTiltDim && tilt.obscureLevel > 0.001 {
                    ZStack {
                        PrivacyParallaxLayer(level: tilt.obscureLevel,
                                             tiltX: tilt.tiltX,
                                             tiltY: tilt.tiltY)
                        if tilt.obscureLevel > 0.55 {
                            VStack(spacing: 10) {
                                Image(systemName: "eye.slash.fill")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))
                                Text(L10n.privacyTiltHint)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                            .opacity(tilt.obscureLevel)
                        }
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
            }
            // Recoverable block overlay (sits above the HUD/banner).
            .overlay {
                if guardEngine.isBlocked {
                    PresenceBlockOverlay(state: guardEngine.state) {
                        guardEngine.continueAfterBlock()
                    }
                }
            }
            // Camera-required gate — covers the video when access is missing.
            .overlay {
                if showCameraGate {
                    PresenceCameraRequiredView(onGrant: handleGrantCamera)
                }
            }
            // Per-layer privacy toggle button (Debug + TestFlight only).
            .overlay(alignment: .topTrailing) {
                if !CaptureProtectionEnvironment.isProduction {
                    Button { showPrivacyPanel = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 92)
                    .padding(.trailing, 16)
                }
            }
            .sheet(isPresented: $showPrivacyPanel) { PrivacyTogglePanel() }
            .animation(.easeInOut(duration: 0.2), value: guardEngine.isBlocked)
            .animation(.easeInOut(duration: 0.2), value: showCameraGate)
            .animation(.easeInOut(duration: 0.2), value: guardEngine.faceCount)
            .animation(.easeOut(duration: 0.12), value: tilt.obscureLevel)
            // Surface notable, non-blocking events as a brief banner.
            .onChange(of: guardEngine.phoneSuspected) { _, suspected in
                if suspected { flashBanner(.phone) }
            }
            .onChange(of: guardEngine.faceCount) { _, count in
                if count >= 2 { flashBanner(.multipleFaces(count)) }
            }
            // Per-layer privacy toggles applied live.
            .onChange(of: tCameraPresence) { _, on in
                guardEngine.setPresenceEnabled(on)
                if on && player.timeControlStatus == .playing { guardEngine.start() }
            }
            .onChange(of: tPhoneDetection) { _, on in
                guardEngine.setPhoneDetectionEnabled(on)
            }
            .onChange(of: tTiltDim) { _, on in
                if on && config.tiltPrivacyEnabled { tilt.start() } else { tilt.stop() }
            }
            .onAppear {
                guardEngine.configure(player: player, userId: userId)
                guardEngine.setPresenceEnabled(tCameraPresence)
                guardEngine.setPhoneDetectionEnabled(tPhoneDetection)
                if config.tiltPrivacyEnabled && tTiltDim { tilt.start() }
                // Explain & gate before any camera use.
                if !consent.hasDecided { showConsent = true }
            }
            .onDisappear { guardEngine.teardown(); tilt.stop() }
            .sheet(isPresented: $showConsent) {
                CameraConsentView(
                    onAccept: {
                        Task {
                            let granted = await consent.ensureSystemPermission()
                            consent.record(granted: granted)
                            showConsent = false
                            if player.timeControlStatus == .playing { guardEngine.start() }
                        }
                    },
                    onDecline: {
                        consent.record(granted: false)
                        showConsent = false
                    }
                )
                .interactiveDismissDisabled(true)
            }
    }

    /// Shows a transient banner and auto-dismisses it after a few seconds.
    /// Re-arming cancels the previous dismissal so back-to-back events don't
    /// hide the banner early.
    private func flashBanner(_ kind: PresenceAlertBanner.Kind) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            activeBanner = kind
        }
        bannerDismiss?.cancel()
        let item = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) { activeBanner = nil }
        }
        bannerDismiss = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: item)
    }

    /// "Enable camera access" tap on the gate. If the OS denied access, send
    /// the user to Settings; if they only declined our in-app screen, re-show
    /// the consent explainer.
    private func handleGrantCamera() {
        switch consent.systemAuthorization {
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        default:
            showConsent = true
        }
    }
}

extension View {
    /// Attaches the ViewerPresenceGuard (anti-sharing / anti-recording) to a
    /// course video. Renders the always-on watermark and, once the user
    /// consents, the camera-driven presence checks with recoverable block
    /// overlays.
    ///
    /// - Parameters:
    ///   - player: the lesson `AVPlayer` (paused/resumed by the guard).
    ///   - userId: account id used to key the on-device face enrollment.
    ///   - userLabel: text shown in the watermark (email or id).
    ///   - config: performance / behaviour knobs (defaults to `.smooth`).
    func viewerPresenceGuard(player: AVPlayer,
                             userId: String,
                             userLabel: String,
                             config: PresenceGuardConfig = .smooth) -> some View {
        modifier(ViewerPresenceGuardModifier(player: player,
                                             userId: userId,
                                             userLabel: userLabel,
                                             config: config))
    }
}
