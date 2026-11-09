import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Device fingerprint

/// Stable per-install identifier sent on every API call as `X-Device-Id`.
/// Uses `identifierForVendor` when available (consistent for the same app
/// on the same device) and falls back to a UUID stored in UserDefaults so
/// previews and unit tests have a deterministic value too.
enum DeviceFingerprint {
    static let value: String = {
        #if canImport(UIKit)
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            return vendorId
        }
        #endif
        let key = "droob.deviceFingerprint"
        if let stored = UserDefaults.standard.string(forKey: key) { return stored }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()

    /// Friendly name like "Kareem's iPhone" used as the device row label.
    /// Falls back to the model + OS version on platforms where the
    /// user-supplied name isn't available.
    static var label: String {
        #if canImport(UIKit)
        let name = asciiSafe(UIDevice.current.name)
        if !name.isEmpty { return name }
        return asciiSafe("\(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)")
        #else
        return "Apple device"
        #endif
    }

    /// HTTP header values must be ASCII — `UIDevice.current.name` is
    /// user-supplied and is very often Arabic here, which produces an invalid
    /// header. Strip anything non-ASCII rather than let the whole request
    /// carry a malformed value.
    private static func asciiSafe(_ value: String) -> String {
        let cleaned = value.unicodeScalars
            .map { $0.isASCII && $0.value >= 32 && $0.value != 127 ? Character($0) : " " }
        return String(cleaned)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}

// MARK: - Envelope Models

struct ApiMeta: Decodable {
    let requestId: String?
    let serverTime: String?
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case serverTime = "server_time"
    }
}

struct ApiEnvelope<T: Decodable>: Decodable {
    let data: T
    let meta: ApiMeta?
}

struct ProblemDetail: Decodable {
    let code: String
    let message: String
    let messageAr: String?
    let details: [String: String]?
    let field: String?
    let retryable: Bool
    enum CodingKeys: String, CodingKey {
        case code, message, field, retryable, details
        case messageAr = "message_ar"
    }
}

struct ProblemEnvelope: Decodable {
    let error: ProblemDetail
    let meta: ApiMeta?
}

// MARK: - DroobError

enum DroobError: LocalizedError {
    case network(underlying: Error)
    case httpError(statusCode: Int, problem: ProblemDetail?)
    case decodingError(underlying: Error)
    case invalidURL
    /// 401 from the backend. Carries the server-supplied bilingual messages
    /// when present so call sites can show the domain reason ("Invalid or
    /// expired code") instead of the generic session-expiry copy. Bare
    /// `.unauthenticated(nil, nil)` is still the fallback for stale tokens
    /// where the server didn't include a problem detail.
    case unauthenticated(message: String?, messageAr: String?)
    /// 403 from the backend. Carries the server-supplied bilingual
    /// messages when present so call sites can show the domain reason
    /// (e.g. "You were removed from this room by a host and can't
    /// rejoin") instead of the generic "Access denied" copy. Previously
    /// this case was payload-free, which silently discarded the server's
    /// `problem.message` — every 403 read identically to the user. Bare
    /// `.forbidden(nil, nil)` is still the fallback when the server didn't
    /// include a problem detail (e.g. an enrollment guard).
    case forbidden(message: String?, messageAr: String?)
    /// 404 from the backend. Carries the server-supplied bilingual
    /// messages when present so call sites can show the domain reason
    /// ("Incorrect passcode") instead of the generic "Resource not
    /// found" copy. Previously this case was payload-free, which
    /// silently discarded the server's `problem.message` and made
    /// every 404 read identical to the user — that's exactly the
    /// bug the wrong-passcode flow surfaced.
    case notFound(message: String?, messageAr: String?)
    /// 403 with `DEVICE_NOT_AUTHORIZED`. The account is pinned to a different
    /// device (one device per student). Kept distinct from `.forbidden` so the
    /// login screen shows the server's explanation rather than collapsing it
    /// into the generic "wrong email or password" banner.
    case deviceNotAuthorized(message: String?, messageAr: String?)
    /// 409. Carries the server's bilingual problem detail for the same reason
    /// `.forbidden` / `.notFound` do — under the Arabic lock the English
    /// `message` alone would be the only thing a banner could show.
    case conflict(message: String, messageAr: String?)
    /// 5xx. Bilingual for the same reason as `.conflict`.
    case serverError(message: String, messageAr: String?)
    case unknown

    /// User-facing text for this error, in the language the APP is running in.
    ///
    /// Every error banner in the app reads this (or `localizedDescription`,
    /// which forwards to it), so this is the single place the app's language
    /// has to be honoured. Before the Arabic lock it returned English
    /// unconditionally and threw away the `message_ar` the server had already
    /// sent, which put Latin script under an Arabic-only UI on every auth,
    /// security, profile, messaging, notification and study-room failure.
    ///
    /// The English branch below is untouched and is what `englishHidden = false`
    /// goes back to reaching.
    var errorDescription: String? {
        if AppLocaleDefault.isArabic { return localizedArabicDescription }
        return englishDescription
    }

