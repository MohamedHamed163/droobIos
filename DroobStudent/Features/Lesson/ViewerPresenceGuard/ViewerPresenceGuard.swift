import Foundation
import AVFoundation
import Combine
import UIKit
import Vision

// MARK: - ViewerPresenceGuard
//
// The engine. Owns a low-resolution front-camera session, samples only a few
// frames per second on a background thread (dropping every backlogged frame),
// runs the tiered detection pipeline, and publishes a debounced
// `PresenceState` the player UI reacts to.
//
// Threading split (deliberate, to keep video smooth AND stay race-free):
//   • `ViewerPresenceGuard` is @MainActor — it owns only the @Published UI
//     state, the player observation, lifecycle hooks, and the block latch.
//   • `CapturePipeline` is a plain queue-confined object that owns the
//     AVCaptureSession and runs ALL detection (Vision + Core ML) on its own
//     background queues. It calls back to the engine on the main thread with
//     a resolved state. The render/main thread never does detection work.
//
// Lifecycle: the guard runs only while the video is actually playing and the
// app is foreground. It stops the pipeline and releases the camera when the
// video pauses, the app backgrounds, or a blocking state latches (recovered
// by the user tapping "continue").

@MainActor
final class ViewerPresenceGuard: ObservableObject {

    /// Debounced verdict for the UI. `.ok` until proven otherwise.
    @Published private(set) var state: PresenceState = .ok
    /// True while the camera pipeline is actively running.
    @Published private(set) var isMonitoring: Bool = false
    /// True while a blocking state has latched the player paused behind the
    /// overlay (until the user taps "continue").
    @Published private(set) var isBlocked: Bool = false

    /// Live count of faces currently in frame (Tier 0), for the on-screen
    /// status HUD. Updated only while monitoring.
    @Published private(set) var faceCount: Int = 0
    /// True when a phone / screen / recording device is currently suspected
    /// in frame (Tier 2 heuristic). Drives the live indicator + alert banner.
    @Published private(set) var phoneSuspected: Bool = false
    /// Last Tier-2 detector summary (top classifications + rectangle count).
    /// For tuning/visibility in the test harness and Xcode console.
    @Published private(set) var phoneDiagnostic: String = ""

    let config: PresenceGuardConfig

    private weak var player: AVPlayer?
    private var userId: String = ""
    private var pipeline: CapturePipeline?

    private var playerObservation: NSKeyValueObservation?
    private var lifecycleObservers: [NSObjectProtocol] = []

    init(config: PresenceGuardConfig = .smooth) {
        self.config = config
    }

    // MARK: Wiring

    /// Binds the guard to a player and the authenticated user. Sets up the
    /// capture pipeline, the play/pause observation, and app-lifecycle hooks.
    /// Call once when the guarded player appears.
    func configure(player: AVPlayer, userId: String) {
        self.player = player
        self.userId = userId

        let pipe = CapturePipeline(config: config, userId: userId)
        pipe.onState = { [weak self] resolved in
            // Delivered on the main thread by the pipeline.
            self?.handleResolvedState(resolved)
        }
        pipe.onTelemetry = { [weak self] count, phone, diag in
            // Live HUD feed, delivered on the main thread by the pipeline.
            guard let self, self.isMonitoring else { return }
            self.faceCount = count
            self.phoneSuspected = phone
            self.phoneDiagnostic = diag
        }
        self.pipeline = pipe

        observePlayer(player)
        observeLifecycle()
    }

    /// Tears everything down: stops the camera, removes observers. Call when
    /// the player view disappears.
    func teardown() {
        playerObservation?.invalidate(); playerObservation = nil
        for o in lifecycleObservers { NotificationCenter.default.removeObserver(o) }
        lifecycleObservers = []
        pipeline?.stop()
        isMonitoring = false
        clearTelemetry()
    }

    // MARK: Start / stop

    /// Starts monitoring if (and only if) the user consented, the OS granted
    /// camera access, and we aren't already running or latched-blocked.
    /// Runtime master switch for the camera presence guard (face count /
    /// identity / phone). Toggled live from the in-video privacy panel.
    private var presenceEnabled = true

    func start() {
        guard presenceEnabled else { return }
        guard PresenceConsentStore.shared.cameraUsable else { return }
        guard !isMonitoring, !isBlocked else { return }
        pipeline?.start()
        isMonitoring = true
    }

    /// Enables/disables the whole camera presence guard at runtime. When off,
    /// the camera stops; when on, the caller resumes it if the video is playing.
    func setPresenceEnabled(_ on: Bool) {
        presenceEnabled = on
        if !on { stop() }
    }

    /// Toggles Tier-2 phone/recording detection at runtime (camera keeps
    /// running for face counting).
    func setPhoneDetectionEnabled(_ on: Bool) {
        pipeline?.setPhoneDetectionEnabled(on)
    }

