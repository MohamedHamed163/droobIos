import SwiftUI

/// Compact overlapping avatar stack with a `+N` overflow chip. Built on
/// top of `MemberAvatar` so the per-user colour palette stays the
/// single source of truth for member chrome across the feature.
struct AvatarStack: View {
    let previews: [MemberPreview]
    /// Server-truth member count; drives the `+N` overflow badge.
    let totalCount: Int
    var visibleLimit: Int = 5
    var avatarSize: CGFloat = 22

    var body: some View {
        let visible = Array(previews.prefix(visibleLimit))
        let overflow = max(0, totalCount - visible.count)
        HStack(spacing: -8) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { _, m in
                // `id` falls back to an anon key when userId is null
                // (2026-07 anonymized peers) — keeps colours stable.
                MemberAvatar(userId: m.id,
                             initials: m.initials,
                             size: avatarSize)
                    .overlay(
                        Circle().stroke(MyCoursesPalette.background,
                                        lineWidth: 1.5))
            }
            if overflow > 0 {
                // Solid black chip + white glyph in both themes — it's a
                // filled badge sitting alongside the coloured avatars,
                // not page text, so it must not follow the palette.
                Text("+\(overflow)")
                    .font(.system(size: avatarSize * 0.40, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: avatarSize, height: avatarSize)
                    .background(Circle().fill(Color.black))
                    .overlay(
                        Circle().stroke(MyCoursesPalette.background,
                                        lineWidth: 1.5))
            }
        }
    }
}
