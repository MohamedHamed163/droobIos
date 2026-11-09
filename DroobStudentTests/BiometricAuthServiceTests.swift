import XCTest
import LocalAuthentication
@testable import DroobStudent

/// Tests for `BiometricAuthService.availability()` mapping. Uses a fake
/// `LAContext` subclass so the mapping logic can be tested without
/// real biometrics enrolled on the device.
final class BiometricAuthServiceTests: XCTestCase {

    func testAvailableFaceID() {
        let service = BiometricAuthService(contextFactory: {
            FakeLAContext(canEvaluate: true, biometryType: .faceID)
        })
        XCTAssertEqual(service.availability(), .available(.faceID))
    }

    func testAvailableTouchID() {
        let service = BiometricAuthService(contextFactory: {
            FakeLAContext(canEvaluate: true, biometryType: .touchID)
        })
        XCTAssertEqual(service.availability(), .available(.touchID))
    }

    func testNotEnrolled() {
        let service = BiometricAuthService(contextFactory: {
            FakeLAContext(
                canEvaluate: false,
                biometryType: .none,
                evaluateError: NSError(
                    domain: LAErrorDomain,
                    code: LAError.biometryNotEnrolled.rawValue))
        })
        XCTAssertEqual(service.availability(), .notEnrolled)
    }

    func testLockedOut() {
        let service = BiometricAuthService(contextFactory: {
            FakeLAContext(
                canEvaluate: false,
                biometryType: .none,
                evaluateError: NSError(
                    domain: LAErrorDomain,
                    code: LAError.biometryLockout.rawValue))
        })
        XCTAssertEqual(service.availability(), .lockedOut)
    }

    func testHardwareNotAvailable() {
        let service = BiometricAuthService(contextFactory: {
            FakeLAContext(
                canEvaluate: false,
                biometryType: .none,
                evaluateError: NSError(
                    domain: LAErrorDomain,
                    code: LAError.biometryNotAvailable.rawValue))
        })
        XCTAssertEqual(service.availability(), .notAvailable)
    }
}

// MARK: - FakeLAContext

/// `LAContext` subclass that lets tests fix the responses to
/// `canEvaluatePolicy` and `biometryType` without touching real hardware.
/// Overrides only the two members `BiometricAuthService` calls.
private final class FakeLAContext: LAContext {
    private let stubCanEvaluate: Bool
    private let stubBiometryType: LABiometryType
    private let stubEvaluateError: NSError?

    init(
        canEvaluate: Bool,
        biometryType: LABiometryType,
        evaluateError: NSError? = nil
    ) {
        self.stubCanEvaluate = canEvaluate
        self.stubBiometryType = biometryType
        self.stubEvaluateError = evaluateError
        super.init()
    }

    override func canEvaluatePolicy(
        _ policy: LAPolicy, error: NSErrorPointer
    ) -> Bool {
        if !stubCanEvaluate, let e = stubEvaluateError {
            error?.pointee = e
        }
        return stubCanEvaluate
    }

    override var biometryType: LABiometryType {
        return stubBiometryType
    }
}
