import Foundation

// MARK: - SessionEndNotice
// One-shot reason for the app dropping back to the sign-in screen.
//
// A failed token refresh signs the user out silently — they just find
// themselves on the login screen with no explanation. That's tolerable for an
// expired session, but not when the reason is the one-device pin: the student
// needs to be told the account is held by another device, otherwise they'll
// retype a password that was never wrong.
//
// Written from the networking layer (any thread) and read once by the login
// screen, so it's guarded by a lock rather than actor-isolated.

enum SessionEndReason {
    /// Refresh was refused because the account is pinned to another device.
    case deviceNotAuthorized

    /// Resolved at read time so it follows the app's current language.
    var message: String {
        switch self {
        case .deviceNotAuthorized: return L10n.loginErrDeviceNotAuthorized
        }
    }
}

enum SessionEndNotice {
    private static let lock = NSLock()
    private static var pending: SessionEndReason?

    static func record(_ reason: SessionEndReason) {
        lock.lock()
        defer { lock.unlock() }
        pending = reason
    }

    /// Returns the pending reason and clears it, so the banner shows once
    /// rather than on every later visit to the login screen.
    static func consume() -> SessionEndReason? {
        lock.lock()
        defer { lock.unlock() }
        let reason = pending
        pending = nil
        return reason
    }
}
