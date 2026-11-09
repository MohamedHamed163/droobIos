import SwiftUI

// MARK: - CameraConsentView
//
// Explicit, opt-in consent screen shown before the presence guard ever opens
// the front camera. Required for App Store / Play Store compliance: Apple
// scrutinizes continuous/always-on camera use heavily, so the justification
// here is precise about what runs, when, and what leaves the device (nothing).
//
// Declining is a first-class choice — the lesson still plays, protected by the
// always-on watermark. Only the camera-based checks are gated.

struct CameraConsentView: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    VStack(alignment: .leading, spacing: 16) {
                        bullet(icon: "video.fill",
                               title: L10n.presenceConsentBullet1Title,
                               body: L10n.presenceConsentBullet1Body)
                        bullet(icon: "bolt.slash.fill",
                               title: L10n.presenceConsentBullet2Title,
                               body: L10n.presenceConsentBullet2Body)
                        bullet(icon: "lock.shield.fill",
                               title: L10n.presenceConsentBullet3Title,
                               body: L10n.presenceConsentBullet3Body)
                        bullet(icon: "hand.raised.fill",
                               title: L10n.presenceConsentBullet4Title,
                               body: L10n.presenceConsentBullet4Body)
                    }

                    Spacer(minLength: 8)
                    buttons
                }
                .padding(24)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.droobGold.opacity(0.16))
                    .frame(width: 64, height: 64)
                Image(systemName: "eye.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
            }
            Text(L10n.presenceConsentTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
            Text(L10n.presenceConsentSubtitle)
                .font(.system(size: 14))
                .foregroundColor(MyCoursesPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    private func bullet(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(MyCoursesPalette.accent)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Text(body)
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: onAccept) {
                Text(L10n.presenceConsentAccept)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(LinearGradient.droobBrand)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onDecline) {
                Text(L10n.presenceConsentDecline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.plain)
        }
    }
}
