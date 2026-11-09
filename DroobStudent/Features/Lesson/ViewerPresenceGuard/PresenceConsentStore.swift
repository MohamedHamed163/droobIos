import Foundation
import AVFoundation
import Combine

// MARK: - PresenceConsentStore
//
// Store / Play compliance: continuous front-camera monitoring for content
// protection must be explained and **opted into** before any camera use.
// This store records the user's in-app consent decision separately from the
// OS camera permission, because they answer different questions:
//
//   • App consent  — "do you accept that we monitor with the front camera
//                     while protected lessons play?"  (our screen)
//   • OS permission — the system camera-access alert (`AVCaptureDevice`).
//
// The guard starts the camera only when BOTH are granted. If app consent is
// declined the camera never runs, but the (ML-free) watermark still shows —
// it is the primary deterrent and needs no permission.
//
// We persist only the decision flags. No biometric data lives here; face
// embeddings (when an identity model is present) are stored separately and
// on-device only — never raw images, never uploaded (KSA PDPL / Egypt DP).

@MainActor
final class PresenceConsentStore: ObservableObject {
    static let shared = PresenceConsentStore()

    private enum Keys {
        static let decided = "presenceGuard.consent.decided"
        static let granted = "presenceGuard.consent.granted"
    }

    /// True once the user has answered the consent screen (either way).
    @Published private(set) var hasDecided: Bool
    /// True only if the user accepted monitoring on our consent screen.
    @Published private(set) var didGrant: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasDecided = defaults.bool(forKey: Keys.decided)
        self.didGrant = defaults.bool(forKey: Keys.granted)
    }

    /// Records the user's choice from the consent screen.
    func record(granted: Bool) {
        didGrant = granted
        hasDecided = true
        defaults.set(true, forKey: Keys.decided)
        defaults.set(granted, forKey: Keys.granted)
    }

    /// Lets the user revoke consent later (e.g. from Settings). Resets to the
    /// undecided state so the explainer is shown again next time.
    func reset() {
        didGrant = false
        hasDecided = false
        defaults.removeObject(forKey: Keys.decided)
        defaults.removeObject(forKey: Keys.granted)
    }

    // MARK: OS camera permission

    /// Current OS camera authorization, independent of our app consent.
    var systemAuthorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Requests the OS camera permission if still undetermined. Returns the
    /// effective "may we use the camera" answer. Safe to call repeatedly.
    func ensureSystemPermission() async -> Bool {
        switch systemAuthorization {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// The guard may run the camera only when the user accepted our screen
    /// *and* the OS granted access.
    var cameraUsable: Bool { didGrant && systemAuthorization == .authorized }
}
