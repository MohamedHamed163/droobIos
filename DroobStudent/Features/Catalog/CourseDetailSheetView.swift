import SwiftUI

// MARK: - CourseDetailSheetView (Figma node 1955-6165)
//
// Bottom-sheet "enrollment screen" reached by tapping a course card
// (Home, Catalog, Instructor profile). Layout matches the Figma:
//
//   • Full-bleed hero — course cover (or an azure gradient fallback) with
//     the title overlaid at the bottom.
//   • Instructor row — avatar with initials, name, ★ rating.
//   • Three feature bullets with green checkmarks.
//   • A gold-bordered card pinned to the bottom. When not enrolled it hosts
//     the request/approval flow (note composer + "Request to Enroll"); once
//     a PENDING request exists it flips to edit/withdraw; when enrolled it
//     swaps to a "Continue Learning" CTA.
//
// Hosts present this with `.presentationDetents([.fraction(0.72), .large])`
// and a platform drag indicator, so the sheet chrome comes from the system.

struct CourseDetailSheetView: View {
    let courseId: String
    let onClose: () -> Void
    /// When non-nil the sheet is in pre-login preview mode: the course loads
    /// via the public endpoint and the enroll CTA calls this to route the
    /// guest to sign-in instead of opening the request composer.
    let onRequireLogin: (() -> Void)?

    @StateObject private var viewModel: CourseDetailViewModel
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    /// Gates the enrollment-approval poll: it must not tick while the app is
    /// backgrounded (or sitting inactive in the switcher).
    @Environment(\.scenePhase) private var scenePhase
    @State private var openingCourseDetail: Bool = false

    // Request-composer state (not-enrolled body).
    @State private var note: String = ""
    @State private var requesting: Bool = false
    @State private var requestError: String? = nil
    @FocusState private var noteFocused: Bool

    // Edit/withdraw sheet for an existing PENDING request.
    @State private var showEditSheet: Bool = false
    /// Set when the approval lands while the edit sheet is still up. The push
    /// has to wait for the sheet's dismissal to finish — see its `onDismiss`.
    @State private var openCourseAfterEditSheetDismiss: Bool = false

    private let maxNote: Int = 500

    init(courseId: String,
         viewModelOverride: CourseDetailViewModel? = nil,
         onRequireLogin: (() -> Void)? = nil,
         onClose: @escaping () -> Void) {
        self.courseId = courseId
        self.onClose = onClose
        self.onRequireLogin = onRequireLogin
        _viewModel = StateObject(
            wrappedValue: viewModelOverride
                ?? CourseDetailViewModel(courseId: courseId, guest: onRequireLogin != nil))
    }

    private var ar: Bool { appLocale == "ar" }
    /// Hidden for now (2026-07): reviews/ratings paused platform-wide.
    private var hideReviews: Bool { true }
    /// Pre-login preview mode — drives a single "Sign in to enrol" CTA.
    private var isGuest: Bool { onRequireLogin != nil }
    private var overLimit: Bool { note.count > maxNote }

    // Figma tokens that don't have an app-wide constant.
    private let cardBg = MyCoursesPalette.surface   // was #0E0E10
    private let buttonText = Color(red: 0x1A / 255.0, green: 0x13 / 255.0, blue: 0x05 / 255.0)

