import SwiftUI

// MARK: - Global type scale
//
// 2026-07: app-wide font bump, now +24.2% over the Figma sizes
// (1.0 → 1.15 → 1.38, then trimmed 10% to 1.38 × 0.9 = 1.242). Every
// BrandFont factory and Font.droob* token multiplies its point size by this
// factor, so call sites keep passing their original (Figma) sizes and the
// scaling stays central. Set back to 1.0 to restore the original scale.
enum TypeScale {
    static let factor: CGFloat = 1.242

    /// Scales a design-spec point size by the global factor.
    static func scaled(_ size: CGFloat) -> CGFloat { size * factor }
}

// MARK: - Typography

extension Font {
    static var droobLargeTitle: Font { .system(size: TypeScale.scaled(32), weight: .bold, design: .rounded) }
    static var droobTitle: Font { .system(size: TypeScale.scaled(24), weight: .bold, design: .rounded) }
    static var droobTitle2: Font { .system(size: TypeScale.scaled(20), weight: .semibold, design: .rounded) }
    static var droobHeadline: Font { .system(size: TypeScale.scaled(17), weight: .semibold, design: .rounded) }
    static var droobBody: Font { .system(size: TypeScale.scaled(16), weight: .regular, design: .default) }
    static var droobSubheadline: Font { .system(size: TypeScale.scaled(15), weight: .regular, design: .default) }
    static var droobCaption: Font { .system(size: TypeScale.scaled(13), weight: .regular, design: .default) }
    static var droobCaption2: Font { .system(size: TypeScale.scaled(11), weight: .regular, design: .default) }
}

// MARK: - Brand display font
//
// 2026-07: Fraunces (italic serif) was retired. A learning app is read for
// hours at a time, and an italic display face hurts legibility — worse,
// Fraunces has no Arabic glyphs, so every Arabic headline was a *synthetic*
// slant applied to a fallback font, which is exactly the shape Arabic readers
// find hardest.
//
// The display face is now upright and locale-aware:
//   Latin  → Inter (already the Home content face, bundled)
//   Arabic → the system face, which iOS resolves to SF Arabic
//
// SF Arabic is Apple's own Arabic UI face: upright, hinted for screen reading
// at small sizes, and present on every device with no bundle cost. If we later
// want one identical Arabic face across iOS/Android/web, bundling IBM Plex
// Sans Arabic here is a drop-in swap — only `arabicFont` below changes.
//
// PostScript names come straight from the .ttf metadata (Font Book → File →
// Get Info). Letter-spacing is still dropped in Arabic mode because
// kashida-shaped letters break visually when tracked apart.

enum BrandFont {
    /// The Arabic face, resolved by the system to SF Arabic. Kept as one
    /// funnel so swapping in a bundled Arabic family is a single edit.
    static func arabicFont(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight)
    }

    /// Display regular — onboarding titles, subtitles, section headers.
    /// Upright in both locales; sizes are multiplied by `TypeScale.factor`.
    static func display(size: CGFloat, isArabic: Bool) -> Font {
        let size = TypeScale.scaled(size)
        return isArabic
            ? arabicFont(size: size, weight: .regular)
            : .custom(interRegular, size: size)
    }

    /// Display semibold — primary CTAs ("Get Started", "Next").
    static func displaySemiBold(size: CGFloat, isArabic: Bool) -> Font {
        let size = TypeScale.scaled(size)
        return isArabic
            ? arabicFont(size: size, weight: .semibold)
            : .custom(interSemiBold, size: size)
    }

    /// Legacy alias — the app-wide de-italic pass (2026-07) rewrote call sites
    /// to `display(size:isArabic:)`. Kept so any straggler compiles upright.
    @available(*, deprecated, renamed: "display(size:isArabic:)")
    static func italic(size: CGFloat, isArabic: Bool) -> Font {
        display(size: size, isArabic: isArabic)
    }

    /// Legacy alias — see `italic(size:isArabic:)`.
    @available(*, deprecated, renamed: "displaySemiBold(size:isArabic:)")
    static func semiBoldItalic(size: CGFloat, isArabic: Bool) -> Font {
        displaySemiBold(size: size, isArabic: isArabic)
    }

    // DM Sans — geometric sans used by the authenticated home / tab screens.
    static let dmSansRegular = "DMSans-Regular"
    static let dmSansMedium  = "DMSans-Medium"
    static let dmSansBold    = "DMSans-Bold"

    /// DM Sans 400. Arabic routes through `arabicFont` so glyph shaping works.
    static func sans(size: CGFloat, isArabic: Bool) -> Font {
        let size = TypeScale.scaled(size)
        return isArabic
            ? arabicFont(size: size, weight: .regular)
            : .custom(dmSansRegular, size: size)
    }

    /// DM Sans 500 — card titles, See All, prices.
    static func sansMedium(size: CGFloat, isArabic: Bool) -> Font {
        let size = TypeScale.scaled(size)
        return isArabic
            ? arabicFont(size: size, weight: .medium)
            : .custom(dmSansMedium, size: size)
    }

    /// DM Sans 700 — big greeting, section headers, stat values.
    static func sansBold(size: CGFloat, isArabic: Bool) -> Font {
        let size = TypeScale.scaled(size)
        return isArabic
            ? arabicFont(size: size, weight: .bold)
            : .custom(dmSansBold, size: size)
    }

    // Inter — the content face of the redesigned Home screen (Figma node
    // 2937:18940). All headings, card text, stats and buttons there are Inter.
    // PostScript names come straight from the bundled .ttf metadata.
    static let interRegular  = "Inter-Regular"
    static let interMedium   = "Inter-Medium"
    static let interSemiBold  = "Inter-SemiBold"
    static let interBold     = "Inter-Bold"

    /// Inter at an explicit weight. Arabic routes through `arabicFont` at the
    /// matching weight (Inter has no Arabic coverage) so shaping works.
    static func inter(size: CGFloat, weight: Font.Weight = .regular, isArabic: Bool = false) -> Font {
        let size = TypeScale.scaled(size)
        if isArabic { return arabicFont(size: size, weight: weight) }
        switch weight {
        case .bold, .heavy, .black:        return .custom(interBold, size: size)
        case .semibold:                    return .custom(interSemiBold, size: size)
        case .medium:                      return .custom(interMedium, size: size)
        default:                           return .custom(interRegular, size: size)
        }
    }
}

// MARK: - Text modifier for Droob brand style

struct DroobTextStyle: ViewModifier {
    let font: Font
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundColor(color)
    }
}

extension View {
    func droobStyle(font: Font = .droobBody, color: Color = .primary) -> some View {
        modifier(DroobTextStyle(font: font, color: color))
    }
}
