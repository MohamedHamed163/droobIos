import SwiftUI
import Combine

struct RootView: View {
    @EnvironmentObject private var authSession: AuthSession
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @State private var splashActive = true
    /// Universal-Link landing state lives here at the root rather than
    /// on `MainTabView` so the cover can present over the splash, auth,
    /// or main flow alike. When the user is signed out at link-tap
    /// time, we defer the join until auth becomes `.authenticated`.
    ///
    /// Bound through `fullScreenCover(item:)` so the cover *only*
    /// presents when there's a real room to show — previously a
    /// separate `showLinkedRoomCover` flag could be flipped while
    /// `linkedRoom` was still nil, producing an empty (black) cover.
    @State private var linkedRoomItem: LinkedRoomItem? = nil
    /// Inline toast for join errors that don't warrant a full cover —
    /// "you must be enrolled" gets surfaced this way after we
    /// transparently route the user into the course detail screen.
    @State private var linkedRoomToast: String? = nil
    @State private var pendingResolveSlug: String? = nil

    // Push-notification chat targets presented as covers. `deferredChatTarget`
    // holds a target that arrived before the session was authenticated (cold
    // launch / tap while signed out) until `state` becomes `.authenticated`.
    @State private var pushRoomItem: RoomIdItem? = nil
    @State private var pushThreadItem: ThreadChatItem? = nil
    @State private var deferredChatTarget: AuthSession.ChatTarget? = nil

    /// Identifiable wrapper so `fullScreenCover(item:)` has a stable
    /// handle for the joined-room payload.
    struct LinkedRoomItem: Identifiable, Hashable {
        let id: String
        let room: StudyRoomDetail
        init(room: StudyRoomDetail) {
            self.id = room.roomId
            self.room = room
        }
    }

    /// Study-room chat opened by id from a tapped push (membership already
    /// exists, so no slug-join is needed).
    struct RoomIdItem: Identifiable, Hashable { let id: String }

    /// Direct/instructor chat opened from a tapped push. Carries the instructor
    /// identity resolved from the inbox so the chat can send replies.
    struct ThreadChatItem: Identifiable, Hashable {
        let id: String            // threadId
        let instructorId: String
        let instructorName: String
        let instructorAvatarUrl: String?
    }

    private static var previewMyCourses: Bool {
        ProcessInfo.processInfo.arguments.contains("-previewMyCourses")
    }
    private static var previewCourseDetail: Bool {
        ProcessInfo.processInfo.arguments.contains("-previewCourseDetail")
    }
    private static var previewWelcome: Bool {
        ProcessInfo.processInfo.arguments.contains("-previewWelcome")
    }
    private static var previewWelcomeBack: Bool {
        ProcessInfo.processInfo.arguments.contains("-previewWelcomeBack")
    }
    private static var previewChangePassword: Bool {
        ProcessInfo.processInfo.arguments.contains("-previewChangePassword")
    }
    /// AI hub, seeded (course picker). `-previewAiHubEmpty` renders the
    /// no-enrollments state instead.
    private static var previewAiHub: Bool {
        ProcessInfo.processInfo.arguments.contains("-previewAiHub")
    }
    private static var previewAiHubEmpty: Bool {
        ProcessInfo.processInfo.arguments.contains("-previewAiHubEmpty")
    }

