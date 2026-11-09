import SwiftUI
import UserNotifications

// MARK: - My Courses

struct MyCoursesView: View {
    @StateObject private var viewModel: MyCoursesViewModel
    @Environment(\.appLocale) private var locale
    @State private var selectedFilter: CourseFilter = .all

    init(viewModelOverride: MyCoursesViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModelOverride ?? MyCoursesViewModel())
    }

    enum CourseFilter: String, CaseIterable {
        case all
        case inProgress
        case completed

        func label(count: Int) -> String {
            switch self {
            case .all:        return "\(L10n.myCoursesFilterAll) (\(count))"
            case .inProgress: return L10n.myCoursesFilterInProgress
            case .completed:  return L10n.myCoursesFilterCompleted
            }
        }
    }

    private var filteredCourses: [EnrolledCourse] {
        switch selectedFilter {
        case .all:        return viewModel.enrollments
        case .inProgress: return viewModel.enrollments.filter { $0.isInProgress }
        case .completed:  return viewModel.enrollments.filter { $0.isCompleted }
        }
    }

    private var enrolledCount: Int { viewModel.enrollments.count }
    private var completedCount: Int { viewModel.enrollments.filter { $0.isCompleted }.count }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    titleBlock

                    filterRow

                    if viewModel.isLoading {
                        MyCoursesSkeletonList()
                    } else if let error = viewModel.errorMessage, viewModel.enrollments.isEmpty {
                        ErrorBanner(message: error) {
                            Task { await viewModel.load() }
                        }
                        .padding(.top, 32)
                    } else if viewModel.enrollments.isEmpty {
                        emptyState
                    } else if filteredCourses.isEmpty {
                        filterEmptyState
                    } else {
                        coursesList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    // MARK: Title Block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text(L10n.myCoursesTitleMy + " ")
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(.primary)
            + Text(L10n.myCoursesTitleCourses)
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(MyCoursesPalette.accent))

            Text(bidiJoin("\(enrolledCount) \(L10n.myCoursesEnrolled)",
                          "\(completedCount) \(L10n.myCoursesCompletedShort)",
                          separator: " · "))
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Filter Row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CourseFilter.allCases, id: \.self) { filter in
                    DroobFilterChip(
                        label: filter.label(count: enrolledCount),
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
        }
    }

    // MARK: Lists

    private var coursesList: some View {
        LazyVStack(spacing: 16) {
            ForEach(filteredCourses) { course in
                NavigationLink {
                    CourseDetailView(courseId: course.id)
                } label: {
                    EnrolledCourseCard(course: course, locale: locale)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 36))
                .foregroundColor(MyCoursesPalette.muted)
            Text(L10n.noEnrollments)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            Text(L10n.myCoursesEmptySubtitle)
                .font(.droobCaption)
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var filterEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(MyCoursesPalette.muted)
            Text(L10n.myCoursesFilterEmpty)
                .font(.droobSubheadline)
                .foregroundColor(MyCoursesPalette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}

// MARK: - Palette (adaptive — flips between light + dark via UIColor.dynamicProvider)
//
// Every token below resolves at render time off the active
// `UITraitCollection.userInterfaceStyle`. The trait collection follows
// `.preferredColorScheme(...)` which `DroobStudentApp` toggles from the
// `appColorScheme` AppStorage flag — so flipping the Light/Dark pill
// re-renders the whole UI without any view code reading the flag itself.
//
// Dark values are the originals; light values come from the figma's
// design tokens (`color/orange/*`, `color/grey/*`, `color/black/solid`,
// `color/red/47`, with `#5A5248` as the warm secondary text).

enum MyCoursesPalette {
    /// App background — pure white in light mode, near-black in dark.
    static let background = adaptive(
        light: UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1),
        dark:  UIColor(red: 0.040, green: 0.040, blue: 0.045, alpha: 1))

    /// Card / row / pill background. `color/orange/90` (#EDE7DC) in light.
    static let surface = Color(uiColor: surfaceUIColor)

    /// `surface` as a raw `UIColor`, for the few UIKit-backed views that need
    /// a concrete colour rather than a SwiftUI `Color` — the KaTeX web view
    /// paints its own background from one. Exposed (rather than re-typed by
    /// hand at the call site) so those surfaces can't drift from the palette.
    static let surfaceUIColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.090, green: 0.085, blue: 0.075, alpha: 1)
            : UIColor(red: 0.929, green: 0.906, blue: 0.863, alpha: 1)  // #EDE7DC
    }

    /// Slightly more saturated cream for stat tiles, code field bg, etc.
    /// `color/orange/85` (#E8DDCA) in light.
    static let surfaceRaised = adaptive(
        light: UIColor(red: 0.910, green: 0.867, blue: 0.792, alpha: 1),  // #E8DDCA
        dark:  UIColor(red: 0.115, green: 0.105, blue: 0.090, alpha: 1))

    /// Card / divider stroke. `color/grey/64` (#A8A49F) at low alpha for
    /// the soft 1pt borders the figma uses in light mode.
    static let stroke = adaptive(
        light: UIColor(red: 0.659, green: 0.643, blue: 0.624, alpha: 0.30),
        dark:  UIColor(white: 1.0, alpha: 0.06))

    /// Secondary / muted text. `#5A5248` (warm grey) in light mode —
    /// matches the figma "Lesson 3.3 — Motion principles" copy weight.
    static let muted = adaptive(
        light: UIColor(red: 0.353, green: 0.322, blue: 0.282, alpha: 1),  // #5A5248
        dark:  UIColor(red: 0.60, green: 0.58, blue: 0.55, alpha: 1))

    /// Primary text. `color/black/solid` (#0C0906) in light, white in dark.
    static let textPrimary = adaptive(
        light: UIColor(red: 0.047, green: 0.035, blue: 0.024, alpha: 1),  // #0C0906
        dark:  UIColor.white)

    /// Tertiary text — timestamps, placeholders, chevrons, counters.
    ///
    /// The light value was `color/grey/64` (#A8A49F) straight from the Figma
    /// dark-mode spec, which measures 2.5:1 on white and 2.0:1 on `surface` —
    /// roughly half the 4.5:1 floor, so every timestamp and placeholder was
    /// unreadable in light mode. #6E675A is the same warm grey family darkened
    /// to 5.6:1 / 4.6:1, still clearly lighter than `muted` (7.7:1 / 6.2:1) so
    /// the three-step text hierarchy survives.
    static let textTertiary = adaptive(
        light: UIColor(red: 0.431, green: 0.404, blue: 0.353, alpha: 1),  // #6E675A
        dark:  UIColor(red: 0.60, green: 0.58, blue: 0.55, alpha: 1))

    /// Danger / error text. `color/red/47` (#C03030) in light.
    static let danger = adaptive(
        light: UIColor(red: 0.753, green: 0.188, blue: 0.188, alpha: 1),  // #C03030
        dark:  UIColor(red: 0.95, green: 0.40, blue: 0.40, alpha: 1))

    /// Light pink banner background for the inline error banner.
    static let dangerSubtle = adaptive(
        light: UIColor(red: 0.988, green: 0.906, blue: 0.906, alpha: 1),  // #FCE7E7
        dark:  UIColor(red: 0.20, green: 0.05, blue: 0.05, alpha: 1))

    /// Success — same green in both modes (`#2BB66D`).
    static let success = Color(red: 0.169, green: 0.714, blue: 0.427)

    /// Brand gold **as a foreground** — text, icons, and hairlines drawn on a
    /// page or card surface.
    ///
    /// `Color.droobGold` (#C6A96B) is a dark-mode value: it was picked to read
    /// on near-black. On the light `surface` (#EDE7DC) it lands at roughly
    /// 1.8:1, far under the 4.5:1 floor, so every gold label that used to sit on
    /// a dark card became unreadable the moment light mode was switched on. Use
    /// this instead wherever gold is the *ink*; keep `.droobGold` where gold is
    /// the *fill* (CTA backgrounds, badges, gradients), since those keep their
    /// own dark foreground.
    ///
    /// The light value is the darkened gold ramp the instructor web already uses
    /// for exactly this job (`--accent-dark`, #7A5D2C), so the two surfaces stay
    /// visually related.
    static let accent = adaptive(
        light: UIColor(red: 0.478, green: 0.365, blue: 0.173, alpha: 1),  // #7A5D2C
        dark:  UIColor(red: 0.776, green: 0.663, blue: 0.420, alpha: 1))  // #C6A96B

    /// A surface that must read as *raised above* `surface` — a text field
    /// inside a composer bar, a chip on a card. Distinct from `surfaceRaised`
    /// only in intent; kept separate so a future palette change can move one
    /// without flattening the other.
    static let surfaceNested = adaptive(
        light: UIColor(red: 1.000, green: 0.996, blue: 0.988, alpha: 1),  // near-white
        dark:  UIColor(red: 0.145, green: 0.137, blue: 0.125, alpha: 1))

    /// Helper that picks the right UIColor for the current trait.
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - Header Pill

