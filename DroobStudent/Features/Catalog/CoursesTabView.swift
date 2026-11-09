import SwiftUI

// MARK: - Courses tab (Figma redesign)
//
// Replaces the prior MyCoursesView + standalone CatalogListView. Hosts the
// two modes ("My Courses" / "Explore") behind a single segmented pill at the
// top of the screen. The shared chrome — title, search field, segmented
// control — stays mounted across mode switches; only the list region swaps.
//
// Pagination on Explore is driven by `CatalogViewModel.loadMore()` (page
// size 20). A trailing sentinel triggers the next page when it scrolls into
// view, matching the Figma "infinite scroll" behaviour.

struct CoursesTabView: View {
    @EnvironmentObject private var authSession: AuthSession
    @StateObject private var instructorBrowseVm = InstructorBrowseViewModel()
    @StateObject private var myCoursesVm: MyCoursesViewModel
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    @State private var mode: Mode = .explore
    @State private var query: String = ""
    /// Instructor groups the student has collapsed on the Enrolled tab.
    /// Empty = all expanded (the default, matching the Figma).
    @State private var collapsedGroups: Set<String> = []
    /// Drives the Explore enrollment bottom sheet. Set when a course is
    /// tapped from an instructor's drawer; the user is still deciding to
    /// enrol, so we present the request sheet rather than pushing the full
    /// course screen (that push is reserved for My Courses).
    @State private var presentedCourse: CourseSheetItem?

    init(
        myCoursesOverride: MyCoursesViewModel? = nil,
        initialMode: Mode = .explore
    ) {
        _myCoursesVm = StateObject(
            wrappedValue: myCoursesOverride ?? MyCoursesViewModel())
        _mode = State(initialValue: initialMode)
    }

    enum Mode: String, CaseIterable {
        case mine, explore
        var label: String {
            switch self {
            case .mine:    return L10n.coursesSegmentMine
            case .explore: return L10n.coursesSegmentExplore
            }
        }
    }

    /// Value-based push target for an instructor profile. Kept distinct
    /// from the `String` course-id destination so the two routes don't
    /// collide on the shared NavigationStack path.
    struct InstructorRoute: Hashable { let id: String }

    /// Identifiable wrapper so the Explore enrollment sheet can bind to
    /// `.sheet(item:)` with a plain course-id String.
    struct CourseSheetItem: Identifiable { let id: String }

    private var ar: Bool { appLocale == "ar" }

    var body: some View {
        ZStack(alignment: .top) {
            AuthFigmaColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Color.clear.frame(height: 8)
                        titleBlock
                        // The Enrolled tab has no search field (it's a small,
                        // grouped list); search lives only on Explore.
                        if mode == .explore { searchField }
                        segmentedControl
                        Group {
                            if mode == .mine {
                                myCoursesSection
                            } else {
                                exploreSection
                            }
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 22)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    if mode == .mine { await myCoursesVm.load() }
                    else            { await instructorBrowseVm.loadInitial() }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await instructorBrowseVm.loadInitial()
            await myCoursesVm.load()
        }
        // Server-side teacher search — every keystroke feeds the VM, which
        // debounces (~300 ms) and re-fetches page 0 with `q`, so instructors
        // beyond the loaded pages are findable.
        .onChange(of: query) { newValue in
            instructorBrowseVm.updateQuery(newValue)
        }
        // Value-based push target for the Mine list and for Home deep-links.
        // The enclosing NavigationStack is path-bound (in MainTabView) on
        // `[String]` course ids, so routing is a deterministic path mutation
        // — no first-render race like the old isPresented + sleep approach.
        .navigationDestination(for: String.self) { id in
            CourseDetailView(courseId: id)
        }
        .navigationDestination(for: InstructorRoute.self) { route in
            InstructorProfileView(instructorId: route.id)
        }
        .coursePresentation(item: $presentedCourse) { item in
            enrollSheetContent(item)
        }
    }

    // The enrollment screen is a full-height design (hero + instructor +
    // bullets + request card), so on iPhone it presents at `.large`. On iPad
    // it isn't a sheet at all — see `adaptiveSheetChrome`.
    private func enrollSheetContent(_ item: CourseSheetItem) -> some View {
        CourseDetailSheetView(courseId: item.id) { presentedCourse = nil }
            .adaptiveSheetChrome(background: AuthFigmaColors.bg)
    }

    // MARK: Title

