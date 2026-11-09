import SwiftUI

// MARK: - Instructor Profile (figma)
//
// Reached by tapping the instructor card on the course detail screen.
// Mirrors the first frame of the figma: big LH avatar + display name +
// professional title, a 4-tile stats grid (Students / Courses / Rating
// / Years), an "ABOUT" bio block, a full-width gold "Message" CTA that
// pushes the chat screen, and a "COURSES" list of the instructor's
// published courses (reusing `ExploreCourseRow`).

struct InstructorProfileView: View {
    let instructorId: String

    @StateObject private var viewModel: InstructorProfileViewModel
    @StateObject private var reviewsVm: InstructorReviewsViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    @State private var navigateToChat = false
    @State private var presentedCourseId: String? = nil
    @State private var profileTab: ProfileTab = .courses
    @State private var showRateSheet = false
    @State private var showDeleteReviewConfirm = false
    @State private var deletingReview = false
    @State private var deleteReviewError: String? = nil
    @State private var requestToCancel: EnrollmentRequest? = nil
    @State private var cancellingRequestId: String? = nil
    @State private var cancelRequestError: String? = nil

    /// Student-scoped tabs on the instructor profile. Courses lists the
    /// instructor's published catalog; Enrolled / Pending are the caller's
    /// own state with this instructor; Reviews is the instructor-level
    /// ratings surface.
    enum ProfileTab: String, CaseIterable, Hashable {
        case courses, enrolled, pending, reviews
        var label: String {
            switch self {
            case .courses:  return L10n.instructorProfileTabCourses
            case .enrolled: return L10n.instructorProfileTabEnrolled
            case .pending:  return L10n.instructorProfileTabPending
            case .reviews:  return L10n.instructorProfileTabReviews
            }
        }
    }

    init(instructorId: String, viewModelOverride: InstructorProfileViewModel? = nil) {
        self.instructorId = instructorId
        _viewModel = StateObject(
            wrappedValue: viewModelOverride ?? InstructorProfileViewModel(
                instructorId: instructorId))
        _reviewsVm = StateObject(
            wrappedValue: InstructorReviewsViewModel(instructorId: instructorId))
    }

    private var ar: Bool { appLocale == "ar" }

    // Hidden for now (2026-07): reviews/ratings paused platform-wide.
    private var hideReviews: Bool { true }

    /// Tabs actually rendered in the tab bar. The `reviews` enum case is
    /// kept so the tab (and all its code) can be restored by flipping
    /// `hideReviews`; it is only filtered out of the visible list.
    private var visibleTabs: [ProfileTab] {
        // Hidden for now (2026-07): reviews/ratings paused platform-wide.
        hideReviews ? ProfileTab.allCases.filter { $0 != .reviews }
                    : ProfileTab.allCases
    }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            content

            if let profile = viewModel.profile {
                // Hidden navigation link — push the chat when the user
                // taps "Message". Same hidden-link pattern the course
                // detail uses for checkout.
                NavigationLink(isActive: $navigateToChat) {
                    InstructorChatView(
                        instructorId: profile.id,
                        instructorName: profile.displayName,
                        instructorAvatarUrl: profile.avatarUrl,
                        // Tapping the chat header pops back here instead
                        // of pushing a second copy of this screen.
                        openedFromProfile: true)
                } label: { EmptyView() }
                .hidden()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .coursePresentation(item: courseSheetBinding, onDismiss: {
            Task { await viewModel.refreshStudentTabs() }
        }) { box in
            courseSheet(box)
        }
        .fullScreenCover(isPresented: $showRateSheet) {
            // Hidden for now (2026-07): reviews/ratings paused platform-wide.
            if !hideReviews {
                rateSheetContent
            }
        }
        .confirmationDialog(
            L10n.instructorReviewDeleteConfirmTitle,
            // Hidden for now (2026-07): reviews/ratings paused platform-wide —
            // the delete-review dialog never presents while hidden.
            isPresented: Binding(
                get: { !hideReviews && showDeleteReviewConfirm },
                set: { showDeleteReviewConfirm = $0 }),
            titleVisibility: .visible
        ) {
            Button(L10n.instructorReviewDeleteConfirmAction, role: .destructive) {
                Task { await deleteMyReview() }
            }
            Button(L10n.courseDetailRateSheetCancel, role: .cancel) {}
        } message: {
            Text(L10n.instructorReviewDeleteConfirmMessage)
        }
        .alert(L10n.instructorReviewDeleteFailed,
               isPresented: Binding(
                get: { deleteReviewError != nil },
                set: { if !$0 { deleteReviewError = nil } })) {
            Button(L10n.ok, role: .cancel) { deleteReviewError = nil }
        }
        .confirmationDialog(
            L10n.enrollRequestCancelConfirmTitle,
            isPresented: Binding(
                get: { requestToCancel != nil },
                set: { if !$0 { requestToCancel = nil } }),
            titleVisibility: .visible,
            presenting: requestToCancel
        ) { request in
            Button(L10n.enrollRequestCancelConfirmYes, role: .destructive) {
                Task { await cancelPendingRequest(request) }
            }
            Button(L10n.enrollRequestCancelConfirmNo, role: .cancel) {}
        } message: { _ in
            Text(L10n.enrollRequestCancelConfirmMessage)
        }
        .alert(L10n.coursesGenericError,
               isPresented: Binding(
                get: { cancelRequestError != nil },
                set: { if !$0 { cancelRequestError = nil } })) {
            Button(L10n.ok, role: .cancel) { cancelRequestError = nil }
        }
    }