struct HeaderPillToggle: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(MyCoursesPalette.muted)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().stroke(MyCoursesPalette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Chip

struct DroobFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                // Gold here is ink + hairline on the page background, not a
                // fill — the chip's own wash is only 12%, so it never carries
                // its own dark plate.
                .foregroundColor(isSelected ? MyCoursesPalette.accent : MyCoursesPalette.muted)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? MyCoursesPalette.accent.opacity(0.12) : Color.clear)
                )
                .overlay(
                    Capsule().stroke(
                        isSelected ? MyCoursesPalette.accent.opacity(0.5) : MyCoursesPalette.stroke,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Enrolled Course Card

struct EnrolledCourseCard: View {
    let course: EnrolledCourse
    let locale: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover band with status badge overlay
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url = course.coverUrl.flatMap(URL.init(string:)) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                ZStack {
                                    course.coverColor
                                    Image(systemName: course.coverSymbol).font(.system(size: 30))
                                        .foregroundColor(Color.droobGold.opacity(0.9))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                    } else {
                        ZStack {
                            course.coverColor
                            Image(systemName: course.coverSymbol).font(.system(size: 30))
                                .foregroundColor(Color.droobGold.opacity(0.9))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(height: 96)

                StatusBadge(course: course)
                    .padding(12)
            }
            .clipShape(RoundedCorners(radius: 16, corners: [.topLeft, .topRight]))

            VStack(alignment: .leading, spacing: 12) {
                Text(course.localizedTitle(locale: locale))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(bidiJoin(course.instructorName,
                              "\(course.lessonCount) \(L10n.lessonsLowercase)",
                              separator: " · "))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)

                if course.isCompleted {
                    HStack(spacing: 6) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 11))
                        Text(L10n.myCoursesCompletedCertEarned)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(MyCoursesPalette.success)
                } else {
                    progressSection
                    continueButton
                }
            }
            .padding(16)
        }
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1)
        )
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MyCoursesPalette.stroke)
                        .frame(height: 4)
                    // The filled part of the track has to read *against* the
                    // card surface, so it takes the ink ramp rather than the
                    // fill gold (which is invisible on the light card).
                    Capsule()
                        .fill(MyCoursesPalette.accent)
                        .frame(width: max(0, geo.size.width * CGFloat(course.progressPct / 100)), height: 4)
                }
            }
            .frame(height: 4)

            Text("\(Int(course.progressPct))%")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MyCoursesPalette.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var continueButton: some View {
        HStack {
            Spacer()
            Text("\(L10n.myCoursesContinueLearning) →")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(LinearGradient.droobBrand)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.top, 4)
    }
}

