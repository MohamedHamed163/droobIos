import SwiftUI
import UIKit

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @Environment(\.appLocale) private var locale

    init(preselectedCourseId: String? = nil) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(preselectedCourseId: preselectedCourseId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Course picker header
            coursePicker // retrigger pipeline

            Divider().overlay(MyCoursesPalette.stroke)

            if viewModel.selectedCourse == nil && !viewModel.isLoadingCourses {
                // No course selected
                EmptyStateView(
                    icon: "brain.head.profile",
                    title: L10n.aiTutor,
                    subtitle: L10n.selectCourse
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message, locale: locale) { sessionId, rating in
                                    Task { await viewModel.submitFeedback(sessionId: sessionId, rating: rating) }
                                }
                                .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        if let last = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                // Error
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.droobCaption)
                        .foregroundColor(MyCoursesPalette.danger)
                        .padding(.horizontal)
                }

                Divider().overlay(MyCoursesPalette.stroke)

                // Input bar
                inputBar
            }
        }
        // Pushed from `AiTutorAskView`, which is on the warm cream / near-black
        // palette — the system colours this screen used to fall back on read as
        // a palette break mid-flow (and don't respect the in-app theme).
        .background(MyCoursesPalette.background.ignoresSafeArea())
        .navigationTitle(L10n.aiTutor)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Course picker

    private var coursePicker: some View {
        HStack {
            if viewModel.isLoadingCourses {
                ProgressView()
                    .padding()
            } else if viewModel.enrolledCourses.isEmpty {
                Text(L10n.selectCourse)
                    .font(.droobCaption)
                    .foregroundColor(MyCoursesPalette.muted)
                    .padding()
            } else {
                Menu {
                    ForEach(viewModel.enrolledCourses) { course in
                        Button(course.localizedTitle(locale: locale)) {
                            viewModel.selectedCourse = course
                        }
                    }
                } label: {
                    HStack {
                        Text(viewModel.selectedCourse?.localizedTitle(locale: locale)
                             ?? L10n.aiTutorSelectCourseShort)
                            .font(.droobSubheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    // Gold as the *fill* at low alpha with `accent` as the
                    // ink — the pattern the multi-model screen uses.
                    .foregroundColor(MyCoursesPalette.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.droobGold.opacity(0.18))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Spacer()

                // Streaming toggle
                HStack(spacing: 6) {
                    Text(L10n.streaming)
                        .font(.droobCaption)
                        .foregroundColor(MyCoursesPalette.muted)
                    Toggle("", isOn: $viewModel.isStreaming)
                        .labelsHidden()
                        .tint(MyCoursesPalette.accent)
                        .scaleEffect(0.8)
                }
                .padding(.trailing)
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField(L10n.askPlaceholder, text: $viewModel.inputText, axis: .vertical)
                .font(.droobBody)
                .lineLimit(1...4)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(MyCoursesPalette.surface)
                .cornerRadius(22)

            if viewModel.isSending {
                Button {
                    viewModel.cancelStreaming()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(MyCoursesPalette.danger)
                }
            } else {
                Button {
                    viewModel.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? MyCoursesPalette.muted.opacity(0.5)
                            : MyCoursesPalette.accent
                        )
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MyCoursesPalette.background)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    let locale: String
    let onFeedback: (String, String) -> Void

    @State private var selectedRating: String? = nil
    @State private var showSources: Bool = false
    @State private var mathHeight: CGFloat = 20

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 20))
                    .foregroundColor(MyCoursesPalette.accent)
                    .frame(width: 32, height: 32)
                    .background(Color.droobGold.opacity(0.18))
                    .clipShape(Circle())
            } else {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if message.role == .assistant && !(message.text.isEmpty && message.isStreaming) {
                    MathMarkdownView(
                        markdown: message.text,
                        textColor: UIColor.label,
                        // The web view paints its own background, so it has
                        // to be handed the same surface the bubble uses.
                        backgroundColor: MyCoursesPalette.surfaceUIColor,
                        isRTL: locale == "ar",
                        contentHeight: $mathHeight
                    )
                    .frame(height: max(20, mathHeight))
                    .padding(12)
                    .background(MyCoursesPalette.surface)
                    .cornerRadius(18)
                } else {
                    Text(message.text.isEmpty && message.isStreaming ? " " : message.text)
                        .font(.droobBody)
                        // White-on-gold fails in both modes; the student's own
                        // bubble is a gold *tint* with normal ink instead.
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .padding(12)
                        .background(
                            message.role == .user
                            ? Color.droobGold.opacity(0.18)
                            : MyCoursesPalette.surface
                        )
                        .cornerRadius(18)
                }

                if message.isStreaming {
                    TypingIndicator()
                }

                // Sources + Feedback (assistant only)
                if message.role == .assistant, !message.isStreaming {
                    HStack(spacing: 8) {
                        if !message.sources.isEmpty {
                            Button {
                                showSources.toggle()
                            } label: {
                                Label("\(message.sources.count) \(L10n.sources)", systemImage: "doc.text")
                                    .font(.droobCaption)
                                    .foregroundColor(MyCoursesPalette.accent)
                            }
                        }

                        Spacer()

                        if let sessionId = message.sessionId {
                            FeedbackButtons(selectedRating: $selectedRating) { rating in
                                selectedRating = rating
                                onFeedback(sessionId, rating)
                            }
                        }
                    }

                    if showSources && !message.sources.isEmpty {
                        SourcesView(sources: message.sources)
                    }
                }
            }

            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(MyCoursesPalette.muted)
            }
        }
    }
}

