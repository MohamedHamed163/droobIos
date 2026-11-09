import Foundation

// MARK: - ProfileSettingsViewModel
//
// Drives the editable account fields on the Profile tab: the display name
// (labelled "Username" in the UI) and the email address. Display-name edits
// land immediately via PUT /profile. Email changes are two-step — request a
// verification code sent to the NEW address, then confirm it — because the
// address must be proven before it becomes the account's login identity.
//
// After either field actually changes server-side we call
// `AuthSession.shared.refreshCurrentUser()` so the cached `/auth/me` snapshot
// (and every view bound to it) reflects the new value.

@MainActor
final class ProfileSettingsViewModel: ObservableObject {
    @Published var profile: StudentProfile? = nil
    @Published var isLoading = true
    @Published var error: String? = nil

    // ── Username edit ────────────────────────────────────────────────────
    @Published var isSavingUsername = false
    @Published var usernameError: String? = nil
    @Published var usernameSaved = false

    // ── Email change ─────────────────────────────────────────────────────
    /// True once a code has been mailed to the pending new address — the UI
    /// swaps the email sheet to the code-entry step.
    @Published var emailCodeSent = false
    /// The address a pending code was sent to. Shown in the verification copy.
    @Published var pendingNewEmail: String? = nil
    @Published var isRequestingEmail = false
    @Published var isConfirmingEmail = false
    @Published var emailError: String? = nil
    @Published var emailChanged = false

    func load() async {
        isLoading = true
        error = nil
        do {
            profile = try await AuthInterceptor.shared.execute(
                APIRequest(path: "/v1/student/settings/profile"))
        } catch let e where APIClient.isCancellationError(e) {
            isLoading = false
            return
        } catch let e as DroobError {
            if case .unauthenticated(_, _) = e { AuthSession.shared.handleUnauthenticated() }
            else { error = e.errorDescription }
        } catch let e {
            error = e.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Username (display name)

    /// Saves a new display name. Returns true on success so the presenting
    /// sheet can dismiss itself.
    @discardableResult
    func saveUsername(_ raw: String) async -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        usernameError = nil
        usernameSaved = false
        guard !trimmed.isEmpty else {
            usernameError = L10n.editUsernameEmpty
            return false
        }
        isSavingUsername = true
        defer { isSavingUsername = false }
        do {
            let updated: StudentProfile = try await AuthInterceptor.shared.execute(
                APIRequest(
                    path: "/v1/student/settings/profile",
                    method: .PUT,
                    body: UpdateProfileBody(displayName: trimmed)))
            profile = updated
            usernameSaved = true
            await AuthSession.shared.refreshCurrentUser()
            return true
        } catch let e as DroobError {
            if case .unauthenticated(_, _) = e { AuthSession.shared.handleUnauthenticated() }
            else { usernameError = e.errorDescription }
            return false
        } catch let e {
            usernameError = e.localizedDescription
            return false
        }
    }

    // MARK: - Email change

    /// Step 1 — mails a 6-digit verification code to the new address. On
    /// success flips `emailCodeSent` so the sheet advances to code entry.
    func requestEmailChange(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        emailError = nil
        isRequestingEmail = true
        defer { isRequestingEmail = false }
        do {
            _ = try await AuthInterceptor.shared.execute(
                APIRequest(
                    path: "/v1/student/settings/email/change",
                    method: .POST,
                    body: RequestEmailChangeBody(newEmail: trimmed))) as [String: Bool]
            pendingNewEmail = trimmed
            emailCodeSent = true
        } catch let e as DroobError {
            handleEmailFlow(error: e)
        } catch let e {
            emailError = e.localizedDescription
        }
    }

    /// Step 2 — confirms the code; on success the account email is updated.
    /// Returns true so the sheet can dismiss.
    @discardableResult
    func confirmEmailChange(code: String) async -> Bool {
        emailError = nil
        isConfirmingEmail = true
        defer { isConfirmingEmail = false }
        do {
            _ = try await AuthInterceptor.shared.execute(
                APIRequest(
                    path: "/v1/student/settings/email/change/confirm",
                    method: .POST,
                    body: ConfirmEmailChangeBody(code: code))) as [String: String]
            emailChanged = true
            await load()
            await AuthSession.shared.refreshCurrentUser()
            return true
        } catch let e as DroobError {
            handleEmailFlow(error: e)
            return false
        } catch let e {
            emailError = e.localizedDescription
            return false
        }
    }

    /// Classifies a `DroobError` from the two-step email-change flow.
    ///
    /// The backend reports a wrong or expired OTP as **401 UNAUTHENTICATED**
    /// with a problem-detail message ("Invalid confirmation code"), i.e. the
    /// *same* status a dead session uses. We must not conflate the two: a 401
    /// that carries a server message is a domain rejection — show it and let
    /// the user retry. Only a *bare* `.unauthenticated(nil, nil)` (a stale
    /// token whose refresh failed upstream in `AuthInterceptor`) is a real
    /// session expiry that should sign the user out.
    private func handleEmailFlow(error e: DroobError) {
        if case .unauthenticated(let msg, _) = e, msg == nil {
            AuthSession.shared.handleUnauthenticated()
        } else {
            emailError = e.errorDescription
        }
    }

    /// Resets the email-change sub-flow so a re-opened sheet starts clean.
    func resetEmailFlow() {
        emailCodeSent = false
        pendingNewEmail = nil
        emailError = nil
        emailChanged = false
    }
}
