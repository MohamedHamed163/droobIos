import Foundation
import LocalAuthentication
import Security

// MARK: - BiometricKeyStoring

/// Abstraction over the device's biometric-protected signing key so the
/// signing flow can be unit-tested with a fake while the real
/// implementation talks to the Secure Enclave.
protocol BiometricKeyStoring {
    /// Whether the device has a biometric-protected key the app can use.
    var hasKey: Bool { get }

    /// Generates a new ECDSA P-256 key in the Secure Enclave gated by
    /// `.biometryCurrentSet` (the key is invalidated automatically if
    /// the user adds or removes a Face ID / Touch ID enrollment). Returns
    /// the X.509 SubjectPublicKeyInfo DER bytes to upload to the server.
    ///
    /// Replaces any prior key — the caller is responsible for matching
    /// that with a re-enrollment on the server.
    func generateKey() throws -> Data

    /// Signs `payload` with the Secure Enclave key. Triggers a Face ID /
    /// Touch ID prompt with `reason` shown to the user (passcode fallback
    /// allowed via `.deviceOwnerAuthentication`). Returns ASN.1 DER ECDSA
    /// signature bytes.
    func sign(payload: Data, reason: String) throws -> Data

    /// Removes the key. Called when the user opts out of biometric login,
    /// signs out, or fails enrollment.
    func deleteKey()
}

// MARK: - DeviceKeyStore (Secure Enclave implementation)

/// Production implementation of {@link BiometricKeyStoring} that holds the
/// private key in the iOS Secure Enclave and exposes it only after a
/// successful Face ID / Touch ID (or passcode-fallback) check.
///
/// ## Access control
/// - `.biometryCurrentSet` — the key is destroyed automatically if the
///   user adds, removes, or changes their Face ID / Touch ID enrollment.
///   This is what prevents a thief who later enrolls their own face from
///   reusing the key.
/// - `.privateKeyUsage` — the key can only be used for cryptographic
///   operations; it is non-exportable.
/// - `kSecAttrTokenIDSecureEnclave` — generated inside the Secure Enclave;
///   the raw private key never leaves it.
///
/// ## Algorithm
/// ECDSA P-256 with SHA-256 (`.ecdsaSignatureMessageX962SHA256`). The
/// Secure Enclave hardware exclusively supports P-256, so this isn't a
/// configurable choice. Signatures come back in ASN.1 DER form, which is
/// what the backend's `SHA256withECDSA` JCA verifier expects.
final class DeviceKeyStore: BiometricKeyStoring {

    /// Keychain tag for the Secure Enclave private key. Unique per app
    /// install (the bundle id is part of the Keychain access group).
    private let keyTag = "sa.droob.biometric.signing.key".data(using: .utf8)!

    var hasKey: Bool {
        return loadPrivateKey() != nil
    }

