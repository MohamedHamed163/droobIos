import SwiftUI

// MARK: - Language (1.4.3)
//
// App locale picker (Arabic only while `AppLocaleDefault.englishHidden` is on;
// writes the `appLocale` AppStorage) plus the global subtitle preferences.
// Subtitles are a separate axis — the *video caption track*, not the app UI
// language — so that menu still offers English. The subtitle rows feed
// PlaybackPreferences, which the lesson player reads when selecting a legible
// AVMediaSelection track.

struct LanguageView: View {
    @AppStorage("appLocale") private var storedLocale: String = AppLocaleDefault.code
    @ObservedObject private var prefs = PlaybackPreferences.shared

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsScreenHeader(
                        title: AppLocaleDefault.englishHidden
                            ? L10n.settingsSubtitles
                            : L10n.languageTitle)
                        .padding(.top, 4)
                    // The whole section goes, not just the English row: a radio
                    // list with one permanently-ticked option reads as a broken
                    // control, and leaving the section header behind would leave
                    // a labelled empty card. The screen becomes the subtitle
                    // preferences it also owns.
                    if !AppLocaleDefault.englishHidden {
                        languageSection
                    }
                    subtitlesSection
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - LANGUAGE

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(text: L10n.languageSectionLabel)
            SettingsCard {
                // Gated, not deleted: `AppLocaleDefault.englishHidden` is the
                // one flag that brings the English row (and its divider) back.
                if !AppLocaleDefault.englishHidden {
                    localeRow(code: "en", label: L10n.languageEnglishOption)
                    SettingsRowDivider()
                }
                localeRow(code: "ar", label: L10n.languageArabicOption)
            }
        }
    }

    private func localeRow(code: String, label: String) -> some View {
        Button {
            storedLocale = code
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Spacer()
                if storedLocale == code {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - SUBTITLES

    private var subtitlesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // With the language section gone this is the only group on the
            // screen and the screen title already says "Subtitles", so the
            // group label would just repeat it one line down.
            if !AppLocaleDefault.englishHidden {
                SettingsSectionLabel(text: L10n.languageSubtitlesSection)
            }
            SettingsCard {
                SettingsToggleRow(
                    icon: nil,
                    title: L10n.languageAutoShowSubtitles,
                    subtitle: L10n.languageAutoShowSubtitlesSubtitle,
                    isOn: $prefs.subtitlesEnabled,
                    onChange: { _ in })
                SettingsRowDivider()
                Menu {
                    Button(L10n.languageEnglishOption) { prefs.subtitleLanguage = "en" }
                    Button(L10n.languageArabicOption) { prefs.subtitleLanguage = "ar" }
                } label: {
                    HStack {
                        Text(L10n.languageSubtitleLanguage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.textPrimary)
                        Spacer()
                        Text(prefs.subtitleLanguage == "ar" ? L10n.arabic : L10n.english)
                            .font(.system(size: 13))
                            .foregroundColor(MyCoursesPalette.muted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.muted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .disabled(!prefs.subtitlesEnabled)
                .opacity(prefs.subtitlesEnabled ? 1 : 0.5)
            }
        }
    }
}