    var body: some View {
        ZStack {
            // Destination loads underneath so it's ready when splash fades
            Group {
                if Self.previewMyCourses {
                    NavigationStack { MyCoursesPreviewHost() }
                } else if Self.previewCourseDetail {
                    NavigationStack { CourseDetailPreviewHost() }
                } else if Self.previewAiHub || Self.previewAiHubEmpty {
                    NavigationStack {
                        AiTutorHubPreviewHost()
                    }
                } else if Self.previewWelcome {
                    WelcomeAccountCreatedView(
                        displayName: "Nour Al-Rashid",
                        email: "nour@droob.co",
                        onMeetInstructors: {}
                    )
                } else if Self.previewWelcomeBack {
                    WelcomeBackView(
                        displayName: "Nour Al-Rashid",
                        email: "nour@droob.co",
                        onGoToDashboard: {},
                        onContinueLastCourse: { _ in }
                    )
                } else if Self.previewChangePassword {
                    NavigationStack {
                        ChangePasswordView(email: "nour@droob.co", otpCode: "123456")
                    }
                } else {
                    switch authSession.state {
                    case .loading:
                        Color(.systemBackground).ignoresSafeArea()
                    case .unauthenticated:
                        AuthNavigationView()
                    case .authenticated:
                        MainTabView()
                            .onReceive(authSession.$pendingDeepLinkCourseId.compactMap { $0 }) { _ in }
                    }
                }
            }

            // Splash always shown on launch; fades out after minimum time + auth resolved
            if splashActive {
                SplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        // KEPT — screenshot & screen-recording block (screen recording /
        // AirPlay / mirroring / external display).
        .captureProtected()
        // SECURITY LAYER DISABLED (2026-07-24): iPad full-screen-only guard
        // turned off per request. This dimmed the app ("seeing the app")
        // when shown in Split View / windowed on iPad. To re-enable,
        // uncomment. See FullScreenGuard.
        // .fullScreenOnlyOniPad()
        // SECURITY LAYER DISABLED (2026-07-24): jailbreak / device-integrity
        // block turned off per request. This blacked out the whole app on a
        // jailbroken device (release builds only). To re-enable, uncomment.
        // See DeviceIntegrity.
        // .overlay {
        //     #if !DEBUG
        //     if DeviceIntegrity.isCompromised {
        //         DeviceIntegrityBlockView().zIndex(20)
        //     }
        //     #endif
        // }
        .task {
            let minDeadline = Date().addingTimeInterval(3.5)

            // Wait until auth state resolves out of .loading
            while authSession.state == .loading {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms polls
            }

            // Honour the minimum splash duration
            let remaining = minDeadline.timeIntervalSinceNow
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }

            withAnimation(.easeInOut(duration: 0.5)) {
                splashActive = false
            }
        }
        // Universal-Link consumer at root level — fires regardless of
        // auth state. When the user is signed out we hold the slug in
        // `pendingResolveSlug` and replay once `state == .authenticated`.
        .onReceive(authSession.$pendingStudyRoomSlug.compactMap { $0 }) { slug in
            print("[DeepLink] RootView received slug=\(slug) authState=\(authSession.state)")
            authSession.pendingStudyRoomSlug = nil
            if case .authenticated = authSession.state {
                Task { await openLinkedRoom(slug: slug) }
            } else {
                pendingResolveSlug = slug
                print("[DeepLink] deferring slug until sign-in")
            }
        }
        // Re-check on auth state transitions — covers the deferred
        // case where the slug arrived pre-auth.
        .onReceive(authSession.$state) { state in
            if case .authenticated = state, let slug = pendingResolveSlug {
                pendingResolveSlug = nil
                print("[DeepLink] auth resolved — consuming deferred slug=\(slug)")
                Task { await openLinkedRoom(slug: slug) }
            }
        }
        // Push-notification tap → open the chat. Defer until authenticated so a
        // tap from the lock screen / cold launch lands in the chat once signed in.
        .onReceive(authSession.$pendingChatTarget.compactMap { $0 }) { target in
            authSession.pendingChatTarget = nil
            if case .authenticated = authSession.state {
                Task { await openChatTarget(target) }
            } else {
                deferredChatTarget = target
            }
        }
        .onReceive(authSession.$state) { state in
            if case .authenticated = state, let target = deferredChatTarget {
                deferredChatTarget = nil
                Task { await openChatTarget(target) }
            }
        }
        .fullScreenCover(item: $linkedRoomItem) { item in
            NavigationStack {
                StudyRoomChatView(
                    roomId: item.room.roomId,
                    prefetchedRoom: item.room)
            }
        }
        .fullScreenCover(item: $pushRoomItem) { item in
            NavigationStack { StudyRoomChatView(roomId: item.id) }
        }
        .fullScreenCover(item: $pushThreadItem) { item in
            NavigationStack {
                InstructorChatView(
                    instructorId: item.instructorId,
                    instructorName: item.instructorName,
                    instructorAvatarUrl: item.instructorAvatarUrl,
                    threadId: item.id)
            }
        }
        // Non-fatal join feedback (waitlist pending, enrollment
        // redirect, generic failures) shown as a transient banner over
        // whatever the user is on — much less disruptive than the
        // previous full-screen error cover.
        .overlay(alignment: .top) {
            if let msg = linkedRoomToast {
                linkedRoomToastBanner(message: msg)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: linkedRoomToast)
    }

    private func linkedRoomToastBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                // Gold as ink on the (light-mode cream) toast surface — the
                // raw #C6A96B glyph washes out to ~1.8:1 there.
                .foregroundColor(MyCoursesPalette.accent)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MyCoursesPalette.textPrimary)
                .lineLimit(3)
            Spacer(minLength: 0)
            Button { linkedRoomToast = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MyCoursesPalette.surface)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    // Hairline is ink too: gold-on-cream leaves the banner with
                    // no discernible edge against the page behind it.
                    .stroke(MyCoursesPalette.accent.opacity(0.4), lineWidth: 1)))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    /// Joins the room behind a Universal-Link slug. Resolves the slug
    /// first (publicly, no auth needed) so we know the parent course
    /// — that gives us a fallback target if the join fails because
    /// the viewer isn't enrolled. The cover is only presented once we
    /// have a concrete `StudyRoomDetail` to render, removing the
    /// "isPresented + nil content" window where the user used to see
    /// a black screen.
    private func openLinkedRoom(slug: String) async {
        print("[DeepLink] openLinkedRoom slug=\(slug) starting join…")

        // 1. Public slug resolution — gives us course_id even if the
        //    join itself is going to be rejected (e.g. not enrolled).
        let resolution = try? await StudyRoomsAPI.resolveSlug(slug)

        // 2. Attempt the join.
        do {
            let result = try await StudyRoomsAPI.joinBySlug(slug)
            if result.status == "JOINED", let detail = result.room {
                print("[DeepLink] joined ok — roomId=\(detail.roomId)")
                // Brief delay lets MainTabView fully mount in the
                // common "sign in → cover presents" flow. Presenting
                // a fullScreenCover while the underlying view is
                // still transitioning out of AuthNavigationView can
                // result in the cover rendering over an unstable
                // hierarchy, which is what produced the black-screen
                // reports.
                try? await Task.sleep(nanoseconds: 250_000_000)
                linkedRoomItem = LinkedRoomItem(room: detail)
            } else if result.status == "PENDING" {
                print("[DeepLink] private room — pending host approval")
                linkedRoomToast = L10n.studyRoomsLinkPendingHostApproval
                scheduleToastDismiss()
            }
        } catch DroobError.forbidden {
            // Enrollment guard — route the user into the course
            // detail screen so they can buy it / read the description
            // before trying to join the room again.
            print("[DeepLink] forbidden — not enrolled in course")
            if let courseId = resolution?.courseId {
                authSession.pendingDeepLinkCourseId = courseId
                linkedRoomToast = L10n.studyRoomsLinkEnrollmentRequired
            } else {
                linkedRoomToast = L10n.studyRoomsLinkEnrollmentRequired
            }
            scheduleToastDismiss()
        } catch {
            print("[DeepLink] join failed: \(error.localizedDescription)")
            linkedRoomToast = error.localizedDescription
            scheduleToastDismiss()
        }
    }

    /// Opens a chat from a tapped push notification and marks it read. Study
    /// rooms present directly by id (the user is already a member). Direct
    /// threads resolve the instructor identity from the inbox so the chat can
    /// load by-thread (which also resets the unread counter server-side).
    private func openChatTarget(_ target: AuthSession.ChatTarget) async {
        // Let MainTabView settle before presenting a cover (mirrors the
        // delay in `openLinkedRoom`, which avoids a black-screen present over
        // a still-transitioning hierarchy on the cold-launch path).
        try? await Task.sleep(nanoseconds: 250_000_000)
        switch target {
        case .studyRoom(let roomId):
            try? await StudyRoomsAPI.markRead(roomId: roomId)
            pushRoomItem = RoomIdItem(id: roomId)
        case .directThread(let threadId):
            let threads: [StudentThread]? = try? await AuthInterceptor.shared.execute(
                APIRequest(path: "/v1/student/messages/threads"))
            guard let t = threads?.first(where: { $0.threadId == threadId }) else { return }
            pushThreadItem = ThreadChatItem(
                id: threadId,
                instructorId: t.instructorId,
                instructorName: t.instructorName,
                instructorAvatarUrl: t.instructorAvatarUrl)
        }
    }

    private func scheduleToastDismiss() {
        Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            await MainActor.run { linkedRoomToast = nil }
        }
    }
}