    private var titleBlock: some View {
        // My Courses uses "Courses" as the headline (not "My Courses",
        // which already labels the pill segment underneath) and a
        // dual-count subtitle "{N} enrolled · {M} completed". Explore
        // keeps its existing copy.
        VStack(alignment: .leading, spacing: 6) {
            Text(mode == .mine
                 ? L10n.myCoursesTitleCourses
                 : L10n.coursesSegmentExplore)
                .font(BrandFont.displaySemiBold(size: 36, isArabic: ar))
                .tracking(ar ? 0 : -1.0)
                .foregroundColor(AuthFigmaColors.gold)
            Text(mode == .mine ? mineSubtitle : exploreSubtitle)
                .font(BrandFont.display(size: 14, isArabic: ar))
                .foregroundColor(AuthFigmaColors.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mineSubtitle: String {
        // "{N} instructors · {M} active courses" — mirrors the Figma header.
        let instructors = myCoursesVm.instructorGroups.count
        let active = myCoursesVm.stats.total
        return String(format: L10n.enrolledSubtitleFmt, instructors, active)
    }

    private var exploreSubtitle: String {
        String(format: L10n.exploreBrowseInstructorsFmt, instructorBrowseVm.totalCount)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AuthFigmaColors.muted)
            TextField("", text: $query,
                      prompt: Text(L10n.catalogSearchPlaceholder)
                        .foregroundColor(AuthFigmaColors.muted))
                .font(BrandFont.display(size: 14, isArabic: ar))
                .foregroundColor(AuthFigmaColors.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AuthFigmaColors.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AuthFigmaColors.surface)
        .clipShape(Capsule())
    }

    // MARK: Segmented

    private var segmentedControl: some View {
        // Two equal segments on a dark surface; the active one lifts to a
        // slightly lighter shade with a thin gold underline. Matches the
        // "My Courses | Explore" pill in the Figma.
        HStack(spacing: 0) {
            segment(.mine)
            segment(.explore)
        }
        .padding(4)
        .background(AuthFigmaColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func segment(_ m: Mode) -> some View {
        let isActive = mode == m
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { mode = m }
        } label: {
            Text(m.label)
                .font(BrandFont.displaySemiBold(size: 14, isArabic: ar))
                .foregroundColor(isActive
                                 ? AuthFigmaColors.textPrimary
                                 : AuthFigmaColors.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? AuthFigmaColors.chipBg : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: My Courses

    @ViewBuilder
    private var myCoursesSection: some View {
        if !myCoursesVm.hasLoaded
            && myCoursesVm.enrollments.isEmpty
            && myCoursesVm.pendingRequests.isEmpty {
            VStack(spacing: 14) {
                MCSkeletonBlock(height: 64, cornerRadius: 16)
                ForEach(0..<3, id: \.self) { _ in
                    MCSkeletonBlock(height: 130, cornerRadius: 16)
                }
            }
        } else if myCoursesVm.instructorGroups.isEmpty {
            emptyMyCoursesState
        } else {
            VStack(alignment: .leading, spacing: 16) {
                EnrolledStatsBar(stats: myCoursesVm.stats)
                ForEach(myCoursesVm.instructorGroups) { group in
                    InstructorGroupCard(
                        group: group,
                        locale: appLocale,
                        isExpanded: !collapsedGroups.contains(group.id),
                        onToggle: { toggleGroup(group.id) })
                }
                discoverMoreButton
                Text(L10n.myCoursesOfflineFooter)
                    .font(BrandFont.display(size: 12, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.muted)
                    .padding(.top, 2)
            }
        }
    }

    private func toggleGroup(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if collapsedGroups.contains(id) {
                collapsedGroups.remove(id)
            } else {
                collapsedGroups.insert(id)
            }
        }
    }

    /// Bordered gold pill that bounces the student over to Explore to find
    /// new instructors. Matches Figma 1923:6158.
    private var discoverMoreButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { mode = .explore }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.enrolledDiscoverMore)
                    .font(BrandFont.displaySemiBold(size: 15, isArabic: ar))
            }
            .foregroundColor(AuthFigmaColors.gold)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AuthFigmaColors.gold.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AuthFigmaColors.gold.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Onboarding empty state for a student with no enrolments — a
    /// decorative mark, a personalised welcome, a two-step "How Droob
    /// works" explainer, and a gold CTA into Explore. Figma 1926:6462.
    private var emptyMyCoursesState: some View {
        VStack(spacing: 18) {
            emptyDecoration
                .padding(.top, 20)

            (Text(L10n.enrolledEmptyWelcomePrefix + " ")
                .foregroundColor(AuthFigmaColors.textPrimary)
             + Text(emptyWelcomeName)
                .foregroundColor(AuthFigmaColors.gold))
                .font(.system(size: 24, weight: .light))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            howDroobWorksCard

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { mode = .explore }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(String(format: L10n.enrolledEmptyBrowseAllFmt,
                                instructorBrowseVm.totalCount))
                        .font(.system(size: 14, weight: .bold))
                        .tracking(-0.07)
                }
                .foregroundColor(Color(red: 0x1A/255, green: 0x13/255, blue: 0x05/255))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(LinearGradient.droobButtonGradient)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: AuthFigmaColors.gold.opacity(0.2), radius: 5, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    /// First name for the welcome headline, mirroring HomeView's greeting.
    private var emptyWelcomeName: String {
        let name = authSession.currentUser?.displayName ?? ""
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return first.isEmpty ? L10n.brandName : first
    }

    /// 120pt radial-glow tile with a dashed "add" mark and a few confetti
    /// flecks — the celebratory empty-state icon from the Figma.
    private var emptyDecoration: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [AuthFigmaColors.gold.opacity(0.2), .clear],
                    center: .center, startRadius: 0, endRadius: 60))
                .frame(width: 120, height: 120)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundColor(AuthFigmaColors.gold.opacity(0.45))
                .frame(width: 58, height: 58)
                .rotationEffect(.degrees(-9))
                .offset(x: -7, y: 5)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AuthFigmaColors.gold.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundColor(AuthFigmaColors.gold))
                .frame(width: 58, height: 58)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(AuthFigmaColors.gold))

            confettiFleck(color: Color(red: 0.55, green: 0.36, blue: 0.96), offset: CGSize(width: 38, height: -34))
            confettiFleck(color: AuthFigmaColors.gold, offset: CGSize(width: -40, height: -28))
            confettiFleck(color: EnrolledPalette.green, offset: CGSize(width: 44, height: 30))
        }
        .frame(width: 120, height: 120)
    }

    private func confettiFleck(color: Color, offset: CGSize) -> some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .offset(offset)
    }

    /// "HOW DROOB WORKS" explainer — two icon-led steps with a connecting
    /// arrow, inside a faint bordered card.
    private var howDroobWorksCard: some View {
        VStack(spacing: 12) {
            Text(L10n.enrolledEmptyHowTitle.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundColor(AuthFigmaColors.gold)

            HStack(alignment: .top, spacing: 8) {
                howStep(icon: "person.fill",
                        title: L10n.enrolledEmptyPickTitle,
                        subtitle: L10n.enrolledEmptyPickSubtitle)
                Image(systemName: ar ? "arrow.left" : "arrow.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(AuthFigmaColors.muted)
                    .padding(.top, 13)
                howStep(icon: "bubble.left.fill",
                        title: L10n.enrolledEmptyRequestTitle,
                        subtitle: L10n.enrolledEmptyRequestSubtitle)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(MyCoursesPalette.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    private func howStep(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(AuthFigmaColors.gold.opacity(0.12))
                    .overlay(Circle().stroke(AuthFigmaColors.gold, lineWidth: 1))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(AuthFigmaColors.gold)
            }
            .frame(width: 38, height: 38)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(MyCoursesPalette.textPrimary)
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundColor(AuthFigmaColors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Explore — Instructors

    @ViewBuilder
    private var exploreSection: some View {
        let list = filteredInstructors
        if instructorBrowseVm.isLoading && instructorBrowseVm.instructors.isEmpty {
            VStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { _ in
                    MCSkeletonBlock(height: 180, cornerRadius: 18)
                }
            }
        } else if let err = instructorBrowseVm.errorMessage,
                  instructorBrowseVm.instructors.isEmpty {
            ErrorBanner(message: err) {
                Task { await instructorBrowseVm.loadInitial() }
            }
        } else if list.isEmpty {
            emptyFilterState
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(format: L10n.exploreInstructorsCountFmt,
                            instructorBrowseVm.totalCount))
                    .font(BrandFont.sansMedium(size: 20, isArabic: ar))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .tracking(ar ? 0 : -0.24)
                LazyVStack(spacing: 16) {
                    ForEach(list) { instructor in
                        InstructorBrowseRow(
                            instructor: instructor,
                            locale: appLocale,
                            courses: instructorBrowseVm.coursesByInstructor[instructor.id],
                            isLoadingCourses: instructorBrowseVm.loadingCourses.contains(instructor.id),
                            onExpand: {
                                Task { await instructorBrowseVm.loadCourses(for: instructor.id) }
                            },
                            onCourseTap: { presentedCourse = CourseSheetItem(id: $0) })
                    }
                    instructorPaginationSentinel
                }
            }
        }
    }

    /// Search moved server-side (2026-07): the VM debounces `query` and
    /// re-fetches `/v1/student/instructors?q=` — the response IS the
    /// filtered list, so rows beyond the loaded pages are findable. The old
    /// client-side filter is kept commented below for reference; it is NOT
    /// layered on top because the server also matches the professional
    /// title in the *other* language, which the client filter would hide.
    private var filteredInstructors: [StudentInstructorSummary] {
        instructorBrowseVm.instructors
        // Old client-side filter over the loaded pages:
        // let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // guard !trimmed.isEmpty else { return instructorBrowseVm.instructors }
        // return instructorBrowseVm.instructors.filter {
        //     $0.displayName.lowercased().contains(trimmed)
        //         || ($0.localizedTitle(locale: appLocale)?.lowercased().contains(trimmed) ?? false)
        // }
    }

    @ViewBuilder
    private var instructorPaginationSentinel: some View {
        // Search is server-side now, so pagination keeps working while a
        // query is active (the next pages carry the same `q`).
        // Old gate: if instructorBrowseVm.hasNextPage && query.isEmpty {
        if instructorBrowseVm.hasNextPage {
            HStack {
                Spacer()
                ProgressView()
                    .tint(AuthFigmaColors.gold)
                    .padding(.vertical, 14)
                    .onAppear {
                        Task { await instructorBrowseVm.loadMore() }
                    }
                Spacer()
            }
        }
    }

    private var emptyFilterState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundColor(AuthFigmaColors.muted)
            Text(L10n.myCoursesFilterEmpty)
                .font(BrandFont.display(size: 14, isArabic: ar))
                .foregroundColor(AuthFigmaColors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

}

// MARK: - Enrolled tab palette
//
// Precise Figma tokens for the Enrolled redesign (node 1923:5973). Kept
// local because they only appear on this surface; the shared
// `AuthFigmaColors` covers gold / surface / muted everywhere else.
private enum EnrolledPalette {
    static let green = Color(red: 0.188, green: 0.820, blue: 0.345)      // #30D158
    static let amber = Color(red: 1.0, green: 0.624, blue: 0.039)        // #FF9F0A
    static let goldStrong = Color(red: 0.878, green: 0.769, blue: 0.561) // #E0C48F
    static let cardBg = MyCoursesPalette.surface                         // was #0E0E10
}

// MARK: - Enrolled stats bar

/// Four-cell summary at the top of the Enrolled tab — total courses,
/// in-progress, completed, pending — each a coloured count over an
/// uppercase caption, split by hairline dividers. Figma 1923:5981.
private struct EnrolledStatsBar: View {
    let stats: MyCoursesViewModel.Stats

    var body: some View {
        HStack(spacing: 0) {
            cell(value: stats.total, label: L10n.enrolledStatCourses,
                 color: AuthFigmaColors.gold)
            divider
            cell(value: stats.inProgress, label: L10n.enrolledStatInProgress,
                 color: MyCoursesPalette.textPrimary)
            divider
            cell(value: stats.completed, label: L10n.enrolledStatCompleted,
                 color: EnrolledPalette.green)
            divider
            cell(value: stats.pending, label: L10n.enrolledStatPending,
                 color: EnrolledPalette.amber)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AuthFigmaColors.gold.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AuthFigmaColors.gold.opacity(0.25), lineWidth: 1))
    }

    private func cell(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.72)
                .foregroundColor(AuthFigmaColors.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(MyCoursesPalette.stroke)
            .frame(width: 0.5, height: 28)
    }
}

// MARK: - Instructor group card (Enrolled)

/// One instructor and their stacked active/pending course rows. A tinted
/// header (avatar, name, specialty, "N courses" pill, chevron) toggles the
/// rows open/closed. Figma 1923:6005.
private struct InstructorGroupCard: View {
    let group: MyCoursesViewModel.InstructorGroup
    let locale: String
    let isExpanded: Bool
    let onToggle: () -> Void

    private var ar: Bool { locale == "ar" }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                ForEach(group.courses) { course in
                    rowDivider
                    courseRow(course)
                }
                ForEach(group.pending) { req in
                    rowDivider
                    pendingRow(req)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(MyCoursesPalette.stroke)
            .frame(height: 0.5)
    }

    // MARK: Header

    private var header: some View {
        Button(action: onToggle) {
            HStack(spacing: 11) {
                EnrolledAvatar(seed: group.id,
                               initials: EnrolledAvatar.initials(from: group.name),
                               size: 40, cornerRadius: 20, fontSize: 14,
                               avatarUrl: group.avatarUrl)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .lineLimit(1)
                    if let title = group.localizedTitle(locale: locale) {
                        Text(title)
                            .font(.system(size: 11))
                            .foregroundColor(AuthFigmaColors.gold)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                coursesPill
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AuthFigmaColors.muted)
                    .rotationEffect(.degrees(isExpanded ? 0 : (ar ? 90 : -90)))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(AuthFigmaColors.gold.opacity(0.05))
        }
        .buttonStyle(.plain)
    }

    private var coursesPill: some View {
        HStack(spacing: 5) {
            Text("\(group.totalCount)")
                .font(.system(size: 11, weight: .bold))
            Text(group.totalCount == 1
                 ? L10n.enrolledCourseSingular
                 : L10n.enrolledCoursePlural)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundColor(AuthFigmaColors.gold)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Capsule().fill(AuthFigmaColors.gold.opacity(0.12)))
        .overlay(Capsule().stroke(AuthFigmaColors.gold.opacity(0.35), lineWidth: 1))
    }

    // MARK: Course rows

    private func courseRow(_ course: EnrolledCourse) -> some View {
        NavigationLink(value: course.id) {
            row(seed: course.id,
                title: course.localizedTitle(locale: locale),
                status: course.isCompleted
                    ? .completed
                    : .inProgress(course.progressPct / 100,
                                  pct: Int(course.progressPct.rounded()),
                                  liveSessions: course.liveSessionCount),
                coverUrl: course.coverUrl)
        }
        .buttonStyle(.plain)
    }

    private func pendingRow(_ req: EnrollmentRequest) -> some View {
        NavigationLink(value: req.courseId) {
            row(seed: req.courseId,
                title: req.localizedCourseTitle(locale: locale),
                status: .pending)
        }
        .buttonStyle(.plain)
    }

    /// Course-row leading tile. Shows the course cover image when one is
    /// available, falling back to the deterministic gradient monogram while
    /// it loads, on failure, or for rows that have no cover (pending
    /// requests).
    private func rowAvatar(seed: String, title: String,
                           coverUrl: String?) -> some View {
        ZStack {
            EnrolledAvatar(seed: seed,
                           initials: EnrolledAvatar.initials(from: title),
                           size: 42, cornerRadius: 9, fontSize: 15)
            if let url = coverUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.clear
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private func row(seed: String, title: String, status: RowStatus,
                     coverUrl: String? = nil) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 11) {
                rowAvatar(seed: seed, title: title, coverUrl: coverUrl)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .lineLimit(1)
                    statusLine(status)
                }
                Spacer(minLength: 6)
                Image(systemName: ar ? "chevron.left" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AuthFigmaColors.muted)
            }
            progressBar(status)
        }
        .padding(12)
        .background(EnrolledPalette.cardBg)
    }

    @ViewBuilder
    private func statusLine(_ status: RowStatus) -> some View {
        switch status {
        case .inProgress(_, let pct, let liveSessions):
            HStack(spacing: 5) {
                (Text("\(pct)% ").font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(AuthFigmaColors.gold)
                 + Text(L10n.enrolledPercentComplete)
                    .font(.system(size: 10.5))
                    .foregroundColor(AuthFigmaColors.muted))
                if liveSessions > 0 {
                    Text("·").foregroundColor(AuthFigmaColors.muted.opacity(0.6))
                    Text(String(format: liveSessions == 1
                                ? L10n.enrolledLiveSessionSingularFmt
                                : L10n.enrolledLiveSessionsFmt, liveSessions))
                        .font(.system(size: 10.5))
                        .foregroundColor(AuthFigmaColors.muted)
                }
            }
        case .completed:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(EnrolledPalette.green)
                Text(L10n.enrolledCompleted)
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.42)
                    .foregroundColor(EnrolledPalette.green)
            }
        case .pending:
            HStack(spacing: 6) {
                Circle()
                    .fill(EnrolledPalette.amber)
                    .frame(width: 5, height: 5)
                Text(L10n.enrolledPendingApproval)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(EnrolledPalette.amber)
            }
        }
    }

    private func progressBar(_ status: RowStatus) -> some View {
        GeometryReader { geo in
            ZStack(alignment: ar ? .trailing : .leading) {
                Capsule().fill(MyCoursesPalette.stroke)
                switch status {
                case .inProgress(let fraction, _, _):
                    Capsule()
                        .fill(LinearGradient(
                            colors: [EnrolledPalette.goldStrong, AuthFigmaColors.gold],
                            startPoint: ar ? .trailing : .leading,
                            endPoint: ar ? .leading : .trailing))
                        .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
                case .completed:
                    Capsule().fill(EnrolledPalette.green.opacity(0.3))
                case .pending:
                    Capsule().fill(EnrolledPalette.amber.opacity(0.3))
                }
            }
        }
        .frame(height: 4)
    }

    /// Course / pending row visual state.
    private enum RowStatus {
        case inProgress(Double, pct: Int, liveSessions: Int)
        case completed
        case pending
    }
}

