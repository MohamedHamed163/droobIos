import SwiftUI
import UIKit

/// Pill chip showing the room's join code with a copy button.
///
/// Layout: pill outline + monospaced code (`9F4-2K7`) + a small copy
/// icon button at the trailing edge. Used under "Enter the room" on
/// `RoomReadyView` and under "Invite classmates" on
/// `StudyRoomChatView`'s empty state.
struct RoomCodeChip: View {
    let rawCode: String

    @State private var copied: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.studyRoomsRoomCodeChip)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
            Text(JoinCodeFormat.display(rawCode))
                .font(.system(size: 13, weight: .bold,
                              design: .monospaced))
                .tracking(1.5)
                .foregroundColor(MyCoursesPalette.accent)
            Divider()
                .frame(width: 1, height: 14)
                .background(MyCoursesPalette.stroke)
            Button {
                UIPasteboard.general.string =
                    JoinCodeFormat.display(rawCode)
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation { copied = false }
                }
            } label: {
                Image(systemName: copied
                      ? "checkmark"
                      : "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(MyCoursesPalette.surface)
                .overlay(Capsule().stroke(
                    MyCoursesPalette.stroke, lineWidth: 1))
        )
    }
}

/// Per-user circular avatar. Background colour is a deterministic
/// hash of the user id so the same user has the same colour everywhere
/// (matches the figma: Sara=purple, Layla=orange, Mohamed=blue,
/// Youssef=green).
struct MemberAvatar: View {
    let userId: String
    let initials: String
    var size: CGFloat = 32

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(Self.colour(for: userId)))
    }

    /// FNV-1a hash → fixed palette. Stable across launches because the
    /// hash only depends on the user id string content. Keep this in
    /// sync with the Android port if/when we add the matching feature.
    static func colour(for userId: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.69, green: 0.34, blue: 0.87),  // purple — Sara
            Color(red: 0.95, green: 0.58, blue: 0.18),  // orange — Layla
            Color(red: 0.16, green: 0.55, blue: 0.95),  // blue   — Mohamed
            Color(red: 0.27, green: 0.78, blue: 0.40),  // green  — Youssef
            Color(red: 0.93, green: 0.36, blue: 0.55),  // pink
            Color(red: 0.83, green: 0.71, blue: 0.25),  // gold
            Color(red: 0.38, green: 0.66, blue: 0.85),  // teal
            Color(red: 0.85, green: 0.40, blue: 0.36),  // red
        ]
        // FNV-1a 32-bit hash (deterministic, no Foundation dep).
        var hash: UInt32 = 0x811c9dc5
        for byte in userId.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x01000193
        }
        return palette[Int(hash % UInt32(palette.count))]
    }
}

/// Compact centred pill for server-generated lifecycle events
/// (V55: "Layla joined" / "Bob left" / host-transfer combinations).
/// Used by `StudyRoomChatView`'s timeline-row renderer; the flanking
/// horizontal dividers that turn the row into a system-event line
/// live there so the pill itself can also be dropped inline anywhere
/// a divider isn't wanted (e.g. previews / Storybook).
///
/// Styling matches the Figma `JOIN system messages` cluster (node
/// 1114:5747): a low-contrast capsule with a thin border, a per-user
/// gradient avatar, and a name + muted suffix. The capsule's fill /
/// border ride the adaptive palette so the pill reads on both the
/// light and the dark chat background (the figma's `#14110B` on
/// `#413723` pairing was dark-only).
struct SystemEventPill: View {
    /// User the avatar represents — the actor (joiner / leaver / new
    /// host). Drives the avatar colour and initials.
    let userId: String
    let initials: String
    /// Rendered text content. Built by the caller so we don't pin a
    /// specific localized template inside the pill — joined / left
    /// / host-transferred have different shapes (single name vs.
    /// "X · Y") and stitching them inside the pill would balloon
    /// the API surface. Caller passes an already-styled `Text`
    /// concatenation (bold + muted), pill applies background +
    /// padding + accessibility.
    let content: Text
    /// Plain-text version of `content` used by VoiceOver, since
    /// `accessibilityLabel` can't be derived from a styled `Text`
    /// composition.
    let accessibilityText: String

    private static let pillFill = MyCoursesPalette.surface
    private static let pillStroke = MyCoursesPalette.stroke

    var body: some View {
        HStack(spacing: 7) {
            avatar
            content
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Self.pillFill)
                .overlay(Capsule().stroke(Self.pillStroke, lineWidth: 1)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Small rounded-square avatar with a per-user gradient. Built
    /// inline (rather than reusing `MemberAvatar`) because Figma uses
    /// a 4-corner-radius rectangle with a topLeading→bottomTrailing
    /// gradient at this size — `MemberAvatar`'s flat-fill circle
    /// would visibly drift from the design.
    private var avatar: some View {
        let base = MemberAvatar.colour(for: userId)
        return ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [base, base.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
            Text(initials)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 17, height: 17)
    }
}

/// Shared muted colour for the trailing " joined " / " left " /
/// " is now the host " portion of a SystemEventPill's text. Public
/// so the chat view can compose the styled `Text` for transfer
/// pills (which need to interleave bold + muted spans).
enum SystemEventPillStyle {
    static let bodyFont: Font = .system(size: 11, weight: .regular)
    static let nameFont: Font = .system(size: 11, weight: .semibold)
    static let nameColor: Color = MyCoursesPalette.textPrimary
    static let mutedColor: Color = MyCoursesPalette.muted
}

/// Fixed (non-adaptive) chrome shared by the room "cover art" tiles —
/// the create form, the settings header, and the joining / pending
/// screens all draw the same gold book glyph on a dark plate.
enum StudyRoomChrome {
    /// The cover plate. Deliberately the same dark tile in both themes:
    /// the glyph and its border are `Color.droobGold`, which is the
    /// dark-mode gold and needs a dark backdrop to read.
    ///
    /// This used to be `Color.black.opacity(0.6)`. An alpha black is not
    /// a dark plate — over the light-mode page (white) it composites to
    /// roughly #666, which drops the gold glyph to about 2.5:1. An
    /// opaque colour is the only way to keep a plate dark regardless of
    /// what is behind it; #14110B is the figma's cover-art fill and puts
    /// the gold glyph back at ~8.4:1.
    static let coverPlate = Color(red: 0.078, green: 0.067, blue: 0.043)
}