// MARK: - Preview hosts (driven by launch args, used for design QA only)

private struct MyCoursesPreviewHost: View {
    var body: some View {
        // The launch arg keeps its historical name (`previewMyCourses`) so
        // fastlane / preview tooling doesn't have to change, but it now
        // boots the redesigned Courses tab with a seeded MyCoursesViewModel.
        let vm = MyCoursesViewModel.previewSeeded()
        return CoursesTabView(myCoursesOverride: vm, initialMode: .mine)
    }
}

/// Renders `AskDroobAIView` preview.
private struct AiTutorHubPreviewHost: View {
    var body: some View {
        AskDroobAIView()
    }
}

private struct CourseDetailPreviewHost: View {
    var body: some View {
        let vm = CourseDetailViewModel.previewSeeded()
        return CourseDetailView(courseId: vm.courseId, viewModelOverride: vm)
    }
}

// MARK: - Splash

struct SplashView: View {
    @State private var appeared = false
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    var body: some View {
        ZStack {
            OnboardingColors.bg.ignoresSafeArea()
            RadialGradient(
                colors: [OnboardingColors.goldDark.opacity(0.30), .clear],
                center: .center, startRadius: 0, endRadius: 280
            )
            .ignoresSafeArea()
            VStack(spacing: 20) {
                DroobLogoMark(size: 110)
                VStack(spacing: 8) {
                    Text(L10n.brandName)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.white)
                    Text(L10n.splashTagline)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(appLocale == "ar" ? 0 : 3)
                        .foregroundColor(OnboardingColors.gold)
                }
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.88)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65)) {
                appeared = true
            }
        }
    }
}

// MARK: - Auth Navigation

struct AuthNavigationView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        if hasSeenOnboarding {
            NavigationStack { LoginView() }
                // Server-free entry point to test the ViewerPresenceGuard
                // without logging in. Shown in Debug + TestFlight, hidden in
                // the public App Store build.
                .overlay(alignment: .bottom) {
                    if !CaptureProtectionEnvironment.isProduction {
                        PresenceTestLauncher().padding(.bottom, 6)
                    }
                }
        } else {
            OnboardingView { hasSeenOnboarding = true }
        }
    }
}

// MARK: - Onboarding container
//
// Three-slide intro that matches the Figma. A standalone brand slide
// (`OnboardingBrandSlide`, page 0) auto-advances after ~3.8s into the
// first content slide, then the user paginates through the remaining
// two with horizontal swipes / CTA taps. The CTA on the final slide
// calls `onFinish`, which flips `hasSeenOnboarding` and pushes the
// auth stack.

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var currentPage = 0

    /// Computed so L10n re-evaluates against the current `appLocale`
    /// every time the view body rebuilds.
    private var slides: [OnboardingSlide] {
        [
            OnboardingSlide(
                id: .myCourses,
                title: L10n.onbSlide1Title,
                description: L10n.onbSlide1Description,
                cta: L10n.onbSlide1CTA,
                isFinish: false
            ),
            OnboardingSlide(
                id: .progress,
                title: L10n.onbSlide2Title,
                description: L10n.onbSlide2Description,
                cta: L10n.onbSlide2CTA,
                isFinish: false
            ),
            OnboardingSlide(
                id: .liveSessions,
                title: L10n.onbSlide3Title,
                description: L10n.onbSlide3Description,
                cta: L10n.onbSlide3CTA,
                isFinish: true
            ),
        ]
    }

    var body: some View {
        ZStack {
            OnboardingColors.bg.ignoresSafeArea()
            TabView(selection: $currentPage) {
                OnboardingBrandSlide {
                    withAnimation(.easeInOut(duration: 0.6)) { currentPage = 1 }
                }
                .tag(0)
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    OnboardingContentSlide(
                        slide: slide,
                        dotIndex: index,
                        totalDots: slides.count,
                        onCTA: {
                            if slide.isFinish {
                                onFinish()
                            } else {
                                withAnimation(.easeInOut(duration: 0.35)) { currentPage += 1 }
                            }
                        }
                    )
                    .tag(index + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}

// MARK: - Slide data model

private enum OnboardingSlideId { case myCourses, progress, liveSessions }

private struct OnboardingSlide {
    let id: OnboardingSlideId
    let title: String
    let description: String
    let cta: String
    /// `true` → CTA finishes onboarding; `false` → advances to next page.
    let isFinish: Bool
}

// MARK: - Brand Slide

private struct OnboardingBrandSlide: View {
    let onAutoAdvance: () -> Void
    @State private var appeared = false
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [OnboardingColors.goldDark.opacity(0.30), .clear],
                center: .center, startRadius: 0, endRadius: 300
            )
            VStack(spacing: 22) {
                DroobLogoMark(size: 120)
                VStack(spacing: 8) {
                    Text(L10n.brandName)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                    Text(L10n.splashTagline)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(appLocale == "ar" ? 0 : 3.5)
                        .foregroundColor(OnboardingColors.gold)
                }
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.88)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65)) {
                appeared = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 3_800_000_000)
                onAutoAdvance()
            }
        }
    }
}

