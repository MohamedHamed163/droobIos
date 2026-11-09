import SwiftUI
import PDFKit
import UIKit

// MARK: - In-app PDF reader with reading-progress reporting
//
// Opens a lesson document with PDFKit, restores the last page the student
// was on, and pushes every page change up to the backend reading-progress
// endpoint so the progress bar on the lesson screen stays in sync.
//
// Page changes are coalesced into one in-flight request: a fresh page hit
// during a pending upload replaces the queued payload, so quick flipping
// produces a small bounded number of writes instead of one per page.
//
// Layout matches the Figma:
//   • top bar — back / "LESSON 3.2" eyebrow / centred title +
//     "PDF · Page X of Y" subtitle / search affordance
//   • PDFKit body
//   • bottom bar — Prev / "X / Y pages" / Add Note / My Notes / Next
//
// The chrome tracks the app color scheme through `MyCoursesPalette`; only
// the PDF page itself (always light "paper") and the note callout drawn on
// top of it stay fixed-colour.

struct LessonPDFReaderView: View {
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    let courseId: String
    let lessonId: String
    let document: LessonDocumentItem
    /// "3.2" — drives the LESSON eyebrow in the dark header. Pass `""` to
    /// hide the eyebrow.
    let lessonNumber: String
    /// Used as the header title (falls back to filename when empty).
    let lessonTitle: String
    /// Shared view-model so the notes list / add-note flows write back to
    /// the same store the lesson player reads.
    @ObservedObject var vm: LessonPlayerViewModel
    /// Override for the initial page. When non-nil, used instead of saved
    /// reading progress so callers can deep-link to a specific page (e.g.
    /// "jump to page 18" from the My Notes screen).
    var initialPageOverride: Int? = nil
    /// Note id to focus once the reader has loaded — pops the Figma-style
    /// comment callout for that note on the landing page so the student
    /// actually sees the saved content (not just the page it's pinned to).
    /// Honoured exactly once per presentation.
    var initialFocusNoteId: String? = nil
    /// Invoked when the student picks a *video*-anchored note from this
    /// reader's MyNotesView. The host (LessonPlayerView) owns the AVPlayer
    /// so the actual seek has to bubble up — without this the reader would
    /// just dismiss and the timestamp would be silently dropped on the
    /// floor.
    var onJumpToVideoTimestamp: ((_ seconds: Int, _ noteId: String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var url: URL? = nil
    @State private var loadError: String? = nil
    @State private var currentPage: Int = 1
    @State private var pageCount: Int = 0
    @State private var pendingExport: URL? = nil
    @State private var pdfDocument: PDFDocument? = nil
    @State private var initialPage: Int = 1

    @State private var showAddNote: Bool = false
    @State private var showMyNotes: Bool = false
    /// "Notes on this page" bottom panel, opened from the bottom-bar Notes pill.
    @State private var showNotesOnPage: Bool = false
    /// Live downward drag offset of the notes panel, for swipe-to-dismiss.
    @State private var notesPanelDrag: CGFloat = 0
    /// Measured height of the bottom toolbar so the compact notes peek panel
    /// can float just above it (Figma 1695:11099) instead of covering it.
    @State private var bottomBarHeight: CGFloat = 64
    @State private var editingNote: LessonNoteItem? = nil
    /// Note whose content is being shown as a floating callout on top of
    /// the current page (Figma-comment style). Set when the reader is
    /// deep-linked to a note from MyNotesView, or when one of the
    /// page-only comment pins is tapped. Cleared on user close, on
    /// paging away from the note's pinned page, or when the user opts
    /// to edit the note.
    @State private var focusedNote: LessonNoteItem? = nil
    /// Snapshot of the live PDF selection + page taken when the user taps
    /// "Add Note". Reset after the compose sheet dismisses so a subsequent
    /// note doesn't accidentally carry stale state.
    @State private var snapshotSelectedText: String? = nil
    @State private var snapshotPage: Int? = nil
    /// Drives the post-save toast on the reader (parity with the player).
    @State private var showSavedToast: Bool = false
    @State private var savedToastLabel: String? = nil
    /// Drives the "Note deleted · Undo" top toast and holds the just-deleted
    /// note so Undo can re-create it.
    @State private var showDeletedToast: Bool = false
    @State private var deletedSnapshot: LessonNoteItem? = nil

    /// Bridges the SwiftUI side to the underlying PDFView so Prev / Next /
    /// programmatic jumps can drive PDFKit without rebuilding the view.
    @StateObject private var controller = PDFController()

    /// Drives the Cmd-F-style in-document search bar. `isSearchOpen`
    /// toggles its visibility; `searchQuery` is the live text the user
    /// has typed. Both reset to empty when the user dismisses the bar.
    @State private var isSearchOpen: Bool = false
    @State private var searchQuery: String = ""
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if isSearchOpen {
                    searchBar
                }
                body0
                bottomBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Re-run the search whenever the query text changes so the
        // match count updates as the user types. Cleared queries drop
        // matches without closing the bar (the user may be retyping).
        .onChange(of: searchQuery) { newValue in
            controller.runSearch(query: newValue)
        }
        .task { await load() }
        .onAppear {
            // Tapping a highlight on the page jumps straight into edit for
            // that note (per product decision). The notes list and sheet
            // flows handle every other entry point.
            controller.onHighlightTapped = { noteId in
                if let target = vm.notes.first(where: { $0.id == noteId }) {
                    editingNote = target
                    snapshotSelectedText = nil
                    snapshotPage = nil
                    showAddNote = true
                }
            }
        }
        // iOS 16 single-arg onChange — the project's deployment target is
        // 16.0 so the iOS 17 two-arg closure overload isn't available here.
        .onChange(of: pdfDocument != nil) { ready in
            // The PDFView only exists after pdfDocument is non-nil; apply
            // highlights once the bridge is alive.
            if ready {
                reapplyHighlights()
                resolveInitialFocus()
            }
        }
        .onChange(of: vm.notes) { _ in
            reapplyHighlights()
            // Notes can finish loading after the PDF is already up — in
            // that case the deep-link `initialFocusNoteId` resolves here
            // instead of in the `pdfDocument` handler above. Also picks
            // up the "auto-focus first note" branch for a non-deep-link
            // open where notes simply hadn't arrived yet at first render.
            resolveInitialFocus()
        }
        .onChange(of: currentPage) { _ in
            reapplyHighlights()
            // Two independent jobs on a page change:
            //
            //   1. We intentionally do NOT clear `focusedNote` when the
            //      student pages off its pinned page. An earlier
            //      version did that to hide the callout, but cleared
            //      the state as a side effect, so paging back never
            //      re-showed the note. Render gating happens in
            //      `visibleFocusedNote`: the callout hides when the
            //      current page doesn't match `pinnedPage`, and
            //      re-appears when the student returns. `focusedNote`
            //      is only cleared on explicit close / edit / dismiss.
            //
            //   2. Auto-focus the first note on the *new* page when
            //      nothing is already focused there. This is what makes
            //      "land on any page that has notes → see the popup"
            //      work for normal forward / backward navigation. The
            //      `visibleFocusedNote == nil` guard means we don't
            //      override a focus that's already pointing at this
            //      page (e.g. the user paged back to where they were).
            if visibleFocusedNote == nil, let first = pageNotes.first {
                focusedNote = first
            }
        }
        .sheet(isPresented: $showAddNote, onDismiss: {
            snapshotSelectedText = nil
            snapshotPage = nil
            editingNote = nil
        }) {
            // June 2026 redesign: two-field compose sheet (CONTENT excerpt +
            // YOUR NOTE body). Presented as a partial sheet so the page stays
            // partly visible behind it, matching the Figma.
            DocumentNoteComposerView(
                existing: editingNote,
                pageOneBased: editingNote?.pinnedPage ?? snapshotPage ?? currentPage,
                documentTitle: lessonTitle.isEmpty ? document.filename : lessonTitle,
                noteIndex: composerNoteIndex,
                capturedSource: snapshotSelectedText,
                onSave: { body, source in
                    if let existing = editingNote {
                        // Update endpoint accepts `content` only — the excerpt
                        // is shown read-only in edit mode so nothing is lost.
                        return await vm.editNote(existing.id, content: body) != nil
                    } else {
                        // V45 contract: a document note needs both the owning
                        // `document_id` and the `pinned_page`. Default the page
                        // to the currently visible page if the snapshot is
                        // missing for any reason.
                        return await vm.addDocumentNote(
                            content: body,
                            documentId: document.id,
                            pinnedPage: snapshotPage ?? currentPage,
                            selectedText: source
                        ) != nil
                    }
                },
                onCancel: { showAddNote = false },
                onSaved: {
                    let page = snapshotPage ?? editingNote?.pinnedPage ?? currentPage
                    showAddNote = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        savedToastLabel = String(format: L10n.lessonNotesPagePrefixFmt, page)
                        showSavedToast = true
                    }
                },
                onDelete: {
                    guard let target = editingNote else { return }
                    deletedSnapshot = target
                    showAddNote = false
                    Task { await vm.deleteNote(target.id) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showDeletedToast = true
                    }
                }
            )
            .presentationDetentsMediumLargeIfAvailable()
        }
        .overlay { notesOnPagePanel }
        // Top-anchored confirmation toasts (Figma 1706 redesign). "Saved"
        // auto-dismisses; "Deleted" carries an Undo that re-creates the note.
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if showSavedToast {
                    TopNoteToast(kind: .saved)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showDeletedToast {
                    TopNoteToast(kind: .deleted, onAction: undoDelete)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 4)
        }
        .overlay(alignment: .bottom) {
            if let note = visibleFocusedNote {
                NoteCommentCallout(
                    note: note,
                    // Pager metadata — when the page has more than one
                    // note, the callout renders chevrons and an "X of N"
                    // label so the student can walk through siblings
                    // without bouncing back to MyNotes between each one.
                    // We pass the live index/total instead of a `Bool`
                    // because the callout uses the values directly in
                    // the position indicator.
                    siblingIndex: focusedNoteIndexOnPage ?? 0,
                    siblingCount: pageNotes.count,
                    onPrev: { stepFocusedNote(by: -1) },
                    onNext: { stepFocusedNote(by: 1) },
                    onEdit: {
                        editingNote = note
                        focusedNote = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showAddNote = true
                        }
                    },
                    onClose: { focusedNote = nil }
                )
                // Pinned to the bottom (per Figma 1061:6279) so the note
                // reads as a caption under the page instead of a card
                // that floats over — and covers — the middle of the
                // slide. Clears the dark Prev/Add/My Notes/Next toolbar.
                .padding(.horizontal, 16)
                .padding(.bottom, 78)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showSavedToast)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showDeletedToast)
        // Animate on the *visible* note's id, not the stored focus. The
        // stored focus persists across pages but the overlay only
        // mounts when `pinnedPage == currentPage`; keying the animation
        // to the visible id triggers the spring transition each time
        // the student pages back onto the note.
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: visibleFocusedNote?.id)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showNotesOnPage)
        .task(id: showSavedToast) {
            guard showSavedToast else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            guard showSavedToast else { return }
            showSavedToast = false
        }
        .task(id: showDeletedToast) {
            guard showDeletedToast else { return }
            // Slightly longer than the saved toast so Undo is reachable.
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if Task.isCancelled { return }
            guard showDeletedToast else { return }
            showDeletedToast = false
            deletedSnapshot = nil
        }
        // My Notes — same screen the lesson player uses, presented full-
        // screen because the reader itself is a fullScreenCover and so has
        // no surrounding NavigationStack to push onto. Document-anchored
        // taps stay inside the reader (PDFView jumps page); video-anchored
        // taps close the reader so the player owner can seek.
        .fullScreenCover(isPresented: $showMyNotes) {
            MyNotesView(
                vm: MyNotesViewModel(lessonId: lessonId),
                lessonNumber: lessonNumber,
                lessonTitle: lessonTitle.isEmpty ? document.filename : lessonTitle,
                onJumpToVideoTimestamp: { ts, noteId in
                    // Hand the seek target up to the player BEFORE closing
                    // the reader. The reader doesn't own the AVPlayer, so
                    // without forwarding (ts, noteId) the player would
                    // dismiss with nothing queued and the tap would be a
                    // no-op.
                    onJumpToVideoTimestamp?(ts, noteId)
                    dismiss()
                },
                onJumpToDocument: { docId, page, noteId in
                    if docId == document.id {
                        // Pre-set focusedNote so the page-change handler
                        // sees the matching pinnedPage and doesn't clear
                        // the focus before the overlay can render.
                        focusedNote = vm.notes.first(where: { $0.id == noteId })
                        controller.go(to: page)
                    } else {
                        // A different document — close this reader so the
                        // player can present the right one.
                        dismiss()
                    }
                },
                onEdit: { note in
                    editingNote = note
                    showMyNotes = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showAddNote = true
                    }
                }
            )
        }
        .sheet(item: $pendingExport) { url in
            ActivityShareSheet(activityItems: [url])
        }
    }

    /// All notes anchored to the page that's currently on screen,
    /// sorted by `createdAt` ASC. This is the same stable ordering the
    /// in-page numbered highlight badges use (`renderHighlights(...)`),
    /// so the prev/next pager in the callout walks through the notes
    /// in the same direction the badges count up. Includes notes with
    /// AND without a `selectedText` snippet — a page-only comment is
    /// still a sibling and should appear in the carousel.
    /// "Notes on this page" — a custom bottom panel (Figma 1695:11250)
    /// rather than a system `.sheet`. A system sheet dims the whole screen,
    /// which blacked out the PDF the notes refer to; this panel covers
    /// ~72% of the height and leaves the page header bright and visible
    /// above it, with tap-above / drag-down to dismiss.
    @ViewBuilder
    private var notesOnPagePanel: some View {
        if showNotesOnPage {
            ZStack(alignment: .bottom) {
                // Transparent tap-catcher: keeps the page bright (no dim)
                // while still letting a tap above the panel dismiss it.
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .ignoresSafeArea()
                    .onTapGesture { showNotesOnPage = false }

                NotesOnThisPageSheet(
                    pageOneBased: currentPage,
                    documentTitle: lessonTitle.isEmpty ? document.filename : lessonTitle,
                    notes: pageNotes,
                    onAdd: {
                        showNotesOnPage = false
                        editingNote = nil
                        snapshotSelectedText = controller.captureSelection().text
                        snapshotPage = currentPage
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showAddNote = true
                        }
                    },
                    onSelect: { note in
                        showNotesOnPage = false
                        focusedNote = note
                    },
                    onAllNotes: {
                        showNotesOnPage = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showMyNotes = true
                        }
                    },
                    onClose: { showNotesOnPage = false }
                )
                .offset(y: notesPanelDrag)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            notesPanelDrag = max(0, value.translation.height)
                        }
                        .onEnded { value in
                            if value.translation.height > 80 {
                                showNotesOnPage = false
                                notesPanelDrag = 0
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    notesPanelDrag = 0
                                }
                            }
                        }
                )
                // Float the compact peek panel just above the bottom
                // toolbar (Figma 1695:11099) rather than covering it.
                .padding(.bottom, bottomBarHeight)
                .transition(.move(edge: .bottom))
            }
        }
    }

    private var pageNotes: [LessonNoteItem] {
        vm.notes
            .filter { $0.pinnedPage == currentPage }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// "Note N" position for the composer subtitle. When editing, the
    /// note's 1-based slot among its page siblings; when composing, the
    /// next slot (capped at the per-page soft limit).
    private var composerNoteIndex: Int {
        if let editing = editingNote,
           let idx = pageNotes.firstIndex(where: { $0.id == editing.id }) {
            return idx + 1
        }
        let page = snapshotPage ?? currentPage
        let count = vm.notes.filter { $0.pinnedPage == page }.count
        return min(count + 1, kMaxNotesPerPage)
    }

    /// Re-creates the most recently deleted note (best-effort) when the
    /// student taps Undo on the deleted toast. A re-created note gets a
    /// fresh id from the backend, which is fine for an undo.
    private func undoDelete() {
        guard let snap = deletedSnapshot, let page = snap.pinnedPage else {
            showDeletedToast = false
            return
        }
        showDeletedToast = false
        deletedSnapshot = nil
        Task {
            _ = await vm.addDocumentNote(
                content: snap.content,
                documentId: document.id,
                pinnedPage: page,
                selectedText: snap.selectedText)
        }
    }

    /// The note to render in the floating callout *right now*, or nil
    /// when nothing should be shown. Composes three rules:
    ///
    ///   1. `focusedNote` must be set (deep-link from MyNotesView, or a
    ///      tap on a comment pin on the page).
    ///   2. The note must still exist in `vm.notes` — guards against a
    ///      stale snapshot lingering after a delete from another tab.
    ///   3. The live note's `pinnedPage` must match `currentPage` — the
    ///      callout only floats over the page the note is anchored to.
    ///
    /// Re-resolving from `vm.notes` (instead of trusting the stored
    /// `focusedNote` snapshot) also picks up edits that landed while
    /// the student was browsing other pages, so paging back surfaces
    /// fresh content rather than the value captured at first focus.
    private var visibleFocusedNote: LessonNoteItem? {
        guard let stored = focusedNote else { return nil }
        guard let live = vm.notes.first(where: { $0.id == stored.id }) else {
            return nil
        }
        guard live.pinnedPage == currentPage else { return nil }
        return live
    }

    /// Zero-based position of the focused note inside `pageNotes`, or
    /// nil when the focused note isn't on this page. Drives the
    /// "X of N" pager label and the enabled state of the prev/next
    /// chevrons in the callout header.
    private var focusedNoteIndexOnPage: Int? {
        guard let visible = visibleFocusedNote else { return nil }
        return pageNotes.firstIndex(where: { $0.id == visible.id })
    }

    /// Walks the focus to the note at `offset` positions away from the
    /// current one inside `pageNotes`. No-op when the move would fall
    /// off either end — the caller (the chevron buttons) is responsible
    /// for hiding itself when at a boundary, but this guard keeps the
    /// state machine honest if anything else ever invokes it.
    private func stepFocusedNote(by offset: Int) {
        guard let idx = focusedNoteIndexOnPage else { return }
        let next = idx + offset
        guard next >= 0, next < pageNotes.count else { return }
        focusedNote = pageNotes[next]
    }

    /// Picks the right note to surface in the callout the first time
    /// the reader has both a PDF rendered AND a loaded notes list.
    /// Called from both the `pdfDocument != nil` and `vm.notes` change
    /// handlers because either side can arrive last on a cold open.
    ///
    /// Priority order:
    ///   1. `initialFocusNoteId` — the student deep-linked from
    ///      MyNotesView. Open with their pick selected.
    ///   2. First note on the *current* page, sorted by created_at.
    ///      Makes a plain "open the reader" land on the popup
    ///      automatically when the landing page happens to have
    ///      notes, matching the per-page auto-show in `onChange(of:
    ///      currentPage)`.
    ///   3. Nothing — no notes are anchored to this page; callout
    ///      stays hidden until the student pages onto one that has
    ///      notes.
    ///
    /// The `focusedNote == nil` guard makes this idempotent: once a
    /// focus is set (by this method, by deep-link, by the page-change
    /// handler, or by a manual pin tap), a later notes-arrival or PDF-
    /// ready event won't reset it.
    private func resolveInitialFocus() {
        guard focusedNote == nil else { return }
        if let noteId = initialFocusNoteId,
           let note = vm.notes.first(where: { $0.id == noteId }) {
            focusedNote = note
            return
        }
        if let first = pageNotes.first {
            focusedNote = first
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    if !lessonNumber.isEmpty {
                        Text(String(format: L10n.lessonPdfEyebrowFmt, lessonNumber))
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.6)
                    }
                }
                .foregroundColor(MyCoursesPalette.textPrimary)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            VStack(spacing: 1) {
                Text(displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(1)
                Text(String(format: L10n.lessonPdfPageOfFmt,
                            currentPage,
                            pageCount > 0 ? pageCount : (document.pageCount ?? 0)))
                    .font(.system(size: 11))
                    .foregroundColor(MyCoursesPalette.muted)
            }

            Spacer(minLength: 4)

            // Notes affordance with a live count badge (Figma 1706) — jumps
            // to the full My Notes screen. Hidden when the lesson has no
            // notes so the header stays clean on a fresh document.
            if !vm.notes.isEmpty {
                Button { showMyNotes = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "note.text")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.textPrimary.opacity(0.85))
                            .frame(width: 36, height: 36)
                        Text("\(vm.notes.count)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.droobGold))
                            .offset(x: 2, y: -2)
                    }
                }
                .buttonStyle(.plain)
            }

            // Search affordance — toggles the Cmd-F-style in-document
            // search bar that floats below the header. Active state is
            // gold-tinted so the user can see the affordance is "on".
            Button {
                if isSearchOpen {
                    // Toggle-off: close + clear matches so the next
                    // open starts fresh.
                    isSearchOpen = false
                    searchFieldFocused = false
                    searchQuery = ""
                    controller.endSearch()
                } else {
                    isSearchOpen = true
                    // Defer focus a frame so the field is in the
                    // hierarchy by the time SwiftUI honours
                    // `searchFieldFocused = true`.
                    DispatchQueue.main.async {
                        searchFieldFocused = true
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSearchOpen
                                     ? MyCoursesPalette.accent
                                     : MyCoursesPalette.textPrimary.opacity(0.85))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Search bar

    /// Cmd-F-style search bar that drops in below the header when the
    /// magnifying-glass button is active. Mirrors the affordance the
    /// user would expect from a desktop "find in document":
    ///   - text field with placeholder
    ///   - "3 of 12" match counter (or "No matches")
    ///   - ↑/↓ to step between matches
    ///   - ✕ to dismiss + clear the search
    private var searchBar: some View {
        let matchCount = controller.searchMatches.count
        let cursor = controller.currentMatchIndex
        let hasQuery = !searchQuery.trimmingCharacters(
            in: .whitespacesAndNewlines).isEmpty

        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
                TextField(L10n.lessonPdfSearchPlaceholder,
                          text: $searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .font(.system(size: 14))
                    .focused($searchFieldFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        // Enter advances to the next match so the
                        // hardware-keyboard / iPad path matches the
                        // chevron behaviour.
                        if matchCount > 0 { controller.nextMatch() }
                    }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(MyCoursesPalette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(MyCoursesPalette.stroke, lineWidth: 1)))

            // Match count — "3 of 12", "No matches", or hidden until
            // the user types something.
            if hasQuery {
                Text(matchCount == 0
                     ? L10n.lessonPdfSearchNoMatches
                     : String(format: L10n.lessonPdfSearchMatchCountFmt,
                              (cursor ?? 0) + 1, matchCount))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(matchCount == 0
                                     ? MyCoursesPalette.textTertiary
                                     : MyCoursesPalette.muted)
                    .fixedSize(horizontal: true, vertical: false)
            }

            // Prev / Next — disabled when there's nothing to step
            // through so the user gets the right affordance.
            Button { controller.previousMatch() } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(matchCount > 0
                                     ? MyCoursesPalette.textPrimary.opacity(0.85)
                                     : MyCoursesPalette.textTertiary.opacity(0.5))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(matchCount == 0)

            Button { controller.nextMatch() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(matchCount > 0
                                     ? MyCoursesPalette.textPrimary.opacity(0.85)
                                     : MyCoursesPalette.textTertiary.opacity(0.5))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(matchCount == 0)

            Button {
                isSearchOpen = false
                searchFieldFocused = false
                searchQuery = ""
                controller.endSearch()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var displayTitle: String {
        if !lessonTitle.isEmpty { return lessonTitle }
        // Strip a leading UUID prefix + extension defensively so we don't
        // leak an ugly storage key into the header.
        var n = document.filename
        let uuid = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[-_ ]+"#
        if let r = n.range(of: uuid, options: .regularExpression) { n.removeSubrange(r) }
        if let dot = n.lastIndex(of: ".") { n = String(n[..<dot]) }
        return n.isEmpty ? document.filename : n
    }

    // MARK: - Body

    /// Renamed to `body0` because SwiftUI views already have `body`.
    @ViewBuilder
    private var body0: some View {
        if let err = loadError {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.orange)
                Text(err)
                    .font(.system(size: 14))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let doc = pdfDocument {
            PDFKitView(
                document: doc,
                initialPage: initialPage,
                controller: controller,
                onPageChanged: { idx in handlePageChange(idx) }
            )
        } else {
            ProgressView()
                .tint(MyCoursesPalette.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Bottom toolbar

    // Figma 1706 bottom bar: ‹ Prev | [Notes N] pill | "12 / 18" + gold
    // progress underline (centre) | ✎ Add | Next ›. The old "My Notes"
    // item folds into the Notes pill, which opens the Notes-on-this-page
    // sheet.
    private var bottomBar: some View {
        HStack(spacing: 6) {
            bottomItem(icon: "chevron.left", title: L10n.lessonPdfPrev) {
                controller.goToPrevious()
            }
            .disabled(currentPage <= 1)
            .opacity(currentPage <= 1 ? 0.4 : 1)

            notesPill

            pageProgress
                .frame(maxWidth: .infinity)

            bottomItem(icon: "square.and.pencil", title: L10n.lessonPdfAdd, iconSize: 18) {
                let snap = controller.captureSelection()
                snapshotSelectedText = snap.text
                snapshotPage = snap.pageOneBased ?? currentPage
                editingNote = nil
                showAddNote = true
                // Deselect after snapshotting so the highlight doesn't linger
                // visually after the compose sheet covers the page.
                controller.clearSelection()
            }

            bottomItem(icon: "chevron.right", title: L10n.lessonPdfNext) {
                controller.goToNext()
            }
            .disabled(currentPage >= effectivePageCount)
            .opacity(currentPage >= effectivePageCount ? 0.4 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // Figma: page-background surface with a hairline top border, so the
        // bar separates from the PDF page without floating off the chrome.
        .background(MyCoursesPalette.background)
        .overlay(
            Rectangle()
                .fill(MyCoursesPalette.stroke)
                .frame(height: 1),
            alignment: .top
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: BottomBarHeightKey.self,
                    value: proxy.size.height
                )
            }
        )
        .onPreferenceChange(BottomBarHeightKey.self) { bottomBarHeight = $0 }
    }

    /// Gold-outlined "Notes N" pill — opens the Notes-on-this-page sheet.
    /// Figma: translucent-gold fill (10%), thin 0.85px gold border (40%),
    /// sans-serif "Notes", and a *solid* gold count badge with dark text.
    private var notesPill: some View {
        Button { showNotesOnPage = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "note.text")
                    .font(.system(size: 13, weight: .regular))
                Text(L10n.lessonPdfNotesPill)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(-0.24)
                    // Never let the label wrap into a vertical
                    // letter-stack when the bottom bar gets tight.
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text("\(pageNotes.count)")
                    .font(.system(size: 9.5, weight: .bold))
                    // Dark ink on the solid-gold chip (Figma orange/6-2 #1A1305).
                    .foregroundColor(Color(red: 0.102, green: 0.075, blue: 0.020))
                    .padding(.horizontal, 4.5)
                    .frame(minWidth: 15.5, minHeight: 15.5)
                    .background(Capsule().fill(Color.droobGold))
            }
            .foregroundColor(MyCoursesPalette.accent)
            .padding(.leading, 8.5)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.droobGold.opacity(0.10))
                    .overlay(Capsule().stroke(MyCoursesPalette.accent.opacity(0.4), lineWidth: 0.85))
            )
        }
        .buttonStyle(.plain)
    }

    /// Centre page indicator with a gold reading-progress underline.
    private var pageProgress: some View {
        let total = pageCount > 0 ? pageCount : (document.pageCount ?? 0)
        let fraction = total > 0 ? min(1, max(0, Double(currentPage) / Double(total))) : 0
        return VStack(spacing: 5) {
            (
                Text("\(currentPage)")
                    .foregroundColor(MyCoursesPalette.accent)
                + Text(" / \(total)")
                    .foregroundColor(MyCoursesPalette.textPrimary)
            )
            .font(BrandFont.display(size: 17.5, isArabic: appLocale == "ar"))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(MyCoursesPalette.surface)
                        .frame(height: 3.3)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 224 / 255, green: 196 / 255, blue: 143 / 255),
                                    Color(red: 198 / 255, green: 169 / 255, blue: 107 / 255)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * fraction, height: 3.3)
                }
            }
            .frame(height: 3.3)
            .frame(maxWidth: 99)
        }
    }

    private var effectivePageCount: Int {
        let n = pageCount > 0 ? pageCount : (document.pageCount ?? Int.max)
        return n
    }

    private func bottomItem(icon: String, title: String, iconSize: CGFloat = 22, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundColor(MyCoursesPalette.accent)
                Text(title)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(MyCoursesPalette.accent)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            // Fixed-width nav items so only `pageProgress` flexes. Four
            // greedy `.frame(maxWidth: .infinity)` siblings would otherwise
            // split the row evenly and squeeze the Notes pill until its
            // label wrapped one-letter-per-line.
            .frame(width: 50)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading

    private func load() async {
        async let progressTask: ReadingProgressState? = try? LessonInteractionsAPI
            .getReadingProgress(lessonId: lessonId, documentId: document.id)

        guard let docUrl = URL(string: document.viewUrl) else {
            loadError = L10n.lessonPdfInvalidUrl
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: docUrl)
            let progress = await progressTask
            await MainActor.run {
                if let pdf = PDFDocument(data: data) {
                    pdfDocument = pdf
                    pageCount = pdf.pageCount
                    // Deep-link override wins over saved progress, so a
                    // "jump to page" from My Notes lands on the right page
                    // even when the student had previously read further.
                    let resolved = initialPageOverride
                        ?? progress?.currentPage
                        ?? 1
                    initialPage = max(1, resolved)
                    currentPage = initialPage
                } else {
                    loadError = L10n.lessonPdfOpenFailed
                }
                cacheForExport(data: data)
            }
        } catch {
            await MainActor.run { loadError = error.localizedDescription }
        }
    }

    private func cacheForExport(data: Data) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(document.filename)
        try? data.write(to: tmp, options: [.atomic])
        url = tmp
    }

    // MARK: - Page tracking

    @State private var lastReported: Int = -1
    @State private var inflightTask: Task<Void, Never>? = nil

    /// Rebuilds the highlight overlays for whatever page is currently visible.
    /// Cheap to call — `PDFController.applyHighlights` removes the old
    /// annotations before adding new ones, so spamming this on every notes
    /// mutation is fine.
    private func reapplyHighlights() {
        guard pdfDocument != nil else { return }
        controller.applyHighlights(
            notesByCreatedAt: vm.notes,
            currentPageOneBased: currentPage
        )
    }

    private func handlePageChange(_ index: Int) {
        let oneBased = max(1, index)
        currentPage = oneBased
        guard oneBased != lastReported else { return }
        inflightTask?.cancel()
        inflightTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            _ = try? await LessonInteractionsAPI.putReadingProgress(
                lessonId: lessonId,
                documentId: document.id,
                currentPage: oneBased)
            lastReported = oneBased
        }
    }
}

