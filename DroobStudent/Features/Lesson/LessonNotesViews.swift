import SwiftUI

// MARK: - Notes UI
//
// Two screens:
//   • AddNoteView     — full-screen modal with Cancel / Add note / Save header
//                       and a single text area, used to create or edit a note.
//   • NotesListView   — bottom sheet listing all of the student's notes for
//                       the current lesson, with edit/delete affordances.

// MARK: - AddNoteView

/// Compose / edit view for a single note. The save action is supplied by the
/// host so this stays free of any API knowledge.
struct AddNoteView: View {
    let lessonTitle: String
    let lessonNumber: String
    /// Existing note when editing; nil when creating.
    let existing: LessonNoteItem?
    /// Optional playback timestamp to anchor a *new* note to. Ignored on edit.
    let timestampSeconds: Int?
    /// Optional excerpt the student selected in the PDF before opening the
    /// compose sheet (V44). When present we render a "Selected text" card
    /// above the editor so the user knows what they're annotating.
    var selectedText: String? = nil
    /// Optional 1-based PDF page anchor (V44). Pairs with `selectedText`.
    var pinnedPage: Int? = nil
    /// Persists the note. Returns true on success. The host is responsible
    /// for dismissing the sheet via `onSaved` (or `onCancel` on failure) —
    /// this view used to render its own success toast, but the toast now
    /// lives on the player so the student sees the inline notes list +
    /// confirmation at the same time.
    let onSave: (String) async -> Bool
    let onCancel: () -> Void
    /// Called by the view after a successful save. Hosts typically dismiss
    /// the sheet here and then show their own toast. Optional; if omitted
    /// the sheet stays open after save (used by hosts that want manual
    /// control of the dismiss timing).
    var onSaved: () -> Void = {}
    /// Tapped from the success toast — host should close this view and open
    /// the notes list. Defaults to no-op when the host doesn't wire it.
    var onViewNotes: () -> Void = {}

    @State private var content: String = ""
    @State private var saving: Bool = false
    @State private var failed: Bool = false
    @FocusState private var editorFocused: Bool

    /// Per-Figma cap on note length. Enforced by trimming the bound string
    /// inside the editor so paste actions can't exceed it either. The counter
    /// turns red when the user is within 20 characters of the cap.
    private let maxContentLength: Int = 500

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().overlay(MyCoursesPalette.stroke)
                subtitle
                if let quote = effectiveSelectedText {
                    SelectedTextCard(quote: quote, pageOneBased: effectivePinnedPage)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                }
                editor
                Spacer(minLength: 0)
                footer
            }
        }
        .onAppear {
            content = existing?.content ?? ""
            editorFocused = true
        }
    }

    private var header: some View {
        HStack {
            Button(action: onCancel) {
                Text(L10n.lessonAddNoteCancel)
                    .font(.system(size: 15))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(existing == nil ? L10n.lessonAddNoteTitleAdd : L10n.lessonAddNoteTitleEdit)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
            Spacer()
            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 6) {
                    if saving { ProgressView().scaleEffect(0.7).tint(MyCoursesPalette.accent) }
                    Text(L10n.lessonAddNoteSave)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(canSave ? MyCoursesPalette.accent : MyCoursesPalette.muted)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var subtitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bidiJoin("Lesson \(lessonNumber)", lessonTitle))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
                .lineLimit(2)
            if failed {
                Text(L10n.lessonAddNoteFailed)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(
                get: { content },
                set: { newValue in
                    if newValue.count > maxContentLength {
                        // Drop the overflow rather than rejecting the whole
                        // edit so paste-then-trim still leaves the user with
                        // the leading portion of their text.
                        content = String(newValue.prefix(maxContentLength))
                    } else {
                        content = newValue
                    }
                }
            ))
                .scrollContentBackgroundIfAvailable()
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .focused($editorFocused)
                .font(.system(size: 16))
                .foregroundColor(.primary)
            if content.isEmpty {
                Text(L10n.lessonAddNotePlaceholder)
                    .font(.system(size: 16))
                    .foregroundColor(MyCoursesPalette.muted)
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Bottom strip with the page + lesson context on the left and the
    /// character counter on the right. Visible whenever the compose sheet is
    /// open — when no page is pinned (e.g. a video-only note) the left side
    /// collapses to just the lesson title.
    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                if effectivePinnedPage != nil {
                    Image(systemName: "doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.muted)
                }
                Text(footerLeftLabel)
                    .font(.system(size: 11))
                    .foregroundColor(MyCoursesPalette.muted)
                    .lineLimit(1)
            }
            Spacer()
            // Both operands are digits, so neither can anchor the neutral "/".
            // Under the Arabic paragraph the pair would render "200 / 40".
            // Isolating the whole counter (no strong character inside) pins it
            // to LTR; isolating the two numbers separately would not.
            Text("\(content.count) / \(maxContentLength)".bidiIsolated)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(
                    content.count >= maxContentLength - 20
                        ? .red.opacity(0.85)
                        : MyCoursesPalette.muted
                )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(MyCoursesPalette.surface.opacity(0.5))
        .overlay(
            Rectangle()
                .fill(MyCoursesPalette.stroke)
                .frame(height: 0.5),
            alignment: .top
        )
    }

    private var footerLeftLabel: String {
        if let page = effectivePinnedPage {
            return String(format: L10n.lessonAddNoteFooterPageFmt, page, lessonTitle)
        }
        return lessonTitle
    }

    /// Returns the quote to display in the "selected text" card. Prefers the
    /// freshly captured selection (for new notes) and falls back to the value
    /// stored on the note we're editing — so editing an existing PDF-anchored
    /// note still shows the original quote for context.
    private var effectiveSelectedText: String? {
        if let s = selectedText, !s.isEmpty { return s }
        if let s = existing?.selectedText, !s.isEmpty { return s }
        return nil
    }

    private var effectivePinnedPage: Int? {
        pinnedPage ?? existing?.pinnedPage
    }

    private var canSave: Bool {
        !saving && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saving = true
        failed = false
        let ok = await onSave(trimmed)
        saving = false
        if ok {
            // Hand control back to the host. Per the May 2026 UX update,
            // the sheet should close immediately and the host renders the
            // success toast on the player itself.
            onSaved()
        } else {
            failed = true
        }
    }
}

// MARK: - Note saved toast
//
// Bottom-anchored card surfaced by the lesson player after a successful
// note save. The view itself is presentation-only — the host owns the
// `showSavedToast` flag and the actions wired to View notes / Dismiss.
//
// Lives here (next to AddNoteView) because the same chip used to be
// rendered inside the compose sheet; the May 2026 redesign hoisted it onto
// the player so the sheet can close immediately on save.

struct PlayerNoteSavedToast: View {
    let timestampLabel: String?
    let onViewNotes: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(MyCoursesPalette.success.opacity(0.22))
                        .frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(MyCoursesPalette.success)
                }
                Text(L10n.lessonPlayerNoteSavedTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
            }

            if let label = timestampLabel {
                HStack(spacing: 6) {
                    Text(L10n.lessonPlayerNoteSavedPinnedFmt
                            .replacingOccurrences(of: "%@", with: ""))
                        .font(.system(size: 12))
                        .foregroundColor(MyCoursesPalette.muted)
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .semibold))
                        Text(label)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(MyCoursesPalette.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.droobGold.opacity(0.16))
                    .clipShape(Capsule())
                }
            }

            HStack(spacing: 10) {
                Button(action: onViewNotes) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12, weight: .semibold))
                        Text(L10n.lessonPlayerViewNotes)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(LinearGradient.droobBrand)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text(L10n.lessonPlayerNoteSavedDismiss)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MyCoursesPalette.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MyCoursesPalette.success.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 18, x: 0, y: 10)
    }
}

