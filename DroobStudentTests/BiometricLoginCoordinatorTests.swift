import XCTest
@testable import DroobStudent

/// Tests for `BiometricLoginCoordinator` orchestration logic.
///
/// Touches neither the Secure Enclave nor the network: the coordinator
/// is constructed with fakes for `BiometricKeyStoring`, `BiometricAPI`,
/// and `TokenStoring`. The real Secure Enclave + LocalAuthentication
/// code paths are exercised only on device — there's no way to enroll a
/// face in the simulator and `SecKeyCreateRandomKey` with
/// `kSecAttrTokenIDSecureEnclave` fails outside one.
final class BiometricLoginCoordinatorTests: XCTestCase {

    // MARK: - enroll

    @MainActor
    func testEnrollGeneratesKeyPromptsAndFlipsFlag() async throws {
        let keyStore = FakeKeyStore()
        let api = FakeBiometricAPI()
        let tokenStore = FakeTokenStore()
        let coord = Self.makeCoordinator(
            keyStore: keyStore, api: api, tokenStore: tokenStore)

        try await coord.enroll(
            keyLabel: "Test phone",
            userId: "user-123",
            confirmReason: "Enable Face ID")

        XCTAssertTrue(keyStore.generateKeyCalled)
        // The enrollment must trigger a sign() call as the Face ID
        // probe — otherwise the user gets no prompt and can't confirm
        // the enrollment worked.
        XCTAssertNotNil(keyStore.signedPayload)
        XCTAssertEqual(api.registeredKey, keyStore.publicKeyBytes.base64EncodedString())
        XCTAssertEqual(api.registeredLabel, "Test phone")
        XCTAssertTrue(coord.isEnrolled)
        XCTAssertEqual(coord.enrolledUserId, "user-123")
    }

    @MainActor
    func testEnrollRollsBackIfUserCancelsBiometricProbe() async {
        let keyStore = FakeKeyStore()
        keyStore.signError = DeviceKeyStoreError.signingFailed(
            NSError(domain: "com.apple.LocalAuthentication", code: -2))
        let api = FakeBiometricAPI()
        let coord = Self.makeCoordinator(
            keyStore: keyStore, api: api, tokenStore: FakeTokenStore())

        do {
            try await coord.enroll(
                keyLabel: nil, userId: "u", confirmReason: "x")
            XCTFail("Should have thrown")
        } catch {}

        // Key was generated, then cancelled — must be deleted to
        // avoid a dangling Secure Enclave key.
        XCTAssertTrue(keyStore.deleteCalled)
        // Server must NOT have been called — we only register after
        // the user confirms via Face ID.
        XCTAssertNil(api.registeredKey)
        XCTAssertFalse(coord.isEnrolled)
    }

    @MainActor
    func testEnrollDeletesKeyIfServerRejects() async {
        let keyStore = FakeKeyStore()
        let api = FakeBiometricAPI()
        api.registerError = DroobError.serverError("nope")
        let coord = Self.makeCoordinator(
            keyStore: keyStore, api: api, tokenStore: FakeTokenStore())

        do {
            try await coord.enroll(
                keyLabel: nil, userId: "u", confirmReason: "x")
            XCTFail("Should have thrown")
        } catch {}
        XCTAssertTrue(keyStore.deleteCalled)
        XCTAssertFalse(coord.isEnrolled)
    }

    // MARK: - unenroll

    @MainActor
    func testUnenrollDeletesKeyAndClearsFlagAndUser() {
        let keyStore = FakeKeyStore()
        let coord = Self.makeCoordinator(
            keyStore: keyStore, api: FakeBiometricAPI(),
            tokenStore: FakeTokenStore())

        Self.testDefaults().set(true, forKey: "droob.biometric.enrolled")
        Self.testDefaults().set("user-1", forKey: "droob.biometric.enrolledUserId")
        coord.unenroll()

        XCTAssertTrue(keyStore.deleteCalled)
        XCTAssertFalse(coord.isEnrolled)
        XCTAssertNil(coord.enrolledUserId)
    }

    // MARK: - signIn

