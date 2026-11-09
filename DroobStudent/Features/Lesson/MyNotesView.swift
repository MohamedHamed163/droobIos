import SwiftUI

// MARK: - MyNotesView
//
// Figma-accurate "My Notes" screen. Pushed onto the navigation stack from
// the lesson player and the PDF reader; scope is one lesson + its documents.
//
// Composition (top to bottom):
//   • header — back chevron, italic gold "My Notes" title, no trailing
//     button (the Figma intentionally has nothing on the right).
//   • filter strip — three rounded pills, All / Document / Video. The
//     active pill gets the brand gold gradient + dark text.
//   • subtitle — "12 NOTES · 2 SOURCES", reading counts from the VM.
//   • list — scrollable cards. Each card carries a type badge, a relative
//     date (Today / Yesterday / "MMM d"), the note content, a divider, and
//     an anchor pill + lesson/source line.
//
// Pagination is keyset cursor-based on the VM. The `onAppear` of the last-
// visible card fires `loadMoreIfNeeded`.
//
// Tap behaviour is delegated upward: the host (LessonPlayerView) seeks the
// video / opens the PDF at the matching page after the screen pops.

/// Hides everything that splits this list by note *source* — the
/// All / Document / Video filter pills and the per-card VIDEO / DOCUMENT
/// badge — so the screen reads as one unified list of notes (2026-08).
///
/// Video-anchored note-taking is being retired (see `hideVideoNotes` in
/// `LessonPlayerView`), which left the two-category UI describing a
/// distinction the student can no longer make. The per-card *anchor* chip
/// (`4:32` / `p.7`) deliberately stays: that isn't a category label, it's
/// the only hint of where a tap will land.
///
/// Hidden rather than deleted. `LessonNotesFilter` still round-trips to the
/// backend's `type` query param and `vm.filter` simply stays `.all`, so
/// flipping this to `false` restores the old screen whole.
private let hideNoteTypeSplit: Bool = true

struct MyNotesView: View {
    @StateObject var vm: MyNotesViewModel

    /// Static lesson context shown on every card's footer. The screen is
    /// lesson-scoped, so this is the same for every row.
    let lessonNumber: String
    let lessonTitle: String

