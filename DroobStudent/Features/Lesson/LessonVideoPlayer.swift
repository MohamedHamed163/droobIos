import SwiftUI
import AVFoundation
import AVKit

// MARK: - Custom video player with Figma-accurate controls
//
// The native SwiftUI `VideoPlayer` doesn't let us style the transport bar,
// so we drive an AVPlayer directly via an AVPlayerLayer-backed UIView and
// draw the controls in SwiftUI on top. This is the unit the lesson screen
// embeds in place of `VideoPlayer(player:)`.
//
// Behavior matches the Figma:
//   • centered play/pause button (gold tint, dark glyph)
//   • bottom row: prev, play/pause, next, current/total time, 1× speed, gear,
//     fullscreen toggle
//   • tap anywhere to toggle the controls overlay
//   • controls auto-hide after 3 s of inactivity while playing
//
// Prev / next are surfaced as closures so the parent (LessonPlayerView) can
// route them through its own navigation/sibling-lesson lookup.

struct LessonVideoPlayer: View {
    let player: AVPlayer
    /// Lesson id the player is for. Used to read/write per-lesson playback
    /// preferences (speed, quality cap) so the in-player quick chip stays
    /// in sync with the Playback Settings screen.
    let lessonId: String
    var onPrevLesson: (() -> Void)? = nil
    var onNextLesson: (() -> Void)? = nil
    /// Timestamps (in whole seconds) at which the student has notes anchored.
    /// Renders YouTube-style dots on the scrubber so notes are reachable from
    /// the timeline. Out-of-range values (negative or > duration) are clipped.
    var noteTimestamps: [Int] = []
    /// Currently "active" note timestamp — the one whose ±10s window the
    /// playhead is inside. Drawn larger with a blue ring so it stands out
    /// against the gold dots.
    var activeNoteTimestamp: Int? = nil
    /// Tapped a marker. Host decides whether to also resume playback after the
    /// seek; this view only emits the intent.
    var onSeekToTimestamp: ((Int) -> Void)? = nil
    /// Host callback that pushes PlaybackSettingsView.
    ///
    /// The gear that used to invoke this is **hidden for now** — the transport
    /// row exposes quality directly instead (see `LessonVideoControls`). The
    /// hook and the settings screen are both left intact so restoring the gear
    /// is a one-button change; nothing else in the player reads it today.
    var onOpenSettings: (() -> Void)? = nil
    /// Whether the loaded stream actually has renditions to switch between.
    /// Progressive MP4 has none, so the quality chip greys out rather than
    /// pretending the pick does something.
    var qualitySelectable: Bool = true
    /// Whether the host is currently showing the video full-screen. Only
    /// drives the expand/collapse glyph — layout is the host's job.
    var isFullscreen: Bool = false
    /// Tapped the fullscreen toggle in the transport row. Host owns the
    /// expansion + orientation change; the player only emits the intent.
    var onToggleFullscreen: (() -> Void)? = nil

    @State private var controlsVisible: Bool = true
    @State private var hideWorkItem: DispatchWorkItem? = nil

    var body: some View {
        ZStack {
            // Screenshot redaction is applied app-wide at the root
            // (DroobStudentApp → .screenshotRedacted()), so the video — like
            // every other screen — is already excluded from still captures.
            // We don't wrap it again here (nesting two secure canvases on the
            // AVPlayerLayer is unnecessary and risky).
            PlayerLayerView(player: player)
                .ignoresSafeArea(.container, edges: .horizontal)

            // Tap surface — separate from controls so a tap on a button
            // doesn't bleed into the overlay-toggle.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }

            if controlsVisible {
                LessonVideoControls(
                    player: player,
                    lessonId: lessonId,
                    onPrevLesson: onPrevLesson,
                    onNextLesson: onNextLesson,
                    noteTimestamps: noteTimestamps,
                    activeNoteTimestamp: activeNoteTimestamp,
                    onSeekToTimestamp: onSeekToTimestamp,
                    onOpenSettings: onOpenSettings,
                    qualitySelectable: qualitySelectable,
                    isFullscreen: isFullscreen,
                    onToggleFullscreen: onToggleFullscreen,
                    onAnyInteraction: scheduleAutoHide
                )
                .transition(.opacity)
            }
        }
        .background(Color.black)
        .onAppear { scheduleAutoHide() }
        // Anti-recording watermark — RE-ENABLED. Drifting, semi-transparent
        // account label so any off-screen recording carries the leaker's
        // identity. Never hit-tests, never touches the camera, never
        // interrupts playback.
        //
        // The *rest* of ViewerPresenceGuard stays disabled (2026-07-24, per
        // request): the front-camera face-presence checks and the
        // phone/recording-device detection that paused behind a recoverable
        // overlay. Those need camera consent and can interrupt a lesson; the
        // watermark is the zero-cost, zero-permission half of the same
        // defense, so it runs standalone here instead of via
        // `.viewerPresenceGuard(...)`. To bring the camera layers back,
        // swap this overlay for that modifier. See ViewerPresenceGuard.
        .overlay {
            PresenceWatermark(
                label: watermarkLabel,
                opacity: watermarkOpacity,
                moveInterval: PresenceGuardConfig.smooth.watermarkMoveIntervalSec,
                fontSize: watermarkFontSize
            )
        }
        // Capture/mirroring/QuickTime-USB blanks the video; also pause so the
        // audio track isn't recorded under the black overlay. (KEPT — this is
        // part of the screen-recording block.)
        .pausePlaybackWhenCaptured(player)
    }

