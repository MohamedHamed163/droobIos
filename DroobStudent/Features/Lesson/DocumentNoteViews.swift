import SwiftUI

// MARK: - Document note flow (June 2026 redesign)
//
// Figma "NEW TAKING NOTE FLOW" (node 1706-16555). The PDF-anchored note
// experience is split into:
//
//   • DocumentNoteComposerView — a two-field compose / edit sheet. The
//     top "CONTENT" field holds the source passage the student pasted or
//     highlighted; the "YOUR NOTE" field holds their own commentary.
//     Either field alone is enough to save — but the backend requires a
//     non-blank `content`, so a source-only note saves the passage *as*
//     the note body (see `resolvedSave`).
//   • NotesOnThisPageSheet — a bottom sheet listing the notes anchored to
//     the page currently on screen, with an "All notes →" jump to the
//     full MyNotesView.
//   • TopNoteToast — the slim top-anchored confirmations ("Note saved to
//     My Notes" / "Note deleted · Undo").
//
// These live separately from the video-note `AddNoteView` so the shared
// player path keeps its single-field compose sheet untouched.

/// Surface tokens for the document-note sheets. These follow the reader
/// chrome, which now tracks the app color scheme via `MyCoursesPalette`;
/// only the gold-tinted empty-field wash is a fixed brand value.
private enum DocNotePalette {
    static let sheet  = MyCoursesPalette.background
    static let field  = Color.droobGold.opacity(0.05)
    static let muted  = MyCoursesPalette.muted
    static let faint  = MyCoursesPalette.textTertiary
}

/// Rectangle with only the top two corners rounded — used by the
/// Notes-on-this-page panel so it reads as a bottom sheet pinned to the
/// screen edge while the page stays visible above it.
struct TopRoundedShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Per-field soft word cap from the Figma counters ("N / 500 words"). The
/// backend hard-caps `content` at 10 000 *characters*; this is a friendlier
/// UI guardrail that turns the counter red and blocks Save when exceeded.
private let kMaxNoteWords = 500
/// Soft per-page note cap used only for the "Note N of M" subtitle.
let kMaxNotesPerPage = 10

private func wordCount(_ s: String) -> Int {
    s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
}

// MARK: - Composer

struct DocumentNoteComposerView: View {
    /// Existing note when editing; nil when composing a fresh note.
    let existing: LessonNoteItem?
    /// 1-based page the note is anchored to.
    let pageOneBased: Int
    /// Source document title, shown nowhere here but kept for parity / future.
    let documentTitle: String
    /// Position of this note among the page's notes (1-based) for the
    /// "Note N of M" subtitle.
    let noteIndex: Int
    /// Source excerpt captured from the live PDF selection (new notes only).
    let capturedSource: String?
    /// Persists the note. `body` is the resolved non-blank content; `source`
    /// is the optional excerpt (nil to leave unset). Returns true on success.
    let onSave: (_ body: String, _ source: String?) async -> Bool
    let onCancel: () -> Void
    /// Called after a successful save so the host can dismiss + toast.
    let onSaved: () -> Void
    /// Edit-mode delete. Host owns the actual API call + toast.
    var onDelete: () -> Void = {}

    @State private var source: String = ""   // CONTENT field
    @State private var noteBody: String = "" // YOUR NOTE field
    @State private var saving = false
    @State private var failed = false
    @State private var showDeleteConfirm = false
    @FocusState private var focus: Field?

