import Foundation

// MARK: - ViewerPresenceGuard — public configuration & state types
//
// `ViewerPresenceGuard` is the on-device "presence guard" attached to the
// course video player. While a protected lesson plays it uses the front
// camera to enforce viewing rules:
//
//   • 0 faces        → nobody watching (possible off-axis re-recording) → block
//   • exactly 1 face → allowed; periodically verify it's the account owner
//   • 2+ faces       → multiple viewers (sharing) → block
//   • always-on      → a moving, semi-transparent watermark of the user's
//                      account label. Zero ML cost; the primary deterrent.
//
// HARD performance rule: detection runs on a *tiered cadence on a background
// thread at low resolution and low frame rate* — never every frame, never on
// the render thread. The video must never stutter because of detection work.
// See `ViewerPresenceGuard` for the camera/sampler and `PresenceStateMachine`
// for the debounced reaction logic.

// MARK: - PresenceState

/// The resolved presence verdict the guard publishes to the player. Produced
/// by `PresenceStateMachine` *after* debouncing — it is never a single-frame
/// reading. `.ok` means playback may continue; every other case asks the
/// player to pause behind a recoverable overlay.
enum PresenceState: Equatable {
    /// Exactly one viewer, identity (if checked) matched — playback allowed.
    case ok
    /// No face sustained past the grace period — possible off-axis recording
    /// rig, or the student simply walked away. Recoverable.
    case noFace
    /// Two or more faces sustained — screen-sharing with another person.
    case multipleFaces
    /// A face is present but the periodic identity / liveness check failed
    /// twice — not the enrolled account owner (or a spoof). Recoverable.
    case wrongPerson
    /// Sustained zero-face *in low light*. Treated gently (a "improve
    /// lighting / tap to continue" hint) rather than a punitive black-out,
    /// because the detector simply can't see — not necessarily a violation.
    case lowLight
    /// A phone / screen / recording device is visible in frame (someone
    /// pointing a second phone at the screen to record). Only used as a hard
    /// block when `phoneDetectionBlocks` is on; otherwise surfaced as a
    /// non-blocking alert banner.
    case recordingDevice

    /// Whether this state should pause playback and show a blocking overlay.
    var isBlocking: Bool { self != .ok }
}

// MARK: - PresenceGuardConfig

/// Every performance / behaviour knob the guard exposes, with the
/// "smooth preset" defaults from the build spec. Tune `sampleFps` first —
/// it is the single biggest lever on cost.
struct PresenceGuardConfig: Equatable {

    // MARK: Sampling & camera

    /// Frames *processed* per second by the detection pipeline. The camera
    /// may deliver 30 fps; we throttle to this and discard the rest. Biggest
    /// performance lever. Spec default 2.5; smooth preset uses 2.
    var sampleFps: Double = 2.0

    /// Capture session preset. Low by design — face counting needs almost no
    /// resolution and a smaller buffer is cheaper to move and to inference.
    var cameraPreset: CameraPreset = .vga640x480

    /// Square side, in pixels, that face crops are downscaled to before
    /// identity / liveness inference (MobileFaceNet-style models want
    /// ~112–160). Keeps inference input tiny and constant.
    var inferenceInputSize: Int = 112

    // MARK: Tier cadence

    /// How often (seconds) the Tier-1 identity match runs — and *only* when
    /// Tier-0 reports exactly one face. Never continuous. Spec default 15;
    /// smooth preset 20.
    var identityMatchIntervalSec: TimeInterval = 20

    /// Cosine-distance threshold above which a face embedding is considered a
    /// different person from the enrolled owner. Higher = more permissive.
    var identityDistanceThreshold: Float = 0.42

    /// Tier-1.5 passive liveness (anti-spoof). Runs on the *same* face crop
    /// as the identity match, so it adds almost no extra cost. On-device,
    /// free, no user action. Catches casual photo / screen spoofs.
    var livenessEnabled: Bool = true

    /// Probability below which the passive liveness model treats the face as
    /// a spoof (printed photo, phone/tablet screen, replayed video).
    var livenessSpoofThreshold: Float = 0.5

    /// Tier-1.5 cloud liveness (AWS Rekognition Face Liveness). Active,
    /// prompted, paid, interrupts the user — off by default. Reserve for a
    /// periodic high-assurance re-check on suspicious events.
    var cloudLivenessEnabled: Bool = false

    /// Tier-2 phone-pointed-at-screen detection (YOLO `cell phone` class).
    /// Heavy, high false-positive rate, easily bypassed off-axis — and the
    /// moving watermark already covers the same threat with zero friction.
    /// Leave disabled.
    var tier2Enabled: Bool = false

    /// Lightweight, model-FREE phone / screen / recording-device heuristic
    /// using Vision's built-in image classifier (`VNClassifyImageRequest`).
    /// No model download. Coarser than YOLO (no bounding box) but works
    /// out of the box. Surfaced as a live indicator + alert banner.
    var phoneDetectionEnabled: Bool = true