// MARK: - Typing indicator

struct TypingIndicator: View {
    @State private var phase: Int = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(MyCoursesPalette.muted)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1.0 : 0.3)
            }
        }
        .padding(8)
        .background(MyCoursesPalette.surface)
        .cornerRadius(12)
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// ─────────────────────────────────────────────────────────────────────
// Multi-model ask
//
// The screen the "Ask AI" affordances on Course Detail and the Lesson
// Player push. Kept in this already-referenced file rather than a new
// one — see the note at the top of the multi-model section in
// ChatViewModel.swift for why.
// ─────────────────────────────────────────────────────────────────────

struct AiTutorAskView: View {
    @StateObject private var viewModel: AiTutorMultiViewModel
    @Environment(\.appLocale) private var locale

    @State private var showModelPicker = false
    @State private var showAttachmentSheet = false
    @State private var pageIndex = 0
    @State private var copiedModelId: String?

    init(courseId: String) {
        _viewModel = StateObject(wrappedValue: AiTutorMultiViewModel(courseId: courseId))
    }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                controls
                Divider().overlay(MyCoursesPalette.stroke)
                resultsArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                composer
            }
        }
        .navigationTitle(L10n.aiMultiTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // The conversational single-model tutor. It had no call
                // sites at all before this screen existed.
                NavigationLink {
                    ChatView(preselectedCourseId: viewModel.courseId)
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
                .accessibilityLabel(L10n.aiMultiOpenChat)
            }
        }
        .task { await viewModel.loadModels() }
        // Snap back to the first (winning) card on every new turn. Keyed on
        // the turn id rather than the answer count, so asking twice and
        // getting the same number of cards still resets the pager.
        .onChange(of: viewModel.turnId) { _, _ in pageIndex = 0 }
        .sheet(isPresented: $showModelPicker) {
            AiTutorModelPickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showAttachmentSheet) {
            // The sheet closes itself through `onClose` once it has
            // handed over the picked payload.
            ChatAttachmentSheet(
                onPicked: { picked in
                    Task { await viewModel.attach(picked) }
                },
                onClose: { showAttachmentSheet = false })
        }
    }

    // MARK: - Controls (mode + models + photo)

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: modeBinding) {
                ForEach(AiTutorAskMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isAsking)

            Text(viewModel.mode.hint)
                .font(.droobCaption)
                .foregroundColor(MyCoursesPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button { showModelPicker = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.aiMultiModelsLabel)
                        .font(.system(size: 13, weight: .semibold))
                    Text(viewModel.modelSummary)
                        .font(.droobCaption)
                        .foregroundColor(MyCoursesPalette.muted)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.muted)
                }
                .foregroundColor(MyCoursesPalette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(MyCoursesPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isAsking)

            if viewModel.hasImage {
                attachmentChip
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var modeBinding: Binding<AiTutorAskMode> {
        Binding(get: { viewModel.mode }, set: { viewModel.setMode($0) })
    }

    private var attachmentChip: some View {
        HStack(spacing: 10) {
            if let data = viewModel.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isUploadingImage
                     ? L10n.aiMultiPhotoUploading
                     : L10n.aiMultiPhotoAttached)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                if !viewModel.isUploadingImage {
                    Text(L10n.aiMultiVisionFilterNote)
                        .font(.droobCaption2)
                        .foregroundColor(MyCoursesPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if viewModel.isUploadingImage {
                ProgressView().scaleEffect(0.8)
            } else {
                Button(L10n.aiMultiPhotoRemove) {
                    Task { await viewModel.removeImage() }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MyCoursesPalette.danger)
            }
        }
        .padding(10)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsArea: some View {
        if viewModel.isAsking {
            AiTutorWaitingView(viewModel: viewModel)
        } else if !viewModel.answers.isEmpty {
            answersSection
        } else if let error = viewModel.errorMessage {
            ScrollView {
                ErrorBanner(message: error) { viewModel.ask() }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
            }
        } else {
            EmptyStateView(
                icon: "sparkles",
                title: L10n.aiMultiEmptyTitle,
                subtitle: L10n.aiMultiEmptySubtitle)
            .padding(.horizontal, 24)
        }
    }

    private var answersSection: some View {
        VStack(spacing: 0) {
            if viewModel.answers.count > 1 {
                HStack {
                    Text(L10n.aiMultiAnswerPosition(
                        min(pageIndex + 1, viewModel.answers.count),
                        viewModel.answers.count))
                    Spacer()
                    Text(L10n.aiMultiAnsweredSummary(
                        viewModel.okCount, viewModel.answers.count))
                }
                .font(.droobCaption)
                .foregroundColor(MyCoursesPalette.muted)
                .padding(.horizontal, 18)
                .padding(.top, 10)

                // Horizontally paged cards, matching the pager idiom the
                // quiz player already uses. Each page scrolls vertically
                // on its own so a long answer never clips.
                TabView(selection: $pageIndex) {
                    ForEach(Array(viewModel.answers.enumerated()),
                            id: \.element.id) { index, answer in
                        answerPage(answer).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            } else if let only = viewModel.answers.first {
                answerPage(only)
            }
        }
    }

    private func answerPage(_ answer: AiTutorAnswer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AiTutorAnswerCard(
                    answer: answer,
                    locale: locale,
                    isWinner: viewModel.isWinner(answer),
                    rating: viewModel.ratings[answer.modelId],
                    isCopied: copiedModelId == answer.modelId,
                    onRate: { rating in
                        Task { await viewModel.rate(modelId: answer.modelId, rating: rating) }
                    },
                    onCopy: { copy(answer) })

                // `best_rationale` belongs to the turn, not the card — show
                // it once, pinned under the winner.
                if viewModel.isWinner(answer),
                   let rationale = viewModel.bestRationale,
                   !rationale.trimmingCharacters(in: .whitespaces).isEmpty {
                    bestRationaleBlock(rationale)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    private func bestRationaleBlock(_ rationale: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.aiMultiBestRationaleTitle, systemImage: "trophy")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MyCoursesPalette.accent)
            Text(rationale)
                .font(.droobCaption)
                .foregroundColor(MyCoursesPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.droobGold.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MyCoursesPalette.accent.opacity(0.35), lineWidth: 1))
    }

    private func copy(_ answer: AiTutorAnswer) {
        guard let text = answer.answer, !text.isEmpty else { return }
        UIPasteboard.general.string = text
        let modelId = answer.modelId
        withAnimation { copiedModelId = modelId }
        // Revert the button to "Copy" so a second copy still reads as a
        // fresh confirmation rather than a stuck checkmark.
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if copiedModelId == modelId {
                withAnimation { copiedModelId = nil }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            // While answers are on screen the error belongs above the
            // composer; with none, `resultsArea` owns it (with a retry).
            if let error = viewModel.errorMessage, !viewModel.answers.isEmpty {
                Text(error)
                    .font(.droobCaption)
                    .foregroundColor(MyCoursesPalette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button { showAttachmentSheet = true } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.muted)
                        .frame(width: 40, height: 40)
                        .background(MyCoursesPalette.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isAsking || viewModel.isUploadingImage)
                .accessibilityLabel(L10n.aiMultiAttachPhoto)

                TextField(L10n.aiMultiQuestionPlaceholder,
                          text: $viewModel.question, axis: .vertical)
                    .font(.droobBody)
                    .lineLimit(1...4)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(MyCoursesPalette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button { viewModel.ask() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        // Gold as *ink* on the near-white light background
                        // measures ~1.8:1 — `accent` is the adaptive token
                        // for exactly this job.
                        .foregroundColor(viewModel.canAsk
                                         ? MyCoursesPalette.accent
                                         : MyCoursesPalette.muted.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canAsk)
                .accessibilityLabel(L10n.aiMultiAsk)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MyCoursesPalette.background)
    }
}

// MARK: - Waiting state

/// Shown for the whole fan-out. DEEP can take ~30 s and the endpoint is
/// not streamed, so instead of a blocking spinner we name the models
/// being asked, run a determinate-feeling bar, and keep Stop reachable.
private struct AiTutorWaitingView: View {
    @ObservedObject var viewModel: AiTutorMultiViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.waitingTitle)
                .font(.droobTitle2)
                .foregroundColor(MyCoursesPalette.textPrimary)

            Text(L10n.aiMultiWaitingSubtitle)
                .font(.droobCaption)
                .foregroundColor(MyCoursesPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: viewModel.waitingProgress)
                // Same reason as the send glyph: the bar sits on the page
                // background, so it needs the adaptive accent, not raw gold.
                .tint(MyCoursesPalette.accent)

            if !viewModel.pendingModelNames.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(viewModel.pendingModelNames.enumerated()),
                                id: \.offset) { _, name in
                            HStack(spacing: 10) {
                                ProgressView().scaleEffect(0.7)
                                // Model names are Latin inside an Arabic
                                // UI — isolate so they don't reorder.
                                Text(name.bidiIsolated)
                                    .font(.droobSubheadline)
                                    .foregroundColor(MyCoursesPalette.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .droobBounceBasedOnSize()
            }

            Button(L10n.aiMultiWaitingCancel) { viewModel.cancelAsk() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(MyCoursesPalette.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(MyCoursesPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(20)
    }
}

// MARK: - Answer card

/// One model's result. Renders the markdown+LaTeX answer through the
/// existing KaTeX web view, or — when the model timed out / got rate
/// limited — a card explaining that, because silently dropping it would
/// leave the student counting missing answers.
private struct AiTutorAnswerCard: View {
    let answer: AiTutorAnswer
    let locale: String
    let isWinner: Bool
    let rating: String?
    let isCopied: Bool
    let onRate: (String) -> Void
    let onCopy: () -> Void

    @State private var mathHeight: CGFloat = 24

    /// The KaTeX web view paints its own background from a concrete
    /// UIColor, so the card and the rendered answer have to agree on one.
    /// (Passing `.clear` is not an option — `MathMarkdownView` converts
    /// the colour to a hex string, and clear resolves to #000000.) It is
    /// the palette's own surface colour rather than a copy of its RGB, so
    /// a palette change moves the card and the web view together.
    private static let cardSurface = MyCoursesPalette.surfaceUIColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if answer.isSuccess {
                MathMarkdownView(
                    markdown: answer.answer ?? "",
                    textColor: UIColor.label,
                    backgroundColor: Self.cardSurface,
                    isRTL: locale == "ar",
                    contentHeight: $mathHeight)
                .frame(height: max(24, mathHeight))
                footer
            } else {
                failureBlock
            }
        }
        .padding(14)
        .background(Color(uiColor: Self.cardSurface))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isWinner
                        ? MyCoursesPalette.accent.opacity(0.55)
                        : MyCoursesPalette.stroke,
                        lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(answer.modelName.bidiIsolated)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)
                .lineLimit(1)

            if isWinner {
                Text(L10n.aiMultiBestBadge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MyCoursesPalette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.droobGold.opacity(0.18))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 4)

            if let latency = answer.latencyText(locale: locale) {
                Text(latency)
                    .font(.droobCaption2)
                    .foregroundColor(MyCoursesPalette.textTertiary)
            }
        }
    }

    private var failureBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: answer.status.failureIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(MyCoursesPalette.danger)
            VStack(alignment: .leading, spacing: 4) {
                Text(answer.status.failureLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(answer.status.failureHint)
                    .font(.droobCaption)
                    .foregroundColor(MyCoursesPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            FeedbackButtons(selectedRating: .constant(rating)) { value in
                onRate(value)
            }

            if rating != nil {
                Text(L10n.aiMultiRatingThanks)
                    .font(.droobCaption2)
                    .foregroundColor(MyCoursesPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: onCopy) {
                Label(isCopied ? L10n.aiMultiCopied : L10n.aiMultiCopy,
                      systemImage: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Model picker

/// Multi-select roster. Capped at 1 in FAST and 3 in DEEP, with DEEP's
/// "Compare all" as the escape hatch for the full fan-out.
struct AiTutorModelPickerSheet: View {
    @ObservedObject var viewModel: AiTutorMultiViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                content
            }
            .navigationTitle(L10n.aiMultiModelsPickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.done) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingModels {
            ProgressView(L10n.aiMultiModelsLoading)
        } else if let error = viewModel.modelsError {
            ErrorBanner(message: error) {
                Task { await viewModel.loadModels() }
            }
            .padding(.horizontal, 20)
        } else if viewModel.models.isEmpty {
            EmptyStateView(icon: "cpu", title: L10n.aiMultiModelsEmpty)
                .padding(.horizontal, 24)
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.mode == .fast
                     ? L10n.aiMultiModelsCapHintFast
                     : L10n.aiMultiModelsCapHintDeep)
                    .font(.droobCaption)
                    .foregroundColor(MyCoursesPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.hasImage {
                    Text(L10n.aiMultiVisionFilterNote)
                        .font(.droobCaption)
                        .foregroundColor(MyCoursesPalette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if viewModel.mode == .deep {
                    compareAllRow
                }

                ForEach(viewModel.models) { model in
                    modelRow(model)
                }
            }
            .padding(16)
        }
    }

    private var compareAllRow: some View {
        Button { viewModel.setCompareAll(!viewModel.compareAll) } label: {
            row(title: L10n.aiMultiModelsCompareAll,
                subtitle: L10n.aiMultiModelsCompareAllHint,
                markers: [],
                isSelected: viewModel.compareAll,
                isDimmed: false)
        }
        .buttonStyle(.plain)
    }

    private func modelRow(_ model: AiTutorModel) -> some View {
        // At the cap, unpicked rows dim rather than disappear so the
        // student can see what they're trading off. FAST swaps instead.
        let selected = viewModel.isSelected(model)
        let dimmed = !selected
            && viewModel.mode == .deep
            && (viewModel.isSelectionAtCap || viewModel.compareAll)
        var markers: [String] = []
        if model.supportsVision { markers.append(L10n.aiMultiModelVision) }
        if model.isFastDefault { markers.append(L10n.aiMultiModelFastDefault) }

        return Button { viewModel.toggle(model) } label: {
            row(title: model.name,
                subtitle: model.provider,
                markers: markers,
                isSelected: selected,
                isDimmed: dimmed)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
    }

    private func row(title: String,
                     subtitle: String,
                     markers: [String],
                     isSelected: Bool,
                     isDimmed: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Model + provider names arrive Latin inside an Arabic UI.
                Text(title.bidiIsolated)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle.bidiIsolated)
                        .font(.droobCaption)
                        .foregroundColor(MyCoursesPalette.muted)
                }
                if !markers.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(markers, id: \.self) { marker in
                            Text(marker)
                                .font(.droobCaption2)
                                .foregroundColor(MyCoursesPalette.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.droobGold.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(isSelected
                                 ? MyCoursesPalette.accent
                                 : MyCoursesPalette.stroke)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected
                        ? MyCoursesPalette.accent.opacity(0.55)
                        : MyCoursesPalette.stroke,
                        lineWidth: 1))
        .opacity(isDimmed ? 0.45 : 1.0)
    }
}

// MARK: - Entry-point card
//
// The affordance the course-detail screen shows. The lesson player uses
// its own inline pill instead, to fit the action row there.

struct AskAiCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.droobGold.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(MyCoursesPalette.accent.opacity(0.45), lineWidth: 1))
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.accent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.aiMultiEntryTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.aiMultiEntrySubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(MyCoursesPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(MyCoursesPalette.accent.opacity(0.40), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bottom-bar AI entry
//
// The AI tutor is reachable from the bottom bar as well as from course
// detail and the lesson player. Those two entry points already know which
// course the student is looking at; the bar does not, and every AI endpoint
// is course-scoped and enrollment-guarded. So the bar can't open
// `AiTutorAskView` directly — it opens `AiTutorHubView`, which resolves the
// course first and then hands over to the *same* ask screen.
//
// Everything below is deliberately in this file rather than a new one: the
// Xcode project has no filesystem-synchronised group, so a new .swift on
// disk compiles fine under `swiftc -parse` and then fails at link time.

// MARK: Shared motion gate
//
// The two ambient animations here (the orb's pulse, the hub's aurora) are the
// only continuously-running motion in the app, so they share one rule: run
// only while the scene is active AND the user hasn't asked for reduced
// motion. Backgrounding the app cancels them rather than leaving a
// `repeatForever` ticking against the render server.
private struct AmbientMotion {
    let reduceMotion: Bool
    let scenePhase: ScenePhase
    var isOn: Bool { !reduceMotion && scenePhase == .active }
}

/// Cancels an in-flight `repeatForever` animation. Setting the driving state
/// back inside a transaction with `disablesAnimations` is the only reliable
/// way to stop one — plain `withAnimation(nil)` leaves it running.
private func cancelAmbientAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}

// MARK: - Tab-bar orb

/// Tracks whether the bottom-bar AI orb should stand down.
///
/// The orb is an overlay on `MainTabView`'s `TabView`, so it floats over
/// every screen pushed inside a tab — including the two chat screens, whose
/// send buttons sit in exactly the same trailing/bottom corner and end up
/// underneath it. Those screens call `.hidesAiTutorOrb()`.
///
/// Holds are recorded *per tab* rather than as one global count, because a
/// pushed screen stays in its tab's stack while the user is off browsing
/// another tab. Keying on the tab means the orb is correct on both sides of
/// a tab switch no matter whether SwiftUI chooses to fire the pushed view's
/// `onDisappear` for that switch: another tab is never suppressed by a chat
/// left open in Messages, and coming back to Messages re-suppresses it even
/// if no `onAppear` fires. A set of ids (not a counter) so a repeated
/// `onAppear` can't inflate the hold.
@MainActor
final class AiTutorOrbVisibility: ObservableObject {
    static let shared = AiTutorOrbVisibility()

    @Published private(set) var isSuppressed: Bool = false

    /// The tab currently selected in `MainTabView`. Holds taken while this
    /// tab is up belong to it.
    private(set) var currentTab: AppTab = .home

    private var holders: [AppTab: Set<UUID>] = [:]

    private init() {}

    func setCurrentTab(_ tab: AppTab) {
        currentTab = tab
        recompute()
    }

    func retain(_ id: UUID) {
        holders[currentTab, default: []].insert(id)
        recompute()
    }

    func release(_ id: UUID) {
        for tab in holders.keys {
            holders[tab]?.remove(id)
        }
        recompute()
    }

    private func recompute() {
        isSuppressed = !(holders[currentTab]?.isEmpty ?? true)
    }
}

private struct HidesAiTutorOrbModifier: ViewModifier {
    /// Identifies this screen's hold, so a repeated `onAppear` re-inserts
    /// the same id instead of leaking a second one.
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { AiTutorOrbVisibility.shared.retain(id) }
            .onDisappear { AiTutorOrbVisibility.shared.release(id) }
    }
}

extension View {
    /// Hides the bottom-bar AI orb for as long as this view is on screen.
    /// For screens with their own bottom-trailing control — the chat
    /// composers' send buttons — which the orb would otherwise cover.
    func hidesAiTutorOrb() -> some View {
        modifier(HidesAiTutorOrbModifier())
    }
}

/// The AI entry in the bottom bar.
///
/// It is *not* a sixth peer tab. It carries no text label — which is both
/// what makes it affordable next to five labelled tabs at the app's 1.242 type
/// scale, and what makes it read as an action rather than another
/// destination. VoiceOver still announces it properly via
/// `ai_hub.tab_a11y`.
///
/// Colours resolve from `MyCoursesPalette`, so the orb works on the light
/// ground as well as the dark one: the disc is filled with `accent` (the gold
/// ramp that stays legible in both themes) and the glyph is punched out in
/// `background`, which inverts with the theme and keeps the mark high
/// contrast either way.
struct AiTutorTabOrb: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var pulse = false

    private var motion: AmbientMotion {
        AmbientMotion(reduceMotion: reduceMotion, scenePhase: scenePhase)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Ambient halo. Slow, low-amplitude — a tab-bar item that
                // flickers is an irritation. 2.8s per half-cycle, 8% of
                // scale, and it never leaves the orb's own footprint.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                MyCoursesPalette.accent.opacity(0.38),
                                MyCoursesPalette.accent.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 33))
                    .frame(width: 66, height: 66)
                    .scaleEffect(pulse ? 1.0 : 0.88)
                    .opacity(pulse ? 0.95 : 0.55)

                // The disc.
                Circle()
                    .fill(MyCoursesPalette.accent)
                    .overlay(
                        // Soft top-lit sheen. Pure white/black at low alpha
                        // rather than a second hue, so it reads as depth on
                        // both grounds and never becomes a second colour.
                        Circle().fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.30),
                                    Color.white.opacity(0.02),
                                    Color.black.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing)))
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.22), lineWidth: 0.8))
                    .frame(width: 50, height: 50)
                    // Two shadows on purpose: the gold one carries the glow on
                    // the dark ground, the neutral one lifts the orb off the
                    // light one (where a gold shadow on cream is invisible and
                    // the orb would sit flat on whatever content is behind it).
                    .shadow(color: MyCoursesPalette.accent.opacity(0.45),
                            radius: 10, x: 0, y: 3)
                    .shadow(color: Color.black.opacity(0.18),
                            radius: 7, x: 0, y: 4)

                Image(systemName: "sparkles")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.background)
            }
            .frame(width: 66, height: 66)
            .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(L10n.aiHubTabA11y)
        .accessibilityHint(L10n.aiHubTabA11yHint)
        .accessibilityAddTraits(.isButton)
        .onAppear { syncPulse(motion.isOn) }
        .onChange(of: motion.isOn) { _, on in syncPulse(on) }
    }

    private func syncPulse(_ on: Bool) {
        guard on else {
            cancelAmbientAnimation { pulse = false }
            return
        }
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

// MARK: - Aurora field
//
// The hub's backdrop: three very soft, heavily blurred gold masses that drift
// against each other. Deliberately monochrome — the brand is one gold, and a
// multi-hue field would be the exact neon cliché this is meant to avoid. The
// alphas are low enough that the same field reads as a warm wash on white and
// as a faint glow on near-black.
private struct AiAuroraField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var drift = false

    private var motion: AmbientMotion {
        AmbientMotion(reduceMotion: reduceMotion, scenePhase: scenePhase)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                blob(opacity: 0.34, diameter: w * 1.00)
                    .offset(x: drift ? -w * 0.24 : w * 0.12,
                            y: drift ? -h * 0.30 : -h * 0.16)
                blob(opacity: 0.20, diameter: w * 0.82)
                    .offset(x: drift ? w * 0.30 : -w * 0.10,
                            y: drift ? -h * 0.02 : h * 0.14)
                blob(opacity: 0.10, diameter: w * 0.62)
                    .offset(x: drift ? -w * 0.06 : w * 0.22,
                            y: drift ? h * 0.24 : h * 0.02)
            }
            .frame(width: w, height: h, alignment: .top)
            .blur(radius: 46)
        }
        .allowsHitTesting(false)
        .onAppear { syncDrift(motion.isOn) }
        .onChange(of: motion.isOn) { _, on in syncDrift(on) }
    }

    private func blob(opacity: Double, diameter: CGFloat) -> some View {
        Circle()
            .fill(MyCoursesPalette.accent.opacity(opacity))
            .frame(width: diameter, height: diameter)
    }

    private func syncDrift(_ on: Bool) {
        guard on else {
            cancelAmbientAnimation { drift = false }
            return
        }
        withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
            drift = true
        }
    }
}

