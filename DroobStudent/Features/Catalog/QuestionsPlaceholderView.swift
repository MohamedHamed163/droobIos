import SwiftUI

// MARK: - All Questions screen
//
// Full Q&A list for a course — pushed from the inline preview on the
// course detail screen (both the "See all N questions" link and the
// "Ask a Question" CTA land here). Matches the Figma layout: custom
// gold back button, big "Q&A" title with "{course} · {N} questions"
// subtitle, a compose row at the top, four filter chips, and a single
// grouped surface card containing the question rows with dividers and
// a per-row status pill.
//
// The file keeps its original name (`QuestionsPlaceholderView.swift`)
// so the existing pbxproj entry continues to find the type without a
// project rename — only the type inside has been replaced. Older call
// sites referenced `QuestionsPlaceholderView` directly; both names
// are kept here for backwards compatibility.

struct AllQuestionsView: View {
    let courseId: String
    let courseTitle: String

    @StateObject private var viewModel: QuestionsViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @State private var showAskSheet = false

    private var ar: Bool { appLocale == "ar" }

    init(courseId: String, courseTitle: String,
         viewModelOverride: QuestionsViewModel? = nil) {
        self.courseId = courseId
        self.courseTitle = courseTitle
        _viewModel = StateObject(
            wrappedValue: viewModelOverride ?? QuestionsViewModel(courseId: courseId))
    }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    headerBlock
                    askRow
                    filterChipRow
                    questionsList
                    paginationSentinel
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.loadInitial() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if viewModel.questions.isEmpty {
                await viewModel.loadInitial()
            }
        }
        .sheet(isPresented: $showAskSheet) {
            AskQuestionSheet(
                onSubmit: { body in await viewModel.submit(body: body) },
                onClose: { showAskSheet = false })
        }
    }

    // MARK: Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: ar ? "chevron.right" : "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.tabCourses)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(Color.droobGold)
            }
            .buttonStyle(.plain)

            Text(L10n.courseDetailQaTitle)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.primary)

            Text(String(format: L10n.qaScreenSubtitleFmt,
                        courseTitle.bidiIsolated, viewModel.totalCount))
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .padding(.top, 12)
    }

    // MARK: Compose row

    private var askRow: some View {
        Button { showAskSheet = true } label: {
            HStack(spacing: 12) {
                ReviewAvatar(name: L10n.profile)
                    .frame(width: 28, height: 28)
                Text(L10n.qaScreenAskPlaceholder)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(MyCoursesPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MyCoursesPalette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Filter chips

    private var filterChipRow: some View {
        // Horizontally scrolling so the four chips fit on small
        // screens; on standard iPhones the row sits comfortably
        // without scrolling.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(QuestionsFilter.allCases, id: \.self) { f in
                    chip(label: f.label, isActive: viewModel.filter == f) {
                        Task { await viewModel.applyFilter(f) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isActive
                                 ? Color(red: 0.08, green: 0.06, blue: 0.04)
                                 : MyCoursesPalette.muted)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        isActive
                        ? AnyShapeStyle(LinearGradient.droobBrand)
                        : AnyShapeStyle(MyCoursesPalette.surface)
                    )
                )
                .overlay(
                    Capsule().stroke(
                        isActive ? Color.clear : MyCoursesPalette.stroke,
                        lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: List

    @ViewBuilder
    private var questionsList: some View {
        if viewModel.isLoading && viewModel.questions.isEmpty {
            VStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    MCSkeletonBlock(height: 140, cornerRadius: 14)
                }
            }
        } else if let err = viewModel.errorMessage, viewModel.questions.isEmpty {
            ErrorBanner(message: err) {
                Task { await viewModel.loadInitial() }
            }
        } else if viewModel.questions.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.questions.enumerated()), id: \.element.id) { idx, q in
                    QuestionFullCard(question: q, locale: appLocale)
                        .padding(16)
                    if idx < viewModel.questions.count - 1 {
                        Rectangle()
                            .fill(MyCoursesPalette.stroke)
                            .frame(height: 1)
                    }
                }
            }
            .background(MyCoursesPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MyCoursesPalette.stroke, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var paginationSentinel: some View {
        if viewModel.hasNextPage {
            HStack {
                Spacer()
                ProgressView()
                    .tint(Color.droobGold)
                    .padding(.vertical, 14)
                    .onAppear {
                        Task { await viewModel.loadMore() }
                    }
                Spacer()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundColor(MyCoursesPalette.muted)
            Text(L10n.qaEmptyState)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Question card (full screen)
//
// Larger and a touch more detailed than the inline preview card on the
// detail screen: the trailing status pill ("✓ Answered" green or
// "Unanswered" muted) is unique to this screen, the instructor reply
// nest uses a slightly different chrome (no left bar — just a tinted
// surface and the instructor's gold name), and the footer is just the
// compact relative time (no upvotes string).

struct QuestionFullCard: View {
    let question: CourseQuestionItem
    let locale: String

    private var ar: Bool { locale == "ar" }

    /// Full instructor thread, oldest-first. Falls back to the singular
    /// `instructorAnswer` so an older backend that only sends the latest
    /// reply still renders one card.
    private var answers: [CourseAnswerItem] {
        if !question.instructorAnswers.isEmpty {
            return question.instructorAnswers
        }
        if let latest = question.instructorAnswer {
            return [latest]
        }
        return []
    }

    private var isAnswered: Bool { !answers.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ReviewAvatar(name: question.authorName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(question.authorName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(QaAgeFormatter.relative(from: question.createdAt, locale: locale))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(MyCoursesPalette.muted)
                }
                Spacer(minLength: 8)
                statusPill
            }
            Text(question.body)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(answers) { answer in
                instructorReply(answer)
            }
        }
    }

    private var statusPill: some View {
        Text(isAnswered ? L10n.qaStatusAnswered : L10n.qaStatusUnanswered)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(isAnswered ? MyCoursesPalette.success : MyCoursesPalette.muted)
    }

    private func instructorReply(_ answer: CourseAnswerItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ReviewAvatar(name: answer.authorName)
                    .frame(width: 24, height: 24)
                Text(answer.authorName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 6)
                Text(QaAgeFormatter.relative(from: answer.createdAt, locale: locale))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            Text(answer.body)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(MyCoursesPalette.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }
}

// MARK: - Ask sheet
//
// Modal composer reached from the "Ask a question…" row at the top of
// the Q&A screen (also from the "Ask a Question" CTA below the inline
// Q&A card on the detail screen). Keeps the layout small — title +
// large multi-line text area + post button. Disables the button while
// the text is blank so the user can't fire an invalid request.

struct AskQuestionSheet: View {
    let onSubmit: (String) async -> Bool
    let onClose: () -> Void

    @State private var text: String = ""
    @State private var submitting = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                header
                ZStack(alignment: .topLeading) {
                    if #available(iOS 16.0, *) {
                        TextEditor(text: $text)
                            .scrollContentBackground(.hidden)
                            .background(MyCoursesPalette.surface)
                            .frame(minHeight: 160)
                            .padding(10)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.primary)
                    } else {
                        TextEditor(text: $text)
                            .frame(minHeight: 160)
                            .padding(10)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.primary)
                    }
                    if text.isEmpty {
                        Text(L10n.qaAskSheetPlaceholder)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(MyCoursesPalette.muted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .background(MyCoursesPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.red)
                }
                Spacer(minLength: 8)
                submitButton
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Text(L10n.qaAskSheetTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
                    .frame(width: 32, height: 32)
                    .background(MyCoursesPalette.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var submitButton: some View {
        Button {
            Task { await run() }
        } label: {
            HStack(spacing: 8) {
                if submitting {
                    ProgressView()
                        .tint(Color(red: 0.08, green: 0.06, blue: 0.04))
                }
                Text(L10n.qaAskSheetSubmit)
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient.droobBrand
                    .opacity(disabled ? 0.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var disabled: Bool {
        submitting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func run() async {
        guard !disabled else { return }
        submitting = true
        errorMessage = nil
        let ok = await onSubmit(text)
        submitting = false
        if ok {
            onClose()
        } else {
            errorMessage = L10n.coursesGenericError
        }
    }
}

// MARK: - Legacy alias
//
// The file keeps its historical name so the Xcode project reference
// doesn't need a rename. Older call sites referenced
// `QuestionsPlaceholderView` directly — alias preserved for source
// compatibility while we migrate.

struct QuestionsPlaceholderView: View {
    let courseId: String
    let courseTitle: String

    var body: some View {
        AllQuestionsView(courseId: courseId, courseTitle: courseTitle)
    }
}
