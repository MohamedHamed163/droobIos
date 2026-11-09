import SwiftUI
import QuickLook

// MARK: - The Library
//
// A sheet, not a push. `AskDroobAIView` is hosted from three places — inside a
// `NavigationStack` from the root, and inside two `NavigationLink` backgrounds
// from a course and from the lesson player — and only one of them guarantees a
// stack this view owns. A `.navigationDestination` push would silently do
// nothing from two of the three entry points, so the Library brings its own
// `NavigationStack` with it.
//
// Everything drawn here comes from `index.json` by way of the store's published
// snapshot. Opening a session file is what `Open` and `Re-export` do; drawing
// the list never touches one.

struct AskDroobLibraryView: View {

    @ObservedObject var viewModel: AskDroobAIViewModel
    @ObservedObject private var store = AskDroobLibraryStore.shared

    @Environment(\.appLocale) private var locale
    @Environment(\.dismiss) private var dismiss

    @State private var shareItem: LibraryShareItem?
    @State private var previewURL: LibraryShareItem?
    @State private var pendingDelete: LibrarySessionSummary?
    @State private var confirmDeleteAll = false
    @State private var isWorking = false
    /// The non-red line: "finish the questions first", "no PDF yet". None of
    /// these is a failure, so none of them is red.
    @State private var message: String?

    private typealias S = AskDroobAIViewModel.Strings
    private var isArabic: Bool { locale == "ar" }

