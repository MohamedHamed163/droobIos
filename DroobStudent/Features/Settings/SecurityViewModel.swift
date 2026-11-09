import Foundation

@MainActor
final class SecurityViewModel: ObservableObject {
    @Published var status: SecurityStatus? = nil
    @Published var devices: [StudentDevice] = []
    @Published var isLoading = true
    @Published var error: String? = nil

    @Published var passwordError: String? = nil
    @Published var passwordChanged = false

    // ── 2FA enrolment state, surfaced via SecurityView sheets ────────────

    /// Result of /enroll — drives the QR view. `nil` until the user taps
    /// the toggle to start enrolment.
    @Published var pendingEnrollment: TwoFactorEnrollResponse? = nil

    /// 10 plaintext codes returned by /verify. Set once after a successful
    /// verify, presented to the user, then cleared.
    @Published var recoveryCodes: [String] = []

    /// Inline error message for any of the 2FA dialogs (enrol, verify,
    /// disable, regenerate). Distinct from the screen-level `error` so the
    /// disable sheet doesn't bleed into the list view.
    @Published var twoFactorError: String? = nil
    @Published var isVerifyingTotp = false

    // ── Biometric (Face ID / Touch ID) login ────────────────────────────

    /// Mirror of {@link BiometricLoginCoordinator.isEnrolled} so the
    /// SwiftUI toggle has an observable source of truth that flips after
    /// a successful enroll/unenroll.
    @Published var biometricEnabled: Bool = BiometricLoginCoordinator.shared.isEnrolled

    /// Inline error for the biometric toggle. Shown next to the row,
    /// not at the top of the screen, so it doesn't replace the device
    /// list while a transient enrollment error is up.
    @Published var biometricError: String? = nil

    /// Capability snapshot the view reads to decide whether to render
    /// the toggle at all. `.notAvailable` hides the row entirely.
    var biometryAvailability: BiometryAvailability {
        BiometricAuthService().availability()
    }

    func enableBiometric() {
        biometricError = nil
        Task {
            do {
                try await AuthSession.shared.enrollBiometric(
                    keyLabel: nil,
                    confirmReason: L10n.securityBiometricEnrollReason)
                biometricEnabled = true
            } catch let e as DroobError {
                biometricError = e.errorDescription
                biometricEnabled = false
            } catch let e as DeviceKeyStoreError {
                // User-cancelled Face ID surfaces as a DeviceKeyStoreError
                // wrapping LAError.userCancel — don't show a banner for
                // that, just bounce the toggle back to off.
                if Self.isUserCancellation(e) {
                    biometricEnabled = false
                } else {
                    biometricError = e.errorDescription
                    biometricEnabled = false
                }
            } catch {
                biometricError = error.localizedDescription
                biometricEnabled = false
            }
        }
    }

    /// Recognises the LocalAuthentication "user cancelled" / "system
    /// cancelled" / "app cancelled" codes wrapped inside a
    /// `DeviceKeyStoreError.signingFailed`. We don't want to show a
    /// red error banner just because the user tapped Cancel.
    private static func isUserCancellation(_ error: DeviceKeyStoreError) -> Bool {
        guard case .signingFailed(let inner) = error else { return false }
        let nsError = inner as NSError
        guard nsError.domain == "com.apple.LocalAuthentication" else { return false }
        switch nsError.code {
        case -2, -4, -9: return true   // userCancel, systemCancel, appCancel
        default: return false
        }
    }

    func disableBiometric() {
        AuthSession.shared.unenrollBiometric()
        biometricEnabled = false
        biometricError = nil
    }

    func load() async {
        isLoading = true
        error = nil
        async let statusReq: SecurityStatus = AuthInterceptor.shared.execute(
            APIRequest(path: "/v1/student/settings/security"))
        async let devicesReq: [StudentDevice] = AuthInterceptor.shared.execute(
            APIRequest(path: "/v1/student/settings/devices"))
        do {
            let (s, d) = try await (statusReq, devicesReq)
            status = s
            devices = d
        } catch let e where APIClient.isCancellationError(e) {
            // Pull-to-refresh cancelled — keep existing data.
            isLoading = false
            return
        } catch let e as DroobError {
            if case .unauthenticated(_, _) = e { AuthSession.shared.handleUnauthenticated() }
            else { error = e.errorDescription }
        } catch let e {
            self.error = e.localizedDescription
        }
        isLoading = false
    }

    // MARK: - 2FA enrolment

    /// Starts enrolment by hitting `/enroll`. The response opens the QR /
    /// verify sheet via `pendingEnrollment`.
    func beginTwoFactorEnrollment() {
        twoFactorError = nil
        Task {
            do {
                let req = APIRequest(
                    path: "/v1/student/settings/security/two-factor/enroll",
                    method: .POST)
                pendingEnrollment = try await AuthInterceptor.shared.execute(req)
            } catch let e as DroobError {
                if case .unauthenticated(_, _) = e { AuthSession.shared.handleUnauthenticated() }
                else { twoFactorError = e.errorDescription }
            } catch let e {
                twoFactorError = e.localizedDescription
            }
        }
    }

