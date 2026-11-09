import SwiftUI

// MARK: - VerifyEmailView (Figma redesign — OTP)
//
// Used by both the register flow (email verification) and the reset-password
// flow (per Figma, both end on the same code-entry screen). Six 46×56 OTP
// boxes with auto-advance, gold "Verify" CTA, and a 60s resend countdown
// that flips from disabled grey to gold when 0:00 hits.

/// Distinguishes the flows that share this OTP screen.
///
/// - `signupVerification` — finishes the password-based register flow;
///   verifies the code against `/v1/auth/verify-email` and lands on tokens.
/// - `passwordReset` — proof-of-identity step before `ChangePasswordView`;
///   the OTP is validated but not consumed.
/// - `passwordlessLogin` — passwordless sign-in via
///   `/v1/auth/email-otp/login/verify`. On success the session is
///   promoted to `.authenticated`. NOTE (2026-07): no UI reaches this case
///   any more — the "sign in with email code" button was removed from
///   `LoginView`. The case and its `AuthSession` calls are kept because they
///   are the shared email-OTP request/verify plumbing; only the entry point
///   was withdrawn.
/// - `passwordlessRegister` — passwordless sign-up via
///   `/v1/auth/email-otp/register/verify`. Returns a registration token;
///   the caller pushes the display-name screen.
enum VerifyEmailPurpose {
    case signupVerification
    case passwordReset
    case passwordlessLogin
    case passwordlessRegister
}

@MainActor
final class VerifyEmailViewModel: ObservableObject {
    @Published var code: String = ""
    @Published var isLoading = false
    @Published var isResending = false
    @Published var error: String? = nil
    @Published var resendBanner = false
    @Published var didAuthenticate = false
    @Published var didVerifyForReset = false
    /// On the `.passwordlessRegister` path, carries the short-lived
    /// registration token the next screen needs to call /register/complete.
    @Published var pendingRegistrationToken: String? = nil
    /// On the `.passwordlessLogin` path, set when the user has 2FA enabled —
    /// the OTP was correct, but a TOTP challenge still has to clear before
    /// tokens are issued. The view pushes `TotpChallengeView` off this.
    @Published var pendingTotpChallengeToken: String? = nil
    @Published var didCancel = false
    @Published var resendSecondsRemaining: Int = 60

    let email: String
    let purpose: VerifyEmailPurpose
    /// Locale captured at the email-entry step; used as the email language
    /// (REGISTER path has no user record yet) and the locale stamped on
    /// the new user row when /register/complete runs.
    let locale: String
    private(set) var challengeToken: String
    private let session = AuthSession.shared
    private var tickTask: Task<Void, Never>?
    /// Wall-clock deadline the cooldown expires at. Driving the countdown
    /// off an absolute Date (rather than a decrementing Int) keeps the
    /// remaining time correct across background suspension — when iOS
    /// pauses our Task.sleep loop, returning to the foreground recomputes
    /// from `Date()` and reflects real elapsed time.
    private var resendDeadline: Date?

    init(email: String, challengeToken: String, purpose: VerifyEmailPurpose = .signupVerification, locale: String = L10n.currentLanguageCode) {
        self.email = email
        self.challengeToken = challengeToken
        self.purpose = purpose
        self.locale = locale
    }

    deinit { tickTask?.cancel() }