    @MainActor
    func testSignInRoundTripsNonceAndStoresTokens() async throws {
        let keyStore = FakeKeyStore()
        let api = FakeBiometricAPI()
        api.challengeNonce = Data([0x01, 0x02, 0x03])
        let tokenStore = FakeTokenStore()
        let coord = Self.makeCoordinator(
            keyStore: keyStore, api: api, tokenStore: tokenStore)

        _ = try await coord.signIn(reason: "Sign in")

        XCTAssertEqual(keyStore.signedPayload, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(api.verifyNonce, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(api.verifySignature, keyStore.fakeSignature)
        XCTAssertEqual(tokenStore.saved?.accessToken, "fake-access")
    }

    @MainActor
    func testSignInPropagatesSigningError() async {
        let keyStore = FakeKeyStore()
        keyStore.signError = DeviceKeyStoreError.keyNotFound
        let coord = Self.makeCoordinator(
            keyStore: keyStore, api: FakeBiometricAPI(),
            tokenStore: FakeTokenStore())

        do {
            _ = try await coord.signIn(reason: "x")
            XCTFail("Should have thrown")
        } catch let error as DeviceKeyStoreError {
            if case .keyNotFound = error { return }
            XCTFail("Wrong error case: \(error)")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Helpers

    /// Each test gets its own isolated `UserDefaults` suite so the
    /// enrolled-flag persists across the coordinator's reads but
    /// doesn't bleed between test methods.
    private static func testDefaults() -> UserDefaults {
        // The test target's bundle id varies; use a fixed suite name
        // so all calls inside one test resolve to the same defaults.
        // Cleared in `setUp`.
        return UserDefaults(suiteName: "droob.biometric.tests")!
    }

    @MainActor
    private static func makeCoordinator(
        keyStore: BiometricKeyStoring,
        api: BiometricAPI,
        tokenStore: TokenStoring
    ) -> BiometricLoginCoordinator {
        return BiometricLoginCoordinator(
            keyStore: keyStore, api: api, tokenStore: tokenStore,
            defaults: testDefaults())
    }

    override func setUp() {
        super.setUp()
        let d = Self.testDefaults()
        d.removeObject(forKey: "droob.biometric.enrolled")
        d.removeObject(forKey: "droob.biometric.enrolledUserId")
    }
}

// MARK: - Fakes

/// In-memory `BiometricKeyStoring` that returns deterministic bytes and
/// records every call so tests can assert on what was invoked.
private final class FakeKeyStore: BiometricKeyStoring {
    let publicKeyBytes = Data([0x30, 0x59, 0x00])
    let fakeSignature = Data([0xAB, 0xCD])

    var generateKeyCalled = false
    var deleteCalled = false
    var signedPayload: Data?
    var signError: Error?

    var hasKey: Bool { true }

    func generateKey() throws -> Data {
        generateKeyCalled = true
        return publicKeyBytes
    }

    func sign(payload: Data, reason: String) throws -> Data {
        if let error = signError { throw error }
        signedPayload = payload
        return fakeSignature
    }

    func deleteKey() {
        deleteCalled = true
    }
}

private final class FakeBiometricAPI: BiometricAPI {
    var registeredKey: String?
    var registeredLabel: String?
    var registerError: Error?

    var challengeNonce = Data([0xFF])
    var verifyNonce: Data?
    var verifySignature: Data?

    func registerDevice(
        publicKeyDerBase64: String, keyLabel: String?, biometryType: String?
    ) async throws {
        if let error = registerError { throw error }
        registeredKey = publicKeyDerBase64
        registeredLabel = keyLabel
    }

    func issueChallenge() async throws -> Data {
        return challengeNonce
    }

    func verify(nonce: Data, signature: Data) async throws -> AuthTokens {
        verifyNonce = nonce
        verifySignature = signature
        return AuthTokens(
            accessToken: "fake-access", refreshToken: "fake-refresh", expiresIn: 60)
    }
}

private final class FakeTokenStore: TokenStoring {
    var saved: AuthTokens?
    func save(tokens: AuthTokens) {
        saved = tokens
    }
}

/// Tests need an inits-from-fields path on `AuthTokens`. The production
/// type is decoded from JSON; add a convenience init via extension so
/// the test file owns it and prod code stays decode-only.
private extension AuthTokens {
    init(accessToken: String, refreshToken: String, expiresIn: Int) {
        // Decode through JSON so we don't fight Decodable-only structs.
        let json = """
        {"access_token":"\(accessToken)","refresh_token":"\(refreshToken)","expires_in":\(expiresIn)}
        """.data(using: .utf8)!
        self = try! JSONDecoder().decode(AuthTokens.self, from: json)
    }
}