// MARK: - Gradient initials avatar (Enrolled)

/// Rounded gradient tile with a two-letter monogram, used by the Enrolled
/// instructor headers and course rows. Colour is derived deterministically
/// from a seed so the same instructor/course keeps a stable hue.
private struct EnrolledAvatar: View {
    let seed: String
    let initials: String
    let size: CGFloat
    let cornerRadius: CGFloat
    let fontSize: CGFloat
    /// Presigned avatar URL. When non-nil/non-blank the image loads over
    /// the gradient monogram and replaces it on `.success`; every other
    /// phase leaves the monogram showing. Defaults to nil so existing
    /// initials-only call sites are unchanged.
    var avatarUrl: String? = nil

    var body: some View {
        let color = Self.color(for: seed)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(LinearGradient(
                colors: [color, color.opacity(0.72)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(.white))
            .overlay {
                if let url = avatarUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            Color.clear
                        }
                    }
                    .frame(width: size, height: size)
                    .clipShape(shape)
                }
            }
    }

    private static let palette: [Color] = [
        Color(red: 0.55, green: 0.36, blue: 0.96),
        Color(red: 0.20, green: 0.55, blue: 0.95),
        Color(red: 0.95, green: 0.55, blue: 0.20),
        Color(red: 0.20, green: 0.70, blue: 0.45),
        Color(red: 0.93, green: 0.35, blue: 0.60),
        Color(red: 0.90, green: 0.72, blue: 0.25)
    ]

    static func color(for seed: String) -> Color {
        var hash = 5381
        for byte in seed.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        return palette[abs(hash) % palette.count]
    }

    /// Two-letter monogram, skipping honorific prefixes ("Dr.", "Prof.").
    static func initials(from name: String) -> String {
        let honorifics: Set<String> = ["dr", "dr.", "prof", "prof.", "eng", "eng.",
                                       "mr", "mr.", "mrs", "mrs.", "ms", "ms."]
        let words = name.split(separator: " ").map(String.init)
            .filter { !honorifics.contains($0.lowercased()) }
        let letters = words.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

// MARK: - Explore course row (instructor profile "their courses" list)

/// Two-row course card. Still used by the instructor profile screen's
/// course list; the Explore tab itself is now instructor-first.
struct ExploreCourseRow: View {
    let course: CourseSummary
    let locale: String

    // Hidden for now (2026-07): reviews/ratings paused platform-wide.
    private var hideReviews: Bool { true }

    private var ar: Bool { locale == "ar" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            cover

            VStack(alignment: .leading, spacing: 4) {
                Text(course.localizedTitle(locale: locale))
                    .font(BrandFont.displaySemiBold(size: 16, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.textPrimary)
                    .lineLimit(1)
                Text(course.instructorName)
                    .font(BrandFont.display(size: 12, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.muted)
                    .lineLimit(1)
                metaLine
                bottomLine
                if course.enrolled {
                    Text(L10n.enrolled)
                        .font(BrandFont.display(size: 11, isArabic: ar))
                        .foregroundColor(MyCoursesPalette.success)
                }
            }
        }
        .padding(14)
        .background(AuthFigmaColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AuthFigmaColors.chipBg)
            if let url = course.coverUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.clear
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(width: 56, height: 56)
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            Text("\(course.lessonCount) \(L10n.lessonsLowercase)")
            // Hidden for now (2026-07): reviews/ratings paused platform-wide.
            if !hideReviews, let avg = course.ratingAvg {
                Text("·")
                Text(String(format: "★ %.1f", avg))
            }
        }
        .font(BrandFont.display(size: 12, isArabic: ar))
        .foregroundColor(AuthFigmaColors.muted)
    }

    /// Price only. The "{N} students enrolled" label that used to sit opposite
    /// it was removed platform-wide (2026-08); pricing is separately hidden
    /// (2026-07), so this row is usually empty and simply collapses.
    private var bottomLine: some View {
        HStack(alignment: .firstTextBaseline) {
            priceLabel
            Spacer(minLength: 8)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var priceLabel: some View {
        // Hidden for now (2026-07): pricing removed from app for ALL users,
        // not just auto-enroll students. Old auto-enroll gate kept below so
        // it can be restored:
        // if AuthSession.shared.currentUser?.isAutoEnroll != true {
        //     Text(course.formattedPrice)
        //         .font(BrandFont.displaySemiBold(size: 15, isArabic: ar))
        //         .foregroundColor(MyCoursesPalette.success)
        // }
        EmptyView()
    }
}

// MARK: - Instructor browse card (Explore)

/// Expandable instructor card for the instructor-first Explore surface
/// (figma node 1888-7960). Header (initials/avatar + name + title), a 2×2
/// stat grid (Years / Rating / Students / Courses), and an expandable
/// "View courses" drawer that lazily reveals the instructor's top courses
/// with a gold "See all" pill that pushes the full profile.
struct InstructorBrowseRow: View {
    let instructor: StudentInstructorSummary
    let locale: String
    /// `nil` until the drawer has been opened and the fetch resolves.
    let courses: [CourseSummary]?
    let isLoadingCourses: Bool
    /// Kicks off the lazy course fetch the first time the drawer opens.
    let onExpand: () -> Void
    /// Opens the enrollment sheet for a tapped course (the user is still
    /// deciding to enrol, so this presents the request sheet rather than
    /// pushing the full course screen).
    let onCourseTap: (String) -> Void

    @State private var expanded = false
    private var ar: Bool { locale == "ar" }

    // Hidden for now (2026-07): reviews/ratings paused platform-wide.
    private var hideReviews: Bool { true }

    /// Warm surface→gold wash used on the stat panel and the course mini-rows.
    /// Mirrors the Figma `linear-gradient(157deg, black 31%, rgba(198,169,107,0.5) 166%)`
    /// — the box only samples up to ~51% toward the gold handle, so the
    /// reachable corner is a warm tint, not full gold. Both stops adapt: the
    /// dark theme still lands on ~#45392A (the original brown), light mode
    /// runs cream → pale gold so the panel text stays legible.
    static let goldWash = LinearGradient(
        stops: [
            .init(color: MyCoursesPalette.surfaceRaised, location: 0.12),
            .init(color: AuthFigmaColors.gold.opacity(0.22), location: 1.0)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Dim 9px label colour inside the stat panel (Figma rgba(235,235,245,0.45)).
    static let statLabel = MyCoursesPalette.muted

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            // Stats hidden for now (2026-07): show the instructor's bio in
            // place of the 2×2 stat panel. statPanel is kept below for restore.
            // statPanel
            bioPanel
            drawerToggle
            if expanded { drawer }
        }
        .padding(15)
        .background(AuthFigmaColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(expanded
                        ? Color(red: 0x63/255, green: 0x56/255, blue: 0x3A/255)
                        : MyCoursesPalette.stroke,
                        lineWidth: 1))
    }

    // MARK: Header

    private var header: some View {
        NavigationLink(value: CoursesTabView.InstructorRoute(id: instructor.id)) {
            HStack(alignment: .top, spacing: 11) {
                avatar(size: 52, cornerRadius: 26, initialsSize: 18,
                       url: instructor.avatarUrl, seed: instructor.id,
                       initials: Self.initials(from: instructor.displayName))
                VStack(alignment: .leading, spacing: 2) {
                    Text(instructor.displayName)
                        .font(BrandFont.sansMedium(size: 16, isArabic: ar))
                        .foregroundColor(AuthFigmaColors.textPrimary)
                        .lineLimit(1)
                    if let title = instructor.localizedTitle(locale: locale) {
                        Text(title)
                            .font(BrandFont.sans(size: 11.5, isArabic: ar))
                            .foregroundColor(AuthFigmaColors.gold)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 2)
                Spacer(minLength: 4)
                Image(systemName: ar ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AuthFigmaColors.muted)
                    .padding(.top, 5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Bio panel (replaces the stat panel while stats are hidden)

    /// The instructor's bio on the same gold-wash surface the stat panel
    /// used, truncated to a few lines. Renders nothing when the instructor
    /// has no bio, so a card without a bio simply omits the panel.
    @ViewBuilder
    private var bioPanel: some View {
        if let bio = instructor.localizedBio(locale: locale) {
            Text(bio)
                .font(BrandFont.sans(size: 12.5, isArabic: ar))
                .foregroundColor(AuthFigmaColors.textPrimary.opacity(0.85))
                .lineSpacing(3)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Self.goldWash))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
        }
    }

    // MARK: Stat panel (2×2, single gold-wash surface)

    private var statPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                statItem(icon: "clock.fill",
                         value: instructor.formattedYears,
                         label: L10n.exploreStatYears)
                // Hidden for now (2026-07): reviews/ratings paused
                // platform-wide — the Rating stat cell is hidden.
                if !hideReviews {
                    statItem(icon: "star.fill",
                             value: instructor.ratingAvg.map { String(format: "%.1f", $0) } ?? "—",
                             label: L10n.exploreStatRating)
                }
            }
            HStack(spacing: 8) {
                // Students cell removed platform-wide (2026-08). This whole
                // panel is currently unrendered (see `bioPanel`) — dropping the
                // cell here too so a restore doesn't bring the count back.
                statItem(icon: "book.fill",
                         value: "\(instructor.coursesCount)",
                         label: L10n.exploreStatCourses)
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Self.goldWash))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AuthFigmaColors.gold)
                .frame(width: 13, height: 13)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(BrandFont.sansMedium(size: 13, isArabic: ar))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(label.uppercased())
                    .font(BrandFont.sans(size: 9, isArabic: ar))
                    .foregroundColor(Self.statLabel)
                    .tracking(0.72)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Drawer

    private var drawerToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            if expanded { onExpand() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AuthFigmaColors.gold)
                Text(L10n.exploreViewCourses)
                    .font(BrandFont.sans(size: 11.5, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.gold)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AuthFigmaColors.gold)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AuthFigmaColors.gold.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(AuthFigmaColors.gold.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var drawer: some View {
        if let courses {
            if courses.isEmpty {
                Text(L10n.exploreNoCourses)
                    .font(BrandFont.display(size: 12, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            } else {
                VStack(spacing: 10) {
                    ForEach(courses.prefix(3)) { course in
                        courseMiniRow(course)
                    }
                    if instructor.coursesCount > 3 {
                        seeAllPill
                    }
                }
            }
        } else if isLoadingCourses {
            HStack {
                Spacer()
                ProgressView().tint(AuthFigmaColors.gold)
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private func courseMiniRow(_ course: CourseSummary) -> some View {
        Button { onCourseTap(course.id) } label: {
            HStack(spacing: 10) {
                avatar(size: 38, cornerRadius: 8, initialsSize: 13,
                       url: course.coverUrl, seed: course.id,
                       initials: Self.initials(from: course.localizedTitle(locale: locale)))
                VStack(alignment: .leading, spacing: 2) {
                    if course.ratingCount == 0 {
                        Text(L10n.exploreNewBadge.uppercased())
                            .font(BrandFont.sans(size: 7.5, isArabic: ar))
                            .tracking(0.6)
                            .foregroundColor(EnrolledPalette.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(EnrolledPalette.green.opacity(0.18)))
                            .overlay(Capsule().stroke(EnrolledPalette.green.opacity(0.5), lineWidth: 1))
                    }
                    Text(course.localizedTitle(locale: locale))
                        .font(BrandFont.sansMedium(size: 12.5, isArabic: ar))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .lineLimit(1)
                    courseMeta(course)
                }
                Spacer(minLength: 4)
                Image(systemName: ar ? "chevron.left" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AuthFigmaColors.gold)
            }
            .padding(.horizontal, 10)
            .padding(.top, 13)
            .padding(.bottom, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Self.goldWash))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(MyCoursesPalette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// "{N} lessons · ★{rating}" with the rating in gold and the separator
    /// dimmed, matching the Figma meta line. The trailing "· {M} enrolled" was
    /// removed platform-wide (2026-08), taking its separator with it.
    @ViewBuilder
    private func courseMeta(_ c: CourseSummary) -> some View {
        let dim = MyCoursesPalette.muted
        let dot = MyCoursesPalette.textTertiary
        HStack(spacing: 7) {
            Text("\(c.lessonCount) \(L10n.lessonsLowercase)")
                .foregroundColor(dim)
            // Hidden for now (2026-07): reviews/ratings paused platform-wide.
            if !hideReviews, let avg = c.ratingAvg {
                Text("·").foregroundColor(dot)
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundColor(AuthFigmaColors.gold)
                    Text(String(format: "%.1f", avg))
                        .foregroundColor(AuthFigmaColors.gold)
                }
            }
        }
        .font(BrandFont.sans(size: 10, isArabic: ar))
        .lineLimit(1)
    }

    private var seeAllPill: some View {
        NavigationLink(value: CoursesTabView.InstructorRoute(id: instructor.id)) {
            HStack(spacing: 5) {
                Text(L10n.exploreSeeAll)
                    .font(BrandFont.sansMedium(size: 11.5, isArabic: ar))
                Image(systemName: ar ? "chevron.left" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(Color(red: 0x1A/255, green: 0x13/255, blue: 0x05/255))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient.droobButtonGradient))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 2)
    }

    // MARK: Avatar / initials helpers

    @ViewBuilder
    private func avatar(size: CGFloat, cornerRadius: CGFloat, initialsSize: CGFloat,
                        url: String?, seed: String, initials: String) -> some View {
        let color = Self.avatarColor(for: seed)
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: [color, color.opacity(0.72)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            if let u = url.flatMap(URL.init(string:)) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default:
                        Text(initials)
                            .font(.system(size: initialsSize, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                Text(initials)
                    .font(.system(size: initialsSize, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
    }

    private static let avatarColors: [Color] = [
        Color(red: 0.55, green: 0.36, blue: 0.96),
        Color(red: 0.20, green: 0.55, blue: 0.95),
        Color(red: 0.95, green: 0.55, blue: 0.20),
        Color(red: 0.20, green: 0.70, blue: 0.45),
        Color(red: 0.93, green: 0.35, blue: 0.60),
        Color(red: 0.90, green: 0.72, blue: 0.25)
    ]

    private static func avatarColor(for seed: String) -> Color {
        var hash = 5381
        for byte in seed.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        return avatarColors[abs(hash) % avatarColors.count]
    }

    /// Two-letter monogram, skipping honorific prefixes ("Dr.", "Prof.").
    private static func initials(from name: String) -> String {
        let honorifics: Set<String> = ["dr", "dr.", "prof", "prof.", "eng", "eng.",
                                       "mr", "mr.", "mrs", "mrs.", "ms", "ms."]
        let words = name.split(separator: " ").map(String.init)
            .filter { !honorifics.contains($0.lowercased()) }
        let letters = words.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    static func abbreviate(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)"
    }
}

// MARK: - Enrolled row (My Courses)

/// Compact My Courses row built to the Figma redesign — cover icon,
/// title, "{instructor} · {N} lessons", a gold (in-progress) or green
/// (complete) progress bar with the trailing "X / Y" lesson fraction or
/// localised "Complete" label, plus a chevron to indicate the tap
/// affordance. Rows are hosted inside a single grouped surface so the
/// separator/divider treatment lives on the parent, not here.
struct MyCoursesEnrolledRow: View {
    let course: EnrolledCourse
    let locale: String

    private var ar: Bool { locale == "ar" }
    private var isComplete: Bool { course.isCompleted }
    private var completed: Int { course.completedLessonCount }
    private var total: Int { course.lessonCount }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            cover

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(course.localizedTitle(locale: locale))
                        .font(BrandFont.displaySemiBold(size: 16, isArabic: ar))
                        .foregroundColor(AuthFigmaColors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: ar ? "chevron.left" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AuthFigmaColors.muted)
                }
                Text(bidiJoin(course.instructorName, "\(total) \(L10n.lessonsLowercase)"))
                    .font(BrandFont.display(size: 12, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.muted)
                    .lineLimit(1)
                progressLine
            }
        }
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AuthFigmaColors.chipBg)
            if let url = course.coverUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.clear
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(width: 48, height: 48)
    }

    private var progressLine: some View {
        HStack(spacing: 10) {
            progressBar
            Text(trailingLabel)
                .font(BrandFont.display(size: 12, isArabic: ar))
                .foregroundColor(isComplete
                                 ? MyCoursesPalette.success
                                 : AuthFigmaColors.muted)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.top, 4)
    }

    private var trailingLabel: String {
        isComplete ? L10n.myCoursesCompleteLabel : "\(completed)/\(total)"
    }

    private var progressBar: some View {
        // Width is driven by completedLessonCount/lessonCount when both
        // are available so the bar matches the fraction shown alongside
        // it; falls back to progressPct (server-computed) when the
        // course has no lessons yet, avoiding a divide-by-zero.
        let pct: Double = {
            if total > 0 { return Double(completed) / Double(total) }
            return course.progressPct / 100
        }()
        return GeometryReader { geo in
            ZStack(alignment: ar ? .trailing : .leading) {
                Capsule()
                    .fill(MyCoursesPalette.stroke)
                Capsule()
                    .fill(isComplete ? MyCoursesPalette.success : AuthFigmaColors.gold)
                    .frame(width: max(0, geo.size.width * CGFloat(min(max(pct, 0), 1))))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Guest catalog (pre-login browse)
//
// Tokenless course list backing the pre-login "Browse Courses" surface
// (App Store Guideline 5.1.1(v) — free courses must be viewable without an
// account). Fetches the public catalog page via `executePublic` so a
// visitor can browse + preview before signing in.

@MainActor
final class GuestCatalogViewModel: ObservableObject {
    @Published private(set) var courses: [CourseSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasNextPage = true

    private var page = 0
    private let pageSize = 20
    private var isFetching = false

    func loadInitial() async {
        page = 0
        hasNextPage = true
        errorMessage = nil
        await fetch(reset: true)
    }

    func loadMore() async {
        guard hasNextPage, !isFetching else { return }
        await fetch(reset: false)
    }

    private func fetch(reset: Bool) async {
        guard !isFetching else { return }
        isFetching = true
        isLoading = courses.isEmpty
        defer { isFetching = false; isLoading = false }

        let request = APIRequest(
            path: "/v1/student/courses",
            method: .GET,
            queryItems: [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "size", value: "\(pageSize)")
            ])
        do {
            let result: SpringPage<CourseSummary> =
                try await AuthInterceptor.shared.executePublic(request)
            courses = reset ? result.content : courses + result.content
            hasNextPage = result.hasNextPage
            page += 1
        } catch {
            if APIClient.isCancellationError(error) { return }
            errorMessage = (error as? DroobError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

// MARK: - GuestBrowseView (pre-login)
//
// Presented from the Login screen. Lets a visitor scroll the catalog and
// open a course preview (`CourseDetailSheetView` in guest mode) without an
// account. Any enroll action routes to sign-in via `onSignIn`, which the
// host uses to dismiss back to the auth flow.

struct GuestBrowseView: View {
    /// Called when the guest chooses to sign in (top bar) or taps the enrol
    /// CTA inside a preview. The host dismisses this cover.
    let onSignIn: () -> Void

    @StateObject private var vm = GuestCatalogViewModel()
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @State private var previewItem: CourseSheetId?
    @Environment(\.dismiss) private var dismiss

    private var ar: Bool { appLocale == "ar" }

    private struct CourseSheetId: Identifiable { let id: String }

    var body: some View {
        NavigationStack {
            ZStack {
                AuthFigmaColors.bg.ignoresSafeArea()
                content
            }
            .navigationTitle(L10n.guestBrowseTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AuthFigmaColors.muted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onSignIn) {
                        Text(L10n.guestBrowseSignIn)
                            .font(BrandFont.displaySemiBold(size: 15, isArabic: ar))
                            .foregroundColor(AuthFigmaColors.gold)
                    }
                }
            }
            .coursePresentation(item: $previewItem) { item in
                courseSheet(item.id)
            }
        }
        .task { if vm.courses.isEmpty { await vm.loadInitial() } }
    }

    private func courseSheet(_ id: String) -> some View {
        CourseDetailSheetView(
            courseId: id,
            onRequireLogin: {
                previewItem = nil
                onSignIn()
            },
            onClose: { previewItem = nil })
            .adaptiveSheetChrome(background: AuthFigmaColors.bg)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.courses.isEmpty {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(0..<5, id: \.self) { _ in
                        MCSkeletonBlock(height: 96, cornerRadius: 16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        } else if let err = vm.errorMessage, vm.courses.isEmpty {
            ErrorBanner(message: err) { Task { await vm.loadInitial() } }
                .padding(.horizontal, 20)
        } else if vm.courses.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 34))
                    .foregroundColor(AuthFigmaColors.muted)
                Text(L10n.exploreNoCourses)
                    .font(BrandFont.display(size: 14, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.muted)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(vm.courses) { course in
                        Button { previewItem = CourseSheetId(id: course.id) } label: {
                            ExploreCourseRow(course: course, locale: appLocale)
                        }
                        .buttonStyle(.plain)
                    }
                    if vm.hasNextPage {
                        ProgressView()
                            .tint(AuthFigmaColors.gold)
                            .padding(.vertical, 14)
                            .onAppear { Task { await vm.loadMore() } }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable { await vm.loadInitial() }
        }
    }
}
