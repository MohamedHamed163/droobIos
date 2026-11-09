import SwiftUI

// MARK: - Edit Username sheet
//
// Presented from the Profile tab's "Username" row. Single-field editor that
// writes the display name through ProfileSettingsViewModel.saveUsername.

struct EditUsernameSheet: View {
    @ObservedObject var vm: ProfileSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String

    init(vm: ProfileSettingsViewModel) {
        self.vm = vm
        _draft = State(initialValue: vm.profile?.displayName ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionLabel(text: L10n.editUsernameSectionLabel)
                    SettingsCard {
                        TextField(L10n.editUsernamePlaceholder, text: $draft)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .foregroundColor(MyCoursesPalette.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                    }
                    if let err = vm.usernameError {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(MyCoursesPalette.danger)
                            .padding(.leading, 4)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle(L10n.editUsernameTitle)
            .navigationBarTitleDisplayMode(.inline)
            // Every `.tint` below is toolbar ink on the sheet's own navigation
            // chrome, which is light in light mode — #C6A96B sits on it at
            // ~2.1:1, so the Cancel/Save buttons read as disabled. The accent
            // ramp is unchanged in dark.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                        .tint(MyCoursesPalette.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSavingUsername {
                        ProgressView().tint(MyCoursesPalette.accent)
                    } else {
                        Button(L10n.editSave) {
                            Task { if await vm.saveUsername(draft) { dismiss() } }
                        }
                        .tint(MyCoursesPalette.accent)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}

// MARK: - Edit Email sheet (two-step: request → verify)
//
// Step 1 collects a new address and mails a 6-digit code to it. Step 2 takes
// the code; only on confirmation does the account email actually change. The
// current address stays the login identity until then.

struct EditEmailSheet: View {
    @ObservedObject var vm: ProfileSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newEmail: String = ""
    @State private var code: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                if vm.emailCodeSent {
                    verifyStep
                } else {
                    requestStep
                }
            }
            .navigationTitle(L10n.editEmailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .onDisappear { vm.resetEmailFlow() }
    }

    // ── Step 1: enter new address ────────────────────────────────────────

    private var requestStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsSectionLabel(text: L10n.editEmailCurrentLabel)
                SettingsCard {
                    HStack {
                        Text(L10n.editEmailCurrentRow)
                            .foregroundColor(MyCoursesPalette.textPrimary)
                        Spacer()
                        Text(vm.profile?.email ?? "—")
                            .foregroundColor(MyCoursesPalette.muted)
                    }
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                SettingsSectionLabel(text: L10n.editEmailNewLabel)
                SettingsCard {
                    TextField(L10n.editEmailNewPlaceholder, text: $newEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }
                Text(L10n.editEmailHelper)
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.muted)
                    .padding(.leading, 4)
                if let err = vm.emailError {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(MyCoursesPalette.danger)
                        .padding(.leading, 4)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // ── Step 2: enter the code we mailed ─────────────────────────────────

    private var verifyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: L10n.editEmailCodeSentFmt, vm.pendingNewEmail ?? ""))
                .font(.system(size: 13))
                .foregroundColor(MyCoursesPalette.muted)
                .padding(.leading, 4)
            SettingsSectionLabel(text: L10n.editEmailCodeLabel)
            SettingsCard {
                TextField(L10n.editEmailCodePlaceholder, text: $code)
                    .keyboardType(.numberPad)
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .onChange(of: code) { newVal in
                        code = String(newVal.filter(\.isNumber).prefix(6))
                    }
            }
            if let err = vm.emailError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.danger)
                    .padding(.leading, 4)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    /// Toolbar ink on the sheet's light navigation chrome — accent ramp, not
    /// the fill gold. See `EditUsernameSheet` for the contrast note.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.cancel) { dismiss() }
                .tint(MyCoursesPalette.accent)
        }
        ToolbarItem(placement: .confirmationAction) {
            if vm.isRequestingEmail || vm.isConfirmingEmail {
                ProgressView().tint(MyCoursesPalette.accent)
            } else if vm.emailCodeSent {
                Button(L10n.editEmailVerify) {
                    Task { if await vm.confirmEmailChange(code: code) { dismiss() } }
                }
                .tint(MyCoursesPalette.accent)
                .disabled(code.count < 6)
            } else {
                Button(L10n.editSave) {
                    Task { await vm.requestEmailChange(newEmail) }
                }
                .tint(MyCoursesPalette.accent)
                .disabled(newEmail.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
