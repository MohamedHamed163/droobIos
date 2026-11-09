import Foundation
import Combine

// MARK: - User model

struct DroobUser: Decodable, Equatable {
    let userId: String
    let email: String
    let displayName: String
    let locale: String?
    let kycStatus: String?
    let bio: String?
    let avatarUrl: String?
    /// Account role from the backend (STUDENT / INSTRUCTOR / ADMIN). The
    /// student app only admits STUDENT accounts — see `AuthSession.isStudent`.
    let role: String?
    /// Backend-signalled "special student" flag. `true` means enrollment is
    /// instant (auto-accepted) and the app hides ALL pricing / "free" wording;
    /// `false`/absent means a normal student who sees pricing + "Free preview"
    /// and goes through the request→approval enroll flow. Consumers read it via
    /// `isAutoEnroll` so a missing key is treated as a normal student.
    let autoEnroll: Bool?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case displayName = "display_name"
        case locale
        case kycStatus = "kyc_status"
        case bio
        case avatarUrl = "avatar_url"
        case role
        case autoEnroll = "auto_enroll"
    }

    /// True only when the backend explicitly flags this account as a special
    /// (auto-enroll) student. A missing/`nil` flag is treated as a normal
    /// student so older builds — and the pre-flag default — keep showing
    /// pricing and the "Free preview" wording.
    var isAutoEnroll: Bool { autoEnroll ?? false }

    /// True unless the backend explicitly reports a non-student role. Treating
    /// a missing role as "student" keeps the app working against older builds,
    /// while a present INSTRUCTOR/ADMIN role is firmly rejected.
    var isStudent: Bool {
        guard let role = role?.uppercased(), !role.isEmpty else { return true }
        return role == "STUDENT"
    }
}

// MARK: - Auth state

enum AuthState: Equatable {
    case loading
    case unauthenticated
    case authenticated(DroobUser)
}

// MARK: - AuthSession
// Uses ObservableObject for broad iOS 16+ compatibility.

@MainActor
final class AuthSession: ObservableObject {
    static let shared = AuthSession()

    @Published private(set) var state: AuthState = .loading
    @Published var pendingDeepLinkCourseId: String? = nil
    /// Study-room Universal-Link slug captured pre-auth. The root view
    /// consumes this once `state == .authenticated` and pushes the
    /// chat screen (joining the room first via the by-slug endpoint).
    @Published var pendingStudyRoomSlug: String? = nil
    /// A chat to open in response to a tapped push notification. `RootView`
    /// consumes this and presents the study-room or direct-thread chat,
    /// deferring until the session is authenticated (covers cold launch).
    @Published var pendingChatTarget: ChatTarget? = nil

    /// Identifies which chat a tapped push should open.
    enum ChatTarget: Equatable {
        case studyRoom(String)     // roomId
        case directThread(String)  // threadId
    }

    var isAuthenticated: Bool {
        if case .authenticated = state { return true }
        return false
    }

    var currentUser: DroobUser? {
        if case .authenticated(let user) = state { return user }
        return nil
    }

    private init() {}

    // MARK: - Bootstrap on launch

    func bootstrap() async {
        guard TokenStore.shared.accessToken != nil || TokenStore.shared.refreshToken != nil else {
            state = .unauthenticated
            return
        }

        do {
            // Try to load current user; if 401, interceptor refreshes automatically
            let request = APIRequest(path: "/v1/auth/me", method: .GET)
            let user: DroobUser = try await AuthInterceptor.shared.execute(request)
            // Reject any stored token belonging to a non-student account so an
            // instructor/admin session can never resume inside the student app.
            guard user.isStudent else {
                TokenStore.shared.clearTokens()
                state = .unauthenticated
                return
            }
            state = .authenticated(user)
        } catch {
            TokenStore.shared.clearTokens()
            state = .unauthenticated
        }
    }

    // MARK: - Login