// MARK: - NotesListView

/// Lists existing notes for a lesson. Hosted as a `.sheet` from
/// LessonPlayerView; tapping a note jumps into AddNoteView in edit mode.
struct NotesListView: View {
    @ObservedObject var vm: LessonPlayerViewModel
    let lessonTitle: String
    let lessonNumber: String
    let onAdd: () -> Void
    let onEdit: (LessonNoteItem) -> Void

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.lessonNotesListTitle)
                        .font(.system(size: 20, weight: .bold))
                    Spacer()
                    Button(action: onAdd) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text(L10n.lessonNotesListAdd)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(LinearGradient.droobBrand)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)

                if vm.notes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "note.text")
                            .font(.system(size: 28))
                            .foregroundColor(MyCoursesPalette.muted)
                        Text(L10n.lessonNotesListEmpty)
                            .font(.system(size: 13))
                            .foregroundColor(MyCoursesPalette.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(vm.notes) { note in
                                NoteRow(
                                    note: note,
                                    onEdit: { onEdit(note) },
                                    onDelete: { Task { await vm.deleteNote(note.id) } }
                                )
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 18)
                    }
                }
            }
        }
    }
}

private struct NoteRow: View {
    let note: LessonNoteItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let ts = note.timestampLabel {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .semibold))
                        Text(ts)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(MyCoursesPalette.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.droobGold.opacity(0.14))
                    .clipShape(Capsule())
                }
                Spacer()
                Menu {
                    Button(L10n.lessonNotesEdit, action: onEdit)
                    Button(L10n.lessonNotesDelete, role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.muted)
                        .frame(width: 26, height: 26)
                }
            }
            Text(note.content)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Selected-text card
//
// Compact card surfaced above the editor when the user invoked Add Note
// after selecting a passage in the PDF reader. Mirrors the Figma — eyebrow
// reads "SELECTED TEXT · P.7" with a gold accent and the quote is rendered
// in a serif italic to read as an excerpt rather than user input.

private struct SelectedTextCard: View {
    let quote: String
    let pageOneBased: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MyCoursesPalette.accent)
                .tracking(0.8)
            Text("\u{201C}\(quote)\u{201D}")
                .font(.system(size: 14))
                .foregroundColor(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MyCoursesPalette.accent.opacity(0.45), lineWidth: 1)
        )
    }

    private var eyebrow: String {
        if let page = pageOneBased {
            return String(format: L10n.lessonAddNoteSelectedTextPageFmt, page)
        }
        return L10n.lessonAddNoteSelectedTextLabel
    }
}

// MARK: - Modifier helper

private extension View {
    @ViewBuilder
    func scrollContentBackgroundIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
