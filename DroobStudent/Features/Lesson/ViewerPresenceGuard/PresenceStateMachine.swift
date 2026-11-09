import Foundation

// MARK: - PresenceStateMachine
//
// Turns the noisy per-sample detector stream into a single debounced
// `PresenceState`. NEVER reacts to one frame — that is the whole point of
// this type. It is confined to the capture/processing queue (no locking):
// the engine feeds it samples from that queue and reads `currentState` from
// the same queue, then hops the result to the main thread to publish.
//
// Debounce rules (all configurable via `PresenceGuardConfig`):
//   • noFace        — zero faces in ≥ `noFaceWindowFraction` of the rolling
//                     window AND that condition has held ≥ `noFaceGraceSec`.
//                     Resolved as `.lowLight` instead of `.noFace` when the
//                     recent frames were mostly too dark to see.
//   • multipleFaces — 2+ faces sustained continuously ≥ `multipleFacesGraceSec`.
//   • wrongPerson   — `wrongPersonStrikes` consecutive failed identity /
//                     liveness checks (these arrive far more rarely than face
//                     samples, every `identityMatchIntervalSec`).
//
// Priority when several could fire: multipleFaces > wrongPerson > noFace/
// lowLight > ok. Multiple viewers and an unknown person are active sharing
// signals; an empty frame is the softest.

final class PresenceStateMachine {

    private let config: PresenceGuardConfig

    /// Rolling history of (timestamp, faceCount, isLowLight) face samples.
    private var samples: [FaceSample] = []

    /// Timestamp at which the rolling "no face" condition first became true;
    /// nil while it is false. Drives the grace timer.
    private var noFaceConditionSince: TimeInterval?
    /// Timestamp at which the current continuous run of 2+ faces began; nil
    /// when the latest sample had < 2 faces.
    private var multipleFacesSince: TimeInterval?
    /// Consecutive failed identity/liveness verdicts.
    private var identityStrikes: Int = 0
    /// Sticky once `wrongPersonStrikes` is reached — cleared only by a
    /// passing verdict or an explicit `reset()` (the "tap to continue" path).
    private var lockedWrongPerson: Bool = false

    private struct FaceSample {
        let time: TimeInterval
        let count: Int
        let lowLight: Bool
    }

    init(config: PresenceGuardConfig) {
        self.config = config
    }

    // MARK: Ingest

    /// Feeds one Tier-0 face-count sample and returns the freshly resolved
    /// state. `count` is the number of faces; `lowLight` is whether the frame
    /// was too dark to trust a zero reading.
    @discardableResult
    func ingestFace(count: Int, lowLight: Bool, at time: TimeInterval) -> PresenceState {
        samples.append(FaceSample(time: time, count: count, lowLight: lowLight))
        trim(now: time)

        // Continuous 2+ run tracking.
        if count >= 2 {
            if multipleFacesSince == nil { multipleFacesSince = time }
        } else {
            multipleFacesSince = nil
        }

        // Rolling "no face" condition.
        if noFaceConditionCurrentlyMet {
            if noFaceConditionSince == nil { noFaceConditionSince = time }
        } else {
            noFaceConditionSince = nil
        }

        return resolve(now: time)
    }

    /// Feeds a Tier-1 identity verdict (only produced every
    /// `identityMatchIntervalSec`, and only when exactly one face is present).
    func ingestIdentity(passed: Bool) {
        applyVerdict(passed: passed)
    }

    /// Feeds a Tier-1.5 liveness verdict. A spoof verdict is treated like a
    /// failed identity check — two in a row lock to `.wrongPerson`.
    func ingestLiveness(passed: Bool) {
        applyVerdict(passed: passed)
    }

    private func applyVerdict(passed: Bool) {
        if passed {
            identityStrikes = 0
            lockedWrongPerson = false
        } else {
            identityStrikes += 1
            if identityStrikes >= config.wrongPersonStrikes {
                lockedWrongPerson = true
            }
        }
    }

    /// Clears all debounce state and gives a fresh grace period — called when
    /// the user taps "Tap to continue" on a blocking overlay so a transient
    /// trigger doesn't immediately re-fire.
    func reset() {
        samples.removeAll(keepingCapacity: true)
        noFaceConditionSince = nil
        multipleFacesSince = nil
        identityStrikes = 0
        lockedWrongPerson = false
    }

    // MARK: Resolution

    /// Recomputes the debounced state from current buffers. Public read for
    /// the engine; pure function of internal state + `now`.
    func resolve(now: TimeInterval) -> PresenceState {
        // 1. Multiple viewers — highest priority sharing signal.
        if let since = multipleFacesSince, now - since >= config.multipleFacesGraceSec {
            return .multipleFaces
        }
        // 2. Wrong / spoofed person.
        if lockedWrongPerson {
            return .wrongPerson
        }
        // 3. Sustained no-face, split into low-light vs genuine absence.
        if let since = noFaceConditionSince, now - since >= config.noFaceGraceSec {
            return recentlyLowLight ? .lowLight : .noFace
        }
        return .ok
    }

    // MARK: Helpers

    /// Drops samples older than the window (by count and by a generous age
    /// cap so a long pause doesn't leave stale readings around).
    private func trim(now: TimeInterval) {
        if samples.count > config.rollingWindow {
            samples.removeFirst(samples.count - config.rollingWindow)
        }
        let maxAge = max(config.noFaceGraceSec, 1) * 3
        samples.removeAll { now - $0.time > maxAge }
    }

    /// True when zero-face samples make up at least `noFaceWindowFraction` of
    /// the (full) rolling window. Requires a full window so a single missed
    /// detection at startup can't trip it.
    private var noFaceConditionCurrentlyMet: Bool {
        guard samples.count >= config.rollingWindow else {
            // Before the window fills, fall back to "every sample so far is
            // zero" so a genuinely-covered camera still blocks after grace.
            return !samples.isEmpty && samples.allSatisfy { $0.count == 0 }
        }
        let zeros = samples.suffix(config.rollingWindow).filter { $0.count == 0 }.count
        let needed = Int((Double(config.rollingWindow) * config.noFaceWindowFraction).rounded(.up))
        return zeros >= needed
    }

    /// Whether the zero-face stretch is mostly dark frames — i.e. the
    /// detector probably just can't see, so we should hint about lighting
    /// rather than punish.
    private var recentlyLowLight: Bool {
        let recent = samples.suffix(config.rollingWindow).filter { $0.count == 0 }
        guard !recent.isEmpty else { return false }
        let dark = recent.filter { $0.lowLight }.count
        return Double(dark) / Double(recent.count) >= 0.5
    }
}
