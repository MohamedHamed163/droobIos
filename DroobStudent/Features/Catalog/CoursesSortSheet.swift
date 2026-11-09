import SwiftUI

// MARK: - Sort options
//
// Lives outside `CoursesTabView` so the sort sheet can reference it
// directly. Each case carries an `apiValue` that maps to the
// `GET /v1/student/courses?sort=` enum on the backend; the host pushes
// the selection through `CatalogViewModel.applySort(...)` which reloads
// from page 0 so the ordering is correct across paginated pages.

enum ExploreSort: String, CaseIterable, Identifiable, Hashable {
    case recentlyAdded
    case mostPopular
    case highestRated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recentlyAdded: return L10n.coursesSortRecentlyAdded
        case .mostPopular:   return L10n.coursesSortMostPopular
        case .highestRated:  return L10n.coursesSortHighestRated
        }
    }

    /// Wire token sent as the `sort` query param. The backend defaults
    /// to {@code RECENT} when the param is absent, so `recentlyAdded`
    /// could omit it — but we still send it explicitly so the request
    /// is self-describing in logs and the default chip behaves the
    /// same whether or not the user has touched the sheet.
    var apiValue: String {
        switch self {
        case .recentlyAdded: return "RECENT"
        case .mostPopular:   return "POPULAR"
        case .highestRated:  return "RATING"
        }
    }

    static let defaultOption: ExploreSort = .recentlyAdded
    var isDefault: Bool { self == .defaultOption }
}

// MARK: - My Courses sort
//
// Client-side ordering applied over the enrolled list — distinct from
// `ExploreSort` because the relevant axes are different (no price, no
// rating, but progress and activity timestamps are first-class). The
// enum knows how to compare two `EnrolledCourse`s under each axis so
// the call site is a single `.sorted(by:)` rather than five branches.

enum MineSort: String, CaseIterable, Identifiable, Hashable {
    case recentlyActive
    case recentlyEnrolled
    case progressHighLow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recentlyActive:    return L10n.mineSortRecentlyActive
        case .recentlyEnrolled:  return L10n.mineSortRecentlyEnrolled
        case .progressHighLow:   return L10n.mineSortProgressHighLow
        }
    }

    static let defaultOption: MineSort = .recentlyActive
    var isDefault: Bool { self == .defaultOption }

    /// Stable comparator for `Array.sorted(by:)`. `nil` timestamps are
    /// treated as "oldest possible" so courses missing a timestamp sink
    /// to the bottom rather than scattering through the list.
    func areInOrder(_ lhs: EnrolledCourse, _ rhs: EnrolledCourse, locale: String) -> Bool {
        switch self {
        case .recentlyActive:
            return (lhs.lastActiveAt ?? .distantPast)
                > (rhs.lastActiveAt ?? .distantPast)
        case .recentlyEnrolled:
            return (lhs.enrolledAt ?? .distantPast)
                > (rhs.enrolledAt ?? .distantPast)
        case .progressHighLow:
            return lhs.progressPct > rhs.progressPct
        }
    }
}

// MARK: - My Courses sort sheet
//
// Visually identical to `CoursesSortSheet` but bound to `MineSort` so
// the rows / checkmark / selection state all share the same layout
// language. Kept as a separate type rather than a generic so the
// initialiser signatures stay obvious at the call site.

struct MineSortSheet: View {
    let initial: MineSort
    let onSelect: (MineSort) -> Void
    let onDone: () -> Void

    @State private var selection: MineSort
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    init(initial: MineSort,
         onSelect: @escaping (MineSort) -> Void,
         onDone: @escaping () -> Void) {
        self.initial = initial
        self.onSelect = onSelect
        self.onDone = onDone
        _selection = State(initialValue: initial)
    }

    private var ar: Bool { appLocale == "ar" }

    /// Header + 3 rows + safe area.
    static let preferredHeight: CGFloat = 300
    static let shortDeviceScreenHeight: CGFloat = 700