    private func deleteMyReview() async {
        deletingReview = true
        let ok = await reviewsVm.delete()
        deletingReview = false
        if !ok { deleteReviewError = L10n.instructorReviewDeleteFailed }
    }

    @ViewBuilder
    private var rateSheetContent: some View {
        let sheet = RateInstructorSheet(
            instructorName: viewModel.profile?.displayName ?? "",
            avatarUrl: viewModel.profile?.avatarUrl,
            existing: reviewsVm.myReview,
            onSubmit: { stars, body in
                await reviewsVm.submit(stars: stars, body: body)
            },
            onClose: { showRateSheet = false })
        sheet
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.profile == nil {
            ProgressView()
                .tint(Color.droobGold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = viewModel.errorMessage, viewModel.profile == nil {
            ErrorBanner(message: err) {
                Task { await viewModel.load() }
            }
            .padding(.horizontal, 20)
        } else if let profile = viewModel.profile {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    backRow
                    identityHeader(profile)
                    // Hidden for now (2026-07): stat tiles replaced by the
                    // bio block below. Restore by uncommenting:
                    // statsGrid(profile)
                    aboutBlock(profile)
                    messageButton
                    tabBar
                    tabContent(profile)
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Back row

    private var backRow: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: ar ? "chevron.right" : "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.droobGold)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: Identity header

    private func identityHeader(_ profile: InstructorPublicProfile) -> some View {
        HStack(alignment: .center, spacing: 16) {
            ReviewAvatar(name: profile.displayName, avatarUrl: profile.avatarUrl)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                if let title = profile.localizedTitle(locale: appLocale) {
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(MyCoursesPalette.muted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Stats

    private func statsGrid(_ profile: InstructorPublicProfile) -> some View {
        HStack(spacing: 10) {
            // Students tile removed platform-wide (2026-08) — see `statsRow`
            // in CourseDetailView for the same call.
            statTile(value: "\(profile.coursesCount)",
                     label: L10n.instructorProfileCourses)
            statTile(value: profile.ratingAvg.map { String(format: "★ %.1f", $0) } ?? "—",
                     label: L10n.instructorProfileRating)
            statTile(value: profile.formattedYears,
                     label: L10n.instructorProfileYears)
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(InstructorFigma.statLabel)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 13)
        .background(InstructorFigma.statCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(InstructorFigma.statCardBorder, lineWidth: 1))
    }

    // MARK: About

    @ViewBuilder
    private func aboutBlock(_ profile: InstructorPublicProfile) -> some View {
        // 2026-07: the bio replaces the stat grid as the profile's lead
        // section — current-language bio first, falling back to the other
        // language, and the whole section hides when both are empty (the
        // old placeholder line is kept commented for reference).
        if let bio = profile.bestBio(locale: appLocale) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.instructorProfileAbout)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
                    .tracking(1.2)
                // Old placeholder-backed line (pre-2026-07):
                // Text(profile.localizedBio(locale: appLocale)
                //      ?? L10n.instructorProfileBioPlaceholder)
                Text(bio)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.primary.opacity(0.92))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MyCoursesPalette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            }
        }
    }

    // MARK: Message button

    private var messageButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button { navigateToChat = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.instructorProfileMessage)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(InstructorFigma.gold)
                .frame(width: 174)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(InstructorFigma.gold.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    // MARK: Tab bar

    private var tabBar: some View {
        // Underline tab row (figma): the active label is gold + bold with a
        // 2px gold underline and a count badge; inactive labels stay muted.
        // A faint hairline runs the full width along the bottom edge.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // Hidden for now (2026-07): reviews/ratings paused
                // platform-wide — `visibleTabs` filters out `.reviews`
                // (was: ProfileTab.allCases).
                ForEach(visibleTabs, id: \.self) { tab in
                    tabButton(tab)
                }
                Spacer(minLength: 0)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MyCoursesPalette.stroke)
                .frame(height: 1)
        }
    }

    private func tabButton(_ tab: ProfileTab) -> some View {
        let active = profileTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { profileTab = tab }
        } label: {
            HStack(spacing: 6) {
                Text(tab.label)
                    .font(.system(size: 14, weight: active ? .bold : .regular))
                    .foregroundColor(active ? InstructorFigma.gold : MyCoursesPalette.muted)
                if let count = tabCount(tab) {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(active ? InstructorFigma.badgeDark : MyCoursesPalette.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(active
                                           ? InstructorFigma.gold
                                           : MyCoursesPalette.surface))
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.top, 9)
            .padding(.bottom, 11)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(active ? InstructorFigma.gold : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func tabCount(_ tab: ProfileTab) -> Int? {
        switch tab {
        case .courses:
            return viewModel.profile?.courses.count
        case .enrolled:
            let n = viewModel.enrolledCourses.count
            return n > 0 ? n : nil
        case .pending:
            let n = viewModel.pendingRequests.count
            return n > 0 ? n : nil
        case .reviews:
            let n = reviewsVm.distribution.ratingCount
            return n > 0 ? n : nil
        }
    }

    @ViewBuilder
    private func tabContent(_ profile: InstructorPublicProfile) -> some View {
        switch profileTab {
        case .courses:  coursesTab(profile)
        case .enrolled: enrolledTab
        case .pending:  pendingTab
        case .reviews:
            // Hidden for now (2026-07): reviews/ratings paused platform-wide —
            // unreachable while the tab is filtered out, gated defensively.
            if !hideReviews { reviewsTab }
        }
    }

    // MARK: Courses tab

    @ViewBuilder
    private func coursesTab(_ profile: InstructorPublicProfile) -> some View {
        if profile.courses.isEmpty {
            tabEmptyState(icon: "book.closed",
                          text: L10n.instructorProfileCoursesEmpty)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(profile.courses) { course in
                    Button {
                        presentedCourseId = course.id
                    } label: {
                        InstructorCourseCard(course: course, locale: appLocale)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Enrolled tab

    @ViewBuilder
    private var enrolledTab: some View {
        if viewModel.enrolledCourses.isEmpty {
            InstructorEnrolledEmptyView(
                instructorName: viewModel.profile?.displayName ?? "")
        } else {
            let courses = viewModel.enrolledCourses
            let completed = courses.filter(\.isCompleted).count
            let inProgress = courses.count - completed
            VStack(alignment: .leading, spacing: 11) {
                enrolledHeader(inProgress: inProgress, completed: completed)
                ForEach(courses) { course in
                    Button {
                        presentedCourseId = course.id
                    } label: {
                        InstructorEnrolledCard(course: course, locale: appLocale)
                    }
                    .buttonStyle(.plain)
                }
                enrolledOtherCoursesFooter
            }
        }
    }

    /// "Your courses with Layla" + "N in progress · M completed".
    private func enrolledHeader(inProgress: Int, completed: Int) -> some View {
        let meta = bidiJoin(
            String(format: L10n.instructorProfileEnrolledInProgressFmt, inProgress),
            String(format: L10n.instructorProfileEnrolledCompletedFmt, completed)
        )
        return VStack(alignment: .leading, spacing: 2) {
            Text(String(format: L10n.instructorProfileEnrolledHeaderFmt,
                        enrolledGivenName))
                .font(BrandFont.sansBold(size: 16, isArabic: ar))
                .foregroundColor(MyCoursesPalette.textPrimary)
            Text(meta)
                .font(BrandFont.sans(size: 11.5, isArabic: ar))
                .foregroundColor(InstructorFigma.ageMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 1)
    }

    /// Dashed "See {name}'s N other courses" pill → jumps to the Courses tab.
    /// `N` is the instructor's published catalog minus the courses already
    /// enrolled in; hidden when there is nothing else to browse.
    @ViewBuilder
    private var enrolledOtherCoursesFooter: some View {
        let total = viewModel.profile?.courses.count ?? 0
        let others = max(0, total - viewModel.enrolledCourses.count)
        if others > 0 {
            Button {
                withAnimation { profileTab = .courses }
            } label: {
                Text(String(format: L10n.instructorProfileSeeOtherCoursesFmt,
                            enrolledShortName.bidiIsolated, others))
                    .font(BrandFont.sansBold(size: 12.5, isArabic: ar))
                    .foregroundColor(InstructorFigma.gold)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(MyCoursesPalette.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                InstructorFigma.gold.opacity(0.3),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    /// Given name only — "Dr. Layla Hassan" → "Layla".
    private var enrolledGivenName: String {
        let parts = (viewModel.profile?.displayName ?? "").split(separator: " ")
        if let first = parts.first, first.hasSuffix("."), parts.count >= 2 {
            return String(parts[1])
        }
        return parts.first.map(String.init) ?? ""
    }

    /// Honorific + given name — "Dr. Layla Hassan" → "Dr. Layla".
    private var enrolledShortName: String {
        let parts = (viewModel.profile?.displayName ?? "").split(separator: " ")
        guard let first = parts.first else { return "" }
        if first.hasSuffix("."), parts.count >= 2 {
            return "\(first) \(parts[1])"
        }
        return String(first)
    }

    // MARK: Pending tab

    @ViewBuilder
    private var pendingTab: some View {
        if viewModel.pendingRequests.isEmpty {
            tabEmptyState(icon: "clock",
                          text: L10n.instructorProfilePendingEmpty)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.pendingRequests) { request in
                    InstructorPendingRow(
                        request: request,
                        locale: appLocale,
                        isCancelling: cancellingRequestId == request.id,
                        onOpen: { presentedCourseId = request.courseId },
                        onCancel: { requestToCancel = request })
                }
            }
        }
    }

    private func cancelPendingRequest(_ request: EnrollmentRequest) async {
        cancellingRequestId = request.id
        let ok = await viewModel.cancelPendingRequest(request)
        cancellingRequestId = nil
        if !ok { cancelRequestError = L10n.coursesGenericError }
    }

    // MARK: Reviews tab

    @ViewBuilder
    private var reviewsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if reviewsVm.isLoading && reviewsVm.reviews.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    MCSkeletonBlock(height: 96, cornerRadius: 14)
                }
            } else if reviewsVm.reviews.isEmpty {
                tabEmptyState(icon: "star",
                              text: L10n.instructorReviewEmpty)
                reviewCTA.padding(.top, 4)
            } else {
                // The caller's own review is lifted to the top, badged
                // "Your review", and carries the edit/delete affordances.
                if let mine = reviewsVm.myReview {
                    InstructorMyReviewCard(
                        review: mine,
                        isDeleting: deletingReview,
                        onEdit: { showRateSheet = true },
                        onDelete: { showDeleteReviewConfirm = true })
                }

                if !otherReviews.isEmpty {
                    Text(String(format: L10n.instructorProfileAllReviewsFmt,
                                reviewsVm.distribution.ratingCount))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(InstructorFigma.gold)
                        .padding(.top, reviewsVm.myReview == nil ? 0 : 4)
                        .padding(.bottom, 2)
                }

                LazyVStack(spacing: 10) {
                    ForEach(otherReviews) { review in
                        InstructorReviewCard(review: review)
                    }
                    if reviewsVm.hasNextPage {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(Color.droobGold)
                                .onAppear { Task { await reviewsVm.loadMore() } }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                }

                // Only show the bottom add-review CTA when the caller hasn't
                // reviewed yet — once they have, edit/delete live on the card.
                if reviewsVm.myReview == nil {
                    reviewCTA.padding(.top, 4)
                }
            }
        }
        .task { await reviewsVm.loadInitial() }
    }

    /// Reviews list with the caller's own row removed — it renders separately
    /// at the top so the "All reviews" section shows only everyone else.
    private var otherReviews: [InstructorReview] {
        guard let mineId = reviewsVm.myReview?.id else { return reviewsVm.reviews }
        return reviewsVm.reviews.filter { $0.id != mineId }
    }

    // The add-review affordance is gated on enrollment: a student can only
    // review an instructor they've actually studied with. When they have no
    // enrolled course, the figma shows a disabled grey "Enroll first" button.
    @ViewBuilder
    private var reviewCTA: some View {
        if viewModel.enrolledCourses.isEmpty {
            Text(L10n.instructorProfileEnrollFirst)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(InstructorFigma.disabledCtaText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(InstructorFigma.disabledCtaBg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Button { showRateSheet = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "star.bubble")
                        .font(.system(size: 15, weight: .semibold))
                    Text(reviewsVm.myReview == nil
                         ? L10n.instructorReviewRateButton
                         : L10n.instructorReviewEditButton)
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(LinearGradient.droobBrand)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func tabEmptyState(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(MyCoursesPalette.muted)
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
    }

    // MARK: Course sheet binding

    private struct CourseSheetItem: Identifiable, Equatable { let id: String }
    private var courseSheetBinding: Binding<CourseSheetItem?> {
        Binding(
            get: { presentedCourseId.map(CourseSheetItem.init(id:)) },
            set: { presentedCourseId = $0?.id })
    }

    private func courseSheet(_ box: CourseSheetItem) -> some View {
        CourseDetailSheetView(courseId: box.id) { presentedCourseId = nil }
            .adaptiveSheetChrome(background: AuthFigmaColors.bg)
    }
}

// MARK: - Pending request row (figma)
//
// One PENDING enrollment request under the instructor's "Pending" tab.
// Orange icon tile + course initials, the requested course title, a
// "PENDING" pill with a "N waiting" stamp, the student's note in a
// gold-bordered quote block, and Edit note / Cancel affordances. Both
// affordances open the course sheet, where edit/cancel actually live.

struct InstructorPendingRow: View {
    let request: EnrollmentRequest
    let locale: String
    let isCancelling: Bool
    let onOpen: () -> Void
    let onCancel: () -> Void

    private var isArabic: Bool { locale == "ar" }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            headerRow
            if let note = request.note, !note.isEmpty {
                noteBlock(note)
            }
            buttonsRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstructorFigma.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(InstructorFigma.orange.opacity(0.3), lineWidth: 1))
    }

    private var headerRow: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(InstructorFigma.orangeTileGradient)
                .frame(width: 46, height: 46)
                .overlay(
                    Text(InstructorFigma.initials(
                        from: request.localizedCourseTitle(locale: locale)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white))
            VStack(alignment: .leading, spacing: 4) {
                Text(request.localizedCourseTitle(locale: locale))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    pendingPill
                    Text(waitingText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(InstructorFigma.waitingText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var pendingPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(InstructorFigma.orange)
                .frame(width: 5, height: 5)
            Text(L10n.instructorProfilePendingPill.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.57)
                .foregroundColor(InstructorFigma.orange)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(InstructorFigma.orange.opacity(0.14)))
        .overlay(Capsule().stroke(InstructorFigma.orange.opacity(0.4), lineWidth: 1))
    }

    private func noteBlock(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.instructorProfileYourNote.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1.08)
                .foregroundColor(InstructorFigma.gold.opacity(0.7))
            Text("“\(note)”")
                .font(.system(size: 12, weight: .light))
                .foregroundColor(InstructorFigma.noteText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 15)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(
            MyCoursesPalette.surfaceRaised
                .clipShape(.rect(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                 bottomTrailingRadius: 9, topTrailingRadius: 9)))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(InstructorFigma.gold.opacity(0.4))
                .frame(width: 3)
        }
    }

    private var buttonsRow: some View {
        HStack(spacing: 6) {
            Button(action: onOpen) {
                Text(L10n.instructorProfileEditNote)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(InstructorFigma.editBtnText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(MyCoursesPalette.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button(action: onCancel) {
                HStack(spacing: 3) {
                    if isCancelling {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(InstructorFigma.red)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    Text(L10n.cancel)
                        .font(.system(size: 11, weight: .regular))
                }
                .foregroundColor(InstructorFigma.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(InstructorFigma.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(InstructorFigma.red.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isCancelling)

            Spacer(minLength: 0)
        }
        .padding(.top, 11)
        .overlay(alignment: .top) {
            Rectangle().fill(MyCoursesPalette.stroke).frame(height: 1)
        }
    }

    /// "2 days waiting" — coarse elapsed since the request was created.
    private var waitingText: String {
        let seconds = Int(Date().timeIntervalSince(request.createdAt))
        switch seconds {
        case ..<3600:
            return L10n.instructorProfileWaitingJustNow
        case 3600..<86_400:
            return String(format: L10n.instructorProfileWaitingHoursFmt, seconds / 3600)
        case 86_400..<604_800:
            return String(format: L10n.instructorProfileWaitingDaysFmt, seconds / 86_400)
        default:
            return String(format: L10n.instructorProfileWaitingWeeksFmt, seconds / 604_800)
        }
    }
}

// MARK: - Rating summary (histogram)
//
// Big average + star row + review count on the left, a 5→1 star bucket
// histogram on the right. Reuses the same RatingDistribution shape and
// visual treatment as the course-detail ratings card.

struct InstructorRatingSummary: View {
    let distribution: RatingDistribution
    let locale: String

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedAverage)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.primary)
                starRow(filled: filledStars(distribution.ratingAvg ?? 0))
                Text(String(format: L10n.courseDetailRatingsCountFmt, distribution.ratingCount))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            VStack(spacing: 6) {
                ForEach(distribution.buckets) { bucket in
                    histogramRow(bucket: bucket)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    private var formattedAverage: String {
        guard let avg = distribution.ratingAvg else { return "—" }
        return String(format: "%.1f", avg)
    }

    private func filledStars(_ value: Double) -> Int {
        max(0, min(5, Int(value.rounded())))
    }

    private func starRow(filled: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < filled ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundColor(Color.droobGold)
            }
        }
    }

    private func histogramRow(bucket: RatingDistribution.Bucket) -> some View {
        HStack(spacing: 8) {
            Text("\(bucket.stars)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(MyCoursesPalette.muted)
                .frame(width: 8, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MyCoursesPalette.stroke)
                    Capsule()
                        .fill(Color.droobGold.opacity(0.85))
                        .frame(width: max(2, geo.size.width * CGFloat(bucket.percent) / 100))
                }
            }
            .frame(height: 6)
            Text("\(bucket.percent)%")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

// MARK: - Instructor review card
//
// One row in the instructor Ratings & Reviews list. Mirrors the
// course-detail review card: initials avatar, author, star row + relative
// age (reads `updatedAt` so edits surface as fresh), then the body.

struct InstructorReviewCard: View {
    let review: InstructorReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                InstructorReviewAvatar(name: review.authorName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.authorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        HStack(spacing: 1) {
                            ForEach(0..<5, id: \.self) { i in
                                Image(systemName: i < review.stars ? "star.fill" : "star")
                                    .font(.system(size: 10))
                                    .foregroundColor(InstructorFigma.gold)
                            }
                        }
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundColor(InstructorFigma.dotMuted)
                        Text(ReviewAgeFormatter.relative(from: review.updatedAt))
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundColor(InstructorFigma.ageMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            if let body = review.body, !body.isEmpty {
                Text("“\(body)”")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(InstructorFigma.reviewBody)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstructorFigma.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(InstructorFigma.cardBorder, lineWidth: 1))
    }
}

// MARK: - Instructor "your review" card (figma 1933:8010)
//
// The caller's own review, lifted to the top of the Reviews tab. Same
// anatomy as `InstructorReviewCard` but gold-tinted (bg gold-6%, border
// gold-40%), badged "YOUR REVIEW", and carrying Edit / Delete actions under
// a hairline divider. Backs the figma's owner-review affordance.

struct InstructorMyReviewCard: View {
    let review: InstructorReview
    let isDeleting: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    private static let red = Color(red: 1.0, green: 0.271, blue: 0.227)  // #FF453A

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if let body = review.body, !body.isEmpty {
                Text("“\(body)”")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(InstructorFigma.reviewBody)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actionsRow
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstructorFigma.gold.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(InstructorFigma.gold.opacity(0.40), lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            InstructorReviewAvatar(name: review.authorName)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(review.authorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .lineLimit(1)
                    Text(L10n.instructorReviewYourReviewBadge)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.54)
                        .foregroundColor(InstructorFigma.gold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(InstructorFigma.gold.opacity(0.18))
                        .clipShape(Capsule())
                }
                HStack(spacing: 7) {
                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: i < review.stars ? "star.fill" : "star")
                                .font(.system(size: 10))
                                .foregroundColor(InstructorFigma.gold)
                        }
                    }
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundColor(InstructorFigma.dotMuted)
                    Text(ReviewAgeFormatter.relative(from: review.updatedAt))
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundColor(InstructorFigma.ageMuted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Button(action: onEdit) {
                actionLabel(icon: "pencil",
                            text: L10n.instructorReviewCardEdit,
                            tint: InstructorFigma.reviewBody,
                            bg: MyCoursesPalette.surfaceRaised,
                            border: MyCoursesPalette.stroke)
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)

            Button(action: onDelete) {
                HStack(spacing: 5) {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Self.red)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(Self.red)
                    }
                    Text(L10n.instructorReviewCardDelete)
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(Self.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Self.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Self.red.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)

            Spacer(minLength: 0)
        }
        .padding(.top, 11)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MyCoursesPalette.stroke)
                .frame(height: 1)
        }
    }

    private func actionLabel(icon: String, text: String, tint: Color,
                             bg: Color, border: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(tint)
            Text(text)
                .font(.system(size: 11, weight: .light))
                .foregroundColor(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(border, lineWidth: 1))
    }
}

// MARK: - Instructor review avatar (figma)
//
// 34px gradient disc with white initials, colour keyed off the author name
// so each reviewer keeps a stable hue. Distinct from the gold-ring
// `ReviewAvatar` used on the course-detail surface.

struct InstructorReviewAvatar: View {
    let name: String

    var body: some View {
        Circle()
            .fill(InstructorFigma.tileGradient(for: name))
            .frame(width: 34, height: 34)
            .overlay(Circle().stroke(MyCoursesPalette.stroke, lineWidth: 1))
            .overlay(
                Text(InstructorFigma.initials(from: name))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white))
    }
}

// MARK: - Enrolled empty state (figma)
//
// Shown under the "Enrolled" tab before the student has any courses with
// this instructor. A glowing "add course" illustration (a back document
// card peeking behind a dashed tile with a plus), a gold headline that
// folds in the instructor's name, and a muted explainer.

struct InstructorEnrolledEmptyView: View {
    let instructorName: String

    var body: some View {
        VStack(spacing: 7.3) {
            illustration
            Text(String(format: L10n.instructorProfileStartLearningFmt, shortName))
                .font(.system(size: 21, weight: .regular))
                .foregroundColor(InstructorFigma.gold)
                .multilineTextAlignment(.center)
                .padding(.top, 7.7)
            Text(L10n.instructorProfileEnrolledEmptySub)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(InstructorFigma.emptySub)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    private var illustration: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [InstructorFigma.gold.opacity(0.15), .clear],
                    center: .center, startRadius: 0, endRadius: 64))
                .frame(width: 150, height: 150)

            // Back document card, tucked behind and to the left.
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(InstructorFigma.emptyBackCard)
                .frame(width: 52, height: 62)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(InstructorFigma.gold.opacity(0.35))
                            .frame(width: 30, height: 4)
                        Capsule().fill(MyCoursesPalette.textTertiary.opacity(0.3))
                            .frame(width: 24, height: 3)
                        Capsule().fill(MyCoursesPalette.textTertiary.opacity(0.3))
                            .frame(width: 18, height: 3)
                    }
                    .padding(10)
                }
                .rotationEffect(.degrees(-8))
                .offset(x: -34, y: 0)

            // Dashed "add course" tile with a plus.
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    InstructorFigma.gold.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 60, height: 66)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(InstructorFigma.gold))
                .offset(x: 8, y: 0)

            // Motion dashes trailing to the right.
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(InstructorFigma.gold.opacity(0.5)).frame(width: 14, height: 2)
                Capsule().fill(InstructorFigma.gold.opacity(0.3)).frame(width: 9, height: 2)
            }
            .offset(x: 58, y: 6)
        }
        .frame(width: 160, height: 90)
    }

    /// "Dr. Layla Hassan" → "Dr. Layla". Keeps an honorific token attached
    /// to the given name; otherwise just the first name.
    private var shortName: String {
        let parts = instructorName.split(separator: " ")
        guard let first = parts.first else { return instructorName }
        if first.hasSuffix("."), parts.count >= 2 {
            return "\(first) \(parts[1])"
        }
        return String(first)
    }
}

// MARK: - Instructor enrolled card (figma 1926:6811 / 1926:6850)
//
// One enrolled course in the instructor-profile "Enrolled" tab. Two shapes:
//   • In progress — gradient initials tile, title, "X of Y lessons", a
//     PROGRESS row + gold fill bar, a "NEXT LESSON" sub-card (play icon +
//     lesson title + chevron), and a gold "Continue" pill.
//   • Completed — gradient tile, title, green "✓ All N lessons completed",
//     a full green bar, and a neutral "Review" pill.

struct InstructorEnrolledCard: View {
    let course: EnrolledCourse
    let locale: String

    private var isArabic: Bool { locale == "ar" }
    private var pct: Int { max(0, min(100, Int(course.progressPct.rounded()))) }

    // #605234 (gold ramp tail) and #1A8A3B (spring green) — used only here.
    private static let goldTail = Color(red: 0.376, green: 0.322, blue: 0.204)
    private static let springGreen = Color(red: 0.102, green: 0.541, blue: 0.231)

    var body: some View {
        VStack(alignment: .leading, spacing: course.isCompleted ? 11 : 10) {
            headerRow
            if course.isCompleted {
                completedBar
                divider
                reviewPill
            } else {
                progressSection
                if let next = course.localizedNextLessonTitle(locale: locale) {
                    nextLessonCard(title: next)
                }
                divider
                continuePill
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstructorFigma.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(InstructorFigma.gold.opacity(0.3), lineWidth: 1))
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(course.localizedTitle(locale: locale))
                    .font(BrandFont.sansBold(size: 15.5, isArabic: isArabic))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if course.isCompleted {
                    completedLine
                } else {
                    lessonsLine
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var avatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(InstructorFigma.tileGradient(for: course.id))
                .overlay(
                    Text(InstructorFigma.initials(
                        from: course.localizedTitle(locale: locale)))
                        .font(BrandFont.sansBold(size: 17, isArabic: isArabic))
                        .foregroundColor(.white))
            if let url = course.coverUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.clear
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var lessonsLine: some View {
        (Text("\(course.completedLessonCount)")
            .font(BrandFont.sansBold(size: 11, isArabic: isArabic))
            .foregroundColor(InstructorFigma.gold)
         + Text(String(format: L10n.instructorProfileEnrolledOfLessonsFmt,
                       course.lessonCount))
            .font(BrandFont.sans(size: 11, isArabic: isArabic))
            .foregroundColor(InstructorFigma.neutral.opacity(0.55)))
            .lineLimit(1)
    }

    private var completedLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(InstructorFigma.newGreen)
            Text(String(format: L10n.instructorProfileAllLessonsCompletedFmt,
                        course.lessonCount))
                .font(BrandFont.sansBold(size: 11, isArabic: isArabic))
                .foregroundColor(InstructorFigma.newGreen)
                .lineLimit(1)
        }
    }

    // MARK: In-progress sections

    private var progressSection: some View {
        VStack(spacing: 5) {
            HStack {
                Text(L10n.instructorProfileProgress.uppercased())
                    .font(BrandFont.sansBold(size: 9.5, isArabic: isArabic))
                    .tracking(0.76)
                    .foregroundColor(InstructorFigma.neutral.opacity(0.5))
                Spacer()
                Text("\(pct)%")
                    .font(BrandFont.sansBold(size: 11, isArabic: isArabic))
                    .foregroundColor(InstructorFigma.gold)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(MyCoursesPalette.stroke)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [InstructorFigma.gold, Self.goldTail],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * CGFloat(pct) / 100))
                }
            }
            .frame(height: 5)
        }
    }

    private func nextLessonCard(title: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(InstructorFigma.gold.opacity(0.18))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundColor(InstructorFigma.gold))
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.instructorProfileNextLesson.uppercased())
                    .font(BrandFont.sansBold(size: 9.5, isArabic: isArabic))
                    .tracking(0.95)
                    .foregroundColor(InstructorFigma.gold)
                Text(title)
                    .font(BrandFont.sansBold(size: 12.5, isArabic: isArabic))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(InstructorFigma.gold)
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(InstructorFigma.gold.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(InstructorFigma.gold.opacity(0.2), lineWidth: 1))
    }

    private var continuePill: some View {
        HStack(spacing: 5) {
            Image(systemName: "play.fill")
                .font(.system(size: 10))
                .foregroundColor(InstructorFigma.badgeDark)
            Text(L10n.continueButton)
                .font(BrandFont.sansBold(size: 11.5, isArabic: isArabic))
                .foregroundColor(InstructorFigma.badgeDark)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(
                    colors: [InstructorFigma.gold, Self.goldTail],
                    startPoint: .leading, endPoint: .trailing)))
    }

    // MARK: Completed sections

    private var completedBar: some View {
        Capsule()
            .fill(LinearGradient(
                colors: [Self.springGreen, InstructorFigma.newGreen],
                startPoint: .leading, endPoint: .trailing))
            .frame(height: 5)
    }

    private var reviewPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(InstructorFigma.noteText)
            Text(L10n.instructorProfileReviewAction)
                .font(BrandFont.sansBold(size: 11.5, isArabic: isArabic))
                .foregroundColor(InstructorFigma.neutral.opacity(0.85))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(MyCoursesPalette.surfaceRaised))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle()
            .fill(MyCoursesPalette.stroke)
            .frame(height: 1)
    }
}

// MARK: - Instructor course card (figma)
//
// One course in the instructor's "Courses" tab. A gradient icon tile with
// the course initials, the localized title + subtitle, an optional NEW
// badge, then a 3-column stat row (Lessons / Rating / Enrolled) framed by
// hairlines, and a gold "View course" affordance. The gradient is derived
// deterministically from the course id so each card keeps a stable colour.

struct InstructorCourseCard: View {
    let course: CourseSummary
    let locale: String

    // Hidden for now (2026-07): reviews/ratings paused platform-wide.
    private var hideReviews: Bool { true }

    private var isArabic: Bool { locale == "ar" }
    private var isNew: Bool { course.ratingCount == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            statsRow
            viewCourseLink
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstructorFigma.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(InstructorFigma.cardBorder, lineWidth: 1))
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            iconTile
            VStack(alignment: .leading, spacing: 3) {
                Text(course.localizedTitle(locale: locale))
                    .font(BrandFont.displaySemiBold(size: 16, isArabic: isArabic))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle = course.localizedSubtitle(locale: locale), !subtitle.isEmpty {
                    Text(subtitle)
                        .font(BrandFont.display(size: 12, isArabic: isArabic))
                        .foregroundColor(InstructorFigma.gold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            if isNew { newBadge }
        }
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(InstructorFigma.tileGradient(for: course.id))
                .overlay(
                    Text(InstructorFigma.initials(from: course.localizedTitle(locale: locale)))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white))
            if let url = course.coverUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.clear
                    }
                }
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(width: 62, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var newBadge: some View {
        Text(L10n.exploreNewBadge.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundColor(InstructorFigma.badgeDark)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(InstructorFigma.newGreen))
    }

    // MARK: Stat row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statColumn(value: "\(course.lessonCount)",
                       label: L10n.statTileLessons)
            // The Enrolled column was removed platform-wide (2026-08).
            // Reviews/ratings are separately hidden (2026-07) — with both gone
            // this is a single-column row, so the divider hangs off the rating
            // rather than standing alone.
            if !hideReviews {
                divider
                ratingColumn
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) {
            Rectangle().fill(InstructorFigma.statRowBorder).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(InstructorFigma.statRowBorder).frame(height: 1)
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.54)
                .foregroundColor(InstructorFigma.gold)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var ratingColumn: some View {
        VStack(spacing: 3) {
            HStack(spacing: 2) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundColor(InstructorFigma.gold)
                Text(course.ratingAvg.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
            }
            Text(String(format: L10n.instructorProfileReviewsCountFmt, course.ratingCount))
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.3)
                .foregroundColor(InstructorFigma.gold)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(InstructorFigma.divider)
            .frame(width: 0.5, height: 24)
    }

    private var viewCourseLink: some View {
        HStack(spacing: 4) {
            Text(L10n.instructorProfileViewCourse)
                .font(BrandFont.displaySemiBold(size: 12, isArabic: isArabic))
            Image(systemName: isArabic ? "chevron.left" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(InstructorFigma.gold)
    }
}

// MARK: - Instructor profile figma palette
//
// Figma tokens for the instructor surface. The brand accents (gold, green,
// orange, red, the initials gradients) are hardcoded — they read on both
// themes. Every neutral (surface / border / text) now defers to
// `MyCoursesPalette`, which resolves light-vs-dark off the trait collection.

enum InstructorFigma {
    // Stat grid tiles
    static let statCardBg = MyCoursesPalette.surfaceRaised                    // was #1C180F
    static let statCardBorder = Color(red: 0.376, green: 0.322, blue: 0.204)  // #605234
    static let statLabel = MyCoursesPalette.muted

    // Course cards
    static let cardBg = MyCoursesPalette.surface                              // was #1C1C1E
    static let cardBorder = MyCoursesPalette.stroke
    static let statRowBorder = MyCoursesPalette.stroke
    /// Vertical hairline between stat columns — heavier than `stroke` by
    /// design, so it rides the tertiary text tint instead.
    static let divider = MyCoursesPalette.textTertiary.opacity(0.37)

    // Accents
    static let gold = Color(red: 0.776, green: 0.663, blue: 0.420)            // #C6A96B
    static let badgeDark = Color(red: 0.102, green: 0.075, blue: 0.020)       // #1A1305
    static let newGreen = Color(red: 0.188, green: 0.820, blue: 0.345)        // #30D158

    // Neutral text base + opacity ramps. `neutral` is the adaptive primary
    // (white in dark, near-black in light) so every ramp below flips with
    // the theme instead of staying at the old #EBEBF5.
    static let neutral = MyCoursesPalette.textPrimary
    static let waitingText = neutral.opacity(0.55)
    static let noteText = neutral.opacity(0.75)
    static let editBtnText = neutral.opacity(0.8)
    static let dotMuted = neutral.opacity(0.25)
    static let ageMuted = neutral.opacity(0.5)
    static let reviewBody = neutral.opacity(0.8)
    static let emptySub = neutral.opacity(0.6)

    // Pending (orange) + cancel (red)
    static let orange = Color(red: 1.0, green: 0.624, blue: 0.039)            // #FF9F0A
    static let orangeTileGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.624, blue: 0.039),
                 Color(red: 0.780, green: 0.420, blue: 0.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let red = Color(red: 1.0, green: 0.271, blue: 0.227)              // #FF453A

    // Gated review CTA
    static let disabledCtaBg = MyCoursesPalette.surfaceRaised                 // was #3A3A3C
    static let disabledCtaText = MyCoursesPalette.textTertiary                // was #6F6F74

    // Empty-state illustration card
    static let emptyBackCard = MyCoursesPalette.surfaceRaised                 // was ~#2A2A2D

    /// Stable 135° gradient keyed off the course id (djb2 hash → 1 of 5
    /// brand-adjacent palettes). Mirrors EnrolledAvatar / InstructorBrowseRow.
    static func tileGradient(for seed: String) -> LinearGradient {
        let palettes: [[Color]] = [
            [Color(red: 0.45, green: 0.32, blue: 0.78), Color(red: 0.62, green: 0.40, blue: 0.90)], // violet
            [Color(red: 0.86, green: 0.31, blue: 0.47), Color(red: 0.96, green: 0.45, blue: 0.58)], // rose
            [Color(red: 0.90, green: 0.49, blue: 0.20), Color(red: 0.98, green: 0.66, blue: 0.28)], // orange
            [Color(red: 0.18, green: 0.49, blue: 0.83), Color(red: 0.30, green: 0.66, blue: 0.92)], // azure
            [Color(red: 0.16, green: 0.62, blue: 0.45), Color(red: 0.26, green: 0.78, blue: 0.55)], // green
        ]
        var hash: UInt64 = 5381
        for byte in seed.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        let pair = palettes[Int(hash % UInt64(palettes.count))]
        return LinearGradient(colors: pair,
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing)
    }

    /// First letter of the first two words, else the first two characters.
    static func initials(from name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        if words.count >= 2 {
            return words.map { String($0.prefix(1)) }.joined().uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
