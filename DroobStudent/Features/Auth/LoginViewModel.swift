import Foundation
import SwiftUI

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var navigateToRegister: Bool = false
    @Published var emailFieldError: String? = nil
    @Published var passwordFieldError: String? = nil
    /// Set when the backend asks for a 2FA code. The login screen reads this
    /// and pushes a `TotpChallengeView` onto the navigation stack.
    @Published var pendingTotpChallenge: String? = nil
    /// Set when the backend asks the user to verify their email first.
    /// LoginView pushes `VerifyEmailView` off this token.
    @Published var pendingEmailVerificationChallenge: String? = nil
    /// Email used in the last login attempt — passed through to the
    /// verify-email screen so we can display "we sent a code to X@Y".
    @Published var pendingEmailVerificationEmail: String? = nil
    /// Set when the backend responds with a `captcha_required` challenge.
    /// LoginView presents the Turnstile sheet off this; the resulting
    /// token comes back via `submitWithCaptcha(_:)`.
    @Published var pendingCaptchaSiteKey: String? = nil
    @AppStorage("keepMeSignedIn") var keepMeSignedIn: Bool = false

    private let authSession = AuthSession.shared

    /// Surfaces the reason the app dropped back to sign-in, when there was
    /// one. A refresh refused by the one-device pin would otherwise land the
    /// user here with no explanation at all.
    func consumeSessionEndNotice() {
        guard errorMessage == nil, let reason = SessionEndNotice.consume() else { return }
        errorMessage = reason.message
    }

    func login() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = L10n.loginErrMissingFields
            // Don't carry over red field outlines from a prior wrong-credentials
            // attempt — the issue now is "empty", not "wrong".
            emailFieldError = nil
            passwordFieldError = nil
            return
        }
        await performLogin(captchaToken: nil)
    }

    /// Re-runs the login attempt after the user solved a Cloudflare Turnstile
    /// challenge. Reuses the email + password already typed; the sheet only
    /// returns the token. Pass `nil` for a cancelled / errored sheet — we surface
    /// a clear banner explaining the extra step rather than dropping the user
    /// back to a silent form with no explanation.
    func submitWithCaptcha(token: String?) async {
        pendingCaptchaSiteKey = nil
        guard let token else {
            // Dismissed without solving (close / error / expiry). Don't leave
            // the form silent — that reproduces the "blocked with no
            // explanation" complaint; tell the user why the step appeared and
            // how to proceed.
            errorMessage = L10n.loginErrCaptchaDismissed
            return
        }
        await performLogin(captchaToken: token)
    }

    private func performLogin(captchaToken: String?) async {
        isLoading = true
        errorMessage = nil
        emailFieldError = nil
        passwordFieldError = nil

        do {
            let outcome = try await authSession.login(
                email: email, password: password, captchaToken: captchaToken)
            switch outcome {
            case .authenticated:
                // RootView swaps to MainTabView via the @Published state.
                break
            case .totpRequired(let challengeToken):
                // Push the TOTP challenge screen — login isn't complete yet.
                pendingTotpChallenge = challengeToken
            case .emailVerificationRequired(let challengeToken):
                pendingEmailVerificationEmail = email
                pendingEmailVerificationChallenge = challengeToken
            case .captchaRequired(let siteKey):
                // The view presents TurnstileSheet off this; once the user
                // solves it, submitWithCaptcha(token:) re-runs this method.
                pendingCaptchaSiteKey = siteKey
            }
        } catch let error as DroobError {
            // A rejected-credentials response (the backend 4xx that means
            // "this email/password pair is wrong") gets the dedicated Figma
            // banner copy — "Wrong email or password. Try again, or reset
            // your password." — instead of the raw server message, which is
            // terse and inconsistent. Genuinely different failures (network
            // down, 5xx) keep their real description so the user can tell a
            // typo apart from an outage.
            errorMessage = Self.isCredentialRejection(error)
                ? L10n.loginErrWrongCredentials
                : error.errorDescription
            // The credentials were fine when the account is simply pinned to
            // another device — flagging both fields would send the user off
            // retyping a password that was never wrong.
            if case .deviceNotAuthorized = error {
                emailFieldError = nil
                passwordFieldError = nil
            } else {
                emailFieldError = L10n.loginErrVerifyEmail
                passwordFieldError = L10n.loginErrVerifyPassword
            }
        } catch {
            errorMessage = error.localizedDescription
            emailFieldError = L10n.loginErrVerifyEmail
            passwordFieldError = L10n.loginErrVerifyPassword
        }

        isLoading = false
    }

    /// True when the login failure is the backend rejecting the supplied
    /// email/password (as opposed to a transport/server fault). These are the
    /// cases that should surface the "wrong email or password" banner.
    private static func isCredentialRejection(_ error: DroobError) -> Bool {
        switch error {
        // The one-device pin is also a 4xx, but the credentials were right —
        // it needs the server's own explanation, not the generic banner.
        case .deviceNotAuthorized:
            return false
        case .unauthenticated, .forbidden, .notFound:
            return true
        case .httpError(let status, _):
            return (400...404).contains(status) || status == 422
        default:
            return false
        }
    }

    func signInWithGoogle(locale: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let idToken = try await GoogleSignInAuth.presentAndFetchIDToken()
            let outcome = try await authSession.signInWithGoogle(idToken: idToken, locale: locale)
            // A 2FA-enrolled user isn't signed in yet — push the same TOTP
            // challenge screen the password flow uses. Skipping this is the
            // bypass we're guarding against.
            if case .totpRequired(let challengeToken) = outcome {
                pendingTotpChallenge = challengeToken
            }
        } catch GoogleSignInError.canceled {
            // user dismissed; no banner
        } catch let error as DroobError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// True iff this install has previously enrolled biometric login and
    /// can still use the Secure Enclave key (i.e. biometry hasn't
    /// changed since enrollment). Drives whether the Face ID button is
    /// rendered.
    var isBiometricLoginAvailable: Bool {
        BiometricLoginCoordinator.shared.isEnrolled
    }

    func signInWithBiometric() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authSession.signInWithBiometric(
                reason: L10n.loginBiometricReason)
        } catch let error as DroobError {
            errorMessage = error.errorDescription
        } catch let error as DeviceKeyStoreError {
            errorMessage = error.errorDescription
        } catch {
            // Don't show a banner for user-cancelled Face ID — LAError
            // surfaces .userCancel / .systemCancel as NSError instances
            // we can recognise by domain.
            if let nsError = error as NSError?, nsError.domain == "com.apple.LocalAuthentication" {
                switch nsError.code {
                case -2 /* userCancel */, -4 /* systemCancel */, -9 /* appCancel */:
                    break
                default:
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    func signInWithApple(locale: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await AppleSignInAuth.presentAndFetch()
            let outcome = try await authSession.signInWithApple(
                idToken: result.idToken, fullName: result.fullName, locale: locale)
            // Same 2FA gate as Google: a TOTP-enrolled user must finish the
            // challenge before the session is authenticated.
            if case .totpRequired(let challengeToken) = outcome {
                pendingTotpChallenge = challengeToken
            }
        } catch AppleSignInError.canceled {
            // user dismissed; no banner
        } catch let error as DroobError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
