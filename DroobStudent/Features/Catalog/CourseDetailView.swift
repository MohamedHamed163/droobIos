import SwiftUI

struct CourseDetailView: View {
    let courseId: String
    @StateObject private var viewModel: CourseDetailViewModel
    @Environment(\.appLocale) private var locale
    @Environment(\.dismiss) private var dismiss
    /// Gates the enrollment-approval poll: it must not tick while the app is
    /// backgrounded (or sitting inactive in the switcher).
    @Environment(\.scenePhase) private var scenePhase
    @State private var showRateSheet: Bool = false
    @State private var showAllReviews: Bool = false
    @State private var showQuestions: Bool = false
    @State private var showInstructorProfile: Bool = false
    @State private var showStudyRooms: Bool = false
    @State private var showRequestSheet: Bool = false
    /// "Ask AI" entry point. Same hidden-NavigationLink idiom as the
    /// other pushes on this screen.
    @State private var showAiTutor: Bool = false
    /// Flipped once, by the approval poll, to push the student straight into
    /// the curriculum the moment the instructor lets them in.
    @State private var openCurriculum: Bool = false
    /// Set when the approval lands while the request sheet is still up. The
    /// push has to wait for the sheet's dismissal to finish — see the sheet's
    /// `onDismiss` below.
    @State private var pushCurriculumAfterSheetDismiss: Bool = false
    /// Join response for the instructor-created room (2026-07) — seeds
    /// the chat for instant first render. Nil until the card is tapped.
    @State private var instructorRoomDetail: StudyRoomDetail? = nil
    /// Guards against double-taps on the Study Together card while the
    /// idempotent join round-trip is in flight.
    @State private var isJoiningInstructorRoom: Bool = false

    // Hidden for now (2026-07): reviews/ratings paused platform-wide.
    private var hideReviews: Bool { true }
    // Hidden for now (2026-07): Q&A + pinned FAQs paused platform-wide.
    private var hideQa: Bool { true }
    // AI tutor enabled with free on-device AI
    private var hideAiTutor: Bool { false }

    init(courseId: String, viewModelOverride: CourseDetailViewModel? = nil) {
        self.courseId = courseId
        _viewModel = StateObject(wrappedValue: viewModelOverride ?? CourseDetailViewModel(courseId: courseId))
    }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            Group {
                if viewModel.isLoading {
                    CourseDetailSkeleton()
                } else if let error = viewModel.errorMessage, viewModel.course == nil {
                    ErrorBanner(message: error) {
                        Task { await viewModel.load() }
                    }
                    .padding(.horizontal, 20)
                } else if let course = viewModel.course {
                    courseContent(course)
                }
            }

