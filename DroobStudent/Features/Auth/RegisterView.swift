import SwiftUI

// MARK: - RegisterView (Figma redesign)
//
// Settings-style inline-row form. Top-to-bottom:
//   chip bar → "< Sign In" back link → "Create account" title →
//   "Join the Droob community" subtitle → "YOUR INFO" section →
//   InlineRowCard(firstName + lastName + email + password Show) →
//   8-char hint → "Create Account" CTA → terms text.

struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @FocusState private var focusedField: Field?
    @State private var showPassword = false
    @State private var showEmailVerification = false
    @State private var showTotpChallenge = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showEmailOtpRegister = false

    private enum Field: Hashable { case firstName, lastName, email, password }

    var body: some View {
        ZStack(alignment: .top) {
            AuthFigmaColors.bg.ignoresSafeArea()

            NavigationLink(
                destination: Group {
                    if let token = viewModel.pendingEmailVerificationChallenge,
                       let email = viewModel.pendingEmailVerificationEmail {
                        VerifyEmailView(email: email, challengeToken: token)
                    }
                },
                isActive: $showEmailVerification
            ) { EmptyView() }.hidden()

            NavigationLink(
                destination: Group {
                    if let token = viewModel.pendingTotpChallenge {
                        TotpChallengeView(challengeToken: token)
                    }
                },
                isActive: $showTotpChallenge
            ) { EmptyView() }.hidden()

            NavigationLink(destination: TermsOfServiceView(), isActive: $showTerms) { EmptyView() }.hidden()
            NavigationLink(destination: PrivacyPolicyView(), isActive: $showPrivacy) { EmptyView() }.hidden()
            NavigationLink(
                destination: EmailOtpEntryView(purpose: .passwordlessRegister, locale: appLocale),
                isActive: $showEmailOtpRegister
            ) { EmptyView() }.hidden()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 22)

                        AuthBackLink(label: L10n.registerBack) { dismiss() }
                            .padding(.bottom, 14)

                    Text(L10n.registerTitle)
                        .font(BrandFont.display(size: 30, isArabic: appLocale == "ar"))
                        .tracking(appLocale == "ar" ? 0 : -1.2)
                        .foregroundColor(AuthFigmaColors.textPrimary)
                        .padding(.bottom, 8)

                    Text(L10n.registerSubtitle)
                        .font(BrandFont.display(size: 17, isArabic: appLocale == "ar"))
                        .foregroundColor(AuthFigmaColors.muted)
                        .padding(.bottom, 24)

                    AuthSectionHeader(text: L10n.registerSectionInfo)
                        .padding(.bottom, 10)

                    if let msg = viewModel.errorMessage {
                        AuthFigmaErrorBanner(title: msg, detail: nil)
                            .padding(.bottom, 14)
                    }

                    InlineRowCard {
                        InlineRow(
                            label: L10n.registerFirstName,
                            text: $viewModel.firstName,
                            placeholder: "",
                            contentType: .givenName,
                            autocap: .words,
                            autocorrection: false,
                            submitLabel: .next,
                            showDivider: true
                        )
                        .focused($focusedField, equals: .firstName)

                        InlineRow(
                            label: L10n.registerLastName,
                            text: $viewModel.lastName,
                            placeholder: "",
                            contentType: .familyName,
                            autocap: .words,
                            autocorrection: false,
                            submitLabel: .next,
                            showDivider: true
                        )
                        .focused($focusedField, equals: .lastName)

                        InlineRow(
                            label: L10n.registerEmail,
                            text: $viewModel.email,
                            placeholder: "",
                            keyboardType: .emailAddress,
                            contentType: .emailAddress,
                            autocap: .never,
                            autocorrection: false,
                            submitLabel: .next,
                            showDivider: true
                        )
                        .focused($focusedField, equals: .email)

                        InlineRow(
                            label: L10n.registerPassword,
                            text: $viewModel.password,
                            placeholder: L10n.registerPasswordPlaceholder,
                            isSecure: true,
                            contentType: .newPassword,
                            autocap: .never,
                            autocorrection: false,
                            submitLabel: .go,
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

                    Text(L10n.registerPasswordHint)
                        .font(BrandFont.display(size: 13, isArabic: appLocale == "ar"))
                        .foregroundColor(AuthFigmaColors.muted)
                        .padding(.top, 10)
                        .padding(.bottom, 24)

                    AuthPrimaryGold(
                        title: L10n.registerCreateAccount,
                        loadingTitle: L10n.registerCreatingAccount,
                        isLoading: viewModel.isLoading
                    ) {
                        focusedField = nil
                        Task { await viewModel.register() }
                    }
                    .padding(.bottom, 12)

                    // Passwordless alternative — skips the password form
                    // entirely. The user can opt into a password later from
                    // Settings via the existing change-password flow.
                    AuthSecondaryDark(title: L10n.emailOtpRegisterCta) {
                        showEmailOtpRegister = true
                    }
                    .padding(.bottom, 18)

                    termsBlock
                        .padding(.bottom, 28)
                        .environment(\.openURL, OpenURLAction { url in
                            switch url.absoluteString {
                            case "droob://terms":   showTerms = true
                            case "droob://privacy": showPrivacy = true
                            default: return .systemAction
                            }
                            return .handled
                        })

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
        .onAppear { viewModel.selectedLocale = appLocale }
        .onChange(of: appLocale) { newValue in viewModel.selectedLocale = newValue }
        .onChange(of: viewModel.pendingEmailVerificationChallenge) { newValue in
            showEmailVerification = newValue != nil
        }
        .onChange(of: viewModel.pendingTotpChallenge) { newValue in
            showTotpChallenge = newValue != nil
        }
        // Clear the challenge when the user backs out of the 2FA screen so a
        // second attempt re-triggers the push (same trap LoginView guards).
        .onChange(of: showTotpChallenge) { isShowing in
            if !isShowing { viewModel.pendingTotpChallenge = nil }
        }
        .onSubmit {
            switch focusedField {
            case .firstName: focusedField = .lastName
            case .lastName:  focusedField = .email
            case .email:     focusedField = .password
            case .password, .none:
                focusedField = nil
                Task { await viewModel.register() }
            }
        }
        .onDisappear { focusedField = nil }
    }

    /// Bottom-of-screen paragraph with tappable "Terms of Service" / "Privacy
    /// Policy" inline links. We build an `AttributedString` so SwiftUI renders
    /// it as one flowing paragraph (rather than three Text views the wrap
    /// engine can't reflow together). Each link uses a custom `droob://`
    /// scheme that the parent screen's `openURL` handler intercepts to push
    /// the matching navigation destination.
    private var termsBlock: some View {
        Text(termsAttributedString)
            .font(BrandFont.display(size: 13, isArabic: appLocale == "ar"))
            .multilineTextAlignment(.center)
            .tint(AuthFigmaColors.gold)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var termsAttributedString: AttributedString {
        var prefix = AttributedString(L10n.registerTermsPrefix)
        prefix.foregroundColor = AuthFigmaColors.muted

        var terms = AttributedString(L10n.registerTermsOfService)
        terms.foregroundColor = AuthFigmaColors.gold
        terms.link = URL(string: "droob://terms")

        var conj = AttributedString(L10n.registerTermsAnd)
        conj.foregroundColor = AuthFigmaColors.muted

        var privacy = AttributedString(L10n.registerPrivacyPolicy)
        privacy.foregroundColor = AuthFigmaColors.gold
        privacy.link = URL(string: "droob://privacy")

        var suffix = AttributedString(L10n.registerTermsSuffix)
        suffix.foregroundColor = AuthFigmaColors.muted

        var out = prefix
        out.append(terms)
        out.append(conj)
        out.append(privacy)
        out.append(suffix)
        return out
    }
}
