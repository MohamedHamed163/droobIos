import Foundation
import CoreMotion
import Combine

// MARK: - PrivacyTiltMonitor
//
// A "privacy screen" approximation driven by the gyroscope/accelerometer
// (Core Motion, no permission required). It learns the angle at which the
// phone is being held head-on and, when the device is *tilted away* from that
// baseline (e.g. angled toward someone sitting beside the viewer), it raises
// an `obscureLevel` (0 = clear … 1 = fully obscured). The host dims/blurs the
// video by that amount, so only the person holding it head-on can comfortably
// see it.
//
// HONEST LIMITATIONS:
//  • Software can't physically limit a screen's viewing angle (that needs a
//    hardware privacy film). This dims content based on device *tilt* — it
//    deters "tilt the phone to show my neighbour", not a fixed off-axis stare.
//  • Motion sensors only exist on real devices (no effect in the Simulator).
//  • "Who is in front of the phone" specifically is handled by the front-camera
//    presence guard; this layer is camera-independent and works even if the
//    user declined camera access.

@MainActor
final class PrivacyTiltMonitor: ObservableObject {
    /// 0 = clear, 1 = fully obscured. Smoothed for animation.
    @Published private(set) var obscureLevel: Double = 0
    /// Signed, normalized tilt direction (−1…1) relative to the head-on
    /// baseline. Drives the parallax "3D" privacy layer so the clear window
    /// shifts toward the front and the off-axis side darkens.
    @Published private(set) var tiltX: Double = 0   // roll  (left/right)
    @Published private(set) var tiltY: Double = 0   // pitch (up/down)

    private let motion = CMMotionManager()
    private let startDeg: Double   // tilt where dimming begins
    private let fullDeg: Double    // tilt where fully obscured

    /// Adaptive "comfortable viewing" baseline (radians). Tracks slow
    /// re-orientation (walking, reclining) so only *sudden* tilts obscure.
    private var baselineRoll: Double?
    private var baselinePitch: Double?

    init(startDegrees: Double = 16, fullDegrees: Double = 42) {
        self.startDeg = startDegrees
        self.fullDeg = max(fullDegrees, startDegrees + 1)
    }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let att = data?.attitude else { return }
            self.process(roll: att.roll, pitch: att.pitch)
        }
    }

    func stop() {
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
        baselineRoll = nil
        baselinePitch = nil
        if obscureLevel != 0 { obscureLevel = 0 }
        tiltX = 0
        tiltY = 0
    }

    // MARK: Processing (main thread — deliveries are queued to .main)

    private func process(roll: Double, pitch: Double) {
        guard let bRoll = baselineRoll, let bPitch = baselinePitch else {
            baselineRoll = roll; baselinePitch = pitch
            return
        }
        let sRoll = Self.angularDelta(roll, bRoll) * 180 / .pi   // signed degrees
        let sPitch = Self.angularDelta(pitch, bPitch) * 180 / .pi
        let deviationDeg = max(abs(sRoll), abs(sPitch))

        let level = Self.smoothstep(deviationDeg, edge0: startDeg, edge1: fullDeg)
        let nx = min(max(sRoll / fullDeg, -1), 1)
        let ny = min(max(sPitch / fullDeg, -1), 1)

        // Only publish on a meaningful change (avoids 30 Hz churn).
        if abs(level - obscureLevel) > 0.02 || (level == 0 && obscureLevel != 0) {
            obscureLevel = level
        }
        if abs(nx - tiltX) > 0.03 { tiltX = nx }
        if abs(ny - tiltY) > 0.03 { tiltY = ny }

        // Adapt the baseline ONLY while held roughly head-on, so a deliberate
        // tilt doesn't "teach" itself as the new normal — but slow drift
        // (reclining, turning) is followed and won't dim.
        if level < 0.1 {
            baselineRoll = Self.ema(bRoll, roll, 0.03)
            baselinePitch = Self.ema(bPitch, pitch, 0.03)
        }
    }

    // MARK: Math

    /// Shortest signed angle a−b, wrapped to −π…π.
    private static func angularDelta(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    private static func ema(_ prev: Double, _ next: Double, _ alpha: Double) -> Double {
        prev + alpha * angularDelta(next, prev)
    }

    private static func smoothstep(_ x: Double, edge0: Double, edge1: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
