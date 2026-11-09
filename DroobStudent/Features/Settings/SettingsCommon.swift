import SwiftUI

// MARK: - Shared dark-theme settings primitives matching Figma frames.

struct SettingsScreenHeader: View {
    let title: String
    var showsBack: Bool = true
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLocale") private var storedLocale: String = AppLocaleDefault.code

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if showsBack {
                    Button {
                        dismiss()
                    } label: {
                        // Plain chevron (no circle) on its own row above the
                        // title, per Figma 419-7063. `chevron.backward`
                        // auto-mirrors in RTL — unlike `chevron.left`.
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.textPrimary)
                            .frame(width: 28, height: 28, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                Text(title)
                    .font(BrandFont.displaySemiBold(size: 30, isArabic: storedLocale == "ar"))
                    .tracking(storedLocale == "ar" ? 0 : -1.36)
                    // Every settings screen title is gold on the page
                    // background. `AuthFigmaColors.gold` is the fixed
                    // dark-mode value and vanishes on the light page, so the
                    // title takes the adaptive ink ramp.
                    .foregroundColor(MyCoursesPalette.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Section eyebrow ("LEARNING", "ACCOUNT", "SECURITY").
struct SettingsSectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.0)
            .foregroundColor(MyCoursesPalette.muted)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One toggle row with optional leading icon, title and subtitle.
struct SettingsToggleRow: View {
    let icon: String?
    /// Matches `ProfileNavRow`: the tile is an 18% wash on the card surface,
    /// so its glyph is gold ink and takes the accent ramp.
    var iconBg: Color = MyCoursesPalette.accent.opacity(0.18)
    var iconTint: Color = MyCoursesPalette.accent
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconBg)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(iconTint)
                }
                .frame(width: 34, height: 34)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(MyCoursesPalette.muted)
                }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                // The "on" track has to be told apart from the card it sits
                // on: #C6A96B on the light card surface is ~1.4:1, which
                // reads as "off". The accent ramp keeps the on-state legible
                // (and is unchanged in dark).
                .tint(MyCoursesPalette.accent)
                .onChange(of: isOn) { newValue in onChange(newValue) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Wraps a list of rows in a single dark card with separators.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(MyCoursesPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(MyCoursesPalette.stroke)
            .frame(height: 1)
            .padding(.leading, 14)
    }
}