    /// Verifies the 6-digit code against the pending secret and surfaces the
    /// fresh recovery codes for display.
    func verifyTwoFactor(code: String) async {
        twoFactorError = nil
        isVerifyingTotp = true
        defer { isVerifyingTotp = false }
        do {
            let req = APIRequest(
                path: "/v1/student/settings/security/two-factor/verify",
                method: .POST,
                body: TwoFactorVerifyRequest(code: code))
            let response: TwoFactorVerifyResponse = try await AuthInterceptor.shared.execute(req)
            recoveryCodes = response.recoveryCodes
            pendingEnrollment = nil
            // Refresh status so the banner flips to green.
            await load()
        } catch let e as DroobError {
            if case .unauthenticated(_, _) = e { AuthSession.shared.handleUnauthenticated() }
            else { twoFactorError = e.errorDescription }
        } catch let e {
            twoFactorError = e.localizedDescription
        }
    }

    /// Disables 2FA after re-verifying with a TOTP or recovery code.
    func disableTwoFactor(code: String) async {
        twoFactorError = nil
        isVerifyingTotp = true
        defer { isVerifyingTotp = false }
        do {
            let req = APIRequest(
                path: "/v1/student/settings/security/two-factor/disable",
                method: .POST,
                body: TwoFactorDisableRequest(code: code))
            _ = try await AuthInterceptor.shared.execute(req) as [String: Bool]
            await load()
        } catch let e as DroobError {
            if case .unauthenticated(_, _) = e { AuthSession.shared.handleUnauthenticated() }
            else { twoFactorError = e.errorDescription }
        } catch let e {
            twoFactorError = e.localizedDescription
        }
    }

    func cancelEnrollment() {
        pendingEnrollment = nil
        twoFactorError = nil
    }

    func dismissRecoveryCodes() {
        recoveryCodes = []
    }

    // MARK: - Devices

    func signOut(deviceId: String) {
        let snapshot = devices
        devices.removeAll { $0.id == deviceId }
        Task {
            do {
                let req = APIRequest(
                    path: "/v1/student/settings/devices/\(deviceId)",
                    method: .DELETE)
                _ = try await AuthInterceptor.shared.execute(req) as [String: Bool]
            } catch let e as DroobError {
                devices = snapshot
                if case .unauthenticated(_, _) = e { AuthSession.shared.handleUnauthenticated() }
                else { error = e.errorDescription }
            } catch let e {
                devices = snapshot
                self.error = e.localizedDescription
            }
        }
    }

    func signOutAllOthers() {
        let snapshot = devices
        devices = devices.filter { $0.isCurrent }
        Task {
            do {
                let req = APIRequest(
                    path: "/v1/student/settings/devices",
                    method: .DELETE)
                _ = try await AuthInterceptor.shared.execute(req) as [String: Int]
            } catch let e as DroobError {
                devices = snapshot
                if case .unauthenticated(_, _) = e { AuthSession.shared.handleUnauthenticated() }
                else { error = e.errorDescription }
            } catch let e {
                devices = snapshot
                self.error = e.localizedDescription
            }
        }
    }

    // MARK: - Change password

    func changePassword(current: String, new: String) async {
        passwordError = nil
        passwordChanged = false
        do {
            let req = APIRequest(
                path: "/v1/student/settings/security/password",
                method: .POST,
                body: ChangePasswordBody(currentPassword: current, newPassword: new))
            _ = try await AuthInterceptor.shared.execute(req) as [String: Bool]
            passwordChanged = true
            await load()
        } catch let e as DroobError {
            if case .unauthenticated(_, _) = e { AuthSession.shared.handleUnauthenticated() }
            else { passwordError = e.errorDescription }
        } catch let e {
            passwordError = e.localizedDescription
        }
    }

    func consumePasswordChanged() {
        passwordChanged = false
        passwordError = nil
    }

    // MARK: - Delete account

    /// Inline error for the delete-account confirmation sheet. Kept separate
    /// from the screen-level `error` so a failed deletion doesn't wipe the
    /// device list behind the sheet.
    @Published var deleteError: String? = nil
    @Published var isDeletingAccount = false

    /// Permanently closes the account. On success the backend has already
    /// revoked this session, so we drop straight to the sign-in screen via
    /// `handleUnauthenticated()`.
    func deleteAccount() async {
        deleteError = nil
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            let req = APIRequest(
                path: "/v1/student/settings/account/delete",
                method: .POST)
            _ = try await AuthInterceptor.shared.execute(req) as [String: Bool]
            AuthSession.shared.handleUnauthenticated()
        } catch let e as DroobError {
            deleteError = e.errorDescription
        } catch let e {
            deleteError = e.localizedDescription
        }
    }
}
