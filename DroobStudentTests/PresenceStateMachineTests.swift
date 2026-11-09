import XCTest
@testable import DroobStudent

/// Validates the debounced presence state machine against the build spec's
/// acceptance criteria: brief look-aways don't block, sustained conditions do,
/// low light is distinguished from absence, and identity failures need two
/// strikes.
final class PresenceStateMachineTests: XCTestCase {

    private func makeConfig() -> PresenceGuardConfig {
        var c = PresenceGuardConfig()
        c.rollingWindow = 10
        c.noFaceWindowFraction = 0.8
        c.noFaceGraceSec = 4
        c.multipleFacesGraceSec = 2
        c.wrongPersonStrikes = 2
        return c
    }

    // MARK: No-face debounce

    /// Looking away briefly (≤3s, under the 4s grace) must NOT black out.
    func testBriefLookAwayDoesNotBlock() {
        let sm = PresenceStateMachine(config: makeConfig())
        var t = 0.0
        // 3 seconds of zero faces (7 samples at 0.5s spacing: 0…3.0).
        while t <= 3.0 {
            XCTAssertEqual(sm.ingestFace(count: 0, lowLight: false, at: t), .ok,
                           "should stay ok at t=\(t) (under grace)")
            t += 0.5
        }
        // Student looks back before the grace elapses.
        XCTAssertEqual(sm.ingestFace(count: 1, lowLight: false, at: 3.5), .ok)
    }

    /// A sustained empty frame past the grace period blacks out as `.noFace`.
    func testSustainedNoFaceBlocks() {
        let sm = PresenceStateMachine(config: makeConfig())
        var last: PresenceState = .ok
        var t = 0.0
        while t < 4.0 {
            last = sm.ingestFace(count: 0, lowLight: false, at: t)
            t += 0.5
        }
        XCTAssertEqual(last, .ok, "still within grace just before 4s")
        XCTAssertEqual(sm.ingestFace(count: 0, lowLight: false, at: 4.0), .noFace,
                       "grace elapsed → noFace")
    }

    /// Sustained zero-face in the dark is a gentle `.lowLight`, not `.noFace`.
    func testSustainedNoFaceInLowLight() {
        let sm = PresenceStateMachine(config: makeConfig())
        var t = 0.0
        while t < 4.0 {
            _ = sm.ingestFace(count: 0, lowLight: true, at: t)
            t += 0.5
        }
        XCTAssertEqual(sm.ingestFace(count: 0, lowLight: true, at: 4.0), .lowLight)
    }

    // MARK: Multiple faces

    /// 2+ faces sustained ~2s pauses with `.multipleFaces`.
    func testSustainedMultipleFacesBlocks() {
        let sm = PresenceStateMachine(config: makeConfig())
        XCTAssertEqual(sm.ingestFace(count: 2, lowLight: false, at: 0.0), .ok)
        XCTAssertEqual(sm.ingestFace(count: 2, lowLight: false, at: 1.0), .ok)
        XCTAssertEqual(sm.ingestFace(count: 2, lowLight: false, at: 1.5), .ok)
        XCTAssertEqual(sm.ingestFace(count: 2, lowLight: false, at: 2.0), .multipleFaces,
                       "2s of sustained 2+ faces → multipleFaces")
    }

    /// A brief second face (under the 2s grace) does not block.
    func testBriefSecondFaceDoesNotBlock() {
        let sm = PresenceStateMachine(config: makeConfig())
        XCTAssertEqual(sm.ingestFace(count: 2, lowLight: false, at: 0.0), .ok)
        XCTAssertEqual(sm.ingestFace(count: 2, lowLight: false, at: 1.0), .ok)
        // Second person leaves before grace elapses.
        XCTAssertEqual(sm.ingestFace(count: 1, lowLight: false, at: 1.5), .ok)
        XCTAssertEqual(sm.ingestFace(count: 2, lowLight: false, at: 2.0), .ok,
                       "run restarted; only 0s sustained again")
    }

    // MARK: Identity / liveness strikes

    /// One identity failure is tolerated; two consecutive locks `.wrongPerson`.
    func testTwoIdentityStrikesLockWrongPerson() {
        let sm = PresenceStateMachine(config: makeConfig())
        _ = sm.ingestFace(count: 1, lowLight: false, at: 0.0)
        sm.ingestIdentity(passed: false)
        XCTAssertEqual(sm.resolve(now: 0.1), .ok, "one strike is tolerated")
        sm.ingestIdentity(passed: false)
        XCTAssertEqual(sm.resolve(now: 0.2), .wrongPerson, "second strike locks")
    }

    /// A passing check resets the strike counter.
    func testPassingCheckResetsStrikes() {
        let sm = PresenceStateMachine(config: makeConfig())
        _ = sm.ingestFace(count: 1, lowLight: false, at: 0.0)
        sm.ingestIdentity(passed: false)
        sm.ingestIdentity(passed: true)          // reset
        sm.ingestIdentity(passed: false)         // strike 1 again
        XCTAssertEqual(sm.resolve(now: 0.3), .ok, "counter was reset by the pass")
    }

    /// Two spoof (liveness) verdicts also lock `.wrongPerson`.
    func testTwoSpoofVerdictsLock() {
        let sm = PresenceStateMachine(config: makeConfig())
        _ = sm.ingestFace(count: 1, lowLight: false, at: 0.0)
        sm.ingestLiveness(passed: false)
        sm.ingestLiveness(passed: false)
        XCTAssertEqual(sm.resolve(now: 0.2), .wrongPerson)
    }

    // MARK: Baseline & reset

    /// Exactly one face is the happy path.
    func testSingleFaceIsOk() {
        let sm = PresenceStateMachine(config: makeConfig())
        for i in 0..<12 {
            XCTAssertEqual(sm.ingestFace(count: 1, lowLight: false, at: Double(i) * 0.5), .ok)
        }
    }

    /// `reset()` (the "tap to continue" path) clears a latched block.
    func testResetClearsState() {
        let sm = PresenceStateMachine(config: makeConfig())
        var t = 0.0
        while t <= 4.0 { _ = sm.ingestFace(count: 0, lowLight: false, at: t); t += 0.5 }
        XCTAssertEqual(sm.resolve(now: 4.0), .noFace)
        sm.reset()
        XCTAssertEqual(sm.resolve(now: 4.0), .ok, "reset gives a fresh grace period")
    }

    /// Multiple faces outranks a no-face reading when both could apply over
    /// the window (priority check).
    func testMultiplePriorityOverNoFace() {
        let sm = PresenceStateMachine(config: makeConfig())
        // Build a mostly-empty window, then a sustained 2-face run.
        for i in 0..<6 { _ = sm.ingestFace(count: 0, lowLight: false, at: Double(i) * 0.5) }
        var t = 3.0
        while t <= 5.0 { _ = sm.ingestFace(count: 2, lowLight: false, at: t); t += 0.5 }
        XCTAssertEqual(sm.resolve(now: 5.0), .multipleFaces)
    }
}
