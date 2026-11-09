import SwiftUI

// MARK: - HomeView (Figma redesign — node 2937:18940, Inter throughout)
//
// Tab #1 of the authenticated app. One aggregate call (GET /v1/student/home)
// powers five sections, top → bottom:
//
//   1. Header        — "Good morning, {first name}" + bell + avatar.
//   2. Continue      — horizontal carousel of in-progress courses with a
//                      gold progress bar, "{watched} / {total}" + percent,
//                      and a page-dots indicator.
//   3. Recommended   — gradient-banner cards with a "Because you …" pill.
//   4. Instructors   — cards with a 2×2 stats grid + "View all courses".
//   5. Next Session  — date chip + title/time + gold "Join" pill.
//
// Pixel values come straight from the Figma frame (390-wide artboard → pt).
// Content type is Inter; the tiny recommendation pill uses DM Sans to match
// the design. Arabic falls back to the system sans at the matching weight.

struct HomeView: View {
    @StateObject private var viewModel = HomeDashboardViewModel()
    @EnvironmentObject private var authSession: AuthSession
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    @Binding private var pendingCourseId: String?
    let onBrowseCourses: () -> Void
    /// Tapping an enrolled course switches the bottom tab to Courses and pushes
    /// the detail there so the nav selection matches the screen.
    let onOpenMyCourse: (String) -> Void

    /// Non-enrolled recommended rows still present the purchase sheet.
    @State private var presentedCourseId: String? = nil
    @State private var continuePage: Int = 0

    init(
        pendingCourseId: Binding<String?> = .constant(nil),
        onBrowseCourses: @escaping () -> Void = {},
        onOpenMyCourse: @escaping (String) -> Void = { _ in }
    ) {
        self._pendingCourseId = pendingCourseId
        self.onBrowseCourses = onBrowseCourses
        self.onOpenMyCourse = onOpenMyCourse
    }

    private var ar: Bool { appLocale == "ar" }
    private var courses: [EnrolledCourse] { viewModel.continueCourses }

    // Hidden for now (2026-07): course recommendations paused platform-wide.
    private var hideRecommended: Bool { true }

