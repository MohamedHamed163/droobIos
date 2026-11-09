import SwiftUI

// MARK: - Entry point

/// Section-quiz entry. Owns the {@link QuizViewModel} and switches between
/// intro / playing / finishing / result / review subviews. Pass-through
/// the section title for the back-button header on the intro screen.
struct QuizView: View {
    let courseId: String
    let quizId: String
    let sectionId: String
    let sectionTitleEn: String
    let sectionTitleAr: String

    @StateObject private var vm: QuizViewModel
    @EnvironmentObject private var auth: AuthSession
    @Environment(\.appLocale) private var locale
    @Environment(\.dismiss) private var dismiss

    init(courseId: String, quizId: String, sectionId: String, sectionTitleEn: String, sectionTitleAr: String) {
        self.courseId = courseId
        self.quizId = quizId
        self.sectionId = sectionId
        self.sectionTitleEn = sectionTitleEn
        self.sectionTitleAr = sectionTitleAr
        _vm = StateObject(wrappedValue: QuizViewModel(
            courseId: courseId, quizId: quizId, sectionId: sectionId,
            displayName: AuthSession.shared.currentUser?.displayName))
    }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.summary == nil { await vm.loadSummary() } }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .intro:
            QuizIntroView(vm: vm, locale: locale, onDismiss: { dismiss() })
        case .playing:
            QuizPlayView(vm: vm, locale: locale, onDismiss: { dismiss() })
        case .confirmSubmit:
            QuizConfirmSubmitView(vm: vm, locale: locale)
        case .finishing:
            QuizFinishingView(vm: vm, locale: locale, onDismiss: { dismiss() })
        case .result:
            QuizResultView(vm: vm, locale: locale, onExit: { dismiss() })
        case .pastGrades:
            QuizPastGradesView(vm: vm, locale: locale, onBack: { vm.backToIntroFromPastGrades() })
        case .reviewList:
            QuizReviewListView(vm: vm, locale: locale)
        case .reviewDetail(let idx):
            QuizReviewDetailView(vm: vm, locale: locale, startIndex: idx, onExit: { dismiss() })
        }
    }
}

// MARK: - Shared header

private struct QuizTopBar: View {
    let title: String
    let trailing: String?
    let onBack: () -> Void
    let titleColor: Color
    let trailingColor: Color

    var body: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.accent)
                        .frame(width: 44, height: 38)
                }
                .buttonStyle(.plain)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(trailingColor)
                        .padding(.trailing, 16)
                }
            }
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(titleColor)
        }
        .frame(height: 38)
        .padding(.top, 14)
    }
}

private struct QuizMcqPill: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.square")
                .font(.system(size: 9, weight: .bold))
            Text(L10n.quizMcq)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
        }
        .foregroundColor(MyCoursesPalette.accent)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.droobGold.opacity(0.10))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(MyCoursesPalette.accent.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Numbered circle progress (shared by play, finishing, review detail)

/// Visual state for a single numbered-progress circle. The Figma board uses
/// gold for play, and green/red for the review-detail view.
private enum QuizCircleState {
    case submitted          // gold filled — answered & locked
    case current            // gold outline — active, not yet locked
    case future             // dim outline — not visited
    case correct            // green filled — review-detail outcome
    case wrong              // red filled — review-detail outcome
}

/// Note the two golds. `.submitted` is a *solid gold chip* — gold is the fill
/// and the number on it is near-black, which reads in either color scheme, so
/// it stays `.droobGold`. `.current` is the opposite: an outline and a number
/// *drawn on the page*, i.e. gold as ink, which is unreadable on the light
/// surface — those take the adaptive `accent` instead. The 8% wash behind
/// `.current` is a fill and stays put.
private struct QuizCircle: View {
    let number: Int
    let state: QuizCircleState

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Circle().strokeBorder(stroke, lineWidth: borderWidth)
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(textColor)
        }
        .frame(width: 32, height: 32)
    }

    private var fill: Color {
        switch state {
        case .submitted: return Color.droobGold
        case .current:   return Color.droobGold.opacity(0.08)
        case .future:    return MyCoursesPalette.surface
        case .correct:   return MyCoursesPalette.success
        case .wrong:     return Color(red: 0.85, green: 0.28, blue: 0.22)
        }
    }
    private var stroke: Color {
        switch state {
        case .submitted: return Color.droobGold
        case .current:   return MyCoursesPalette.accent
        case .future:    return MyCoursesPalette.stroke
        case .correct:   return MyCoursesPalette.success
        case .wrong:     return Color(red: 0.85, green: 0.28, blue: 0.22)
        }
    }
    private var borderWidth: CGFloat {
        switch state {
        case .current: return 1.5
        default:       return 1
        }
    }
    private var textColor: Color {
        switch state {
        case .submitted: return Color(red: 0.10, green: 0.07, blue: 0.04)
        case .current:   return MyCoursesPalette.accent
        case .future:    return MyCoursesPalette.muted
        case .correct, .wrong: return .white
        }
    }
}

