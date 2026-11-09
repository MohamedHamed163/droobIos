import SwiftUI

// MARK: - LoginView (Figma redesign)
//
// Layout (top → bottom):
//   chip bar (Dark / EN) → big gold-glow logo → "Sign In to Droob" →
//   subtitle → InlineRowCard(email + password Show toggle) →
//   "Forgot Password?" → "Sign In" CTA → "or" divider → Google / Apple →
//   "Don't have an account? Sign Up".
//
// Error state replaces the dark-row card with a red-tinted variant + adds
// a translucent red banner above and a dark "Reset Password" CTA below
// the gold "Try Again" CTA.

struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @FocusState private var focusedField: Field?
    @State private var showPassword = false
    @State private var showForgotPassword = false
    @State private var showTotpChallenge = false
    @State private var showEmailVerification = false
    @State private var showRegister = false
    /// Pre-login course browser (App Store Guideline 5.1.1(v)): lets a
    /// visitor preview courses without an account; enrolling routes back
    /// here to sign in.
    @State private var showGuestBrowse = false

    private enum Field: Hashable { case email, password }

    // "Error mode" — red field outlines, Try Again label, Reset Password CTA —
    // applies only when the backend rejected the credentials, not when local
    // validation surfaced (e.g. empty-field hint). Local-validation messages
    // still render in the banner above via viewModel.errorMessage.
    private var isError: Bool {
        viewModel.emailFieldError != nil || viewModel.passwordFieldError != nil
    }

    // Browse the catalog without an account (App Store Guideline 5.1.1(v)).
    // Extracted from `body` so the (already large) login view stays cheap to
    // type-check. Enrolling from a preview routes back here to sign in.
    private var guestBrowseButton: some View {
        Button { showGuestBrowse = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.loginBrowseCoursesGuest)
            }
            .font(BrandFont.display(size: 15, isArabic: appLocale == "ar"))
            .foregroundColor(AuthFigmaColors.muted)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 22)
        .fullScreenCover(isPresented: $showGuestBrowse) {
            GuestBrowseView(onSignIn: { showGuestBrowse = false })
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            AuthFigmaColors.bg.ignoresSafeArea()

            // Hidden navigation triggers
            NavigationLink(destination: ForgotPasswordView(), isActive: $showForgotPassword) { EmptyView() }.hidden()
            NavigationLink(
                destination: Group {
                    if let token = viewModel.pendingTotpChallenge {
                        TotpChallengeView(challengeToken: token)
                    }
                },
                isActive: $showTotpChallenge
            ) { EmptyView() }.hidden()
            NavigationLink(
                destination: Group {
                    if let token = viewModel.pendingEmailVerificationChallenge,
                       let email = viewModel.pendingEmailVerificationEmail {
                        VerifyEmailView(email: email, challengeToken: token)
                    }
                },
                isActive: $showEmailVerification
            ) { EmptyView() }.hidden()
            NavigationLink(destination: RegisterView(), isActive: $showRegister) { EmptyView() }.hidden()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 22)

                        AuthLogo(size: 72, showGlow: true)
                            .padding(.bottom, 16)

                    Text(L10n.loginTitle)
                        .font(BrandFont.display(size: 30, isArabic: appLocale == "ar"))
                        .tracking(appLocale == "ar" ? 0 : -1.2)
                        .foregroundColor(AuthFigmaColors.textPrimary)
                        .lineSpacing(35.4 - 30)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 6)

                    Text(L10n.loginSubtitle)
                        .font(BrandFont.display(size: 17, isArabic: appLocale == "ar"))
                        .foregroundColor(AuthFigmaColors.muted)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 18)

                    // Error banner (only in error state). Use the actual
                    // viewModel.errorMessage so missing-fields / rate-limit /
                    // server-error cases show their own text instead of all
                    // collapsing to "invalid credentials".
                    if let message = viewModel.errorMessage {
                        AuthFigmaErrorBanner(title: message, detail: nil)
                            .padding(.bottom, 14)
                    }

                    // Inline row card (email + password).
                    InlineRowCard {
                        InlineRow(
                            label: L10n.loginEmailLabel,
                            text: $viewModel.email,
                            placeholder: L10n.loginEmailPlaceholder,
                            keyboardType: .emailAddress,
                            contentType: .emailAddress,
                            autocap: .never,
                            autocorrection: false,
                            submitLabel: .next,
                            isError: isError,
                            showDivider: true
                        )
                        .focused($focusedField, equals: .email)

                        InlineRow(
                            label: L10n.loginPasswordLabel,
                            text: $viewModel.password,
                            placeholder: L10n.loginPasswordPlaceholder,
                            isSecure: true,
                            contentType: .password,
                            autocap: .never,
                            autocorrection: false,
                            submitLabel: .go,
                            isError: isError,
                            revealSecure: showPassword,
                            trailing: AnyView(
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Text(showPassword ? L10n.loginHide : L10n.loginShow)
                                        .font(BrandFont.display(size: 15, isArabic: appLocale == "ar"))
                                        .foregroundColor(AuthFigmaColors.gold)
                                }
                                .buttonStyle(.plain)
                            ),
                            showDivider: false
                        )
                        .focused($focusedField, equals: .password)
                    }

                    // Always visible — recovery must stay reachable even after a
                    // failed login. In the error state this sits above the gold CTA,
                    // with the "Reset Password" CTA also shown below it.
                    HStack {
                        Spacer()
                        Button { showForgotPassword = true } label: {
                            Text(L10n.loginForgot)
                                .font(BrandFont.display(size: 15, isArabic: appLocale == "ar"))
                                .foregroundColor(AuthFigmaColors.gold)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 16)

                    // Primary CTA.
                    AuthPrimaryGold(
                        title: isError ? L10n.loginTryAgain : L10n.loginSignIn,
                        loadingTitle: L10n.loginSigningIn,
                        isLoading: viewModel.isLoading
                    ) { submit() }
                    .padding(.bottom, isError ? 10 : 16)

                    if isError {
                        AuthSecondaryDark(title: L10n.loginResetPassword) {
                            showForgotPassword = true
                        }
                        .padding(.bottom, 16)
                    }

                    // Alternate sign-in methods stay visible regardless of
                    // error state — a failed password attempt shouldn't hide
                    // them, they are independent auth paths. The divider only
                    // renders when something follows it: with the email-code
                    // button gone (below) Face ID is the last remaining
                    // alternate, and an "or" introducing nothing looks broken.
                    if viewModel.isBiometricLoginAvailable {
                        AuthOrDivider(label: L10n.loginOr)
                            .padding(.bottom, 12)
                    }

                    // 2026-07: the passwordless "sign in with an email code"
                    // entry point was removed — sign-in is password (or Face
                    // ID) plus account creation. The email-OTP machinery
                    // itself stays: registration verification and the
                    // settings email-change flow both still use it.

                    // Face ID / Touch ID button — only when this install
                    // has previously enrolled biometric login. Renders
                    // above the Google/Apple row because it's the fastest
                    // path back into an existing session.
                    if viewModel.isBiometricLoginAvailable {
                        AuthSocialButton(label: L10n.loginBiometricFaceID) {
                            Task { await viewModel.signInWithBiometric() }
                        } icon: {
                            Image(systemName: "faceid")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AuthFigmaColors.textPrimary)
                        }
                        .padding(.bottom, 10)
                    }

                    // Hidden for now (2026-07): Google/Apple sign-in removed
                    // from the login screen. The "or" divider above now only
                    // shows when the Face ID button does; restoring this block
                    // means making that divider unconditional again.
                    // Restore by uncommenting this block:
                    // HStack(spacing: 10) {
                    //     AuthSocialButton(label: L10n.loginSocialGoogle) {
                    //         Task { await viewModel.signInWithGoogle(locale: appLocale) }
                    //     } icon: {
                    //         GoogleLogo().frame(width: 18, height: 18)
                    //     }
                    //     AuthSocialButton(label: L10n.loginSocialApple) {
                    //         Task { await viewModel.signInWithApple(locale: appLocale) }
                    //     } icon: {
                    //         Image(systemName: "apple.logo")
                    //             .font(.system(size: 16, weight: .semibold))
                    //             .foregroundColor(AuthFigmaColors.textPrimary)
                    //     }
                    // }
                    // .padding(.bottom, 18)

                    Button { showRegister = true } label: {
                        HStack(spacing: 4) {
                            Text(L10n.loginNoAccountPrefix)
                                .foregroundColor(AuthFigmaColors.muted)
                            Text(L10n.loginSignUpLink)
                                .foregroundColor(AuthFigmaColors.gold)
                        }
                        .font(BrandFont.display(size: 15, isArabic: appLocale == "ar"))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 14)

                    guestBrowseButton
                    }
                    .padding(.horizontal, 22)
                }
                .scrollDismissesKeyboard(.never)
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: viewModel.pendingTotpChallenge) { newValue in
            showTotpChallenge = newValue != nil
        }
        // Clear the challenge when the user backs out of the 2FA screen,
        // otherwise re-logging in returns the same token, `onChange` above
        // doesn't fire, and the push never re-triggers — same trap the
        // forgot-password chain guards against below.
        .onChange(of: showTotpChallenge) { isShowing in
            if !isShowing { viewModel.pendingTotpChallenge = nil }
        }
        .onChange(of: viewModel.pendingEmailVerificationChallenge) { newValue in
            showEmailVerification = newValue != nil
        }
        .sheet(item: Binding(
            get: { viewModel.pendingCaptchaSiteKey.map(CaptchaSiteKey.init) },
            set: { newValue in viewModel.pendingCaptchaSiteKey = newValue?.value }
        )) { siteKey in
            TurnstileSheet(siteKey: siteKey.value) { token in
                Task { await viewModel.submitWithCaptcha(token: token) }
            }
        }
        .onSubmit {
            switch focusedField {
            case .email:    focusedField = .password
            case .password, .none: submit()
            }
        }
        .onAppear { viewModel.consumeSessionEndNotice() }
        .onDisappear { focusedField = nil }
        .onReceive(NotificationCenter.default.publisher(
            for: .droobResetPasswordFlowDone)) { _ in
            // Collapse the whole forgot-password chain back to sign-in after
            // a successful reset. Flipping the root binding here is reliable;
            // bubbling dismiss() up through the nested isActive links is not.
            showForgotPassword = false
        }
    }

    private func submit() {
        focusedField = nil
        Task { await viewModel.login() }
    }
}

