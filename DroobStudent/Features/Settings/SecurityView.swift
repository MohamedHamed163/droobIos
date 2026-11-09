import SwiftUI

struct SecurityView: View {
    @StateObject private var vm = SecurityViewModel()
    @State private var showChangePassword = false
    @State private var twoFactorBinding = false
    @State private var showDisableSheet = false
    @State private var showDeleteSheet = false

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    SettingsScreenHeader(title: L10n.securityScreenTitle)
                        .padding(.top, 4)

                    if vm.isLoading && vm.status == nil {
                        skeleton
                    } else if let status = vm.status {
                        AccountSecuredBanner(status: status)
                        passwordAndTwoFactorCard(status: status)
                        activeDevicesSection
                        DeviceLimitCard(limit: status.deviceLimit)
                        dangerZoneSection
                    } else if let err = vm.error {
                        ErrorBanner(message: err) { Task { await vm.load() } }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.load() }
        .onChange(of: vm.status?.twoFactorEnabled) { newValue in
            if let v = newValue, v != twoFactorBinding { twoFactorBinding = v }
        }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet(
                error: vm.passwordError,
                onSave: { current, new in
                    Task {
                        await vm.changePassword(current: current, new: new)
                        if vm.passwordChanged { showChangePassword = false }
                    }
                })
        }
        // 2FA enrolment sheet — opens when /enroll has populated pendingEnrollment.
        .sheet(item: Binding(
            get: { vm.pendingEnrollment.map { EnrollmentBox(value: $0) } },
            set: { _ in vm.cancelEnrollment() })
        ) { box in
            TwoFactorEnrollmentView(
                enrollment: box.value,
                onCancel: vm.cancelEnrollment,
                onVerified: { code in await vm.verifyTwoFactor(code: code) },
                error: vm.twoFactorError,
                isVerifying: vm.isVerifyingTotp)
        }
        // Recovery codes sheet — shown right after a successful /verify.
        .sheet(isPresented: Binding(
            get: { !vm.recoveryCodes.isEmpty },
            set: { if !$0 { vm.dismissRecoveryCodes() } })
        ) {
            RecoveryCodesView(codes: vm.recoveryCodes, onDone: vm.dismissRecoveryCodes)
        }
        // Disable confirmation — keeps the toggle from quietly killing 2FA.
        .sheet(isPresented: $showDisableSheet) {
            TwoFactorDisableSheet(
                isVerifying: vm.isVerifyingTotp,
                error: vm.twoFactorError,
                onCancel: { showDisableSheet = false; vm.cancelEnrollment() },
                onConfirm: { code in
                    await vm.disableTwoFactor(code: code)
                    if vm.status?.twoFactorEnabled == false { showDisableSheet = false }
                })
        }
        // Account closure — irreversible, so gated behind an explicit
        // confirmation sheet with an acknowledgement toggle.
        .sheet(isPresented: $showDeleteSheet, onDismiss: { vm.deleteError = nil }) {
            DeleteAccountSheet(
                error: vm.deleteError,
                isDeleting: vm.isDeletingAccount,
                onCancel: { showDeleteSheet = false },
                onConfirm: { await vm.deleteAccount() })
        }
    }

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // `Color.red.opacity(0.9)` is systemRed thinned for a dark page; on
            // the light page it composites to ~#FF564C and drops to ~3:1 as
            // ink. The `danger` ramp is the same signal tuned per theme.
            Text(L10n.securityDangerZone)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(MyCoursesPalette.danger)

            Button(action: { showDeleteSheet = true }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(MyCoursesPalette.danger.opacity(0.18))
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.danger)
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.securityDeleteAccountRow)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.danger)
                        Text(L10n.securityDeleteAccountSubtitle)
                            .font(.system(size: 11))
                            .foregroundColor(MyCoursesPalette.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.muted)
                }
                .padding(14)
                .background(MyCoursesPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MyCoursesPalette.danger.opacity(0.35), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// `Identifiable` shim so we can drive a `.sheet(item:)` off the
    /// optional enrollment payload.
    private struct EnrollmentBox: Identifiable {
        let value: TwoFactorEnrollResponse
        var id: String { value.secretBase32 }
    }

    // MARK: - Sections

    private func passwordAndTwoFactorCard(status: SecurityStatus) -> some View {
        SettingsCard {
            ChangePasswordRow(
                lastChangedAt: status.passwordChangedAt,
                onTap: { showChangePassword = true })
            SettingsRowDivider()
            // The toggle no longer flips a flag directly. ON kicks off the
            // enrolment sheet; OFF opens the disable confirmation sheet
            // — both controlled by the view model. We use a derived
            // binding so SwiftUI doesn't treat the optimistic flip as the
            // source of truth.
            SettingsToggleRow(
                icon: "lock.shield.fill",
                iconBg: status.twoFactorEnabled
                    ? MyCoursesPalette.success.opacity(0.18)
                    : MyCoursesPalette.surfaceRaised,
                iconTint: status.twoFactorEnabled
                    ? MyCoursesPalette.success
                    : MyCoursesPalette.muted,
                title: L10n.securityTwoFactorRow,
                subtitle: status.twoFactorEnabled
                    ? L10n.securityTwoFactorEnabledVia
                    : L10n.securityTwoFactorDisabled,
                isOn: Binding(
                    get: { vm.status?.twoFactorEnabled ?? false },
                    set: { newValue in
                        if newValue {
                            vm.beginTwoFactorEnrollment()
                        } else {
                            showDisableSheet = true
                        }
                    }),
                onChange: { _ in })

            // Biometric login toggle. Hidden when the device has no
            // biometry hardware at all — `.notEnrolled` and `.lockedOut`
            // are still surfaced so the user knows to enable it in
            // Settings → Face ID & Passcode.
            if case .notAvailable = vm.biometryAvailability {
                EmptyView()
            } else {
                SettingsRowDivider()
                SettingsToggleRow(
                    icon: "faceid",
                    iconBg: vm.biometricEnabled
                        ? MyCoursesPalette.success.opacity(0.18)
                        : MyCoursesPalette.surfaceRaised,
                    iconTint: vm.biometricEnabled
                        ? MyCoursesPalette.success
                        : MyCoursesPalette.muted,
                    title: L10n.securityBiometricRow,
                    subtitle: vm.biometricEnabled
                        ? L10n.securityBiometricEnabled
                        : (vm.biometricError ?? L10n.securityBiometricDisabled),
                    isOn: Binding(
                        get: { vm.biometricEnabled },
                        set: { newValue in
                            if newValue { vm.enableBiometric() }
                            else { vm.disableBiometric() }
                        }),
                    onChange: { _ in })
            }
        }
    }

    private var activeDevicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.securityActiveDevices)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Spacer()
                if vm.devices.contains(where: { !$0.isCurrent }) {
                    Button(action: vm.signOutAllOthers) {
                        Text(L10n.securitySignOutAll)
                            .font(.system(size: 13))
                            .foregroundColor(MyCoursesPalette.danger)
                    }
                }
            }
            ForEach(vm.devices) { device in
                DeviceRow(device: device, onSignOut: { vm.signOut(deviceId: device.id) })
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: 16) {
            MCSkeletonBlock(height: 80, cornerRadius: 14)
            MCSkeletonBlock(height: 140, cornerRadius: 14)
            MCSkeletonBlock(height: 70, cornerRadius: 14)
            MCSkeletonBlock(height: 70, cornerRadius: 14)
            MCSkeletonBlock(height: 70, cornerRadius: 14)
        }
    }
}