/// Horizontally-scrolling numbered circles with a trailing chevron when there
/// is more content off-screen. Used during play, finishing and review-detail.
///
/// When `onTap` is supplied (play + review-detail) each circle becomes a button
/// that jumps to that question, and the row auto-scrolls to keep `current`
/// centered as the student navigates by swipe or tap.
private struct QuizNumberedProgress: View {
    let count: Int
    let stateFor: (Int) -> QuizCircleState
    var current: Int? = nil
    var onTap: ((Int) -> Void)? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<count, id: \.self) { i in
                        circle(i)
                            .id(i)
                    }
                    if count > 8 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.muted)
                            .padding(.leading, 2)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear {
                if let current { proxy.scrollTo(current, anchor: .center) }
            }
            .onChange(of: current) { val in
                guard let val else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(val, anchor: .center)
                }
            }
        }
        .frame(height: 38)
    }

    @ViewBuilder
    private func circle(_ i: Int) -> some View {
        if let onTap {
            Button { onTap(i) } label: {
                QuizCircle(number: i + 1, state: stateFor(i))
            }
            .buttonStyle(.plain)
        } else {
            QuizCircle(number: i + 1, state: stateFor(i))
        }
    }
}

// MARK: - Intro

private struct QuizIntroView: View {
    @ObservedObject var vm: QuizViewModel
    let locale: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            QuizTopBar(
                title: L10n.quizNavTitle,
                trailing: nil,
                onBack: onDismiss,
                titleColor: MyCoursesPalette.accent,
                trailingColor: .clear
            )