    var body: some View {
        ZStack {
            AuthFigmaColors.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                ForEach(Array(MineSort.allCases.enumerated()), id: \.element) { idx, option in
                    row(option)
                    if idx < MineSort.allCases.count - 1 {
                        Rectangle()
                            .fill(AuthFigmaColors.divider)
                            .frame(height: 1)
                            .padding(.horizontal, 24)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(L10n.coursesSortTitle)
                .font(BrandFont.displaySemiBold(size: 22, isArabic: ar))
                .foregroundColor(AuthFigmaColors.textPrimary)
            Spacer()
            Button(action: onDone) {
                Text(L10n.coursesSortDone)
                    .font(BrandFont.display(size: 16, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.gold)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func row(_ option: MineSort) -> some View {
        let active = option == selection
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                selection = option
            }
            onSelect(option)
        } label: {
            HStack {
                Text(option.label)
                    .font(BrandFont.display(size: 16, isArabic: ar))
                    .foregroundColor(active
                                     ? AuthFigmaColors.textPrimary
                                     : AuthFigmaColors.muted)
                Spacer()
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AuthFigmaColors.gold)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(active ? AuthFigmaColors.chipBg.opacity(0.5) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sort sheet
//
// Bottom-sheet picker that mirrors the Figma "Sort by" panel: a header
// row ("Sort by" + gold "Done"), then one row per option with a thin
// divider between rows and a gold checkmark on the active option. The
// active row also tints its background subtly to match the design.
//
// Tapping a row applies the new sort immediately (so the user sees the
// list reorder behind the sheet); "Done" only dismisses. This matches
// the pattern used by Apple's first-party sort sheets where the
// destructive action is the dismiss, not the selection.

struct CoursesSortSheet: View {
    let initial: ExploreSort
    let onSelect: (ExploreSort) -> Void
    let onDone: () -> Void

    @State private var selection: ExploreSort
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    init(initial: ExploreSort,
         onSelect: @escaping (ExploreSort) -> Void,
         onDone: @escaping () -> Void) {
        self.initial = initial
        self.onSelect = onSelect
        self.onDone = onDone
        _selection = State(initialValue: initial)
    }

    private var ar: Bool { appLocale == "ar" }

    var body: some View {
        ZStack {
            AuthFigmaColors.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                ForEach(Array(ExploreSort.allCases.enumerated()), id: \.element) { idx, option in
                    row(option)
                    if idx < ExploreSort.allCases.count - 1 {
                        Rectangle()
                            .fill(AuthFigmaColors.divider)
                            .frame(height: 1)
                            .padding(.horizontal, 24)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    /// Fixed height the host pins the sheet to via
    /// `.presentationDetents([.height(CoursesSortSheet.preferredHeight)])`.
    /// Sized for the header + three rows + bottom safe area on standard
    /// iPhones, matching the Figma spec. The host falls back to
    /// `.large` on screens shorter than `shortDeviceScreenHeight`.
    static let preferredHeight: CGFloat = 300
    static let shortDeviceScreenHeight: CGFloat = 700

    // MARK: Header

    private var header: some View {
        HStack {
            Text(L10n.coursesSortTitle)
                .font(BrandFont.displaySemiBold(size: 22, isArabic: ar))
                .foregroundColor(AuthFigmaColors.textPrimary)
            Spacer()
            Button(action: onDone) {
                Text(L10n.coursesSortDone)
                    .font(BrandFont.display(size: 16, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.gold)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Row

    @ViewBuilder
    private func row(_ option: ExploreSort) -> some View {
        let active = option == selection
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                selection = option
            }
            onSelect(option)
        } label: {
            HStack {
                Text(option.label)
                    .font(BrandFont.display(size: 16, isArabic: ar))
                    .foregroundColor(active
                                     ? AuthFigmaColors.textPrimary
                                     : AuthFigmaColors.muted)
                Spacer()
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AuthFigmaColors.gold)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(active ? AuthFigmaColors.chipBg.opacity(0.5) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