// MARK: - Account Secured banner

private struct AccountSecuredBanner: View {
    let status: SecurityStatus

    private var secured: Bool { status.twoFactorEnabled }
    /// Drives the icon tile and the hairline only (the copy is neutral ink).
    /// The unsecured state was a fixed amber #FF9E40 tuned for near-black —
    /// ~1.5:1 on the light plate. `danger` is the adaptive ramp for exactly
    /// this "your account needs attention" signal and stays distinct from the
    /// green secured state in both themes.
    private var tint: Color {
        secured ? MyCoursesPalette.success : MyCoursesPalette.danger
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.18))
                Image(systemName: secured ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 22))
                    .foregroundColor(tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                // Copy is neutral ink, not the tint. Both tints were picked to
                // glow on near-black; on the light plate #2BB66D lands at
                // ~2.5:1 and the amber at ~2.0:1, so the banner's headline was
                // the least readable text on the screen. The status still reads
                // as green/amber through the icon tile and the hairline.
                Text(L10n.securityAccountSecured)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(secured ? L10n.securitySecuredSubtitle
                             : L10n.securityNotSecuredSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        // Opaque plate: a 10% tint wash composites against the page, so in
        // light mode the banner was all but white and lost its card shape.
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Change-password row

private struct ChangePasswordRow: View {
    let lastChangedAt: Date?
    let onTap: () -> Void

    private var lastChangedLabel: String {
        guard let date = lastChangedAt else { return L10n.securityLastChangedNever }
        let f = RelativeDateTimeFormatter()
        // Pinned, or the relative phrase follows the DEVICE while the prefix
        // beside it comes from L10n — one label, two languages.
        f.locale = Locale(identifier: L10n.currentLanguageCode)
        f.unitsStyle = .full
        return L10n.securityLastChangedPrefix + f.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MyCoursesPalette.danger.opacity(0.18))
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.danger)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.securityChangePassword)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                    Text(lastChangedLabel)
                        .font(.system(size: 11))
                        .foregroundColor(MyCoursesPalette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Device row

private struct DeviceRow: View {
    let device: StudentDevice
    let onSignOut: () -> Void

    private var icon: String {
        let lower = device.label.lowercased()
        if lower.contains("mac") || lower.contains("pc") { return "laptopcomputer" }
        return "iphone"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                // Nested, not raised: the current-device row's own plate is
                // `surfaceRaised`, so a `surfaceRaised` tile on top of it
                // flattened to a single colour and the tile lost its shape
                // behind the glyph. `surfaceNested` sits above both plates.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MyCoursesPalette.surfaceNested)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                // `bidiJoin` also drops the nil location, which used to
                // leave the row starting with a bare " · ".
                Text(bidiJoin(device.location, device.activityDescription))
                    .font(.system(size: 11))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            Spacer(minLength: 0)

            if device.isCurrent {
                Text(L10n.securityCurrentDevice)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.success)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(MyCoursesPalette.success.opacity(0.18))
                    .clipShape(Capsule())
            } else {
                Button(action: onSignOut) {
                    Text(L10n.securitySignOut)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.danger)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        // Opaque subtle-danger chip. The 15% red wash went pale
                        // pink on the cream row and left the label at ~2.9:1.
                        .background(MyCoursesPalette.dangerSubtle)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        // The current device is marked by a warmer, raised plate plus a gold
        // hairline. A 10% gold wash used to supply that plate, but it
        // composites against the page — on the light page it landed lighter
        // than `surface`, so the highlighted row read as the flattest one.
        .background(
            device.isCurrent
            ? MyCoursesPalette.surfaceRaised
            : MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(device.isCurrent
                    ? MyCoursesPalette.accent.opacity(0.45)
                    : MyCoursesPalette.stroke,
                    lineWidth: 1))
    }
}

// MARK: - Device limit warning

private struct DeviceLimitCard: View {
    let limit: Int
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Amber #FF9E40 is a dark-mode glow; on the cream plate it lands at
            // ~1.5:1, well under the 3:1 graphics floor. Joins the card's gold
            // ink voice (below) rather than becoming a lone adaptive tint.
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(MyCoursesPalette.accent)
            VStack(alignment: .leading, spacing: 2) {
                // Both copy lines were dark-mode-only warm tints (amber /
                // #D9BC88) and dropped to ~2:1 once the plate went cream, so
                // the card now carries a single gold ink voice under the
                // amber warning glyph.
                Text(L10n.securityDeviceLimitTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
                Text(String(format: L10n.securityDeviceLimitMessage, limit))
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        // Opaque plate: a 10% gold wash over the light page is white, which
        // left the card shapeless (dark mode is unchanged — 10% gold over
        // near-black is what `surfaceRaised` already resolves to).
        .background(MyCoursesPalette.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyCoursesPalette.accent.opacity(0.30), lineWidth: 1))
    }
}

// MARK: - Change password sheet

private struct ChangePasswordSheet: View {
    let error: String?
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var current: String = ""
    @State private var newPwd: String = ""
    @State private var confirmPwd: String = ""
    @State private var revealCurrent = false
    @State private var revealNew = false
    @State private var revealConfirm = false

    /// New-password contains a digit, symbol, or punctuation — same rule
    /// the signup / reset flows enforce (see ChangePasswordViewModel).
    private var hasDigitOrSymbol: Bool {
        newPwd.rangeOfCharacter(from: .decimalDigits) != nil
            || newPwd.rangeOfCharacter(from: .symbols) != nil
            || newPwd.rangeOfCharacter(from: .punctuationCharacters) != nil
    }

    /// Mirrors `ChangePasswordViewModel.validationError`: min 8 chars, a
    /// number or symbol, and a matching confirmation. `nil` once the new
    /// password is valid and confirmed.
    private var validationError: String? {
        if newPwd.count < 8 { return L10n.securityPasswordTooShort }
        if !hasDigitOrSymbol { return L10n.securityPasswordNeedsNumberOrSymbol }
        if newPwd != confirmPwd { return L10n.securityPasswordsDontMatch }
        return nil
    }

    private var canSave: Bool {
        !current.isEmpty && validationError == nil
    }

    /// Server error takes precedence; otherwise surface the mismatch only
    /// once the user has actually started typing a confirmation, so the
    /// banner doesn't flash while they're still filling the new field.
    private var displayedError: String? {
        if let error { return error }
        if !confirmPwd.isEmpty && newPwd != confirmPwd {
            return L10n.securityPasswordsDontMatch
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.securityChangePassword)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.textPrimary)

                        field(L10n.securityCurrentPassword, text: $current,
                              revealed: $revealCurrent)
                        field(L10n.securityNewPassword, text: $newPwd,
                              revealed: $revealNew)
                        field(L10n.securityConfirmPassword, text: $confirmPwd,
                              revealed: $revealConfirm)

                        if !newPwd.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                requirementRow(L10n.securityPasswordReqLength,
                                               met: newPwd.count >= 8)
                                requirementRow(L10n.securityPasswordReqNumber,
                                               met: hasDigitOrSymbol)
                            }
                        }

                        if let displayedError {
                            Text(displayedError)
                                .font(.system(size: 12))
                                .foregroundColor(MyCoursesPalette.danger)
                        }

                        Button {
                            onSave(current, newPwd)
                        } label: {
                            Text(L10n.save)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(LinearGradient.droobBrand)
                                .clipShape(Capsule())
                        }
                        .disabled(!canSave)
                        .opacity(canSave ? 1.0 : 0.5)
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.cancel) { dismiss() }
                        .foregroundColor(MyCoursesPalette.muted)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func requirementRow(_ text: String, met: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundColor(met ? MyCoursesPalette.success : MyCoursesPalette.muted)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(met ? MyCoursesPalette.textPrimary : MyCoursesPalette.muted)
        }
    }

    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>,
                       revealed: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Group {
                if revealed.wrappedValue {
                    TextField("", text: text)
                } else {
                    SecureField("", text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .foregroundColor(MyCoursesPalette.textPrimary)
            .overlay(alignment: .leading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .foregroundColor(MyCoursesPalette.muted)
                        .allowsHitTesting(false)
                }
            }

            Button {
                revealed.wrappedValue.toggle()
            } label: {
                Image(systemName: revealed.wrappedValue ? "eye.slash" : "eye")
                    .font(.system(size: 16))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }
}

// MARK: - Delete account sheet

/// Irreversible account closure. We don't ask for the password here — OTP /
/// social signups have placeholder hashes and would otherwise be locked out
/// — so the destructive button is gated behind an explicit acknowledgement
/// toggle instead.
private struct DeleteAccountSheet: View {
    let error: String?
    let isDeleting: Bool
    let onCancel: () -> Void
    let onConfirm: () async -> Void

    @State private var acknowledged = false

    var body: some View {
        NavigationStack {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(MyCoursesPalette.danger.opacity(0.18))
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(MyCoursesPalette.danger)
                            }
                            .frame(width: 48, height: 48)
                            Text(L10n.securityDeleteAccountTitle)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(MyCoursesPalette.textPrimary)
                        }

                        Text(L10n.securityDeleteAccountWarning)
                            .font(.system(size: 14))
                            .foregroundColor(MyCoursesPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: { acknowledged.toggle() }) {
                            HStack(spacing: 10) {
                                Image(systemName: acknowledged
                                      ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 20))
                                    .foregroundColor(acknowledged
                                        ? MyCoursesPalette.danger : MyCoursesPalette.muted)
                                Text(L10n.securityDeleteAccountAcknowledge)
                                    .font(.system(size: 13))
                                    .foregroundColor(MyCoursesPalette.textPrimary)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if let error {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(MyCoursesPalette.danger)
                        }

                        Button {
                            Task { await onConfirm() }
                        } label: {
                            HStack(spacing: 8) {
                                if isDeleting {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                }
                                Text(L10n.securityDeleteAccountConfirm)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            // Opaque: at 90% the red composited against the
                            // now-white sheet and the white label fell to
                            // ~3.1:1. The disabled state is already handled
                            // by the `.opacity` below.
                            .background(Color.red)
                            .clipShape(Capsule())
                        }
                        .disabled(!acknowledged || isDeleting)
                        .opacity((!acknowledged || isDeleting) ? 0.5 : 1.0)
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.cancel) { onCancel() }
                        .foregroundColor(MyCoursesPalette.muted)
                        .disabled(isDeleting)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
