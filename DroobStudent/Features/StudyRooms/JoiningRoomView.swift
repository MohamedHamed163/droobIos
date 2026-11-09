import SwiftUI

/// Transient loading screen between the user tapping Join (or
/// `joinByCode`) and the chat opening. Centred cover icon with a
/// gold rotating arc, room name + course on subtitle, and an inline
/// `Cancel` link that drops the user back to the room list.
struct JoiningRoomView: View {
    let roomName: String
    let courseTitle: String
    let onCancel: () -> Void

    @State private var spin: Double = 0

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                ZStack {
                    // Outer animated ring — gradient arc that spins
                    // around the cover icon.
                    Circle()
                        .trim(from: 0, to: 0.35)
                        .stroke(
                            LinearGradient(
                                colors: [MyCoursesPalette.accent,
                                         MyCoursesPalette.accent.opacity(0.0)],
                                startPoint: .leading,
                                endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2,
                                               lineCap: .round))
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(spin))
                        .onAppear {
                            withAnimation(
                                .linear(duration: 1.4)
                                    .repeatForever(autoreverses: false)) {
                                spin = 360
                            }
                        }
                    // Mid ring — static thin outline.
                    Circle()
                        .stroke(MyCoursesPalette.accent.opacity(0.20), lineWidth: 1)
                        .frame(width: 140, height: 140)

                    // Cover tile — deliberately dark in both themes so
                    // the gold glyph keeps its contrast. Opaque, not an
                    // alpha black: see StudyRoomChrome.coverPlate.
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(StudyRoomChrome.coverPlate)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.droobGold.opacity(0.45),
                                        lineWidth: 1))
                        .frame(width: 72, height: 72)
                        .overlay(
                            Image(systemName: "book.pages.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(.droobGold))
                }
                .padding(.bottom, 14)

                Text(L10n.studyRoomsJoiningTitle)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: onCancel) {
                    Text(L10n.studyRoomsCancel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.muted)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.top, 14)

                Spacer()
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private var subtitle: String {
        if courseTitle.isEmpty { return roomName }
        return bidiJoin(roomName, courseTitle)
    }
}
