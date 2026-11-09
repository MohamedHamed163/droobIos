import Foundation

// MARK: - AuthInterceptor
// Actor-isolated to prevent concurrent refresh races.

actor AuthInterceptor {
    static let shared = AuthInterceptor()

    private let client = APIClient.shared
    private var isRefreshing = false
    private var pendingContinuations: [CheckedContinuation<String, Error>] = []

    private init() {}

    /// Execute an authenticated request, transparently refreshing on 401 once.
    func execute<T: Decodable>(_ apiRequest: APIRequest) async throws -> T {
        guard let accessToken = TokenStore.shared.accessToken else {
            throw DroobError.unauthenticated(message: nil, messageAr: nil)
        }

        do {
            return try await client.execute(apiRequest, accessToken: accessToken)
        } catch let DroobError.unauthenticated(message, messageAr) {
            // A 401 that carries a server problem-detail message is a DOMAIN
            // rejection (invalid/expired OTP, wrong passcode, …) — NOT a dead
            // session. The backend renders these via DroobException, whereas a
            // genuinely expired token yields a *bare*, body-less 401. Refreshing
            // a domain 401 is pointless (the token is fine) and, worse, if that
            // refresh ever fails it collapses into a bare `.unauthenticated(nil,
            // nil)` that call sites read as session expiry and sign the user out
            // — exactly the "wrong code in change-email logs me out" bug. Only a
            // bare 401 is worth a refresh+retry; surface domain 401s unchanged.
            guard message == nil, messageAr == nil else {
                throw DroobError.unauthenticated(message: message, messageAr: messageAr)
            }
            let newToken = try await refreshTokens()
            return try await client.execute(apiRequest, accessToken: newToken)
        }
    }

    /// Execute a request that works with OR without auth. A signed-in user
    /// sends their token (and gets the personalised view + transparent
    /// 401-refresh); a guest with no token sends none and gets the public
    /// view. Unlike {@link execute}, this never throws `.unauthenticated`
    /// merely because the caller has no token — that's the whole point of a
    /// pre-login "browse courses" surface (App Store Guideline 5.1.1(v)).
    func executePublic<T: Decodable>(_ apiRequest: APIRequest) async throws -> T {
        let token = TokenStore.shared.accessToken
        do {
            return try await client.execute(apiRequest, accessToken: token)
        } catch let DroobError.unauthenticated(message, messageAr) {
            // A domain 401 (carries a server message) is surfaced, never
            // refreshed — see `execute` for why refreshing one risks a spurious
            // logout.
            guard message == nil, messageAr == nil else {
                throw DroobError.unauthenticated(message: message, messageAr: messageAr)
            }
            // Only a *stale* token is worth refreshing. A guest (no token)
            // hitting a still-protected endpoint surfaces the error to the
            // caller without wiping any session (there's nothing to wipe).
            guard token != nil else {
                throw DroobError.unauthenticated(message: nil, messageAr: nil)
            }
            let newToken = try await refreshTokens()
            return try await client.execute(apiRequest, accessToken: newToken)
        }
    }

    /// Variant for endpoints returning `204 No Content`. Same 401-refresh
    /// behaviour as {@link execute}, but no decoding.
    func executeVoid(_ apiRequest: APIRequest) async throws {
        guard let accessToken = TokenStore.shared.accessToken else {
            throw DroobError.unauthenticated(message: nil, messageAr: nil)
        }
        do {
            try await client.executeVoid(apiRequest, accessToken: accessToken)
        } catch let DroobError.unauthenticated(message, messageAr) {
            // Domain 401s (carrying a message) are surfaced, never refreshed —
            // see `execute`.
            guard message == nil, messageAr == nil else {
                throw DroobError.unauthenticated(message: message, messageAr: messageAr)
            }
            let newToken = try await refreshTokens()
            try await client.executeVoid(apiRequest, accessToken: newToken)
        }
    }

    /// Execute a raw URLRequest (used for SSE) with auth + 401 refresh.
    func executeBytes(for urlRequest: URLRequest) async throws -> URLSession.AsyncBytes {
        guard let accessToken = TokenStore.shared.accessToken else {
            throw DroobError.unauthenticated(message: nil, messageAr: nil)
        }
        var authedRequest = urlRequest
        authedRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            return try await client.bytesStream(for: authedRequest)
        } catch DroobError.unauthenticated(_, _) {
            let newToken = try await refreshTokens()
            authedRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            return try await client.bytesStream(for: authedRequest)
        }
    }

    // MARK: - Token refresh (serialised, coalesced)

    private func refreshTokens() async throws -> String {
        // If another refresh is already in flight, queue up and wait
        if isRefreshing {
            return try await withCheckedThrowingContinuation { continuation in
                pendingContinuations.append(continuation)
            }
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        guard let refreshToken = TokenStore.shared.refreshToken else {
            resumePending(with: .failure(DroobError.unauthenticated(message: nil, messageAr: nil)))
            throw DroobError.unauthenticated(message: nil, messageAr: nil)
        }

        do {
            let request = APIRequest(
                path: "/v1/auth/refresh",
                method: .POST,
                body: RefreshRequest(refreshToken: refreshToken),
                requiresAuth: false
            )
            let authResponse: AuthTokens = try await client.execute(request, accessToken: nil)
            TokenStore.shared.save(tokens: authResponse)
            resumePending(with: .success(authResponse.accessToken))
            return authResponse.accessToken
        } catch {
            // The one-device pin also gates refresh, so a token carried onto a
            // second device dies here rather than at the login screen. Keep the
            // reason so the user gets an explanation instead of a silent bounce
            // back to sign-in.
            if case DroobError.deviceNotAuthorized = error {
                SessionEndNotice.record(.deviceNotAuthorized)
            }
            TokenStore.shared.clearTokens()
            resumePending(with: .failure(DroobError.unauthenticated(message: nil, messageAr: nil)))
            throw DroobError.unauthenticated(message: nil, messageAr: nil)
        }
    }

    private func resumePending(with result: Result<String, Error>) {
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        for cont in continuations {
            switch result {
            case .success(let token): cont.resume(returning: token)
            case .failure(let error): cont.resume(throwing: error)
            }
        }
    }
}

