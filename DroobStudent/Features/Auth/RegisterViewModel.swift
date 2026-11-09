import Foundation

@MainActor
final class RegisterViewModel: ObservableObject {
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var selectedLocale: String = AppLocaleDefault.code
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    /// Set once /register returns. RegisterView pushes `VerifyEmailView`
    /// off this token. The email value is shown in the verify screen's
    /// "we sent a code to X" copy.
    @Published var pendingEmailVerificationChallenge: String? = nil
    @Published var pendingEmailVerificationEmail: String? = nil
    /// Set when social sign-in lands on a 2FA gate. RegisterView pushes the
    /// `TotpChallengeView` off this, mirroring the login screen — a returning
    /// user who taps Google/Apple here must still clear their second factor.
    @Published var pendingTotpChallenge: String? = nil

    private let authSession = AuthSession.shared

    /// First + last names joined for the backend's `display_name` field.
    /// Empty parts are dropped so a missing last name doesn't produce a
    /// trailing space.
    var combinedDisplayName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil

        do {
            let idToken = try await GoogleSignInAuth.presentAndFetchIDToken()
            let outcome = try await authSession.signInWithGoogle(idToken: idToken, locale: selectedLocale)
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

    func signInWithApple() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await AppleSignInAuth.presentAndFetch()
            let outcome = try await authSession.signInWithApple(
                idToken: result.idToken, fullName: result.fullName, locale: selectedLocale)
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

    func register() async {
        guard !firstName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = L10n.authErrFirstName
            return
        }
        guard !email.isEmpty else {
            errorMessage = L10n.authErrEmail
            return
        }
        // Spec from the Figma password hint: 8 chars min, plus a digit or symbol.
        let pw = password
        let hasDigitOrSymbol = pw.rangeOfCharacter(from: .decimalDigits) != nil
            || pw.rangeOfCharacter(from: .symbols) != nil
            || pw.rangeOfCharacter(from: .punctuationCharacters) != nil
        guard pw.count >= 8, hasDigitOrSymbol else {
            errorMessage = L10n.authErrPasswordRule
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let outcome = try await authSession.register(
                email: email,
                password: password,
                displayName: combinedDisplayName,
                locale: selectedLocale
            )
            switch outcome {
            case .emailVerificationRequired(let token):
                pendingEmailVerificationEmail = email
                pendingEmailVerificationChallenge = token
                // Remember to show the post-signup welcome screen once the
                // user completes OTP and AuthSession transitions to .authenticated.
                UserDefaults.standard.set(email, forKey: "pendingWelcomeForEmail")
            }
        } catch let error as DroobError {
            switch error {
            case .conflict:
                errorMessage = L10n.authErrEmailTaken
            default:
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
