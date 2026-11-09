import Foundation

// MARK: - Multipart upload helper
//
// Standalone uploader for chat attachments. `APIRequest` only handles
// JSON bodies, and the chat upload endpoint needs `multipart/form-data`
// with a `file` part — so we build the URLRequest by hand and send it
// through the same `Authorization: Bearer <token>` header the rest of
// the app uses. On 401 we don't bother with the refresh dance (the
// caller will hit the standard API path for the follow-up send and
// catch the 401 there); chat attachments are an interactive flow so
// surfacing the failure is fine.

/// Server response shape (mirrors `MessageAttachmentUploadResponse` on
/// the backend). The opaque `attachmentKey` is the value the iOS
/// composer re-submits in the matching send-message call.
struct ChatAttachmentUpload: Decodable, Equatable {
    let attachmentKey: String
    let attachmentType: String   // "IMAGE" | "DOCUMENT"
    let attachmentName: String
    let attachmentSizeBytes: Int64
    let attachmentUrl: String
    let contentType: String

    enum CodingKeys: String, CodingKey {
        case attachmentKey       = "attachment_key"
        case attachmentType      = "attachment_type"
        case attachmentName      = "attachment_name"
        case attachmentSizeBytes = "attachment_size_bytes"
        case attachmentUrl       = "attachment_url"
        case contentType         = "content_type"
    }
}

enum ChatAttachmentUploader {

    /// Mirrors `MessageService.MAX_ATTACHMENT_BYTES` on the backend. Kept
    /// in sync by hand — if the server bumps the limit, bump it here too
    /// or local validation will reject files the server would accept.
    static let maxAttachmentBytes: Int = 25 * 1024 * 1024

    /// Human-readable cap used in the "too large" error string. Pulled
    /// out so the L10n format and this constant can't drift.
    static let maxAttachmentMegabytes: Int = 25

    /// Friendly, localized upload errors. Each maps to a specific
    /// failure mode the composer surfaces inline above the input row.
    enum UploadError: LocalizedError {
        case empty
        case tooLarge(maxMegabytes: Int)
        case unsupportedType
        case network
        case server

        var errorDescription: String? {
            switch self {
            case .empty:
                return L10n.chatAttachmentErrorEmpty
            case .tooLarge(let max):
                return String(format: L10n.chatAttachmentErrorTooLargeFmt, max)
            case .unsupportedType:
                return L10n.chatAttachmentErrorUnsupported
            case .network:
                return L10n.chatAttachmentErrorNetwork
            case .server:
                return L10n.chatAttachmentErrorGeneric
            }
        }
    }

    /// Uploads `data` as a multipart `file` part to the chat-attachment
    /// endpoint. `filename` + `contentType` come straight from the iOS
    /// picker — we don't try to re-sniff the type so the server's
    /// classifier sees what the picker reported.
    static func upload(
        data: Data,
        filename: String,
        contentType: String
    ) async throws -> ChatAttachmentUpload {
        // Reject obvious-failures locally before we burn the user's
        // bandwidth + time on a multi-MB POST that we already know the
        // server will reject. The server still re-checks — this is just
        // for a friendlier experience.
        if data.isEmpty {
            throw UploadError.empty
        }
        if data.count > maxAttachmentBytes {
            throw UploadError.tooLarge(maxMegabytes: maxAttachmentMegabytes)
        }

        guard let token = TokenStore.shared.accessToken else {
            throw DroobError.unauthenticated(message: nil, messageAr: nil)
        }
        var url = APIClient.publicBaseURL
        url.appendPathComponent("v1/student/messages/attachments")
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            boundary: boundary,
            partName: "file",
            filename: filename,
            contentType: contentType,
            data: data)
        request.timeoutInterval = 60

        let responseData: Data
        let urlResponse: URLResponse
        do {
            (responseData, urlResponse) = try await URLSession.shared.data(for: request)
        } catch {
            throw UploadError.network
        }
        guard let http = urlResponse as? HTTPURLResponse else {
            throw UploadError.server
        }
        if http.statusCode == 401 {
            throw DroobError.unauthenticated(message: nil, messageAr: nil)
        }
        // The server returns 400 for empty / too-large / unsupported
        // payloads — map each to the matching localized error so the
        // composer pill reads like a real message, not "HTTP 400".
        if http.statusCode == 400 {
            throw mapBadRequest(responseData, fallbackBytes: data.count)
        }
        if http.statusCode == 413 {
            throw UploadError.tooLarge(maxMegabytes: maxAttachmentMegabytes)
        }
        if !(200...299).contains(http.statusCode) {
            throw UploadError.server
        }
        // Envelope is `{ "data": {...}, "meta": {...} }` — same as the
        // rest of the API. Decode it then return `.data`.
        struct Envelope: Decodable { let data: ChatAttachmentUpload }
        do {
            let env = try JSONDecoder().decode(Envelope.self, from: responseData)
            return env.data
        } catch {
            throw UploadError.server
        }
    }

    /// Parses the server's `{ "error": { "message": "..." } }` envelope
    /// for a 400 and best-guesses which `UploadError` to throw. The
    /// server's English message for "too large" includes the word
    /// "exceeds" + "limit"; "empty" is self-explanatory; everything
    /// else falls through to the generic "couldn't upload" copy.
    private static func mapBadRequest(_ body: Data, fallbackBytes: Int) -> UploadError {
        struct ErrorEnvelope: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: body))?
            .error?.message?.lowercased() ?? ""
        if message.contains("exceed") || message.contains("too large")
            || message.contains("limit") || message.contains("size") {
            return .tooLarge(maxMegabytes: maxAttachmentMegabytes)
        }
        if message.contains("empty") {
            return .empty
        }
        if message.contains("content type") || message.contains("disallowed")
            || message.contains("not allowed") || message.contains("unsupported") {
            return .unsupportedType
        }
        // No useful server message — use the local byte count as a last
        // hint. If we're at or above the local cap, almost certainly a
        // size rejection.
        if fallbackBytes >= maxAttachmentBytes {
            return .tooLarge(maxMegabytes: maxAttachmentMegabytes)
        }
        return .server
    }

    /// Builds the wire body for a single-part multipart upload. The
    /// CRLF terminators are mandatory — RFC 7578 — and forgetting the
    /// trailing newlines silently truncates the file on some servers
    /// (Spring is forgiving but not infinitely so).
    private static func multipartBody(
        boundary: String,
        partName: String,
        filename: String,
        contentType: String,
        data: Data
    ) -> Data {
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"\(partName)\"; filename=\"\(filename)\"\r\n")
        body.appendUTF8("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