    var body: some View {
        NavigationStack {
            ZStack {
                AuthFigmaColors.bg.ignoresSafeArea()

                if viewModel.isLoading {
                    skeleton
                } else if let err = viewModel.errorMessage, viewModel.course == nil {
                    ErrorBanner(message: err) {
                        Task { await viewModel.load() }
                    }
                    .padding(.horizontal, 24)
                } else if let course = viewModel.course {
                    content(course)
                }
            }
            .overlay(alignment: .topTrailing) { closeButton }
            .navigationDestination(isPresented: $openingCourseDetail) {
                CourseDetailView(courseId: courseId)
            }
        }
        .task { await viewModel.load() }
        // Approval polling is only allowed to run while this sheet is on
        // screen AND the app is in the foreground. `.onAppear` marks the
        // screen live and does an immediate catch-up poll; `.onDisappear`
        // cancels the task so it can't outlive the sheet. Both hooks are
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
        // Instructor approved while the "Request sent." card was up: tear
        // down any note-edit sheet and auto-route straight to the course
        // page. Fires once — the view model latches `approvalDetected`, and
        // it only flips after the enrollment state has been refreshed, so
        // the pushed course screen renders as enrolled.
        .onChange(of: viewModel.approvalDetected) { detected in
            guard detected else { return }
            // With no sheet up the push can go straight through.
            guard showEditSheet else { openingCourseDetail = true; return }
            // Otherwise it must not ride the same transaction as the
            // dismissal: SwiftUI tears the sheet down and silently drops a
            // navigation activation made in that same update, leaving the
            // student on the "Request sent." card. Defer to `onDismiss`.
            openCourseAfterEditSheetDismiss = true
            showEditSheet = false
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ course: CourseDetail) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                hero(course)

                VStack(alignment: .leading, spacing: 16) {
                    instructorRow(course)
                    featuresList(course)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 16)
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomCard(course)
        }
        // `onDismiss` runs once the sheet is actually gone, so the deferred
        // approval push is a separate update from the dismissal. The extra
        // main-queue hop gives the navigation stack a runloop turn of its own
        // — activating the destination from inside the dismissal's own update
        // is the very thing that loses the push.
        .sheet(isPresented: $showEditSheet, onDismiss: {
            guard openCourseAfterEditSheetDismiss else { return }
            openCourseAfterEditSheetDismiss = false
            DispatchQueue.main.async { openingCourseDetail = true }
        }) {
            editSheetContent(course)
        }
    }

    // Edit/withdraw the existing PENDING request. Reuses the shared
    // RequestEnrollmentSheet in `.edit` mode, matching CourseDetailView.
    @ViewBuilder
    private func editSheetContent(_ course: CourseDetail) -> some View {
        let sheet = RequestEnrollmentSheet(
            mode: .edit,
            courseTitle: course.localizedTitle(locale: appLocale),
            instructorName: course.instructorName,
            coverUrl: course.coverUrl,
            existingNote: viewModel.pendingRequest?.note,
            onSubmit: { note in
                await viewModel.editPendingNote(note: note) ? .saved : .failed
            },
            onCancelRequest: { await viewModel.cancelPendingRequest() },
            onClose: { showEditSheet = false })

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

    // MARK: - Close

    /// Only drawn when this screen is presented as a cover (iPad). A cover has
    /// no drag-to-dismiss, so without this the student is stuck — and it has to
    /// sit on the whole screen rather than on the hero, or a course that fails
    /// to load leaves nothing to tap. On iPhone the sheet's own grabber does
    /// the job and the Figma layout stays untouched.
    @ViewBuilder
    private var closeButton: some View {
        if CoursePresentation.isCover {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(MyCoursesPalette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.horizontal, 16)
            .accessibilityLabel(Text(L10n.close))
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private func hero(_ course: CourseDetail) -> some View {
        ZStack(alignment: .bottomLeading) {
            // A fixed-size Color.clear drives the hero's layout; the cover rides
            // on top as an overlay so a wide/large `scaledToFill` cover can't
            // leak its scaled width into the ScrollView and stretch the sheet.
            // `.clipped()` trims the overflow. (The azure gradient fallback is
            // already flexible, so only the image path needed containing.)
            Color.clear
                .frame(height: 224)
                .frame(maxWidth: .infinity)
                .overlay(
                    Group {
                        if let url = course.coverUrl.flatMap(URL.init(string:)) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: azureGradient
                                }
                            }
                        } else {
                            azureGradient
                        }
                    }
                )
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center, endPoint: .bottom)
                .frame(height: 224)
                .allowsHitTesting(false)

            Text(course.localizedTitle(locale: appLocale))
                .font(BrandFont.displaySemiBold(size: 30, isArabic: ar))
                .tracking(ar ? 0 : -0.9)
                .foregroundColor(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
        }
        .frame(height: 224)
        .frame(maxWidth: .infinity)
    }

    private var azureGradient: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color(red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0), location: 0.0),
                .init(color: Color(red: 0x1A / 255.0, green: 0x4F / 255.0, blue: 0xA0 / 255.0), location: 0.6),
                .init(color: Color(red: 0x0A / 255.0, green: 0x2D / 255.0, blue: 0x6B / 255.0), location: 1.0)
            ]),
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Instructor row

    private func instructorRow(_ course: CourseDetail) -> some View {
        HStack(spacing: 11) {
            avatar(course)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.instructorName)
                    .font(BrandFont.displaySemiBold(size: 16, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.textPrimary)
                    .lineLimit(1)
                // Hidden for now (2026-07): reviews/ratings paused platform-wide.
                if !hideReviews, let r = course.ratingAvg {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AuthFigmaColors.gold)
                        Text(formattedRating(r))
                            .font(BrandFont.displaySemiBold(size: 12, isArabic: ar))
                            .foregroundColor(AuthFigmaColors.textPrimary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func avatar(_ course: CourseDetail) -> some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [
                        Color(red: 0xBF / 255.0, green: 0x5A / 255.0, blue: 0xF2 / 255.0),
                        Color(red: 0x7C / 255.0, green: 0x2F / 255.0, blue: 0xA0 / 255.0)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(instructorInitials(course.instructorName))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            // Presigned avatar loads over the gradient initials disc and
            // replaces it on success; any other phase keeps the fallback.
            if let url = course.instructorAvatarUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.clear
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(Circle())
            }
        }
        .frame(width: 38, height: 38)
    }

    // MARK: - Feature bullets

    private func featuresList(_ course: CourseDetail) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            let hours = max(1, course.totalDurationMinutes / 60)
            featureRow(String(
                format: L10n.courseDetailSheetVideoLessonsHoursFmt,
                course.lessonCount, hours))
        }
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AuthFigmaColors.successGreen)
            Text(text)
                .font(BrandFont.display(size: 14.5, isArabic: ar))
                .foregroundColor(AuthFigmaColors.textPrimary.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Bottom card

    @ViewBuilder
    private func bottomCard(_ course: CourseDetail) -> some View {
        Group {
            if isGuest {
                guestCard
            } else if course.enrolled {
                continueCard
            } else if viewModel.pendingRequest != nil {
                requestSentCard
            } else {
                requestCard(course)
            }
        }
        .frame(maxWidth: .infinity)
        .background(cardBg)
        .clipShape(.rect(topLeadingRadius: 26, topTrailingRadius: 26))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                .stroke(AuthFigmaColors.gold.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.85), radius: 30, y: -12)
        .shadow(color: AuthFigmaColors.gold.opacity(0.08), radius: 40)
    }

    // Not-enrolled, no pending request — request composer.
    private func requestCard(_ course: CourseDetail) -> some View {
        let firstName = instructorFirstName(course.instructorName)
        return VStack(alignment: .leading, spacing: 0) {
            // A REJECTED / CANCELLED decision found by the approval poll:
            // reflected in place, above the composer, so the student can
            // simply request again. Deliberately never navigates.
            if let decision = viewModel.requestDecision {
                Text(decision == .rejected
                     ? L10n.enrollRequestDecisionRejected
                     : L10n.enrollRequestDecisionCancelled)
                    .font(BrandFont.display(size: 12.5, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.enrollRequestRequestToEnroll)
                    .font(BrandFont.displaySemiBold(size: 22, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.gold)
                Text(String(format: L10n.enrollRequestSubtitlePersonalFmt, firstName))
                    .font(BrandFont.display(size: 12.5, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.textPrimary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 14)

            HStack {
                Text(String(format: L10n.enrollRequestNoteToFmt, firstName).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(AuthFigmaColors.gold)
                Spacer()
                Text(bidiJoin("\(note.count)", "\(maxNote)", separator: " / "))
                    .font(BrandFont.display(size: 10.5, isArabic: ar))
                    .foregroundColor(overLimit
                                     ? AuthFigmaColors.errorRed
                                     : AuthFigmaColors.textPrimary.opacity(0.4))
            }
            .padding(.bottom, 7)

            noteEditor

            if let err = requestError {
                Text(err)
                    .font(BrandFont.display(size: 12, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.errorRed)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }

            Button(action: { Task { await submitRequest() } }) {
                HStack(spacing: 7) {
                    if requesting {
                        ProgressView().tint(buttonText)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(L10n.enrollRequestRequestToEnroll)
                        .font(BrandFont.displaySemiBold(size: 14, isArabic: ar))
                }
                .foregroundColor(buttonText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(LinearGradient.droobButtonGradient.opacity(submitDisabled ? 0.5 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: AuthFigmaColors.gold.opacity(0.25), radius: 10, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(submitDisabled)
            .padding(.top, 14)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var submitDisabled: Bool { requesting || overLimit }

    // Pending request — "Request sent." confirmation (Figma node 1994-6103).
    private var requestSentCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AuthFigmaColors.successGreen)
                Text(L10n.enrollRequestSentBanner)
                    .font(BrandFont.displaySemiBold(size: 15, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.successGreen)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(AuthFigmaColors.successGreen.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AuthFigmaColors.successGreen.opacity(0.5), lineWidth: 1))

            Button(action: { showEditSheet = true }) {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.instructorProfileEditNote)
                        .font(BrandFont.displaySemiBold(size: 16, isArabic: ar))
                }
                .foregroundColor(buttonText)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(LinearGradient.droobButtonGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: AuthFigmaColors.gold.opacity(0.25), radius: 10, y: 6)
            }
            .buttonStyle(.plain)

            // The poll gives up after its ceiling (an instructor may take a
            // day) — hand the student a manual refresh rather than leaving
            // them on a card that will never update on its own.
            if viewModel.approvalPollGaveUp {
                HStack(spacing: 6) {
                    Text(L10n.enrollRequestPollStoppedHint)
                        .font(BrandFont.display(size: 12, isArabic: ar))
                        .foregroundColor(AuthFigmaColors.textPrimary.opacity(0.5))
                    Button(action: { Task { await viewModel.checkApprovalNow() } }) {
                        Text(L10n.enrollRequestCheckNow)
                            .font(BrandFont.displaySemiBold(size: 12, isArabic: ar))
                            .foregroundColor(AuthFigmaColors.gold)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var noteEditor: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        ZStack(alignment: .topLeading) {
            TextEditor(text: $note)
                .focused($noteFocused)
                .modifier(SheetHiddenScrollBackground())
                .frame(height: 118)
                .font(BrandFont.display(size: 13, isArabic: ar))
                .foregroundColor(AuthFigmaColors.textPrimary.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)

            if note.isEmpty {
                Text(L10n.enrollRequestNotePlaceholder)
                    .font(BrandFont.display(size: 13, isArabic: ar))
                    .foregroundColor(AuthFigmaColors.textPrimary.opacity(0.4))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .allowsHitTesting(false)
            }
        }
        .background(MyCoursesPalette.surfaceRaised)
        .clipShape(shape)
        .overlay(shape.stroke(
            overLimit ? AuthFigmaColors.errorRed : AuthFigmaColors.gold.opacity(0.35),
            lineWidth: 1))
    }

    // Pre-login preview — a single CTA that sends the guest to sign-in.
    // Enrolment (and progress/streaming) are account-based, so they live
    // behind authentication; browsing/previewing the course does not.
    private var guestCard: some View {
        VStack(spacing: 10) {
            Button(action: { onRequireLogin?() }) {
                Text(L10n.courseGuestSignInToEnroll)
                    .font(BrandFont.displaySemiBold(size: 17, isArabic: ar))
                    .foregroundColor(buttonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(LinearGradient.droobButtonGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Text(L10n.courseGuestPreviewHint)
                .font(BrandFont.display(size: 12, isArabic: ar))
                .foregroundColor(AuthFigmaColors.textPrimary.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // Enrolled — Continue Learning CTA.
    private var continueCard: some View {
        Button(action: { openingCourseDetail = true }) {
            Text("\(L10n.myCoursesContinueLearning) →")
                .font(BrandFont.displaySemiBold(size: 17, isArabic: ar))
                .foregroundColor(buttonText)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(LinearGradient.droobButtonGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Actions

    private func submitRequest() async {
        guard !submitDisabled else { return }
        requesting = true
        requestError = nil
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: String? = trimmed.isEmpty ? nil : trimmed
        let result = await viewModel.requestEnrollment(note: payload)
        requesting = false
        switch result {
        case .autoEnrolled:
            // Backend auto-approved (testing): the student is enrolled now, so
            // close this Explore sheet and land on the Courses tab's Enrolled
            // list rather than flipping to a "Request Pending" card.
            noteFocused = false
            onClose()
            NotificationCenter.default.post(
                name: .droobOpenEnrolledCourses, object: nil)
        case .requestSent, .saved:
            noteFocused = false
        case .failed:
            requestError = viewModel.errorMessage ?? L10n.coursesGenericError
        }
    }

    // MARK: - Helpers

    private func formattedRating(_ r: Double) -> String {
        String(format: "%.1f", r)
    }

    private func instructorFirstName(_ name: String) -> String {
        let honorifics: Set<String> = ["dr", "dr.", "prof", "prof.", "mr", "mr.",
                                       "mrs", "mrs.", "ms", "ms.", "د", "د.", "أ", "أ."]
        let tokens = name.split(separator: " ").map(String.init)
        let firstReal = tokens.first { !honorifics.contains($0.lowercased()) }
        return firstReal ?? tokens.first ?? name
    }

    private func instructorInitials(_ name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }

    // MARK: - Skeleton

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 18) {
            MCSkeletonBlock(height: 224, cornerRadius: 0)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 11) {
                    MCSkeletonBlock(height: 38, cornerRadius: 19, width: 38)
                    VStack(alignment: .leading, spacing: 6) {
                        MCSkeletonBlock(height: 14, cornerRadius: 4, width: 160)
                        MCSkeletonBlock(height: 10, cornerRadius: 3, width: 60)
                    }
                    Spacer()
                }
                ForEach(0..<3, id: \.self) { _ in
                    MCSkeletonBlock(height: 14, cornerRadius: 4)
                }
            }
            .padding(.horizontal, 22)
            Spacer()
        }
    }
}

// MARK: - Scroll background helper

private struct SheetHiddenScrollBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

// MARK: - Adaptive presentation
//
// iPhone keeps the Figma bottom sheet. iPad deliberately does not, and the
// reason is not cosmetic: a page/form sheet is a *smaller presentation
// container* than the window, and every descendant is laid out inside it.
// The whole course flow lives in this screen's NavigationStack — course
// detail, curriculum, and the lesson player — so on iPad the player's
// fullscreen toggle (which is a `maxHeight: .infinity` + `ignoresSafeArea`
// expansion, not a presentation of its own) could only ever fill the card it
// was sitting in. Presenting as a cover makes the window the container again,
// and the player's existing fullscreen layout covers the actual screen.

enum CoursePresentation {
    /// iPad presents the course as a full-screen cover; iPhone keeps the sheet.
    static var isCover: Bool { UIDevice.current.userInterfaceIdiom == .pad }
}

extension View {
    /// Presents the course screen the way the current device wants it —
    /// `.sheet` on iPhone, `.fullScreenCover` on iPad. Same call shape as
    /// `.sheet(item:onDismiss:content:)` so call sites only swap the name.
    @ViewBuilder
    func coursePresentation<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        if CoursePresentation.isCover {
            fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        } else {
            sheet(item: item, onDismiss: onDismiss, content: content)
        }
    }

    /// The sheet chrome the phone presentation wants and the iPad cover must
    /// not get: detents are inert on a cover, and a drag indicator would
    /// advertise a drag-to-dismiss that a cover doesn't have (the screen draws
    /// its own close button in that case instead).
    @ViewBuilder
    func adaptiveSheetChrome(background: Color) -> some View {
        if CoursePresentation.isCover {
            self
        } else if #available(iOS 16.4, *) {
            self
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(background)
        } else {
            self
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}
