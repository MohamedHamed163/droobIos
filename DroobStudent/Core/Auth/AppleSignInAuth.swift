import AuthenticationServices
import Foundation
import UIKit

enum AppleSignInError: LocalizedError {
    case missingIDToken
    case unexpectedCredentialType
    case canceled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingIDToken: return "Apple did not return an ID token."
        case .unexpectedCredentialType: return "Unexpected credential type from Apple."
        case .canceled: return "Apple sign-in canceled."
        case .failed(let msg): return msg
        }
    }
}

struct AppleSignInResult {
    let idToken: String
    let fullName: String?
}

@MainActor
enum AppleSignInAuth {
    static func presentAndFetch() async throws -> AppleSignInResult {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = AppleSignInDelegate(continuation: continuation)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            // Retain delegate until completion via association.
            objc_setAssociatedObject(controller, &AppleSignInDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
            controller.performRequests()
        }
    }
}

private var AppleSignInDelegateKey: UInt8 = 0

@MainActor
private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?

    init(continuation: CheckedContinuation<AppleSignInResult, Error>) {
        self.continuation = continuation
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                resume(throwing: AppleSignInError.unexpectedCredentialType)
                return
            }
            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                resume(throwing: AppleSignInError.missingIDToken)
                return
            }
            let fullName: String? = {
                guard let name = credential.fullName else { return nil }
                let parts = [name.givenName, name.familyName].compactMap { $0 }
                let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                return joined.isEmpty ? nil : joined
            }()
            resume(returning: AppleSignInResult(idToken: idToken, fullName: fullName))
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            let ns = error as NSError
            // .canceled = explicit Cancel tap. .unknown = sheet dismissed
            // (swipe / tap outside / no iCloud account on simulator) — UX-wise
            // these are also "user backed out", not real failures.
            let isCancel = ns.domain == ASAuthorizationError.errorDomain
                && (ns.code == ASAuthorizationError.canceled.rawValue
                    || ns.code == ASAuthorizationError.unknown.rawValue)
            if isCancel {
                resume(throwing: AppleSignInError.canceled)
            } else {
                resume(throwing: AppleSignInError.failed(error.localizedDescription))
            }
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            return scene?.windows.first(where: { $0.isKeyWindow })
                ?? scene?.windows.first
                ?? ASPresentationAnchor()
        }
    }

    private func resume(returning value: AppleSignInResult) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    private func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
