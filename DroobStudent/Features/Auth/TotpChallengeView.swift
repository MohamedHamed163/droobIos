import SwiftUI

/// Second leg of a 2FA login. The login screen pushes this when the
/// backend returns `challenge: "totp_required"`; on success the session
/// flips to authenticated and the navigation stack unwinds to the
/// authenticated tab view.
@MainActor
final class TotpChallengeViewModel: ObservableObject {
    @Published var code: String = ""
    @Published var isLoading = false
    @Published var error: String? = nil
    /// Set to true once /v1/auth/totp succeeds. The view dismisses itself
    /// off this so we don't leak the TOTP screen into authenticated state.
    @Published var didAuthenticate = false

    /// Toggles the input mode between numeric (TOTP) and alphanumeric
    /// (recovery code). Recovery codes are 11 chars `xxxxx-xxxxx`.
    @Published var useRecoveryCode = false

    private let challengeToken: String
    private let session = AuthSession.shared

    init(challengeToken: String) {
        self.challengeToken = challengeToken
    }

    func submit() async {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        error = nil
        do {
            try await session.completeTotpChallenge(challengeToken: challengeToken, code: trimmed)
            didAuthenticate = true
        } catch let e as DroobError {
            self.error = e.errorDescription
        } catch let e {
            self.error = e.localizedDescription
        }
        isLoading = false
    }
}

struct TotpChallengeView: View {
    @StateObject private var vm: TotpChallengeViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    init(challengeToken: String) {
        _vm = StateObject(wrappedValue: TotpChallengeViewModel(challengeToken: challengeToken))
    }

    var body: some View {
        let p = AuthPalette.resolve(colorScheme)
        ZStack(alignment: .top) {
            AuthBackground(palette: p)
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 56)

                    // Back to the previous screen (Sign In, or the email-OTP
                    // step on the passwordless path). Without this the user is
                    // stranded on the 2FA challenge with no way to cancel.
                    HStack {
                        AuthBackLink(label: L10n.otpBack) {
                            fieldFocused = false
                            dismiss()
                        }
                        Spacer()
                    }
                    .padding(.bottom, 22)

                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.droobGold.opacity(0.18))
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(Color.droobGold)
                        }
                        .frame(width: 64, height: 64)
                        .padding(.bottom, 8)

                        (Text(L10n.totpTitleLine1).font(.system(size: 26, weight: .bold)).foregroundColor(p.text)
                        + Text(L10n.totpTitleLine2)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(p.gold))
                        Text(vm.useRecoveryCode
                             ? L10n.recoverySubtitle
                             : L10n.totpSubtitle)
                            .font(.system(size: 13))
                            .foregroundColor(p.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 24)

                    if let error = vm.error {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 13, weight: .semibold))
                            Text(error)
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .foregroundColor(.red)
                        .padding(12)
                        .background(Color.red.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.bottom, 14)
                    }

                    TextField(vm.useRecoveryCode ? "abcde-12345" : "123 456", text: $vm.code)
                        .keyboardType(vm.useRecoveryCode ? .asciiCapable : .numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(vm.useRecoveryCode ? nil : .oneTimeCode)
                        .focused($fieldFocused)
                        // iOS only reads `keyboardType` when the keyboard is
                        // (re)presented; changing it on a field that's already
                        // first responder is ignored. Tying the field identity
                        // to the mode forces a fresh field — and thus a fresh
                        // keyboard of the correct type — whenever we toggle.
                        .id(vm.useRecoveryCode)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundColor(p.text)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 16)
                        .background(p.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(p.line, lineWidth: 1))
                        .onChange(of: vm.code) { newValue in
                            if !vm.useRecoveryCode {
                                let filtered = String(newValue.filter(\.isNumber).prefix(6))
                                if filtered != newValue { vm.code = filtered }
                            }
                        }
                        .padding(.bottom, 18)

                    Button {
                        Task { await vm.submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if vm.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(
                                        tint: Color(red: 0.08, green: 0.06, blue: 0.04)))
                            } else {
                                Text(L10n.totpVerifySignIn)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                            }
                            Spacer()
                        }
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.878, green: 0.769, blue: 0.561),
                                    Color(red: 0.776, green: 0.663, blue: 0.420)],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                            .opacity(canSubmit ? 1.0 : 0.55))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .padding(.bottom, 14)

                    Button {
                        vm.useRecoveryCode.toggle()
                        vm.code = ""
                        // The field above is recreated on this toggle (its
                        // `.id` changes), which dismisses the keyboard. Re-focus
                        // on the next runloop so the new field comes up with the
                        // correct keyboard for the selected mode.
                        DispatchQueue.main.async { fieldFocused = true }
                    } label: {
                        Text(vm.useRecoveryCode
                             ? L10n.totpUseAuthenticator
                             : L10n.totpUseRecovery)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(p.gold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)

                    Color.clear.frame(height: 36)
                }
                .padding(.horizontal, 22)
            }
            .scrollDismissesKeyboard(.never)
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { fieldFocused = true }
    }

    private var canSubmit: Bool {
        !vm.isLoading && (vm.useRecoveryCode ? !vm.code.isEmpty : vm.code.count == 6)
    }
}
