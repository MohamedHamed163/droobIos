import SwiftUI

// MARK: - ChangePasswordView
//
// Third step of the forgot-password flow. Reached after the user
// correctly enters the OTP. Takes a new password (+ confirmation) and
// posts the change to the backend. On success it does NOT sign the user
// in — it shows a "Password changed successfully" screen prompting the
// user to log in again with the new credentials.
//
// Flow: ForgotPasswordView → VerifyEmailView (purpose .passwordReset)
//   → ChangePasswordView → (success screen) → back to LoginView.

@MainActor
final class ChangePasswordViewModel: ObservableObject {
    @Published var newPassword: String = ""
    @Published var confirmPassword: String = ""
    @Published var showPassword: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var didFinish: Bool = false

    let email: String
    let otpCode: String

    init(email: String, otpCode: String) {
        self.email = email
        self.otpCode = otpCode
    }

    /// Same rule as registration: at least 8 characters, with a digit
    /// or symbol. Kept in sync with `RegisterViewModel.register`.
    var validationError: String? {
        if newPassword.count < 8 {
            return L10n.authErrPasswordShort
        }
        let hasDigitOrSymbol = newPassword.rangeOfCharacter(from: .decimalDigits) != nil
            || newPassword.rangeOfCharacter(from: .symbols) != nil
            || newPassword.rangeOfCharacter(from: .punctuationCharacters) != nil
        if !hasDigitOrSymbol {
            return L10n.authErrPasswordNoDigit
        }
        if newPassword != confirmPassword {
            return L10n.authErrPasswordMismatch
        }
        return nil
    }

    var canSubmit: Bool {
        !isLoading && !newPassword.isEmpty && !confirmPassword.isEmpty
    }

    /// Drives the Figma "Password strength" meter. Scores length + character
    /// variety into four buckets; `.empty` hides the meter entirely so the
    /// pristine screen matches the form before the user types.
    var strength: PasswordStrength {
        let p = newPassword
        if p.isEmpty { return .empty }
        var score = 0
        if p.count >= 8 { score += 1 }
        if p.count >= 12 { score += 1 }
        let hasLetter = p.rangeOfCharacter(from: .letters) != nil
        let hasDigit = p.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSymbol = p.rangeOfCharacter(from: .symbols) != nil
            || p.rangeOfCharacter(from: .punctuationCharacters) != nil
        if hasLetter && hasDigit { score += 1 }
        if hasSymbol { score += 1 }
        switch score {
        case 0, 1: return .weak
        case 2: return .fair
        case 3: return .good
        default: return .strong
        }
    }

