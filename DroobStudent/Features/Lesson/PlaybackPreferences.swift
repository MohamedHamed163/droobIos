import Foundation
import SwiftUI
import Combine

// MARK: - PlaybackPreferences
//
// Single source of truth for the per-student playback settings exposed by
// the Playback Settings screen and the in-player quick chips. Keeping the
// store outside any single view lets the player read its initial state
// synchronously when the AVPlayer is created and react to changes made on
// the Settings screen without prop-drilling closures.
//
// Persistence model (per the May 2026 product decision):
//
//   • Speed   — per-lesson, saved in UserDefaults under
//               `droob.playback.speed.<lessonId>`. Defaults to 1×.
//   • Quality — per-lesson, saved in UserDefaults under
//               `droob.playback.quality.<lessonId>`. Defaults to .auto
//               (no bitrate cap; AVPlayer picks adaptively).
//   • Autoplay-next-lesson — global, persisted across sessions via
//               `@AppStorage`. Default ON.
//   • Subtitles — global, persisted, but currently a no-op (no caption
//               tracks exist on the backend yet — see PlaybackSettingsView
//               for the disabled-row treatment).
//
// The class is `@MainActor` because every consumer is a SwiftUI view; it
// also publishes the global toggles via @AppStorage-equivalent properties
// so views observing the store re-render when those flip.

/// Video quality preset. The raw bitrate cap is what we feed into
/// `AVPlayerItem.preferredPeakBitRate` — `0` means "no cap, let HLS pick
/// adaptively." Values are conservative ceilings sized to comfortably
/// stream the matching rendition over a typical mobile connection.
enum PlaybackQuality: String, CaseIterable, Identifiable, Codable {
    case auto        // adaptive — let HLS choose
    case low480p     // ~480p
    case high720p    // ~720p HD
    case ultra1080p  // ~1080p Full HD
    var id: String { rawValue }

    /// AVPlayerItem.preferredPeakBitRate value in bits-per-second.
    /// 0 is the documented "no preference" sentinel for adaptive playback.
    var preferredPeakBitsPerSecond: Double {
        switch self {
        case .auto:        return 0
        case .low480p:     return 1_200_000
        case .high720p:    return 3_000_000
        case .ultra1080p:  return 6_500_000
        }
    }
}

@MainActor
final class PlaybackPreferences: ObservableObject {
    /// Process-wide shared instance. The player and the Settings screen
    /// both bind to this so updates from either side propagate immediately
    /// without any explicit wiring.
    static let shared = PlaybackPreferences()

    // ── Global, persistent ───────────────────────────────────────────────
    @AppStorage("droob.playback.autoplayNext") var autoplayNextLesson: Bool = true
    @AppStorage("droob.playback.subtitlesOn")  var subtitlesEnabled: Bool   = false
    /// BCP-47 language code of the preferred caption track ("en"/"ar"). The
    /// player matches this against the legible AVMediaSelectionGroup; if the
    /// lesson has no track in this language we fall back to the first
    /// available one so the toggle still shows *something*.
    @AppStorage("droob.playback.subtitleLang") var subtitleLanguage: String  = "en"

    /// Bump this on every per-lesson write so views observing a specific
    /// lesson re-render. Per-lesson values live in UserDefaults so they
    /// don't need to be cached in memory; this counter is just a published
    /// change signal.
    @Published private var perLessonRevision: Int = 0

    /// Allowed speed multipliers in the order the UI lists them. Mirrors
    /// the V21 in-player menu; the Settings screen consumes the same list
    /// so adding a new value (e.g. 0.25×) shows up in both places.
    static let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    private let defaults: UserDefaults
    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // ── Per-lesson: speed ────────────────────────────────────────────────

    func speed(forLesson lessonId: String) -> Float {
        // touch the revision so observers refresh on writes
        _ = perLessonRevision
        let stored = defaults.float(forKey: Self.speedKey(lessonId))
        return stored == 0 ? 1.0 : stored
    }

    func setSpeed(_ value: Float, forLesson lessonId: String) {
        defaults.set(value, forKey: Self.speedKey(lessonId))
        perLessonRevision &+= 1
    }

    // ── Per-lesson: quality ──────────────────────────────────────────────

    func quality(forLesson lessonId: String) -> PlaybackQuality {
        _ = perLessonRevision
        if let raw = defaults.string(forKey: Self.qualityKey(lessonId)),
           let q = PlaybackQuality(rawValue: raw) {
            return q
        }
        return .auto
    }

    func setQuality(_ value: PlaybackQuality, forLesson lessonId: String) {
        defaults.set(value.rawValue, forKey: Self.qualityKey(lessonId))
        perLessonRevision &+= 1
    }

    // ── Key helpers ──────────────────────────────────────────────────────

    private static func speedKey(_ lessonId: String) -> String {
        "droob.playback.speed.\(lessonId)"
    }
    private static func qualityKey(_ lessonId: String) -> String {
        "droob.playback.quality.\(lessonId)"
    }
}