// MARK: - Model constellation
//
// A ring of satellites converging on a single core: the shape of what the
// tutor actually does — several models asked at once, one answer surfaced.
// The satellites are unlabelled on purpose. Naming them would mean either
// hardcoding a roster that the server owns, or firing the models request from
// a screen that has no course yet; neither is worth a decorative caption.
private struct AiModelConstellation: View {
    var diameter: CGFloat = 168

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var spin = false

    /// Satellite sizes/alphas vary so the ring reads as a constellation
    /// rather than a loading spinner.
    private let satellites: [(size: CGFloat, opacity: Double)] = [
        (9, 0.90), (6, 0.55), (8, 0.75), (5, 0.42), (7, 0.65), (5, 0.34)
    ]

    private var motion: AmbientMotion {
        AmbientMotion(reduceMotion: reduceMotion, scenePhase: scenePhase)
    }

    var body: some View {
        let radius = diameter / 2 - 10
        ZStack {
            ZStack {
                ForEach(Array(satellites.enumerated()), id: \.offset) { index, node in
                    let angle = Double(index) / Double(satellites.count) * 360

                    // Hairline from the core out to this satellite.
                    Capsule()
                        .fill(LinearGradient(
                            colors: [
                                MyCoursesPalette.accent.opacity(0.0),
                                MyCoursesPalette.accent.opacity(node.opacity * 0.45)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing))
                        .frame(width: radius, height: 1)
                        .offset(x: radius / 2)
                        .rotationEffect(.degrees(angle))

                    Circle()
                        .fill(MyCoursesPalette.accent.opacity(node.opacity))
                        .frame(width: node.size, height: node.size)
                        .offset(x: radius)
                        .rotationEffect(.degrees(angle))
                }
            }
            .rotationEffect(.degrees(spin ? 360 : 0))

            // Core.
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [
                            MyCoursesPalette.accent.opacity(0.30),
                            MyCoursesPalette.accent.opacity(0.0)
                        ],
                        center: .center, startRadius: 8, endRadius: 40))
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(MyCoursesPalette.accent)
                    .overlay(
                        Circle().fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.28),
                                    Color.white.opacity(0.02),
                                    Color.black.opacity(0.14)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing)))
                    .frame(width: 56, height: 56)

                Image(systemName: "sparkles")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.background)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
        .onAppear { syncSpin(motion.isOn) }
        .onChange(of: motion.isOn) { _, on in syncSpin(on) }
    }

    private func syncSpin(_ on: Bool) {
        guard on else {
            cancelAmbientAnimation { spin = false }
            return
        }
        withAnimation(.linear(duration: 64).repeatForever(autoreverses: false)) {
            spin = true
        }
    }
}