    /// Sum-of-shapes for {@link login}. `.authenticated` means we already
    /// have access + refresh tokens stored and the user is logged in;
    /// `.totpRequired` means the caller must present a 6-digit / recovery
    /// code via {@link completeTotpChallenge} to finish the login;
    /// `.emailVerificationRequired` means the account was created but the
    /// mailbox hasn't been confirmed — the verify-email screen owns the
    /// next step.
    enum LoginOutcome {
        case authenticated
        case totpRequired(challengeToken: String)
        case emailVerificationRequired(challengeToken: String)
        /// Backend wants a Cloudflare Turnstile token before it will check
        /// the password. `siteKey` is the public Turnstile key the WebView
        /// uses to render the widget.
        case captchaRequired(siteKey: String)
    }

    /// Email + password login. Always returns a success, but the success
    /// may carry a TOTP, email-verification, or captcha challenge instead
    /// of a final session.
    @discardableResult
    func login(email: String, password: String, captchaToken: String? = nil) async throws -> LoginOutcome {
        let body = LoginRequest(email: email, password: password, captchaToken: captchaToken)
        let request = APIRequest(path: "/v1/auth/login", method: .POST, body: body, requiresAuth: false)
        let response: LoginResponse = try await APIClient.shared.execute(request, accessToken: nil)
        if response.requiresCaptcha, let siteKey = response.captchaSiteKey {
            return .captchaRequired(siteKey: siteKey)
        }
        if response.requiresEmailVerification, let challengeToken = response.challengeToken {
            return .emailVerificationRequired(challengeToken: challengeToken)
        }
        if response.requiresTotp, let challengeToken = response.challengeToken {
            return .totpRequired(challengeToken: challengeToken)
        }
        guard let tokens = response.tokens else {
            // Server returned neither tokens nor a challenge — treat as
            // a server error rather than silently passing through.
            throw DroobError.serverError(message: "Malformed login response", messageAr: L10n.errBadResponse)
        }
        TokenStore.shared.save(tokens: tokens)
        try await fetchCurrentUser()
        return .authenticated
    }

    /// Second leg of a 2FA login. Sends the 6-digit (or recovery) code along
    /// with the challenge token; on success persists the issued tokens and
    /// promotes session state to authenticated.
    func completeTotpChallenge(challengeToken: String, code: String) async throws {
        let body = TotpChallengeRequest(challengeToken: challengeToken, code: code)
        let request = APIRequest(path: "/v1/auth/totp", method: .POST, body: body, requiresAuth: false)
        let tokens: AuthTokens = try await APIClient.shared.execute(request, accessToken: nil)
        TokenStore.shared.save(tokens: tokens)
        try await fetchCurrentUser()
    }

    // MARK: - Register

    /// Outcome of /register. Today the backend always issues an email
    /// verification challenge; this enum exists so the caller doesn't
    /// reach into a {@link LoginResponse} directly.
    enum RegisterOutcome {
        case emailVerificationRequired(challengeToken: String)
    }

    /// Creates the account and starts the email verification flow. Does NOT
    /// authenticate the session — the caller must complete /verify-email
    /// to receive tokens.
    @discardableResult
    func register(email: String, password: String, displayName: String, locale: String) async throws -> RegisterOutcome {
        let body = RegisterRequest(email: email, password: password, displayName: displayName, locale: locale, role: "STUDENT")
        let request = APIRequest(path: "/v1/auth/register", method: .POST, body: body, requiresAuth: false)
        let response: LoginResponse = try await APIClient.shared.execute(request, accessToken: nil)
        guard response.requiresEmailVerification, let token = response.challengeToken else {
            throw DroobError.serverError(message: "Malformed register response", messageAr: L10n.errBadResponse)
        }
        return .emailVerificationRequired(challengeToken: token)
    }

    /// Completes email verification. On success persists the issued tokens
    /// and promotes session state to `.authenticated`.
    func verifyEmail(challengeToken: String, code: String) async throws {
        let body = VerifyEmailRequestBody(challengeToken: challengeToken, code: code)
        let request = APIRequest(path: "/v1/auth/verify-email", method: .POST, body: body, requiresAuth: false)
        let tokens: AuthTokens = try await APIClient.shared.execute(request, accessToken: nil)
        TokenStore.shared.save(tokens: tokens)
        try await fetchCurrentUser()
    }