private struct StatusBadge: View {
    let course: EnrolledCourse

    /// Neutral tint for the "not started" badge. Deliberately a fixed light
    /// grey rather than `MyCoursesPalette.muted`: the badge floats on the
    /// scrimmed cover art, which is dark in *both* themes (a photo, or the
    /// opaque dark `coverColor` placeholder), so the adaptive muted token
    /// would flip to near-black there and disappear in light mode.
    private static let neutralOnCover = Color(white: 0.86)

    var body: some View {
        if course.isCompleted {
            badge(text: "✓ \(L10n.myCoursesDone)", tint: MyCoursesPalette.success)
        } else if course.isInProgress {
            // Gold stays the dark-mode value here — see `neutralOnCover`.
            badge(text: L10n.myCoursesInProgressBadge, tint: Color.droobGold)
        } else {
            badge(text: L10n.myCoursesNotStarted, tint: Self.neutralOnCover)
        }
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // Opaque, not `black.opacity(0.4)`: the badge lands on arbitrary
            // cover art, and a 40% black over a bright photo composites to
            // mid-grey — which the tints above can't sit on. An opaque plate
            // gives every tint the dark backdrop it was picked for.
            .background(Color(red: 0.075, green: 0.070, blue: 0.060))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Skeleton

private struct MyCoursesSkeletonList: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    MCSkeletonBlock(height: 96, cornerRadius: 0)
                    VStack(alignment: .leading, spacing: 12) {
                        MCSkeletonBlock(height: 16, cornerRadius: 4, width: 220)
                        MCSkeletonBlock(height: 11, cornerRadius: 3, width: 140)
                        MCSkeletonBlock(height: 4, cornerRadius: 2)
                        MCSkeletonBlock(height: 38, cornerRadius: 19)
                    }
                    .padding(16)
                }
                .background(MyCoursesPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

struct MCSkeletonBlock: View {
    let height: CGFloat
    let cornerRadius: CGFloat
    var width: CGFloat? = nil
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            // Tinted off the adaptive tertiary so the pulse stays visible on
            // the cream light-mode surfaces as well as the dark ones.
            .fill(MyCoursesPalette.textTertiary.opacity(pulse ? 0.18 : 0.10))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : width)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Rounded Corners helper

struct RoundedCorners: Shape {
    var radius: CGFloat = 16
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Sessions Models

struct StudentSession: Decodable, Identifiable {
    let id: String
    let titleEn: String
    let titleAr: String
    let descriptionEn: String?
    let descriptionAr: String?
    let startsAt: Date
    let durationMinutes: Int?
    let platform: String
    let joinUrl: String?
    let status: String
    let instructorName: String

    enum CodingKeys: String, CodingKey {
        case id
        case titleEn = "title_en"
        case titleAr = "title_ar"
        case descriptionEn = "description_en"
        case descriptionAr = "description_ar"
        case startsAt = "starts_at"
        case durationMinutes = "duration_minutes"
        case platform
        case joinUrl = "join_url"
        case status
        case instructorName = "instructor_name"
    }

    var isLive: Bool { status == "LIVE" }

    /// Localized duration label, or nil when the backend omitted a duration.
    /// Rolls minutes into hours: "45 min", "1 hr", "5 hr 3 min".
    var durationLabel: String? {
        guard let total = durationMinutes, total > 0 else { return nil }
        let hours = total / 60
        let minutes = total % 60
        switch (hours, minutes) {
        case (0, _):
            return String(format: L10n.sessionsDurationMinFmt, minutes)
        case (_, 0):
            return String(format: L10n.sessionsDurationHrFmt, hours)
        default:
            return String(format: L10n.sessionsDurationHrMinFmt, hours, minutes)
        }
    }

    /// True once the scheduled start time has been reached. The backend only
    /// flips `status` to "LIVE" when the instructor actually starts the call,
    /// which can lag the scheduled time — so a row treats "start time reached"
    /// as join-ready on its own and swaps Remind for Join.
    func hasStarted(from now: Date = Date()) -> Bool { now >= startsAt }

    /// How long before the scheduled start the Join action opens, on both Home
    /// and the Sessions tab. Before this window a row shows "Remind"; from this
    /// window on it shows "Join". Matches the approved cross-platform flow.
    static let joinWindow: TimeInterval = 15 * 60

    /// The instant the Join action opens — `joinWindow` before the start.
    var joinOpensAt: Date { startsAt.addingTimeInterval(-StudentSession.joinWindow) }

    /// Whether Join is available at `now`: the backend already flipped the
    /// session to LIVE, or now has reached the join window (15 min before start).
    func canJoin(from now: Date = Date()) -> Bool { isLive || now >= joinOpensAt }

    /// Derived end instant (`startsAt + durationMinutes`), or nil when the
    /// backend omitted a usable duration. A started session with no known end is
    /// treated as open-ended (stays live until the next fetch drops it).
    var endsAt: Date? {
        guard let total = durationMinutes, total > 0 else { return nil }
        return startsAt.addingTimeInterval(TimeInterval(total * 60))
    }

    /// Whether the Sessions tab should surface this in its dedicated Live section
    /// at `now`: the backend marked it LIVE, or its scheduled start has arrived
    /// and it hasn't run past `endsAt` (open-ended when the duration is unknown).
    func isLiveNow(from now: Date = Date()) -> Bool {
        if isLive { return true }
        guard now >= startsAt else { return false }
        guard let end = endsAt else { return true }
        return now < end
    }

    /// Whether the session has run past its end at `now` (and the backend isn't
    /// still flagging it LIVE) — the Sessions tab drops it without a reload.
    /// Sessions with no known duration never auto-end here.
    func hasEnded(from now: Date = Date()) -> Bool {
        if isLive { return false }
        guard let end = endsAt else { return false }
        return now >= end
    }

    /// How long a session lingers in Home's "Next Session" slot after its
    /// scheduled start, so a student who's a few minutes late can still join
    /// from Home. Once it elapses the session is treated as in-progress and
    /// drops off Home (the Sessions tab keeps it until it ends).
    static let homeGraceWindow: TimeInterval = 10 * 60

    /// The instant this session should drop out of Home's "Next Session" slot.
    var homeExpiry: Date { startsAt.addingTimeInterval(StudentSession.homeGraceWindow) }

    /// Picks the session to feature in Home's "Next Session" slot from a list
    /// ordered by start time ascending (as the backend returns it). Keeps a
    /// session that started within the last `homeGraceWindow` — so one that
    /// just began still shows as the next session (now joinable) — and drops
    /// anything older, which is in-progress and surfaces on the Sessions tab.
    static func nextForHome(
        from sessions: [StudentSession],
        now: Date = Date()
    ) -> StudentSession? {
        let cutoff = now.addingTimeInterval(-homeGraceWindow)
        return sessions.first { $0.startsAt > cutoff }
    }
}

@MainActor
final class SessionsViewModel: ObservableObject {
    @Published var sessions: [StudentSession] = []
    @Published var isLoading = true
    @Published var error: String? = nil
    private var inflight = false

    func load() async {
        if inflight { NSLog("[Sessions] load() skipped — already in flight"); return }
        inflight = true
        defer { inflight = false }

        NSLog("[Sessions] load() start")
        let hadData = !sessions.isEmpty
        if !hadData { isLoading = true }
        error = nil
        do {
            let items: [StudentSession] = try await AuthInterceptor.shared.execute(
                APIRequest(path: "/v1/student/sessions")
            )
            sessions = items
            NSLog("[Sessions] load() ok, count=\(items.count)")
            await SessionReminderScheduler.reconcile(sessions: items)
        } catch let e where APIClient.isCancellationError(e) {
            // Pull-to-refresh cancelled mid-flight; ignore.
            if isLoading { isLoading = false }
            return
        } catch let e as DroobError {
            if case .unauthenticated(_, _) = e {
                AuthSession.shared.handleUnauthenticated()
            } else {
                error = e.errorDescription
            }
            NSLog("[Sessions] load() droobError=\(String(describing: e))")
        } catch {
            self.error = error.localizedDescription
            NSLog("[Sessions] load() error=\(error.localizedDescription)")
        }
        if isLoading { isLoading = false }
    }
}

// MARK: - Sessions View

struct SessionsView: View {
    @StateObject private var viewModel = SessionsViewModel()
    @Environment(\.appLocale) private var locale

    /// Ticks so the live/upcoming split and each row's Remind→Join flip advance
    /// without a reload as sessions cross their join window, start, and end.
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleBlock.padding(.top, 8)
                    Group {
                        if viewModel.isLoading {
                            sessionsSkeleton
                        } else if let err = viewModel.error {
                            ErrorBanner(message: err) { Task { await viewModel.load() } }
                                .padding(.top, 32)
                        } else {
                            let live = viewModel.sessions.filter { $0.isLiveNow(from: now) }
                            let upcoming = viewModel.sessions.filter {
                                !$0.isLiveNow(from: now) && !$0.hasEnded(from: now)
                            }
                            if live.isEmpty && upcoming.isEmpty {
                                emptyState
                            } else {
                                sessionsContent(live: live, upcoming: upcoming)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .animation(nil, value: viewModel.isLoading)
                .animation(nil, value: viewModel.sessions.count)
            }
            .droobBounceBasedOnSize()
            .scrollIndicators(.hidden)
            .transaction { $0.animation = nil }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onReceive(clock) { now = $0 }
    }

    // MARK: Title

    /// Just "Sessions" in gold serif italic per the new Figma — the previous
    /// two-tone "Live Sessions" treatment was retired with the week-strip.
    private var titleBlock: some View {
        Text(L10n.sessionsTitle)
            .font(.system(size: 36, weight: .bold))
            .foregroundColor(MyCoursesPalette.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Sessions content (live now + upcoming)

    @ViewBuilder
    private func sessionsContent(live: [StudentSession], upcoming: [StudentSession]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(live) { session in
                LiveNowCard(session: session, locale: locale)
            }

            if !upcoming.isEmpty {
                Text(L10n.sessionsUpcomingHeader)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(MyCoursesPalette.muted)

                VStack(spacing: 0) {
                    ForEach(Array(upcoming.enumerated()), id: \.element.id) { idx, session in
                        UpcomingSessionRow(session: session, locale: locale, now: now)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                        if idx < upcoming.count - 1 {
                            Divider()
                                .background(MyCoursesPalette.stroke)
                                .padding(.leading, 14)
                        }
                    }
                }
                .background(MyCoursesPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1)
                )
            }
        }
        .transaction { $0.animation = nil }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(MyCoursesPalette.surface)
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(MyCoursesPalette.stroke, lineWidth: 1))
                Image(systemName: "video.badge.checkmark")
                    .font(.system(size: 34))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            VStack(spacing: 8) {
                Text(L10n.sessionsEmptyTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(L10n.sessionsEmptySubtitle)
                    .font(.system(size: 14))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: Skeleton

    private var sessionsSkeleton: some View {
        VStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in MCSkeletonBlock(height: 130, cornerRadius: 16) }
        }
    }
}

// MARK: - Live now card
//
// Pinned at the top of the Sessions screen when one of the upcoming entries
// is currently live. Green dot + title + instructor + gold "Join" pill.
// Tapping Join opens the platform URL in Safari via `Link`.

private struct LiveNowCard: View {
    let session: StudentSession
    let locale: String

    private var title: String { L10n.localized(locale, ar: session.titleAr, en: session.titleEn) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(MyCoursesPalette.success)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(MyCoursesPalette.success.opacity(0.35), lineWidth: 6)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(1)
                Text(session.instructorName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            SessionJoinPill(joinUrl: session.joinUrl)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1)
        )
    }

}

// MARK: - Shared join pill
//
// Gold "Join" pill shared by the live-now card and by upcoming rows whose
// start time has been reached. Opens the platform URL; renders dimmed and
// inert when the backend hasn't supplied a join_url yet.
struct SessionJoinPill: View {
    let joinUrl: String?

    var body: some View {
        if let raw = joinUrl, let url = URL(string: raw) {
            Link(destination: url) { label }
        } else {
            // Defensive — show a non-tappable pill so the layout still
            // matches the Figma when join_url is missing.
            label.opacity(0.5)
        }
    }

    private var label: some View {
        Text(L10n.sessionsJoin)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(LinearGradient.droobBrand)
            .clipShape(Capsule())
    }
}

// MARK: - Upcoming session row
//
// Compact row used inside the "UPCOMING" card. Date chip on the left,
// title + instructor·duration + time in the middle, outlined Remind pill
// on the right that toggles a local notification via SessionReminderScheduler.

private struct UpcomingSessionRow: View {
    let session: StudentSession
    let locale: String
    /// Wall clock ticked by the parent (`SessionsView`), so the row flips
    /// Remind→Join at its join window without its own timer and stays in step
    /// with the parent's live/upcoming split.
    let now: Date

    @State private var reminderOn: Bool = false
    @State private var reminderError: String? = nil

    private var title: String { L10n.localized(locale, ar: session.titleAr, en: session.titleEn) }
    private var reminderId: String { SessionReminderScheduler.reminderId(for: session.id) }

    /// Once the session is live or its join window (15 min before start) has been
    /// reached, the row offers "Join" instead of "Remind".
    private var canJoin: Bool { session.canJoin(from: now) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            dateChip

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(2)

                // The instructor name truncates, but the duration is pinned
                // (fixedSize + higher layout priority) so a long instructor
                // name can never push the duration out of view.
                HStack(spacing: 4) {
                    Text(session.instructorName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let duration = session.durationLabel {
                        Text(verbatim: "·")
                            .fixedSize()
                        Text(duration)
                            .fixedSize()
                            .layoutPriority(1)
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(MyCoursesPalette.muted)

                Text(session.startsAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: L10n.currentLanguageCode))))
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.muted)

                if let err = reminderError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }

            Spacer(minLength: 6)

            if canJoin {
                SessionJoinPill(joinUrl: session.joinUrl)
            } else {
                remindButton
            }
        }
        .task { reminderOn = await SessionReminderScheduler.isScheduled(id: reminderId) }
    }