    /// Stops the pipeline and releases the camera.
    func stop() {
        guard isMonitoring else { return }
        pipeline?.stop()
        isMonitoring = false
        clearTelemetry()
    }

    /// Resets the live HUD readings so a stale count/phone flag doesn't linger
    /// after the camera stops.
    private func clearTelemetry() {
        faceCount = 0
        phoneSuspected = false
        phoneDiagnostic = ""
    }

    /// "Tap to continue" — clears the latched block, resets the debounce
    /// window for a fresh grace period, restarts the camera, and resumes
    /// playback.
    func continueAfterBlock() {
        isBlocked = false
        state = .ok
        pipeline?.reset()
        start()
        player?.play()
    }

    // MARK: - Test harness hooks
    //
    // Used by the in-app "Test Detection" screen. Compiled in all configs but
    // only reachable from the non-production launcher (Debug + TestFlight).

    /// Wires the capture pipeline + lifecycle WITHOUT binding to an AVPlayer,
    /// so the test harness can drive `start()`/`stop()` directly (there is no
    /// video to observe). Real camera detection runs as in production.
    func configureForTesting(userId: String) {
        self.userId = userId
        let pipe = CapturePipeline(config: config, userId: userId)
        pipe.onState = { [weak self] resolved in self?.handleResolvedState(resolved) }
        pipe.onTelemetry = { [weak self] count, phone, diag in
            guard let self, self.isMonitoring else { return }
            self.faceCount = count
            self.phoneSuspected = phone
            self.phoneDiagnostic = diag
        }
        self.pipeline = pipe
        observeLifecycle()
    }

    /// Forces a resolved state (to preview overlays on the Simulator, which
    /// has no camera).
    func debugSimulate(_ simulated: PresenceState) {
        state = simulated
        isBlocked = simulated.isBlocking
    }

    /// Forces the live HUD readings (Simulator preview).
    func debugTelemetry(faceCount: Int, phone: Bool) {
        self.faceCount = faceCount
        self.phoneSuspected = phone
    }

    // MARK: Player & lifecycle observation

    private func observePlayer(_ player: AVPlayer) {
        playerObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let status = p.timeControlStatus
            Task { @MainActor in self?.handlePlaybackStatus(status) }
        }
        handlePlaybackStatus(player.timeControlStatus)
    }

    private func handlePlaybackStatus(_ status: AVPlayer.TimeControlStatus) {
        // While a block is latched we own the paused state — ignore the pause
        // we ourselves issued so we don't double-handle it.
        guard !isBlocked else { return }
        switch status {
        case .playing:
            start()
        case .paused, .waitingToPlayAtSpecifiedRate:
            stop()
        @unknown default:
            stop()
        }
    }

    private func observeLifecycle() {
        let nc = NotificationCenter.default
        let bg = nc.addObserver(forName: UIApplication.willResignActiveNotification,
                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        let fg = nc.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.player?.timeControlStatus == .playing { self.start() }
            }
        }
        lifecycleObservers = [bg, fg]
    }

    // MARK: Reacting to resolved state

    private func handleResolvedState(_ resolved: PresenceState) {
        state = resolved
        guard resolved.isBlocking, !isBlocked else { return }
        // Latch the block: pause playback, raise the overlay, and release the
        // camera until the user taps "continue".
        isBlocked = true
        player?.pause()
        pipeline?.stop()
        isMonitoring = false
        clearTelemetry()
    }
}

// MARK: - CapturePipeline
//
// Queue-confined owner of the camera session and the detection pipeline. Not
// actor-isolated: all of its mutable state is touched only on `sessionQueue`
// (session lifecycle) or `videoQueue` (frame processing). Emits resolved
// states to `onState` on the main thread.

private final class CapturePipeline {
    /// Invoked on the MAIN thread with each newly resolved state.
    var onState: ((PresenceState) -> Void)?
    /// Invoked on the MAIN thread with live (faceCount, phoneSuspected,
    /// diagnostic) for the status HUD whenever a value changes.
    var onTelemetry: ((Int, Bool, String) -> Void)?