    /// The original English copy. Kept whole so flipping
    /// `AppLocaleDefault.englishHidden` back restores it verbatim.
    private var englishDescription: String? {
        switch self {
        case .network(let e): return e.localizedDescription
        case .httpError(_, let p): return p?.message ?? "Request failed"
        case .decodingError(let e):
            // Give a more specific reason than Swift's default
            // localised message ("missing"/"not in correct format")
            // so a wire-shape mismatch surfaces with the failing key
            // instead of a generic copy. The DEBUG path also dumps
            // the coding path which is what you actually need.
            if let dec = e as? DecodingError {
                switch dec {
                case .keyNotFound(let key, let ctx):
                    return "Missing field '\(key.stringValue)'" +
                        " in \(prettyPath(ctx.codingPath))"
                case .typeMismatch(let type, let ctx):
                    return "Wrong type for \(prettyPath(ctx.codingPath))" +
                        " (expected \(type))"
                case .valueNotFound(let type, let ctx):
                    return "Null where \(type) was required" +
                        " at \(prettyPath(ctx.codingPath))"
                case .dataCorrupted(let ctx):
                    return "Malformed response at " +
                        "\(prettyPath(ctx.codingPath)): \(ctx.debugDescription)"
                @unknown default:
                    return "Decoding error: \(e.localizedDescription)"
                }
            }
            return "Decoding error: \(e.localizedDescription)"
        case .invalidURL: return "Invalid URL"
        case .unauthenticated(let msg, _): return msg ?? "Please log in again"
        case .forbidden(let msg, _): return msg ?? "Access denied"
        case .notFound(let msg, _): return msg ?? "Resource not found"
        case .deviceNotAuthorized(let msg, _): return msg ?? L10n.loginErrDeviceNotAuthorized
        case .conflict(let msg, _): return msg
        case .serverError(let msg, _): return msg
        case .unknown: return "An unknown error occurred"
        }
    }

    /// Compact human-readable form of a CodingKey path used by the
    /// decode-error branch — e.g. `data.members[0].user_id`.
    private func prettyPath(_ path: [CodingKey]) -> String {
        if path.isEmpty { return "root" }
        return path.map { key in
            if let i = key.intValue { return "[\(i)]" }
            return key.stringValue
        }.joined(separator: ".")
    }

    /// Arabic copy for every case — the server's `message_ar` when it sent one,
    /// otherwise the bundled Arabic string for that class of failure.
    ///
    /// Total on purpose: this is what `errorDescription` returns under the
    /// Arabic lock, so a `nil`/`default` branch here would fall back to English
    /// on exactly the paths (network, decode, 409, 5xx) the server has no
    /// Arabic message for.
    ///
    /// Technical detail — the decode path's failing key, the URLError text — is
    /// never user copy in any language, so it goes to the console in DEBUG and
    /// the banner gets the plain sentence.
    var localizedArabicDescription: String? {
        switch self {
        case .network:
            return L10n.errNetwork
        case .httpError(_, let p):
            return p?.messageAr ?? L10n.errRequestFailed
        case .decodingError:
            #if DEBUG
            print("[DroobError.decodingError] \(englishDescription ?? "")")
            #endif
            return L10n.errBadResponse
        case .invalidURL:
            return L10n.errInvalidURL
        case .unauthenticated(_, let ar): return ar ?? L10n.errLoginAgain
        case .forbidden(_, let ar): return ar ?? L10n.errAccessDenied
        case .notFound(_, let ar): return ar ?? L10n.errNotFound
        case .deviceNotAuthorized(_, let ar): return ar ?? L10n.loginErrDeviceNotAuthorized
        case .conflict(_, let ar): return ar ?? L10n.errConflict
        case .serverError(_, let ar): return ar ?? L10n.errServer
        case .unknown: return L10n.errUnknown
        }
    }
}

// MARK: - HTTP Method

enum HTTPMethod: String {
    case GET, POST, PUT, PATCH, DELETE
}

// MARK: - APIRequest