    /// Two-line date chip: month over a large day.
    ///
    /// Locale-pinned like the Home chip — these followed the device. The
    /// `.uppercased()` went with it: it is meaningless for Arabic month names.
    private var dateChip: some View {
        VStack(spacing: 0) {
            Text(session.startsAt.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: L10n.currentLanguageCode))))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(MyCoursesPalette.muted)
            Text(session.startsAt.formatted(.dateTime.day().locale(Locale(identifier: L10n.currentLanguageCode))))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)
        }
        .frame(width: 56, height: 56)
        .background(MyCoursesPalette.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1)
        )
    }

    private var remindButton: some View {
        Button {
            Task { await toggleReminder() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: reminderOn ? "bell.fill" : "bell")
                    .font(.system(size: 11, weight: .semibold))
                Text(L10n.sessionsRemind)
                    .font(.system(size: 13, weight: .semibold))
            }
            // Armed state is gold ink + gold hairline on the card surface, so
            // it takes the ink ramp; the 12% wash is not a plate.
            .foregroundColor(reminderOn ? MyCoursesPalette.accent : MyCoursesPalette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(reminderOn ? MyCoursesPalette.accent.opacity(0.12) : Color.clear)
            )
            .overlay(
                Capsule().stroke(
                    reminderOn ? MyCoursesPalette.accent.opacity(0.6) : MyCoursesPalette.stroke,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleReminder() async {
        reminderError = nil
        if reminderOn {
            await SessionReminderScheduler.cancel(id: reminderId)
            reminderOn = false
            return
        }
        do {
            try await SessionReminderScheduler.schedule(
                id: reminderId,
                title: title,
                startsAt: session.startsAt
            )
            reminderOn = true
        } catch SessionReminderScheduler.ReminderError.permissionDenied {
            reminderError = L10n.sessionsRemindPermissionDenied
        } catch SessionReminderScheduler.ReminderError.startsInPast {
            reminderError = L10n.sessionsRemindTooClose
        } catch {
            reminderError = L10n.sessionsRemindGenericError
        }
    }
}

// MARK: - Session reminder scheduling

enum SessionReminderScheduler {
    enum ReminderError: Error {
        case permissionDenied
        case startsInPast
    }

    static let idPrefix = "session-reminder-"

    /// How long before the scheduled start the reminder fires. Matches Android.
    static let lead: TimeInterval = 5 * 60

    static func reminderId(for sessionId: String) -> String { idPrefix + sessionId }

    static func isScheduled(id: String) async -> Bool {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.contains { $0.identifier == id }
    }

    static func schedule(id: String, title: String, startsAt: Date) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let granted: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            granted = true
        case .denied:
            granted = false
        case .notDetermined:
            granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            granted = false
        }
        guard granted else { throw ReminderError.permissionDenied }

        let fireDate = startsAt.addingTimeInterval(-lead)
        guard fireDate > Date() else { throw ReminderError.startsInPast }

        let content = UNMutableNotificationContent()
        content.title = L10n.pushLiveSessionTitle
        content.body = L10n.pushLiveSessionBody(title)
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await center.add(request)
    }

    static func cancel(id: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Reconciles pending session reminders against the freshly fetched sessions.
    /// Drops any reminder whose session is no longer in the student's upcoming
    /// list (a cancelled or deleted session simply disappears from
    /// `/v1/student/sessions`), and moves a reminder whose session was
    /// rescheduled so it fires `lead` before the *new* start — or drops it when
    /// the new fire time has already passed.
    static func reconcile(sessions: [StudentSession]) async {
        let active = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let locale = L10n.currentLanguageCode
        let center = UNUserNotificationCenter.current()
        for request in await center.pendingNotificationRequests()
        where request.identifier.hasPrefix(idPrefix) {
            let sessionId = String(request.identifier.dropFirst(idPrefix.count))
            guard let session = active[sessionId] else {
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                continue
            }
            // The armed trigger keeps minute-precision calendar components;
            // compare against the expected fire time at the same precision to
            // spot a reschedule.
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let armedFire = Calendar.current.date(from: trigger.dateComponents)
            else { continue }
            let expectedFire = session.startsAt.addingTimeInterval(-lead)
            if abs(armedFire.timeIntervalSince(expectedFire)) < 60 { continue }
            center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
            // Re-arm at the new time. schedule refuses a fire time already in
            // the past — the right outcome for a session moved to (near-)now.
            try? await schedule(
                id: request.identifier,
                title: L10n.localized(locale, ar: session.titleAr, en: session.titleEn),
                startsAt: session.startsAt
            )
        }
    }
}

// MessagesView is defined in Features/Messages/MessagesView.swift
