import Foundation
import Security

// MARK: - TokenStore
// Stores access and refresh tokens in the Keychain.
// kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly — survives relaunch, not device restore.

final class TokenStore {
    static let shared = TokenStore()

    private let accessTokenKey = "droob.accessToken"
    private let refreshTokenKey = "droob.refreshToken"

    private init() {}

    // MARK: - Read

    var accessToken: String? {
        get { read(key: accessTokenKey) }
    }

    var refreshToken: String? {
        get { read(key: refreshTokenKey) }
    }

    // MARK: - Write

    func save(tokens: AuthTokens) {
        save(value: tokens.accessToken, for: accessTokenKey)
        save(value: tokens.refreshToken, for: refreshTokenKey)
    }

    func clearTokens() {
        delete(key: accessTokenKey)
        delete(key: refreshTokenKey)
    }

    // MARK: - Keychain helpers

    private func read(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private func save(value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Try update first
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Add new item
            var addQuery: [CFString: Any] = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
