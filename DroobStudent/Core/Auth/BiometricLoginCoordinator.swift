import Foundation

// MARK: - BiometricAPI

/// Network surface the coordinator depends on. Wraps the three
/// biometric endpoints so the coordinator can be tested against a fake
/// without spinning up URLSession.
protocol BiometricAPI {
    /// `POST /v1/auth/biometric/register` — requires an authenticated
    /// session. Server stores the SPKI under the caller's user_id.
    func registerDevice(
        publicKeyDerBase64: String, keyLabel: String?, biometryType: String?
    ) async throws

    /// `POST /v1/auth/biometric/challenge` — anonymous; identified via
    /// `X-Device-Id` header. Returns nonce bytes the client must sign.
    func issueChallenge() async throws -> Data

    /// `POST /v1/auth/biometric/verify` — anonymous. Returns the
    /// access/refresh token pair on success.
    func verify(nonce: Data, signature: Data) async throws -> AuthTokens
}

// MARK: - DefaultBiometricAPI

/// Production `BiometricAPI` built on top of {@link APIClient} and
/// {@link AuthInterceptor}. Routes the authenticated `register` call
/// through the interceptor (so a 401 refreshes the access token) and
/// the two anonymous calls through `APIClient` directly.
struct DefaultBiometricAPI: BiometricAPI {
    func registerDevice(
        publicKeyDerBase64: String, keyLabel: String?, biometryType: String?
    ) async throws {
        let body = BiometricRegisterBody(
            publicKey: publicKeyDerBase64,
            keyLabel: keyLabel,
            biometry: biometryType)
        let request = APIRequest(
            path: "/v1/auth/biometric/register", method: .POST, body: body)
        _ = try await AuthInterceptor.shared.execute(request) as EmptyResponse
    }

    func issueChallenge() async throws -> Data {
        let request = APIRequest(
            path: "/v1/auth/biometric/challenge", method: .POST,
            requiresAuth: false)
        let response: BiometricChallengeBody = try await APIClient.shared.execute(
            request, accessToken: nil)
        guard let nonce = Data(base64Encoded: response.nonce) else {
            throw DroobError.serverError(message: "Malformed biometric challenge", messageAr: L10n.errBadResponse)
        }
        return nonce
    }

    func verify(nonce: Data, signature: Data) async throws -> AuthTokens {
        let body = BiometricVerifyBody(
            nonce: nonce.base64EncodedString(),
            signature: signature.base64EncodedString())
        let request = APIRequest(
            path: "/v1/auth/biometric/verify", method: .POST,
            body: body, requiresAuth: false)
        return try await APIClient.shared.execute(request, accessToken: nil)
    }
}

// MARK: - BiometricLoginCoordinator

/// Orchestrates the two biometric flows:
///
/// - **Enroll** (`enroll`) — called from Settings after the user opts in
///   from a session that's already password-authenticated. Generates a
///   Secure Enclave key, uploads its public part, and remembers the
///   enrollment locally.
/// - **Login** (`signIn`) — called from the login screen when no
///   session exists but a prior enrollment is present. Asks the server
///   for a nonce, signs it via Face ID, exchanges the signature for
///   tokens, and stores them.
///
/// Both calls are async/throws. The view models translate `DroobError`
/// and `DeviceKeyStoreError` into UI states.
@MainActor
final class BiometricLoginCoordinator {

    static let shared = BiometricLoginCoordinator()

    private let keyStore: BiometricKeyStoring
    private let biometrics: BiometricAuthService
    private let api: BiometricAPI
    private let tokenStore: TokenStoring
    private let defaults: UserDefaults
    private let enrollmentDefault = "droob.biometric.enrolled"
    private let enrolledUserDefault = "droob.biometric.enrolledUserId"

    init(
        keyStore: BiometricKeyStoring = DeviceKeyStore(),
        biometrics: BiometricAuthService = BiometricAuthService(),
        api: BiometricAPI = DefaultBiometricAPI(),
        tokenStore: TokenStoring = TokenStore.shared,
        defaults: UserDefaults = .standard
    ) {
        self.keyStore = keyStore
        self.biometrics = biometrics
        self.api = api
        self.tokenStore = tokenStore
        self.defaults = defaults
    }

    /// True iff this install has completed enrollment AND still has a
    /// usable Secure Enclave key. Used by the login screen to decide
    /// whether to render the Face ID button.
    var isEnrolled: Bool {
        return defaults.bool(forKey: enrollmentDefault)
            && keyStore.hasKey
    }

