import Foundation
import UIKit
import GoogleSignIn

enum GoogleSignInError: LocalizedError {
    case noPresenter
    case missingIDToken
    case canceled

    var errorDescription: String? {
        switch self {
        case .noPresenter: return "Could not present Google sign-in."
        case .missingIDToken: return "Google did not return an ID token."
        case .canceled: return nil
        }
    }
}

@MainActor
enum GoogleSignInAuth {
    /// Presents the Google sign-in flow and returns the verified ID token.
    static func presentAndFetchIDToken() async throws -> String {
        guard let presenter = topViewController() else {
            throw GoogleSignInError.noPresenter
        }
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch {
            let ns = error as NSError
            if ns.domain == kGIDSignInErrorDomain,
               ns.code == GIDSignInError.canceled.rawValue {
                throw GoogleSignInError.canceled
            }
            throw error
        }
        guard let idToken = result.user.idToken?.tokenString else {
            throw GoogleSignInError.missingIDToken
        }
        return idToken
    }

    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? scene?.windows.first?.rootViewController else { return nil }
        var top: UIViewController = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