    // MARK: - Password reset (forgot password)

    /// Starts the password-reset flow. The backend always responds 204 —
    /// including when the email is unknown — to keep the endpoint from
    /// leaking which addresses are registered. Caller should treat any
    /// non-throwing return as "we attempted to send a code".
    func requestPasswordReset(email: String) async throws {
        let body = ForgotPasswordRequestBody(email: email)
        let request = APIRequest(
            path: "/v1/auth/forgot-password", method: .POST,
            body: body, requiresAuth: false)
        _ = try await APIClient.shared.execute(request, accessToken: nil) as EmptyResponse
    }

    /// Validates a forgot-password OTP at the verify-code step, before the
    /// user is prompted for a new password. Throws on wrong / expired /
    /// exhausted codes so the OTP screen surfaces the error rather than
    /// silently advancing to ChangePasswordView.
    func verifyPasswordResetCode(email: String, code: String) async throws {
        let body = VerifyResetCodeRequestBody(email: email, code: code)
        let request = APIRequest(
            path: "/v1/auth/verify-reset-code", method: .POST,
            body: body, requiresAuth: false)
        _ = try await APIClient.shared.execute(request, accessToken: nil) as EmptyResponse
    }

    /// Completes the password-reset flow: verifies the OTP and persists the
    /// new password hash server-side. The session is deliberately left
    /// unauthenticated — the user must sign in again with the new password.
    /// We discard any tokens the backend returns so the client lands on a
    /// "Password changed successfully" screen rather than being silently
    /// logged in (which hides the password change and bypasses re-auth).
    func confirmPasswordReset(email: String, code: String, newPassword: String) async throws {
        let body = ResetPasswordRequestBody(email: email, code: code, newPassword: newPassword)
        let request = APIRequest(
            path: "/v1/auth/reset-password", method: .POST,
            body: body, requiresAuth: false)
        _ = try await APIClient.shared.execute(request, accessToken: nil) as AuthTokens
    }

    /// Asks the backend to re-issue a verification code for the same
    /// challenge. Rate-limited server-side; surfaces as a `DroobError` on
    /// cooldown.
    func resendVerificationEmail(challengeToken: String) async throws {
        let body = ResendVerificationRequestBody(challengeToken: challengeToken)
        let request = APIRequest(path: "/v1/auth/resend-verification", method: .POST, body: body, requiresAuth: false)
        _ = try await APIClient.shared.execute(request, accessToken: nil) as EmptyResponse
    }

    // MARK: - Email OTP (passwordless) — student app only

    /// Outcome of /email-otp/login/verify. Most users land on
    /// `.authenticated`; users with TOTP enabled get a `.totpRequired`
    /// challenge they finish via {@link completeTotpChallenge}.
    enum EmailOtpLoginOutcome {
        case authenticated
        case totpRequired(challengeToken: String)
    }

    /// Asks the backend to email a sign-in code. The backend never reveals
    /// whether the email is registered — caller should treat any non-throwing
    /// return as "if the account exists, a code is on the way".
    func requestEmailOtpLogin(email: String, locale: String) async throws {
        let body = EmailOtpRequestBody(email: email, locale: locale)
        let request = APIRequest(
            path: "/v1/auth/email-otp/login/request", method: .POST,
            body: body, requiresAuth: false)
        _ = try await APIClient.shared.execute(request, accessToken: nil) as EmptyResponse
    }

