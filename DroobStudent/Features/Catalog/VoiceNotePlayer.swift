import AVFoundation
import Combine
import Foundation
import SwiftUI

// MARK: - VoiceNotePlaybackCoordinator
//
// Process-wide "currently playing voice note" tracker. Each bubble owns
// its own `VoiceNotePlayer`, but only one note may be audible at a time
// — matching WhatsApp / Telegram. When a bubble starts playback it
// registers itself here; the previous holder is asked to pause. Without
// this, multiple bubbles tapped in quick succession overlap, AVAudioSession
// state thrashes between them, and the second tap intermittently produces
// silent playback. Lives on the main actor since SwiftUI's `@StateObject`
// already does, and there's no use case for cross-thread access.

@MainActor
final class VoiceNotePlaybackCoordinator {
    static let shared = VoiceNotePlaybackCoordinator()
    private weak var current: VoiceNotePlayer?

    func setActivePlayer(_ player: VoiceNotePlayer) {
        if let existing = current, existing !== player {
            existing.pauseFromCoordinator()
        }
        current = player
    }

    func clear(_ player: VoiceNotePlayer) {
        if current === player { current = nil }
    }
}

// MARK: - VoiceNotePlayer
//
// Pull-on-demand audio player for voice-note bubbles. Each bubble owns
// its own player instance — voice notes are short so the cost of one
// `AVAudioPlayer` per visible bubble is negligible, and shared singleton
// state would make pause/seek bookkeeping painful.
//
// The player streams from the presigned URL the backend mints into
// `attachment_url`. We download the bytes the first time the user hits
// play, cache them on disk under the bubble's message id, and feed
// them to `AVAudioPlayer` — avoids re-downloading on every replay.