    func startCountdown(from seconds: Int = 60) {
        tickTask?.cancel()
        resendDeadline = Date().addingTimeInterval(TimeInterval(seconds))
        refreshFromDeadline()
        tickTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await MainActor.run { self.refreshFromDeadline() }
                if self.resendSecondsRemaining == 0 { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// Recomputes `resendSecondsRemaining` from the wall-clock deadline.
    /// Call on every tick and whenever the app returns to the foreground.
    func refreshFromDeadline() {
        guard let deadline = resendDeadline else {
            resendSecondsRemaining = 0
            return
        }
        let remaining = Int(ceil(deadline.timeIntervalSinceNow))
        resendSecondsRemaining = max(0, remaining)
    }

    var canResend: Bool { !isResending && resendSecondsRemaining == 0 }

    /// Formats the remaining countdown as `M:SS` (e.g. `0:42`).
    var cooldownLabel: String {
        let m = resendSecondsRemaining / 60
        let s = resendSecondsRemaining % 60
        return String(format: "%d:%02d", m, s)
    }

    func submit() async {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 6 else { return }
        isLoading = true
        error = nil

        switch purpose {
        case .signupVerification:
            do {
                try await session.verifyEmail(challengeToken: challengeToken, code: trimmed)
                didAuthenticate = true
            } catch let e as DroobError {
                error = e.errorDescription
            } catch let e {
                error = e.localizedDescription
            }
        case .passwordReset:
            // Validate the OTP against the backend BEFORE advancing to the
            // new-password screen. /v1/auth/verify-reset-code checks the
            // code without consuming it, so the subsequent reset-password
            // call still works with the same code.
            do {
                try await session.verifyPasswordResetCode(email: email, code: trimmed)
                code = trimmed
                didVerifyForReset = true
            } catch let e as DroobError {
                error = e.errorDescription
            } catch let e {
                error = e.localizedDescription
            }
        case .passwordlessLogin:
            do {
                let outcome = try await session.verifyEmailOtpLogin(email: email, code: trimmed)
                switch outcome {
                case .authenticated:
                    didAuthenticate = true
                case .totpRequired(let token):
                    // OTP cleared, but the account has 2FA enabled. Hand off to
                    // TotpChallengeView (pushed by the View's NavigationLink)
                    // exactly like the password-login path does.
                    pendingTotpChallengeToken = token
                }
            } catch let e as DroobError {
                error = e.errorDescription
            } catch let e {
                error = e.localizedDescription
            }
        case .passwordlessRegister:
            do {
                let regToken = try await session.verifyEmailOtpRegister(
                    email: email, code: trimmed, locale: locale)
                pendingRegistrationToken = regToken
            } catch let e as DroobError {
                error = e.errorDescription
            } catch let e {
                error = e.localizedDescription
            }
        }

        isLoading = false
    }

    func resend() async {
        guard canResend else { return }
        isResending = true
        error = nil
        resendBanner = false
        do {
            switch purpose {
            case .signupVerification:
                try await session.resendVerificationEmail(challengeToken: challengeToken)
            case .passwordReset:
                // The reset flow has no JWT challenge token — re-issue by
                // calling /forgot-password again. Backend handles its own
                // resend cooldown (silent no-op within the window) and the
                // account-enumeration guard, so this is safe to retry.
                try await session.requestPasswordReset(email: email)
            case .passwordlessLogin:
                try await session.requestEmailOtpLogin(email: email, locale: locale)
            case .passwordlessRegister:
                try await session.requestEmailOtpRegister(email: email, locale: locale)
            }
            resendBanner = true
            startCountdown()
        } catch let e as DroobError {
            error = e.errorDescription
        } catch let e {
            error = e.localizedDescription
        }
        isResending = false
    }
}

struct VerifyEmailView: View {
    @StateObject private var vm: VerifyEmailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @State private var pushChangePassword = false
    @State private var pushDisplayName = false
    @State private var pushTotpChallenge = false

    init(email: String, challengeToken: String, purpose: VerifyEmailPurpose = .signupVerification, locale: String = L10n.currentLanguageCode) {
        _vm = StateObject(wrappedValue: VerifyEmailViewModel(
            email: email, challengeToken: challengeToken, purpose: purpose, locale: locale))
    }

    var body: some View {
        ZStack(alignment: .top) {
            AuthFigmaColors.bg.ignoresSafeArea()

            // Hidden link that fires only on the reset-password path —
            // after the OTP is accepted locally we push the new-password
            // entry screen onto the same navigation stack.
            NavigationLink(
                destination: ChangePasswordView(email: vm.email, otpCode: vm.code),
                isActive: $pushChangePassword
            ) { EmptyView() }.hidden()

            // Push the display-name prompt after a successful passwordless
            // register OTP verification. The registration token is short-lived
            // (15 min) so we don't gate on user dawdling.
            NavigationLink(
                destination: Group {
                    if let token = vm.pendingRegistrationToken {
                        DisplayNamePromptView(registrationToken: token, email: vm.email)
                    }
                },
                isActive: $pushDisplayName
            ) { EmptyView() }.hidden()

            // Push the TOTP screen when the passwordless-login OTP cleared but
            // the account has 2FA enabled. The flow continues exactly as if
            // password sign-in had cleared the password check.
            NavigationLink(
                destination: Group {
                    if let token = vm.pendingTotpChallengeToken {
                        TotpChallengeView(challengeToken: token)
                    }
                },
                isActive: $pushTotpChallenge
            ) { EmptyView() }.hidden()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 22)

                        AuthBackLink(label: L10n.otpBack) { vm.didCancel = true }
                            .padding(.bottom, 22)

                    // Email icon block
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AuthFigmaColors.surface)
                        Image(systemName: "envelope")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AuthFigmaColors.textPrimary)
                    }
                    .frame(width: 50, height: 50)
                    .padding(.bottom, 22)