// MARK: - Hub

/// Course resolver for the bottom-bar AI entry.
///
/// Three outcomes, in order of how often they should cost the student a tap:
///   * exactly one enrolled course → no picker at all, the ask screen renders
///     in place. Choosing from a list of one is a step that only exists
///     because the code needed it.
///   * two or more → a picker, ordered exactly as `/v1/student/enrollments`
///     returns them. There is no cheap signal for "last course asked about"
///     (the AI feature persists nothing locally), and the brief explicitly
///     rules out building persistence for it, so the server order stands.
///   * none → a real empty state that says what the tutor is for, with a way
///     through to the catalogue.
///
/// The enrolled list comes from `MyCoursesViewModel`, the same view model the
/// My Courses screen uses, hitting the same endpoint. No new API surface.
struct AiTutorHubView: View {
    /// Routes to the catalogue. Owned by the caller because leaving the hub
    /// means dismissing it first.
    let onBrowseCatalogue: () -> Void
    let onClose: () -> Void

    @StateObject private var courses: MyCoursesViewModel
    @Environment(\.appLocale) private var locale

    /// `coursesOverride` mirrors `CoursesTabView(myCoursesOverride:)`: it lets
    /// the launch-arg preview hosts in `RootView` render this screen's three
    /// states (and check them in RTL / light mode) without a live backend.
    init(
        coursesOverride: MyCoursesViewModel? = nil,
        onBrowseCatalogue: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        _courses = StateObject(wrappedValue: coursesOverride ?? MyCoursesViewModel())
        self.onBrowseCatalogue = onBrowseCatalogue
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if courses.enrollments.count == 1, let only = courses.enrollments.first {
                // Skip the picker entirely.
                AiTutorAskView(courseId: only.id)
            } else {
                hub
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(L10n.aiHubClose) { onClose() }
            }
        }
        .task {
            guard !courses.hasLoaded else { return }
            await courses.load()
        }
    }

    private var hub: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            AiAuroraField().ignoresSafeArea()

            if !courses.hasLoaded {
                loadingState
            } else if let error = courses.errorMessage, courses.enrollments.isEmpty {
                ErrorBanner(message: error) {
                    Task { await courses.load() }
                }
                .padding(.horizontal, 20)
            } else if courses.enrollments.isEmpty {
                emptyState
            } else {
                picker
            }
        }
        .navigationTitle(L10n.aiHubTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: 22) {
            AiModelConstellation()
            Text(L10n.aiHubLoading)
                .font(.droobSubheadline)
                .foregroundColor(MyCoursesPalette.muted)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            AiModelConstellation(diameter: 148)
                .opacity(0.7)

            Text(L10n.aiHubEmptyTitle)
                .font(.droobTitle2)
                .foregroundColor(MyCoursesPalette.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.aiHubEmptyBody)
                .font(.droobSubheadline)
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            DroobButton(L10n.aiHubEmptyCta) { onBrowseCatalogue() }
                .padding(.top, 4)
        }
        .padding(.horizontal, 28)
    }

    private var picker: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    AiModelConstellation(diameter: 156)

                    Text(L10n.aiHubHeadline)
                        .font(.droobTitle)
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.aiHubSubheadline)
                        .font(.droobSubheadline)
                        .foregroundColor(MyCoursesPalette.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.aiHubPickCourse)
                        .font(.droobHeadline)
                        .foregroundColor(MyCoursesPalette.textPrimary)
                    Text(L10n.aiHubPickCourseHint)
                        .font(.droobCaption)
                        .foregroundColor(MyCoursesPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

                LazyVStack(spacing: 10) {
                    ForEach(courses.enrollments) { course in
                        NavigationLink {
                            AiTutorAskView(courseId: course.id)
                        } label: {
                            AiTutorHubCourseRow(course: course, locale: locale)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .refreshable { await courses.load() }
    }
}

/// One enrolled course in the hub picker. Kept flatter and quieter than
/// `EnrolledCourseCard` — this is a disambiguation step on the way to the ask
/// screen, not a place to browse.
private struct AiTutorHubCourseRow: View {
    let course: EnrolledCourse
    let locale: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MyCoursesPalette.accent.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MyCoursesPalette.accent.opacity(0.30), lineWidth: 1))
                Image(systemName: course.coverSymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(course.localizedTitle(locale: locale))
                    .font(.droobHeadline)
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(course.instructorName)
                    .font(.droobCaption)
                    .foregroundColor(MyCoursesPalette.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // `chevron.forward` mirrors itself in RTL; `chevron.right` would not.
            Image(systemName: "chevron.forward")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MyCoursesPalette.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MyCoursesPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1)))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