struct APIRequest {
    var path: String
    var method: HTTPMethod
    var body: (any Encodable)?
    var queryItems: [URLQueryItem]?
    var requiresAuth: Bool
    /// Per-call header overrides, merged in after the standard JSON +
    /// device headers and before `Authorization` (so a caller can never
    /// accidentally clobber the bearer token).
    ///
    /// Added for the multi-model AI tutor, which must send
    /// `Accept-Language` so the upstream models answer — and the server
    /// labels them — in the app's language rather than the device's.
    /// Defaults to `nil`, so every existing call site is unchanged.
    var headers: [String: String]?
    /// Per-call deadline, in seconds, for endpoints whose server-side work
    /// legitimately outlasts the shared session's 30 s.
    ///
    /// `timeoutIntervalForRequest` is the wait for the *next byte*, which is
    /// fine for every streamed or fast endpoint but wrong for a non-streamed
    /// fan-out: the multi-model AI tutor asks up to ten upstream models and
    /// sends nothing until they all return, so a 30 s deadline kills real
    /// answers. Setting this routes the call through a session whose ceiling
    /// sits above the value, instead of raising the deadline app-wide (which
    /// would make every ordinary call hang far longer on a dead network).
    /// `nil` — the default — keeps the shared 30 s behaviour.
    var timeout: TimeInterval?

    init(path: String,
         method: HTTPMethod = .GET,
         body: (any Encodable)? = nil,
         queryItems: [URLQueryItem]? = nil,
         requiresAuth: Bool = true,
         headers: [String: String]? = nil,
         timeout: TimeInterval? = nil) {
        self.path = path
        self.method = method
        self.body = body
        self.queryItems = queryItems
        self.requiresAuth = requiresAuth
        self.headers = headers
        self.timeout = timeout
    }
}