@MainActor
final class VoiceNotePlayer: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false
    /// Set when the last play attempt failed (session error, expired
    /// presigned URL / non-2xx fetch, undecodable audio, or AVAudioPlayer
    /// refusing to start). Drives a visible retry affordance on the bubble
    /// so a failure is no longer a silent dead tap — the whole point of
    /// this surface is that we *catch* the failure next time instead of
    /// the user staring at a play icon that does nothing.
    @Published var loadFailed: Bool = false
    /// Elapsed playback seconds — drives the progress bar + counter.
    /// Updated by a polled ticker rather than KVO since AVAudioPlayer
    /// doesn't expose a Combine publisher for `currentTime`.
    @Published var elapsed: TimeInterval = 0
    /// Total length in whole seconds, as the bubble first heard from
    /// the server. We trust the server-side value because the local
    /// duration extracted from AVAudioPlayer is sometimes flaky on
    /// fresh files (returns 0 before playback starts).
    let totalSeconds: Int

    /// Streaming URL — the presigned GET the backend re-mints every
    /// time the message is fetched. `var`, not `let`: the bubble owns
    /// this player as a `@StateObject` (constructed once), but the
    /// presigned URL has a 4h TTL and the parent re-mints a fresh one on
    /// every message-list fetch. `updateURL` lets a refreshed list heal
    /// a player whose captured URL has gone stale — without this the
    /// player reused the original (possibly expired) URL forever.
    private var url: URL
    /// Stable per-message id we use as the cache filename suffix.
    private let messageId: String

    private var audioPlayer: AVAudioPlayer?
    private var tickerTask: Task<Void, Never>?
    private var isFetching = false
    /// Set when the AVAudioSession's interruption-ended notification
    /// fires while this player was playing — used to resume in
    /// {@link #play} instead of falling into the "play on a player at
    /// end-of-file" path.
    private var wasInterrupted = false
    private var interruptionObserver: NSObjectProtocol?

    /// Wall-clock playback position, used when `AVAudioPlayer.currentTime`
    /// refuses to move.
    ///
    /// `currentTime` is the source of truth whenever it works, but it is
    /// pinned at 0 for the entire clip when the file is **Opus inside an
    /// MP4 container** — which is exactly what the instructor web records.
    /// Its `pickAudioMime()` asks for `audio/mp4`, and Chrome honours the
    /// container while encoding Opus inside it (`MediaRecorder.mimeType`
    /// comes back as `audio/mp4;codecs=opus`). Such a note decodes and
    /// plays audibly, and the finish delegate fires on time, but every
    /// position query returns 0 — so the counter and the bar sat frozen for
    /// the whole note and only "unfroze" when playback ended. Student-sent
    /// notes are AAC-in-MP4 from `VoiceNoteRecorder`, where `currentTime`
    /// works, which is why the bug looked specific to received messages.
    ///
    /// `playedBeforeCurrentSegment` accumulates completed play stretches;
    /// `segmentStartedAt` timestamps the stretch in flight. There is no
    /// scrubbing UI, so wall time and media time differ only by decode
    /// latency.
    private var playedBeforeCurrentSegment: TimeInterval = 0
    private var segmentStartedAt: Date?

    init(url: URL, messageId: String, totalSeconds: Int) {
        self.url = url
        self.messageId = messageId
        self.totalSeconds = max(0, totalSeconds)
        super.init()
        registerInterruptionObserver()
    }

    deinit {
        if let token = interruptionObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// 0.0 – 1.0 progress fraction for the bar. Falls back to 0 when
    /// we don't know the total yet.
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1.0, elapsed / Double(totalSeconds))
    }

    func toggle() {
        if isPlaying {
            pause()
        } else {
            Task { await play() }
        }
    }

    // MARK: Position

    /// Current playback position, preferring the decoder's own clock and
    /// falling back to wall time for files whose `currentTime` never moves
    /// (see `playedBeforeCurrentSegment`). Clamped to the server-reported
    /// length so the counter can't tick past the duration printed on the
    /// idle bubble.
    private var position: TimeInterval {
        let reported = audioPlayer?.currentTime ?? 0
        let value = reported > 0 ? reported : wallClockPosition
        guard totalSeconds > 0 else { return value }
        return min(value, Double(totalSeconds))
    }

    private var wallClockPosition: TimeInterval {
        guard let start = segmentStartedAt else { return playedBeforeCurrentSegment }
        return playedBeforeCurrentSegment + Date().timeIntervalSince(start)
    }

    /// Start timing a stretch of playback.
    private func beginPositionSegment() {
        segmentStartedAt = Date()
    }

    /// Fold the in-flight stretch into the accumulated total. Idempotent so
    /// a pause that races the coordinator's hand-off can't double-count.
    private func endPositionSegment() {
        guard let start = segmentStartedAt else { return }
        playedBeforeCurrentSegment += Date().timeIntervalSince(start)
        segmentStartedAt = nil
    }

    /// Rewind the readout to the top — used when the note finishes or is
    /// replayed from the start.
    private func resetPosition() {
        playedBeforeCurrentSegment = 0
        segmentStartedAt = nil
        elapsed = 0
    }

    // MARK: Internal

    private func play() async {
        // Re-ensure the AVAudioSession on every play — not just the
        // first one. The session is a process-wide singleton that
        // `VoiceNoteRecorder.cleanupRecorder()` deactivates after every
        // recording. If the user records new notes between plays,
        // a stale active player needs the session put back into
        // `.playback` + active state before its `play()` will produce
        // audio. Skipping this was the main "tap does nothing" path
        // for bubbles whose player had already been created.
        // Optimistically clear any prior failure — this attempt gets a
        // clean slate, and we only re-raise the flag if it fails again.
        loadFailed = false

        do {
            try ensureAudioSession()
        } catch {
            NSLog("[VoiceNote] msg=%@ ensureAudioSession failed: %@",
                  messageId, String(describing: error))
            loadFailed = true
            return
        }

        if audioPlayer == nil {
            do {
                audioPlayer = try await loadPlayer()
            } catch {
                // Expired presigned URL / non-2xx fetch / undecodable
                // audio all land here. Surface it so the bubble can show
                // a retry control instead of silently doing nothing.
                NSLog("[VoiceNote] msg=%@ loadPlayer failed url=%@ err=%@",
                      messageId, url.absoluteString, String(describing: error))
                loadFailed = true
                return
            }
        }
        guard let player = audioPlayer else { loadFailed = true; return }

        // AVAudioPlayer that has played to the end keeps `currentTime`
        // pinned at `duration` and `play()` becomes a no-op. The user
        // would see the play icon flip to pause with no audio. Rewind
        // explicitly so a second tap on a finished bubble restarts
        // playback from the top — the standard chat-bubble behaviour.
        //
        // The `duration > 0` guard matters for Opus-in-MP4, where the
        // decoder reports a duration of either 0 or a nonsense 35-hour
        // value and `currentTime` never leaves 0. Without it the "we're at
        // the end, rewind" test is true on *every* tap, so resuming a
        // paused note would snap the counter back to 0:00 while the audio
        // carried on from where it left off. Those files reach the top via
        // `audioPlayerDidFinishPlaying` instead, which rewinds explicitly.
        if !wasInterrupted, player.duration > 0,
           player.currentTime >= player.duration - 0.05 {
            player.currentTime = 0
            resetPosition()
        }
        wasInterrupted = false

        // Take the "now playing" slot before starting audio so any
        // bubble that was previously playing gets a `pauseFromCoordinator`
        // call and yields the foreground. Doing this *before* `play()`
        // keeps the AVAudioSession transitions deterministic — old
        // player pauses, new one starts, no overlap.
        VoiceNotePlaybackCoordinator.shared.setActivePlayer(self)

        // `play()` returns false when AVAudioPlayer couldn't begin —
        // e.g. session was deactivated by another component between
        // the `setActive(true)` above and now. Surface that as "not
        // playing" so the UI doesn't lie about the state.
        let started = player.play()
        if !started {
            NSLog("[VoiceNote] msg=%@ AVAudioPlayer.play() returned false (duration=%.2f currentTime=%.2f)",
                  messageId, player.duration, player.currentTime)
            isPlaying = false
            loadFailed = true
            VoiceNotePlaybackCoordinator.shared.clear(self)
            return
        }
        isPlaying = true
        beginPositionSegment()
        startTicker()
    }

    /// Adopt a freshly-minted presigned URL from a refreshed message
    /// list. No-op if unchanged. When it *does* change we drop the
    /// constructed `AVAudioPlayer` (it was bound to the old URL's bytes
    /// only via the on-disk cache; the cache is keyed by `messageId` so
    /// good bytes survive) and clear the failure flag so the next tap
    /// re-fetches against the new URL. This is what heals a player whose
    /// original presigned URL expired before it was ever played.
    func updateURL(_ newURL: URL) {
        guard newURL != url else { return }
        url = newURL
        // Only tear down the player if we don't yet have working audio —
        // never interrupt an in-flight playback for a URL refresh.
        if !isPlaying {
            audioPlayer = nil
            loadFailed = false
            // The next tap rebuilds the player from the new URL, so the
            // accumulated wall-clock position no longer describes anything.
            resetPosition()
        }
    }

    private func loadPlayer() async throws -> AVAudioPlayer {
        let data = try await fetchBytes()
        do {
            let player = try makeAudioPlayer(from: data)
            player.delegate = self
            player.prepareToPlay()
            return player
        } catch {
            // Cache was poisoned (e.g. an expired-URL error body written
            // by an older build). Drop it and try once more from network.
            NSLog("[VoiceNote] msg=%@ AVAudioPlayer(data:) init failed (%d bytes): %@ — refetching",
                  messageId, data.count, String(describing: error))
            try? FileManager.default.removeItem(at: cachedFile())
            let fresh = try await fetchBytes()
            let player = try makeAudioPlayer(from: fresh)
            player.delegate = self
            player.prepareToPlay()
            return player
        }
    }

    /// Builds an `AVAudioPlayer` from raw bytes, passing an explicit
    /// `fileTypeHint` of m4a/AAC.
    ///
    /// The voice recorder emits AAC inside an MP4 container (see
    /// `VoiceNoteRecorder`). `AVAudioPlayer(data:)` — with no hint —
    /// has to sniff the container from the bytes, and for these short
    /// AAC/MP4 clips it intermittently fails to recognise the format
    /// and throws `OSStatus -39 / 1954115647 ('fmt?')`. That error was
    /// being swallowed into the red retry icon, which is the bug the
    /// user kept hitting. Handing AVAudioPlayer the type hint up front
    /// removes the sniffing step and makes decode deterministic. We fall
    /// back to the hint-less initializer if the hinted one ever throws
    /// so a future non-m4a codec still gets a chance to play.
    private func makeAudioPlayer(from data: Data) throws -> AVAudioPlayer {
        do {
            return try AVAudioPlayer(data: data,
                                     fileTypeHint: AVFileType.m4a.rawValue)
        } catch {
            return try AVAudioPlayer(data: data)
        }
    }

    private func pause() {
        audioPlayer?.pause()
        isPlaying = false
        endPositionSegment()
        stopTicker()
        VoiceNotePlaybackCoordinator.shared.clear(self)
    }

    /// Called by the coordinator when another bubble starts playback.
    /// Same as a user-initiated pause, but does *not* clear the
    /// coordinator's `current` pointer — the coordinator is mid-handoff
    /// and is about to install the new player as `current`.
    fileprivate func pauseFromCoordinator() {
        audioPlayer?.pause()
        isPlaying = false
        endPositionSegment()
        stopTicker()
    }

    private func ensureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true, options: [])
    }

    private func fetchBytes() async throws -> Data {
        // On-disk cache hit — short-circuit the network. Voice notes
        // are short, expire when the message is deleted, and aren't
        // sensitive enough to need a SQLite-backed cache.
        let cachedURL = cachedFile()
        if let cached = try? Data(contentsOf: cachedURL), !cached.isEmpty {
            return cached
        }
        if isFetching {
            throw URLError(.cancelled)
        }
        isFetching = true
        defer { isFetching = false }
        let (data, response) = try await URLSession.shared.data(from: url)
        // The presigned URL has a 4h TTL. If it has expired (or any other
        // non-2xx response comes back), S3 returns an XML error body —
        // never write that to the cache or AVAudioPlayer will fail every
        // replay forever after.
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            NSLog("[VoiceNote] msg=%@ fetch HTTP %ld url=%@ body=%@",
                  messageId, http.statusCode, url.absoluteString, body)
            try? FileManager.default.removeItem(at: cachedURL)
            throw URLError(.badServerResponse)
        }
        NSLog("[VoiceNote] msg=%@ fetched %ld bytes, ctype=%@",
              messageId, data.count,
              (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "?")
        try? data.write(to: cachedURL)
        return data
    }

    private func cachedFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-cache-\(messageId).m4a")
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while let self, !Task.isCancelled, await self.isPlaying {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.elapsed = self.position
                }
            }
        }
    }

    private func stopTicker() {
        tickerTask?.cancel()
        tickerTask = nil
    }
}