    /// Submits the OTP. On `.authenticated` the session is promoted to
    /// authenticated; on `.totpRequired` the caller must follow up via
    /// {@link completeTotpChallenge}.
    @discardableResult
    func verifyEmailOtpLogin(email: String, code: String) async throws -> EmailOtpLoginOutcome {
        let body = EmailOtpVerifyBody(email: email, code: code, locale: nil)
        let request = APIRequest(
            path: "/v1/auth/email-otp/login/verify", method: .POST,
            body: body, requiresAuth: false)
        let response: LoginResponse = try await APIClient.shared.execute(request, accessToken: nil)
        if response.requiresTotp, let token = response.challengeToken {
            return .totpRequired(challengeToken: token)
        }
        guard let tokens = response.tokens else {
            throw DroobError.serverError(message: "Malformed OTP login response", messageAr: L10n.errBadResponse)
        }
        TokenStore.shared.save(tokens: tokens)
        try await fetchCurrentUser()
        return .authenticated
    }

    /// Asks the backend to email a sign-up code. Like the login variant, the
    /// backend doesn't reveal whether the address is already registered —
    /// the UI shows the same "code sent" copy either way.
    func requestEmailOtpRegister(email: String, locale: String) async throws {
        let body = EmailOtpRequestBody(email: email, locale: locale)
        let request = APIRequest(
            path: "/v1/auth/email-otp/register/request", method: .POST,
            body: body, requiresAuth: false)
        _ = try await APIClient.shared.execute(request, accessToken: nil) as EmptyResponse
    }

    /// Submits the sign-up OTP. Returns a short-lived registration token; the
    /// caller pushes the display-name screen and finishes via
    /// {@link completeEmailOtpRegister}. No user account is created yet.
    func verifyEmailOtpRegister(email: String, code: String, locale: String) async throws -> String {
        let body = EmailOtpVerifyBody(email: email, code: code, locale: locale)
        let request = APIRequest(
            path: "/v1/auth/email-otp/register/verify", method: .POST,
            body: body, requiresAuth: false)
        let response: LoginResponse = try await APIClient.shared.execute(request, accessToken: nil)
        guard response.requiresRegistration, let regToken = response.registrationToken else {
            throw DroobError.serverError(message: "Malformed OTP register-verify response", messageAr: L10n.errBadResponse)
        }
        return regToken
    }

    /// Exchanges the registration token + chosen display name for real
    /// access/refresh tokens. On success the session advances to
    /// `.authenticated` with the freshly-created student profile.
    func completeEmailOtpRegister(registrationToken: String, displayName: String) async throws {
        let body = CompleteEmailOtpRegisterBody(
            registrationToken: registrationToken, displayName: displayName)
        let request = APIRequest(
            path: "/v1/auth/email-otp/register/complete", method: .POST,
            body: body, requiresAuth: false)
        let tokens: AuthTokens = try await APIClient.shared.execute(request, accessToken: nil)
        TokenStore.shared.save(tokens: tokens)
        try await fetchCurrentUser()
    }

    // MARK: - Social sign-in (Google / Apple)

    /// Outcome of a Google/Apple sign-in. Like email+password, social sign-in
    /// can land on a 2FA gate: a user who enrolled TOTP must complete it via
    /// {@link completeTotpChallenge} before the session is authenticated. The
    /// caller MUST react to `.totpRequired` — the result is intentionally not
    /// `@discardableResult` so a forgotten case can't silently re-open the
    /// 2FA bypass this enum exists to close.
    enum SocialLoginOutcome {
        case authenticated
        case totpRequired(challengeToken: String)
    }

    // MARK: - Google sign-in

    func signInWithGoogle(idToken: String, locale: String) async throws -> SocialLoginOutcome {
        let body = GoogleSignInRequest(idToken: idToken, locale: locale)
        let request = APIRequest(path: "/v1/auth/google", method: .POST, body: body, requiresAuth: false)
        let response: LoginResponse = try await APIClient.shared.execute(request, accessToken: nil)
        if response.requiresTotp, let challengeToken = response.challengeToken {
            return .totpRequired(challengeToken: challengeToken)
        }
        guard let tokens = response.tokens else {
            throw DroobError.serverError(message: "Malformed Google sign-in response", messageAr: L10n.errBadResponse)
        }
        TokenStore.shared.save(tokens: tokens)
        try await fetchCurrentUser()
        return .authenticated
    }

    // MARK: - Apple sign-in

