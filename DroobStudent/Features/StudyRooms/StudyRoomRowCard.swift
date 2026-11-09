import SwiftUI

/// Public-rooms list card. Matches the Figma:
///   - cover tile
///   - time-since-last-activity ("23 min")
///   - room name (Fraunces italic)
///   - "Hosted by {host}"
///   - avatar stack + member count
///   - inline gold "Join" pill
///
/// The whole row is tappable (calls `onTap`); the Join pill calls
/// `onJoin`. Both lead to the same destination (the joining screen
/// → chat); kept separate so callers can attach analytics differently
/// later.
struct StudyRoomRowCard: View {
    let room: StudyRoomSummary
    var onTap: () -> Void
    var onJoin: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                topRow
                bottomRow
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(MyCoursesPalette.stroke,
                                    lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: 12) {
            // Cover tile
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.droobGold.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MyCoursesPalette.accent.opacity(0.40),
                                    lineWidth: 1))
                Image(systemName: "book.pages.fill")
                    .foregroundColor(MyCoursesPalette.accent)
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(relativeTime)
                    .font(.system(size: 11))
                    .foregroundColor(MyCoursesPalette.muted)
                Text(room.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(1)
                Text(String(format: L10n.studyRoomsHostedByFmt,
                            room.hostName))
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.muted)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 10) {
            AvatarStack(
                previews: room.memberPreviews,
                totalCount: room.participantCount,
                visibleLimit: 5,
                avatarSize: 22)
            Text(membersString)
                .font(.system(size: 12))
                .foregroundColor(MyCoursesPalette.muted)
            Spacer()
            if room.isMember {
                // Already in this room — open it rather than re-join.
                Button(action: onTap) {
                    Text(L10n.studyRoomsOpenAction)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MyCoursesPalette.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .stroke(MyCoursesPalette.accent.opacity(0.55),
                                        lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onJoin) {
                    Text(L10n.studyRoomsJoinAction)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(LinearGradient(
                                colors: [Color.droobGold,
                                         Color.droobGold.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var membersString: String {
        room.participantCount == 1
            ? L10n.studyRoomsRoomOneMember
            : String(format: L10n.studyRoomsRoomMembersFmt,
                     room.participantCount)
    }

    /// "23 min", "2 hr", "3 d", or "just now". Uses
    /// `lastMessageAt` when available — falls back to `createdAt` so
    /// brand-new rooms show "just now" instead of nothing.
    private var relativeTime: String {
        let anchor = room.lastMessageAt ?? room.createdAt
        let delta = Date().timeIntervalSince(anchor)
        if delta < 60 { return L10n.studyRoomsAgoNow }
        if delta < 3600 {
            return String(format: L10n.studyRoomsAgoMinFmt,
                          Int(delta / 60))
        }
        if delta < 86_400 {
            return String(format: L10n.studyRoomsAgoHourFmt,
                          Int(delta / 3600))
        }
        return String(format: L10n.studyRoomsAgoDayFmt,
                      Int(delta / 86_400))
    }
}