extension VoiceNotePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer, successfully flag: Bool
    ) {
        Task { @MainActor in
            isPlaying = false
            resetPosition()
            stopTicker()
            // Rewind so the *next* tap restarts from the top without
            // having to allocate a new AVAudioPlayer. `play()` also
            // guards this, but doing it here keeps the player in a
            // clean state from the moment it stops.
            audioPlayer?.currentTime = 0
            VoiceNotePlaybackCoordinator.shared.clear(self)
        }
    }
}

// MARK: - Audio session interruption handling

extension VoiceNotePlayer {
    /// Subscribe to `AVAudioSession.interruptionNotification` so a phone
    /// call mid-playback doesn't leave every subsequent voice note
    /// silently failing. Without this, the session stays deactivated
    /// after the interruption ends and any bubble whose `audioPlayer`
    /// was already constructed sees `player.play()` no-op forever.
    private func registerInterruptionObserver() {
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard
                let info = note.userInfo,
                let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }
            // The notification is delivered on the main queue
            // (`queue: .main` above) but the closure isn't isolated to
            // the MainActor in the type system. Hop explicitly so the
            // mutations below are race-free.
            Task { @MainActor in
                self.handleInterruption(type: type, userInfo: info)
            }
        }
    }

    private func handleInterruption(
        type: AVAudioSession.InterruptionType,
        userInfo: [AnyHashable: Any]
    ) {
        switch type {
        case .began:
            // The OS has paused our audio and deactivated the session.
            // Reflect that in our own state so the UI shows the play
            // icon, and remember to resume — not restart — when the
            // interruption ends.
            if isPlaying {
                wasInterrupted = true
                isPlaying = false
                endPositionSegment()
                stopTicker()
            }
        case .ended:
            // Only resume if the system advises us to (e.g. the phone
            // call ended and we held the audio focus before it began).
            // We do *not* eagerly resume on every `.ended` — the user
            // may have moved focus to another app.
            guard
                wasInterrupted,
                let raw = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
            else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: raw)
            if options.contains(.shouldResume) {
                Task { await self.play() }
            } else {
                wasInterrupted = false
            }
        @unknown default:
            break
        }
    }
}