// MARK: - Supporting types

struct RefreshRequest: Encodable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct AuthTokens: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

/// Sum-of-shapes returned by `POST /v1/auth/login`. Either the user is fully
/// authenticated (token fields populated) or they need to complete a 2FA
/// challenge (`challenge == "totp_required"` + `challengeToken` populated).
/// Mirrors the backend's `TokenResponse` so we can decode either shape from
/// the same endpoint.
struct LoginResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let challenge: String?
    let challengeToken: String?
    /// Cloudflare Turnstile site key — populated only when
    /// `challenge == "captcha_required"`. iOS uses it to render the widget.
    let captchaSiteKey: String?
    /// Registration token — populated only on the
    /// `challenge == "registration_required"` branch of
    /// `/v1/auth/email-otp/register/verify`. Submitted to /register/complete
    /// together with the chosen display name.
    let registrationToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken       = "access_token"
        case refreshToken      = "refresh_token"
        case expiresIn         = "expires_in"
        case challenge
        case challengeToken    = "challenge_token"
        case captchaSiteKey    = "captcha_site_key"
        case registrationToken = "registration_token"
    }

    var requiresTotp: Bool { challenge == "totp_required" }
    var requiresEmailVerification: Bool { challenge == "email_verification_required" }
    var requiresCaptcha: Bool { challenge == "captcha_required" }
    /// Returned by /v1/auth/email-otp/register/verify — the OTP was correct,
    /// but the client must call /register/complete with a display name before
    /// real tokens are minted.
    var requiresRegistration: Bool { challenge == "registration_required" }

    /// Promote a successful login response to the existing AuthTokens
    /// shape so the rest of the auth flow doesn't need to know about
    /// the challenge branch.
    var tokens: AuthTokens? {
        guard let access = accessToken,
              let refresh = refreshToken,
              let expires = expiresIn else { return nil }
        return AuthTokens(accessToken: access, refreshToken: refresh, expiresIn: expires)
    }
}
