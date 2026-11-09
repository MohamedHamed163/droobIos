import SwiftUI
import UIKit

/// Bottom sheet shown by the "Share" button on the success screen and
/// by "Invite classmates" inside a room.
///
/// v1 surface:
///   - Room card (icon + name) for context
///   - Pretty `ROOM LINK` row — deep linking lands later, the URL is a
///     client-derived slug for now so the user has something paste-worthy
///   - For PRIVATE rooms only — a `JOIN CODE` row with copy
///   - Trailing `Copy` button on each row; tapping flips the label to
///     "Copied" for a beat
struct InviteSheet: View {
    let room: StudyRoomDetail

    @State private var linkCopied: Bool = false
    @State private var codeCopied: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            roomCard
                .padding(.horizontal, 20)
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 16) {
                rowLabel(L10n.studyRoomsInviteRoomLinkLabel)
                copyableRow(
                    icon: "link",
                    text: prettyLink,
                    copied: $linkCopied,
                    toCopy: prettyLink)

                if room.privacy == .private, let code = room.joinCode {
                    rowLabel(L10n.studyRoomsInviteCodeLabel)
                    copyableRow(
                        icon: "number",
                        text: code,
                        copied: $codeCopied,
                        toCopy: code)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Spacer()
        }
        .padding(.top, 8)
    }

    private var header: some View {
        HStack {
            Text(L10n.studyRoomsInviteSheetTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MyCoursesPalette.muted)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(MyCoursesPalette.surface))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    private var roomCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.droobGold.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MyCoursesPalette.accent.opacity(0.4),
                                    lineWidth: 1))
                Image(systemName: "book.pages.fill")
                    .foregroundColor(MyCoursesPalette.accent)
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(width: 48, height: 48)

            Text(room.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(MyCoursesPalette.textPrimary)
                .lineLimit(2)

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

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.4)
            .foregroundColor(MyCoursesPalette.muted)
    }

    private func copyableRow(
        icon: String, text: String,
        copied: Binding<Bool>, toCopy: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(MyCoursesPalette.muted)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(MyCoursesPalette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                UIPasteboard.general.string = toCopy
                withAnimation { copied.wrappedValue = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation { copied.wrappedValue = false }
                }
            } label: {
                Text(copied.wrappedValue
                     ? L10n.studyRoomsInviteCopied
                     : L10n.studyRoomsInviteCopy)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.droobGold))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MyCoursesPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
        )
    }

    /// Server-issued slug rendered as a Universal Link. iOS will open
    /// the app via the AASA component path `/r/*`; tapping the link
    /// outside the app falls back to a web landing page on the apex.
    private var prettyLink: String {
        guard !room.slug.isEmpty else {
            // Defensive fallback while a freshly-deployed app talks to
            // an older backend that hasn't returned a slug yet.
            return "droob-sa.net/r/\(String(room.roomId.suffix(8)))"
        }
        return "droob-sa.net/r/\(room.slug)"
    }
}
