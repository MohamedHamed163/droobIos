import Foundation

// MARK: - FaceEnrollmentStore
//
// Persists the enrolled account owner's face *embedding* — and ONLY the
// embedding — on-device. Never a raw image, never uploaded. This is the
// privacy contract that keeps the identity tier compliant with KSA PDPL and
// Egypt data-protection rules: biometric template, local, deletable.
//
// Stored as a small JSON blob in Application Support with complete file
// protection (encrypted at rest, unreadable while the device is locked),
// keyed per user id so a shared device never matches the wrong owner.

struct FaceEnrollment: Codable {
    let userId: String
    let embedding: [Float]
    /// Unix seconds; lets the app re-enroll if the template ages out.
    let enrolledAt: TimeInterval
}

final class FaceEnrollmentStore {
    static let shared = FaceEnrollmentStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "presenceguard.enrollment")

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PresenceGuard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("enrollment.json")
    }

    /// Returns the enrolled template for `userId`, or nil if this device has
    /// no enrollment for that account.
    func enrollment(for userId: String) -> FaceEnrollment? {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let record = try? JSONDecoder().decode(FaceEnrollment.self, from: data),
                  record.userId == userId else { return nil }
            return record
        }
    }

    /// Stores (capture-once) the embedding for `userId`, replacing any prior
    /// enrollment. Written with complete file protection.
    func save(userId: String, embedding: [Float], at time: TimeInterval) {
        let record = FaceEnrollment(userId: userId, embedding: embedding, enrolledAt: time)
        queue.async {
            guard let data = try? JSONEncoder().encode(record) else { return }
            try? data.write(to: self.fileURL, options: [.atomic, .completeFileProtection])
        }
    }

    /// Removes the enrollment (e.g. on logout or a privacy reset).
    func clear() {
        queue.async { try? FileManager.default.removeItem(at: self.fileURL) }
    }

    /// Whether an enrollment exists for this user on this device.
    func isEnrolled(userId: String) -> Bool { enrollment(for: userId) != nil }
}