                    Text(L10n.otpTitle)
                        .font(BrandFont.display(size: 30, isArabic: appLocale == "ar"))
                        .tracking(appLocale == "ar" ? 0 : -1.2)
                        .foregroundColor(AuthFigmaColors.textPrimary)
                        .padding(.bottom, 8)

                    (Text(String(format: L10n.otpSubtitleFmt, ""))
                        .foregroundColor(AuthFigmaColors.muted)
                    + Text(vm.email)
                        .foregroundColor(AuthFigmaColors.textPrimary))
                        .font(BrandFont.display(size: 17, isArabic: appLocale == "ar"))
                        .padding(.bottom, 22)

                    if vm.resendBanner {
                        Text(L10n.otpResendingBanner)
                            .font(BrandFont.display(size: 13, isArabic: appLocale == "ar"))
                            .foregroundColor(AuthFigmaColors.gold)
                            .padding(.bottom, 12)
                            .transition(.opacity)
                    }

                    if let error = vm.error {
                        AuthFigmaErrorBanner(title: error, detail: nil)
                            .padding(.bottom, 14)
                    }

                    OTPCodeField(
                        code: $vm.code,
                        digitCount: 6,
                        isError: vm.error != nil,
                        onComplete: { _ in
                            Task { await vm.submit() }
                        }
                    )
                    .padding(.bottom, 22)

                    AuthPrimaryGold(
                        title: L10n.otpVerify,
                        loadingTitle: L10n.otpVerifying,
                        isLoading: vm.isLoading,
                        isDisabled: vm.code.count != 6
                    ) {
                        Task { await vm.submit() }
                    }
                    .padding(.bottom, 16)

                    HStack(spacing: 6) {
                        Text(L10n.otpDidntReceive)
                            .foregroundColor(AuthFigmaColors.muted)
                        Button {
                            Task { await vm.resend() }
                        } label: {
                            Text(vm.canResend
                                 ? L10n.otpResendCode
                                 : String(format: L10n.otpResendCooldownFmt, vm.cooldownLabel))
                                .foregroundColor(vm.canResend ? AuthFigmaColors.gold : AuthFigmaColors.muted)
                        }
                        .buttonStyle(.plain)
                        .disabled(!vm.canResend)
                    }
                    .font(BrandFont.display(size: 14, isArabic: appLocale == "ar"))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 28)

                    Color.clear.frame(height: 32)
                    }
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.never)
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { vm.startCountdown() }
        .onChange(of: scenePhase) { phase in
            // The 1-second tick task is suspended while the app is backgrounded,
            // so the displayed cooldown can drift behind real elapsed time.
            // Re-sync from the absolute deadline as soon as we're active again.
            if phase == .active { vm.refreshFromDeadline() }
        }
        .onChange(of: vm.didCancel) { canceled in
            if canceled { dismiss() }
        }
        .onChange(of: vm.didVerifyForReset) { verified in
            if verified { pushChangePassword = true }
        }
        .onChange(of: vm.pendingRegistrationToken) { token in
            pushDisplayName = token != nil
        }
        .onChange(of: vm.pendingTotpChallengeToken) { token in
            pushTotpChallenge = token != nil
        }
        // Reset the sentinel when the user backs out of the 2FA screen so a
        // later retry that returns the same token still re-fires the push.
        .onChange(of: pushTotpChallenge) { isShowing in
            if !isShowing { vm.pendingTotpChallengeToken = nil }
        }
        .animation(.easeInOut(duration: 0.22), value: vm.resendBanner)
    }
}

