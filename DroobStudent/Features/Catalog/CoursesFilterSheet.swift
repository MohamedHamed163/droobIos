import SwiftUI

// MARK: - Multi-dimension filter selection
//
// Modelled as three independent enums so a Price tier, Rating tier, and
// Level tier compose without combinatorial explosion. `.allDefault` is
// the no-filter state used by "Clear all" and as the initial value.

struct CoursesFilterSelection: Equatable {
    var price: PriceTier
    var rating: RatingTier
    var level: LevelTier

    enum PriceTier: CaseIterable, Hashable {
        case any, free, under50, between50And100, over100

        var label: String {
            switch self {
            case .any:              return L10n.coursesFilterPriceAny
            case .free:             return L10n.coursesFilterFree
            case .under50:          return L10n.coursesFilterPriceUnder50
            case .between50And100:  return L10n.coursesFilterPrice50To100
            case .over100:          return L10n.coursesFilterPrice100Plus
            }
        }
    }

    enum RatingTier: CaseIterable, Hashable {
        case any, fourPointFive, four, threePointFive

        var label: String {
            switch self {
            case .any:           return L10n.coursesFilterRatingAny
            case .fourPointFive: return L10n.coursesFilterRating45
            case .four:          return L10n.coursesFilterRating40
            case .threePointFive: return L10n.coursesFilterRating35
            }
        }

        var minimum: Double? {
            switch self {
            case .any:            return nil
            case .fourPointFive:  return 4.5
            case .four:           return 4.0
            case .threePointFive: return 3.5
            }
        }
    }

    enum LevelTier: CaseIterable, Hashable {
        case all, beginner, intermediate, advanced

        var label: String {
            switch self {
            case .all:          return L10n.coursesFilterLevelAll
            case .beginner:     return L10n.coursesFilterLevelBeginner
            case .intermediate: return L10n.coursesFilterLevelIntermediate
            case .advanced:     return L10n.coursesFilterLevelAdvanced
            }
        }

        /// Uppercase wire token sent as the `level` query param on
        /// `/v1/student/courses`. `nil` means "don't filter" (the "All
        /// Levels" chip), which the API treats as omitting the param.
        var apiValue: String? {
            switch self {
            case .all:          return nil
            case .beginner:     return "BEGINNER"
            case .intermediate: return "INTERMEDIATE"
            case .advanced:     return "ADVANCED"
            }
        }
    }

    static let allDefault = CoursesFilterSelection(
        price: .any, rating: .any, level: .all)

    var isDefault: Bool { self == .allDefault }

    /// Returns `true` when the given course passes every active dimension.
    /// Price and rating are evaluated client-side against the already-loaded
    /// page; level is also re-checked here (in addition to being pushed as
    /// the `level` query param) so list updates don't lag the API by a
    /// round-trip when the selection changes.
    func matches(_ course: CourseSummary) -> Bool {
        let dollars = course.priceCents / 100
        switch price {
        case .any:              break
        case .free:             if course.priceCents != 0 { return false }
        case .under50:          if !(dollars < 50) { return false }
        case .between50And100:  if !(dollars >= 50 && dollars <= 100) { return false }
        case .over100:          if !(dollars > 100) { return false }
        }
        if let min = rating.minimum, (course.ratingAvg ?? -1) < min {
            return false
        }
        if let want = level.apiValue, course.level != want {
            return false
        }
        return true
    }
}

// MARK: - Filter sheet
//
// Bottom-sheet picker with three sections (Price, Rating, Level) and a
// sticky "Apply Filters" CTA. Mirrors the Figma:
//   • Active chip → gold outline + gold italic label
//   • Inactive chip → AuthFigmaColors.chipBg + muted label
//   • Clear all → resets selection to `.allDefault` without dismissing

struct CoursesFilterSheet: View {
    let initial: CoursesFilterSelection
    /// `true` on short devices (iPhone SE class) where the fixed-height
    /// detent would clip — the host detects this and asks for the
    /// scrollable variant. Tall phones get the non-scrollable layout
    /// from the Figma.
    let scrollable: Bool
    let onApply: (CoursesFilterSelection) -> Void
    let onCancel: () -> Void

    @State private var selection: CoursesFilterSelection
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    init(initial: CoursesFilterSelection,
         scrollable: Bool = false,
         onApply: @escaping (CoursesFilterSelection) -> Void,
         onCancel: @escaping () -> Void) {
        self.initial = initial
        self.scrollable = scrollable
        self.onApply = onApply
        self.onCancel = onCancel
        _selection = State(initialValue: initial)
    }

    private var ar: Bool { appLocale == "ar" }

    // Hidden for now (2026-07): reviews/ratings paused platform-wide.
    private var hideReviews: Bool { true }