// MARK: - Content Slide
//
// Layout matches the Figma:
//   - illustration floats in the top ~55% of the screen
//   - bottom sheet (page dots → title → subtitle → CTA) sits on the
//     pure-black canvas. No surface treatment, no sign-in link.

private struct OnboardingContentSlide: View {
    let slide: OnboardingSlide
    let dotIndex: Int
    let totalDots: Int
    let onCTA: () -> Void

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                OnboardingIllustration(id: slide.id)
                    .frame(height: geo.size.height * 0.55)
                    .frame(maxWidth: .infinity)

                OnboardingBottomSheet(
                    slide: slide,
                    dotIndex: dotIndex,
                    totalDots: totalDots,
                    onCTA: onCTA
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(OnboardingColors.bg)
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Illustration dispatcher

private struct OnboardingIllustration: View {
    let id: OnboardingSlideId

    var body: some View {
        ZStack {
            OnboardingColors.bg
            switch id {
            case .myCourses:    MyCoursesIllustration()
            case .progress:     ProgressIllustration()
            case .liveSessions: LiveSessionsIllustration()
            }
        }
    }
}

// MARK: - Slide 1: My Courses card + streak pill

private struct MyCoursesIllustration: View {
    private struct Row {
        let icon: String
        let name: String
        let progress: Double  // 0...1; 1.0 = completed (checkmark instead of %)
    }

    private var rows: [Row] {
        [
            Row(icon: "paintbrush.fill", name: L10n.onbSampleCourse1, progress: 0.84),
            Row(icon: "function", name: L10n.onbSampleCourse2, progress: 0.55),
            Row(icon: "chart.bar.fill", name: L10n.onbSampleCourse3, progress: 1.0),
        ]
    }

    var body: some View {
        VStack(spacing: 22) {
            // Courses card
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.onbMyCoursesTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Text(L10n.onbMyCoursesSubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(OnboardingColors.muted)
                }
                .padding(.bottom, 4)

                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    courseRow(row)
                    if idx < rows.count - 1 {
                        Rectangle()
                            .fill(OnboardingColors.divider)
                            .frame(height: 1)
                    }
                }
            }
            .padding(16)
            .background(OnboardingColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.38), radius: 20, x: 0, y: 6)
            .frame(maxWidth: 320)

            // Streak pill
            HStack(spacing: 10) {
                Image(systemName: "flame.fill").font(.system(size: 16))
                    .foregroundColor(Color.droobGold)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.onbStreakLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(L10n.onbStreakSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(OnboardingColors.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(OnboardingColors.surface)
            )
            .shadow(color: .black.opacity(0.38), radius: 20, x: 0, y: 6)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func courseRow(_ row: Row) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(OnboardingColors.iconChipBg)
                Image(systemName: row.icon).font(.system(size: 16))
                    .foregroundColor(Color.droobGold.opacity(0.9))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 5) {
                Text(row.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(OnboardingColors.progressTrack)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(OnboardingColors.green)
                            .frame(width: geo.size.width * CGFloat(row.progress))
                    }
                }
                .frame(height: 4)
            }

            if row.progress >= 1.0 {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(OnboardingColors.green)
                    .frame(width: 34, alignment: .trailing)
            } else {
                Text("\(Int(row.progress * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OnboardingColors.gold)
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }
}

// MARK: - Slide 2: progress ring + stats card

private struct ProgressIllustration: View {
    private let ringSize: CGFloat = 180
    private let lineWidth: CGFloat = 14
    private let progress: Double = 0.84

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(OnboardingColors.progressTrack, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        OnboardingColors.gold,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.white)
                    Text(L10n.onbProgressThisCourse)
                        .font(.system(size: 12))
                        .foregroundColor(OnboardingColors.muted)
                }
            }
            .frame(width: ringSize, height: ringSize)

            VStack(spacing: 0) {
                statRow(label: L10n.onbStatsStreak, value: "12")
                Rectangle().fill(OnboardingColors.divider).frame(height: 1)
                statRow(label: L10n.onbStatsWatchTime, value: "28h")
                Rectangle().fill(OnboardingColors.divider).frame(height: 1)
                statRow(label: L10n.onbStatsQuizAvg, value: "81%")
            }
            .background(OnboardingColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.38), radius: 20, x: 0, y: 6)
            .frame(maxWidth: 280)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(OnboardingColors.muted)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Slide 3: live session + office hours cards