    private enum Field { case source, body }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        ZStack {
            DocNotePalette.sheet.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        contentField
                        yourNoteField
                        Text(L10n.docNoteHelper)
                            .font(.system(size: 12))
                            .foregroundColor(DocNotePalette.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 2)
                        if failed {
                            Text(L10n.lessonAddNoteFailed)
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                }
                if isEditing {
                    deleteButton
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                }
            }
        }
        .overlay { if showDeleteConfirm { deleteConfirmDialog } }
        .onAppear {
            source = existing?.selectedText ?? capturedSource ?? ""
            noteBody = existing?.content ?? ""
            // Focus the note body for fresh notes; leave edit mode unfocused
            // so the keyboard doesn't immediately cover the Delete button.
            if !isEditing { focus = .body }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 2) {
            HStack {
                Button(action: onCancel) {
                    Text(L10n.lessonAddNoteCancel)
                        .font(.system(size: 15))
                        .foregroundColor(MyCoursesPalette.accent)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(isEditing ? L10n.docNoteEditTitle : L10n.docNoteNewTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)

                Spacer()

                saveButton
            }
            Text(String(format: L10n.docNoteSubtitleFmt,
                        noteIndex, kMaxNotesPerPage, pageOneBased))
                .font(.system(size: 11))
                .foregroundColor(DocNotePalette.muted)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .overlay(
            Rectangle().fill(MyCoursesPalette.stroke).frame(height: 0.5),
            alignment: .bottom
        )
    }

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: 6) {
                if saving { ProgressView().scaleEffect(0.6).tint(.black) }
                Text(L10n.lessonAddNoteSave)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(canSave ? .black : DocNotePalette.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(canSave
                    ? Color.droobGold
                    : MyCoursesPalette.surface)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    // MARK: CONTENT field

    private var contentField: some View {
        let words = wordCount(source)
        let over = words > kMaxNoteWords
        let filled = !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 7) {
            fieldLabel(icon: "text.quote",
                       label: L10n.docNoteContentLabel,
                       trailing: filled ? nil : L10n.docNotePasteHint)
            // CONTENT is editable only for fresh notes; on edit the backend
            // update endpoint accepts `content` only, so the excerpt is shown
            // read-only to avoid silently dropping changes.
            if isEditing {
                if filled {
                    Text(source)
                        .font(.system(size: 15))
                        .foregroundColor(MyCoursesPalette.accent.opacity(0.95))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(fieldBackground(filled: true, over: false))
                } else {
                    EmptyView()
                }
            } else {
                ZStack(alignment: .topLeading) {
                    NoteTextEditor(text: $source)
                        .font(.system(size: 15))
                        .foregroundColor(MyCoursesPalette.accent.opacity(0.95))
                        .frame(minHeight: 54)
                        .padding(8)
                        .focused($focus, equals: .source)
                    if source.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12))
                            Text(L10n.docNoteContentPlaceholder)
                                .font(.system(size: 14))
                        }
                        .foregroundColor(DocNotePalette.faint)
                        .padding(.horizontal, 13)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                    }
                }
                .background(fieldBackground(filled: filled, over: over))
                wordCounter(words, over: over)
            }
        }
    }

    // MARK: YOUR NOTE field

    private var yourNoteField: some View {
        let words = wordCount(noteBody)
        let over = words > kMaxNoteWords
        let filled = !noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 7) {
            fieldLabel(icon: "square.and.pencil",
                       label: L10n.docNoteYourNoteLabel,
                       trailing: nil)
            ZStack(alignment: .topLeading) {
                NoteTextEditor(text: $noteBody)
                    .font(.system(size: 15))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .frame(minHeight: 96)
                    .padding(8)
                    .focused($focus, equals: .body)
                if noteBody.isEmpty {
                    Text(L10n.docNoteYourNotePlaceholder)
                        .font(.system(size: 14))
                        .foregroundColor(DocNotePalette.faint)
                        .padding(.horizontal, 13)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(fieldBackground(filled: filled, over: over))
            wordCounter(words, over: over)
        }
    }

    // MARK: Field chrome

    private func fieldLabel(icon: String, label: String, trailing: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MyCoursesPalette.accent)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .foregroundColor(MyCoursesPalette.accent)
            if !isEditing {
                Text(L10n.docNoteOptional)
                    .font(.system(size: 11))
                    .foregroundColor(DocNotePalette.muted)
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundColor(DocNotePalette.muted)
            }
        }
    }

    /// Border is gold-as-ink (adaptive `accent`) so the dashed empty-field
    /// outline survives on the light sheet; the wash behind it is gold-as-fill
    /// and keeps the brand value in both schemes.
    private func fieldBackground(filled: Bool, over: Bool) -> some View {
        let stroke: Color = over
            ? .red
            : (filled ? MyCoursesPalette.accent.opacity(0.65) : MyCoursesPalette.accent.opacity(0.40))
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(over ? Color.red.opacity(0.06)
                       : (filled ? Color.droobGold.opacity(0.08) : DocNotePalette.field))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        stroke,
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: filled || over ? [] : [4, 4]))
            )
    }

    private func wordCounter(_ words: Int, over: Bool) -> some View {
        Text(String(format: L10n.docNoteWordsFmt, words, kMaxNoteWords))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(over ? .red.opacity(0.9) : DocNotePalette.muted)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: Delete

    private var deleteButton: some View {
        Button { showDeleteConfirm = true } label: {
            Text(L10n.docNoteDelete)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MyCoursesPalette.surface)
                )
        }
        .buttonStyle(.plain)
    }

    private var deleteConfirmDialog: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { showDeleteConfirm = false }
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.red.opacity(0.18)).frame(width: 52, height: 52)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.red)
                }
                .padding(.top, 4)
                Text(L10n.docNoteDeleteTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(String(format: L10n.docNoteDeleteMessageFmt, pageOneBased))
                    .font(.system(size: 13))
                    .foregroundColor(DocNotePalette.muted)
                    .multilineTextAlignment(.center)
                HStack(spacing: 0) {
                    Button { showDeleteConfirm = false } label: {
                        Text(L10n.docNoteDeleteKeep)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    Button {
                        showDeleteConfirm = false
                        onDelete()
                    } label: {
                        Text(L10n.docNoteDeleteDiscard)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 280)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(MyCoursesPalette.surfaceRaised)
            )
        }
    }

    // MARK: Save logic

    /// At least one field non-empty, neither over the word cap, and (when
    /// editing) the body actually changed.
    private var canSave: Bool {
        guard !saving else { return false }
        let body = noteBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(body.isEmpty && src.isEmpty) else { return false }
        guard wordCount(noteBody) <= kMaxNoteWords,
              wordCount(source) <= kMaxNoteWords else { return false }
        if isEditing { return body != (existing?.content ?? "") }
        return true
    }

    private func save() async {
        let body = noteBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        // Backend requires a non-blank `content`: a source-only note saves
        // the excerpt as the body.
        let finalContent = body.isEmpty ? src : body
        let finalSource: String? = src.isEmpty ? nil : src
        guard !finalContent.isEmpty else { return }
        saving = true
        failed = false
        let ok = await onSave(finalContent, finalSource)
        saving = false
        if ok { onSaved() } else { failed = true }
    }
}

