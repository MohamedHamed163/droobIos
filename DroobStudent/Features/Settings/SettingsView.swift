import SwiftUI

// MARK: - Settings (1.4)
//
// Hub reached from the Profile tab. Groups the account destinations
// (Notifications, Security, Payments, Language), the two global playback
// preferences (dark mode + autoplay), and the support entry point. Most
// rows reuse screens that already exist; this view is the navigation spine
// the Figma redesign introduces between Profile and those leaves.

struct SettingsView: View {
    @AppStorage("appLocale") private var storedLocale: String = AppLocaleDefault.code
    @AppStorage(AppColorSchemeDefault.storageKey)
    private var appColorScheme: String = AppColorSchemeDefault.code
    @ObservedObject private var prefs = PlaybackPreferences.shared

    @State private var showDetectionTest = false

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsScreenHeader(title: L10n.settingsTitle)
                        .padding(.top, 4)
                    accountSection
                    preferencesSection
                    supportSection
                    if !CaptureProtectionEnvironment.isProduction {
                        detectionTestSection
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showDetectionTest) {
            PresenceGuardTestView()
        }
    }

    // MARK: - DETECTION TEST (Debug + TestFlight only; hidden in App Store)

    private var detectionTestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Localized, not left in English: `isProduction` is false on
            // TestFlight too, so real students see this section.
            SettingsSectionLabel(text: L10n.settingsDeveloperSection)
            SettingsCard {
                Button {
                    showDetectionTest = true
                } label: {
                    ProfileNavRow(
                        icon: "wrench.and.screwdriver.fill",
                        title: L10n.settingsTestDetection,
                        subtitle: nil)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - ACCOUNT

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(text: L10n.settingsAccountSection)
            SettingsCard {
                navRow(icon: "bell.fill", title: L10n.settingsNotifications) {
                    NotificationsView()
                }
                SettingsRowDivider()
                navRow(icon: "shield.fill", title: L10n.settingsSecurity) {
                    SecurityView()
                }
                SettingsRowDivider()
                // The destination is NOT only the UI-language picker: it also
                // owns the video *caption track* preferences, which are a
                // separate axis and stay useful in an Arabic-only app. So while
                // `englishHidden` is on the row is re-labelled to what it
                // actually still does rather than removed — deleting it would
                // strand the subtitle toggle with no way in. Flip the flag and
                // the globe and the language name come straight back.
                NavigationLink {
                    LanguageView()
                } label: {
                    ProfileNavRow(
                        icon: AppLocaleDefault.englishHidden ? "captions.bubble.fill" : "globe",
                        title: AppLocaleDefault.englishHidden
                            ? L10n.settingsSubtitles
                            : L10n.settingsLanguage,
                        subtitle: AppLocaleDefault.englishHidden
                            ? (prefs.subtitleLanguage == "ar" ? L10n.arabic : L10n.english)
                            : (storedLocale == "ar" ? L10n.arabic : L10n.english))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - PREFERENCES

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(text: L10n.settingsPreferencesSection)
            SettingsCard {
                // The app ships light and follows only this choice, never the
                // device appearance. Writing the key re-resolves every adaptive
                // token app-wide through `.preferredColorScheme` at the root, so
                // nothing else needs to observe it.
                SettingsToggleRow(
                    icon: "moon.fill",
                    title: L10n.settingsDarkMode,
                    subtitle: nil,
                    isOn: Binding(
                        get: { appColorScheme == "dark" },
                        set: { appColorScheme = $0 ? "dark" : "light" }),
                    onChange: { _ in })
                SettingsRowDivider()
                SettingsToggleRow(
                    icon: "bolt.fill",
                    title: L10n.settingsAutoplay,
                    subtitle: nil,
                    isOn: $prefs.autoplayNextLesson,
                    onChange: { _ in })
            }
        }
    }

    // MARK: - SUPPORT

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(text: L10n.settingsSupportSection)
            SettingsCard {
                navRow(icon: "questionmark.circle.fill", title: L10n.settingsHelpSupport) {
                    HelpSupportView()
                }
            }
        }
    }

    // MARK: - Helper

    private func navRow<Destination: View>(
        icon: String,
        title: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            ProfileNavRow(icon: icon, title: title, subtitle: nil)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
