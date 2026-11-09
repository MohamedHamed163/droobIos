import SwiftUI

struct NotificationsView: View {
    @StateObject private var vm = NotificationsViewModel()

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    SettingsScreenHeader(title: L10n.notificationsScreenTitle)
                        .padding(.top, 4)

                    if vm.isLoading && vm.prefs == nil {
                        skeleton
                    } else if let prefs = vm.prefs {
                        learningSection(prefs: prefs)
                    } else if let err = vm.error {
                        ErrorBanner(message: err) { Task { await vm.load() } }
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.load() }
    }

    // MARK: - Sections

    /// The only section left. Lesson reminders, streak alerts and new-message
    /// toggles used to live here and under a SESSIONS & MESSAGES heading; as of
    /// 2026-08 the backend delivers nothing but course-content changes, so
    /// those switches controlled notifications that no longer exist. The prefs
    /// themselves are untouched server-side — restoring a kind is enough to
    /// bring its row back here.
    private func learningSection(prefs: NotificationPrefs) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(text: L10n.notificationsSectionLearning)
            SettingsCard {
                toggleRow(
                    title: L10n.notifCourseUpdates,
                    subtitle: L10n.notifCourseUpdatesSubtitle,
                    keyPath: \.courseUpdates,
                    initial: prefs.courseUpdates)
            }
        }
    }

    // MARK: - Helpers

    private func toggleRow(
        title: String,
        subtitle: String?,
        keyPath: WritableKeyPath<NotificationPrefs, Bool>,
        initial: Bool
    ) -> some View {
        ToggleRowBinding(
            title: title,
            subtitle: subtitle,
            initial: initial,
            onChange: { newValue in vm.toggle(keyPath, to: newValue) })
    }

    private var skeleton: some View {
        VStack(spacing: 16) {
            MCSkeletonBlock(height: 160, cornerRadius: 14)
            MCSkeletonBlock(height: 120, cornerRadius: 14)
            MCSkeletonBlock(height: 90, cornerRadius: 14)
        }
    }
}

/// Pulls toggle state into a binding so SettingsToggleRow's onChange fires
/// on user-initiated flips without re-firing every time prefs reload.
private struct ToggleRowBinding: View {
    let title: String
    let subtitle: String?
    let initial: Bool
    let onChange: (Bool) -> Void

    @State private var value: Bool

    init(title: String, subtitle: String?, initial: Bool, onChange: @escaping (Bool) -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.initial = initial
        self.onChange = onChange
        _value = State(initialValue: initial)
    }

    var body: some View {
        SettingsToggleRow(
            icon: nil,
            title: title,
            subtitle: subtitle,
            isOn: $value,
            onChange: onChange)
            .onChange(of: initial) { newValue in
                if newValue != value { value = newValue }
            }
    }
}