private struct LiveSessionsIllustration: View {
    var body: some View {
        VStack(spacing: 14) {
            liveSessionCard
            officeHoursCard
        }
        .padding(.horizontal, 24)
    }

    private var liveSessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                // Avatar
                ZStack {
                    Circle().fill(OnboardingColors.iconChipBg)
                    Text(L10n.onbDemoInstructorInitials)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(OnboardingColors.gold)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.onbDemoInstructorName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(L10n.onbInstructorRole)
                        .font(.system(size: 11))
                        .foregroundColor(OnboardingColors.muted)
                }
                Spacer()
                // LIVE pill
                HStack(spacing: 5) {
                    Circle().fill(OnboardingColors.green).frame(width: 6, height: 6)
                    Text(L10n.onbBadgeLive)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
            }

            Text(L10n.onbDemoSessionTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            HStack(spacing: 10) {
                Text(L10n.onbSessionViewers)
                Text("·")
                Text(L10n.onbSessionDuration)
            }
            .font(.system(size: 11))
            .foregroundColor(OnboardingColors.muted)

            HStack {
                Text(L10n.onbSessionStartedAgo)
                    .font(.system(size: 11))
                    .foregroundColor(OnboardingColors.muted)
                Spacer()
                Text(L10n.onbJoinButton)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(OnboardingColors.gold))
            }
        }
        .padding(14)
        .background(OnboardingColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.38), radius: 20, x: 0, y: 6)
    }

    private var officeHoursCard: some View {
        HStack(spacing: 12) {
            // Date block
            VStack(spacing: 1) {
                Text(L10n.onbDemoMonth)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(OnboardingColors.gold)
                Text("17")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)
            .background(OnboardingColors.iconChipBg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.onbOfficeHoursTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(L10n.onbOfficeHoursTime)
                    .font(.system(size: 11))
                    .foregroundColor(OnboardingColors.muted)
            }
            Spacer()
            Text(L10n.onbBookButton)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    Capsule()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        }
        .padding(14)
        .background(OnboardingColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.38), radius: 20, x: 0, y: 6)
    }
}

// MARK: - Bottom sheet (dots → title → subtitle → CTA)

private struct OnboardingBottomSheet: View {
    let slide: OnboardingSlide
    let dotIndex: Int
    let totalDots: Int
    let onCTA: () -> Void

    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    private var isArabic: Bool { appLocale == "ar" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingPageDots(currentPage: dotIndex, totalPages: totalDots)
                .padding(.bottom, 18)

            // Title — Fraunces italic 30pt, white, tight letter-spacing.
            Text(slide.title)
                .font(BrandFont.display(size: 30, isArabic: isArabic))
                .tracking(isArabic ? 0 : -1.2)
                .foregroundColor(.white)
                .lineSpacing(35.4 - 30)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            // Subtitle — Fraunces italic 17pt, muted.
            Text(slide.description)
                .font(BrandFont.display(size: 17, isArabic: isArabic))
                .foregroundColor(OnboardingColors.subtitle)
                .lineSpacing(26.35 - 17)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 28)

            // CTA — Figma button gradient (#C6A96B → #605234, 90deg) +
            // 16px rounded corners. Single source of truth in
            // `LinearGradient.droobButtonGradient`.
            Button(action: onCTA) {
                Text(slide.cta)
                    .font(BrandFont.displaySemiBold(size: 18, isArabic: isArabic))
                    .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(LinearGradient.droobButtonGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}

// MARK: - Shared components

private struct DroobLogoMark: View {
    let size: CGFloat

    var body: some View {
        Image("DroobLogo")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous))
            .shadow(
                color: OnboardingColors.gold.opacity(0.40),
                radius: size * 0.36, x: 0, y: size * 0.18
            )
    }
}

private struct OnboardingPageDots: View {
    let currentPage: Int
    let totalPages: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalPages, id: \.self) { i in
                Capsule()
                    .fill(i == currentPage ? OnboardingColors.gold : Color.white.opacity(0.22))
                    .frame(width: i == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
            }
        }
    }
}

// MARK: - Color tokens
//
// Sourced from Figma. `surface`, `divider`, `green` and `subtitle` are
// direct lifts; the gold tones match the existing brand gradient (kept so
// the CTA looks consistent with the rest of the app post-onboarding).

private enum OnboardingColors {
    /// Page background — pure black canvas.
    static let bg            = Color.black
    /// Card surface — #1C1C1E (Figma color-grey-11).
    static let surface       = Color(red: 0x1C / 255.0, green: 0x1C / 255.0, blue: 0x1E / 255.0)
    /// Small chip background behind icons / avatars / date blocks.
    static let iconChipBg    = Color(red: 0x2C / 255.0, green: 0x2C / 255.0, blue: 0x2E / 255.0)
    /// Row separator inside the My Courses / stats cards — rgba(84,84,88,0.36).
    static let divider       = Color(red: 84 / 255.0, green: 84 / 255.0, blue: 88 / 255.0, opacity: 0.36)
    /// Progress-bar track, dim.
    static let progressTrack = Color.white.opacity(0.10)
    /// Subtitle text — rgba(235,235,245,0.60), Figma color-grey-9460.
    static let subtitle      = Color(red: 235 / 255.0, green: 235 / 255.0, blue: 245 / 255.0, opacity: 0.60)
    /// Muted small text inside cards.
    static let muted         = Color(red: 235 / 255.0, green: 235 / 255.0, blue: 245 / 255.0, opacity: 0.55)

