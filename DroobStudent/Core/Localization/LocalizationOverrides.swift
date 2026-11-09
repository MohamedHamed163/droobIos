import Foundation
import Combine

// MARK: - LocalizationOverrides
//
// DB-backed translation overrides. The bundled `Localizable.strings` stays the
// offline/default baseline; a backend override for a key+locale wins at runtime
// (see `L10n.loc(_:)`), so wording can change without an App Store release.
//
// Backend contract — GET /v1/public/i18n/IOS (UNAUTHENTICATED, must work
// pre-login):
//   { "platform":"IOS", "revision":42,
//     "locales": { "en": {"auth.login":"Sign in", …}, "ar": {…} } }
// Response carries an ETag ("IOS-v42"); we echo it back as `If-None-Match` so an
// unchanged bundle returns 304 (no-op). Keys/placeholders are iOS-native — they
// match the `Localizable.strings` keys 1:1 (`%d`, `%@` preserved).
//
// The store is read synchronously from the render (main) thread via `loc(_:)`
// and written from a background fetch task, so the in-memory map is guarded by a
// lock. `revision` is `@Published` so a high-level observer (`DroobStudentApp`)
// re-renders the tree when overrides change; because every `L10n.*` value is a
// computed property re-read each render, the new wording flows through.
final class LocalizationOverrides: ObservableObject {
    static let shared = LocalizationOverrides()

    /// Bumped on every applied override change so SwiftUI re-renders. Views
    /// observing the shared store rebuild, picking up the new wording.
    @Published private(set) var revision: Int = 0

    /// In-memory `[locale: [key: value]]`. Guarded by `lock` because `loc(_:)`
    /// reads it synchronously on the main thread while `refresh()` writes it
    /// from a background task.
    private var overrides: [String: [String: String]] = [:]
    private let lock = NSLock()

    // Persistence — versioned keys so a schema change invalidates cleanly.
    private static let storeKey = "droob.i18n.overrides.v1"
    private static let etagKey  = "droob.i18n.etag.v1"

    private let defaults = UserDefaults.standard

    private init() {
        loadPersisted()
    }

    // MARK: - Read (hot path, called from L10n.loc)

    /// Backend override for `key` in `locale`, or `nil` to fall back to the
    /// bundled `Localizable.strings`. Cheap + synchronous.
    func value(forKey key: String, locale: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return overrides[locale]?[key]
    }

    // MARK: - Persistence

    /// Loads the last-known overrides into memory on init so a cold offline
    /// start still applies them.
    private func loadPersisted() {
        guard let data = defaults.data(forKey: Self.storeKey),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return }
        lock.lock()
        overrides = decoded
        lock.unlock()
    }

    private func persist(_ snapshot: [String: [String: String]]) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storeKey)
    }

    private var storedETag: String? { defaults.string(forKey: Self.etagKey) }
    private func storeETag(_ etag: String) { defaults.set(etag, forKey: Self.etagKey) }

    // MARK: - Fetch

    /// Wire shape for GET /v1/public/i18n/IOS.
    private struct Payload: Decodable {
        let platform: String
        let revision: Int
        let locales: [String: [String: String]]
    }

    /// Fetches the override bundle and applies it. UNAUTHENTICATED — no bearer
    /// token, and deliberately NOT routed through the 401-refresh interceptor;
    /// a plain `URLSession` call on `APIClient.publicBaseURL`. Sends the stored
    /// ETag as `If-None-Match` (304 → no-op). Any error keeps whatever is
    /// cached. Fetches ALL locales (no `?locale` filter) so both languages are
    /// always cached and a language switch needs no refetch.
    func refresh() async {
        let url = APIClient.publicBaseURL.appendingPathComponent("/v1/public/i18n/IOS")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = storedETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return // offline / transient — keep the cached bundle
        }
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 304 { return }                     // unchanged
        guard http.statusCode == 200, !data.isEmpty,
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }

        // Replace each returned locale's map wholesale so keys removed on the
        // backend don't linger. An all-locales fetch returns every language; a
        // `?locale`-filtered one would only touch that locale.
        lock.lock()
        for (locale, map) in payload.locales {
            overrides[locale] = map
        }
        let snapshot = overrides
        lock.unlock()

        persist(snapshot)
        // HTTPURLResponse header lookup is case-insensitive ("ETag"/"Etag").
        if let etag = http.value(forHTTPHeaderField: "ETag") {
            storeETag(etag)
        }

        // Publish on the main thread so SwiftUI observers re-render safely.
        await MainActor.run { self.revision += 1 }
    }
}