            if vm.isLoadingSummary {
                Spacer(); ProgressView().tint(MyCoursesPalette.accent); Spacer()
            } else if let error = vm.summaryError {
                Spacer(); Text(error).foregroundColor(.red).padding(); Spacer()
            } else if let summary = vm.summary {
                introContent(summary: summary)
            }
        }
    }

    private func introContent(summary: QuizSummary) -> some View {
        let hasPrior = summary.bestScorePct != nil
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    Spacer().frame(height: 28)

                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 44))
                        .foregroundColor(MyCoursesPalette.accent)
                        .frame(maxWidth: .infinity)

                    Text(L10n.localized(locale, ar: summary.titleAr, en: summary.titleEn))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .multilineTextAlignment(.center)

                    let desc = L10n.localized(locale, ar: summary.descriptionAr, en: summary.descriptionEn)
                    if !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(MyCoursesPalette.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Figma: MCQ pill only appears for the has-prior state.
                    if hasPrior {
                        QuizMcqPill()
                    }

                    VStack(spacing: 0) {
                        statRow(label: L10n.quizQuestions, value: "\(summary.questionCount)")
                        if let best = summary.bestScorePct {
                            Divider().background(MyCoursesPalette.stroke)
                            statRow(label: L10n.quizBestScore, value: "\(Int(best))%")
                        }
                    }
                    .background(MyCoursesPalette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)

                    Spacer().frame(height: 12)
                }
            }

            VStack(spacing: 12) {
                // No attempt limit — students can take the quiz as many times
                // as they need, so the start/retake button is always enabled.
                Button {
                    Task { await vm.startQuiz() }
                } label: {
                    HStack(spacing: 6) {
                        if hasPrior {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text(hasPrior ? L10n.quizRetake : L10n.quizStart)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(LinearGradient.droobBrand)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vm.isStarting)

                // Figma: secondary CTA only renders for the has-prior state.
                if hasPrior {
                    Button { Task { await vm.openPastGrades() } } label: {
                        Text(L10n.quizReviewPastGrades)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(MyCoursesPalette.textPrimary)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(MyCoursesPalette.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(MyCoursesPalette.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(MyCoursesPalette.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Play (submit-per-question + skip)

private struct QuizPlayView: View {
    @ObservedObject var vm: QuizViewModel
    let locale: String
    let onDismiss: () -> Void

    var body: some View {
        if vm.questions.isEmpty {
            AnyView(EmptyView())
        } else {
            AnyView(content())
        }
    }

    private func playProgressState(_ idx: Int) -> QuizCircleState {
        let q = vm.questions[idx]
        if idx == vm.currentIndex { return .current }
        if vm.isAnswered(q.id) { return .submitted }
        return .future
    }

    private func content() -> some View {
        VStack(spacing: 0) {
            QuizTopBar(
                title: L10n.quizSectionQuiz,
                trailing: L10n.quizQuestionNOfN(vm.currentIndex + 1, vm.questions.count),
                onBack: onDismiss,
                titleColor: MyCoursesPalette.accent,
                trailingColor: MyCoursesPalette.muted
            )

            // Tappable numbered circles — jump to any question.
            QuizNumberedProgress(
                count: vm.questions.count,
                stateFor: playProgressState,
                current: vm.currentIndex,
                onTap: { vm.goToQuestion($0) }
            )
            .padding(.top, 8)

            // Swipeable pager — free back/forth navigation between questions.
            TabView(selection: $vm.currentIndex) {
                ForEach(0..<vm.questions.count, id: \.self) { i in
                    questionPage(question: vm.questions[i])
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: vm.currentIndex)

            if let q = vm.currentQuestion {
                bottomBar(question: q)
            }
        }
    }

    private func questionPage(question: QuizQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                QuizMcqPill()
                    .padding(.top, 12)

                MathText(
                    source: L10n.localized(locale, ar: question.textAr, en: question.textEn),
                    font: .system(size: 19),
                    fontSize: 19,
                    weight: .bold,
                    color: MyCoursesPalette.textPrimary,
                    isRTL: locale == "ar"
                )

                selectionHint(question: question)

                VStack(spacing: 10) {
                    ForEach(Array(question.options.enumerated()), id: \.element.id) { idx, option in
                        optionRow(question: question, option: option, index: idx)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }

    // Bottom — explicit per-question actions. Selecting an option only updates
    // local state; the answer is recorded only when the student taps "Submit
    // answer". "Skip" advances without recording, so a skipped question is never
    // scored even if an option is still selected. Both route to the
    // review-before-submit screen once the last question is handled.
    private func bottomBar(question: QuizQuestion) -> some View {
        let hasSelection = !vm.selection(for: question.id).isEmpty
        return HStack(spacing: 10) {
            Button { vm.skipCurrent() } label: {
                Text(L10n.quizSkip)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(MyCoursesPalette.surface)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button { vm.submitCurrentAnswer() } label: {
                Text(L10n.quizSubmitAnswer)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(LinearGradient.droobBrand)
                    .clipShape(Capsule())
                    .opacity(hasSelection ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func selectionHint(question: QuizQuestion) -> some View {
        let selected = vm.selection(for: question.id).count
        if question.isMultiChoice {
            if selected == 0 {
                hintRow(icon: "circle", text: L10n.quizTapToSelectMulti, color: MyCoursesPalette.muted)
            } else {
                hintRow(icon: "checkmark.square",
                        text: L10n.quizSelectedOfTotal(selected, question.options.count),
                        color: MyCoursesPalette.accent)
            }
        } else {
            hintRow(icon: "circle", text: L10n.quizTapToSelectSingle, color: MyCoursesPalette.muted)
        }
    }

    private func hintRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).font(.system(size: 12, weight: .regular))
        }
        .foregroundColor(color)
    }

    private func optionRow(question: QuizQuestion, option: QuizOption, index: Int) -> some View {
        let label = ["A","B","C","D","E"][min(index, 4)]
        let text = L10n.localized(locale, ar: option.textAr, en: option.textEn)
        let selected = vm.selection(for: question.id).contains(option.id)

        return Button {
            vm.toggle(optionId: option.id, for: question)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    // A/B/C chip: gold is the fill and the letter on it is
                    // near-black, so this keeps the brand value. The row's
                    // selected outline below is gold as ink on the card and
                    // takes the adaptive accent instead — same ramp, both
                    // legible.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.droobGold : MyCoursesPalette.stroke.opacity(0.6))
                        .frame(width: 24, height: 24)
                    Text(label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(selected
                            ? Color(red: 0.10, green: 0.07, blue: 0.04)
                            : MyCoursesPalette.muted)
                }
                MathText(
                    source: text,
                    font: .system(size: 14),
                    fontSize: 14,
                    weight: .medium,
                    color: MyCoursesPalette.textPrimary,
                    isRTL: locale == "ar"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(MyCoursesPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? MyCoursesPalette.accent : MyCoursesPalette.stroke,
                            lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Review before submit (Ready to submit? / N unanswered)

/// Distinct, explicit final-submission step reached from the play screen's
/// Finish button. Shows answered/skipped counts and only submits the whole
/// attempt via Submit Quiz / Submit anyway — so finishing the quiz is never
/// conflated with answering the last question.
private struct QuizConfirmSubmitView: View {
    @ObservedObject var vm: QuizViewModel
    let locale: String

    private let amber = Color(red: 0.86, green: 0.62, blue: 0.26)

    var body: some View {
        let total = vm.questions.count
        let answered = vm.answeredCount
        let skipped = vm.unansweredCount
        let complete = vm.allAnswered

        return VStack(spacing: 0) {
            QuizTopBar(
                title: L10n.quizSectionQuiz,
                trailing: L10n.quizQuestionNOfN(total, total),
                onBack: { vm.backToPlayFromConfirm() },
                titleColor: MyCoursesPalette.accent,
                trailingColor: MyCoursesPalette.muted
            )

            Spacer()

            VStack(spacing: 18) {
                answeredChip(answered: answered, total: total, skipped: skipped, complete: complete)

                VStack(spacing: 8) {
                    Text(complete ? L10n.quizReadyToSubmit : L10n.quizUnansweredTitle(skipped))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(MyCoursesPalette.accent)
                        .multilineTextAlignment(.center)

                    Text(complete ? L10n.quizAllAnsweredSubtitle(total) : L10n.quizUnansweredSubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(MyCoursesPalette.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                if complete {
                    lookingGoodCard()
                } else {
                    jumpBackCard()
                }

                legend(answered: answered, skipped: skipped, complete: complete)
            }
            .padding(.horizontal, 16)

            Spacer()
            Spacer()

            bottomBar(complete: complete)
        }
    }

    private func answeredChip(answered: Int, total: Int, skipped: Int, complete: Bool) -> some View {
        let numberColor = complete ? MyCoursesPalette.success : amber
        return VStack(spacing: 2) {
            Text(L10n.quizAnswered)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(MyCoursesPalette.muted)
            // Both operands are digits, but the " / " between them is neutral:
            // under the Arabic UI it would otherwise render as "total / answered".
            Text(bidiJoin("\(answered)", "\(total)", separator: " / "))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(numberColor)
            Text(complete ? L10n.quizAllComplete : L10n.quizNSkipped(skipped))
                .font(.system(size: 11))
                .foregroundColor(complete ? MyCoursesPalette.success : MyCoursesPalette.muted)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(numberColor.opacity(0.25), lineWidth: 1))
    }

    private func jumpBackCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .bold))
                Text(L10n.quizJumpBackTo)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
            }
            .foregroundColor(MyCoursesPalette.accent)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.unansweredIndices, id: \.self) { idx in
                        Button { vm.jumpToQuestion(idx) } label: {
                            Text(L10n.quizQuestionLabel(idx + 1))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(MyCoursesPalette.accent)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.droobGold.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(MyCoursesPalette.accent.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.droobGold.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(MyCoursesPalette.accent.opacity(0.40), lineWidth: 1))
    }

    private func lookingGoodCard() -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(MyCoursesPalette.success)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.quizLookingGoodTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.success)
                Text(L10n.quizLookingGoodBody)
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MyCoursesPalette.success.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(MyCoursesPalette.success.opacity(0.35), lineWidth: 1))
    }

    private func legend(answered: Int, skipped: Int, complete: Bool) -> some View {
        HStack(spacing: 14) {
            legendItem(color: MyCoursesPalette.success,
                       text: complete ? L10n.quizAllAnswered : L10n.quizNAnswered(answered))
            if !complete {
                legendItem(color: amber, text: L10n.quizNSkipped(skipped))
            }
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(MyCoursesPalette.muted)
        }
    }

    private func bottomBar(complete: Bool) -> some View {
        HStack(spacing: 10) {
            Button { vm.backToPlayFromConfirm() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                    Text(L10n.quizGoBack)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(MyCoursesPalette.textPrimary)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(MyCoursesPalette.surface)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button { Task { await vm.finishQuiz() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text(complete ? L10n.quizSubmitQuiz : L10n.quizSubmitAnyway)
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(LinearGradient.droobBrand)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}

// MARK: - Finishing screen (keeps header + progress visible above the card)

private struct QuizFinishingView: View {
    @ObservedObject var vm: QuizViewModel
    let locale: String
    let onDismiss: () -> Void
    @State private var spin = false

    private func progressState(_ idx: Int) -> QuizCircleState {
        let q = vm.questions[idx]
        return vm.isAnswered(q.id) ? .submitted : .future
    }

    var body: some View {
        VStack(spacing: 0) {
            QuizTopBar(
                title: L10n.quizSectionQuiz,
                trailing: L10n.quizQuestionNOfN(vm.questions.count, vm.questions.count),
                onBack: onDismiss,
                titleColor: MyCoursesPalette.accent,
                trailingColor: MyCoursesPalette.muted
            )
            QuizNumberedProgress(count: vm.questions.count, stateFor: progressState)
                .padding(.top, 8)

            Spacer()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(MyCoursesPalette.accent.opacity(0.35), lineWidth: 2)
                        .frame(width: 76, height: 76)
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(MyCoursesPalette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 76, height: 76)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: spin)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(MyCoursesPalette.accent)
                }

                Text(L10n.quizFinishingTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(L10n.quizFinishingSubtitle(vm.questions.count))
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)

                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(MyCoursesPalette.accent.opacity(0.6))
                            .frame(width: 5, height: 5)
                            .opacity(spin ? 1 : 0.3)
                            .animation(.easeInOut(duration: 0.6).repeatForever()
                                .delay(0.15 * Double(i)), value: spin)
                    }
                }
                .padding(.top, 4)
            }
            .padding(28)
            .background(MyCoursesPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 30)

            Spacer()
            Spacer()
        }
        .onAppear { spin = true }
    }
}

// MARK: - Result screen (pass / fail / flawless)

struct QuizResultView: View {
    @ObservedObject var vm: QuizViewModel
    let locale: String
    let onExit: () -> Void

    private let passGreen = MyCoursesPalette.success
    private let failRed = Color(red: 0.85, green: 0.28, blue: 0.22)

    var body: some View {
        guard let result = vm.quizResult else { return AnyView(EmptyView()) }
        return AnyView(content(result: result))
    }

    private func ringColor(_ r: QuizResult) -> Color {
        if r.scorePct >= 100 { return passGreen }
        return r.passed ? passGreen : failRed
    }

    private func subtitle(_ r: QuizResult) -> String {
        if r.scorePct >= 100 { return L10n.quizPerfectScore }
        return r.passed ? L10n.quizYouPassed : L10n.quizYouDidntPass
    }

    private func content(result: QuizResult) -> some View {
        VStack(spacing: 0) {
            Text(L10n.quizQuizComplete)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MyCoursesPalette.accent)
                .padding(.top, 22)

            ScrollView {
                VStack(spacing: 22) {
                    Spacer().frame(height: 18)

                    scoreRing(result: result)

                    VStack(spacing: 6) {
                        nameStyledHeadline(result: result)
                        Text(subtitle(result))
                            .font(.system(size: 13))
                            .foregroundColor(MyCoursesPalette.muted)
                    }

                    HStack(spacing: 10) {
                        statTile(value: "\(result.correctCount)", label: L10n.quizCorrect, color: passGreen)
                        statTile(value: "\(result.wrongCount)",   label: L10n.quizWrong,   color: failRed)
                    }
                    .padding(.horizontal, 16)

                    // Figma: Retake button is always present (above Review/Exit).
                    Button {
                        Task { await vm.retake() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 13, weight: .bold))
                            Text(L10n.quizRetake)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(LinearGradient.droobBrand)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    Spacer().frame(height: 8)
                }
                .padding(.top, 14)
                .padding(.bottom, 30)
            }

            // Bottom action row — Review answers + Exit
            HStack(spacing: 10) {
                Button { Task { await vm.openReviewList() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .bold))
                        Text(L10n.quizReviewAnswers)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(MyCoursesPalette.surface)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onExit) {
                    Text(L10n.quizExit)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(LinearGradient.droobBrand)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // Headline copy:
    //   100%  → "Flawless, Name!"  (exclamation)
    //   pass  → "Well done so far, Name"  (no !)
    //   fail  → "Not this time, Name"  (no !)
    // Name (when present) renders in gold italic; the rest in textPrimary serif italic.
    private func nameStyledHeadline(result: QuizResult) -> some View {
        let base: String
        let trailingPunct: String
        if result.scorePct >= 100 {
            base = L10n.quizFlawless
            trailingPunct = "!"
        } else if result.passed {
            base = L10n.quizWellDoneSoFar
            trailingPunct = ""
        } else {
            base = L10n.quizNotThisTime
            trailingPunct = ""
        }
        let nameSuffix: String? = vm.firstName.map { ", \($0)\(trailingPunct)" }
        return Group {
            if let name = nameSuffix {
                (Text(base)
                    .foregroundColor(MyCoursesPalette.textPrimary)
                 + Text(name)
                    .foregroundColor(MyCoursesPalette.accent))
                .font(.system(size: 22, weight: .bold))
            } else {
                Text(base)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
            }
        }
    }

    private func scoreRing(result: QuizResult) -> some View {
        let color = ringColor(result)
        let isFlawless = result.scorePct >= 100
        let isFail = !result.passed
        return ZStack {
            // Decorative dot scatter for the 100% state (gold + green).
            if isFlawless {
                ForEach(0..<6, id: \.self) { i in
                    let positions: [CGPoint] = [
                        CGPoint(x: -90, y: -50),
                        CGPoint(x:  95, y: -50),
                        CGPoint(x:  80, y:  60),
                        CGPoint(x: -85, y:  55),
                        CGPoint(x:   0, y: -95),
                        CGPoint(x:  35, y:  90)
                    ]
                    Circle()
                        .fill(i % 2 == 0 ? MyCoursesPalette.accent : MyCoursesPalette.success)
                        .frame(width: 5, height: 5)
                        .offset(x: positions[i].x, y: positions[i].y)
                }
            }
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 12)
                .frame(width: 200, height: 200)
            Circle()
                .trim(from: 0, to: CGFloat(min(1.0, max(0, result.scorePct / 100))))
                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 200, height: 200)
                .shadow(color: isFail ? color.opacity(0.7) : .clear, radius: 12)
                .shadow(color: isFlawless ? color.opacity(0.5) : .clear, radius: 18)
            VStack(spacing: 2) {
                Text("\(Int(result.scorePct))%")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(L10n.quizScoreOutOf(result.correctCount, result.totalCount))
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.muted)
            }
        }
        .padding(.vertical, 4)
    }

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(MyCoursesPalette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(color.opacity(0.3), lineWidth: 1))
    }
}

private let passGreen = MyCoursesPalette.success
private let failRed   = Color(red: 0.85, green: 0.28, blue: 0.22)

// MARK: - Past grades (prior attempts)

/// Lists the student's prior completed attempts (score, pass/fail, date).
/// Reached from the intro screen's "Review past grades" CTA. Tapping an
/// attempt drills into its full per-question answer review.
struct QuizPastGradesView: View {
    @ObservedObject var vm: QuizViewModel
    let locale: String
    let onBack: () -> Void

    /// Not `static let`: caching for the process would pin whatever locale
    /// happened to be current at first use.
    private static var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.currentLanguageCode)
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if vm.isLoadingAttempts {
                Spacer(); ProgressView().tint(MyCoursesPalette.accent); Spacer()
            } else if let error = vm.attemptsError {
                Spacer()
                Text(error).foregroundColor(.red).multilineTextAlignment(.center).padding()
                Spacer()
            } else if vm.pastAttempts.isEmpty {
                Spacer()
                Text(L10n.quizNoPastAttempts)
                    .font(.system(size: 14))
                    .foregroundColor(MyCoursesPalette.muted)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(vm.pastAttempts) { attempt in
                            Button {
                                Task { await vm.openAttemptReview(attemptId: attempt.attemptId) }
                            } label: {
                                attemptRow(attempt)
                            }
                            .buttonStyle(.plain)
                        }

                        Text(L10n.quizTapToReview)
                            .font(.system(size: 11))
                            .foregroundColor(MyCoursesPalette.muted)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.accent)
                        .frame(width: 44, height: 38)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            Text(L10n.quizPastGradesTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MyCoursesPalette.accent)
        }
        .frame(height: 38)
        .padding(.top, 14)
    }

    private func attemptRow(_ a: QuizAttemptSummary) -> some View {
        let outcomeColor = a.passed ? passGreen : failRed
        return HStack(spacing: 12) {
            // Score chip
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(outcomeColor.opacity(0.12))
                    .frame(width: 56, height: 48)
                Text("\(Int(a.scorePct))%")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(outcomeColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(L10n.quizAttemptNumber(a.attemptNumber))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                    Text(a.passed ? L10n.quizPassedBadge : L10n.quizFailedBadge)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.4)
                        .foregroundColor(outcomeColor)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(outcomeColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                HStack(spacing: 8) {
                    Text(L10n.quizScoreOutOf(a.correctCount, a.totalCount))
                        .font(.system(size: 12))
                        .foregroundColor(MyCoursesPalette.muted)
                    if let date = a.completedAt {
                        Text("·").foregroundColor(MyCoursesPalette.muted)
                        Text(Self.dateFormatter.string(from: date))
                            .font(.system(size: 12))
                            .foregroundColor(MyCoursesPalette.muted)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }
}

// MARK: - Review list

struct QuizReviewListView: View {
    @ObservedObject var vm: QuizViewModel
    let locale: String

    enum Filter { case all, correct, wrong }
    @State private var filter: Filter = .all

    var body: some View {
        VStack(spacing: 0) {
            header

            if vm.isLoadingReview {
                Spacer(); ProgressView().tint(MyCoursesPalette.accent); Spacer()
            } else if let review = vm.review {
                ScrollView {
                    VStack(spacing: 14) {
                        filterChips(review: review)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        VStack(spacing: 10) {
                            ForEach(Array(filtered(review.questions).enumerated()), id: \.element.id) { _, q in
                                Button {
                                    if let originalIdx = review.questions.firstIndex(where: { $0.id == q.id }) {
                                        vm.openReviewDetail(originalIdx)
                                    }
                                } label: {
                                    reviewRow(q: q)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)

                        Text(L10n.quizTapToReview)
                            .font(.system(size: 11))
                            .foregroundColor(MyCoursesPalette.muted)
                            .padding(.top, 8)
                    }
                    .padding(.bottom, 30)
                }
            } else {
                Spacer()
            }
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                Button { vm.backFromReviewList() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.accent)
                        .frame(width: 44, height: 38)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            Text(L10n.quizReviewAnswers)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MyCoursesPalette.accent)
        }
        .frame(height: 38)
        .padding(.top, 14)
    }

    private func filterChips(review: QuizReview) -> some View {
        let correct = review.questions.filter { $0.outcome == "CORRECT" }.count
        let wrong = review.questions.filter { $0.outcome != "CORRECT" }.count
        return HStack(spacing: 8) {
            chip(label: L10n.quizFilterCount(L10n.quizFilterAll, review.questions.count),
                 color: MyCoursesPalette.accent, active: filter == .all) { filter = .all }
            chip(label: L10n.quizFilterCount(L10n.quizFilterCorrect, correct),
                 color: passGreen, active: filter == .correct) { filter = .correct }
            chip(label: L10n.quizFilterCount(L10n.quizFilterWrong, wrong),
                 color: failRed, active: filter == .wrong) { filter = .wrong }
            Spacer()
        }
    }

    private func chip(label: String, color: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(active ? color : MyCoursesPalette.textPrimary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(active ? color.opacity(0.12) : MyCoursesPalette.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(active ? color.opacity(0.4) : MyCoursesPalette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func filtered(_ qs: [QuizReviewQuestion]) -> [QuizReviewQuestion] {
        switch filter {
        case .all: return qs
        case .correct: return qs.filter { $0.outcome == "CORRECT" }
        case .wrong:   return qs.filter { $0.outcome != "CORRECT" }
        }
    }

    private func reviewRow(q: QuizReviewQuestion) -> some View {
        let isCorrect = q.outcome == "CORRECT"
        let text = L10n.localized(locale, ar: q.textAr, en: q.textEn)
        let scoreText = bidiJoin("\(isCorrect ? 1 : 0)", "1", separator: " / ")
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isCorrect ? passGreen : failRed)
                    .frame(width: 30, height: 30)
                Image(systemName: isCorrect ? "checkmark" : "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            // Figma: "Q1 Fundamental React hooks" inline (no stacked label).
            HStack(spacing: 6) {
                Text("Q\(q.sortOrder + 1)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
                Text(mathPlainText(text))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            Text(scoreText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isCorrect ? passGreen : failRed)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }
}

// MARK: - Review detail

struct QuizReviewDetailView: View {
    @ObservedObject var vm: QuizViewModel
    let locale: String
    let startIndex: Int
    let onExit: () -> Void

    @State private var index: Int = 0
    @State private var didInit = false

    private var review: QuizReview? { vm.review }
    private var question: QuizReviewQuestion? {
        guard let review, index >= 0, index < review.questions.count else { return nil }
        return review.questions[index]
    }
    private var isLast: Bool {
        guard let review else { return false }
        return index >= review.questions.count - 1
    }
    private var isFirst: Bool { index <= 0 }

    var body: some View {
        Group {
            if let q = question, let review {
                content(q: q, review: review)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if !didInit { index = startIndex; didInit = true }
        }
    }

    private func reviewProgressState(_ idx: Int) -> QuizCircleState {
        guard let review else { return .future }
        let q = review.questions[idx]
        return q.outcome == "CORRECT" ? .correct : .wrong
    }

    private func content(q: QuizReviewQuestion, review: QuizReview) -> some View {
        let isCorrect = q.outcome == "CORRECT"
        let outcomeColor = isCorrect ? passGreen : failRed
        return VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button { vm.backToReviewList() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.accent)
                            .frame(width: 44, height: 38)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(L10n.quizQuestionNOfN(q.sortOrder + 1, review.questions.count))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(outcomeColor)
                        .padding(.trailing, 16)
                }
                Text(L10n.quizSectionQuiz)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
            }
            .frame(height: 38)
            .padding(.top, 14)

            QuizNumberedProgress(
                count: review.questions.count,
                stateFor: reviewProgressState,
                current: index,
                onTap: { index = $0 }
            )
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: isCorrect ? "checkmark" : "xmark")
                                .font(.system(size: 9, weight: .bold))
                            Text(bidiJoin(isCorrect ? L10n.quizFilterCorrect : L10n.quizFilterWrong,
                                          bidiJoin("\(isCorrect ? 1 : 0)", "1", separator: " / ")))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(outcomeColor)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(outcomeColor.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(outcomeColor.opacity(0.4), lineWidth: 1))
                        Spacer()
                        Text(L10n.quizReviewOnly)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MyCoursesPalette.muted)
                    }
                    .padding(.top, 14)

                    MathText(
                        source: L10n.localized(locale, ar: q.textAr, en: q.textEn),
                        font: .system(size: 19),
                        fontSize: 19,
                        weight: .bold,
                        color: MyCoursesPalette.textPrimary,
                        isRTL: locale == "ar"
                    )

                    VStack(spacing: 10) {
                        ForEach(Array(q.options.enumerated()), id: \.element.id) { idx, option in
                            reviewOption(option: option, index: idx)
                        }
                    }

                    let expl = L10n.localized(locale, ar: q.explanationAr, en: q.explanationEn)
                    if !expl.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            MathText(
                                source: expl,
                                font: .system(size: 13),
                                fontSize: 13,
                                color: MyCoursesPalette.textPrimary.opacity(0.85),
                                isRTL: locale == "ar"
                            )
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.droobGold.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MyCoursesPalette.accent.opacity(0.20), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }

            HStack(spacing: 10) {
                Button { index -= 1 } label: {
                    Text(L10n.quizPrev)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isFirst
                            ? MyCoursesPalette.muted.opacity(0.5)
                            : MyCoursesPalette.textPrimary)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(MyCoursesPalette.surface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isFirst)

                Button {
                    if isLast { onExit() } else { index += 1 }
                } label: {
                    Text(isLast ? L10n.quizExit : "\(L10n.quizNext) →")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(LinearGradient.droobBrand)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // Figma option states:
    //   • Correct + user selected     → green outline, green check, "Your answer · correct"
    //   • Correct + user missed       → red outline,   red x,        "You missed this"
    //   • Wrong + user selected       → red outline,   red x,        "Your answer · wrong"
    //   • Neither correct nor picked  → dim
    private func reviewOption(option: QuizReviewOption, index: Int) -> some View {
        let label = ["A","B","C","D","E"][min(index, 4)]
        let text = L10n.localized(locale, ar: option.textAr, en: option.textEn)

        let isCorrectSelected = option.isCorrect && option.wasSelected
        let isMissedCorrect   = option.isCorrect && !option.wasSelected
        let isWrongPick       = !option.isCorrect && option.wasSelected

        let outline: Color
        let bg: Color
        let chipBg: Color
        let chipFg: Color
        var trailingIcon: String? = nil
        var subtext: String? = nil
        var subtextColor: Color = passGreen

        if isCorrectSelected {
            outline = passGreen
            bg = passGreen.opacity(0.10)
            chipBg = passGreen
            chipFg = .white
            trailingIcon = "checkmark"
            subtext = bidiJoin(L10n.quizYourAnswer, L10n.quizFilterCorrect.lowercased())
            subtextColor = passGreen
        } else if isMissedCorrect {
            outline = failRed
            bg = failRed.opacity(0.10)
            chipBg = failRed
            chipFg = .white
            trailingIcon = "xmark"
            subtext = L10n.quizYouMissedThis
            subtextColor = failRed
        } else if isWrongPick {
            outline = failRed
            bg = failRed.opacity(0.10)
            chipBg = failRed
            chipFg = .white
            trailingIcon = "xmark"
            subtext = bidiJoin(L10n.quizYourAnswer, L10n.quizFilterWrong.lowercased())
            subtextColor = failRed
        } else {
            outline = MyCoursesPalette.stroke
            bg = MyCoursesPalette.surface.opacity(0.5)
            chipBg = MyCoursesPalette.stroke.opacity(0.5)
            chipFg = MyCoursesPalette.muted
        }

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(chipBg).frame(width: 24, height: 24)
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(chipFg)
            }
            VStack(alignment: .leading, spacing: 2) {
                MathText(
                    source: text,
                    font: .system(size: 14),
                    fontSize: 14,
                    weight: .medium,
                    color: isCorrectSelected || isMissedCorrect || isWrongPick
                        ? MyCoursesPalette.textPrimary
                        : MyCoursesPalette.muted,
                    isRTL: locale == "ar"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                if let sub = subtext {
                    Text(sub)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(subtextColor)
                }
            }
            Spacer(minLength: 8)
            if let icon = trailingIcon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isCorrectSelected ? passGreen : failRed)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(outline, lineWidth: 1))
    }
}