    func submit() async {
        if let err = validationError {
            error = err
            return
        }
        isLoading = true
        error = nil

        // POSTs /v1/auth/reset-password with { email, code, new_password }.
        // On success the backend swaps the password hash. The session is
        // deliberately left unauthenticated (see confirmPasswordReset) so
        // we land on the success screen and the user re-authenticates.
        do {
            try await AuthSession.shared.confirmPasswordReset(
                email: email, code: otpCode, newPassword: newPassword)
            didFinish = true
        } catch let e as DroobError {
            error = e.errorDescription
        } catch let e {
            error = e.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Password strength
//
// Four-level strength used by the "Create New Password" meter. Each level
// maps to a fill fraction (bar width) and a label color. The bar itself
// draws the gold Figma gradient; the level only varies its width + the
// trailing word's tint.
enum PasswordStrength: Equatable {
    case empty, weak, fair, good, strong

    /// Shown on the same row as `reset.strength`, so it has to be in the same
    /// language as the label beside it — it used to be a hardcoded English
    /// switch, which put "قوة كلمة المرور" and "Weak" on one line.
    var label: String {
        switch self {
        case .empty:  return ""
        case .weak:   return L10n.resetStrengthWeak
        case .fair:   return L10n.resetStrengthFair
        case .good:   return L10n.resetStrengthGood
        case .strong: return L10n.resetStrengthStrong
        }
    }

    var fraction: CGFloat {
        switch self {
        case .empty:  return 0
        case .weak:   return 0.28
        case .fair:   return 0.5
        case .good:   return 0.72
        case .strong: return 1
        }
    }

    var color: Color {
        switch self {
        case .empty:  return .clear
        case .weak:   return AuthFigmaColors.errorRed
        case .fair:   return AuthFigmaColors.gold
        case .good:   return Color(red: 1.0, green: 0.624, blue: 0.039) // #FF9F0A
        case .strong: return AuthFigmaColors.successGreen
        }
    }
}

struct ChangePasswordView: View {
    @StateObject private var vm: ChangePasswordViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    private var isArabic: Bool { appLocale == "ar" }

    init(email: String, otpCode: String) {
        _vm = StateObject(wrappedValue: ChangePasswordViewModel(email: email, otpCode: otpCode))
    }

    var body: some View {
        ZStack(alignment: .top) {
            AuthFigmaColors.bg.ignoresSafeArea()

            if vm.didFinish {
                successScreen
            } else {
                formScreen
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // Shown after the backend confirms the password change. The user is
    // intentionally NOT logged in here — they must sign in again with the
    // new password. "Sign In" collapses the whole forgot-password chain
    // back to LoginView via a notification. Matches Figma node 599-4188.
    private var successScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 9.3) {
                ZStack {
                    Circle()
                        .fill(AuthFigmaColors.successGreen.opacity(0.1))
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(AuthFigmaColors.successGreen)
                }
                .frame(width: 72, height: 72)

                Text(L10n.resetDoneTitle)
                    .font(BrandFont.display(size: 28, isArabic: isArabic))
                    .tracking(isArabic ? 0 : -1.12)
                    .foregroundColor(AuthFigmaColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14.7)

                Text(L10n.resetDoneBody)
                    .font(BrandFont.display(size: 17, isArabic: isArabic))
                    .foregroundColor(AuthFigmaColors.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .padding(.horizontal, 24)

            Spacer()

            AuthPrimaryGold(title: L10n.login) {
                NotificationCenter.default.post(name: .droobResetPasswordFlowDone, object: nil)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    private var formScreen: some View {
        VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 22)

                        AuthBackLink(label: L10n.back) { dismiss() }
                            .padding(.bottom, 22)

                        Text(L10n.resetTitle)
                            .font(BrandFont.display(size: 34, isArabic: isArabic))
                            .tracking(isArabic ? 0 : -1.36)
                            .foregroundColor(AuthFigmaColors.textPrimary)
                            .padding(.bottom, 8)

                        Text(L10n.resetSubtitle)
                            .font(BrandFont.display(size: 17, isArabic: isArabic))
                            .foregroundColor(AuthFigmaColors.muted)
                            .padding(.bottom, 22)

                        if let err = vm.error {
                            AuthFigmaErrorBanner(title: err, detail: nil)
                                .padding(.bottom, 14)
                        }

                        if vm.strength != .empty {
                            passwordStrengthMeter
                                .padding(.bottom, 16)
                        }

                        AuthSectionHeader(text: L10n.resetSectionNewPassword)
                            .padding(.bottom, 10)

                        InlineRowCard {
                            InlineRow(
                                label: L10n.resetFieldPassword,
                                text: $vm.newPassword,
                                placeholder: "••••••••",
                                isSecure: true,
                                contentType: .newPassword,
                                autocap: .never,
                                autocorrection: false,
                                submitLabel: .next,
                                isError: vm.error != nil,
                                revealSecure: vm.showPassword,
                                trailing: revealToggle
                            )
                            InlineRow(
                                label: L10n.resetFieldConfirm,
                                text: $vm.confirmPassword,
                                placeholder: "••••••••",
                                isSecure: true,
                                contentType: .newPassword,
                                autocap: .never,
                                autocorrection: false,
                                submitLabel: .done,
                                isError: vm.error != nil,
                                revealSecure: vm.showPassword,
                                trailing: revealToggle,
                                showDivider: false
                            )
                        }

                        Text(L10n.resetHint)
                            .font(BrandFont.display(size: 13, isArabic: isArabic))
                            .foregroundColor(AuthFigmaColors.muted)
                            .padding(.top, 7)
                            .padding(.bottom, 28)

                        AuthPrimaryGold(
                            title: L10n.resetUpdateButton,
                            loadingTitle: L10n.resetUpdating,
                            isLoading: vm.isLoading,
                            isDisabled: !vm.canSubmit
                        ) {
                            Task { await vm.submit() }
                        }
                        .padding(.bottom, 28)

                        Color.clear.frame(height: 32)
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.never)
                .scrollIndicators(.hidden)
        }
    }

    // Single eye toggle reused on both password rows so the show/hide
    // control is consistent across the form (Figma node 599-4020).
    private var revealToggle: AnyView {
        AnyView(
            Button {
                vm.showPassword.toggle()
            } label: {
                Image(systemName: vm.showPassword ? "eye.slash" : "eye")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(AuthFigmaColors.muted)
            }
            .buttonStyle(.plain)
        )
    }

    private var passwordStrengthMeter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.resetStrength)
                    .font(BrandFont.display(size: 13, isArabic: isArabic))
                    .foregroundColor(AuthFigmaColors.muted)
                Spacer()
                Text(vm.strength.label)
                    .font(BrandFont.display(size: 13, isArabic: isArabic))
                    .foregroundColor(vm.strength.color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(red: 120/255, green: 120/255, blue: 128/255)
                            .opacity(0.22))
                    Capsule()
                        .fill(LinearGradient.droobButtonGradient)
                        .frame(width: geo.size.width * vm.strength.fraction)
                }
            }
            .frame(height: 4)
        }
    }
}

#Preview {
    ChangePasswordView(email: "nour@droob.co", otpCode: "123456")
}