// MARK: - PDFKit bridge

/// SwiftUI-side handle to the underlying PDFView so the toolbar (Prev / Next /
/// programmatic jumps) can drive PDFKit without forcing a SwiftUI rebuild,
/// and so the Add Note flow can read the user's current text selection.
final class PDFController: ObservableObject {
    weak var view: PDFView?

    /// Updated whenever the user changes the selection. Published so the
    /// SwiftUI side can react (e.g. enable a "quote this passage" pill).
    /// `nil` whitespace strings are normalised to `nil`.
    @Published var selectedText: String? = nil

    /// Fired when the user taps one of our note-highlight annotations.
    /// Carries the note id so the host can open the Add Note sheet in edit
    /// mode for that exact note. Wired to PDFKit's
    /// `PDFViewAnnotationHit` notification in `PDFKitView`.
    var onHighlightTapped: ((String) -> Void)? = nil

    /// Annotations we've added per page, keyed by note id. Tracked so we can
    /// surgically remove them on re-render without disturbing user-drawn
    /// annotations the PDF may already have.
    private var addedAnnotations: [String: [PDFAnnotation]] = [:]

    func goToNext() { view?.goToNextPage(nil) }
    func goToPrevious() { view?.goToPreviousPage(nil) }
    func go(to oneBasedPage: Int) {
        guard let v = view, let doc = v.document,
              let page = doc.page(at: max(0, oneBasedPage - 1)) else { return }
        v.go(to: page)
    }