// MARK: - APIClient

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    /// Session used only by requests that declare their own `timeout`. Its
    /// ceiling is deliberately well above any single call's deadline, so the
    /// per-request `timeoutInterval` is what actually fires. See
    /// `APIRequest.timeout`.
    private let extendedSession: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder

    private var baseURL: URL {
        Self.publicBaseURL
    }

    /// Exposed so non-API consumers (e.g. the Turnstile WebView, which must
    /// load `/captcha.html` from the backend hostname Cloudflare validates
    /// against) can resolve URLs without duplicating the resolution rules.
    static var publicBaseURL: URL {
        let urlString = Bundle.main.object(forInfoDictionaryKey: "DROOB_API_BASE_URL") as? String
            ?? ProcessInfo.processInfo.environment["DROOB_API_BASE_URL"]
            ?? "http://localhost:9080"
        return URL(string: urlString)!
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)

        let longConfig = URLSessionConfiguration.default
        longConfig.timeoutIntervalForRequest = Self.extendedTimeoutCeiling
        longConfig.timeoutIntervalForResource = 600
        self.extendedSession = URLSession(configuration: longConfig)

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .useDefaultKeys
        // Spring Boot serialises Instant as ISO-8601. Try fractional-second
        // variant first, then the plain variant, so both work.
        let isoWithMs = ISO8601DateFormatter()
        isoWithMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = isoWithMs.date(from: s) { return d }
            if let d = isoPlain.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Cannot parse date: \(s)")
        }
        self.decoder = dec
    }

    /// Upper bound on any per-request `timeout`. Requests asking for more
    /// than this are clamped rather than silently cut short by the session.
    private static let extendedTimeoutCeiling: TimeInterval = 180

    /// The session a request runs on — the extended one only when it asked
    /// for a longer deadline than the shared session allows.
    private func session(for apiRequest: APIRequest) -> URLSession {
        apiRequest.timeout == nil ? self.session : self.extendedSession
    }

    // MARK: - Build URLRequest

    func buildURLRequest(for apiRequest: APIRequest, accessToken: String? = nil) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(apiRequest.path), resolvingAgainstBaseURL: false)
        if let queryItems = apiRequest.queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { throw DroobError.invalidURL }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = apiRequest.method.rawValue
        if let timeout = apiRequest.timeout {
            urlRequest.timeoutInterval = min(timeout, Self.extendedTimeoutCeiling)
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        // The APP's language, not the device's. Only the AI tutor used to send
        // this, so every other endpoint had no signal to pick a language and
        // answered in English `message` — under the Arabic lock that is Latin
        // script in an Arabic-only UI. A caller-supplied `Accept-Language` in
        // `apiRequest.headers` still overrides this below.
        urlRequest.setValue(L10n.currentLanguageCode, forHTTPHeaderField: "Accept-Language")
        // Stable per-install device fingerprint so the backend can upsert
        // the caller's row in `student_devices` without duplicates.
        urlRequest.setValue(DeviceFingerprint.value, forHTTPHeaderField: "X-Device-Id")
        urlRequest.setValue(DeviceFingerprint.label, forHTTPHeaderField: "X-Device-Label")

        // Caller-supplied headers (e.g. Accept-Language). Applied before the
        // bearer token so `Authorization` always wins.
        if let extra = apiRequest.headers {
            for (field, value) in extra {
                urlRequest.setValue(value, forHTTPHeaderField: field)
            }
        }

        if let token = accessToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = apiRequest.body {
            urlRequest.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return urlRequest
    }

    // MARK: - Execute

    func execute<T: Decodable>(_ apiRequest: APIRequest, accessToken: String? = nil) async throws -> T {
        let urlRequest = try buildURLRequest(for: apiRequest, accessToken: accessToken)
        return try await performRequest(urlRequest, on: session(for: apiRequest))
    }

    /// Variant for endpoints that return `204 No Content` — no decoding,
    /// any 2xx with empty body succeeds.
    func executeVoid(_ apiRequest: APIRequest, accessToken: String? = nil) async throws {
        let urlRequest = try buildURLRequest(for: apiRequest, accessToken: accessToken)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session(for: apiRequest).data(for: urlRequest)
        } catch {
            if Self.isCancellationError(error) { throw CancellationError() }
            throw DroobError.network(underlying: error)
        }
        guard let httpResponse = response as? HTTPURLResponse else { throw DroobError.unknown }
        if (200..<300).contains(httpResponse.statusCode) { return }
        let problem = try? decoder.decode(ProblemEnvelope.self, from: data)
        throw mapHTTPError(statusCode: httpResponse.statusCode, problem: problem?.error)
    }

    /// `session` defaults to the shared 30 s one; callers with their own
    /// deadline pass the extended session (see `APIRequest.timeout`).
    func performRequest<T: Decodable>(_ urlRequest: URLRequest,
                                      on session: URLSession? = nil) async throws -> T {
        let session = session ?? self.session
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            // SwiftUI's `.refreshable` runs the body in a Task that gets
            // cancelled the moment the user releases the pull gesture. The
            // in-flight URLSessionTask then completes with NSURLErrorCancelled
            // (or with `CancellationError` from Swift Concurrency). We
            // re-throw cancellation as a Swift `CancellationError` so the
            // call site can recognise and ignore it instead of surfacing
            // "cancelled" as a user-facing error.
            if Self.isCancellationError(error) {
                throw CancellationError()
            }
            throw DroobError.network(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DroobError.unknown
        }

        if (200..<300).contains(httpResponse.statusCode) {
            // An empty body on a 2xx usually means the request was
            // intercepted by something between the app and the API
            // (Wi-Fi captive portal, proxy, host unreachable returning
            // a 200 from a probe). Surface this as a clean network
            // error instead of a misleading "decoding error".
            if data.isEmpty {
                throw DroobError.network(
                    underlying: NSError(domain: "DroobAPIClient",
                                        code: -1,
                                        userInfo: [NSLocalizedDescriptionKey:
                                            "Empty response from server"]))
            }
            do {
                let envelope = try decoder.decode(ApiEnvelope<T>.self, from: data)
                return envelope.data
            } catch {
                throw DroobError.decodingError(underlying: error)
            }
        } else {
            let problem = try? decoder.decode(ProblemEnvelope.self, from: data)
            throw mapHTTPError(statusCode: httpResponse.statusCode, problem: problem?.error)
        }
    }

    // MARK: - Raw bytes for SSE

    func bytesStream(for urlRequest: URLRequest) async throws -> URLSession.AsyncBytes {
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DroobError.unknown
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DroobError.httpError(statusCode: httpResponse.statusCode, problem: nil)
        }
        return bytes
    }

    // MARK: - Error mapping

    private func mapHTTPError(statusCode: Int, problem: ProblemDetail?) -> DroobError {
        switch statusCode {
        case 401: return .unauthenticated(message: problem?.message, messageAr: problem?.messageAr)
        case 403:
            // The one-device pin is a 403 like any other, but it needs its own
            // banner — see `deviceNotAuthorized`.
            if problem?.code == "DEVICE_NOT_AUTHORIZED" {
                return .deviceNotAuthorized(
                    message: problem?.message, messageAr: problem?.messageAr)
            }
            return .forbidden(message: problem?.message, messageAr: problem?.messageAr)
        case 404: return .notFound(message: problem?.message, messageAr: problem?.messageAr)
        case 409: return .conflict(message: problem?.message ?? "Conflict",
                                   messageAr: problem?.messageAr)
        case 500...: return .serverError(message: problem?.message ?? "Server error",
                                         messageAr: problem?.messageAr)
        default: return .httpError(statusCode: statusCode, problem: problem)
        }
    }
}

extension APIClient {
    /// True iff the error represents a cancellation — either the Swift
    /// concurrency form (`CancellationError`) or the URLSession form
    /// (`URLError.cancelled` / `NSURLErrorCancelled`).
    static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        // Walk one level into DroobError.network(...) so call sites that
        // match on the high-level error don't accidentally surface a
        // "cancelled" message.
        if let droob = error as? DroobError, case .network(let underlying) = droob {
            return isCancellationError(underlying)
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        return false
    }
}

// MARK: - AnyEncodable helper

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