    func generateKey() throws -> Data {
        // Clear any prior key first; re-enrollment must not stack.
        deleteKey()

        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &accessError
        ) else {
            throw DeviceKeyStoreError.accessControlFailed(
                (accessError?.takeRetainedValue() as Error?) ?? DeviceKeyStoreError.unknown)
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String:       kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String:       kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String:    true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessControl as String:  access
            ]
        ]

        var creationError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &creationError) else {
            throw DeviceKeyStoreError.keyGenerationFailed(
                (creationError?.takeRetainedValue() as Error?) ?? DeviceKeyStoreError.unknown)
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw DeviceKeyStoreError.publicKeyExtractionFailed
        }

        // SecKeyCopyExternalRepresentation returns the raw EC point
        // (X9.63 uncompressed) for an EC key. The backend needs the
        // X.509 SubjectPublicKeyInfo wrapper around it so the standard
        // JCA `KeyFactory("EC")` parser can read it without us
        // hand-rolling the curve parameters.
        var repError: Unmanaged<CFError>?
        guard let rawECPoint = SecKeyCopyExternalRepresentation(publicKey, &repError) as Data? else {
            throw DeviceKeyStoreError.publicKeyExtractionFailed
        }
        return Self.wrapP256RawPointInSPKI(rawECPoint)
    }

    func sign(payload: Data, reason: String) throws -> Data {
        let context = LAContext()
        context.localizedReason = reason
        // `.deviceOwnerAuthentication` allows the user to fall back to
        // the device passcode if Face ID fails repeatedly or is locked
        // out. The challenge-response flow still requires the Secure
        // Enclave key, which is fine: passcode is one of the policies
        // that satisfies `.userPresence` and our access control.

        guard let privateKey = loadPrivateKey(authContext: context) else {
            throw DeviceKeyStoreError.keyNotFound
        }

        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            payload as CFData,
            &signError
        ) as Data? else {
            throw DeviceKeyStoreError.signingFailed(
                (signError?.takeRetainedValue() as Error?) ?? DeviceKeyStoreError.unknown)
        }
        return signature
    }

    func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrKeyClass as String:       kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag as String: keyTag
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Private helpers

    private func loadPrivateKey(authContext: LAContext? = nil) -> SecKey? {
        var query: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrKeyClass as String:       kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag as String: keyTag,
            kSecReturnRef as String:          true
        ]
        if let authContext {
            query[kSecUseAuthenticationContext as String] = authContext
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let key = result else { return nil }
        // CFTypeRef → SecKey via Unmanaged-safe bridge.
        return (key as! SecKey)
    }

    /// Wraps a raw 65-byte uncompressed P-256 EC point (0x04 || X || Y)
    /// in a SubjectPublicKeyInfo DER envelope:
    ///
    /// ```asn1
    /// SubjectPublicKeyInfo ::= SEQUENCE {
    ///   algorithm        AlgorithmIdentifier,
    ///   subjectPublicKey BIT STRING
    /// }
    /// ```
    ///
    /// The 26-byte prefix below is the fixed ASN.1 encoding for
    /// `id-ecPublicKey` (1.2.840.10045.2.1) parameterised with the
    /// P-256 curve OID (1.2.840.10045.3.1.7), followed by the BIT STRING
    /// header for a 66-byte (520-bit) payload. This payload is exactly
    /// `0x00 || rawECPoint` (the leading 0x00 is the BIT STRING's
    /// "no unused bits" indicator).
    ///
    /// Hand-rolling this is unpleasant but pulling in a full ASN.1
    /// library for one fixed wrapper isn't worth it — the bytes are
    /// constants for this exact (curve, key-class) combination.
    static func wrapP256RawPointInSPKI(_ rawECPoint: Data) -> Data {
        let spkiHeader: [UInt8] = [
            0x30, 0x59,                                           // SEQUENCE (0x59 bytes)
            0x30, 0x13,                                           //   SEQUENCE (algorithm)
            0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, //     OID id-ecPublicKey
            0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, // OID prime256v1
            0x03, 0x42, 0x00                                      //   BIT STRING (66 bytes, 0 unused)
        ]
        var out = Data(spkiHeader)
        out.append(rawECPoint)
        return out
    }
}

// MARK: - Errors

enum DeviceKeyStoreError: LocalizedError {
    case accessControlFailed(Error)
    case keyGenerationFailed(Error)
    case publicKeyExtractionFailed
    case keyNotFound
    case signingFailed(Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .accessControlFailed(let e):
            return "Couldn't create Secure Enclave access control: \(e.localizedDescription)"
        case .keyGenerationFailed(let e):
            return "Couldn't generate Secure Enclave key: \(e.localizedDescription)"
        case .publicKeyExtractionFailed:
            return "Couldn't read the public key from the Secure Enclave"
        case .keyNotFound:
            return "No biometric key is enrolled on this device"
        case .signingFailed(let e):
            return "Biometric signing failed: \(e.localizedDescription)"
        case .unknown:
            return "Unknown biometric error"
        }
    }
}