    /// Returns the live selection at call time + the 1-based current page so
    /// the Add Note flow can snapshot both atomically.
    func captureSelection() -> (text: String?, pageOneBased: Int?) {
        guard let v = view, let doc = v.document else { return (nil, nil) }
        let text = v.currentSelection?.string?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText: String? = (text?.isEmpty == false) ? text : nil
        let pageIdx: Int? = v.currentPage.map { doc.index(for: $0) + 1 }
        return (cleanText, pageIdx)
    }

    /// Clears the active selection — call after the Add Note sheet opens so
    /// the highlight visual disappears, since the snapshot is already on the
    /// compose sheet.
    func clearSelection() {
        view?.clearSelection()
    }

    /// Pulled by the PDFKit notification observer.
    func refreshSelectedText() {
        let s = view?.currentSelection?.string?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalised: String? = (s?.isEmpty == false) ? s : nil
        if normalised != selectedText {
            selectedText = normalised
        }
    }

    // MARK: - Text search
    //
    // Cmd-F-style in-document text search. The host view owns the
    // search bar UI (query field + prev/next + close); this controller
    // owns the PDFKit interop.
    //
    // We pick `PDFDocument.findString(_:withOptions:)` over the
    // delegate-based `PDFView.beginFindString` so the host can:
    //   1. show a synchronous "X of N" match count without juggling
    //      a delegate;
    //   2. navigate forward/back deterministically by indexing into
    //      the returned `[PDFSelection]`.
    // For a multi-thousand-page document the synchronous call could
    // be slow, but lesson PDFs are short enough that a blocking
    // search is the right ergonomic call.

