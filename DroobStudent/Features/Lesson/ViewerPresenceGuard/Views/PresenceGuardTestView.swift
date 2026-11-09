import SwiftUI

// MARK: - PresenceGuardTestView (DEBUG harness)
//
// A server-free, login-free screen to exercise the ViewerPresenceGuard:
// live face count, phone / recording-device detection, the moving watermark,
// and every overlay — without needing the backend or a real lesson video.
//
//   • On a REAL DEVICE → "Start camera" runs the actual detection pipeline,
//     so the face count and phone indicator update live.
//   • On the SIMULATOR (no camera) → use the "Simulate" buttons to preview
//     each state, HUD reading, and overlay.
//
// Reachable from a DEBUG-only launcher on the login screen.

struct PresenceGuardTestView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = ViewerPresenceGuard()
    @ObservedObject private var consent = PresenceConsentStore.shared

    @State private var hudVisible = false
    @State private var showConsent = false
    @State private var activeBanner: PresenceAlertBanner.Kind?
    @State private var bannerDismiss: DispatchWorkItem?

    private let userLabel = "test@bonyad-hub.com"
    private let userId = "presence-test-user"

    var body: some View {
        ZStack {
            fakeVideo

            // Real guard UI, bound to the engine.
            PresenceWatermark(label: userLabel, opacity: 0.18, moveInterval: 4)

            if hudVisible {
                VStack {
                    HStack {
                        PresenceHUD(faceCount: engine.faceCount,
                                    phoneSuspected: engine.phoneSuspected)
                        Spacer()
                    }
                    .padding(.top, 60).padding(.leading, 16)
                    Spacer()
                }
            }

            if let kind = activeBanner {
                VStack {
                    PresenceAlertBanner(kind: kind)
                        .padding(.top, 60).padding(.horizontal, 16)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if engine.isBlocked {
                PresenceBlockOverlay(state: engine.state) { engine.continueAfterBlock() }
            }

            VStack { Spacer(); controlPanel }

            closeButton
        }
        .onAppear { engine.configureForTesting(userId: userId) }
        .onDisappear { engine.teardown() }
        .onChange(of: engine.phoneSuspected) { _, p in if p { flashBanner(.phone) } }
        .onChange(of: engine.faceCount) { _, c in if c >= 2 { flashBanner(.multipleFaces(c)) } }
        .animation(.easeInOut(duration: 0.2), value: engine.isBlocked)
        .sheet(isPresented: $showConsent) {
            CameraConsentView(
                onAccept: {
                    Task {
                        let granted = await consent.ensureSystemPermission()
                        consent.record(granted: granted)
                        showConsent = false
                        startCamera()
                    }
                },
                onDecline: { consent.record(granted: false); showConsent = false }
            )
        }
    }

    // MARK: Fake video backdrop

    private var fakeVideo: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.12), Color(white: 0.02)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.white.opacity(0.25))
                Text(L10n.guardSampleVideo)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                Text(L10n.guardHarness)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
            }
            .padding(.top, 56).padding(.trailing, 16)
            Spacer()
        }
    }

    // MARK: Control panel

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow

            // Live Tier-2 detector readout (top classifications + rectangle
            // count). Hold a phone up to the camera and watch this update.
            if engine.isMonitoring {
                Text(engine.phoneDiagnostic.isEmpty ? "scanning…" : engine.phoneDiagnostic)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(engine.phoneSuspected ? .red : .white.opacity(0.55))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Real camera (device).
            HStack(spacing: 10) {
                panelButton(engine.isMonitoring ? "Stop camera" : "Start camera",
                            system: engine.isMonitoring ? "stop.fill" : "camera.fill",
                            tint: engine.isMonitoring ? .red : Color.droobGold) {
                    engine.isMonitoring ? stopCamera() : startCamera()
                }
                panelButton(L10n.guardResetConsent, system: "arrow.counterclockwise", tint: .gray) {
                    consent.reset()
                }
            }

            Divider().overlay(Color.white.opacity(0.15))

            Text(L10n.guardSimulate)
                .font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.5))

            // HUD readings.
            HStack(spacing: 8) {
                chip("0 faces") { simulateTelemetry(0, phone: false) }
                chip("1 face")  { simulateTelemetry(1, phone: false) }
                chip("2 faces") { simulateTelemetry(2, phone: false) }
                chip("Phone")   { simulateTelemetry(max(engine.faceCount, 1), phone: true) }
            }
            // Block overlays.
            HStack(spacing: 8) {
                chip("No face")   { engine.debugSimulate(.noFace) }
                chip("Multiple")  { engine.debugSimulate(.multipleFaces) }
                chip("Wrong")     { engine.debugSimulate(.wrongPerson) }
            }
            HStack(spacing: 8) {
                chip("Low light") { engine.debugSimulate(.lowLight) }
                chip("Recording") { engine.debugSimulate(.recordingDevice) }
                chip("Clear")     { engine.debugSimulate(.ok) }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }

    private var statusRow: some View {
        HStack(spacing: 14) {
            label("State", engine.state == .ok ? "ok" : "\(engine.state)")
            label("Faces", "\(engine.faceCount)")
            label("Phone", engine.phoneSuspected ? "YES" : "no")
            label("Cam", engine.isMonitoring ? "ON" : "off")
        }
    }

    private func label(_ k: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(k).font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.5))
            Text(v).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private func panelButton(_ title: String, system: String, tint: Color,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 12, weight: .bold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity).frame(height: 42)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func startCamera() {
        hudVisible = true
        if consent.cameraUsable {
            engine.start()
        } else if !consent.hasDecided {
            showConsent = true
        } else {
            // Consent decided but not usable (declined or OS-denied) — still
            // show the HUD so the harness isn't blank; detection just won't run.
            showConsent = true
        }
    }

    private func stopCamera() {
        engine.stop()
        hudVisible = false
    }

    private func simulateTelemetry(_ count: Int, phone: Bool) {
        hudVisible = true
        engine.debugTelemetry(faceCount: count, phone: phone)
    }

    private func flashBanner(_ kind: PresenceAlertBanner.Kind) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { activeBanner = kind }
        bannerDismiss?.cancel()
        let item = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) { activeBanner = nil }
        }
        bannerDismiss = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: item)
    }
}

// MARK: - Launcher (floats over the login screen, DEBUG only)

struct PresenceTestLauncher: View {
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 12, weight: .bold))
                Text(L10n.settingsTestDetection).font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 14).frame(height: 40)
            .background(Color.droobGold)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $show) { PresenceGuardTestView() }
    }
}