    // MARK: - Watermark

    /// Account label burned into the watermark: email first, then the user
    /// id, then a neutral fallback so the mark is never blank.
    private var watermarkLabel: String {
        AuthSession.shared.currentUser?.email
            ?? AuthSession.shared.currentUser?.userId
            ?? "Droob"
    }

    /// Fullscreen is when a phone gets pointed at the screen, so the mark
    /// gets appreciably louder there — roughly double the configured inline
    /// opacity. Inline playback keeps the spec's subtle 15–25% band, where a
    /// heavier mark would just sit in the way of a 260pt-tall video.
    private var watermarkOpacity: Double {
        let base = PresenceGuardConfig.smooth.watermarkOpacity
        return isFullscreen ? min(base * 2.0, 0.4) : base
    }

    /// Same reasoning applied to type size: a landscape frame is several
    /// times the area of the inline one, so the inline 13pt would read as a
    /// speck (and crop out of a re-recording) at fullscreen size.
    private var watermarkFontSize: CGFloat { isFullscreen ? 22 : 13 }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.18)) { controlsVisible.toggle() }
        if controlsVisible { scheduleAutoHide() }
    }

    private func scheduleAutoHide() {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem {
            // Only auto-hide while playing — when paused the user wants the
            // controls present.
            if player.timeControlStatus == .playing {
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
    }
}

// MARK: - PlayerLayer wrapper

/// AVPlayerLayer-backed UIView so we get the raw video surface without
/// AVKit's built-in controls. `aspectFit` letterboxes — the Figma's video
/// area is 16:9 letterboxed on top of a black background, which is what
/// AVPlayerLayer + a black parent yields.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerHostView {
        let v = PlayerHostView()
        v.playerLayer.videoGravity = .resizeAspect
        v.playerLayer.player = player
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerHostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Controls overlay

private struct LessonVideoControls: View {
    let player: AVPlayer
    let lessonId: String
    var onPrevLesson: (() -> Void)?
    var onNextLesson: (() -> Void)?
    var noteTimestamps: [Int]
    var activeNoteTimestamp: Int?
    var onSeekToTimestamp: ((Int) -> Void)?
    var onOpenSettings: (() -> Void)?
    var qualitySelectable: Bool = true
    var isFullscreen: Bool
    var onToggleFullscreen: (() -> Void)?
    var onAnyInteraction: () -> Void

    /// Shared store so this in-overlay control writes through to the same
    /// state the Playback Settings screen reads. We observe it via
    /// `@ObservedObject` so a change made on the settings screen (e.g. the
    /// student picks 1.5×) immediately updates the chip label too.
    @ObservedObject private var prefs = PlaybackPreferences.shared

    @State private var isPlaying: Bool = false
    @State private var currentSeconds: Double = 0
    @State private var totalSeconds: Double = 0
    @State private var isScrubbing: Bool = false
    @State private var playbackRate: Float = 1.0
    @State private var showSpeedMenu: Bool = false
    @State private var timeObserverToken: Any? = nil
    @State private var rateObservation: NSKeyValueObservation? = nil
    @State private var statusObservation: NSKeyValueObservation? = nil

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    /// Presets offered in the quality menu. Deliberately the same three rows
    /// PlaybackSettingsView shows: `.auto` is a stored value, never an offered
    /// option, because the ladder it settles on is the 720p one.
    private let qualityOptions: [PlaybackQuality] = [.low480p, .high720p, .ultra1080p]

    private var selectedQuality: PlaybackQuality { prefs.quality(forLesson: lessonId) }

    /// Same rule as `PlaybackSettingsView.matchesSelectedQuality` — treat
    /// `.auto` as the recommended 720p row so the menu is never checkmark-less.
    private func matchesSelectedQuality(_ q: PlaybackQuality) -> Bool {
        selectedQuality == .auto ? q == .high720p : q == selectedQuality
    }

    private func qualityLabel(_ q: PlaybackQuality) -> String {
        switch q {
        case .low480p:         return L10n.playbackSettingsQualityLow
        case .ultra1080p:      return L10n.playbackSettingsQualityHigh
        case .high720p, .auto: return L10n.playbackSettingsQualityMed
        }
    }

    /// Chip text. Bare numerals read the same in both locales, so unlike the
    /// menu rows this needs no key.
    private func qualityShortLabel(_ q: PlaybackQuality) -> String {
        switch q {
        case .low480p:         return "480p"
        case .ultra1080p:      return "1080p"
        case .high720p, .auto: return "720p"
        }
    }

    private func applyQuality(_ q: PlaybackQuality) {
        onAnyInteraction()
        prefs.setQuality(q, forLesson: lessonId)
    }

    var body: some View {
        ZStack {
            // Dim layer for legibility on bright frames.
            LinearGradient(
                colors: [Color.black.opacity(0.35), .clear, Color.black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )

            VStack {
                Spacer()

                // Centered play/pause
                Button {
                    onAnyInteraction()
                    togglePlay()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                        .frame(width: 76, height: 76)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .overlay(
                            // Inner gold disc (matches Figma central button).
                            // Gold as a FILL with dark ink on top, so it is
                            // correct in both color schemes and stays put —
                            // it sits on the video's own black plate, which
                            // never flips with the app's appearance.
                            Circle()
                                .fill(Color.droobGold)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                                )
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                // Scrubber
                scrubBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                // Transport row
                transportRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
            }
        }
        .onAppear {
            attachObservers()
            isPlaying = player.timeControlStatus == .playing
            updateTotal()
            // Sync the local chip + the AVPlayer to the persisted speed for
            // this lesson. If the player resumed mid-playback we restore
            // the rate so the student keeps watching at their chosen speed.
            let stored = prefs.speed(forLesson: lessonId)
            playbackRate = stored
            if isPlaying { player.rate = stored }
        }
        .onChange(of: prefs.speed(forLesson: lessonId)) { newRate in
            // Settings screen wrote a new speed — mirror it onto the chip
            // and the AVPlayer in real time.
            playbackRate = newRate
            if isPlaying { player.rate = newRate }
        }
        .onDisappear { detachObservers() }
    }

    private var scrubBar: some View {
        // YouTube-style track: the native SwiftUI Slider sits underneath, and
        // a non-interactive marker overlay decorates it with dots at note
        // timestamps. Marker hit-testing is enabled only on the dot circles
        // themselves (small targets) so most of the bar still routes drags
        // to the slider — letting students scrub freely without "snapping"
        // to nearby notes.
        VStack(spacing: 4) {
            ZStack {
                Slider(
                    value: Binding(
                        get: { currentSeconds },
                        set: { newVal in
                            isScrubbing = true
                            currentSeconds = newVal
                        }
                    ),
                    in: 0...max(totalSeconds, 0.1),
                    onEditingChanged: { editing in
                        onAnyInteraction()
                        if !editing {
                            seek(to: currentSeconds)
                            isScrubbing = false
                        }
                    }
                )
                .tint(Color.droobGold)

                if !noteTimestamps.isEmpty, totalSeconds > 0 {
                    noteMarkers
                        .allowsHitTesting(true)
                }
            }
            .frame(height: 30)
        }
    }

    /// Note-timestamp dots positioned over the slider. Each dot fires
    /// `onSeekToTimestamp` so the host can seek + auto-play. The active
    /// timestamp (i.e. the one inside the playhead's ±10s window) is drawn
    /// larger with a blue ring so it reads as the "you are here" marker.
    private var noteMarkers: some View {
        GeometryReader { geo in
            // Slider draws a thin track with horizontal insets for its thumb;
            // approximating that inset keeps markers aligned to the visual
            // track instead of the full bar width.
            let trackInset: CGFloat = 14
            let usable = max(geo.size.width - trackInset * 2, 1)
            ZStack(alignment: .leading) {
                ForEach(uniqueClampedTimestamps, id: \.self) { ts in
                    let fraction = min(max(Double(ts) / totalSeconds, 0), 1)
                    let isActive = activeNoteTimestamp == ts
                    Circle()
                        .fill(Color.droobGold)
                        .frame(width: isActive ? 12 : 7, height: isActive ? 12 : 7)
                        .overlay(
                            Group {
                                if isActive {
                                    Circle()
                                        .stroke(Color.blue, lineWidth: 2)
                                        .frame(width: 16, height: 16)
                                }
                            }
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
                        .contentShape(Circle().inset(by: -6))   // expand tap target
                        .position(
                            x: trackInset + CGFloat(fraction) * usable,
                            y: geo.size.height / 2
                        )
                        .onTapGesture {
                            onAnyInteraction()
                            onSeekToTimestamp?(ts)
                        }
                }
            }
        }
    }

    /// Deduplicated + sorted, with negatives and any value past the duration
    /// dropped so we never draw a marker off the end of the bar.
    private var uniqueClampedTimestamps: [Int] {
        guard totalSeconds > 0 else { return [] }
        let maxTs = Int(totalSeconds.rounded(.down))
        return Array(Set(noteTimestamps.filter { $0 >= 0 && $0 <= maxTs })).sorted()
    }

    private var transportRow: some View {
        // Spacing is tighter than the pre-fullscreen design (was 14) so the
        // six controls + time still fit on 375-pt-wide phones.
        HStack(spacing: 8) {
            transportButton("backward.end.fill") {
                onPrevLesson?()
            }
            .disabled(onPrevLesson == nil)
            .opacity(onPrevLesson == nil ? 0.4 : 1)

            transportButton(isPlaying ? "pause.fill" : "play.fill") {
                togglePlay()
            }

            transportButton("forward.end.fill") {
                onNextLesson?()
            }
            .disabled(onNextLesson == nil)
            .opacity(onNextLesson == nil ? 0.4 : 1)

            // Elapsed / total. Two all-digit operands around a neutral "/", so
            // the Arabic paragraph would swap them and show the total first.
            // The isolate goes around the whole pair — there is no strong
            // character inside, so it resolves LTR.
            Text("\(formatTime(currentSeconds)) / \(formatTime(totalSeconds))".bidiIsolated)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .center)

            Menu {
                ForEach(speeds, id: \.self) { rate in
                    Button {
                        applyRate(rate)
                    } label: {
                        HStack {
                            Text(String(format: "%g×", rate))
                            if abs(playbackRate - rate) < 0.001 {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(String(format: "%g×", playbackRate))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 30)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .onTapGesture { onAnyInteraction() }

            // Quality picker. Replaces the old gear: settings are hidden for
            // now, and quality was the only thing in there that had no other
            // home (speed is the chip to the left, autoplay and subtitles both
            // live in app Settings).
            Menu {
                ForEach(qualityOptions) { q in
                    Button {
                        applyQuality(q)
                    } label: {
                        HStack {
                            Text(qualityLabel(q))
                            if matchesSelectedQuality(q) {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(qualityShortLabel(selectedQuality))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 30)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .onTapGesture { onAnyInteraction() }
            .disabled(!qualitySelectable)
            .opacity(qualitySelectable ? 1 : 0.5)
            .accessibilityLabel(L10n.playbackSettingsQuality)

            Button {
                onAnyInteraction()
                onToggleFullscreen?()
            } label: {
                Image(systemName: isFullscreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 30)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(onToggleFullscreen == nil)
            .opacity(onToggleFullscreen == nil ? 0.5 : 1)
        }
    }

    private func transportButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            onAnyInteraction()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 38, height: 30)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Player control

    private func togglePlay() {
        if isPlaying { player.pause() } else {
            player.play()
            // Re-apply playback rate after resume — AVPlayer resets the rate
            // when playback finishes and starts over.
            player.rate = playbackRate
        }
    }

    private func seek(to seconds: Double) {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            // Restore rate after seek (seeks pause the rate).
            if isPlaying { player.rate = playbackRate }
        }
    }

    private func applyRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player.rate = rate }
        // Write through to the shared store so the Playback Settings screen
        // shows the same value on next open. Persists per-lesson.
        prefs.setSpeed(rate, forLesson: lessonId)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, !seconds.isNaN else { return "0:00" }
        let total = Int(seconds.rounded())
        let mm = total / 60
        let ss = total % 60
        return String(format: "%d:%02d", mm, ss)
    }

    // MARK: - Observers

    private func attachObservers() {
        // Time observer — coarse 0.2 s tick is plenty for a smooth seek bar
        // and far cheaper than CADisplayLink-frequency updates.
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isScrubbing else { return }
            currentSeconds = CMTimeGetSeconds(time)
            updateTotal()
        }
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { p, _ in
            Task { @MainActor in
                isPlaying = p.timeControlStatus == .playing
            }
        }
        statusObservation = player.observe(\.currentItem?.status, options: [.new]) { p, _ in
            Task { @MainActor in updateTotal() }
        }
    }

    private func detachObservers() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        rateObservation?.invalidate(); rateObservation = nil
        statusObservation?.invalidate(); statusObservation = nil
    }

    private func updateTotal() {
        if let dur = player.currentItem?.duration, dur.isNumeric {
            let secs = CMTimeGetSeconds(dur)
            if secs.isFinite, secs > 0 { totalSeconds = secs }
        }
    }
}