    // Brand accents (kept from prior pass for CTA continuity).
    static let gold          = Color(red: 0.776, green: 0.663, blue: 0.420)
    static let goldStrong    = Color(red: 0.878, green: 0.769, blue: 0.561)
    static let goldDark      = Color(red: 0.376, green: 0.322, blue: 0.204)

    /// Apple system green — #30D158 — used for completed-state and LIVE dot.
    static let green         = Color(red: 0x30 / 255.0, green: 0xD1 / 255.0, blue: 0x58 / 255.0)
}

// MARK: - Main Tab

enum AppTab: Int {
    // Five tabs total — Catalog was folded into Courses (the redesigned
    // Courses tab hosts both "Enrolled" + "Explore" modes). All five
    // render directly in the bottom bar; nothing collapses into an
    // iOS-generated "More" tab.
    case home, courses, sessions, messages, profile

    /// The AI tutor. Deliberately NOT a sixth `.tabItem`: `UITabBarController`
    /// only lays out five items on iPhone and folds the rest into its own
    /// "More" list, which is precisely what the five-tab consolidation above
    /// was done to escape. So `.ai` is a routing value, not a TabView tag —
    /// `MainTabView` renders it as an unlabelled orb docked to the bar and
    /// presents `AiTutorHubView` over the tab UI. Every existing tab keeps
    /// its slot and its order.
    ///
    /// Listed last so the raw values of the five real tabs don't shift.
    case ai
}