// MARK: - VoiceNoteBubble (SwiftUI)
//
// Play/pause button + progress bar + duration counter. Used by the
// chat bubble for VOICE messages. The bubble owns its `VoiceNotePlayer`
// via `@StateObject` so swiping or scrolling the view doesn't reset
// playback mid-listen.

struct VoiceNoteBubble: View {
    let url: URL
    let messageId: String
    let totalSeconds: Int
    let outgoing: Bool

    @StateObject private var player: VoiceNotePlayer

    init(url: URL, messageId: String, totalSeconds: Int, outgoing: Bool) {
        self.url = url
        self.messageId = messageId
        self.totalSeconds = totalSeconds
        self.outgoing = outgoing
        _player = StateObject(wrappedValue: VoiceNotePlayer(
            url: url, messageId: messageId, totalSeconds: totalSeconds))
    }

    var body: some View {
        // Whole bubble is the play/pause target — matches WhatsApp /
        // Telegram, and pins the hit-test region explicitly so a tap
        // here can't be misrouted to a neighbouring bubble's button by
        // SwiftUI's hit-test resolver after a fullScreenCover dismiss.
        Button { player.toggle() } label: {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(player.loadFailed
                                     ? Color.red.opacity(0.9)
                                     : (outgoing
                                        ? Color(red: 0.08, green: 0.06, blue: 0.04)
                                        : MyCoursesPalette.accent))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(outgoing
                                      ? Color(red: 0.08, green: 0.06, blue: 0.04).opacity(0.15)
                                      : Color.droobGold.opacity(0.18)))

                VStack(alignment: .leading, spacing: 4) {
                    progressBar
                    Text(formatDuration(currentSeconds))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(outgoing
                                         ? Color(red: 0.08, green: 0.06, blue: 0.04).opacity(0.7)
                                         : MyCoursesPalette.muted)
                }
                .frame(maxWidth: 160, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bubbleFill(outgoing: outgoing))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        // Adopt the freshly-minted presigned URL whenever the parent
        // re-renders this bubble with a new one (e.g. a message-list
        // refresh re-mints all attachment URLs). Heals players whose
        // captured URL expired before first play.
        .onChange(of: url) { newURL in
            player.updateURL(newURL)
        }
    }

