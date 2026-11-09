import Foundation

/// Server-driven runtime config, fetched from `/v1/public/config/IOS`.
///
/// Today it carries one setting: whether screenshots and screen recording are
/// blocked app-wide. That used to be a per-user toggle in Settings; it is now a
/// single policy an admin sets for the whole platform, and the app has no local
/// override.
///
/// Same shape as `LocalizationOverrides`: unauthenticated (the endpoint has to
/// work on the login screen), conditional-GET with an `ETag` so an unchanged
/// config costs a ~0-byte 304, and the last value is cached in `UserDefaults`
/// so it applies from the very first frame and survives being offline.
///
/// **Fail closed.** Until a device has successfully read this, capture stays
/// blocked — see `CaptureProtectionEnvironment.defaultValue`. A network failure
/// must never be the thing that unprotects course content; the opposite
/// mistake, blocking a screenshot that should have been allowed, is recoverable
/// the moment the fetch succeeds.
enum RemoteAppConfig {

    private static let etagKey = "appConfigETag"

    private struct Payload: Decodable {
        let capture_blocked: Bool
    }

    /// Fetches the config and caches it. Silent on failure — the cached value
    /// (or the fail-closed default) stands.
    static func refresh() async {
        let url = APIClient.publicBaseURL.appendingPathComponent("/v1/public/config/IOS")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = UserDefaults.standard.string(forKey: etagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return // offline / transient — keep the cached policy
        }
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 304 { return }                     // unchanged
        guard http.statusCode == 200, !data.isEmpty,
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }

        UserDefaults.standard.set(
            payload.capture_blocked,
            forKey: CaptureProtectionEnvironment.storageKey)

        // Store the ETag only after the body has been applied, so a failed
        // decode can't leave us 304-ing against a value we never adopted.
        if let etag = http.value(forHTTPHeaderField: "ETag") {
            UserDefaults.standard.set(etag, forKey: etagKey)
        }
    }
}