    /// All matches for the most recent query, in document order. Empty
    /// when no search is active or there are no matches.
    @Published private(set) var searchMatches: [PDFSelection] = []
    /// Zero-based pointer into `searchMatches`. `nil` whenever
    /// `searchMatches` is empty.
    @Published private(set) var currentMatchIndex: Int? = nil

    /// Recomputes `searchMatches` against the active document. Pass an
    /// empty/whitespace string to clear the search.
    func runSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty / whitespace-only query → clear the search but leave
        // the bar open (the user may still be retyping).
        if trimmed.isEmpty {
            searchMatches = []
            currentMatchIndex = nil
            view?.clearSelection()
            return
        }
        guard let v = view, let doc = v.document else {
            searchMatches = []
            currentMatchIndex = nil
            return
        }
        // .caseInsensitive + .diacriticInsensitive matches the spirit
        // of a "search in document" affordance — users typing a Latin
        // approximation of an Arabic word still get hits.
        let opts: NSString.CompareOptions = [.caseInsensitive,
                                              .diacriticInsensitive]
        let results = doc.findString(trimmed, withOptions: opts)
        searchMatches = results
        currentMatchIndex = results.isEmpty ? nil : 0
        if !results.isEmpty {
            highlightCurrentMatch()
        } else {
            v.clearSelection()
        }
    }

    /// Moves the cursor to the next match, wrapping at the end. No-op
    /// when no search is active.
    func nextMatch() {
        guard !searchMatches.isEmpty,
              let idx = currentMatchIndex else { return }
        currentMatchIndex = (idx + 1) % searchMatches.count
        highlightCurrentMatch()
    }

    /// Moves the cursor to the previous match, wrapping at the start.
    func previousMatch() {
        guard !searchMatches.isEmpty,
              let idx = currentMatchIndex else { return }
        currentMatchIndex = (idx - 1 + searchMatches.count) % searchMatches.count
        highlightCurrentMatch()
    }

    /// Clears the active search — drops matches + the highlight, but
    /// leaves the page position alone.
    func endSearch() {
        searchMatches = []
        currentMatchIndex = nil
        view?.clearSelection()
    }

    /// Selects + scrolls to the active match. Highlighting is rendered
    /// by PDFKit's own "current selection" affordance (gold-tinted
    /// box) so we don't need to mint a temporary annotation.
    private func highlightCurrentMatch() {
        guard let v = view,
              let idx = currentMatchIndex,
              idx < searchMatches.count else { return }
        let selection = searchMatches[idx]
        v.setCurrentSelection(selection, animate: true)
        v.scrollSelectionToVisible(nil)
    }

    // MARK: - Note highlight overlays

    /// Re-renders the gold highlight + numbered badge annotations for the
    /// given notes. Notes without a `selectedText` are skipped (page-only
    /// notes have nothing to highlight). Numbering is per-page, in the order
    /// the notes appear in `notesByCreatedAt`.
    ///
    /// Safe to call repeatedly — previously added annotations are removed
    /// before the new ones go in, so this can drive every "notes changed"
    /// or "page changed" reaction without leaking annotations.
    func applyHighlights(
        notesByCreatedAt: [LessonNoteItem],
        currentPageOneBased: Int
    ) {
        guard let v = view, let doc = v.document else { return }
        removeAllAddedAnnotations()

        let pageIdx = max(0, currentPageOneBased - 1)
        guard pageIdx < doc.pageCount, let page = doc.page(at: pageIdx) else { return }

        // Filter + stable-order the notes that belong on this page so the
        // numbered badges agree across re-renders (created_at ASC).
        let pageNotes = notesByCreatedAt
            .filter {
                $0.pinnedPage == currentPageOneBased
                && ($0.selectedText?.isEmpty == false)
            }
            .sorted { $0.createdAt < $1.createdAt }

        for (idx, note) in pageNotes.enumerated() {
            guard let quote = note.selectedText else { continue }
            let badgeNumber = idx + 1
            let added = addHighlight(for: note, quote: quote, on: page,
                                     in: doc, badgeNumber: badgeNumber)
            if !added.isEmpty {
                addedAnnotations[note.id] = added
            }
        }
    }

    /// Locates `quote` on `page`, draws a gold highlight annotation over
    /// each matched line, and stamps a small numbered circle just after the
    /// last line. Returns every annotation it added (so the caller can
    /// remove them later).
    ///
    /// PDFKit's `findString` matches across page boundaries, so we filter
    /// the result down to selections that live on `page`. If the quote can't
    /// be found — e.g. the PDF was reflowed or the student edited the
    /// excerpt — we no-op rather than guessing, keeping the page clean.
    private func addHighlight(
        for note: LessonNoteItem,
        quote: String,
        on page: PDFPage,
        in doc: PDFDocument,
        badgeNumber: Int
    ) -> [PDFAnnotation] {
        // findString returns one selection per match; we take the first match
        // on this page. Most notes capture a single passage so this is the
        // expected shape; multi-match cases (a phrase repeated on the same
        // page) get the earliest occurrence.
        let matches = doc.findString(quote, withOptions: [.caseInsensitive])
        guard let selection = matches.first(where: { sel in
            sel.pages.contains(page)
        }) else { return [] }

        var added: [PDFAnnotation] = []
        // selectionsByLine() splits a multi-line selection into one
        // sub-selection per visual line. After filtering to the lines that
        // actually live on `page`, each one becomes a separate highlight
        // rect so wrapped text doesn't get a single over-tall rectangle.
        let lineRects = selection.selectionsByLine()
            .filter { $0.pages.contains(page) }
            .map { $0.bounds(for: page) }

        // Highlight every line individually so multi-line selections wrap
        // correctly instead of being treated as one big rect.
        for rect in lineRects {
            let highlight = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            highlight.color = UIColor.systemYellow.withAlphaComponent(0.45)
            // Custom key the tap handler reads to route back to the note. We
            // store the routing id under `.name` because `.contents` doubles
            // as the visible glyph for some annotation types (notably
            // freeText badges below), so reserving `.name` for routing keeps
            // both safe.
            highlight.setValue("droob_note:\(note.id)", forAnnotationKey: .name)
            page.addAnnotation(highlight)
            added.append(highlight)
        }

        // Numbered badge — a filled gold circle just past the last highlight
        // line with the badge number on top. PDFKit doesn't ship a "circle
        // with text" annotation, so we stack a `.circle` (fill + border) and
        // a transparent `.freeText` (the number). Both share the same
        // routing id so tapping either jumps to the note.
        if let lastRect = lineRects.last {
            let badgeSize: CGFloat = 16
            let badgeRect = CGRect(
                x: lastRect.maxX + 4,
                y: lastRect.minY + (lastRect.height - badgeSize) / 2,
                width: badgeSize,
                height: badgeSize
            )
            let circle = PDFAnnotation(bounds: badgeRect, forType: .circle, withProperties: nil)
            circle.color = UIColor.systemYellow.withAlphaComponent(0.9)
            circle.interiorColor = UIColor.systemYellow.withAlphaComponent(0.9)
            circle.setValue("droob_note:\(note.id)", forAnnotationKey: .name)
            page.addAnnotation(circle)
            added.append(circle)

            let label = PDFAnnotation(bounds: badgeRect, forType: .freeText, withProperties: nil)
            label.color = .clear
            label.fontColor = UIColor(red: 0.08, green: 0.06, blue: 0.04, alpha: 1)
            label.font = UIFont.systemFont(ofSize: 10, weight: .bold)
            label.alignment = .center
            label.contents = "\(badgeNumber)"
            label.setValue("droob_note:\(note.id)", forAnnotationKey: .name)
            page.addAnnotation(label)
            added.append(label)
        }

        return added
    }

    /// Drops every annotation we previously added, leaving any author-drawn
    /// annotations in the PDF itself untouched.
    private func removeAllAddedAnnotations() {
        for (_, anns) in addedAnnotations {
            for ann in anns { ann.page?.removeAnnotation(ann) }
        }
        addedAnnotations.removeAll()
    }

    /// Maps a tapped PDFAnnotation back to a note id, if it was one we added.
    /// The routing id lives on `.name` (set in `addHighlight`) so it survives
    /// alongside the visible badge text stored in `.contents`.
    func noteId(for annotation: PDFAnnotation) -> String? {
        guard let raw = annotation.value(forAnnotationKey: .name) as? String,
              raw.hasPrefix("droob_note:") else { return nil }
        return String(raw.dropFirst("droob_note:".count))
    }
}

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let initialPage: Int
    let controller: PDFController
    let onPageChanged: (Int) -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(true, withViewOptions: nil)
        view.backgroundColor = UIColor(red: 0.95, green: 0.93, blue: 0.88, alpha: 1)
        if initialPage > 1, let target = document.page(at: max(0, initialPage - 1)) {
            view.go(to: target)
        }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: view
        )
        // Routes taps on our gold highlight / numbered-badge annotations back
        // through the controller so the host can open the matching note for
        // edit. Authored annotations in the PDF itself fire the same
        // notification — `noteId(for:)` returns nil for those so we ignore
        // them and let PDFKit's default action take over.
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.annotationHit(_:)),
            name: .PDFViewAnnotationHit,
            object: view
        )
        context.coordinator.view = view
        context.coordinator.controller = controller
        controller.view = view
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChanged: onPageChanged)
    }

    final class Coordinator: NSObject {
        let onPageChanged: (Int) -> Void
        weak var view: PDFView?
        weak var controller: PDFController?
        init(onPageChanged: @escaping (Int) -> Void) {
            self.onPageChanged = onPageChanged
        }
        @objc func pageChanged(_ note: Notification) {
            guard let v = view, let doc = v.document, let cur = v.currentPage else { return }
            onPageChanged(doc.index(for: cur) + 1)
        }
        @objc func selectionChanged(_ note: Notification) {
            controller?.refreshSelectedText()
        }
        @objc func annotationHit(_ note: Notification) {
            guard
                let ann = note.userInfo?["PDFAnnotationHit"] as? PDFAnnotation,
                let controller = controller,
                let noteId = controller.noteId(for: ann)
            else { return }
            controller.onHighlightTapped?(noteId)
        }
    }
}

