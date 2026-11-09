import SwiftUI

/// Confirmation sheet shown when the user toggles 2FA **off**. Requires
/// re-presenting either a current TOTP code or one of the recovery codes,
/// so a stolen session can't quietly disable the second factor.
struct TwoFactorDisableSheet: View {
    let isVerifying: Bool
    let error: String?
    let onCancel: () -> Void
    let onConfirm: (String) async -> Void

    @State private var code: String = ""
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        (Text(L10n.twoFaDisableLine1).font(.system(size: 22, weight: .bold)).foregroundColor(MyCoursesPalette.textPrimary)
                        + Text(L10n.twoFaTitle)
                            .font(.system(size: 22, weight: .bold))
                            // Gold as ink on the page background — the ramp.
                            .foregroundColor(MyCoursesPalette.accent))
                        Text(L10n.twoFaDisableSubtitle)
                            .font(.system(size: 13))
                            .foregroundColor(MyCoursesPalette.muted)
                            .lineSpacing(2)
                    }

                    TextField("123 456", text: $code)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($codeFocused)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(MyCoursesPalette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(MyCoursesPalette.stroke, lineWidth: 1))

                    if let error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(MyCoursesPalette.danger)
                    }

                    Spacer()

                    Button {
                        Task { await onConfirm(code) }
                    } label: {
                        HStack {
                            Spacer()
                            if isVerifying {
                                ProgressView().tint(.white)
                            } else {
                                Text(L10n.twoFaDisableAction)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .frame(height: 52)
                        // Opaque, matching `DeleteAccountSheet`: at 85% the red
                        // composited against the now-white sheet to a pale
                        // #FF584F and the white label fell under 3:1. Disabled
                        // dimming moves off the fill and onto the whole pill so
                        // plate and label fade together, instead of the plate
                        // alone washing out from under white text.
                        .background(Color.red)
                        .clipShape(Capsule())
                        .opacity(code.isEmpty ? 0.5 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .disabled(code.isEmpty || isVerifying)
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.cancel, action: onCancel)
                        .foregroundColor(MyCoursesPalette.muted)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .onAppear { codeFocused = true }
    }
}