    var body: some View {
        ZStack(alignment: .top) {
            HomeColors.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // Ask Droob AI hero. Sits ABOVE the `isLoading` branch on
                    // purpose: it advertises a capability, depends on nothing
                    // the home aggregate returns, and so renders identically
                    // during the first load.
                    AiHeroCard(isArabic: ar)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    if viewModel.isLoading {
                        loadingSkeleton
                            .padding(.top, 18)
                    } else {
                        // Continue Learning — title always shows; the carousel is
                        // swapped for a "Nothing in progress yet" card when there
                        // are no in-progress courses.
                        if !courses.isEmpty {
                            continueSection.padding(.top, 16)
                        } else {
                            continueEmptySection.padding(.top, 16)
                        }
                        // Hidden for now (2026-07): course recommendations paused
                        // platform-wide — the whole section (title, cards, AND the
                        // "Enroll to unlock recommendations" empty card) is hidden;
                        // nothing renders in its place.
                        if !hideRecommended {
                            // Recommended — title always shows; an "Enroll to unlock
                            // recommendations" card (carrying the Browse CTA) stands in
                            // until the recommendation engine has picks.
                            if !viewModel.recommended.isEmpty {
                                recommendedSection.padding(.top, 24)
                            } else {
                                recommendedEmptySection.padding(.top, 24)
                            }
                        }
                        if !viewModel.instructors.isEmpty {
                            instructorsSection.padding(.top, 22)
                        }
                        // Next Session — title always shows; a "No live sessions
                        // scheduled" card stands in when nothing is upcoming.
                        if let session = viewModel.homeNextSession {
                            nextSessionSection(session).padding(.top, 24)
                        } else {
                            nextSessionEmptySection.padding(.top, 24)
                        }
                    }

                    Color.clear.frame(height: 28)
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.load() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .onAppear { handlePendingDeepLink() }
        .onChange(of: pendingCourseId) { _ in handlePendingDeepLink() }
        .coursePresentation(item: courseSheetBinding) { idBox in sheetContent(idBox) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greetingPrefix)
                    .font(BrandFont.inter(size: 13, weight: .regular, isArabic: ar))
                    .foregroundColor(HomeColors.muted60)
                Text(displayFirstName)
                    .font(BrandFont.inter(size: 30, weight: .bold, isArabic: ar))
                    .tracking(ar ? 0 : -1.2)
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                notificationBell
                avatarBlock
            }
        }
    }

    private var notificationBell: some View {
        NavigationLink { NotificationsInboxView() } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(HomeColors.goldButton)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(HomeColors.hex(0x1C1C1C, 0.4), lineWidth: 1))
                    Image(systemName: "bell.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(HomeColors.nearBlack)
                }
                .frame(width: 24, height: 24)

                if unreadCount > 0 {
                    Circle().fill(Color.red)
                        .frame(width: 4, height: 4)
                        .offset(x: 1, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.inboxTitle)
    }

    private var avatarBlock: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(HomeColors.surface)
                if let s = viewModel.greeting?.avatarUrl, let url = URL(string: s) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else { initialsText }
                    }
                    .clipShape(Circle())
                } else {
                    initialsText
                }
            }
            .frame(width: 44, height: 44)

            Circle().fill(HomeColors.green)
                // Ring punches the presence dot out of the page canvas.
                .overlay(Circle().stroke(MyCoursesPalette.background, lineWidth: 2))
                .frame(width: 12, height: 12)
                .offset(x: -1, y: -1)
        }
    }

    private var initialsText: some View {
        Text(displayInitials)
            .font(BrandFont.inter(size: 17, weight: .semibold, isArabic: ar))
            .foregroundColor(HomeColors.gold)
    }

    private var unreadCount: Int {
        viewModel.greeting?.unreadNotificationsCount ?? viewModel.unreadNotifications
    }

    private var greetingPrefix: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return L10n.greetingMorning + ","
        case 12..<17: return L10n.greetingAfternoon + ","
        default:      return L10n.greetingEvening + ","
        }
    }

    private var displayFirstName: String {
        if let f = viewModel.greeting?.firstName, !f.isEmpty { return f }
        let name = authSession.currentUser?.displayName ?? ""
        return name.split(separator: " ").first.map(String.init) ?? (name.isEmpty ? "—" : name)
    }

    private var displayInitials: String {
        if let i = viewModel.greeting?.initials, !i.isEmpty { return i }
        let words = (authSession.currentUser?.displayName ?? "—").split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "—" : letters.joined()
    }

    // MARK: - Continue Learning

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(t("Continue Learning", "متابعة التعلم"))
                    .font(BrandFont.inter(size: 21, weight: .semibold, isArabic: ar))
                    .foregroundColor(HomeColors.gold)
                Spacer(minLength: 8)
                continueCounter
            }
            .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(courses) { course in
                        Button { onOpenMyCourse(course.id) } label: { continueCard(course) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
            .onScrollGeometryChange(for: Int.self) { geo in
                let stride = 296.0 + 14.0
                return max(0, min(courses.count - 1, Int((geo.contentOffset.x + stride / 2) / stride)))
            } action: { _, page in
                continuePage = page
            }

            if courses.count > 1 {
                continueDots.padding(.horizontal, 18).padding(.top, 4)
            }
        }
    }

    private var continueCounter: some View {
        (
            Text("\(continuePage + 1)")
                .font(BrandFont.inter(size: 11.9, weight: .bold, isArabic: ar))
                .foregroundColor(HomeColors.gold)
            + Text(" " + t("of \(courses.count) courses", "من \(courses.count) دورات"))
                .font(BrandFont.inter(size: 11.9, weight: .regular, isArabic: ar))
                .foregroundColor(HomeColors.grey55)
        )
        .lineLimit(1)
    }

    private var continueDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<courses.count, id: \.self) { i in
                let active = i == continuePage
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(active ? HomeColors.gold : HomeColors.dotInactive)
                    .frame(width: active ? 18 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func continueCard(_ e: EnrolledCourse) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 13) {
                courseCoverTile(e)

                VStack(alignment: .leading, spacing: 3) {
                    // The card is a fixed 296 pt and both lines are capped at
                    // one line, which was tuned against English. Arabic titles
                    // run ~30% longer, so without a scale floor they simply
                    // tail-truncate on the first screen of the app. The floor
                    // only engages when the string would not otherwise fit.
                    Text(e.localizedTitle(locale: appLocale))
                        .font(BrandFont.inter(size: 18, weight: .semibold, isArabic: ar))
                        .foregroundColor(HomeColors.titleText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let next = e.localizedNextLessonTitle(locale: appLocale) {
                        Text(bidiJoin(t("Lesson", "الدرس"), next, separator: " — "))
                            .font(BrandFont.inter(size: 12.5, weight: .regular, isArabic: ar))
                            .foregroundColor(HomeColors.grey61)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }

            progressTrack(e.progressPct / 100)

            HStack(spacing: 8) {
                if e.totalDurationSeconds > 0 {
                    Text(watchedLabel(e))
                        .font(BrandFont.inter(size: 11.6, weight: .regular, isArabic: ar))
                        .foregroundColor(HomeColors.grey57)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("\(Int(e.progressPct.rounded()))%")
                    .font(BrandFont.inter(size: 14, weight: .bold, isArabic: ar))
                    .foregroundColor(HomeColors.goldText)
            }
        }
        .padding(18)
        .frame(width: 296, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(HomeColors.cardGradient))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(HomeColors.cardBorderGold, lineWidth: 1))
    }

    /// Leading tile on a Continue Learning card: the course's own cover art.
    /// Falls back to a deterministic gradient carrying the course initials when
    /// the course has no cover (or it fails to load) — the tile used to be a
    /// keyword-guessed emoji, which said nothing about the actual course.
    private func courseCoverTile(_ e: EnrolledCourse) -> some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        let tint = HomeColors.coverTint(for: e.id)
        return shape
            .fill(LinearGradient(colors: [tint, tint.opacity(0.72)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Text(Self.courseInitials(e.localizedTitle(locale: appLocale)))
                    .font(BrandFont.inter(size: 17, weight: .semibold, isArabic: ar))
                    .foregroundColor(.white))
            .overlay {
                if let url = e.coverUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color.clear
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(shape)
                }
            }
            .frame(width: 50, height: 50)
            .overlay(shape.stroke(HomeColors.iconBoxBorder, lineWidth: 1))
    }

    /// Up to two letters from the course title. Arabic titles have no case, so
    /// `uppercased()` is a no-op there rather than a mangling.
    private static func courseInitials(_ title: String) -> String {
        let letters = title.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private func progressTrack(_ pct: Double) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(MyCoursesPalette.stroke)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(HomeColors.progressFill)
                    .frame(width: max(0, g.size.width * min(1, max(0, pct))))
            }
        }
        .frame(height: 9)
    }

    // MARK: - Empty states (new-student home — Figma node 3066:12156)

    /// Continue Learning empty state: the gold section title (no counter) above a
    /// dashed "Nothing in progress yet" card with a gold monitor glyph.
    private var continueEmptySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(t("Continue Learning", "متابعة التعلم"))
                .font(BrandFont.inter(size: 21, weight: .semibold, isArabic: ar))
                .foregroundColor(HomeColors.gold)
                .padding(.horizontal, 18)
            emptyInfoCard(
                icon: "display", iconTint: HomeColors.gold, iconPt: 17,
                tile: 42, tileRadius: 13, tileGap: 14, cardRadius: 16, padH: 19, padV: 17,
                title: t("Nothing in progress yet", "لا شيء قيد التقدّم بعد"), titleSize: 13.9,
                subtitle: t("Your active courses will appear here.", "ستظهر دوراتك النشطة هنا."),
                subtitleSize: 11.3, textGap: 3
            )
            .padding(.horizontal, 18)
        }
    }

    /// Next Session empty state: a dashed "No live sessions scheduled" card with a
    /// grey calendar glyph, under the standard gold section title.
    private var nextSessionEmptySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Next Session", "الجلسة القادمة"))
                .font(BrandFont.inter(size: 20, weight: .semibold, isArabic: ar))
                .tracking(ar ? 0 : -0.6)
                .foregroundColor(HomeColors.gold)
                .padding(.horizontal, 16)
            emptyInfoCard(
                icon: "calendar", iconTint: HomeColors.grey55, iconPt: 18,
                tile: 48, tileRadius: 14, tileGap: 15, cardRadius: 18, padH: 19, padV: 19,
                title: t("No live sessions scheduled", "لا توجد جلسات مباشرة مجدولة"), titleSize: 14.4,
                subtitle: t("Upcoming sessions from your instructors will appear here.",
                            "ستظهر الجلسات القادمة من مدرّبيك هنا."),
                subtitleSize: 11.7, textGap: 3.25, subtitleLineSpacing: 4
            )
            .padding(.horizontal, 16)
        }
    }

    /// Shared dashed icon+text empty card (Continue Learning + Next Session):
    /// an #0C0C0E fill with a dashed #26262A rounded border, a dark icon tile on
    /// the leading edge, then a bold title over a muted subtitle.
    private func emptyInfoCard(
        icon: String, iconTint: Color, iconPt: CGFloat,
        tile: CGFloat, tileRadius: CGFloat, tileGap: CGFloat,
        cardRadius: CGFloat, padH: CGFloat, padV: CGFloat,
        title: String, titleSize: CGFloat,
        subtitle: String, subtitleSize: CGFloat, textGap: CGFloat,
        subtitleLineSpacing: CGFloat = 0
    ) -> some View {
        HStack(spacing: tileGap) {
            ZStack {
                RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
                    .fill(HomeColors.iconTileBg)
                    .overlay(RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
                        .stroke(HomeColors.iconTileBorder, lineWidth: 1))
                Image(systemName: icon)
                    .font(.system(size: iconPt, weight: .regular))
                    .foregroundColor(iconTint)
            }
            .frame(width: tile, height: tile)

            VStack(alignment: .leading, spacing: textGap) {
                Text(title)
                    .font(BrandFont.inter(size: titleSize, weight: .bold, isArabic: ar))
                    .foregroundColor(HomeColors.emptyTitle)
                Text(subtitle)
                    .font(BrandFont.inter(size: subtitleSize, weight: .regular, isArabic: ar))
                    .foregroundColor(HomeColors.emptySubtitle)
                    .lineSpacing(subtitleLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, padH)
        .padding(.vertical, padV)
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(HomeColors.emptyCardBg))
        .overlay(RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
            .strokeBorder(HomeColors.emptyCardBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    /// Recommended empty state ("Enroll to unlock recommendations"): a Fraunces
    /// italic headline + muted body + solid-gold Browse-courses button, over an
    /// #0E0E12 base lit by a soft gold glow at the top edge.
    private var recommendedEmptySection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(t("Recommended for you", "موصى به لك"))
                .font(BrandFont.inter(size: 19, weight: .semibold, isArabic: ar))
                .foregroundColor(HomeColors.gold)
                .padding(.horizontal, 18)
            recommendedEmptyCard.padding(.horizontal, 18)
        }
    }

    private var recommendedEmptyCard: some View {
        VStack(spacing: 9.1) {
            Text(t("Enroll to unlock\nrecommendations", "سجّل لفتح التوصيات"))
                .font(BrandFont.displaySemiBold(size: 19, isArabic: ar))
                .foregroundColor(HomeColors.titleText)
                .multilineTextAlignment(.center)
            Text(t("Your picks are based on the courses you enroll in. Start your first course and we’ll suggest what to learn next.",
                    "تعتمد اقتراحاتنا على الدورات التي تسجّل بها. ابدأ دورتك الأولى وسنقترح ما تتعلّمه تالياً."))
                .font(BrandFont.inter(size: 12.3, weight: .regular, isArabic: ar))
                .foregroundColor(HomeColors.grey61)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onBrowseCourses) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(HomeColors.nearBlack)
                    Text(t("Browse courses", "تصفّح الدورات"))
                        .font(BrandFont.inter(size: 14.5, weight: .bold, isArabic: ar))
                        .foregroundColor(HomeColors.nearBlack)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(HomeColors.goldFill))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 23)
        .padding(.vertical, 27)
        .background(
            ZStack {
                HomeColors.recEmptyBg
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: HomeColors.recGlow.opacity(0.14), location: 0),
                        .init(color: HomeColors.recGlow.opacity(0), location: 0.7),
                    ]),
                    center: .top, startRadius: 0, endRadius: 225
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(HomeColors.recEmptyBorder, lineWidth: 1))
    }

    // MARK: - Recommended

    private var recommendedSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(t("Recommended for you", "موصى به لك"))
                .font(BrandFont.inter(size: 19, weight: .semibold, isArabic: ar))
                .foregroundColor(HomeColors.gold)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(viewModel.recommended.enumerated()), id: \.element.id) { idx, rec in
                        Button { presentedCourseId = rec.course.id } label: {
                            recommendedCard(rec, index: idx)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func recommendedCard(_ rec: RecommendedCourse, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let url = rec.course.coverUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: recBannerPlaceholder(rec, index)
                        }
                    }
                } else {
                    recBannerPlaceholder(rec, index)
                }
            }
            .frame(height: 72)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                if let reason = rec.localizedReasonTitle(locale: appLocale), !reason.isEmpty {
                    reasonBadge(reason)
                }
                Text(localizedCourseTitle(rec.course))
                    .font(BrandFont.inter(size: 11.84, weight: .medium, isArabic: ar))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(bidiJoin(rec.course.instructorName,
                              "\(rec.course.lessonCount) \(t("lessons", "درسًا"))",
                              separator: " · "))
                    .font(BrandFont.inter(size: 7.36, weight: .regular, isArabic: ar))
                    .foregroundColor(HomeColors.muted60)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 192, alignment: .leading)
        .background(HomeColors.surface)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(HomeColors.recBorder, lineWidth: 0.86))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Banner shown when a recommended course has no cover image (or it
    /// fails to load): the original gradient + thematic emoji treatment.
    private func recBannerPlaceholder(_ rec: RecommendedCourse, _ index: Int) -> some View {
        ZStack {
            bannerGradient(index)
            Text(recEmoji(rec, index)).font(.system(size: 28))
        }
    }

    private func reasonBadge(_ reason: String) -> some View {
        HStack(spacing: 3.7) {
            Image(systemName: "sparkles")
                .font(.system(size: 7, weight: .semibold))
                .foregroundColor(HomeColors.cyan)
            Text("\(t("Because you watched", "لأنك شاهدت")) \(reason.bidiIsolated)")
                .font(.custom(BrandFont.dmSansBold, size: 7.4))
                .foregroundColor(HomeColors.cyan)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6.6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(HomeColors.cyan13))
    }

    // MARK: - Explore Instructors

    private var instructorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Explore Instructors", "استكشف المدرّسين"))
                .font(BrandFont.inter(size: 18, weight: .semibold, isArabic: ar))
                .foregroundColor(HomeColors.gold)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.instructors) { inst in
                        NavigationLink { InstructorProfileView(instructorId: inst.id) } label: {
                            instructorCard(inst)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func instructorCard(_ inst: StudentInstructorSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle().fill(instructorColor(inst))
                    Text(nameInitials(inst.displayName))
                        .font(BrandFont.inter(size: 9.3, weight: .bold, isArabic: ar))
                        // Fixed white — always sits on a saturated avatar disc.
                        .foregroundColor(.white)
                    // Presigned avatar loads over the initials disc and
                    // replaces it on success; any other phase leaves the
                    // colored-initials fallback showing.
                    if let url = inst.avatarUrl.flatMap(URL.init(string:)) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Color.clear
                            }
                        }
                        .frame(width: 31, height: 31)
                        .clipShape(Circle())
                    }
                }
                .frame(width: 31, height: 31)

                VStack(alignment: .leading, spacing: 2) {
                    Text(inst.displayName)
                        .font(BrandFont.inter(size: 9.86, weight: .bold, isArabic: ar))
                        .foregroundColor(HomeColors.titleText)
                        .lineLimit(1)
                    if let title = inst.localizedTitle(locale: appLocale) {
                        Text(title)
                            .font(BrandFont.inter(size: 7.07, weight: .regular, isArabic: ar))
                            .foregroundColor(HomeColors.grey55)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
            }

            // Stats hidden for now (2026-07): show the instructor's bio in
            // place of the 2×2 stat box. statsBox is kept below for restore.
            // statsBox(inst)
            bioBox(inst)
            viewAllRow
        }
        .padding(10.5)
        .frame(width: 196, alignment: .leading)
        .background(HomeColors.surface)
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(HomeColors.instrBorder, lineWidth: 0.62))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    /// Instructor bio on the same sheen surface the stat box used, truncated
    /// to fit the fixed-width card. Renders an empty spacer when the
    /// instructor set no bio, so the card keeps its shape without a panel.
    @ViewBuilder
    private func bioBox(_ inst: StudentInstructorSummary) -> some View {
        if let bio = inst.localizedBio(locale: appLocale) {
            Text(bio)
                .font(BrandFont.inter(size: 8.4, weight: .regular, isArabic: ar))
                .foregroundColor(MyCoursesPalette.textPrimary)
                .lineSpacing(2)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(HomeColors.sheen))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(HomeColors.statsBorder, lineWidth: 0.62))
        } else {
            // No bio → reserve a little height so the "View profile" row and
            // card outline stay aligned with cards that do have one.
            Color.clear.frame(height: 4)
        }
    }

    private func statsBox(_ inst: StudentInstructorSummary) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Students cell removed platform-wide (2026-08). This box is
                // currently unrendered (see `bioBox`) — dropping the cell here
                // too so a restore doesn't bring the count back.
                statCell(icon: "star.fill", value: ratingText(inst.ratingAvg), label: t("Rating", "التقييم"))
            }
            HStack(spacing: 0) {
                statCell(icon: "book.fill", value: "\(inst.coursesCount)", label: t("Courses", "الدورات"))
                statCell(icon: "clock.fill", value: inst.formattedYears, label: t("Years", "سنوات"))
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(HomeColors.sheen))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(HomeColors.statsBorder, lineWidth: 0.62))
    }

    private func statCell(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(MyCoursesPalette.muted)
                .frame(width: 11, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(BrandFont.inter(size: 8.9, weight: .bold, isArabic: ar))
                    .foregroundColor(HomeColors.titleText)
                Text(label.uppercased())
                    .font(BrandFont.inter(size: 5.6, weight: .bold, isArabic: ar))
                    .tracking(ar ? 0 : 0.5)
                    .foregroundColor(HomeColors.statLabel)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var viewAllRow: some View {
        HStack(spacing: 0) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 9))
                .foregroundColor(MyCoursesPalette.textPrimary)
            Text(t("View all courses", "عرض كل الدورات"))
                .font(BrandFont.inter(size: 8, weight: .regular, isArabic: ar))
                .foregroundColor(HomeColors.viewAllText)
                .padding(.leading, 7)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 9))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .padding(.horizontal, 9.3)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 7.4, style: .continuous)
            .stroke(HomeColors.viewAllBorder, lineWidth: 0.62))
    }

    // MARK: - Next Session

    private func nextSessionSection(_ s: HomeNextSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Next Session", "الجلسة القادمة"))
                .font(BrandFont.inter(size: 20, weight: .semibold, isArabic: ar))
                .tracking(ar ? 0 : -0.6)
                .foregroundColor(HomeColors.gold)
                .padding(.horizontal, 16)
            nextSessionCard(s).padding(.horizontal, 16)
        }
    }

    private func nextSessionCard(_ s: HomeNextSession) -> some View {
        HStack(spacing: 13) {
            VStack(spacing: 0) {
                Text(monthAbbrev(s.startsAt))
                    .font(BrandFont.inter(size: 9, weight: .semibold, isArabic: ar))
                    .tracking(0.54)
                    .foregroundColor(HomeColors.muted60)
                Text(dayNumber(s.startsAt))
                    .font(BrandFont.inter(size: 22, weight: .semibold, isArabic: ar))
                    .tracking(ar ? 0 : -0.66)
                    .foregroundColor(MyCoursesPalette.textPrimary)
            }
            .frame(width: 48, height: 52)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HomeColors.chipBg))

            VStack(alignment: .leading, spacing: 2) {
                Text(s.localizedTitle(locale: appLocale))
                    .font(BrandFont.inter(size: 15, weight: .medium, isArabic: ar))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(1)
                Text(bidiJoin(timeText(s.startsAt),
                              "\(s.durationMinutes) \(t("min", "د"))",
                              separator: " · "))
                    .font(BrandFont.inter(size: 13, weight: .medium, isArabic: ar))
                    .foregroundColor(HomeColors.muted60)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            joinButton(s)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(height: 80)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(HomeColors.sheen))
    }

    @ViewBuilder
    private func joinButton(_ s: HomeNextSession) -> some View {
        if let urlStr = s.joinUrl, let url = URL(string: urlStr), s.canJoin {
            Link(destination: url) { joinLabel }
        } else {
            joinLabel.opacity(s.canJoin ? 1 : 0.55)
        }
    }

    private var joinLabel: some View {
        Text(t("Join", "انضمام"))
            .font(BrandFont.inter(size: 14, weight: .bold, isArabic: ar))
            .tracking(ar ? 0 : -0.14)
            .foregroundColor(HomeColors.nearBlack)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(HomeColors.goldButton))
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            skeleton(height: 24, width: 180).padding(.horizontal, 18)
            skeleton(height: 137, width: 296).padding(.horizontal, 18)
            skeleton(height: 19, width: 200).padding(.horizontal, 18).padding(.top, 8)
            HStack(spacing: 10) {
                skeleton(height: 156, width: 192)
                skeleton(height: 156, width: 120)
            }.padding(.horizontal, 18)
            skeleton(height: 80, width: nil).padding(.horizontal, 16).padding(.top, 8)
        }
    }

    private func skeleton(height: CGFloat, width: CGFloat?) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(HomeColors.surface)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    // MARK: - Sheet / deep-link plumbing

    private func sheetContent(_ idBox: CourseSheetItem) -> some View {
        CourseDetailSheetView(courseId: idBox.id) { presentedCourseId = nil }
            .adaptiveSheetChrome(background: HomeColors.bg)
    }

    private struct CourseSheetItem: Identifiable, Equatable { let id: String }

    private var courseSheetBinding: Binding<CourseSheetItem?> {
        Binding(
            get: { presentedCourseId.map(CourseSheetItem.init(id:)) },
            set: { presentedCourseId = $0?.id })
    }

    private func handlePendingDeepLink() {
        guard let id = pendingCourseId else { return }
        presentedCourseId = id
        pendingCourseId = nil
    }

    // MARK: - Formatting helpers

    private func t(_ en: String, _ arr: String) -> String { ar ? arr : en }

    private func localizedCourseTitle(_ c: CourseSummary) -> String {
        L10n.localized(appLocale, ar: c.titleAr, en: c.titleEn)
    }

    private func watchedLabel(_ e: EnrolledCourse) -> String {
        let total = e.totalDurationSeconds
        let watched = Int(Double(total) * min(1, max(0, e.progressPct / 100)))
        // "watched / total" is isolated as one unit, not one isolate per side:
        // the slash is neutral, so under the Arabic paragraph the two durations
        // would swap and the total would read as the watched figure.
        return bidiJoin("\(durationHM(watched)) / \(durationHM(total))",
                        t("watched", "تمت المشاهدة"),
                        separator: " ")
    }

    private func durationHM(_ secs: Int) -> String {
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func ratingText(_ r: Double?) -> String {
        guard let r else { return "—" }
        return String(format: "%.1f", r)
    }

    private func nameInitials(_ name: String) -> String {
        let words = name.split(separator: " ")
        guard let first = words.first?.first else { return "—" }
        if words.count > 1, let last = words.last?.first {
            return (String(first) + String(last)).uppercased()
        }
        return String(first).uppercased()
    }

    // The next-session chip on the FIRST screen a student sees. Without an
    // explicit `.locale(...)` these resolve against `Locale.autoupdatingCurrent`
    // — the DEVICE — so an English phone printed "APR / 17 / 3:45 PM" inside an
    // otherwise Arabic card. `.uppercased()` is dropped with it: Arabic has no
    // letter case, and uppercasing an Arabic month name is a no-op that only
    // ever mattered to the English string.
    private var chipLocale: Locale { Locale(identifier: L10n.currentLanguageCode) }
    private func monthAbbrev(_ d: Date) -> String {
        d.formatted(.dateTime.month(.abbreviated).locale(chipLocale))
    }
    private func dayNumber(_ d: Date) -> String {
        d.formatted(.dateTime.day().locale(chipLocale))
    }
    private func timeText(_ d: Date) -> String {
        d.formatted(.dateTime.hour().minute().locale(chipLocale))
    }

    private func bannerGradient(_ i: Int) -> LinearGradient {
        i % 2 == 0 ? HomeColors.azureBanner : HomeColors.violetBanner
    }

    private func instructorColor(_ inst: StudentInstructorSummary) -> Color {
        let palette = [HomeColors.hex(0xE08A2B), HomeColors.hex(0x22A06B),
                       HomeColors.hex(0x0A84FF), HomeColors.hex(0x8E5BFF),
                       HomeColors.hex(0xE0563B)]
        return palette[abs(inst.instructorId.hashValue) % palette.count]
    }

    private func recEmoji(_ rec: RecommendedCourse, _ index: Int) -> String {
        emoji(for: rec.course.titleEn, fallbackSeed: rec.course.id,
              pool: index % 2 == 0 ? ["⚛️", "🚀"] : ["⚡", "🔬"])
    }

    /// Thematic emoji keyed off the course title, falling back to a
    /// deterministic pick so arbitrary catalog data still reads as the design.
    private func emoji(for title: String, fallbackSeed: String, pool: [String]) -> String {
        let t = title.lowercased()
        if t.contains("react") { return "⚛️" }
        if t.contains("design") || t.contains("ux") || t.contains("ui") { return "🎨" }
        if t.contains("python") { return "🐍" }
        if t.contains("data") || t.contains("analyt") { return "📊" }
        if t.contains("ai") || t.contains("machine") || t.contains("ml") { return "🧠" }
        if t.contains("market") { return "📈" }
        if t.contains("fast") || t.contains("api") || t.contains("backend") || t.contains("perf") { return "⚡" }
        if t.contains("web") || t.contains("front") { return "💻" }
        return pool[abs(fallbackSeed.hashValue) % pool.count]
    }
}

