import SwiftUI
import Foundation

// MARK: - DeviceIntegrity
//
// Lightweight, conservative environment checks for the app's content-
// protection threat model. iOS apps can't run on Android emulators (BlueStacks
// etc.) or be installed as an APK — that's impossible by platform — so the
// realistic "untrusted environment" signals on iOS are:
//   • a jailbroken device (where screen-capture / hooking protections can be
//     stripped), and
//   • the iOS Simulator (a development/emulation environment).
//
// Detection is best-effort and defeatable by a determined attacker, but it
// raises the bar. Checks are intentionally conservative (a strong signal is
// required) to avoid locking out legitimate users.

enum DeviceIntegrity {

    /// True when running in the iOS Simulator (Xcode), the closest thing to an
    /// "emulator" that an iOS build can run in.
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Conservative jailbreak detection. True only on a strong signal:
    /// a successful write outside the sandbox, or ≥2 known jailbreak
    /// artifacts present. Always false in the Simulator and DEBUG builds.
    static var isJailbroken: Bool {
        #if targetEnvironment(simulator) || DEBUG
        return false
        #else
        if canWriteOutsideSandbox() { return true }
        return suspiciousPathCount() >= 2
        #endif
    }

    /// The environment is considered compromised (for content protection)
    /// when the device is jailbroken.
    static var isCompromised: Bool { isJailbroken }

    // MARK: Signals

    private static let suspiciousPaths = [
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/usr/sbin/sshd",
        "/bin/bash",
        "/etc/apt",
        "/private/var/lib/apt/",
        "/usr/bin/ssh",
        "/var/jb"                     // rootless jailbreaks (palera1n, Dopamine)
    ]

    private static func suspiciousPathCount() -> Int {
        let fm = FileManager.default
        return suspiciousPaths.reduce(0) { $0 + (fm.fileExists(atPath: $1) ? 1 : 0) }
    }

    /// A sandboxed app cannot write outside its container. If this succeeds,
    /// the sandbox is broken → jailbroken.
    private static func canWriteOutsideSandbox() -> Bool {
        let path = "/private/" + UUID().uuidString + ".txt"
        do {
            try "integrity".write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Block screen
//
// Shown app-wide (release builds) when the device is jailbroken, so protected
// course content never renders in a compromised environment.

struct DeviceIntegrityBlockView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(.red.opacity(0.9))
                Text(L10n.integrityBlockedTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(L10n.integrityBlockedMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
    }
}
