import SwiftUI

// MARK: - PlaybackSettingsView
//
// Figma-accurate Playback Settings screen, pushed onto the lesson player's
// navigation stack when the student taps the gear icon in the video
// controls. Three sections:
//
//   • SPEED         — six radio rows (0.5×–2×). Per-lesson.
//   • VIDEO QUALITY — three radio rows (480p / 720p HD / 1080p Full HD)
//                     plus an implicit "Auto" baseline that's the default
//                     when the user has never touched the row. Per-lesson.
//                     Only meaningful for an adaptive (HLS) stream — a
//                     lesson served as a single progressive MP4 has no
//                     renditions to choose from, so the host passes
//                     `qualitySelectable: false` and the rows go inert
//                     rather than pretending to do something.
//   • OPTIONS       — Autoplay next lesson + Subtitles toggles. Global
//                     (apply to every lesson).
//
// Subtitles ride on the legible AVMediaSelection tracks the HLS manifest now
// advertises (the backend injects #EXT-X-MEDIA SUBTITLES renditions), so the
// toggle is live. A lesson with no uploaded VTT simply has an empty legible
// group and the toggle becomes a no-op for that video.

struct PlaybackSettingsView: View {
    let lessonId: String
    let lessonTitle: String

    @ObservedObject var prefs: PlaybackPreferences
    /// Whether this lesson's stream actually has multiple renditions. `true`
    /// for HLS (and for any caller that doesn't know — the historical case);
    /// `false` for a single-file MP4, where the rows are shown greyed with an
    /// explanatory footer instead of silently doing nothing.
    var qualitySelectable: Bool = true

    @Environment(\.dismiss) private var dismiss

    /// Caption tracks now flow through the HLS manifest, so the subtitle
    /// toggle is enabled. Per-lesson availability is handled gracefully at
    /// playback time (a lesson without a VTT just has nothing to select).
    private let subtitlesAvailable: Bool = true

    @State private var selectedSpeed: Float = 1.0
    @State private var selectedQuality: PlaybackQuality = .auto

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    speedSection
                    qualitySection
                    optionsSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            selectedSpeed = prefs.speed(forLesson: lessonId)
            selectedQuality = prefs.quality(forLesson: lessonId)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "< Settings" back affordance. The label reads as the previous
            // screen in iOS convention; here it labels the *destination* of
            // the chevron, matching the Figma copy verbatim.
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text(L10n.playbackSettingsBackLabel)
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(MyCoursesPalette.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.playbackSettingsTitle)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(MyCoursesPalette.accent)
                Text("(\(lessonTitle))")
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
            }
        }
    }

    // MARK: - Speed

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow(L10n.playbackSettingsSpeed)
            groupedCard {
                ForEach(Array(PlaybackPreferences.speedOptions.enumerated()), id: \.offset) { idx, rate in
                    radioRow(
                        title: speedLabel(rate),
                        checked: abs(selectedSpeed - rate) < 0.001,
                        showDivider: idx < PlaybackPreferences.speedOptions.count - 1
                    ) {
                        selectedSpeed = rate
                        prefs.setSpeed(rate, forLesson: lessonId)
                    }
                }
            }
            sectionFooter(L10n.playbackSettingsSpeedFooter)
        }
    }

    private func speedLabel(_ rate: Float) -> String {
        // "0.75×" / "1×" / "1.25×" — strip the trailing .0 for whole numbers.
        let s = (rate.truncatingRemainder(dividingBy: 1) == 0)
            ? String(format: "%.0f", rate)
            : String(format: "%g", rate)
        return "\(s)×"
    }

    // MARK: - Quality

    private var qualitySection: some View {
        let options: [(PlaybackQuality, String, String)] = [
            (.low480p,    L10n.playbackSettingsQualityLow,    L10n.playbackSettingsQualityLowSub),
            (.high720p,   L10n.playbackSettingsQualityMed,    L10n.playbackSettingsQualityMedSub),
            (.ultra1080p, L10n.playbackSettingsQualityHigh,   L10n.playbackSettingsQualityHighSub),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow(L10n.playbackSettingsQuality)
            groupedCard {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                    let (q, title, sub) = opt
                    qualityRow(
                        title: title,
                        subtitle: sub,
                        checked: qualitySelectable && matchesSelectedQuality(q),
                        enabled: qualitySelectable,
                        showDivider: idx < options.count - 1
                    ) {
                        selectedQuality = q
                        prefs.setQuality(q, forLesson: lessonId)
                    }
                }
            }
            sectionFooter(qualitySelectable
                          ? L10n.playbackSettingsQualityFooter
                          : L10n.playbackSettingsQualitySingle)
        }
    }

    /// Treat `.auto` as matching "720p HD" so the recommended row carries
    /// the checkmark on first open (matches the Figma's default state). A
    /// fresh setSpeed write upgrades the preference to .high720p anyway.
    private func matchesSelectedQuality(_ q: PlaybackQuality) -> Bool {
        switch selectedQuality {
        case .auto:        return q == .high720p
        default:           return q == selectedQuality
        }
    }

    // MARK: - Options (global)

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow(L10n.playbackSettingsOptions)
            groupedCard {
                toggleRow(
                    title: L10n.playbackSettingsAutoplay,
                    isOn: $prefs.autoplayNextLesson,
                    enabled: true,
                    showDivider: true
                )
                toggleRow(
                    title: L10n.playbackSettingsSubtitles,
                    isOn: $prefs.subtitlesEnabled,
                    enabled: subtitlesAvailable,
                    showDivider: false
                )
            }
            if !subtitlesAvailable {
                sectionFooter(L10n.playbackSettingsSubtitlesUnavailable)
            }
        }
    }

    // MARK: - Building blocks

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(MyCoursesPalette.muted)
            .tracking(0.8)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(MyCoursesPalette.muted)
            .padding(.top, 2)
    }

    @ViewBuilder
    private func groupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(MyCoursesPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MyCoursesPalette.stroke, lineWidth: 1)
            )
    }

    private func radioRow(
        title: String,
        checked: Bool,
        showDivider: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                if showDivider { Divider().overlay(MyCoursesPalette.stroke) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func qualityRow(
        title: String,
        subtitle: String,
        checked: Bool,
        enabled: Bool = true,
        showDivider: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(enabled ? .primary : MyCoursesPalette.muted)
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(MyCoursesPalette.muted)
                    }
                    Spacer()
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                if showDivider { Divider().overlay(MyCoursesPalette.stroke) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func toggleRow(
        title: String,
        isOn: Binding<Bool>,
        enabled: Bool,
        showDivider: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(enabled ? .primary : MyCoursesPalette.muted)
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(.green)
                    .disabled(!enabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if showDivider { Divider().overlay(MyCoursesPalette.stroke) }
        }
    }
}