            if let course = viewModel.course {
                // Hidden for now (2026-07): reviews/ratings paused platform-wide.
                if !hideReviews {
                    NavigationLink(isActive: $showAllReviews) {
                        AllReviewsView(courseId: course.id, courseTitle: course.localizedTitle(locale: locale))
                    } label: { EmptyView() }
                    .hidden()
                }

                // Hidden for now (2026-07): Q&A + pinned FAQs paused platform-wide.
                if !hideQa {
                    NavigationLink(isActive: $showQuestions) {
                        AllQuestionsView(
                            courseId: course.id,
                            courseTitle: course.localizedTitle(locale: locale))
                    } label: { EmptyView() }
                    .hidden()
                }

                NavigationLink(isActive: $showInstructorProfile) {
                    InstructorProfileView(instructorId: course.instructorId)
                } label: { EmptyView() }
                .hidden()

                // AI tutor. Opens the Ask Droob AI chat directly.
                if !hideAiTutor {
                    NavigationLink(isActive: $showAiTutor) {
                        AskDroobAIView()
                    } label: { EmptyView() }
                    .hidden()
                }

                // Approval auto-route. The view model refreshes the course +
                // enrollment state before it flips `approvalDetected`, so by
                // the time this activates `course` already reads as enrolled
                // and the curriculum won't 403 on a stale local model.
                NavigationLink(isActive: $openCurriculum) {
                    CurriculumView(course: course)
                } label: { EmptyView() }
                .hidden()

                // Study Rooms entry point. 2026-07: routes straight to
                // the instructor-created room's chat (after an
                // idempotent join) — the student create/join flow is
                // hidden, not deleted. Old destination kept below:
                // NavigationLink(isActive: $showStudyRooms) {
                //     CreateOrJoinRoomView(
                //         courseId: course.id,
                //         courseTitle: course.localizedTitle(locale: locale))
                // } label: { EmptyView() }
                // .hidden()
                NavigationLink(isActive: $showStudyRooms) {
                    if let room = viewModel.instructorRoom {
                        StudyRoomChatView(
                            roomId: room.roomId,
                            prefetchedRoom: instructorRoomDetail,
                            courseTitle: course.localizedTitle(locale: locale))
                    }
                } label: { EmptyView() }
                .hidden()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        // Approval polling is only allowed to run while this screen is on
        // screen AND the app is in the foreground. `.onAppear` marks the
        // screen live and does an immediate catch-up poll; `.onDisappear`
        // cancels the task so it can't outlive the screen. Both hooks are
        // synchronous calls into the view model, which is what keeps a resume
        // and a suspend ordered against each other.
        .onAppear {
            viewModel.requestResumeApprovalPolling()
        }
        .onDisappear {
            viewModel.suspendApprovalPolling()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // Catch-up poll on return — approval very often lands while
                // the app is backgrounded, so don't wait out a full tick.
                viewModel.requestResumeApprovalPolling()
            case .inactive, .background:
                // `.inactive` (app switcher, control centre, incoming call)
                // counts as "not being read" too — suspend on both.
                viewModel.suspendApprovalPolling()
            @unknown default:
                viewModel.suspendApprovalPolling()
            }
        }
        // Instructor approved the pending request: drop any open request
        // sheet and take the student straight into the course. Fires once —
        // the view model latches `approvalDetected`.
        .onChange(of: viewModel.approvalDetected) { detected in
            guard detected else { return }
            // With no sheet up the push can go straight through.
            guard showRequestSheet else { openCurriculum = true; return }
            // Otherwise it must not ride the same transaction as the
            // dismissal: SwiftUI tears the sheet down and silently drops a
            // NavigationLink activation made in that same update, so the
            // student lands back on the course screen with nothing pushed.
            // Hand the push to `onDismiss` instead.
            pushCurriculumAfterSheetDismiss = true
            showRequestSheet = false
        }
        // Collapse the entire study-rooms sub-stack (CreateOrJoin → Room
        // Ready → chat) back to the course in one deterministic flip when
        // the user exits a room from inside the chat. Resetting this top
        // binding tears down the nested `isActive` links reliably, where a
        // `dismiss()` from the chat would get dropped by the still-`true`
        // parent bindings (the "Back to course does nothing" bug).
        .onReceive(NotificationCenter.default.publisher(for: .droobExitStudyRooms)) { _ in
            showStudyRooms = false
        }
        .sheet(isPresented: $showRateSheet) {
            // Hidden for now (2026-07): reviews/ratings paused platform-wide.
            if !hideReviews, let course = viewModel.course {
                rateSheetContent(course: course)
            }
        }
        // `onDismiss` runs once the sheet is actually gone, so the deferred
        // approval push is a separate update from the dismissal. The extra
        // main-queue hop gives the navigation stack a runloop turn of its own
        // — activating the link from inside the dismissal's own update is the
        // very thing that loses the push.
        .sheet(isPresented: $showRequestSheet, onDismiss: {
            guard pushCurriculumAfterSheetDismiss else { return }
            pushCurriculumAfterSheetDismiss = false
            DispatchQueue.main.async { openCurriculum = true }
        }) {
            if let course = viewModel.course {
                requestSheetContent(course: course)
            }
        }
    }

    @ViewBuilder
    private func requestSheetContent(course: CourseDetail) -> some View {
        let editing = viewModel.pendingRequest != nil
        let sheet = RequestEnrollmentSheet(
            mode: editing ? .edit : .create,
            courseTitle: course.localizedTitle(locale: locale),
            instructorName: course.instructorName,
            coverUrl: course.coverUrl,
            existingNote: viewModel.pendingRequest?.note,
            onSubmit: { note in
                if editing {
                    return await viewModel.editPendingNote(note: note) ? .saved : .failed
                } else {
                    return await viewModel.requestEnrollment(note: note)
                }
            },
            onCancelRequest: editing ? { await viewModel.cancelPendingRequest() } : nil,
            onAutoEnrolled: {
                // Auto-approved by the backend (testing): close the composer and
                // land on the Courses tab's Enrolled list, where the just-
                // enrolled course now appears — keeps the UI consistent with the
                // approved state instead of showing "Request Sent".
                showRequestSheet = false
                NotificationCenter.default.post(
                    name: .droobOpenEnrolledCourses, object: nil)
            },
            onClose: { showRequestSheet = false })

        if #available(iOS 16.4, *) {
            sheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(MyCoursesPalette.background)
        } else {
            sheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func rateSheetContent(course: CourseDetail) -> some View {
        let sheet = RateCourseSheet(
            courseTitle: course.localizedTitle(locale: locale),
            instructorName: course.instructorName,
            coverUrl: course.coverUrl,
            existing: viewModel.course?.recentReviews.first { _ in false }, // no per-user lookup yet
            onSubmit: { stars, body in
                await viewModel.submitReview(stars: stars, body: body)
            },
            onClose: { showRateSheet = false })

        if #available(iOS 16.4, *) {
            sheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(MyCoursesPalette.background)
        } else {
            sheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func courseContent(_ course: CourseDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(for: course)
                infoBlock(for: course)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: Hero

    private func hero(for course: CourseDetail) -> some View {
        ZStack(alignment: .top) {
            // Gradient background that matches the design's purple-to-black hero
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.10, blue: 0.28),
                    MyCoursesPalette.background
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 320)

            // Gold symbol fallback — covered by the course cover when it loads;
            // stays visible while loading or when the course has no cover.
            Image(systemName: coverSymbol(for: course))
                .font(.system(size: 64, weight: .regular))
                .foregroundColor(Color.droobGold.opacity(0.9))
                .frame(maxWidth: .infinity)
                .frame(height: 320)

            if let url = course.coverUrl.flatMap(URL.init(string:)) {
                // A fixed-size Color.clear drives the hero's layout; the cover
                // rides on top as an overlay. `scaledToFill` may make a wide/
                // large cover overflow the 320-tall box, but an overlay reports
                // the *base's* size — so the image's scaled width can never
                // propagate into the ScrollView and stretch the page — and the
                // trailing `.clipped()` trims the overflow. (Without this a wide
                // cover pushed the page wider than the screen and moved controls
                // off-screen.)
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .overlay(
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                ZStack {
                                    img.resizable().scaledToFill()
                                    // Scrim: keeps the chrome legible over the image
                                    // and fades the bottom edge into the page background.
                                    LinearGradient(
                                        stops: [
                                            .init(color: .black.opacity(0.45), location: 0),
                                            .init(color: .clear, location: 0.4),
                                            .init(color: MyCoursesPalette.background.opacity(0.85), location: 1),
                                        ],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                }
                            default:
                                Color.clear
                            }
                        }
                    )
                    .clipped()
            }

            heroChrome
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }
        .frame(height: 320)
    }

    private var heroChrome: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(MyCoursesPalette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: Info block

    private func infoBlock(for course: CourseDetail) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            metaRow(for: course)
            titleBlock(for: course)
            // Hidden for now (2026-07): pricing removed from app for ALL
            // users, not just auto-enroll students. Old gate kept below so it
            // can be restored:
            // if AuthSession.shared.currentUser?.isAutoEnroll != true {
            //     priceLabel(for: course)
            // }
            statsRow(for: course)

            // "Ask AI" — the AI tutor's entry point on this screen. Gated
            // on enrollment to match the backend's enrollment guard on the
            // tutor endpoints, same as the Study Together card below.
            // Hidden for now (2026-08): AI tutor paused platform-wide.
            if course.enrolled, !hideAiTutor {
                AskAiCard { showAiTutor = true }
            }

            // "Study together" card — gated on enrollment to match the
            // backend's enrollment guard. 2026-07: also gated on an
            // instructor-created room existing; tapping joins that room
            // (idempotent) and opens its chat directly instead of the
            // student create/join flow.
            // Old gate: if course.enrolled { ... showStudyRooms = true ... }
            if course.enrolled, let room = viewModel.instructorRoom {
                // The card renders "1 room live now" — the instructor
                // room is the only room surfaced here.
                StudyTogetherCard(liveCount: 1) {
                    openInstructorRoom(room)
                }
                .disabled(isJoiningInstructorRoom)
            }

            if course.enrolled {
                progressCard(for: course)
            }

            instructorCard(for: course)

            if !course.sections.isEmpty {
                curriculumBlock(for: course)
            }

            // Hidden for now (2026-07): Q&A + pinned FAQs paused platform-wide.
            if !hideQa, !course.pinnedFaqs.isEmpty {
                CoursePinnedFaqsBlock(
                    faqs: course.pinnedFaqs,
                    instructorName: course.instructorName,
                    locale: locale)
            }

            // Hidden for now (2026-07): reviews/ratings paused platform-wide.
            if !hideReviews {
                reviewsBlock(for: course)
                rateCourseButton(for: course)
            }
            // Hidden for now (2026-07): Q&A + pinned FAQs paused platform-wide.
            if !hideQa {
                qaBlock(for: course)
            }

            primaryAction(for: course)
        }
    }

    // MARK: Rate This Course
    //
    // Lives between Reviews and Q&A per the Figma — it's a follow-on
    // affordance to the reviews block ("…and rate it yourself"), not a
    // Q&A action. Disabled / muted for non-enrolled users since the
    // backend rejects reviews from non-enrolled students.

    private func rateCourseButton(for course: CourseDetail) -> some View {
        Button {
            if course.enrolled { showRateSheet = true }
        } label: {
            qaActionButtonLabel(
                icon: "star",
                text: L10n.courseDetailRateThisCourse,
                enabled: course.enrolled)
        }
        .buttonStyle(.plain)
        .disabled(!course.enrolled)
    }

    // MARK: Curriculum

    private func curriculumBlock(for course: CourseDetail) -> some View {
        let sections = course.sections.filter { !$0.isRevision }
        return VStack(alignment: .leading, spacing: 14) {
            Text(L10n.courseDetailCurriculumTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            if sections.isEmpty {
                curriculumEmptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        NavigationLink {
                            CurriculumView(course: course)
                        } label: {
                            ModuleRow(
                                index: index + 1,
                                section: section,
                                locale: locale)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var curriculumEmptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "book")
                .font(.system(size: 28))
                .foregroundColor(MyCoursesPalette.muted)
            Text(L10n.courseDetailCurriculumEmpty)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: Reviews

    private func reviewsBlock(for course: CourseDetail) -> some View {
        let distribution = course.ratingDistribution ?? RatingDistribution.empty
        return CourseReviewsBlock(
            distribution: distribution,
            recentReviews: course.recentReviews,
            locale: locale,
            onSeeAll: { showAllReviews = true })
    }

    // MARK: Q&A

    private func qaBlock(for course: CourseDetail) -> some View {
        // CourseQuestionsBlock owns the section title + the preview
        // card; the "Ask a Question" CTA stays here so the host
        // controls navigation. Two-row preview matches the Figma; full
        // thread lives on the placeholder screen until that ships.
        VStack(alignment: .leading, spacing: 14) {
            CourseQuestionsBlock(
                questions: course.recentQuestions,
                totalCount: course.questionsCount,
                locale: locale,
                onSeeAll: { showQuestions = true })

            Button {
                showQuestions = true
            } label: {
                askQuestionButtonLabel
            }
            .buttonStyle(.plain)
        }
    }

    /// Surface-filled button used for "Rate This Course" between
    /// Reviews and Q&A. Sits as a quiet secondary affordance on top of
    /// the same dark surface the other cards use, with a white star and
    /// white serif italic label — matches the muted treatment in the
    /// Figma. Greys out for non-enrolled students.
    private func qaActionButtonLabel(icon: String, text: String, enabled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundColor(enabled ? .primary : MyCoursesPalette.muted)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MyCoursesPalette.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    /// Dark-navy CTA with a medium-blue stroke and blue icon + text —
    /// matches the Figma "Ask a Question" treatment. Distinct from any
    /// gold/white action on the page so it reads as the Q&A section's
    /// primary participation affordance regardless of enrolment.
    private var askQuestionButtonLabel: some View {
        let blueAccent = Color(red: 0.31, green: 0.49, blue: 1.00)
        let darkNavy   = Color(red: 0.04, green: 0.06, blue: 0.15)
        return HStack(spacing: 10) {
            Image(systemName: "bubble.left")
                .font(.system(size: 14, weight: .semibold))
            Text(L10n.courseDetailAskAQuestion)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundColor(blueAccent)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(darkNavy))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(blueAccent.opacity(0.65), lineWidth: 1))
    }

    private func metaRow(for course: CourseDetail) -> some View {
        HStack(spacing: 8) {
            if course.isBestseller {
                Text(L10n.courseBestseller)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.droobGold)
                    .clipShape(Capsule())
            }
            Text(L10n.courseCategoryUxUi)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MyCoursesPalette.muted)

            // Hidden for now (2026-07): reviews/ratings paused platform-wide.
            if !hideReviews, let rating = course.ratingAvg {
                Text("·")
                    .foregroundColor(MyCoursesPalette.muted)
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.droobGold)
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
        }
    }

    private func titleBlock(for course: CourseDetail) -> some View {
        let parts = splitTitle(course.localizedTitle(locale: locale))
        return VStack(alignment: .leading, spacing: 2) {
            Text(parts.first)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
            if let second = parts.second {
                Text(second)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color.droobGold)
            }
        }
    }

    /// Joins the instructor-created room (idempotent for existing
    /// members) and pushes its chat. The join response seeds the chat
    /// for instant first render; on failure we still push — the chat's
    /// own bootstrap refetches the detail and surfaces any error.
    private func openInstructorRoom(_ room: StudyRoomSummary) {
        guard !isJoiningInstructorRoom else { return }
        isJoiningInstructorRoom = true
        Task { @MainActor in
            instructorRoomDetail = try? await StudyRoomsAPI.joinPublic(roomId: room.roomId)
            isJoiningInstructorRoom = false
            showStudyRooms = true
        }
    }

    /// Price shown to normal students under the title. Uses
    /// `CurrencyFormat`, which renders `L10n.free` ("Free") for a zero price.
    /// Hidden entirely for special (auto-enroll) students — see `infoBlock`.
    private func priceLabel(for course: CourseDetail) -> some View {
        Text(CurrencyFormat.formatted(priceCents: course.priceCents, currency: course.currency))
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(Color.droobGold)
    }

    private func statsRow(for course: CourseDetail) -> some View {
        HStack(spacing: 16) {
            statItem(icon: "book.fill", text: "\(course.lessonCount) \(L10n.lessonsLowercase)")
            statItem(icon: "clock", text: course.formattedHours)
            // Enrolled-student count removed platform-wide (2026-08). The
            // backend still sends `students_count`; nothing renders it.
        }
    }

    private func statItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(MyCoursesPalette.muted)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MyCoursesPalette.muted)
        }
    }

    private func progressCard(for course: CourseDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.courseYourProgress)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(Int(course.progressPct))%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.droobGold)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(MyCoursesPalette.stroke).frame(height: 5)
                    Capsule()
                        .fill(LinearGradient.droobBrand)
                        .frame(width: max(0, geo.size.width * CGFloat(course.progressPct / 100)), height: 5)
                }
            }
            .frame(height: 5)

            HStack(spacing: 4) {
                Text("\(course.completedLessonCount) \(L10n.courseProgressOf) \(course.lessonCount) \(L10n.lessonsLowercase)")
                if let next = course.localizedNextLessonTitle(locale: locale) {
                    Text("· \(L10n.courseProgressNext): \(next.bidiIsolated)")
                }
            }
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(MyCoursesPalette.muted)
        }
        .padding(16)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    private func instructorCard(for course: CourseDetail) -> some View {
        Button {
            if !course.instructorId.isEmpty { showInstructorProfile = true }
        } label: {
            instructorCardLabel(for: course)
        }
        .buttonStyle(.plain)
        .disabled(course.instructorId.isEmpty)
    }

    private func instructorCardLabel(for course: CourseDetail) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.droobGold.opacity(0.4), lineWidth: 1)
                    .background(Circle().fill(Color.droobGold.opacity(0.10)))
                Text(initials(course.instructorName))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.droobGold)
                // Presigned avatar loads over the gold-ring initials disc
                // and replaces it on success; any other phase keeps the
                // initials fallback showing.
                if let url = course.instructorAvatarUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color.clear
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                }
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(course.instructorName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Text(L10n.courseInstructorSubtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .padding(14)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    @ViewBuilder
    private func primaryAction(for course: CourseDetail) -> some View {
        if course.enrolled {
            NavigationLink {
                CurriculumView(course: course)
            } label: {
                primaryButton(text: L10n.myCoursesContinueLearning, leading: "play.fill")
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: 12) {
                // Rule: a REJECTED / CANCELLED decision found by the poll
                // updates the UI in place and never navigates.
                if let decision = viewModel.requestDecision {
                    decisionNotice(for: decision)
                }

                if viewModel.pendingRequest != nil {
                    Button {
                        showRequestSheet = true
                    } label: {
                        pendingButton
                    }
                    .buttonStyle(.plain)

                    // The poll gives up after its ceiling (an instructor may
                    // take a day) — hand the student a manual refresh instead
                    // of leaving them on a screen that will never update.
                    if viewModel.approvalPollGaveUp {
                        Button {
                            Task { await viewModel.checkApprovalNow() }
                        } label: {
                            Text(L10n.enrollRequestCheckNow)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.droobGold)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        showRequestSheet = true
                    } label: {
                        primaryButton(text: L10n.enrollRequestRequestToEnroll, leading: nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Inline notice for a terminal, non-approving decision.
    private func decisionNotice(for decision: EnrollmentRequestStatus) -> some View {
        Text(decision == .rejected
             ? L10n.enrollRequestDecisionRejected
             : L10n.enrollRequestDecisionCancelled)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(MyCoursesPalette.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    /// "Request Pending" state — a muted, surface-filled button with a clock
    /// glyph. Tappable to open the manage (edit-note / withdraw) sheet.
    private var pendingButton: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.enrollRequestPendingButton)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(Color.droobGold)
            Text(viewModel.approvalPollGaveUp
                 ? L10n.enrollRequestPollStoppedHint
                 : L10n.enrollRequestPendingSubtitle)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(MyCoursesPalette.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.droobGold.opacity(0.4), lineWidth: 1))
    }

    private func primaryButton(text: String, leading: String?) -> some View {
        HStack(spacing: 8) {
            if let leading {
                Image(systemName: leading)
                    .font(.system(size: 14, weight: .bold))
            }
            Text(text)
                .font(.system(size: 16, weight: .semibold))
        }
        .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(LinearGradient.droobBrand)
        .clipShape(Capsule())
    }

    // MARK: helpers

    /// Splits "UX/UI Fundamentals: Design with Intention" into two lines so we
    /// can paint the second line in gold, matching the Figma title treatment.
    private func splitTitle(_ title: String) -> (first: String, second: String?) {
        if let colon = title.range(of: ":") {
            let head = title[..<colon.lowerBound].trimmingCharacters(in: .whitespaces)
            let tail = title[colon.upperBound...].trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { return (head, tail) }
        }
        return (title, nil)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined()
    }

    private func coverSymbol(for course: CourseDetail) -> String {
        let pool = ["graduationcap.fill", "book.fill", "paintbrush.fill",
                    "chart.bar.fill", "lightbulb.fill", "laptopcomputer",
                    "globe", "function"]
        return pool[abs(course.id.hashValue) % pool.count]
    }
}

// MARK: - Module Row

struct ModuleRow: View {
    let index: Int
    let section: CourseSection
    let locale: String

    var body: some View {
        HStack(spacing: 14) {
            statusIcon
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(bidiJoin("\(L10n.courseModule) \(index)",
                              section.localizedTitle(locale: locale),
                              separator: " — "))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(statusSubtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(statusColor)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .padding(14)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    private var statusIcon: some View {
        Group {
            if section.isCompleted {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MyCoursesPalette.success.opacity(0.15))
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MyCoursesPalette.success)
                }
            } else if section.isInProgress {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.droobGold.opacity(0.15))
                    Text("\(index)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.droobGold)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1)
                    Text("\(index)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.muted)
                }
            }
        }
    }

    private var statusSubtitle: String {
        if section.isCompleted {
            return "\(L10n.myCoursesCompletedFilter) · \(section.lessonCount) \(L10n.lessonsLowercase)"
        }
        if section.isInProgress {
            return "\(L10n.courseInProgressLower) · \(section.completedLessonCount)/\(section.lessonCount) \(L10n.lessonsLowercase)"
        }
        return "\(L10n.courseNotStartedLower) · \(section.lessonCount) \(L10n.lessonsLowercase)"
    }

    private var statusColor: Color {
        if section.isCompleted { return MyCoursesPalette.success }
        if section.isInProgress { return Color.droobGold }
        return MyCoursesPalette.muted
    }
}

// MARK: - Skeleton

struct CourseDetailSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero placeholder
                Rectangle()
                    .fill(MyCoursesPalette.textTertiary.opacity(0.12))
                    .frame(height: 320)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        MCSkeletonBlock(height: 22, cornerRadius: 11, width: 70)
                        MCSkeletonBlock(height: 22, cornerRadius: 11, width: 90)
                    }

                    MCSkeletonBlock(height: 28, cornerRadius: 6, width: 240)
                    MCSkeletonBlock(height: 28, cornerRadius: 6, width: 200)

                    HStack(spacing: 12) {
                        MCSkeletonBlock(height: 14, cornerRadius: 4, width: 70)
                        MCSkeletonBlock(height: 14, cornerRadius: 4, width: 50)
                        MCSkeletonBlock(height: 14, cornerRadius: 4, width: 60)
                    }

                    ForEach(0..<5, id: \.self) { _ in
                        MCSkeletonBlock(height: 64, cornerRadius: 14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
    }
}