    private let config: PresenceGuardConfig
    private let userId: String

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "presenceguard.session")
    private let videoQueue = DispatchQueue(label: "presenceguard.video", qos: .utility)
    private let output = AVCaptureVideoDataOutput()
    private var delegate: SampleDelegate?
    private var processor: FrameProcessor?
    private var configured = false

    init(config: PresenceGuardConfig, userId: String) {
        self.config = config
        self.userId = userId
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded()
            self.loadEnrollment()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func reset() {
        videoQueue.async { [weak self] in self?.processor?.reset() }
    }

    func setPhoneDetectionEnabled(_ on: Bool) {
        videoQueue.async { [weak self] in self?.processor?.phoneRuntimeEnabled = on }
    }

    // MARK: Session config (sessionQueue only)

    private func configureIfNeeded() {
        guard !configured else { return }

        session.beginConfiguration()
        session.sessionPreset = config.cameraPreset.avPreset

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            NSLog("[PresenceGuard] no front camera input available")
            return
        }
        session.addInput(input)

        // 420 luma is cheap to read for the brightness gate; Vision is fine
        // with it too.
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        // The iOS equivalent of CameraX's STRATEGY_KEEP_ONLY_LATEST — drop
        // backlogged frames for free so we always process the freshest one.
        output.alwaysDiscardsLateVideoFrames = true

        let proc = FrameProcessor(config: config, userId: userId)
        proc.onState = { [weak self] resolved in
            DispatchQueue.main.async { self?.onState?(resolved) }
        }
        proc.onTelemetry = { [weak self] count, phone, diag in
            DispatchQueue.main.async { self?.onTelemetry?(count, phone, diag) }
        }
        let del = SampleDelegate(processor: proc)
        self.processor = proc
        self.delegate = del
        output.setSampleBufferDelegate(del, queue: videoQueue)

        if session.canAddOutput(output) { session.addOutput(output) }

        // Portrait + mirrored so an upright, portrait-held phone yields
        // upright faces to Vision (we then pass `.up`). Front-camera lesson
        // viewing is overwhelmingly portrait in this layout. 90° is the
        // portrait rotation in the iOS 17+ `videoRotationAngle` API (which
        // replaced the deprecated `videoOrientation`).
        if let conn = output.connection(with: .video) {
            let portraitAngle: CGFloat = 90
            if conn.isVideoRotationAngleSupported(portraitAngle) {
                conn.videoRotationAngle = portraitAngle
            }
            if conn.isVideoMirroringSupported { conn.isVideoMirrored = true }
        }

        session.commitConfiguration()
        configured = true
    }

    private func loadEnrollment() {
        let enrolled = FaceEnrollmentStore.shared.enrollment(for: userId)?.embedding
        let proc = processor
        videoQueue.async { proc?.setEnrolledEmbedding(enrolled) }
    }
}

// MARK: - SampleDelegate
//
// Thin AVFoundation delegate. The output holds it weakly, so the pipeline
// retains it. Forwards each frame to the FrameProcessor on the video queue
// (the same queue we registered, so no extra hop).

private final class SampleDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let processor: FrameProcessor
    init(processor: FrameProcessor) { self.processor = processor }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processor.process(pixelBuffer: pixelBuffer)
    }
}

// MARK: - FrameProcessor
//
// Confined to the video queue. Owns the tiered detectors and the debounced
// state machine, throttles to `sampleFps`, and runs the expensive identity /
// liveness tier only every `identityMatchIntervalSec` and only when exactly
// one face is present. Emits a resolved state via `onState`.

private final class FrameProcessor {
    var onState: ((PresenceState) -> Void)?
    var onTelemetry: ((Int, Bool, String) -> Void)?

    private let config: PresenceGuardConfig
    private let userId: String
    private let counter = FaceCounter()
    private let cropper: FaceCropper
    private let embedder: FaceEmbedder?
    private let liveness: LivenessClassifier?
    private let phoneDetector: PhoneScreenDetector?
    private let machine: PresenceStateMachine

    private var enrolledEmbedding: [Float]?
    private var lastProcess: TimeInterval = 0
    private var lastIdentity: TimeInterval = 0
    private var lastPublished: PresenceState = .ok

    // Tier 2 phone detection (debounced) + last-reported telemetry.
    /// Runtime toggle (from the in-video privacy panel). Defaults to the
    /// config value; set live via the pipeline on the video queue.
    var phoneRuntimeEnabled: Bool
    private var lastPhoneCheck: TimeInterval = 0
    private var phoneStrikes: Int = 0
    private var phoneConfirmed: Bool = false
    private var phoneDiag: String = ""
    private var lastFaceCountReported: Int = -1
    private var lastPhoneReported: Bool = false
    private var lastDiagReported: String = ""

    init(config: PresenceGuardConfig, userId: String) {
        self.config = config
        self.userId = userId
        self.cropper = FaceCropper(useHardwareAccel: config.useHardwareAccel)
        self.embedder = PresenceModelFactory.makeEmbedder(config)
        self.liveness = PresenceModelFactory.makeLiveness(config)
        self.phoneDetector = config.phoneDetectionEnabled
            ? PhoneScreenDetector(threshold: config.phoneConfidenceThreshold)
            : nil
        self.phoneRuntimeEnabled = config.phoneDetectionEnabled
        self.machine = PresenceStateMachine(config: config)
    }

    func setEnrolledEmbedding(_ embedding: [Float]?) {
        enrolledEmbedding = embedding
    }