// MARK: - Activity share sheet (Save-to-Files)

struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Detents helper (mirror of the one in LessonPlayerView)

private extension View {
    @ViewBuilder
    func presentationDetentsLargeIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }

    /// Medium + large detents with a drag indicator — used by the
    /// document-note compose sheet and the Notes-on-this-page sheet so
    /// they read as partial bottom sheets per the Figma.
    @ViewBuilder
    func presentationDetentsMediumLargeIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}

// MARK: - Floating note callout
//
// Figma-comment-style card layered on top of the PDF page. Shown when
// the student deep-links into a note from MyNotesView (or, in future,
// taps a corner pin on the page). Carries the note's full content plus
// the snippet it was anchored to so the saved text is visible on the
// slide rather than requiring a trip back to the notes list.

/// Measures the bottom toolbar's height so the notes peek panel can be
/// padded up to sit flush above it.
private struct BottomBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 64
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct NoteCommentCallout: View {
    let note: LessonNoteItem
    /// Zero-based position of this note among siblings on the same
    /// page. Used together with `siblingCount` to render the "X of N"
    /// label and to gate the prev/next chevrons at the edges.
    let siblingIndex: Int
    let siblingCount: Int
    let onPrev: () -> Void
    let onNext: () -> Void
    let onEdit: () -> Void
    let onClose: () -> Void

    /// Pager controls only earn their slot when the page has more than
    /// one note. With a single note the chevrons + "1 of 1" label
    /// would be visual noise.
    private var hasSiblings: Bool { siblingCount > 1 }
    private var canGoPrev: Bool { hasSiblings && siblingIndex > 0 }
    private var canGoNext: Bool { hasSiblings && siblingIndex < siblingCount - 1 }

    /// Card fill from Figma 1061:6279 — fixed dark (rgba(28,28,30,0.94))
    /// rather than the adaptive palette so the caption always reads as a
    /// dark chip over the light "paper" PDF page, in either color scheme.
    private static let cardFill = Color(
        red: 28 / 255.0, green: 28 / 255.0, blue: 30 / 255.0
    ).opacity(0.94)

    var body: some View {
        HStack(spacing: 0) {
            // Flush gold accent bar on the leading edge — the left side
            // is square (only the trailing corners are rounded) so the
            // bar reads as a border, matching the Figma caption.
            Rectangle()
                .fill(Color.droobGold)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                header
                // Render the body as a fixed-size, line-limited caption.
                // A bare ScrollView is greedy vertically and — on the
                // automatic-popup path — could balloon the card until it
                // swallowed the whole slide. `.fixedSize` + `.lineLimit`
                // pin the caption to its intrinsic (capped) height no
                // matter what; the full text is always one tap away via
                // Edit / My Notes.
                Text(note.content)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineSpacing(4)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 15)
            .padding(.trailing, 15)
            .padding(.vertical, 13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Belt-and-braces against the full-slide blow-up: pin the card to
        // its intrinsic vertical height so it hugs the caption rather than
        // greedily taking whatever the overlay slot offers.
        .fixedSize(horizontal: false, vertical: true)
        .background(Self.cardFill)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 13,
                topTrailingRadius: 13,
                style: .continuous
            )
        )
        .shadow(color: Color.black.opacity(0.6), radius: 20, x: 0, y: 14)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "note.text")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.droobGold)
            Text(eyebrowText)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundColor(Color.droobGold)
                .lineLimit(1)
            Spacer(minLength: 8)
            if hasSiblings {
                pagerControls
            }
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.droobGold)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
    }

    /// "YOUR NOTE · PAGE 7", or just "YOUR NOTE" when the note carries
    /// no pinned page.
    private var eyebrowText: String {
        if let page = note.pinnedPage {
            return String(format: L10n.lessonNotesCalloutEyebrowFmt, page)
        }
        return L10n.lessonNotesCalloutEyebrow
    }

    /// "‹  2 of 3  ›" cluster shown in the header when the page has
    /// more than one note. Each chevron disables (greys out + no-op)
    /// at the boundary so the student can tell when they've reached
    /// the first / last note without the button silently swallowing
    /// taps.
    private var pagerControls: some View {
        HStack(spacing: 6) {
            pagerButton(
                systemName: "chevron.left",
                enabled: canGoPrev,
                action: onPrev
            )
            // Digit / digit around a neutral separator: isolate the whole pair
            // so the Arabic paragraph cannot swap "2 / 3" into "3 / 2".
            Text("\(siblingIndex + 1) / \(siblingCount)".bidiIsolated)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(minWidth: 34)
            pagerButton(
                systemName: "chevron.right",
                enabled: canGoNext,
                action: onNext
            )
        }
    }

    private func pagerButton(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(enabled ? Color.droobGold : .white.opacity(0.7))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