// MARK: - Email-OTP entry screen (passwordless register)

/// Purpose of the email-input step that precedes OTP entry.
///
/// 2026-07: the LOGIN variant was removed along with the "sign in with email
/// code" button on `LoginView` — sign-in is password / Face ID only now, so
/// this screen is reachable from the REGISTER flow exclusively. The enum is
/// kept (rather than collapsed away) because `EmailOtpEntryView` and
/// `VerifyEmailView` are shared screens and the purpose is what routes the
/// request; `VerifyEmailPurpose` and the `AuthSession` email-OTP calls are
/// deliberately left intact — registration verification and the settings
/// email-change flow ride on the same machinery.
enum EmailOtpEntryPurpose {
    case passwordlessRegister
}

@MainActor
final class EmailOtpEntryViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var isLoading = false
    @Published var error: String? = nil
    /// Non-nil when the request succeeded and the OTP screen should push.
    /// We pass the trimmed email through so the verify screen displays the
    /// same value the user typed and submits it to the verify endpoint.
    @Published var didRequestForEmail: String? = nil

    let purpose: EmailOtpEntryPurpose
    let locale: String

    init(purpose: EmailOtpEntryPurpose, locale: String) {
        self.purpose = purpose
        self.locale = locale
    }

    func submit() async {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            error = L10n.forgotErrorEmpty
            return
        }
        isLoading = true
        error = nil
        do {
            switch purpose {
            case .passwordlessRegister:
                try await AuthSession.shared.requestEmailOtpRegister(email: trimmed, locale: locale)
            }
            didRequestForEmail = trimmed
        } catch let e as DroobError {
            error = e.errorDescription
        } catch let e {
            error = e.localizedDescription
        }
        isLoading = false
    }
}

struct EmailOtpEntryView: View {
    @StateObject private var vm: EmailOtpEntryViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @FocusState private var emailFocused: Bool
    @State private var pushOtp = false

    init(purpose: EmailOtpEntryPurpose, locale: String) {
        _vm = StateObject(wrappedValue: EmailOtpEntryViewModel(purpose: purpose, locale: locale))
    }

    private var title: String {
        switch vm.purpose {
        case .passwordlessRegister: return L10n.emailOtpRegisterEmailTitle
        }
    }

    private var subtitle: String {
        switch vm.purpose {
        case .passwordlessRegister: return L10n.emailOtpRegisterEmailSubtitle
        }
    }

    private var verifyPurpose: VerifyEmailPurpose {
        switch vm.purpose {
        case .passwordlessRegister: return .passwordlessRegister
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            AuthFigmaColors.bg.ignoresSafeArea()

            NavigationLink(
                destination: Group {
                    if let email = vm.didRequestForEmail {
                        // No JWT challenge token on this flow — pass the
                        // email through `challengeToken` for consistency
                        // with the existing initializer signature; the
                        // verify-OTP path keys on email + purpose.
                        VerifyEmailView(
                            email: email,
                            challengeToken: email,
                            purpose: verifyPurpose,
                            locale: vm.locale
                        )
                    }
                },
                isActive: $pushOtp
            ) { EmptyView() }.hidden()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 22)

                        AuthBackLink(label: L10n.forgotBack) { dismiss() }
                            .padding(.bottom, 14)

                        Text(title)
                            .font(BrandFont.display(size: 30, isArabic: appLocale == "ar"))
                            .tracking(appLocale == "ar" ? 0 : -1.2)
                            .foregroundColor(AuthFigmaColors.textPrimary)
                            .padding(.bottom, 10)

                        Text(subtitle)
                            .font(BrandFont.display(size: 17, isArabic: appLocale == "ar"))
                            .foregroundColor(AuthFigmaColors.muted)
                            .lineSpacing(26.35 - 17)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 24)

                        if let err = vm.error {
                            AuthFigmaErrorBanner(title: err, detail: nil)
                                .padding(.bottom, 14)
                        }