    /// Failed → retry glyph; otherwise the usual play/pause toggle.
    private var iconName: String {
        if player.loadFailed { return "arrow.clockwise" }
        return player.isPlaying ? "pause.fill" : "play.fill"
    }

    /// Track + fill. The incoming fill is `accent`, not raw `.droobGold`:
    /// on the cream `surface` an incoming bubble sits on, #C6A96B measures
    /// about 1.8:1, so a 3pt bar sweeping across it was invisible in light
    /// mode — the played portion looked identical to the unplayed one. The
    /// outgoing bubble keeps its dark ink, which reads on the gold plate.
    /// Android's `VoiceNoteBubble` already draws this with `palette.accent`.
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(outgoing
                          ? Color(red: 0.08, green: 0.06, blue: 0.04).opacity(0.2)
                          : MyCoursesPalette.stroke)
                Capsule()
                    .fill(outgoing
                          ? Color(red: 0.08, green: 0.06, blue: 0.04)
                          : MyCoursesPalette.accent)
                    .frame(width: max(2, geo.size.width * CGFloat(player.progress)))
            }
        }
        .frame(height: 3)
    }

    private var currentSeconds: Int {
        // Mid-playback we show elapsed; idle we show total — same
        // pattern as WhatsApp / Telegram bubble.
        if player.isPlaying { return Int(player.elapsed.rounded()) }
        return player.elapsed > 0 ? Int(player.elapsed.rounded()) : totalSeconds
    }

    private func bubbleFill(outgoing: Bool) -> some ShapeStyle {
        if outgoing {
            return AnyShapeStyle(LinearGradient.droobBrand)
        } else {
            return AnyShapeStyle(MyCoursesPalette.surface)
        }
    }

    private func formatDuration(_ s: Int) -> String {
        let mins = s / 60
        let secs = s % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
