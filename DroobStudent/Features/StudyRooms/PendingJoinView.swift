import SwiftUI

/// Shown to the requester when joining a PRIVATE room ends up on the
/// host's waitlist. Mirrors the figma's calm "waiting" state — same
/// gold ring around the cover icon, but the spinner is replaced by a
/// static clock + waitlist count is suppressed (this view is the
/// requester's perspective, not the host's).
struct PendingJoinView: View {
    let roomName: String
    let courseTitle: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(MyCoursesPalette.accent.opacity(0.20), lineWidth: 1)
                        .frame(width: 140, height: 140)
                    // Dark cover tile in both themes — matches
                    // JoiningRoomView; keeps the gold glyph legible.
                    // Opaque so it stays dark over the light page.
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(StudyRoomChrome.coverPlate)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.droobGold.opacity(0.45),
                                        lineWidth: 1))
                        .frame(width: 72, height: 72)
                        .overlay(
                            Image(systemName: "clock.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.droobGold))
                }
                .padding(.bottom, 14)

                Text(L10n.studyRoomsPendingTitle)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)

                Text(subtitleText)
                    .font(.system(size: 14))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 2)

                Spacer()

                Button(action: onDismiss) {
                    Text(L10n.studyRoomsPendingNotifyMe)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Color.droobGold,
                                             Color.droobGold.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing)))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private var subtitleText: String {
        String(format: L10n.studyRoomsPendingSubtitleFmt,
               roomName)
    }
}
