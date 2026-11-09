import SwiftUI

/// Success screen shown right after a room is created.
///
/// Layout (mirrors Figma):
///   - Floating decorative shapes
///   - Big green check
///   - "Room is *Ready*" (italic accent on Ready)
///   - Subtitle — branches on privacy:
///       PUBLIC  → "{name} is now open. We'll let your friends in {course} know."
///       PRIVATE → "{name} is now open." (we don't tease a fan-out we
///                 can't actually do for a private invite-only room)
///   - Room card pill
///   - Primary CTA → push StudyRoomChatView
///   - Secondary CTA → present InviteSheet
struct RoomReadyView: View {
    let room: StudyRoomDetail
    let courseTitle: String

    @State private var showInvite: Bool = false
    @State private var enterChat: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            FloatingShapesBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 32)
                checkMark
                    .padding(.bottom, 28)

                title
                    .padding(.bottom, 8)
                subtitle
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)

                roomCard
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                enterButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                shareButton
                    .padding(.horizontal, 24)

                // Room-code chip below the buttons for PRIVATE rooms —
                // matches the figma where the code is reachable without
                // opening the invite sheet.
                if room.privacy == .private,
                   let code = room.joinCode, !code.isEmpty {
                    RoomCodeChip(rawCode: code)
                        .padding(.top, 14)
                }

                Spacer()
            }
            // Hidden nav link for "Enter the room".
            NavigationLink(isActive: $enterChat) {
                StudyRoomChatView(
                    roomId: room.roomId,
                    prefetchedRoom: room,
                    courseTitle: courseTitle,
                    // Leaving a room created here closes it (last member
                    // out). Unwind past this "Room is ready" screen too,
                    // otherwise the user is dropped back on a ready
                    // screen whose "Enter room" button re-opens a now-dead
                    // room. Dismiss *this* screen in a single operation:
                    // popping "Room is ready" also tears down the chat
                    // pushed from it, landing the user on the rooms list.
                    //
                    // An earlier version popped the chat first
                    // (`enterChat = false`) and then deferred `dismiss()`
                    // by one runloop tick. That deferred dismiss fired
                    // while the chat-pop animation was still in flight, so
                    // SwiftUI dropped it and the user stayed stranded on
                    // "Room is ready." Collapsing to one `dismiss()`
                    // removes the race entirely.
                    onLeaveRoom: { dismiss() })
            } label: { EmptyView() }
            .hidden()
        }
        // Hide the system back button so the custom chevron below
        // stands alone. Before this, `navigationBarBackButtonHidden(false)`
        // explicitly kept the default back control AND we added a
        // second custom one in `.topBarLeading`, producing two back
        // chevrons stacked in the same slot. The custom variant is
        // kept because the system back button renders in the default
        // tint and reads poorly against the gradient; the custom one
        // takes the palette's primary-text colour so it inverts with
        // the theme (was pinned white when the app was dark-only).
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(MyCoursesPalette.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showInvite) {
            inviteSheetContent
        }
    }

    // MARK: - Pieces

    private var checkMark: some View {
        ZStack {
            // Outer glow halo
            Circle()
                .fill(Color.green.opacity(0.15))
                .frame(width: 180, height: 180)
                .blur(radius: 30)
            Circle()
                .fill(Color.green.opacity(0.25))
                .frame(width: 130, height: 130)
            Circle()
                .fill(LinearGradient(
                    colors: [Color.green, Color.green.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 110, height: 110)
            Image(systemName: "checkmark")
                .font(.system(size: 50, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var title: some View {
        HStack(spacing: 8) {
            Text(L10n.studyRoomsReadyTitlePrefix)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)
            Text(L10n.studyRoomsReadyTitleSuffix)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(MyCoursesPalette.accent)
        }
    }

    private var subtitle: some View {
        Text(subtitleString)
            .font(.system(size: 14))
            .foregroundColor(MyCoursesPalette.muted)
            .multilineTextAlignment(.center)
    }

    private var subtitleString: String {
        switch room.privacy {
        case .public:
            return String(format: L10n.studyRoomsReadySubtitlePublicFmt,
                          room.name, courseTitle)
        case .private:
            return String(format: L10n.studyRoomsReadySubtitlePrivateFmt,
                          room.name)
        }
    }

    private var roomCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.droobGold.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MyCoursesPalette.accent.opacity(0.45),
                                    lineWidth: 1))
                Image(systemName: "book.pages.fill")
                    .foregroundColor(MyCoursesPalette.accent)
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(width: 48, height: 48)

            Text(room.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MyCoursesPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
        )
    }

    private var enterButton: some View {
        Button {
            enterChat = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(L10n.studyRoomsEnterRoom)
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.droobGold,
                                 Color.droobGold.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
            )
            .foregroundColor(.black)
        }
        .buttonStyle(.plain)
    }

    private var shareButton: some View {
        let isPrivate = room.privacy == .private
        return Button {
            showInvite = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPrivate
                      ? "paperplane.fill" : "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                // Private rooms read "Invite" (the verb fits the
                // codes-only sharing model); public rooms keep "Share"
                // since the link works for anyone.
                Text(isPrivate
                     ? L10n.studyRoomsInviteAction
                     : L10n.studyRoomsShare)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            )
            .foregroundColor(MyCoursesPalette.textPrimary)
        }
        .buttonStyle(.plain)
    }

    /// Wraps `InviteSheet` with detent + dark background. Split out
    /// so the iOS 16.0 vs 16.4 branch on `presentationBackground` lives
    /// in one place — see the `if #available` guard below.
    @ViewBuilder
    private var inviteSheetContent: some View {
        if #available(iOS 16.4, *) {
            InviteSheet(room: room)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(MyCoursesPalette.background)
        } else {
            // iOS 16.0–16.3 fall back to the default sheet background.
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                InviteSheet(room: room)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Decorative floaters

/// Static decorative shapes scattered behind the check mark — mirrors
/// the Figma reference. No animation in v1 — keeps the screen calm and
/// the focus on the green check.
private struct FloatingShapesBackground: View {
    var body: some View {
        ZStack {
            shape(.circle, color: .yellow.opacity(0.7), size: 8,
                  offset: CGSize(width: -120, height: -180))
            shape(.circle, color: .purple.opacity(0.8), size: 10,
                  offset: CGSize(width: 130, height: -140))
            shape(.circle, color: .green.opacity(0.8), size: 8,
                  offset: CGSize(width: 170, height: -90))
            shape(.square, color: .blue.opacity(0.9), size: 16,
                  offset: CGSize(width: -90, height: -50))
            shape(.square, color: .orange.opacity(0.9), size: 10,
                  offset: CGSize(width: -150, height: 60))
        }
    }

    enum ShapeKind { case circle, square }

    @ViewBuilder
    private func shape(_ kind: ShapeKind, color: Color, size: CGFloat,
                       offset: CGSize) -> some View {
        Group {
            switch kind {
            case .circle:
                Circle().fill(color)
            case .square:
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .rotationEffect(.degrees(-20))
            }
        }
        .frame(width: size, height: size)
        .offset(offset)
    }
}