struct MainTabView: View {
    @EnvironmentObject private var authSession: AuthSession
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @AppStorage("pendingWelcomeForEmail") private var pendingWelcomeForEmail: String = ""
    @AppStorage("pendingWelcomeBackForEmail") private var pendingWelcomeBackForEmail: String = ""
    @State private var selectedTab: AppTab = .home
    @State private var showWelcomeCover: Bool = false
    @State private var showWelcomeBackCover: Bool = false
    /// Deep-link payload routed through Home so it pushes a CourseDetailView
    /// onto the Home navigation stack.
    @State private var deepLinkCourseId: String? = nil
    /// Navigation path for the Courses tab's stack. Seeding it with a
    /// course id (e.g. from a Home "My Courses" tap) deterministically
    /// pushes that course's CourseDetailView — path-based navigation honors
    /// a non-empty path on construction, so there's no first-render race.
    /// Mine-list rows append to it via value-based NavigationLinks. Typed as
    /// `NavigationPath` (not `[String]`) so the stack can also hold the
    /// Explore "See all" instructor route alongside course-id pushes.
    @State private var coursesPath = NavigationPath()
    /// Bumping this rebuilds the Courses NavigationStack from scratch,
    /// popping any deep push (course → section → lesson) back to the list
    /// root. Used by Home's "See all" so the user lands on the list root
    /// regardless of where they last left the Courses tab. Regular bottom-bar
    /// taps on Courses don't bump this, so their deep state is preserved.
    @State private var coursesStackResetId: UUID = UUID()
    /// Initial segment shown when the Courses tab is (re)built. "See all"
    /// under Home's My Courses section sets this to `.mine` so the user
    /// lands on the enrolled list rather than Explore.
    @State private var coursesInitialMode: CoursesTabView.Mode = .explore
    /// Presents `AiTutorHubView` — the bottom bar's AI destination. It rides
    /// over the tab UI rather than inside it because a sixth `.tabItem` would
    /// hand iOS its "More" tab (see `AppTab.ai`). The hub owns a
    /// `NavigationStack` of its own so the ask screen it resolves to is
    /// pushed exactly the way course detail and the lesson player push it.
    @State private var showAiHub = false
    /// Key window's bottom safe-area inset (34pt with a home indicator, 0
    /// with a home button). The AI orb's overlay is already laid out inside
    /// the safe area but *not* inside the tab bar, so this doesn't offset the
    /// indicator — it stands in for how much taller the bar itself is on
    /// those devices (iOS 26's floating capsule rises ~86pt above the safe
    /// area; the classic bar on home-button devices, ~49pt). Adding it to a
    /// fixed 56 lands the orb a few points clear of the bar on both. Read
    /// from UIKit for the same reason `applyTabBarSemantic` reaches into the
    /// live tree: the bar is UIKit-backed and SwiftUI's geometry at this
    /// level doesn't report its height.
    @State private var bottomSafeInset: CGFloat = 0
    /// AI tutor enabled with free on-device AI (Gemini, Groq, etc.)
    private var hideAiTutor: Bool { false }
    /// Screens that own the same bottom-trailing corner as the orb — the
    /// 1:1 and study-room chat composers, whose send buttons land directly
    /// under it — suppress it while they're up via `.hidesAiTutorOrb()`.
    @ObservedObject private var orbVisibility = AiTutorOrbVisibility.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(
                    pendingCourseId: $deepLinkCourseId,
                    onBrowseCourses: {
                        // "See all" on the My Courses section should land
                        // on the list root, not whatever deep screen the
                        // user last visited inside Courses. Clear the path,
                        // rebuild the stack via `.id()`, force the Mine segment.
                        coursesInitialMode = .mine
                        coursesPath = NavigationPath()
                        coursesStackResetId = UUID()
                        selectedTab = .courses
                    },
                    onOpenMyCourse: { id in
                        // Route to the picked course by seeding the Courses
                        // stack's path. Rebuilding via `.id()` first drops any
                        // stale deep stack from another course (Course A →
                        // section → lesson, pushed via plain NavigationLinks)
                        // and re-applies the Mine segment; the rebuilt stack
                        // then renders `coursesPath == [id]` immediately and
                        // shows the course detail. Path-based navigation honors
                        // a non-empty initial path deterministically, so unlike
                        // the old isPresented + 100ms-sleep approach there's no
                        // first-render race that strands the user on the list.
                        coursesInitialMode = .mine
                        var seeded = NavigationPath()
                        seeded.append(id)
                        coursesPath = seeded
                        coursesStackResetId = UUID()
                        selectedTab = .courses
                    }
                )
            }
            .tabItem { Label(L10n.tabHome, systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack(path: $coursesPath) {
                CoursesTabView(initialMode: coursesInitialMode)
            }
            .id(coursesStackResetId)
            .tabItem { Label(L10n.tabCourses, systemImage: "books.vertical.fill") }
            .tag(AppTab.courses)

            NavigationStack { SessionsView() }
            .tabItem { Label(L10n.tabSessions, systemImage: "calendar") }
            .tag(AppTab.sessions)

            NavigationStack { MessagesView() }
            .tabItem { Label(L10n.tabMessages, systemImage: "message.fill") }
            .tag(AppTab.messages)

            NavigationStack { ProfileView() }
            .tabItem { Label(L10n.profile, systemImage: "person.circle.fill") }
            .tag(AppTab.profile)
        }
        // The AI entry. Not a peer of the five above — an unlabelled,
        // gradient-lit orb docked to the trailing end of the bar, sized to
        // read as an action. Being label-free is what makes it affordable:
        // at the app's 1.242 type scale a sixth *labelled* tab would squeeze
        // every existing one, and this costs no bar width at all.
        //
        // Trailing/leading flips automatically with `layoutDirection`, so it
        // lands on the left in Arabic, on the same side as the last tab.
        .overlay(alignment: .bottomTrailing) {
            if !hideAiTutor, !orbVisibility.isSuppressed {
                AiTutorTabOrb { showAiHub = true }
                    .padding(.trailing, 14)
                    .padding(.bottom, bottomSafeInset + 56)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: orbVisibility.isSuppressed)
        .fullScreenCover(isPresented: $showAiHub) {
            NavigationStack {
                AskDroobAIView()
            }
        }
        // Selected tab-item icon + label. UITabBar's own background is a light
        // material in light mode, where #C6A96B reads at ~1.9:1 and the selected
        // tab becomes the *least* legible one; the accent ramp keeps the gold
        // identity while resolving to #7A5D2C there (unchanged in dark).
        .accentColor(MyCoursesPalette.accent)
        // SwiftUI's `.environment(\.layoutDirection)` doesn't propagate down
        // into the UIKit-backed UITabBar. We force the tab order to mirror
        // when the user has chosen Arabic by flipping the global semantic
        // attribute, which the SDK reads at TabBar layout time. We also
        // localise the "More" tab title here because UITabBarController
        // pulls that string from UIKit's bundle, not ours.
        .onAppear {
            applyTabBarSemantic(for: appLocale)
            evaluateWelcomeCover()
            refreshBottomSafeInset()
            orbVisibility.setCurrentTab(selectedTab)
        }
        // Orb holds are recorded per tab (see `AiTutorOrbVisibility`), so
        // the store needs to know which tab is up: a chat left open in
        // Messages must not keep the orb hidden on Home.
        .onChange(of: selectedTab) { tab in orbVisibility.setCurrentTab(tab) }
        .onReceive(NotificationCenter.default.publisher(
            for: UIDevice.orientationDidChangeNotification)) { _ in
            refreshBottomSafeInset()
        }
        .onChange(of: appLocale) { newLocale in applyTabBarSemantic(for: newLocale) }
        .onReceive(authSession.$pendingDeepLinkCourseId.compactMap { $0 }) { courseId in
            deepLinkCourseId = courseId
            selectedTab = .home
            authSession.pendingDeepLinkCourseId = nil
        }
        // Empty-state CTAs in the Messages tab post this to route the
        // user back to the Courses tab so they can browse / pick a
        // course → study rooms.
        .onReceive(NotificationCenter.default.publisher(
            for: .droobSwitchToTab)) { note in
            if let tab = note.object as? AppTab {
                // "Browse courses" must land on the Courses browse root, not
                // whatever deep screen (course → section → lesson) the user
                // last left the Courses tab on. Rebuild the stack via `.id()`
                // and force the Explore segment — same approach as Home's
                // "See all". Other tabs switch without touching their stacks.
                // `.ai` isn't a TabView tag — it opens the hub over the tab
                // UI, leaving whichever tab the user was on selected
                // underneath.
                if tab == .ai {
                    if !hideAiTutor { showAiHub = true }
                    return
                }
                if tab == .courses {
                    coursesInitialMode = .explore
                    coursesPath = NavigationPath()
                    coursesStackResetId = UUID()
                }
                selectedTab = tab
            }
        }
        // Auto-approved enrollment (testing backend) → land on the Courses
        // tab's Enrolled list root so the just-enrolled course is visible.
        // Rebuilds the stack via `.id()` and forces the Mine segment, mirroring
        // Home's "See all" landing.
        .onReceive(NotificationCenter.default.publisher(
            for: .droobOpenEnrolledCourses)) { _ in
            coursesInitialMode = .mine
            coursesPath = NavigationPath()
            coursesStackResetId = UUID()
            selectedTab = .courses
        }
        // Study-room Universal-Link landing lives on RootView so it
        // works regardless of which auth branch is currently rendered.
        .onReceive(authSession.$state) { _ in evaluateWelcomeCover() }
        .fullScreenCover(isPresented: $showWelcomeCover) {
            if let user = authSession.currentUser {
                WelcomeAccountCreatedView(
                    displayName: user.displayName,
                    email: user.email,
                    onMeetInstructors: {
                        showWelcomeCover = false
                        pendingWelcomeForEmail = ""
                        selectedTab = .courses
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showWelcomeBackCover) {
            if let user = authSession.currentUser {
                WelcomeBackView(
                    displayName: user.displayName,
                    email: user.email,
                    onGoToDashboard: {
                        showWelcomeBackCover = false
                        pendingWelcomeBackForEmail = ""
                        selectedTab = .home
                    },
                    onContinueLastCourse: { courseId in
                        showWelcomeBackCover = false
                        pendingWelcomeBackForEmail = ""
                        selectedTab = .home
                        // Routes the Home navigation stack to push the
                        // CourseDetailView for this course (existing
                        // deep-link mechanism — see onReceive above).
                        authSession.pendingDeepLinkCourseId = courseId
                    }
                )
            }
        }
    }

    /// Caches the key window's bottom safe-area inset (34pt on
    /// home-indicator devices, 0 on home-button ones) so the AI orb clears
    /// the tab bar on both. Deferred a runloop turn because at `.onAppear`
    /// the window may not be key yet — same reason `applyTabBarSemantic`
    /// hops to `DispatchQueue.main.async` before touching the live tree.
    private func refreshBottomSafeInset() {
        DispatchQueue.main.async {
            let inset = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?
                .safeAreaInsets.bottom
            bottomSafeInset = inset ?? 0
        }
    }

    /// Show the post-signup welcome cover once, only for the email that
    /// just completed registration. Cleared whenever we present it.
    private func evaluateWelcomeCover() {
        guard let email = authSession.currentUser?.email else { return }
        if !pendingWelcomeForEmail.isEmpty,
           email.caseInsensitiveCompare(pendingWelcomeForEmail) == .orderedSame {
            showWelcomeCover = true
            return
        }
        if !pendingWelcomeBackForEmail.isEmpty,
           email.caseInsensitiveCompare(pendingWelcomeBackForEmail) == .orderedSame {
            showWelcomeBackCover = true
        }
    }

    /// UIKit reads `semanticContentAttribute` once per layout pass. Setting
    /// it on `UITabBar.appearance()` flips both the icon order and the
    /// safe-area inset direction so the tab bar mirrors RTL even though
    /// SwiftUI's `layoutDirection` env doesn't reach UITabBar.
    ///
    /// We also walk the active UIWindow's view hierarchy to find the
    /// UITabBarController and rename its `moreNavigationController` so the
    /// "More" tab and its drill-down navigation bar both pick up the
    /// localised title. This bypass is necessary because `Label("More")`
    /// in `.tabItem` is rendered by UIKit's MoreNavigationController whose
    /// title comes from UIKit's localisation bundle, not ours.
    private func applyTabBarSemantic(for locale: String) {
        let attr: UISemanticContentAttribute = locale == "ar" ? .forceRightToLeft : .forceLeftToRight
        // Appearance proxies only affect views created AFTER this call. We set
        // them so freshly-instantiated UIKit views adopt the new direction.
        UITabBar.appearance().semanticContentAttribute = attr
        UINavigationBar.appearance().semanticContentAttribute = attr
        UIView.appearance().semanticContentAttribute = attr
        // Schedule the live-tree mutation for after SwiftUI lays out — at
        // .onAppear the UITabBarController hierarchy may not exist yet.
        DispatchQueue.main.async {
            applyLiveSemantic(attr: attr)
            renameMoreTab(to: L10n.tabMore)
        }
    }

    /// Mutates ALREADY-RENDERED UIKit views to pick up the new layout
    /// direction. Setting `UIView.appearance()` alone isn't enough at runtime
    /// because Apple resolves the appearance proxy at instantiation; switching
    /// language after launch leaves the existing tab bar / nav bar mirrored
    /// the wrong way until we set the attribute on the live instances and
    /// force a layout pass.
    private func applyLiveSemantic(attr: UISemanticContentAttribute) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.semanticContentAttribute = attr
                walkAndApply(window, attr: attr)
                window.rootViewController?.view.setNeedsLayout()
                window.rootViewController?.view.layoutIfNeeded()
            }
        }
    }

    /// Recursively flips the semantic attribute on UIKit containers that
    /// auto-mirror (tab bar, nav bar, toolbar). We deliberately don't touch
    /// every UIView — SwiftUI-hosted content listens to
    /// `\.environment(\.layoutDirection)` which we set at the App level, so
    /// only the UIKit chrome needs the manual flip.
    private func walkAndApply(_ view: UIView, attr: UISemanticContentAttribute) {
        if view is UITabBar || view is UINavigationBar || view is UIToolbar {
            view.semanticContentAttribute = attr
            view.setNeedsLayout()
        }
        for sub in view.subviews {
            walkAndApply(sub, attr: attr)
        }
    }

    /// Walks every connected scene's UITabBarController and patches the
    /// "More" tab's title + nav bar. No-op if none exists yet.
    private func renameMoreTab(to title: String) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if let tabBarController = findTabBarController(window.rootViewController) {
                    tabBarController.moreNavigationController.navigationBar.topItem?.title = title
                    tabBarController.moreNavigationController.tabBarItem.title = title
                }
            }
        }
    }

    private func findTabBarController(_ vc: UIViewController?) -> UITabBarController? {
        guard let vc else { return nil }
        if let tab = vc as? UITabBarController { return tab }
        for child in vc.children {
            if let tab = findTabBarController(child) { return tab }
        }
        if let presented = vc.presentedViewController {
            return findTabBarController(presented)
        }
        return nil
    }
}