// MARK: - TextEditor wrapper

/// `TextEditor` with a transparent background on iOS 16+ so the field's
/// own rounded fill shows through.
private struct NoteTextEditor: View {
    @Binding var text: String
    var body: some View {
        if #available(iOS 16.0, *) {
            TextEditor(text: $text).scrollContentBackground(.hidden)
        } else {
            TextEditor(text: $text)
        }
    }
}

// MARK: - Notes on this page sheet

struct NotesOnThisPageSheet: View {
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    let pageOneBased: Int
    let documentTitle: String
    let notes: [LessonNoteItem]
    let onAdd: () -> Void
    let onSelect: (LessonNoteItem) -> Void
    let onAllNotes: () -> Void
    let onClose: () -> Void

    /// Figma 1695:11099 "PEEK PANEL — compact state": a page-background chip
    /// with 18pt top corners and a gold hairline top border, sized to its
    /// content (drag handle + header + one row of horizontally-scrolling
    /// cards) so the PDF page stays visible above it instead of being covered.
    private static let panelFill = MyCoursesPalette.background

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            header
            if notes.isEmpty {
                emptyState
            } else {
                cardScroller
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            TopRoundedShape(radius: 18)
                .fill(Self.panelFill)
                .overlay(
                    TopRoundedShape(radius: 18)
                        .stroke(MyCoursesPalette.accent.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.6), radius: 18, x: 0, y: -12)
        )
    }

    private var dragHandle: some View {
        Capsule()
            .fill(MyCoursesPalette.textTertiary)
            .frame(width: 40, height: 4.5)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.notesOnPageTitle)
                .font(BrandFont.display(size: 16, isArabic: appLocale == "ar"))
                .foregroundColor(MyCoursesPalette.accent)
            if !notes.isEmpty {
                countBadge
            }
            Spacer(minLength: 12)
            if notes.isEmpty {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DocNotePalette.muted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onAllNotes) {
                    HStack(spacing: 4) {
                        Text(L10n.notesAllLink)
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(MyCoursesPalette.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private var countBadge: some View {
        Text("\(notes.count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(MyCoursesPalette.accent)
            .frame(minWidth: 20, minHeight: 20)
            .padding(.horizontal, 6)
            .background(Capsule().fill(Color.droobGold.opacity(0.2)))
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.droobGold.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(MyCoursesPalette.accent)
            }
            Text(L10n.notesOnPageEmpty)
                .font(.system(size: 14))
                .foregroundColor(MyCoursesPalette.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(action: onAdd) {
                Text(L10n.notesOnPageAdd)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.droobGold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    private var cardScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(notes) { note in
                    PeekNoteCard(note: note) { onSelect(note) }
                }
            }
            .padding(.leading, 11)
            .padding(.trailing, 16)
            .padding(.top, 7)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Peek note card

/// Fixed-width compact card for the "Notes on this page" peek panel
/// (Figma 1695:11147): a 240×100 gold-outlined chip with a timestamp, an optional
/// gold-barred excerpt, and a 2-line body preview. Tapping opens the note
/// in the floating callout over the page.
private struct PeekNoteCard: View {
    let note: LessonNoteItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 7) {
                Text(timestamp)
                    .font(.system(size: 10))
                    .foregroundColor(MyCoursesPalette.textTertiary)

                if let quote = note.selectedText, !quote.isEmpty {
                    HStack(spacing: 0) {
                        Rectangle().fill(MyCoursesPalette.accent).frame(width: 2)
                        Text("\u{201C}\(quote)\u{201D}")
                            .font(.system(size: 11))
                            .foregroundColor(MyCoursesPalette.accent.opacity(0.9))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                        Spacer(minLength: 0)
                    }
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 5,
                            topTrailingRadius: 5,
                            style: .continuous
                        )
                        .fill(Color.droobGold.opacity(0.08))
                    )
                }

                Text(note.content)
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 8)
            .frame(width: 240, height: 100, alignment: .topLeading)
            .background(
                // The peek panel behind these cards is itself
                // `MyCoursesPalette.background`; filling the card with the
                // same token flattened the two together and left the card
                // outlined but not raised. `surface` is the card token.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MyCoursesPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MyCoursesPalette.accent.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var timestamp: String {
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(note.createdAt) {
            day = L10n.lessonNotesDateToday
        } else if cal.isDateInYesterday(note.createdAt) {
            day = L10n.lessonNotesDateYesterday
        } else {
            let df = DateFormatter()
            df.locale = Locale(identifier: L10n.currentLanguageCode)
            df.setLocalizedDateFormatFromTemplate("MMMd")
            day = df.string(from: note.createdAt)
        }
        let tf = DateFormatter()
        tf.locale = Locale(identifier: L10n.currentLanguageCode)
        // Template, not a literal "h:mm a": the hardcoded pattern forced a
        // 12-hour clock with a Latin AM/PM marker regardless of locale.
        tf.setLocalizedDateFormatFromTemplate("jmm")
        // "أمس · 3:45 PM" — the time is digits plus a Latin AM/PM marker, so
        // without isolation the marker detaches and lands on the wrong side.
        return bidiJoin(day, tf.string(from: note.createdAt))
    }
}

// MARK: - Top toast

/// Slim top-anchored confirmation pill. Used for "Note saved to My Notes"
/// (green check, no action) and "Note deleted · Undo" (trash + gold Undo).
struct TopNoteToast: View {
    enum Kind { case saved, deleted }
    let kind: Kind
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill((kind == .saved ? MyCoursesPalette.success : Color.red)
                            .opacity(0.22))
                    .frame(width: 22, height: 22)
                Image(systemName: kind == .saved ? "checkmark" : "trash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(kind == .saved ? MyCoursesPalette.success : .red)
            }
            Text(kind == .saved ? L10n.noteSavedToMyNotes : L10n.noteDeletedToast)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MyCoursesPalette.textPrimary)
            if kind == .deleted, let onAction {
                Spacer(minLength: 8)
                Button(action: onAction) {
                    Text(L10n.noteUndo)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MyCoursesPalette.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule().fill(MyCoursesPalette.surfaceRaised)
                .overlay(Capsule().stroke(MyCoursesPalette.stroke, lineWidth: 1))
        )
        .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 8)
    }
}
