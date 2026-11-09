import Foundation

// MARK: - Enrollment request networking
//
// Thin wrapper over the student enrollment-request endpoints (ADR-0006).
// All calls go through `AuthInterceptor.shared.execute` so the
// transparent 401-refresh applies, matching every other feature service.
// Callers own their own loading/error state; this layer just maps paths
// to typed responses and throws `DroobError` straight through.

enum EnrollmentRequestService {

    private struct NoteBody: Encodable {
        let note: String?
    }

    /// `POST /v1/student/courses/{courseId}/enrollment-requests`
    /// Opens a PENDING request against a published course. The note is
    /// optional and capped server-side at 500 chars (we trim blank → nil).
    /// 404 if the course isn't published; 409 if already enrolled or a
    /// PENDING request already exists.
    static func create(courseId: String, note: String?) async throws -> EnrollmentRequest {
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/enrollment-requests",
            method: .POST,
            body: NoteBody(note: note))
        return try await AuthInterceptor.shared.execute(request)
    }

    /// `GET /v1/student/enrollment-requests?status=&instructorId=`
    /// The caller's requests, newest first. When `instructorId` is set the
    /// backend ignores `status` and scopes to that instructor (drives the
    /// instructor-profile "Pending" tab).
    static func list(
        status: EnrollmentRequestStatus? = nil,
        instructorId: String? = nil
    ) async throws -> [EnrollmentRequest] {
        var items: [URLQueryItem] = []
        if let instructorId {
            items.append(URLQueryItem(name: "instructorId", value: instructorId))
        } else if let status, status != .unknown {
            items.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        let request = APIRequest(
            path: "/v1/student/enrollment-requests",
            queryItems: items.isEmpty ? nil : items)
        return try await AuthInterceptor.shared.execute(request)
    }

    /// `GET /v1/student/courses/{courseId}/enrollment-request`
    /// The caller's *latest* request for one course, whatever its status.
    /// A single indexed row read — deliberately cheap, which is what makes
    /// the course screen's short-cadence approval poll affordable (the
    /// `list` call above fans out over every request the student ever made).
    ///
    /// Returns `nil` on 404. That is the backend's normal answer for "this
    /// student never requested this course", not a failure: callers must not
    /// surface it as an error, they should read it as "nothing to poll".
    /// Every other error is thrown so a caller can tell "no request" apart
    /// from "couldn't ask".
    static func latest(courseId: String) async throws -> EnrollmentRequest? {
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/enrollment-request")
        do {
            // Bound explicitly: letting the generic bind to the optional
            // return type would make the decoder try to decode `T?`.
            let found: EnrollmentRequest =
                try await AuthInterceptor.shared.execute(request)
            return found
        } catch let error as DroobError {
            if case .notFound = error { return nil }
            throw error
        }
    }

    /// `PATCH /v1/student/enrollment-requests/{requestId}`
    /// Edits the note on the caller's own PENDING request. 404 if not the
    /// caller's; 409 if no longer PENDING.
    static func editNote(requestId: String, note: String?) async throws -> EnrollmentRequest {
        let request = APIRequest(
            path: "/v1/student/enrollment-requests/\(requestId)",
            method: .PATCH,
            body: NoteBody(note: note))
        return try await AuthInterceptor.shared.execute(request)
    }

    /// `POST /v1/student/enrollment-requests/{requestId}/cancel`
    /// Withdraws the caller's own PENDING request (→ CANCELLED). 404 if not
    /// theirs; 409 if no longer PENDING.
    @discardableResult
    static func cancel(requestId: String) async throws -> EnrollmentRequest {
        let request = APIRequest(
            path: "/v1/student/enrollment-requests/\(requestId)/cancel",
            method: .POST)
        return try await AuthInterceptor.shared.execute(request)
    }
}