                        InlineRowCard {
                            InlineRow(
                                label: L10n.loginEmailLabel,
                                text: $vm.email,
                                placeholder: L10n.loginEmailPlaceholder,
                                keyboardType: .emailAddress,
                                contentType: .emailAddress,
                                autocap: .never,
                                autocorrection: false,
                                submitLabel: .send,
                                isError: vm.error != nil,
                                showDivider: false
                            )
                            .focused($emailFocused)
                            .onSubmit { Task { await vm.submit() } }
                        }
                        .padding(.bottom, 24)

                        AuthPrimaryGold(
                            title: L10n.emailOtpSendCode,
                            loadingTitle: L10n.emailOtpSending,
                            isLoading: vm.isLoading
                        ) {
                            emailFocused = false
                            Task { await vm.submit() }
                        }
                        .padding(.bottom, 28)

                        Color.clear.frame(height: 32)
                    }
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.never)
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: vm.didRequestForEmail) { newValue in
            pushOtp = newValue != nil
        }
        // Reset sentinel when the user pops back from the OTP screen so the
        // next submit re-triggers the push (same dance as ForgotPasswordView).
        .onChange(of: pushOtp) { isShowing in
            if !isShowing { vm.didRequestForEmail = nil }
        }
    }
}

// MARK: - Display-name prompt (new passwordless registrations)
//
// Runs after `/email-otp/register/verify` succeeds — the registration token
// has been issued but no user row exists yet. Submitting completes the
// account, mints tokens, and promotes the AuthSession to authenticated.

@MainActor
final class DisplayNamePromptViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var isLoading = false
    @Published var error: String? = nil

    let registrationToken: String
    let email: String

    init(registrationToken: String, email: String) {
        self.registrationToken = registrationToken
        self.email = email
    }

    func submit() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = L10n.forgotErrorEmpty
            return
        }
        isLoading = true
        error = nil
        do {
            try await AuthSession.shared.completeEmailOtpRegister(
                registrationToken: registrationToken, displayName: trimmed)
            // AuthSession flips to .authenticated and the root navigation
            // swaps to the home stack automatically — no explicit push.
        } catch let e as DroobError {
            error = e.errorDescription
        } catch let e {
            error = e.localizedDescription
        }
        isLoading = false
    }
}

struct DisplayNamePromptView: View {
    @StateObject private var vm: DisplayNamePromptViewModel
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @FocusState private var nameFocused: Bool

    init(registrationToken: String, email: String) {
        _vm = StateObject(wrappedValue: DisplayNamePromptViewModel(
            registrationToken: registrationToken, email: email))
    }

    var body: some View {
        ZStack(alignment: .top) {
            AuthFigmaColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 22)

                        Text(L10n.displayNameTitle)
                            .font(BrandFont.display(size: 30, isArabic: appLocale == "ar"))
                            .tracking(appLocale == "ar" ? 0 : -1.2)
                            .foregroundColor(AuthFigmaColors.textPrimary)
                            .padding(.bottom, 10)

                        Text(L10n.displayNameSubtitle)
                            .font(BrandFont.display(size: 17, isArabic: appLocale == "ar"))
                            .foregroundColor(AuthFigmaColors.muted)
                            .lineSpacing(26.35 - 17)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 24)

                        if let err = vm.error {
                            AuthFigmaErrorBanner(title: err, detail: nil)
                                .padding(.bottom, 14)
                        }

                        InlineRowCard {
                            InlineRow(
                                label: L10n.displayNameLabel,
                                text: $vm.name,
                                placeholder: L10n.displayNamePlaceholder,
                                contentType: .name,
                                autocap: .words,
                                autocorrection: false,
                                submitLabel: .done,
                                isError: vm.error != nil,
                                showDivider: false
                            )
                            .focused($nameFocused)
                            .onSubmit { Task { await vm.submit() } }
                        }
                        .padding(.bottom, 24)

                        AuthPrimaryGold(
                            title: L10n.displayNameContinue,
                            loadingTitle: L10n.displayNameContinuing,
                            isLoading: vm.isLoading,
                            isDisabled: vm.name.trimmingCharacters(in: .whitespaces).isEmpty
                        ) {
                            nameFocused = false
                            Task { await vm.submit() }
                        }
                        .padding(.bottom, 28)

                        Color.clear.frame(height: 32)
                    }
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.never)
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
