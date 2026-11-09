import Foundation
import LocalAuthentication

// MARK: - BiometryAvailability

/// Capability snapshot used by the UI to decide whether to render the
/// Face ID button on the login screen and the toggle in Settings.
enum BiometryAvailability: Equatable {
    case available(BiometryType)
    case notEnrolled        // hardware present, user hasn't set up Face/Touch ID
    case notAvailable       // hardware not present (older iPad, etc.)
    case lockedOut          // too many failed attempts
}

enum BiometryType: String {
    case faceID  = "face_id"
    case touchID = "touch_id"
    case opticID = "optic_id"
}

// MARK: - BiometricAuthService

/// Thin wrapper around `LAContext` that exposes only the operations the
/// app needs and keeps the LocalAuthentication API surface out of the
/// view models. Stateless — a new `LAContext` is used per evaluation so
/// the auth result can't be cached longer than the system allows.
final class BiometricAuthService {

    private let contextFactory: () -> LAContext

    /// `contextFactory` is injected so tests can hand in a fake
    /// `LAContext` subclass without touching real biometrics.
    init(contextFactory: @escaping () -> LAContext = { LAContext() }) {
        self.contextFactory = contextFactory
    }

    /// What kind of biometry, if any, the device supports today.
    ///
    /// Uses `.deviceOwnerAuthentication` (Face ID / Touch ID with
    /// passcode fallback) for the capability check too — matching the
    /// policy we'll actually evaluate at sign time. If we instead asked
    /// about `.deviceOwnerAuthenticationWithBiometrics`, a user without
    /// enrolled biometry would get `notEnrolled` even though
    /// passcode-fallback would still work.
    func availability() -> BiometryAvailability {
        let context = contextFactory()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(
            .deviceOwnerAuthentication, error: &error)

        if canEvaluate {
            switch context.biometryType {
            case .faceID:  return .available(.faceID)
            case .touchID: return .available(.touchID)
            case .opticID: return .available(.opticID)
            case .none:    return .notAvailable
            @unknown default: return .notAvailable
            }
        }

        guard let laError = error as? LAError else { return .notAvailable }
        switch laError.code {
        case .biometryNotEnrolled: return .notEnrolled
        case .biometryLockout:     return .lockedOut
        case .biometryNotAvailable: return .notAvailable
        default: return .notAvailable
        }
    }
}