// MARK: - Forgot Password ViewModel
//
// Single-step "send code to my email" flow. On success we push the OTP
// screen (`VerifyEmailView` reused — same UI for both verify-email and
// reset-password code entry, per design.)

@MainActor
final class ForgotPasswordViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    /// True once the user successfully posted to /forgot-password. We DON'T
    /// claim a code was sent (the backend always 204s, including for
    /// non-existent accounts — that's the account-enumeration guard).
    @Published var didSubmit: Bool = false
    /// Distinct from `didSubmit` — toggled when the user explicitly taps
    /// "I have a code", which is what pushes VerifyEmailView. This way the
    /// app never advances to the OTP screen on its own for an unknown email.
    @Published var pendingChallengeToken: String? = nil

    func send() async {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            error = L10n.forgotErrorEmpty
            return
        }
        isLoading = true
        error = nil
        do {
            try await AuthSession.shared.requestPasswordReset(email: trimmed)
            // Backend always 204s (account-enumeration guard) — show a
            // neutral "if an account exists" message and let the user
            // proceed manually via "I have a code".
            didSubmit = true
        } catch let e as DroobError {
            error = e.errorDescription
        } catch let e {
            error = e.localizedDescription
        }
        isLoading = false
    }

    /// User confirms they got a code and wants to enter it. Triggers the
    /// push to VerifyEmailView. The `email` is reused as the sentinel
    /// since the forgot-password flow doesn't issue a JWT challenge token.
    func continueToOtp() {
        pendingChallengeToken = email.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Forgot Password screen (Figma redesign)
//
// Single-field "send my reset code" screen. Successful submit pushes the
// OTP entry screen via `VerifyEmailView`.

struct ForgotPasswordView: View {
    @StateObject private var vm = ForgotPasswordViewModel()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @FocusState private var emailFocused: Bool
    @State private var showVerify = false

    var body: some View {
        ZStack(alignment: .top) {
            AuthFigmaColors.bg.ignoresSafeArea()

            NavigationLink(
                destination: Group {
                    if let token = vm.pendingChallengeToken {
                        VerifyEmailView(
                            email: vm.email,
                            challengeToken: token,
                            purpose: .passwordReset
                        )
                    }
                },
                isActive: $showVerify
            ) { EmptyView() }.hidden()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 22)

                        AuthBackLink(label: L10n.forgotBack) { dismiss() }
                            .padding(.bottom, 14)

                    Text(L10n.forgotTitle)
                        .font(BrandFont.display(size: 30, isArabic: appLocale == "ar"))
                        .tracking(appLocale == "ar" ? 0 : -1.2)
                        .foregroundColor(AuthFigmaColors.textPrimary)
                        .padding(.bottom, 10)

                    Text(L10n.forgotDescription)
                        .font(BrandFont.display(size: 17, isArabic: appLocale == "ar"))
                        .foregroundColor(AuthFigmaColors.muted)
                        .lineSpacing(26.35 - 17)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 24)

                    AuthSectionHeader(text: L10n.forgotEmailSection)
                        .padding(.bottom, 10)

                    if let err = vm.error {
                        AuthFigmaErrorBanner(title: err, detail: nil)
                            .padding(.bottom, 14)
                    }

                    // Neutral confirmation — shown after a successful POST
                    // regardless of whether the account actually exists, so
                    // the screen never reveals which addresses are registered.
                    if vm.didSubmit && vm.error == nil {
                        Text(L10n.forgotSentNeutral)
                            .font(BrandFont.display(size: 14, isArabic: appLocale == "ar"))
                            .foregroundColor(AuthFigmaColors.gold)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 14)
                    }

                    InlineRowCard {
                        InlineRow(
                            label: L10n.forgotEmailLabel,
                            text: $vm.email,
                            placeholder: L10n.forgotEmailPlaceholder,
                            keyboardType: .emailAddress,
                            contentType: .emailAddress,
                            autocap: .never,
                            autocorrection: false,
                            submitLabel: .send,
                            isError: vm.error != nil,
                            showDivider: false
                        )
                        .focused($emailFocused)
                        .onChange(of: vm.email) { _ in
                            // Editing the email after submission resets the
                            // confirmation state so the user can start over
                            // with a different address.
                            if vm.didSubmit { vm.didSubmit = false }
                        }
                        .onSubmit { Task { await vm.send() } }
                    }

                    Text(L10n.forgotHint)
                        .font(BrandFont.display(size: 13, isArabic: appLocale == "ar"))
                        .foregroundColor(AuthFigmaColors.muted)
                        .padding(.top, 10)
                        .padding(.bottom, 24)

                    AuthPrimaryGold(
                        title: L10n.forgotSendButton,
                        loadingTitle: L10n.forgotSending,
                        isLoading: vm.isLoading
                    ) {
                        emailFocused = false
                        Task { await vm.send() }
                    }
                    .padding(.bottom, vm.didSubmit && vm.error == nil ? 12 : 28)

                    // Only appears after a successful submission — the user
                    // taps it once they've actually received a code. Auto-
                    // advancing instead would imply "we sent something" for
                    // unknown emails, which is what the bug report flagged.
                    if vm.didSubmit && vm.error == nil {
                        AuthSecondaryDark(title: L10n.forgotHaveCode) {
                            vm.continueToOtp()
                        }
                        .padding(.bottom, 28)
                    }

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
        .onChange(of: vm.pendingChallengeToken) { newValue in
            showVerify = newValue != nil
        }
        // Reset the sentinel when the user navigates back from the OTP
        // screen, otherwise the next "I have a code" tap assigns the same
        // email value and `onChange(of: pendingChallengeToken)` doesn't fire
        // — leaving the user stuck on the email screen with no way back.
        .onChange(of: showVerify) { isShowing in
            if !isShowing { vm.pendingChallengeToken = nil }
        }
    }
}