    var body: some View {
        ZStack {
            AuthFigmaColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if scrollable {
                    ScrollView {
                        sectionsBlock
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                            .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                    applyButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                } else {
                    // No ScrollView — the sheet is sized to fit all three
                    // sections and the CTA in one go (see
                    // `Self.preferredHeight`). The Spacer absorbs any
                    // leftover slack on taller phones so the Apply button
                    // always pins to the bottom.
                    VStack(alignment: .leading, spacing: 24) {
                        sectionsBlock
                        Spacer(minLength: 12)
                        applyButton
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var sectionsBlock: some View {
        // Price filter removed — this is a free-enrollment app, so the
        // catalog has no money tiers to filter by (App Store Guideline 3.1.1).
        VStack(alignment: .leading, spacing: 24) {
            header
            // Hidden for now (2026-07): reviews/ratings paused platform-wide —
            // the Rating filter section (and its divider) is hidden. The
            // RatingTier enum and `matches()` logic are kept; the selection
            // stays `.any` while the chips are hidden, so no filtering occurs.
            if !hideReviews {
                section(title: L10n.coursesFilterSectionRating) {
                    chipGrid(
                        CoursesFilterSelection.RatingTier.allCases,
                        isActive: { $0 == selection.rating },
                        onTap: { selection.rating = $0 })
                }
                divider
            }
            section(title: L10n.coursesFilterSectionLevel) {
                chipGrid(
                    CoursesFilterSelection.LevelTier.allCases,
                    isActive: { $0 == selection.level },
                    onTap: { selection.level = $0 })
            }
        }
    }

    /// Fixed height the host should pin the sheet to via
    /// `.presentationDetents([.height(CoursesFilterSheet.preferredHeight)])`.
    /// Sized to fit the three sections + CTA on iPhone 13/14/15/16-class
    /// screens without scrolling, matching the Figma spec exactly.
    static let preferredHeight: CGFloat = 470

    /// Screens shorter than this fall back to `[.large]` + a ScrollView
    /// because the fixed-height detent would clip the Apply CTA below the
    /// safe area on iPhone SE-class devices.
    static let shortDeviceScreenHeight: CGFloat = 700

    // MARK: Header

    private var header: some View {
        HStack {
            Text(L10n.coursesFilterSheetTitle)
                .font(BrandFont.displaySemiBold(size: 22, isArabic: ar))
                .foregroundColor(AuthFigmaColors.textPrimary)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selection = .allDefault
                }
            } label: {
                Text(L10n.coursesFilterClearAll)
                    .font(BrandFont.display(size: 15, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.textPrimary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Section + chips

    @ViewBuilder
    private func section<Content: View>(title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(BrandFont.display(size: 12, isArabic: ar))
                .tracking(1.6)
                .foregroundColor(AuthFigmaColors.muted)
            content()
        }
    }

    /// Wrapping chip grid. Each option renders the same chip; the active
    /// option gains a gold outline + gold italic label. Wraps to a new line
    /// when chips would otherwise overflow the available width.
    @ViewBuilder
    private func chipGrid<Option: Hashable>(
        _ options: [Option],
        isActive: @escaping (Option) -> Bool,
        onTap: @escaping (Option) -> Void
    ) -> some View where Option: ChipLabelProviding {
        FlowLayout(spacing: 10, lineSpacing: 10) {
            ForEach(options, id: \.self) { option in
                chip(label: option.label, isActive: isActive(option)) {
                    withAnimation(.easeInOut(duration: 0.12)) { onTap(option) }
                }
            }
        }
    }

    @ViewBuilder
    private func chip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(BrandFont.display(size: 15, isArabic: ar))
                .foregroundColor(isActive
                                 ? AuthFigmaColors.gold
                                 : AuthFigmaColors.muted)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(AuthFigmaColors.chipBg))
                .overlay(
                    Capsule().stroke(
                        isActive ? AuthFigmaColors.gold : Color.clear,
                        lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(AuthFigmaColors.divider)
            .frame(height: 1)
            .padding(.vertical, 2)
    }

    // MARK: Apply

    private var applyButton: some View {
        Button {
            onApply(selection)
        } label: {
            Text(L10n.coursesFilterApply)
                .font(BrandFont.displaySemiBold(size: 17, isArabic: ar))
                .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(LinearGradient.droobButtonGradient)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chip label protocol
//
// Lets `chipGrid` accept any of the three filter enums without an
// AnyView dance. Each enum exposes its localized label via this
// protocol; SwiftUI's `ForEach` sees a concrete generic `Option` type.

protocol ChipLabelProviding: Hashable {
    var label: String { get }
}

extension CoursesFilterSelection.PriceTier: ChipLabelProviding { }
extension CoursesFilterSelection.RatingTier: ChipLabelProviding { }
extension CoursesFilterSelection.LevelTier: ChipLabelProviding { }

// MARK: - Wrapping flow layout
//
// SwiftUI's built-in HStack doesn't wrap, and a LazyVGrid would force
// equal-width columns that break the Figma's pill widths. This is a
// minimal Layout impl that places children left-to-right, wrapping to a
// new line when the next child would overflow. iOS 16+ only (matches
// the app's deployment target).

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                widestRow = max(widestRow, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        widestRow = max(widestRow, x - spacing)
        let height = y + lineHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : widestRow, height: height)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            sub.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