// MARK: - Home palette (exact Figma hexes — node 2937:18940)

private enum HomeColors {
    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255.0,
              green: Double((v >> 8) & 0xFF) / 255.0,
              blue: Double(v & 0xFF) / 255.0,
              opacity: a)
    }

    // Canvas / surface / text tokens forward to the shared adaptive palette
    // so Home flips with the app-wide Light/Dark toggle. The Figma hexes they
    // replaced were the dark-mode values, which MyCoursesPalette reproduces on
    // its dark side. Banner gradients and status hues stay fixed; gold splits
    // into an ink token and a fill token (see below).
    static let bg          = MyCoursesPalette.background
    static let nearBlack   = hex(0x141008)  // text/icon ON the gold CTA fill — fixed in both themes
    /// Gold as INK — section titles, the carousel counter/dots, the avatar
    /// initials, the empty-card glyph. #C6A96B was picked to read on near-black;
    /// on the light cream surface it lands around 1.8:1, so foreground gold has
    /// to resolve through the adaptive accent ramp (#7A5D2C light / #C6A96B
    /// dark) — the dark side is byte-identical to the old hex.
    static let gold        = MyCoursesPalette.accent
    /// Gold as FILL — the "Browse courses" CTA plate. It draws `nearBlack` on
    /// top, so it must stay the bright brand hex in both themes.
    static let goldFill    = hex(0xC6A96B)
    /// Percent label on the continue card. Same ink problem as `gold`, worse:
    /// #E0C48F on the cream card gradient is ~1.2:1.
    static let goldText    = MyCoursesPalette.accent
    static let surface     = MyCoursesPalette.surface
    static let chipBg      = MyCoursesPalette.surfaceRaised
    static let green       = hex(0x30D158)
    static let muted60     = MyCoursesPalette.muted
    static let grey57      = MyCoursesPalette.muted
    static let grey61      = MyCoursesPalette.muted
    static let grey55      = MyCoursesPalette.muted
    static let titleText   = MyCoursesPalette.textPrimary
    static let statLabel   = MyCoursesPalette.textTertiary
    static let viewAllText = MyCoursesPalette.textPrimary
    static let cyan        = hex(0x2DC9C9)
    static let cyan13      = hex(0x2DC9C9, 0.13)
    static let dotInactive = MyCoursesPalette.textTertiary
    static let cardBorderGold = MyCoursesPalette.stroke
    // The cover tile sits *on* the continue card, whose gradient runs
    // surfaceRaised → surface, so it needs its own hairline to stay distinct.
    static let iconBoxBorder = MyCoursesPalette.stroke

    /// Fallback fill for a course with no cover art. Picked deterministically
    /// from the course id so a given course always wears the same colour.
    static func coverTint(for seed: String) -> Color {
        let palette = [hex(0x8C5CF6), hex(0x338CF2), hex(0xF28C33),
                       hex(0x33B372), hex(0xED599A), hex(0xE5B840)]
        var hash = 5381
        for byte in seed.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        return palette[abs(hash) % palette.count]
    }
    static let recBorder   = MyCoursesPalette.stroke
    static let instrBorder = MyCoursesPalette.stroke
    static let statsBorder = MyCoursesPalette.stroke
    static let viewAllBorder = MyCoursesPalette.stroke

    // Empty-state cards (new-student home — node 3066:12156)
    static let emptyCardBg     = MyCoursesPalette.background      // dashed empty card fill
    static let emptyCardBorder = MyCoursesPalette.stroke          // dashed empty card border
    static let iconTileBg      = MyCoursesPalette.surface         // empty card icon tile bg
    static let iconTileBorder  = MyCoursesPalette.stroke          // empty card icon tile border
    static let emptyTitle      = MyCoursesPalette.textPrimary     // empty card title
    static let emptySubtitle   = MyCoursesPalette.muted           // empty card subtitle
    static let recEmptyBg      = MyCoursesPalette.surface         // "Enroll to unlock" card base
    static let recEmptyBorder  = MyCoursesPalette.stroke          // "Enroll to unlock" card border
    static let recGlow         = hex(0x8C6928)  // top-center gold glow (@14%)

    static let goldButton = LinearGradient(
        stops: [.init(color: hex(0xC6A96B), location: 0.293),
                .init(color: hex(0x605234), location: 0.947)],
        startPoint: .leading, endPoint: .trailing)

    // 134.77° ≈ top-leading → bottom-trailing. Adaptive stops: the warm
    // near-black pair the Figma specifies is what the palette resolves to in
    // dark; light mode gets the matching cream pair.
    static let cardGradient = LinearGradient(
        stops: [.init(color: MyCoursesPalette.surfaceRaised, location: 0),
                .init(color: MyCoursesPalette.surface, location: 0.6)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let progressFill = LinearGradient(
        stops: [.init(color: hex(0x5E4E2A), location: 0),
                .init(color: hex(0xA88E50), location: 0.52),
                .init(color: hex(0xE8D096), location: 1)],
        startPoint: .leading, endPoint: .trailing)

    // ~160°, surface → translucent gold sheen (next-session card + stats box).
    static let sheen = LinearGradient(
        stops: [.init(color: MyCoursesPalette.surface, location: 0.31),
                .init(color: hex(0xC6A96B, 0.5), location: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let azureBanner = LinearGradient(
        colors: [hex(0x1C2D4A), hex(0x0D1626)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let violetBanner = LinearGradient(
        colors: [hex(0x2A1438), hex(0x160A22)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// =====================================================================
// MARK: - Ask Droob AI hero card
// =====================================================================
//
// A single, large, always-visible card at the top of Home that advertises what
// the AI tutor actually does — in motion — and opens it on tap.
//
// Everything below lives in this file on purpose. `DroobStudent.xcodeproj` is
// `objectVersion = 56` with no filesystem-synchronised group, so a new .swift
// on disk would need four separate `project.pbxproj` registrations and would
// otherwise compile to nothing and fail silently at link time.
//
// PERFORMANCE — the mechanism, stated plainly.
//   Home is a plain `VStack` inside a `ScrollView` (not a `List`, not lazy), so
//   the card stays *instantiated* when it scrolls away. Something therefore has
//   to stop the clock explicitly. There is exactly one clock, read by two
//   timelines (the `Canvas` and the typed row) that share the same `running`
//   flag and the same `elapsed(at:)`:
//
//     TimelineView(.animation(minimumInterval: 1/30, paused: !running))
//     running = !reduceMotion && scenePhase == .active && onScreen
//
//   * off-screen  → `.onScrollVisibilityChange(threshold: 0.10)` flips
//     `onScreen`. (iOS 18 API; the deployment target is 18.0 on every
//     configuration, so no availability guard is needed.)
//   * backgrounded → `scenePhase != .active`, the same rule `AmbientMotion` in
//     ChatView already uses.
//   * reduced motion → `running` is false forever and `t` is pinned to 0.
//
//   `t` accumulates across pauses (`accrued` + time since `resumedAt`) so
//   nothing jumps when the card comes back. All four motions are pure
//   functions of `t`, drawn by ONE `Canvas` in one pass; the only other thing
//   under a timeline is the typed line, marked `.equatable()` so the text
//   subtree is not re-laid-out on the ~28 frames in 30 where neither the
//   string nor the caret changed.
//
//   What is NOT under a timeline matters just as much. The card's gradient
//   fill, its 1 pt border and its drop shadow, plus the eyebrow chip, the
//   headline and the CTA row, are built once per layout in `card(geo:ink:rtl:)`
//   and never re-diffed per frame. A shadow inside the timeline would have its
//   source alpha invalidated by the redrawn `Canvas` every frame, forcing Core
//   Animation to re-rasterise and gaussian-blur the whole card offscreen 30×/s.
//   For the same reason the artwork's ~30 paths, its stroke styles and the
//   rule-colour ramp are precomputed into `HeroArt` outside the `Canvas`
//   closure, and each sheet is transformed through a `GraphicsContext` value
//   copy rather than `drawLayer`, so no frame opens an offscreen buffer.
//
// TYPE SIZES are deliberately NOT routed through `BrandFont`/`TypeScale`.
// The card's internal grid (22 / 24 / 19 / 18 pt rows summing to a 150 pt card)
// is authored against the same 390 pt artboard as the point sizes, and the
// long Arabic headline only fits the 210 pt text column at the authored size.
// Pushing every size through the app-wide 1.242 factor would overflow both the
// row boxes and the column. See `heroFont` below.

// MARK: Hero geometry
//
// One scale factor drives the whole card. 358 is the phone card width on the
// 390 pt artboard (390 − 2×16). `cardW` is capped and `s` clamped at 1.30 so an
// iPad gets a *bigger card*, not a letterbox band of empty gold: at 520 pt the
// artwork panel jumps to a fixed 160 and gains a fourth sheet, and the whole
// content group is centred.
//
// The width cap is 520, not the 640 the layout table names. 640 was picked to
// stop the card stretching, but the content cannot fill it: the artwork panel
// is bounded by the card's HEIGHT (sheet A is 92 units tall, so u ≤ 164/92 and
// panelW ≤ ~178), and the text column only needs 210 × ts. 520 is the width at
// which the ramp's own numbers — panel 160, gap 15.6, text 241.5, margins
// 51 — add up to a filled card instead of one with 140 pt of gold nothing in
// the middle. Everything else in the table is unchanged, and no phone is
// affected: the cap only binds above 520.
private struct HeroGeo: Equatable {
    let cardW: CGFloat
    let cardH: CGFloat
    /// Geometry ramp, 1.00 (phone) → 1.30 (iPad).
    let s: CGFloat
    /// Type ramp, capped a little lower so text never outgrows its row box.
    let ts: CGFloat
    let padH: CGFloat
    let padV: CGFloat
    let panelW: CGFloat
    let gap: CGFloat
    let radius: CGFloat
    let textW: CGFloat
    /// Text column + gap + artwork panel. Centred in the card, so the leftover
    /// width on a wide layout becomes even outer margin instead of a dead hole
    /// between a left-pinned drawing and a right-pinned paragraph.
    let groupW: CGFloat
    /// Distance from the card edge to the content group. Equals `padH` on
    /// every phone; larger only once the text column hits its cap. The Canvas
    /// derives the artwork panel's centre from this, so drawing and layout
    /// can't drift apart.
    let sideInset: CGFloat
    /// True on the wide layout — adds sheet D behind the stack.
    let wide: Bool

    init(available: CGFloat) {
        let w = min(max(available, 260), 520)
        let scale = min(max(w / 358, 1.0), 1.30)
        let ph = 18 * scale
        let panel: CGFloat = w >= 520 ? 160 : 100 * scale
        let gp = 12 * scale
        let typeScale = min(scale, 1.15)
        // The text column is capped at the PHONE column scaled by the type
        // ramp — 210 pt is what the long Arabic headline and the longest
        // English phrase need at ts = 1.00, so 210 × ts is what they need at
        // any ts. Handing an iPad the ~300 pt that is merely left over would
        // put 100 pt of dead air between the sentence and the drawing, which
        // is the same "band of empty space" the `cardW` cap exists to avoid —
        // just moved inside the card. On every phone the cap is exactly the
        // available width, so the phone layout is bit-for-bit unchanged.
        let text = max(min(w - 2 * ph - panel - gp, 210 * typeScale), 90)
        let group = text + gp + panel

        cardW = w
        s = scale
        ts = typeScale
        cardH = (150 * scale).rounded()
        radius = (22 * scale).rounded()
        padH = ph
        padV = ph
        panelW = panel
        gap = gp
        textW = text
        groupW = group
        sideInset = max((w - group) / 2, ph)
        wide = w >= 520
    }
}

// MARK: Hero palette
//
// Light and dark are both authored; neither is an inversion of the other.
// Dark keeps the brand `#C6A96B` as ink. Light drops to `#7A5D2C` — the same
// darkened ramp `MyCoursesPalette.accent` already uses — because raw brand gold
// measures ~1.8:1 on the cream surface.
//
// Note the deliberate choice on dark: the paper is a warm dark tone, not white.
// A white sheet on a near-black card would be the brightest thing on Home and
// would out-shout the student's own course list; the gold rules carry the
// "paper" reading instead.
private struct HeroRGB {
    let r: Double, g: Double, b: Double

    init(_ v: UInt32) {
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }

    /// Linear blend towards `other`. Used for the ruled lines, which travel
    /// from `ruleUnread` to `ruleRead` behind the scan bar.
    func lerp(to other: HeroRGB, _ k: Double) -> Color {
        let k = min(max(k, 0), 1)
        return Color(red: r + (other.r - r) * k,
                     green: g + (other.g - g) * k,
                     blue: b + (other.b - b) * k)
    }
}

private struct HeroInk {
    let cardTop: Color, cardBottom: Color, border: Color
    let shadow: Color, shadowRadius: CGFloat, shadowY: CGFloat
    let glow: Color, glowBase: Double
    let shimmer: Color, shimmerPeak: Double
    let chipBg: Color, chipInk: Color
    let headline: Color, streamInk: Color, caret: Color, ctaInk: Color
    let sheetFillA: Color, sheetFillB: Color, sheetFillC: Color
    let sheetStroke: Color, foldFill: Color
    let ruleUnread: HeroRGB, ruleRead: HeroRGB
    let glyphInk: Color, scanInk: Color

    static func resolve(dark: Bool) -> HeroInk {
        if dark {
            return HeroInk(
                cardTop: HomeColors.hex(0x1B1610),
                cardBottom: HomeColors.hex(0x100D08),
                border: HomeColors.hex(0x3A2F18),
                shadow: HomeColors.hex(0xC6A96B, 0.10), shadowRadius: 14, shadowY: 4,
                glow: HomeColors.hex(0xC6A96B), glowBase: 0.16,
                shimmer: HomeColors.hex(0xE8D096), shimmerPeak: 0.18,
                chipBg: HomeColors.hex(0xC6A96B, 0.14),
                chipInk: HomeColors.hex(0xE0C48F),
                headline: HomeColors.hex(0xF5F1E8),
                streamInk: HomeColors.hex(0xE0C48F),
                caret: HomeColors.hex(0xC6A96B),
                ctaInk: HomeColors.hex(0xC6A96B),
                sheetFillA: HomeColors.hex(0x2A2318),
                sheetFillB: HomeColors.hex(0x221C13),
                sheetFillC: HomeColors.hex(0x1C1710),
                sheetStroke: HomeColors.hex(0x4A3D22),
                foldFill: HomeColors.hex(0x3E3320),
                ruleUnread: HeroRGB(0x6B5B38), ruleRead: HeroRGB(0xD9BC88),
                glyphInk: HomeColors.hex(0xE0C48F),
                scanInk: HomeColors.hex(0xE8D096))
        }
        return HeroInk(
            cardTop: HomeColors.hex(0xFFFCF4),
            cardBottom: HomeColors.hex(0xF3EBDA),
            border: HomeColors.hex(0xE0D2AE),
            shadow: HomeColors.hex(0x000000, 0.06), shadowRadius: 10, shadowY: 3,
            glow: HomeColors.hex(0xC6A96B), glowBase: 0.10,
            shimmer: HomeColors.hex(0xC6A96B), shimmerPeak: 0.10,
            chipBg: HomeColors.hex(0x7A5D2C, 0.10),
            chipInk: HomeColors.hex(0x7A5D2C),
            headline: HomeColors.hex(0x15130F),
            streamInk: HomeColors.hex(0x7A5D2C),
            caret: HomeColors.hex(0x7A5D2C),
            ctaInk: HomeColors.hex(0x7A5D2C),
            sheetFillA: HomeColors.hex(0xFFFFFF),
            sheetFillB: HomeColors.hex(0xFBF6EA),
            sheetFillC: HomeColors.hex(0xF5EEDD),
            sheetStroke: HomeColors.hex(0xDFD3B6),
            foldFill: HomeColors.hex(0xEDE2C6),
            ruleUnread: HeroRGB(0xC9BFA8), ruleRead: HeroRGB(0x8A6D2F),
            glyphInk: HomeColors.hex(0x7A5D2C),
            scanInk: HomeColors.hex(0xA88E50))
    }
}

// MARK: Copy
//
// Localised once and memoised: the typing machine walks *grapheme clusters* of
// the original string, and `Array(String)` is a cluster array in Swift, so the
// per-frame cost is an array slice and nothing else.
private struct HeroCopy: Equatable {
    let eyebrow: String
    let title: String
    let cta: String
    let a11y: String
    let a11yHint: String
    /// Grapheme-cluster arrays. NEVER `utf16`, `unicodeScalars` or
    /// `NSString.substring(to:)` — Arabic is a joined script with combining
    /// marks and slicing by code unit produces broken glyphs.
    let phrases: [[Character]]
    /// Per-phrase duration in ms: n×45 (type) + 1600 (hold) + n×22 (delete)
    /// + 320 (gap) = n×67 + 1920.
    let durations: [Double]
    let cycle: Double

    static func build() -> HeroCopy {
        let raw = [L10n.homeAiHeroPhrase1, L10n.homeAiHeroPhrase2,
                   L10n.homeAiHeroPhrase3, L10n.homeAiHeroPhrase4]
        let phrases = raw.map { Array($0) }
        let durations = phrases.map { Double($0.count) * 67 + 1920 }
        return HeroCopy(eyebrow: L10n.homeAiHeroEyebrow,
                        title: L10n.homeAiHeroTitle,
                        cta: L10n.homeAiHeroCta,
                        a11y: L10n.homeAiHeroA11y,
                        a11yHint: L10n.homeAiHeroA11yHint,
                        phrases: phrases,
                        durations: durations,
                        cycle: durations.reduce(0, +))
    }
}

// MARK: Typing machine
//
// A pure function of the clock — no stored animation state, so a pause and a
// resume cannot desynchronise it. Cadence: 45 ms per cluster while typing,
// 1600 ms hold, 22 ms per cluster while deleting, 320 ms at empty. The caret
// is SOLID while typing or deleting and blinks at 530 ms only during the hold
// and the gap — what a real terminal does, and it stops the caret strobing
// against fast-moving text.
private enum TypeMachine {
    static let typeMs = 45.0
    static let holdMs = 1600.0
    static let deleteMs = 22.0
    static let blinkMs = 530.0

    struct Frame {
        let text: String
        let caretOn: Bool
    }

    static func stateAt(_ tMs: Double, copy: HeroCopy, reduced: Bool) -> Frame {
        guard let first = copy.phrases.first else { return Frame(text: "", caretOn: false) }
        // Reduced motion: phrase index 0, fully typed, no caret. A finished
        // sentence, not a half-finished one waiting for a frame that never comes.
        if reduced || copy.cycle <= 0 {
            return Frame(text: String(first), caretOn: false)
        }

        var u = tMs.truncatingRemainder(dividingBy: copy.cycle)
        if u < 0 { u += copy.cycle }

        var i = 0
        while i < copy.durations.count - 1 && u >= copy.durations[i] {
            u -= copy.durations[i]
            i += 1
        }

        let clusters = copy.phrases[i]
        let n = clusters.count
        let typeEnd = Double(n) * typeMs
        let holdEnd = typeEnd + holdMs
        let deleteEnd = holdEnd + Double(n) * deleteMs

        var visible: Int
        var solid = false
        if u < typeEnd {
            visible = Int((u / typeMs).rounded(.down))
            solid = true
        } else if u < holdEnd {
            visible = n
        } else if u < deleteEnd {
            visible = n - Int(((u - holdEnd) / deleteMs).rounded(.down))
            solid = true
        } else {
            visible = 0
        }
        visible = min(max(visible, 0), n)

        let caretOn = solid || Int((tMs / blinkMs).rounded(.down)) % 2 == 0
        return Frame(text: String(clusters[0..<visible]), caretOn: caretOn)
    }
}

// MARK: Fonts
//
// See the note at the top of this section: the hero grid is authored at the
// same scale as these point sizes, so they bypass `TypeScale`. Arabic routes
// to the system face (SF Arabic) at the matching weight, exactly as
// `BrandFont` does — Inter has no Arabic coverage.
private func heroFont(size: CGFloat, weight: Font.Weight, isArabic: Bool) -> Font {
    if isArabic { return .system(size: size, weight: weight) }
    switch weight {
    case .bold, .heavy, .black: return .custom(BrandFont.interBold, size: size)
    case .semibold:             return .custom(BrandFont.interSemiBold, size: size)
    case .medium:               return .custom(BrandFont.interMedium, size: size)
    default:                    return .custom(BrandFont.interRegular, size: size)
    }
}

// MARK: The typed line
//
// `Equatable` on (text, caret, scale, locale, theme) only — so `.equatable()`
// lets SwiftUI skip the text subtree on every frame where none of those moved,
// which is roughly 28 frames out of 30.
private struct HeroTypedLine: View, Equatable {
    let text: String
    let caretOn: Bool
    let showCaret: Bool
    let s: CGFloat
    let ts: CGFloat
    let isArabic: Bool
    let dark: Bool
    let ink: Color
    let caretInk: Color

    static func == (a: HeroTypedLine, b: HeroTypedLine) -> Bool {
        a.text == b.text && a.caretOn == b.caretOn && a.showCaret == b.showCaret
            && a.s == b.s && a.ts == b.ts && a.isArabic == b.isArabic && a.dark == b.dark
    }

    var body: some View {
        // Sibling caret inside an HStack: the stack mirrors with layout
        // direction, so the caret lands to the LEFT of Arabic text and to the
        // RIGHT of English text with no special case anywhere.
        HStack(alignment: .center, spacing: 3 * s) {
            // FIRST STRONG ISOLATE … POP DIRECTIONAL ISOLATE, applied at
            // render time only and never counted as graphemes. This is what
            // keeps the Latin run in "قراءة ورقة عمل PDF" from flipping the
            // whole line while P, PD, PDF arrive.
            Text(text.bidiIsolated)
                .font(heroFont(size: 13.5 * ts, weight: .regular, isArabic: isArabic))
                .foregroundColor(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .accessibilityHidden(true)
            if showCaret {
                RoundedRectangle(cornerRadius: 1 * s, style: .continuous)
                    .fill(caretInk)
                    .frame(width: 2 * s, height: 14 * s)
                    .opacity(caretOn ? 1 : 0)   // hard cut, never a fade
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: The artwork — every shape is a Path, no bitmaps, no SF Symbols
//
// Authored in "sheet units" on a 100-unit-wide panel and scaled by
// `u = panelW / 100`. Sheet A (front) is the reference: 68 × 92, radius 5,
// fold 16.
private struct HeroSheetSpec {
    let w: CGFloat            // sheet units
    let h: CGFloat            // sheet units
    let rot: Double           // degrees
    let dx: CGFloat           // offset from panel centre, sheet units
    let dy: CGFloat           // offset from panel centre, sheet units
    let opacity: Double
    let bobAmp: Double        // points, ×s
    let bobPhase: Double      // radians
    let front: Bool           // only sheet A carries rules + glyphs + the scan
}

/// The sheet silhouette: rounded rect with the top-trailing corner cut away
/// for the fold. Built in LTR sheet-local coordinates and reflected as a whole
/// (`x' = w − x`) in RTL, so the fold lands on the sheet's top-left.
private func heroSheetOutline(w: CGFloat, h: CGFloat, r: CGFloat, f: CGFloat, rtl: Bool) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r, y: 0))
    p.addLine(to: CGPoint(x: w - f, y: 0))
    p.addLine(to: CGPoint(x: w, y: f))                     // the fold cut
    p.addLine(to: CGPoint(x: w, y: h - r))
    p.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - r, y: h), radius: r)
    p.addLine(to: CGPoint(x: r, y: h))
    p.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - r), radius: r)
    p.addLine(to: CGPoint(x: 0, y: r))
    p.addArc(tangent1End: .zero, tangent2End: CGPoint(x: r, y: 0), radius: r)
    p.closeSubpath()
    return rtl ? p.applying(heroMirror(w)) : p
}

private func heroMirror(_ w: CGFloat) -> CGAffineTransform {
    CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
}

/// Every path, colour and stroke style in the artwork whose value is a pure
/// function of (geometry, direction, palette) — which is all of them except
/// the two scan rectangles and the rules' current tint.
///
/// Built ONCE per layout, OUTSIDE the `TimelineView`, and captured by the
/// `Canvas` closure. Rebuilding these ~30 `CGPath`-backed objects on every one
/// of the 30 frames/s is the thing a Canvas animation must never do: it is
/// sustained main-thread allocation that lands straight on top of Home's
/// scroll run loop the moment the user flicks the list.
private struct HeroArt {
    struct Sheet {
        /// Sheet-local coordinates, RTL mirroring already baked in.
        let outline: Path
        let flap: Path
        let edge: Path
        let fill: Color
        let opacity: Double
        let sw: CGFloat
        let sh: CGFloat
        /// Card-absolute centre, before the bob.
        let cx: CGFloat
        let cy: CGFloat
        /// Degrees, RTL already applied.
        let rot: Double
        /// Points — already multiplied by the geometry ramp.
        let bobAmp: Double
        let bobPhase: Double
        let front: Bool
    }

    /// Quantisation of the unread → read ramp. A 1/32 step between two
    /// neighbouring tones is invisible, and it costs zero allocations a frame.
    static let rampSteps = 32

    let cardW: CGFloat
    let cardH: CGFloat
    let cardPath: Path
    let panelCX: CGFloat
    let panelCY: CGFloat
    let u: CGFloat
    let hairline: CGFloat

    let sheets: [Sheet]
    let sheetStroke: Color
    let foldFill: Color

    let rules: [Path]
    let ruleYUnits: [CGFloat]
    let ruleStyle: StrokeStyle
    let ruleRamp: [Color]

    let integral: Path
    let integralStyle: StrokeStyle
    let bar: Path
    let barStyle: StrokeStyle
    let dots: [Path]
    let glyphInk: Color

    init(g: HeroGeo, ink: HeroInk, rtl: Bool) {
        let w = g.cardW
        let h = g.cardH
        cardW = w
        cardH = h
        cardPath = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                        cornerRadius: g.radius, style: .continuous)

        // The artwork panel sits on the card's trailing side — right in LTR,
        // left in RTL. `Canvas` is pinned to LTR by the caller so these
        // coordinates are absolute and the maths glyphs can never be flipped
        // by the framework.
        let pcx = rtl ? g.sideInset + g.panelW / 2 : w - g.sideInset - g.panelW / 2
        panelCX = pcx
        panelCY = h / 2

        let unit = g.panelW / 100
        u = unit
        hairline = 1 * unit

        var specs: [HeroSheetSpec] = []
        if g.wide {
            // The extra iPad width is spent on content, not air.
            specs.append(HeroSheetSpec(w: 54, h: 74, rot: 12, dx: -26, dy: -14,
                                       opacity: 0.16, bobAmp: 0.6, bobPhase: 2.4, front: false))
        }
        specs.append(HeroSheetSpec(w: 58, h: 78, rot: -9, dx: -16, dy: -8,
                                   opacity: 0.28, bobAmp: 0.9, bobPhase: 1.60, front: false))
        specs.append(HeroSheetSpec(w: 62, h: 84, rot: 5, dx: -4, dy: 2,
                                   opacity: 0.50, bobAmp: 1.4, bobPhase: 0.80, front: false))
        specs.append(HeroSheetSpec(w: 68, h: 92, rot: -2, dx: 8, dy: 6,
                                   opacity: 1.00, bobAmp: 2.0, bobPhase: 0, front: true))

        let fills = g.wide
            ? [ink.sheetFillC, ink.sheetFillC, ink.sheetFillB, ink.sheetFillA]
            : [ink.sheetFillC, ink.sheetFillB, ink.sheetFillA]

        // RTL mirrors the offsets and the rotations — and nothing else.
        let mx: CGFloat = rtl ? -1 : 1
        var built: [Sheet] = []
        built.reserveCapacity(specs.count)
        for (index, spec) in specs.enumerated() {
            let sw = spec.w * unit
            let sh = spec.h * unit
            let f = 16 * unit
            let outline = heroSheetOutline(w: sw, h: sh, r: 5 * unit, f: f, rtl: rtl)

            // Fold flap — a filled triangle over the cut, so the corner reads
            // as folded paper rather than a chamfer.
            var flap = Path()
            flap.move(to: CGPoint(x: sw - f, y: 0))
            flap.addLine(to: CGPoint(x: sw, y: f))
            flap.addLine(to: CGPoint(x: sw - f, y: f))
            flap.closeSubpath()
            var edge = Path()
            edge.move(to: CGPoint(x: sw - f, y: 0))
            edge.addLine(to: CGPoint(x: sw, y: f))
            if rtl {
                flap = flap.applying(heroMirror(sw))
                edge = edge.applying(heroMirror(sw))
            }

            built.append(Sheet(outline: outline, flap: flap, edge: edge,
                               fill: fills[index], opacity: spec.opacity,
                               sw: sw, sh: sh,
                               cx: pcx + spec.dx * mx * unit,
                               cy: h / 2 + spec.dy * unit,
                               rot: rtl ? -spec.rot : spec.rot,
                               bobAmp: spec.bobAmp * Double(g.s),
                               bobPhase: spec.bobPhase,
                               front: spec.front))
        }
        sheets = built
        sheetStroke = ink.sheetStroke
        foldFill = ink.foldFill

        // Ruled lines — anchored to the sheet's LEADING inset: x = 10 running
        // right in LTR, x = 58 running left in RTL.
        let ys: [CGFloat] = [40, 50, 60, 70, 80]
        let lengths: [CGFloat] = [0.95, 0.72, 1.00, 0.58, 0.86]
        ruleYUnits = ys
        rules = (0..<5).map { k -> Path in
            let len = lengths[k] * 48 * unit
            let x1 = rtl ? 58 * unit : 10 * unit
            let x2 = rtl ? 58 * unit - len : 10 * unit + len
            var p = Path()
            p.move(to: CGPoint(x: x1, y: ys[k] * unit))
            p.addLine(to: CGPoint(x: x2, y: ys[k] * unit))
            return p
        }
        ruleStyle = StrokeStyle(lineWidth: 1.7 * unit, lineCap: .round)
        let steps = HeroArt.rampSteps
        ruleRamp = (0...steps).map { ink.ruleUnread.lerp(to: ink.ruleRead, Double($0) / Double(steps)) }

        // Maths glyphs. In RTL only the group ORIGIN moves
        // (x' = 68 − 11 − 36 = 21, i.e. +10); the paths are never mirrored.
        // Saudi curriculum maths is typeset left-to-right regardless of the
        // surrounding Arabic, and a back-to-front ∫ would read as an error.
        let gdx: CGFloat = rtl ? 10 : 0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: (x + gdx) * unit, y: y * unit)
        }

        var ip = Path()
        ip.move(to: pt(19.0, 10.0))
        ip.addCurve(to: pt(13.0, 12.0), control1: pt(19.0, 7.5), control2: pt(13.0, 7.5))
        ip.addCurve(to: pt(19.0, 24.0), control1: pt(13.0, 16.0), control2: pt(19.0, 20.0))
        ip.addCurve(to: pt(13.0, 26.0), control1: pt(19.0, 28.5), control2: pt(13.0, 28.5))
        integral = ip
        integralStyle = StrokeStyle(lineWidth: 1.8 * unit, lineCap: .round)

        var bp = Path()
        bp.move(to: pt(28, 18))
        bp.addLine(to: pt(46, 18))
        bar = bp
        barStyle = StrokeStyle(lineWidth: 1.6 * unit, lineCap: .round)

        dots = ([12.5, 23.5] as [CGFloat]).map { dotY -> Path in
            let c = pt(37, dotY)
            return Path(ellipseIn: CGRect(x: c.x - 1.8 * unit, y: c.y - 1.8 * unit,
                                          width: 3.6 * unit, height: 3.6 * unit))
        }
        glyphInk = ink.glyphInk
    }
}

/// The whole card's motion, drawn in ONE pass. Every value here is a pure
/// function of `t`; nothing is stored, so pausing and resuming the clock is
/// invisible.
///
/// Two rules keep the per-frame cost flat:
///
///  * NO ALLOCATION. Every path, colour and stroke style comes out of `art`,
///    which was built once outside the `TimelineView`. The only objects made
///    here are the two scan rectangles and the two ambient gradients, and the
///    scan pair exists for 2.4 s in every 6.
///  * NO TRANSPARENCY LAYERS. Each sheet is drawn through a VALUE COPY of the
///    context (`var layer = ctx`), which carries its own transform, clip and
///    opacity with no render-target switch. `drawLayer` would open an offscreen
///    buffer per sheet, per frame, forever — 4 of them, 5 while the scan is up.
///    The one thing a copy does not give is GROUP opacity: on the three ghost
///    sheets the fold flap now composites over the sheet fill rather than with
///    it. Their fills sit within ~2 % of the card gradient by design (see the
///    palette note), so the difference is arithmetic, not visible; the front
///    sheet — the only one anybody actually reads — is at opacity 1 and is
///    bit-identical either way.
private func heroDraw(_ ctx: inout GraphicsContext, t: Double,
                      ink: HeroInk, art: HeroArt, reduced: Bool) {
    let w = art.cardW
    let h = art.cardH
    guard w > 1, h > 1 else { return }

    // ── 1. Glow breath (5.00 s) ────────────────────────────────────────────
    let breath = reduced ? 0 : sin(2 * .pi * t / 5.0)
    let glowRadius = 0.62 * h * (1 + 0.06 * breath)
    let glowAlpha = ink.glowBase * (reduced ? 1.0 : 0.85 + 0.15 * breath)
    ctx.fill(art.cardPath, with: .radialGradient(
        Gradient(stops: [.init(color: ink.glow.opacity(glowAlpha), location: 0),
                         .init(color: ink.glow.opacity(0), location: 1)]),
        center: CGPoint(x: art.panelCX, y: art.panelCY),
        startRadius: 0, endRadius: max(glowRadius, 1)))

    // ── 2. Shimmer sweep (12.00 s = 4.5 s sweep + 7.5 s dark) ──────────────
    // Three clamped stops, so the gradient *is* the band: everything outside
    // it is transparent. Skipped entirely — no draw call — while dark.
    if !reduced {
        let cycle = t.truncatingRemainder(dividingBy: 12.0)
        if cycle < 4.5 {
            let p = cycle / 4.5
            let alpha = ink.shimmerPeak * sin(.pi * p)   // fades in/out, no pop
            let x0 = (-0.30 + 1.30 * p) * w
            ctx.fill(art.cardPath, with: .linearGradient(
                Gradient(stops: [.init(color: ink.shimmer.opacity(0), location: 0),
                                 .init(color: ink.shimmer.opacity(alpha), location: 0.5),
                                 .init(color: ink.shimmer.opacity(0), location: 1)]),
                startPoint: CGPoint(x: x0, y: -0.20 * h),
                endPoint: CGPoint(x: x0 + 0.30 * w, y: 1.20 * h)))
        }
    }

    // ── 3. Scan sweep (6.00 s: 2.4 s down + 0.8 s fade back + 2.8 s idle) ──
    let scanP = reduced ? 0 : t.truncatingRemainder(dividingBy: 6.0) / 6.0
    let scanning = !reduced && scanP < 0.40
    let scanYUnits = scanning ? (scanP / 0.40) * 92 : 0
    let steps = Double(HeroArt.rampSteps)

    // ── 4. The document stack, back to front ───────────────────────────────
    for sheet in art.sheets {
        let bob = reduced ? 0 : sheet.bobAmp * sin(2 * .pi * t / 7.0 + sheet.bobPhase)

        var layer = ctx                       // value copy, not an offscreen
        layer.opacity = sheet.opacity
        layer.translateBy(x: sheet.cx, y: sheet.cy + CGFloat(bob))
        layer.rotate(by: .degrees(sheet.rot))
        layer.translateBy(x: -sheet.sw / 2, y: -sheet.sh / 2)

        layer.fill(sheet.outline, with: .color(sheet.fill))
        layer.stroke(sheet.outline, with: .color(art.sheetStroke), lineWidth: art.hairline)
        layer.fill(sheet.flap, with: .color(art.foldFill))
        layer.stroke(sheet.edge, with: .color(art.sheetStroke), lineWidth: art.hairline)

        guard sheet.front else { continue }

        // Ruled lines. Only the TINT moves with `t`; the geometry is `art`'s.
        for k in art.rules.indices {
            let readK: Double
            if reduced {
                readK = 1                                  // the finished state
            } else if scanning {
                readK = min(max((scanYUnits - Double(art.ruleYUnits[k])) / 4, 0), 1)
            } else {
                readK = min(max(1 - (scanP - 0.40) / 0.1333, 0), 1)
            }
            let index = Int((readK * steps).rounded())
            layer.stroke(art.rules[k], with: .color(art.ruleRamp[index]), style: art.ruleStyle)
        }

        layer.stroke(art.integral, with: .color(art.glyphInk), style: art.integralStyle)
        layer.stroke(art.bar, with: .color(art.glyphInk), style: art.barStyle)
        for dot in art.dots {
            layer.fill(dot, with: .color(art.glyphInk))
        }

        // The scan bar itself, clipped to the sheet: a gold bar walking down
        // the page with a soft comet trailing above it. This is what says
        // "reading a worksheet". The clip rides on another context copy — same
        // isolation as a nested layer, none of the compositing.
        guard scanning else { continue }
        var scan = layer
        scan.clip(to: sheet.outline)
        let y = CGFloat(scanYUnits) * art.u
        scan.fill(Path(CGRect(x: 0, y: y, width: sheet.sw, height: 2 * art.u)),
                  with: .color(ink.scanInk.opacity(0.85)))
        scan.fill(Path(CGRect(x: 0, y: y - 10 * art.u, width: sheet.sw, height: 10 * art.u)),
                  with: .linearGradient(
                    Gradient(stops: [.init(color: ink.scanInk.opacity(0), location: 0),
                                     .init(color: ink.scanInk.opacity(0.35), location: 1)]),
                    startPoint: CGPoint(x: 0, y: y - 10 * art.u),
                    endPoint: CGPoint(x: 0, y: y)))
    }
}

// MARK: - AiHeroCard

/// The Home hero. One tap target, one accessibility element, one clock.
///
/// Navigation reuses the existing route: posting `AppTab.ai` on
/// `.droobSwitchToTab` is exactly what the docked AI orb in `MainTabView`
/// does, so the card and the tab-bar entry land in the same place with zero
/// new plumbing.
struct AiHeroCard: View {
    let isArabic: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// Flipped by `.onScrollVisibilityChange`. Home's `ScrollView` is NOT
    /// lazy, so the card stays instantiated when scrolled away — this is what
    /// actually stops the clock.
    @State private var onScreen = true
    @State private var measuredWidth: CGFloat = 0
    /// Seconds banked while paused, plus the instant the clock last resumed.
    /// `t = accrued + now − resumedAt`, so nothing jumps across a pause.
    @State private var accrued: TimeInterval = 0
    @State private var resumedAt: Date? = nil
    @State private var copy: HeroCopy

    init(isArabic: Bool) {
        self.isArabic = isArabic
        _copy = State(initialValue: HeroCopy.build())
    }

    private var running: Bool {
        !reduceMotion && scenePhase == .active && onScreen
    }

    /// Used for the single frame before `onGeometryChange` reports, so the card
    /// never renders at a nonsense size. Both values are already clamped by
    /// `HeroGeo`, so this only picks which side of the ramp to start on.
    private var fallbackWidth: CGFloat {
        hSizeClass == .regular ? 520 : 358
    }

    private func elapsed(at date: Date) -> TimeInterval {
        guard !reduceMotion else { return 0 }
        guard let resumedAt else { return accrued }
        return accrued + max(0, date.timeIntervalSince(resumedAt))
    }

    /// Banks the elapsed time on pause and restarts the reference on resume.
    private func syncClock(_ isRunning: Bool) {
        if isRunning {
            if resumedAt == nil { resumedAt = Date() }
        } else {
            if let resumedAt { accrued += max(0, Date().timeIntervalSince(resumedAt)) }
            resumedAt = nil
        }
    }

    var body: some View {
        let geo = HeroGeo(available: measuredWidth > 0 ? measuredWidth : fallbackWidth)
        let ink = HeroInk.resolve(dark: colorScheme == .dark)
        let rtl = layoutDirection == .rightToLeft

        return Button {
            NotificationCenter.default.post(name: .droobSwitchToTab, object: AppTab.ai)
        } label: {
            card(geo: geo, ink: ink, rtl: rtl)
        }
        // Reduced motion drops the press scale but keeps the opacity change,
        // so the card still acknowledges the tap.
        .buttonStyle(PressableButtonStyle(pressedScale: reduceMotion ? 1.0 : 0.985))
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if abs(width - measuredWidth) > 0.5 { measuredWidth = width }
        }
        .onScrollVisibilityChange(threshold: 0.10) { visible in
            if visible != onScreen { onScreen = visible }
        }
        .onChange(of: running, initial: true) { _, isRunning in syncClock(isRunning) }
        .onChange(of: isArabic) { _, _ in copy = HeroCopy.build() }
        // ONE element, ONE label, built from the COMPLETED copy for all four
        // phrases — so what a screen-reader user hears is a superset of what a
        // sighted user sees over 12 seconds, never a fragment.
        //
        // A `Button` is already a single merged accessibility element, and
        // `.accessibilityLabel` replaces the label SwiftUI would otherwise
        // derive by concatenating the eyebrow / headline / CTA. Deliberately
        // NOT `.accessibilityElement(children: .ignore)` here: that builds a
        // *new* element around the button and takes its activation with it, so
        // VoiceOver would announce the card and then do nothing on double-tap.
        // The streaming line and the caret are hidden at source instead.
        .accessibilityLabel(copy.a11y)
        .accessibilityHint(copy.a11yHint)
        .accessibilityAddTraits(.isButton)
    }

    /// ONE clock, two consumers — and everything that does not move stays out
    /// of both of them.
    ///
    /// The card's chrome (gradient fill, 1 pt border, drop shadow) and every
    /// static word on it are built HERE, once per layout. Only the `Canvas` and
    /// the single typed row live inside a `TimelineView`. That split is not
    /// cosmetic: with the shadow inside the timeline, its source alpha is
    /// invalidated by the redrawn `Canvas` on every frame, so Core Animation
    /// cannot reuse the cached blur and re-rasterises the whole ~358×150 pt
    /// card offscreen 30×/s — continuously, and again on the render path during
    /// a Home scroll.
    ///
    /// The shadow is cast by the opaque fill alone and deliberately sits
    /// OUTSIDE the clip, which is what keeps it visible.
    private func card(geo: HeroGeo, ink: HeroInk, rtl: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: geo.radius, style: .continuous)
        // ~30 CGPath-backed objects and the rule colour ramp: built once here,
        // captured by the Canvas closure, never rebuilt per frame.
        let art = HeroArt(g: geo, ink: ink, rtl: rtl)

        return ZStack {
            shape
                .fill(LinearGradient(colors: [ink.cardTop, ink.cardBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: ink.shadow, radius: ink.shadowRadius, x: 0, y: ink.shadowY)

            ZStack {
                // All four motions, one draw pass. `paused` stops SwiftUI
                // issuing updates entirely and leaves the last frame on screen;
                // 30 Hz because nothing here moves fast enough to need 60, and
                // it halves the cost on a cheap phone. Pinned to LTR so the
                // artwork's mirroring is decided by `rtl` alone (see §D.4) — a
                // framework flip would mirror the maths glyphs too.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !running)) { context in
                    let t = elapsed(at: context.date)
                    Canvas(opaque: false, rendersAsynchronously: false) { ctx, _ in
                        heroDraw(&ctx, t: t, ink: ink, art: art, reduced: reduceMotion)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
                .allowsHitTesting(false)

                // Leading text column + a reserved gap for the artwork panel.
                // The HStack mirrors with layout direction, so in Arabic the
                // text sits on the right and the sheets on the left, with no
                // manual flipping.
                HStack(alignment: .center, spacing: geo.gap) {
                    textColumn(geo: geo, ink: ink)
                    Color.clear.frame(width: geo.panelW)
                }
                .frame(width: geo.groupW)   // centred by the ZStack; see HeroGeo.sideInset
                .padding(.vertical, geo.padV)
            }
            .frame(width: geo.cardW, height: geo.cardH)
            .clipShape(shape)
        }
        .frame(width: geo.cardW, height: geo.cardH)
        .overlay(shape.strokeBorder(ink.border, lineWidth: 1))
    }

    /// Fixed row heights, so the card never reflows as the typed string grows.
    /// 22 + 8 + 24 + 6 + 19 + 17 + 18 = 114 = cardH − 2 × padV.
    private func textColumn(geo: HeroGeo, ink: HeroInk) -> some View {
        let s = geo.s
        let ts = geo.ts
        return VStack(alignment: .leading, spacing: 0) {
            eyebrow(geo: geo, ink: ink)
                .frame(height: 22 * s, alignment: .leading)
            Color.clear.frame(height: 8 * s)

            Text(copy.title)
                .font(heroFont(size: 18.5 * ts, weight: .semibold, isArabic: isArabic))
                .foregroundColor(ink.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(height: 24 * s, alignment: .leading)
            Color.clear.frame(height: 6 * s)

            streamRow(geo: geo, ink: ink)
            Color.clear.frame(height: 17 * s)

            HStack(spacing: 6 * s) {
                Text(copy.cta)
                    .font(heroFont(size: 12.5 * ts, weight: .semibold, isArabic: isArabic))
                    .lineLimit(1)
                Image(systemName: "chevron.forward")   // auto-mirrors in RTL
                    .font(.system(size: 10 * ts, weight: .semibold))
            }
            .foregroundColor(ink.ctaInk)
            .frame(height: 18 * s, alignment: .leading)
        }
        .frame(width: geo.textW, alignment: .leading)
    }

    /// The ONLY text on the card that moves, and the only one inside a
    /// timeline. The eyebrow chip, the headline and the CTA row never change,
    /// so they stay in `textColumn` and are diffed once, not thirty times a
    /// second. Both timelines read the same paused clock through
    /// `elapsed(at:)`, so they cannot drift apart.
    ///
    /// `HeroTypedLine` is `.equatable()`, so even in here the text subtree is
    /// skipped on the ~28 frames in 30 where neither the string nor the caret
    /// changed.
    private func streamRow(geo: HeroGeo, ink: HeroInk) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !running)) { context in
            let frame = TypeMachine.stateAt(elapsed(at: context.date) * 1000,
                                            copy: copy, reduced: reduceMotion)
            HeroTypedLine(text: frame.text,
                          caretOn: frame.caretOn,
                          showCaret: !reduceMotion,
                          s: geo.s, ts: geo.ts,
                          isArabic: isArabic,
                          dark: colorScheme == .dark,
                          ink: ink.streamInk,
                          caretInk: ink.caret)
                .equatable()
        }
        // 19 pt was measured against Latin. Arabic sits taller at the same
        // point size — the descenders on ج/ح/ع alone — so a hard clip took the
        // bottoms off the rotating phrases. The extra 3 pt is inside the 210 pt
        // column budget and costs nothing in English.
        .frame(height: 22 * geo.s, alignment: .leading)
        .clipped()
    }

    private func eyebrow(geo: HeroGeo, ink: HeroInk) -> some View {
        HStack(spacing: 5 * geo.s) {
            Image(systemName: "sparkles")
                .font(.system(size: 11 * geo.ts, weight: .semibold))
            Text(copy.eyebrow)
                .font(heroFont(size: 10.5 * geo.ts, weight: .bold, isArabic: isArabic))
                // Arabic is never letter-spaced — kashida-shaped letters break
                // visually when tracked apart.
                .tracking(isArabic ? 0 : 0.6)
                .lineLimit(1)
        }
        .foregroundColor(ink.chipInk)
        .padding(.horizontal, 8 * geo.s)
        .padding(.vertical, 4 * geo.s)
        .background(
            RoundedRectangle(cornerRadius: 8 * geo.s, style: .continuous)
                .fill(ink.chipBg)
        )
    }
}