    func reset() {
        machine.reset()
        lastPublished = .ok
        lastProcess = 0
        phoneStrikes = 0
        phoneConfirmed = false
        phoneDiag = ""
        lastFaceCountReported = -1
        lastPhoneReported = false
        lastDiagReported = ""
        // Keep `lastIdentity` so we don't hammer the model right after a
        // resume; the interval timer carries over.
    }

    func process(pixelBuffer: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        // Frame sampler: skip anything that arrives faster than our target
        // cadence. This is the single biggest cost control.
        guard now - lastProcess >= config.minFrameInterval else { return }
        lastProcess = now

        // Tier 0 — face count + brightness (cheap, every sample).
        let result = counter.analyze(pixelBuffer, orientation: .up)
        let lowLight = result.luma < config.lowLightLumaThreshold
        machine.ingestFace(count: result.faceCount, lowLight: lowLight, at: now)

        // Tier 1 / 1.5 — identity + liveness (medium, rare): only with
        // exactly one face, only every `identityMatchIntervalSec`, only when
        // a model is actually bundled.
        if result.faceCount == 1,
           let face = result.largestFace,
           embedder != nil,
           now - lastIdentity >= config.identityMatchIntervalSec,
           !lowLight {
            lastIdentity = now
            runIdentity(on: pixelBuffer, face: face)
        }

        // Tier 2 — phone / recording-device heuristic (model-free, debounced).
        // Runs regardless of face count (someone watching can still hold a
        // second phone up to record).
        if phoneRuntimeEnabled, let phoneDetector,
           now - lastPhoneCheck >= config.phoneDetectionIntervalSec {
            lastPhoneCheck = now
            let phone = phoneDetector.detect(pixelBuffer, orientation: .up)
            phoneDiag = phone.diagnostic
            if phone.detected {
                phoneStrikes += 1
                if phoneStrikes >= config.phoneDetectionStrikes { phoneConfirmed = true }
            } else {
                phoneStrikes = 0
                phoneConfirmed = false
            }
            #if DEBUG
            NSLog("[PresenceGuard] phone? \(phone.detected) [\(phone.label ?? "-")] \(phone.diagnostic)")
            #endif
        } else if !phoneRuntimeEnabled, phoneConfirmed {
            // Toggled off — clear the REC indicator.
            phoneConfirmed = false
            phoneStrikes = 0
            phoneDiag = ""
        }

        // Live HUD telemetry — emit when face count, phone state, OR the
        // diagnostic changes (the diagnostic refreshes each Tier-2 pass so the
        // harness shows live readings).
        if result.faceCount != lastFaceCountReported
            || phoneConfirmed != lastPhoneReported
            || phoneDiag != lastDiagReported {
            lastFaceCountReported = result.faceCount
            lastPhoneReported = phoneConfirmed
            lastDiagReported = phoneDiag
            onTelemetry?(result.faceCount, phoneConfirmed, phoneDiag)
        }

        var resolved = machine.resolve(now: now)
        // A confirmed recording device blocks only when configured to (default
        // is alert-only via telemetry above); never override a stronger
        // face-based block.
        if phoneConfirmed, config.phoneDetectionBlocks, resolved == .ok {
            resolved = .recordingDevice
        }
        if resolved != lastPublished {
            lastPublished = resolved
            onState?(resolved)
        }
    }

    /// Crops the face once and runs identity + (same-crop) liveness. On the
    /// very first run with no enrollment yet, captures the template once
    /// (embedding only) and treats it as a pass — the device owner self-
    /// enrolls on first watch.
    private func runIdentity(on pixelBuffer: CVPixelBuffer, face: VNFaceObservation) {
        guard let embedder,
              let crop = cropper.crop(pixelBuffer, face: face, side: config.inferenceInputSize),
              let embedding = try? embedder.embedding(from: crop), !embedding.isEmpty
        else { return }

        if let enrolled = enrolledEmbedding {
            let distance = cosineDistance(embedding, enrolled)
            machine.ingestIdentity(passed: distance <= config.identityDistanceThreshold)
        } else {
            // Capture-once enrollment (embedding only, on-device).
            enrolledEmbedding = embedding
            FaceEnrollmentStore.shared.save(userId: userId, embedding: embedding,
                                            at: Date().timeIntervalSince1970)
            machine.ingestIdentity(passed: true)
        }

        // Tier 1.5 — passive liveness on the same crop.
        if let liveness, let prob = try? liveness.livenessProbability(from: crop) {
            machine.ingestLiveness(passed: prob >= config.livenessSpoofThreshold)
        }
    }
}

// MARK: - CameraPreset → AVCaptureSession.Preset

extension CameraPreset {
    var avPreset: AVCaptureSession.Preset {
        switch self {
        case .low:        return .low
        case .cif352x288: return .cif352x288
        case .vga640x480: return .vga640x480
        case .hd1280x720: return .hd1280x720
        }
    }
}