    /// The user_id of whoever enrolled this device, if any. Used to
    /// auto-unenroll when a different user signs in on the same
    /// device — otherwise User B could tap "Sign In with Face ID"
    /// after User A enrolled and be silently signed in as User A.
    var enrolledUserId: String? {
        defaults.string(forKey: enrolledUserDefault)
    }

    /// Generates a fresh Secure Enclave key, prompts the user for
    /// Face ID to confirm the enrollment works, uploads the public
    /// part to the server, and flips the enrolled flag.
    ///
    /// `userId` is stored alongside the flag so {@link
    /// enrolledUserId} can later detect if a different user signs in
    /// on this device — see {@link AuthSession.fetchCurrentUser}.
    ///
    /// `confirmReason` is the string shown in the Face ID prompt.
    /// Must be called from an already-authenticated session — the
    /// server endpoint requires a bearer token.
    func enroll(keyLabel: String?, userId: String, confirmReason: String) async throws {
        let publicKeyDer = try keyStore.generateKey()
        let biometryType = biometrics.availability().rawType
        do {
            // Force a Face ID / Touch ID prompt RIGHT NOW so the user
            // explicitly confirms enrollment. Without this, the key is
            // generated silently and the first prompt would be at the
            // next sign-in — which makes the enrollment toggle feel
            // like it did nothing. Also a sanity check that the SE
            // key actually works on this device.
            //
            // The signature output is discarded. We only care that the
            // sign call returns without throwing, which means the user
            // passed biometric auth and the SE key is functional.
            let enrollmentProbe = "droob.biometric.enrollment-probe".data(using: .utf8)!
            _ = try keyStore.sign(payload: enrollmentProbe, reason: confirmReason)

            try await api.registerDevice(
                publicKeyDerBase64: publicKeyDer.base64EncodedString(),
                keyLabel: keyLabel,
                biometryType: biometryType)
        } catch {
            // Roll back the half-completed enrollment. Covers both the
            // user-cancelled-Face-ID case and the server-rejection
            // case. Don't want a Secure Enclave key dangling without
            // a matching server row, or vice versa.
            keyStore.deleteKey()
            throw error
        }
        defaults.set(true, forKey: enrollmentDefault)
        defaults.set(userId, forKey: enrolledUserDefault)
    }

    /// Reverses an enrollment: deletes the local key and the flag. The
    /// server-side row stays (the user might re-enroll on the same
    /// device) but becomes unusable because there's no matching private
    /// key. Could be extended later with a `DELETE /biometric/device`
    /// endpoint.
    func unenroll() {
        keyStore.deleteKey()
        defaults.removeObject(forKey: enrollmentDefault)
        defaults.removeObject(forKey: enrolledUserDefault)
    }

    /// Performs a biometric sign-in: pulls a nonce, prompts Face ID to
    /// sign it, exchanges the signature for tokens. On success the
    /// caller should refresh `AuthSession` via `bootstrap()` so the
    /// session state advances to `.authenticated`.
    func signIn(reason: String) async throws -> AuthTokens {
        let nonce = try await api.issueChallenge()
        let signature = try keyStore.sign(payload: nonce, reason: reason)
        let tokens = try await api.verify(nonce: nonce, signature: signature)
        tokenStore.save(tokens: tokens)
        return tokens
    }
}

// MARK: - TokenStoring (test seam)

/// Tiny protocol over the bits of {@link TokenStore} the coordinator
/// uses, so tests can drop in a fake without touching the Keychain.
protocol TokenStoring {
    func save(tokens: AuthTokens)
}

extension TokenStore: TokenStoring {}

// MARK: - Request / response bodies

private struct BiometricRegisterBody: Encodable {
    let publicKey: String
    let keyLabel: String?
    let biometry: String?
    enum CodingKeys: String, CodingKey {
        case publicKey = "public_key"
        case keyLabel  = "key_label"
        case biometry
    }
}

private struct BiometricChallengeBody: Decodable {
    let nonce: String
    let expiresAt: Date?
    enum CodingKeys: String, CodingKey {
        case nonce
        case expiresAt = "expires_at"
    }
}

private struct BiometricVerifyBody: Encodable {
    let nonce: String
    let signature: String
}

// MARK: - BiometryAvailability bridge

private extension BiometryAvailability {
    /// Wire format used by the backend's `biometry_type` column.
    var rawType: String? {
        if case .available(let type) = self { return type.rawValue }
        return nil
    }
}