    /// Seconds between phone-detection passes. Kept fairly tight so a phone
    /// held up to record is caught within a couple of seconds.
    var phoneDetectionIntervalSec: TimeInterval = 1.5

    /// Minimum classifier confidence for a phone/screen identifier to count.
    /// In-scene objects score low next to a face, so this is deliberately
    /// permissive — the rectangle signal backs it up.
    var phoneConfidenceThreshold: Float = 0.3

    /// Consecutive positive passes before the phone alert fires. 1 = fire on
    /// the first detection (most responsive); raise to debounce harder.
    var phoneDetectionStrikes: Int = 1

    /// When true, a confirmed recording device also pauses playback (a hard
    /// block). Default false — alert only — because the heuristic can
    /// false-positive and we don't want to rage-block on a glasses case or a
    /// dark rectangle.
    var phoneDetectionBlocks: Bool = false

    // MARK: Debounce / state machine

    /// Seconds of sustained zero-face required before blacking out. A
    /// note-taking student looks away briefly; a camera rig stays out of
    /// frame continuously. Spec default 4.
    var noFaceGraceSec: TimeInterval = 4

    /// Rolling window (in samples) the state machine evaluates. With
    /// `sampleFps` 2 this is ~5 s of history.
    var rollingWindow: Int = 10

    /// Fraction of the rolling window that must be zero-face for the
    /// "no face" condition to hold (spec: "no face in ≥8 of last 10").
    var noFaceWindowFraction: Double = 0.8

    /// Seconds of sustained 2+ faces before pausing for multiple viewers.
    var multipleFacesGraceSec: TimeInterval = 2

    /// Consecutive failed identity/liveness checks before locking to
    /// `.wrongPerson`. Spec default 2.
    var wrongPersonStrikes: Int = 2

    /// Average-luma threshold (0…1) below which a frame counts as "low light"
    /// — used to distinguish "nobody there" from "detector can't see".
    var lowLightLumaThreshold: Double = 0.16

    // MARK: Hardware

    /// iOS: Core ML → Neural Engine / GPU (`.all`). Vision uses hardware
    /// automatically. Set false to force CPU (debugging / thermal tests).
    var useHardwareAccel: Bool = true

    // MARK: Watermark

    /// Opacity of the always-on account watermark (spec 15–25%).
    var watermarkOpacity: Double = 0.18

    /// Seconds between watermark repositions. Slow drift, never distracting.
    var watermarkMoveIntervalSec: TimeInterval = 4

    // MARK: Privacy screen / camera gating

    /// Cosmetic "privacy screen" vignette: darkens the left/right edges of the
    /// video so the readable area is a central strip. NOTE: this is a visual
    /// deterrent only — software cannot physically limit the screen's viewing
    /// angle (that needs a hardware privacy filter). Real off-axis-camera
    /// defense is the watermark + presence guard + FairPlay.
    var privacyDimEnabled: Bool = true

    /// How dark the privacy vignette edges get (0…1).
    var privacyDimStrength: Double = 0.6

    /// Require camera access to watch a protected lesson. When true, denying
    /// camera permission blocks the video. Default is **false** — the camera
    /// is OPTIONAL: if the user declines, the lesson still plays (protected by
    /// the always-on watermark), which is what App Store review expects
    /// (Guideline 5.1.1 — don't withhold core functionality for a declined
    /// permission). Set true only if monitored viewing is contractually core.
    var requireCameraToView: Bool = false

    /// Gyro/accelerometer "privacy tilt": dims the video as the phone is
    /// tilted away from a head-on baseline (deters angling it toward someone
    /// beside the viewer). Camera-independent. No effect in the Simulator.
    var tiltPrivacyEnabled: Bool = true
    /// Tilt (degrees from baseline) where dimming begins.
    var tiltPrivacyStartDegrees: Double = 16
    /// Tilt (degrees) where the video is fully obscured.
    var tiltPrivacyFullDegrees: Double = 42

    /// The spec's recommended "smooth" preset, spelled out explicitly so a
    /// caller can opt in with one symbol.
    static let smooth = PresenceGuardConfig()

    // MARK: Derived

    /// Minimum seconds between two processed frames, from `sampleFps`.
    var minFrameInterval: TimeInterval { sampleFps > 0 ? 1.0 / sampleFps : 0 }
}

// MARK: - CameraPreset

/// Thin wrapper so the config stays free of an `import AVFoundation`. Mapped
/// to a real `AVCaptureSession.Preset` inside the engine.
enum CameraPreset: Equatable {
    case low          // ~192×144 — cheapest; fine for pure counting
    case cif352x288
    case vga640x480   // default
    case hd1280x720
}