    func signInWithApple(idToken: String, fullName: String?, locale: String) async throws -> SocialLoginOutcome {
        let body = AppleSignInRequest(idToken: idToken, fullName: fullName, locale: locale)
        let request = APIRequest(path: "/v1/auth/apple", method: .POST, body: body, requiresAuth: false)
        let response: LoginResponse = try await APIClient.shared.execute(request, accessToken: nil)
        if response.requiresTotp, let challengeToken = response.challengeToken {
            return .totpRequired(challengeToken: challengeToken)
        }
        guard let tokens = response.tokens else {
            throw DroobError.serverError(message: "Malformed Apple sign-in response", messageAr: L10n.errBadResponse)
        }
        TokenStore.shared.save(tokens: tokens)
        try await fetchCurrentUser()
        return .authenticated
    }

    // MARK: - Biometric (Face ID / Touch ID) login

    /// Enrolls the current device for biometric login. Caller must be
    /// in an authenticated session (the server-side endpoint requires
    /// a bearer token).
    ///
    /// Prompts the user for Face ID / Touch ID as part of enrollment
    /// so the toggle confirms it worked. `confirmReason` is the string
    /// shown in the system prompt.
    func enrollBiometric(keyLabel: String?, confirmReason: String) async throws {
        guard let user = currentUser else { throw DroobError.unauthenticated(message: nil, messageAr: nil) }
        try await BiometricLoginCoordinator.shared.enroll(
            keyLabel: keyLabel, userId: user.userId, confirmReason: confirmReason)
    }

    /// Removes the local biometric enrollment. Safe to call even if
    /// there's no enrollment.
    func unenrollBiometric() {
        BiometricLoginCoordinator.shared.unenroll()
    }

    /// Signs in via Face ID / Touch ID using a previously-enrolled
    /// Secure Enclave key. On success the session state advances to
    /// `.authenticated` and the user's profile is fetched.
    func signInWithBiometric(reason: String) async throws {
        _ = try await BiometricLoginCoordinator.shared.signIn(reason: reason)
        try await fetchCurrentUser()
    }

    // MARK: - Logout

    func logout() async {
        if let refreshToken = TokenStore.shared.refreshToken {
            let body = LogoutRequest(refreshToken: refreshToken)
            let request = APIRequest(path: "/v1/auth/logout", method: .POST, body: body)
            _ = try? await AuthInterceptor.shared.execute(request) as EmptyResponse
        }
        // Intentionally keep the biometric enrollment across logout —
        // that's the whole point of "Sign In with Face ID". The
        // {@link fetchCurrentUser} cross-user check below will clear
        // the enrollment automatically if a *different* user signs in
        // on this device next, so we don't leak the old user's key to
        // someone else.
        // Drop this device's push token server-side before clearing the
        // session. The token is device-global, so without this the row stays
        // pointed at the logging-out account and a different user signing in
        // on this device keeps receiving the old account's pushes. Must run
        // while still authenticated (the DELETE needs a valid access token).
        await PushService.shared.unregister()
        TokenStore.shared.clearTokens()
        state = .unauthenticated
    }

    // MARK: - Helpers

    func handleUnauthenticated() {
        TokenStore.shared.clearTokens()
        state = .unauthenticated
    }

    /// Re-fetches `/v1/auth/me` and republishes `state`. Call after a profile
    /// edit (display name / email change) so the Profile tab and any header
    /// bound to `currentUser` reflect the new values without a re-login.
    func refreshCurrentUser() async {
        guard isAuthenticated else { return }
        try? await fetchCurrentUser()
    }