    var body: some View {
        content
            .navigationTitle(S.libraryTitle(isArabic))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(S.close(isArabic)) { dismiss() }
                        .foregroundColor(.droobGold)
                }
                if !store.sessions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                confirmDeleteAll = true
                            } label: {
                                Label(
                                    S.deleteAllAction(isArabic),
                                    systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(.droobGold)
                        }
                        .disabled(isWorking)
                    }
                }
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .onAppear { store.start() }
            .sheet(item: $shareItem) { item in
                ActivityShareSheet(activityItems: [item.url])
            }
            // Every saved sheet opens in the same viewer the export opens in,
            // with sharing as its secondary action.
            .sheet(item: $previewURL) { item in
                SolutionPreviewSheet(url: item.url, isArabic: isArabic) {
                    previewURL = nil
                }
            }
            .confirmationDialog(
                S.deleteOneTitle(isArabic),
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { entry in
                Button(S.deleteConfirm(isArabic), role: .destructive) {
                    delete(entry)
                }
                Button(S.cancel(isArabic), role: .cancel) {}
            } message: { _ in
                Text(S.deleteOneBody(isArabic))
            }
            .confirmationDialog(
                S.deleteAllTitle(isArabic),
                isPresented: $confirmDeleteAll,
                titleVisibility: .visible
            ) {
                Button(S.deleteAllConfirm(isArabic), role: .destructive) {
                    deleteAll()
                }
                Button(S.cancel(isArabic), role: .cancel) {}
            } message: {
                Text(S.deleteAllBody(
                    isArabic,
                    count: store.sessions.count,
                    size: S.size(store.totalBytes, isArabic)))
            }
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            // The only state that can take more than a frame: a rebuild after a
            // corrupt index.
            VStack {
                Spacer()
                ProgressView().tint(.droobGold)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if store.sessions.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                banner
                noticeLine
                sessionList
                footer
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundColor(.droobGold.opacity(0.4))
            Text(S.emptyTitle(isArabic))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(S.emptyBody(isArabic))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Eviction banner
    //
    // It persists across launches until dismissed, because eviction almost
    // always happens during a batch with this screen closed.

    @ViewBuilder
    private var banner: some View {
        if let notice = store.notice, !notice.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if notice.pdfs > 0 {
                    Text(S.evictedPdfs(isArabic, count: notice.pdfs))
                }
                if notice.scans > 0 {
                    Text(S.evictedScans(isArabic, count: notice.scans))
                }
                if notice.sessions > 0 {
                    Text(S.evictedSessions(isArabic, count: notice.sessions))
                }
                Button(S.dismiss(isArabic)) { store.dismissNotice() }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.orange)
            }
            .font(.caption)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var noticeLine: some View {
        if let message {
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
    }

    // MARK: - List

    private var sessionList: some View {
        List {
            ForEach(store.sessions) { entry in
                Button { open(entry) } label: {
                    LibraryRow(entry: entry, isArabic: isArabic)
                }
                .buttonStyle(.plain)
                // Deliberately not `.disabled` on the row: `Open` is refused
                // inside `open(_:)` instead, because disabling the row would
                // take `Delete` with it and a damaged session is exactly the one
                // a student needs to be able to delete.
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                // Swipe alone is not discoverable, so the context menu carries
                // all four actions and the swipe carries only the destructive
                // one.
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDelete = entry
                    } label: {
                        Label(S.delete(isArabic), systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        open(entry)
                    } label: {
                        Label(S.open(isArabic), systemImage: "arrow.up.forward.app")
                    }
                    .disabled(entry.damaged)

                    // First, above Share: reading the sheet is the common case,
                    // and until now the only way to see one was to send it to
                    // yourself. Share stays a separate action — a student
                    // forwarding the sheet to WhatsApp should not have to walk
                    // through a viewer to do it.
                    Button {
                        preview(entry)
                    } label: {
                        Label(
                            S.libraryOpenPdf(isArabic),
                            systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(!entry.hasExport)

                    Button {
                        share(entry)
                    } label: {
                        Label(S.sharePdf(isArabic), systemImage: "square.and.arrow.up")
                    }
                    .disabled(!entry.hasExport)

                    Button {
                        reExport(entry)
                    } label: {
                        Label(S.reExport(isArabic), systemImage: "arrow.clockwise")
                    }
                    .disabled(
                        entry.answerCount == 0
                            || entry.damaged
                            || isWorking
                            || viewModel.isExporting)

                    Button(role: .destructive) {
                        pendingDelete = entry
                    } label: {
                        Label(S.delete(isArabic), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        let used = Double(store.totalBytes) / Double(max(store.budgetBytes, 1))
        let nearlyFull = used >= store.warnFraction
        return VStack(spacing: 4) {
            Text(S.footerUsage(
                isArabic,
                count: store.sessions.count,
                used: S.size(store.totalBytes, isArabic),
                budget: S.size(store.budgetBytes, isArabic)))
                .foregroundColor(nearlyFull ? .orange : .secondary)
            if nearlyFull {
                Text(S.nearlyFull(isArabic))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }
            Text(S.footerLocalOnly(isArabic))
                .foregroundColor(.secondary)
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    /// Refusing is the only correct behaviour while work is in flight: swapping
    /// `messages` mid-batch would post the in-flight answer into the wrong
    /// transcript and shift every later question/answer pair in the export.
    private func open(_ entry: LibrarySessionSummary) {
        guard !entry.damaged else { return }
        message = nil
        guard !viewModel.isBatchRunning,
              !viewModel.isLoading,
              !viewModel.isProcessingOCR else {
            message = S.busyCannotOpen(isArabic)
            return
        }
        Task {
            if await viewModel.openSession(id: entry.id) {
                dismiss()
            } else {
                message = S.openFailed(isArabic)
            }
        }
    }

    private func share(_ entry: LibrarySessionSummary) {
        message = nil
        Task {
            if let url = await store.exportURL(for: entry.id) {
                shareItem = LibraryShareItem(url: url)
            } else {
                message = S.noExportYet(isArabic)
            }
        }
    }

    /// Opens the stored sheet in the viewer. Resolves through the same
    /// `exportURL(for:)` as `share(_:)` — the badge on the row can outlive the
    /// file when the budget evicts an old export, and "no PDF yet" is the honest
    /// answer in both places.
    private func preview(_ entry: LibrarySessionSummary) {
        message = nil
        Task {
            if let url = await store.exportURL(for: entry.id) {
                previewURL = LibraryShareItem(url: url)
            } else {
                message = S.noExportYet(isArabic)
            }
        }
    }

    /// Regenerates the sheet from `session.json` and replaces the stored export.
    ///
    /// One at a time *across the whole feature*, not just this sheet:
    /// `isWorking` is a `@State` on the Library and says nothing about an export
    /// the chat already has in flight. Since `commit` bumps `updatedAt` and the
    /// list is newest-first, the top row during a chat export is that very
    /// session — so tapping Re-export there used to put two WKWebViews on the
    /// key window rendering the same session, and whichever finished second
    /// unlinked the file the first one's share sheet was pointing at. Claiming
    /// the view model's single export slot makes the two paths exclusive, and
    /// the chat's Library button is disabled while it holds the slot itself.
    private func reExport(_ entry: LibrarySessionSummary) {
        guard !isWorking else { return }
        message = nil
        guard viewModel.beginExternalExport() else {
            message = S.exportBusy(isArabic)
            return
        }
        isWorking = true
        Task {
            do {
                let session = try await store.loadSession(id: entry.id)
                // Positional pairing, exactly as the chat exporter does it: the
                // transcript alternates, so an assistant turn answers the user
                // turn above it.
                var problems: [SolutionPDFExporter.Problem] = []
                var pending: String?
                for message in session.messages {
                    if message.isUser {
                        pending = message.text
                    } else {
                        problems.append(SolutionPDFExporter.Problem(
                            question: pending ?? "", answer: message.text))
                        pending = nil
                    }
                }
                guard !problems.isEmpty else {
                    message = S.noExportYet(isArabic)
                    isWorking = false
                    viewModel.endExternalExport()
                    return
                }
                // Same reasoning as the row subtitle: re-exporting an old
                // session must not hand an Arabic-only student an English
                // sheet titled "Ask Droob AI Solutions". The stored answers are
                // whatever language they were written in — only the chrome
                // (title, headings, dates, page numbers) follows the app.
                let shown = AppLocaleDefault.presentationLocale(session.locale)
                let title = shown == "ar"
                    ? "حلول اسأل دروب"
                    : "Ask Droob AI Solutions"
                let url = try await SolutionPDFExporter.export(
                    problems: problems,
                    title: title,
                    locale: shown,
                    sessionId: entry.id,
                    kind: .session)
                // Into the viewer, like every other export. Sharing is one tap
                // from there, and re-exporting to look at the result no longer
                // means sending the file somewhere first.
                previewURL = LibraryShareItem(url: url)
            } catch {
                message = (error is LibraryError)
                    ? S.saveFailed(isArabic)
                    : S.openFailed(isArabic)
            }
            isWorking = false
            viewModel.endExternalExport()
        }
    }

    /// No undo and no snackbar reprieve: the files are gone from disk, and
    /// pretending otherwise would be a lie.
    ///
    /// The chat is detached from the session *before* the files go, not after.
    /// Deleting the live session is allowed during a batch — the Library button
    /// stays enabled and a damaged row must always be deletable — and removing
    /// `sessions/`, `scans/` and `exports/` for a 20 MB scan takes long enough
    /// for the next answer to arrive mid-deletion. While `activeSessionId` still
    /// pointed at it, that answer wrote the whole transcript straight back and
    /// the row reappeared, transcript restored and scan and PDF gone, right
    /// after a confirmation that said "This can't be undone".
    private func delete(_ entry: LibrarySessionSummary) {
        pendingDelete = nil
        message = nil
        if viewModel.activeSessionId == entry.id {
            viewModel.resetAfterLibraryWipe()
        }
        Task {
            await store.delete(id: entry.id)
        }
    }

    private func deleteAll() {
        confirmDeleteAll = false
        message = nil
        viewModel.resetAfterLibraryWipe()
        Task {
            await store.deleteAll()
        }
    }
}

// MARK: - One row

private struct LibraryRow: View {

    let entry: LibrarySessionSummary
    let isArabic: Bool

    private typealias S = AskDroobAIViewModel.Strings

    var body: some View {
        // Leading/trailing rather than left/right, so the whole row mirrors
        // under RTL without a single hardcoded edge.
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.droobGold.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 17))
                        .foregroundColor(.droobGold))

            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(entry.damaged ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Three joined parts — date · question count · size — and the
                // Arabic form ("١٢ سبتمبر ٢٠٢٥ · ١٢ سؤالاً · ٤٫٢ م.ب") is
                // materially longer than the English one, in a row that also
                // carries a 40 pt icon, a PDF badge and a chevron.
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if entry.hasExport {
                Text(S.pdfBadge)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.droobGold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.droobGold, lineWidth: 1))
            }

            if !entry.damaged {
                // `chevron.forward` mirrors under RTL; `chevron.right` does not.
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private var titleText: String {
        if entry.damaged { return S.damagedRow(isArabic) }
        let trimmed = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? S.untitledSession(isArabic) : trimmed
    }

    private var subtitle: String {
        // Presented in the APP's locale, not the session's. A session archived
        // before the Arabic lock still carries locale == "en" on disk, and
        // formatting against that put "12 Sept 2025 · 8 questions · 3.4 MB" in
        // the middle of an otherwise all-Arabic list, for good — nothing ever
        // rewrites the stored value. `presentationLocale` is a no-op the moment
        // the flag goes back to false, so each session gets its own language
        // back rather than having been migrated on disk.
        let shown = AppLocaleDefault.presentationLocale(entry.locale)
        // U+00B7 with spaces, in both directions.
        return [
            S.rowDate(entry.updatedAt, locale: shown),
            S.questionCount(shown == "ar", count: entry.questionCount),
            S.size(entry.bytes, shown == "ar")
        ].joined(separator: " · ")
    }

    private var iconName: String {
        guard entry.attachmentCount > 0 else { return "doc.text" }
        if let mime = entry.attachmentMime, mime.hasPrefix("image/") { return "photo" }
        return "doc.richtext"
    }
}

// MARK: - Sheet payloads

/// `.sheet(item:)` needs identity, and sharing the same file twice legitimately
/// presents two sheets.
struct LibraryShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Quick Look

/// Shows a stored scan — a PDF or a photograph — without leaving the app.
struct QuickLookPreview: UIViewControllerRepresentable {

    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(
            _ controller: QLPreviewController, previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
