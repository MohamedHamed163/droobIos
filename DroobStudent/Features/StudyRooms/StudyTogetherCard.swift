import SwiftUI

/// "Study Together" card on the course detail screen.
///
/// Tapping the card joins the instructor-created room for the course
/// (idempotent) and opens its chat — students cannot create rooms, so
/// the copy here must stay join-only. Lives between the stats row and
/// the progress card on `CourseDetailView`.
///
/// Visually mirrors the design: large italic title, descriptive
/// subtitle, right-chevron, and a footer row with a small group icon
/// and a red live-dot for the "X rooms live now" badge.
struct StudyTogetherCard: View {
    let liveCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                Divider()
                    .background(MyCoursesPalette.accent.opacity(0.25))
                    .padding(.vertical, 12)
                liveRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color.droobGold.opacity(0.10),
                            Color.droobGold.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(MyCoursesPalette.accent.opacity(0.40), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: 14) {
            // Icon tile
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.droobGold.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MyCoursesPalette.accent.opacity(0.45), lineWidth: 1))
                Image(systemName: "person.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.studyTogetherTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(L10n.studyTogetherSubtitle)
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
        }
    }

    private var liveRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 16))
                .foregroundColor(MyCoursesPalette.accent.opacity(0.85))
                .frame(width: 32, height: 24)

            HStack(spacing: 6) {
                // Red live dot.
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text(liveCountText)
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            Spacer()
        }
    }

    private var liveCountText: String {
        // Pluralisation is deliberately simple — the iOS L10n layer
        // doesn't have a Plural helper yet, and 1-vs-many is the only
        // distinction the design needs.
        if liveCount == 1 {
            return L10n.studyTogetherOneRoomLive
        }
        return String(format: L10n.studyTogetherRoomsLive, liveCount)
    }
}

#if DEBUG
struct StudyTogetherCard_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            VStack(spacing: 20) {
                StudyTogetherCard(liveCount: 3, onTap: {})
                StudyTogetherCard(liveCount: 1, onTap: {})
                StudyTogetherCard(liveCount: 0, onTap: {})
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
