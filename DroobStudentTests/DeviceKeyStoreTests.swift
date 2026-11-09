import XCTest
@testable import DroobStudent

/// Tests for the pure parts of `DeviceKeyStore` — specifically the
/// SubjectPublicKeyInfo wrapper, which is hand-rolled and worth pinning
/// to a known-good byte sequence.
///
/// The Secure Enclave paths (`generateKey`, `sign`) are not exercised
/// here: they require an actual SE which simulators don't provide.
/// Those paths are covered by manual smoke tests on a physical device.
final class DeviceKeyStoreTests: XCTestCase {

    /// Pins the 26-byte ASN.1 prefix the implementation prepends to a
    /// raw P-256 EC point. Generated independently from the OpenSSL
    /// ASN.1 spec for `SubjectPublicKeyInfo { id-ecPublicKey, prime256v1 }`
    /// followed by a 66-byte BIT STRING (0x00 + 65-byte EC point).
    ///
    /// If this test ever fails, you've changed the header bytes — be
    /// sure the new bytes still decode under
    /// `KeyFactory.getInstance("EC")` on the JVM side.
    func testSPKIWrapperEmitsExpectedHeader() {
        let rawECPoint = Data(repeating: 0xAA, count: 65)
        let spki = DeviceKeyStore.wrapP256RawPointInSPKI(rawECPoint)

        let expectedHeader: [UInt8] = [
            0x30, 0x59,
            0x30, 0x13,
            0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
            0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07,
            0x03, 0x42, 0x00
        ]
        XCTAssertEqual(Array(spki.prefix(expectedHeader.count)), expectedHeader)
        XCTAssertEqual(spki.count, expectedHeader.count + rawECPoint.count)
        XCTAssertEqual(Array(spki.suffix(rawECPoint.count)), Array(rawECPoint))
    }

    /// Total SPKI is always 91 bytes for a P-256 key (26-byte header +
    /// 65-byte raw EC point). Spring Boot rejects anything else, so
    /// pinning the length here gives us a fast failure if the prefix
    /// ever drifts.
    func testSPKILengthIsAlways91Bytes() {
        let rawECPoint = Data(repeating: 0x42, count: 65)
        XCTAssertEqual(
            DeviceKeyStore.wrapP256RawPointInSPKI(rawECPoint).count, 91)
    }
}