    private func fetchCurrentUser() async throws {
        let request = APIRequest(path: "/v1/auth/me", method: .GET)
        guard let token = TokenStore.shared.accessToken else { throw DroobError.unauthenticated(message: nil, messageAr: nil) }
        let user: DroobUser = try await APIClient.shared.execute(request, accessToken: token)

        // Portal gate (defense-in-depth): the backend already rejects non-student
        // logins via `intended_role`, but enforce it here too so that any token
        // reaching this client — social sign-in, a stale keychain token, a future
        // auth path — can only ever resolve to a STUDENT session. Anything else is
        // signed straight back out with a clear message.
        guard user.isStudent else {
            TokenStore.shared.clearTokens()
            state = .unauthenticated
            throw DroobError.forbidden(
                message: "This account isn't a student account. Please use the Droob instructor app.",
                messageAr: "هذا الحساب ليس حساب طالب. الرجاء استخدام تطبيق المعلّم.")
        }

        // Cross-user safety: if this device has a biometric enrollment
        // belonging to a DIFFERENT user, clear it. Otherwise the next
        // tap on the Face ID button would silently sign that other
        // user in. Same-user re-login keeps the enrollment intact.
        if let enrolledId = BiometricLoginCoordinator.shared.enrolledUserId,
           enrolledId != user.userId {
            BiometricLoginCoordinator.shared.unenroll()
        }

        state = .authenticated(user)
        // (Re)register this device's push token for the now-authenticated user.
        // Re-login on a shared device re-points the token to this account, so
        // pushes follow the user actually signed in — not whoever launched the
        // app first. logout() nils lastSyncedToken, so this re-syncs even when
        // the device's FCM token is unchanged across an account switch.
        PushService.shared.requestAuthorizationIfAuthenticated()
    }
}

// MARK: - Request bodies

private struct LoginRequest: Encodable {
    let email: String
    let password: String
    let captchaToken: String?
    // Declares which app this is so the backend rejects non-student accounts.
    let intendedRole = "STUDENT"
    enum CodingKeys: String, CodingKey {
        case email
        case password
        case captchaToken = "captcha_token"
        case intendedRole = "intended_role"
    }
}

private struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let displayName: String
    let locale: String
    let role: String
}

private struct LogoutRequest: Encodable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct TotpChallengeRequest: Encodable {
    let challengeToken: String
    let code: String
    enum CodingKeys: String, CodingKey {
        case challengeToken = "challenge_token"
        case code
    }
}

private struct VerifyEmailRequestBody: Encodable {
    let challengeToken: String
    let code: String
    enum CodingKeys: String, CodingKey {
        case challengeToken = "challenge_token"
        case code
    }
}

private struct ResendVerificationRequestBody: Encodable {
    let challengeToken: String
    enum CodingKeys: String, CodingKey {
        case challengeToken = "challenge_token"
    }
}

private struct ForgotPasswordRequestBody: Encodable {
    let email: String
    let intendedRole = "STUDENT"
    enum CodingKeys: String, CodingKey {
        case email
        case intendedRole = "intended_role"
    }
}

private struct VerifyResetCodeRequestBody: Encodable {
    let email: String
    let code: String
    let intendedRole = "STUDENT"
    enum CodingKeys: String, CodingKey {
        case email
        case code
        case intendedRole = "intended_role"
    }
}

private struct ResetPasswordRequestBody: Encodable {
    let email: String
    let code: String
    let newPassword: String
    let intendedRole = "STUDENT"
    enum CodingKeys: String, CodingKey {
        case email
        case code
        case newPassword = "new_password"
        case intendedRole = "intended_role"
    }
}

private struct GoogleSignInRequest: Encodable {
    let idToken: String
    let locale: String
    let intendedRole = "STUDENT"
    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case locale
        case intendedRole = "intended_role"
    }
}

private struct AppleSignInRequest: Encodable {
    let idToken: String
    let fullName: String?
    let locale: String
    let intendedRole = "STUDENT"
    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case fullName = "full_name"
        case locale
        case intendedRole = "intended_role"
    }
}

private struct EmailOtpRequestBody: Encodable {
    let email: String
    let locale: String?
}

private struct EmailOtpVerifyBody: Encodable {
    let email: String
    let code: String
    let locale: String?
}

private struct CompleteEmailOtpRegisterBody: Encodable {
    let registrationToken: String
    let displayName: String
    enum CodingKeys: String, CodingKey {
        case registrationToken = "registration_token"
        case displayName       = "display_name"
    }
}

struct EmptyResponse: Decodable {}