    /// Host-supplied actions. The view itself only pops; the host is
    /// responsible for the actual seek / open behaviour because it owns the
    /// `AVPlayer` and the PDF reader presentation.
    /// `noteId` lets the host pin the explicit selection so an adjacent
    /// note within the same active-window doesn't steal the highlight
    /// after the seek.
    let onJumpToVideoTimestamp: (_ seconds: Int, _ noteId: String) -> Void
    /// `noteId` lets the host surface the tapped note's content on the
    /// landing page (Figma-comment-style callout) — without it the host
    /// only knows which page to flip to, not which note to highlight.
    let onJumpToDocument: (_ documentId: String, _ page: Int, _ noteId: String) -> Void
    let onEdit: (LessonNoteItem) -> Void
    /// Compose a brand-new note from inside the list. Optional because the PDF
    /// reader has its own add-note affordance and doesn't want a second one;
    /// the lesson player, where this list *is* the notes entry point, passes it.
    var onAddNote: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if !hideNoteTypeSplit {
                    filterStrip
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }
                subtitle
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if vm.items.isEmpty {
                await vm.loadFirstPage()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // This screen only ever appears modally (a popup over the player,
            // a cover over the reader), so it closes rather than goes back.
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.close))

            Spacer()

            Text(L10n.lessonNotesListTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(MyCoursesPalette.accent)

            Spacer()

            // Trailing slot. Keeps its 40pt whether or not there's a button in
            // it, so the title stays optically centred either way.
            Group {
                if let onAddNote {
                    Button(action: onAddNote) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.accent)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L10n.lessonPlayerNewNote))
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Filter strip

    private var filterStrip: some View {
        HStack(spacing: 0) {
            filterPill(.all,      label: L10n.lessonNotesFilterAll,      icon: nil)
            filterPill(.document, label: L10n.lessonNotesFilterDocument, icon: "doc")
            filterPill(.video,    label: L10n.lessonNotesFilterVideo,    icon: "video")
        }
        .padding(4)
        .background(MyCoursesPalette.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1)
        )
    }

    private func filterPill(_ value: LessonNotesFilter, label: String, icon: String?) -> some View {
        let active = vm.filter == value
        return Button {
            Task { await vm.setFilter(value) }
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(active ? Color(red: 0.08, green: 0.06, blue: 0.04) : MyCoursesPalette.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                Group {
                    if active {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient.droobBrand)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subtitle (counts)

    private var subtitle: some View {
        HStack {
            Text(String(
                format: L10n.lessonNotesSubtitleFmt,
                vm.totalCount,
                vm.sourceCount))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
                .tracking(0.8)
            Spacer()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.items.isEmpty {
            ProgressView()
                .tint(MyCoursesPalette.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.items) { note in
                        MyNotesCard(
                            note: note,
                            lessonNumber: lessonNumber,
                            lessonTitle: lessonTitle,
                            onTap: { handleTap(note) },
                            onEdit: { onEdit(note) },
                            onDelete: { Task { await vm.deleteNote(note.id) } }
                        )
                        .onAppear {
                            Task { await vm.loadMoreIfNeeded(currentItem: note) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 28))
                .foregroundColor(MyCoursesPalette.muted)
            Text(L10n.lessonNotesListEmpty)
                .font(.system(size: 13))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tap routing

    /// Pops the screen first so the host's seek / open lands on a fully
    /// presented player or PDF reader (otherwise the dismiss animation can
    /// race the navigation push and the seek looks like it didn't happen).
    /// Stash the host callback first, then dismiss. The host parks the
    /// intent in its own state and runs the seek/present inside the
    /// fullScreenCover's `onDismiss` once this screen is fully gone —
    /// chaining presentations directly here races SwiftUI's dismiss
    /// animation, which silently cancels the follow-up cover (showed up
    /// as the "canceled screen" bug on the video → doc-note path).
    private func handleTap(_ note: LessonNoteItem) {
        if let ts = note.timestampSeconds {
            onJumpToVideoTimestamp(ts, note.id)
            dismiss()
        } else if let docId = note.documentId, let page = note.pinnedPage {
            onJumpToDocument(docId, page, note.id)
            dismiss()
        }
    }
}

// MARK: - Card

/// Figma-accurate note card. Tap routes to the host via `onTap`; long-press
/// reveals the Edit / Delete menu so the row interaction stays simple.
private struct MyNotesCard: View {
    let note: LessonNoteItem
    let lessonNumber: String
    let lessonTitle: String
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                topRow
                Text(note.content)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(MyCoursesPalette.stroke)
                bottomRow
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MyCoursesPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MyCoursesPalette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L10n.lessonNotesEdit, action: onEdit)
            Button(L10n.lessonNotesDelete, role: .destructive, action: onDelete)
        }
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            // Hidden while the notes list is unified — see `hideNoteTypeSplit`.
            // The row keeps its shape either way; the date just slides to the
            // leading edge of an otherwise empty line.
            if !hideNoteTypeSplit { typeBadge }
            Spacer(minLength: 0)
            Text(dateLabel)
                .font(.system(size: 12))
                .foregroundColor(MyCoursesPalette.muted)
        }
    }

    @ViewBuilder
    private var typeBadge: some View {
        if note.isVideo {
            badge(icon: "video", label: L10n.lessonNotesTypeVideo, tint: .blue)
        } else if note.isDocument {
            badge(icon: "doc", label: L10n.lessonNotesTypeDocument, tint: MyCoursesPalette.accent)
        }
    }

    private func badge(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14))
        .clipShape(Capsule())
    }

    /// "Today" / "Today · p.7" / "Yesterday" / "MMM d" / "MMM d, yyyy".
    /// The "· p.N" suffix only appears for document notes on today's date
    /// — matches the Figma card 2 ("Today · p.36").
    private var dateLabel: String {
        var base = relativeDate(note.createdAt)
        if note.isDocument, let page = note.pinnedPage,
           Calendar.current.isDateInToday(note.createdAt) {
            base += " · "
            base += String(format: L10n.lessonNotesPagePrefixFmt, page)
        }
        return base
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return L10n.lessonNotesDateToday }
        if cal.isDateInYesterday(date) { return L10n.lessonNotesDateYesterday }
        let formatter = DateFormatter()
        // "Localized" in `setLocalizedDateFormatFromTemplate` means localized to
        // the formatter's locale, which defaults to the DEVICE. Pin it.
        formatter.locale = Locale(identifier: L10n.currentLanguageCode)
        // Same-year shows "MMM d"; older shows "MMM d, yyyy".
        if cal.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        }
        return formatter.string(from: date)
    }

    private var bottomRow: some View {
        HStack(spacing: 8) {
            anchorPill
            Text(sourceLine)
                .font(.system(size: 13))
                .foregroundColor(MyCoursesPalette.muted)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var anchorPill: some View {
        if note.isVideo, let label = note.timestampLabel {
            anchorChip(icon: "clock", label: label, tint: MyCoursesPalette.accent)
        } else if note.isDocument, let page = note.pinnedPage {
            anchorChip(icon: "doc",
                       label: String(format: L10n.lessonNotesPagePrefixFmt, page),
                       tint: MyCoursesPalette.accent)
        }
    }

    private func anchorChip(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.16))
        .clipShape(Capsule())
    }

    /// Source line for the bottom row. Video notes get "Lesson 3.5 · Title";
    /// document notes get "{Document} · Lesson 3.5" (filename first so it
    /// reads as "this came from the UX Foundations PDF").
    private var sourceLine: String {
        if note.isDocument {
            let title = note.documentTitle ?? lessonTitle
            return bidiJoin(title, "\(L10n.lesson) \(lessonNumber)")
        }
        return bidiJoin("\(L10n.lesson) \(lessonNumber)", lessonTitle)
    }
}
