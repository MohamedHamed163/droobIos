import SwiftUI
import AVKit
import AVFoundation
import Combine

// MARK: - Playback model

struct PlaybackResponse: Decodable {
    let manifestUrl: String
    let durationMinutes: Int?
    let attendeesCount: Int
    let nextLessonId: String?
    let nextLessonTitleEn: String?
    let nextLessonTitleAr: String?
    let nextSectionTitleEn: String?
    let nextSectionTitleAr: String?
    let nextLessonNumber: String?
    /// "video" or "text" — the next lesson's content type. Lets Up Next and
    /// Autoplay open the right screen (video player vs documents) instead of
    /// always pushing the player. Optional so an older backend that doesn't
    /// send the field still decodes; `nextIsVideo` then defaults to video,
    /// preserving the previous behaviour.
    let nextLessonType: String?
    /// Whether the student already finished each neighbour. Optional because a
    /// backend predating the field sends nothing — nil then means "unknown",
    /// which falls back to not-completed, the behaviour before it existed.
    let nextLessonCompleted: Bool?
    let prevLessonCompleted: Bool?
    /// The previous lesson in curriculum order. Mirrors the `next` block field
    /// for field — same meanings, same null-when-absent rule, all nil at the
    /// first lesson of a course. The backend has sent these since 2026-07; the
    /// player simply never decoded them, which is why its previous button had
    /// nothing to point at.
    let prevLessonId: String?
    let prevLessonTitleEn: String?
    let prevLessonTitleAr: String?
    let prevSectionTitleEn: String?
    let prevSectionTitleAr: String?
    let prevLessonNumber: String?
    let prevLessonType: String?
    /// Raw `VideoStatus` name for this lesson's video, when the backend sends
    /// it. Kept as a String (not the enum) so an unrecognised/new status can
    /// never fail the decode of the whole payload; `videoStatus` maps it.
    /// Absent on older backends — treated as "ready", the previous behaviour.
    let videoStatusRaw: String?
    /// Raw `playback_kind` — "HLS" or "MP4". Tells us what `manifestUrl`
    /// actually points at: a token-authorized HLS manifest (adaptive, the
    /// historical shape) or a short-lived presigned progressive MP4 produced
    /// by the passthrough pipeline. Kept as a String so an unknown future
    /// value can't fail the whole decode, and **optional** because servers
    /// predating the field send nothing — see `playbackKind`.
    let playbackKindRaw: String?

    enum CodingKeys: String, CodingKey {
        case manifestUrl = "manifest_url"
        case durationMinutes = "duration_minutes"
        case attendeesCount = "attendees_count"
        case nextLessonId = "next_lesson_id"
        case nextLessonTitleEn = "next_lesson_title_en"
        case nextLessonTitleAr = "next_lesson_title_ar"
        case nextSectionTitleEn = "next_section_title_en"
        case nextSectionTitleAr = "next_section_title_ar"
        case nextLessonNumber = "next_lesson_number"
        case nextLessonType = "next_lesson_type"
        case nextLessonCompleted = "next_lesson_completed"
        case prevLessonCompleted = "prev_lesson_completed"
        case prevLessonId = "prev_lesson_id"
        case prevLessonTitleEn = "prev_lesson_title_en"
        case prevLessonTitleAr = "prev_lesson_title_ar"
        case prevSectionTitleEn = "prev_section_title_en"
        case prevSectionTitleAr = "prev_section_title_ar"
        case prevLessonNumber = "prev_lesson_number"
        case prevLessonType = "prev_lesson_type"
        case videoStatusRaw = "video_status"
        case playbackKindRaw = "playback_kind"
    }

    /// Parsed encoding status, or nil when the backend didn't send one (or
    /// sent a value this build doesn't know).
    var videoStatus: VideoStatus? {
        videoStatusRaw.flatMap { VideoStatus(rawValue: $0.uppercased()) }
    }

    /// How to treat `manifestUrl`. Falls back to `.hls` when the field is
    /// absent *or* carries a value this build doesn't recognise: every server
    /// that predates `playback_kind` only ever returned HLS manifests, so HLS
    /// is the behaviour-preserving default for an app already in the wild.
    var playbackKind: PlaybackKind {
        playbackKindRaw.flatMap { PlaybackKind(rawValue: $0.uppercased()) } ?? .hls
    }

    /// Whether the next lesson is a video lesson. Defaults to `true` when the
    /// type is absent so a pre-field backend keeps the old (video) routing.
    var nextIsVideo: Bool { (nextLessonType ?? "video") == "video" }

    /// The neighbours as the player wants them: nil when there is no lesson on
    /// that side, which is exactly what disables the Previous / Next controls.
    var nextLesson: LessonRef? {
        nextLessonId.map {
            LessonRef(lessonId: $0,
                      titleEn: nextLessonTitleEn ?? "",
                      titleAr: nextLessonTitleAr ?? "",
                      sectionTitleEn: nextSectionTitleEn ?? "",
                      sectionTitleAr: nextSectionTitleAr ?? "",
                      number: nextLessonNumber ?? "",
                      isVideo: nextIsVideo,
                      alreadyCompleted: nextLessonCompleted ?? false)
        }
    }

    var prevLesson: LessonRef? {
        prevLessonId.map {
            LessonRef(lessonId: $0,
                      titleEn: prevLessonTitleEn ?? "",
                      titleAr: prevLessonTitleAr ?? "",
                      sectionTitleEn: prevSectionTitleEn ?? "",
                      sectionTitleAr: prevSectionTitleAr ?? "",
                      number: prevLessonNumber ?? "",
                      isVideo: (prevLessonType ?? "video") == "video",
                      alreadyCompleted: prevLessonCompleted ?? false)
        }
    }
}

// MARK: - Lesson reference

/// Everything the player needs to open a lesson without going back to the
/// curriculum for it. Doubles as the identity the host swaps when the student
/// moves between lessons — see `LessonPlayerView`.
struct LessonRef: Equatable {
    let lessonId: String
    let titleEn: String
    let titleAr: String
    let sectionTitleEn: String
    let sectionTitleAr: String
    let number: String
    /// A "text" lesson has no video surface, so it can't be swapped into the
    /// player — it opens `LessonDocumentsView` instead.
    var isVideo: Bool = true
    /// Only ever known for the lesson the student arrived on. Neighbours load
    /// their own completion state from the view model, so `false` here is a
    /// starting value, not a claim.
    var alreadyCompleted: Bool = false

    func title(locale: String) -> String { L10n.localized(locale, ar: titleAr, en: titleEn) }
}

// MARK: - Playback kind

/// What the playback endpoint's URL actually points at.
///
/// AVPlayer plays both shapes from a plain URL, so the split only matters for
/// the features that are HLS-only: adaptive variant selection (the peak
/// bitrate cap) and FairPlay content keys, neither of which exists on a
/// progressive file.
///
/// `.mp4` is the passthrough pipeline's output — a short-lived presigned
/// faststart MP4, still token-gated exactly like the manifest was, just not
/// segmented. It is *not* a permanent public URL.
enum PlaybackKind: String {
    /// Token-authorized HLS manifest with signed segment URLs. Adaptive.
    case hls = "HLS"
    /// Presigned progressive MP4 (remuxed faststart). Single quality.
    case mp4 = "MP4"

    /// Whether the stream carries multiple renditions the player can switch
    /// between. Only HLS does; a progressive file is whatever it is.
    var isAdaptive: Bool { self == .hls }
}

// MARK: - Video encoding status

/// Mirror of the backend `VideoStatus` enum. Only `READY` yields a playable
/// manifest; everything before it means the upload/encode pipeline is still
/// working on the file, and `FAILED` is a genuine error.
///
/// Note the encode step is called **PROCESSING**, not "ENCODING" — the raw
/// values here have to match the server's names exactly or every status
/// decodes as unknown.
enum VideoStatus: String {
    case uploading  = "UPLOADING"
    case queued     = "QUEUED"
    case validating = "VALIDATING"
    case processing = "PROCESSING"
    case ready      = "READY"
    case failed     = "FAILED"

    /// True while the pipeline is still working — the lesson isn't broken,
    /// it just isn't watchable yet.
    var isPreparing: Bool {
        switch self {
        case .uploading, .queued, .validating, .processing: return true
        case .ready, .failed:                               return false
        }
    }
}

/// Why the player has no video to show. Kept as an enum (rather than the old
/// bare `String?`) so "still encoding" can render as its own informational
/// state instead of being mistaken for a failure.
private enum VideoUnavailable: Equatable {
    /// The upload/encode pipeline hasn't produced a manifest yet.
    case processing
    /// A real failure — already-localised message, ready to display.
    case error(String)
}

// MARK: - LessonPlayerView

/// Thin host around the player. It owns nothing but *which* lesson is on
/// screen, so Previous / Next can swap lessons in place instead of pushing.
///
/// That distinction matters: pushing would leave the student unwinding a stack
/// of every lesson they walked through to get back to the course, and would
/// keep an `AVPlayer` alive per pushed screen. Reassigning `currentLesson` and
/// keying the content on the lesson id gives SwiftUI a clean teardown and
/// rebuild — new view model, new player, new load — while the back chevron
/// keeps pointing at the course.
struct LessonPlayerView: View {
    let courseId: String
    let instructorName: String
    private let initialLesson: LessonRef

    @State private var currentLesson: LessonRef? = nil

    init(
        courseId: String,
        lessonId: String,
        lessonTitleEn: String,
        lessonTitleAr: String,
        sectionTitleEn: String,
        sectionTitleAr: String,
        lessonNumber: String,
        alreadyCompleted: Bool,
        instructorName: String = ""
    ) {
        self.courseId = courseId
        self.instructorName = instructorName
        self.initialLesson = LessonRef(
            lessonId: lessonId,
            titleEn: lessonTitleEn,
            titleAr: lessonTitleAr,
            sectionTitleEn: sectionTitleEn,
            sectionTitleAr: sectionTitleAr,
            number: lessonNumber,
            isVideo: true,
            alreadyCompleted: alreadyCompleted)
    }

    var body: some View {
        let lesson = currentLesson ?? initialLesson
        LessonPlayerContent(
            courseId: courseId,
            lesson: lesson,
            instructorName: instructorName,
            onSwitchLesson: { currentLesson = $0 }
        )
        .id(lesson.lessonId)
    }
}

// MARK: - LessonPlayerContent

private struct LessonPlayerContent: View {
    let courseId: String
    let lesson: LessonRef
    let instructorName: String
    /// Hands a *video* neighbour back to the host to swap in. Text lessons
    /// never come through here — they have no video surface, so they push
    /// `LessonDocumentsView` instead.
    let onSwitchLesson: (LessonRef) -> Void

    // Shims so the rest of this view reads exactly as it did when the lesson's
    // fields were stored properties.
    private var lessonId: String { lesson.lessonId }
    private var lessonTitleEn: String { lesson.titleEn }
    private var lessonTitleAr: String { lesson.titleAr }
    private var sectionTitleEn: String { lesson.sectionTitleEn }
    private var sectionTitleAr: String { lesson.sectionTitleAr }
    private var lessonNumber: String { lesson.number }

    @StateObject private var vm: LessonPlayerViewModel
    @Environment(\.appLocale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var player: AVPlayer? = nil
    @State private var isLoadingVideo: Bool = true
    /// Non-nil when there is no video surface to show — either because the
    /// encode is still in flight (`.processing`) or because something failed.
    @State private var videoUnavailable: VideoUnavailable? = nil
    @State private var playback: PlaybackResponse? = nil
    @State private var documents: [LessonDocumentItem] = []
    @State private var requiredReading: LessonDocumentItem? = nil
    @State private var readingProgress: ReadingProgressState? = nil
    @State private var startTime: Date = Date()
    @State private var playerObservers: [NSObjectProtocol] = []
    @State private var statusObservation: NSKeyValueObservation? = nil
    @State private var periodicTimeToken: Any? = nil
    /// Tracks whether playback was active immediately before the lesson
    /// screen disappeared so we can auto-resume when it returns — most
    /// commonly when the student pushes PlaybackSettingsView via the gear
    /// icon and pops back. Without this they'd land on a paused video and
    /// have to tap play again.
    @State private var wasPlayingBeforeDisappear: Bool = false
    /// Note id the student explicitly tapped from a notes list (inline
    /// section, callout, MyNotesView). Wins over the playhead-window
    /// heuristic in `activeNote` so two close-together notes don't
    /// trade places when both are inside the ±10s window. Cleared
    /// automatically once the playhead leaves the note's window.
    @State private var selectedNoteId: String? = nil
    /// Pending action queued by MyNotesView before it dismissed. Run
    /// inside the cover's `onDismiss` so a follow-up fullScreenCover
    /// (e.g. presenting the PDF reader) doesn't race the dismiss
    /// animation and get silently canceled by SwiftUI.
    @State private var pendingNoteJump: PendingNoteJump? = nil
    /// Current playback position in whole seconds. Driven by a periodic time
    /// observer in `attachPlayerObservers` so the active-note callout and
    /// marker highlighting work even when the player's controls overlay is
    /// hidden (the controls' own observer is torn down with the overlay).
    @State private var currentSeconds: Int = 0
    /// Furthest playback position (in whole seconds) the student has reached
    /// this session. Monotonic locally — seeking backwards never lowers it —
    /// and reported to the backend on exit/background so admin course insights
    /// can show how much of each lesson a student actually watched. The server
    /// is itself monotonic and clamps to video duration, so duplicate or
    /// lower reports are harmless.
    @State private var furthestSeconds: Int = 0
    /// Window in seconds around a note's anchor during which the note is
    /// surfaced as "active" (drives the blue callout and the highlighted
    /// scrubber dot).
    private let activeNoteWindow: Int = 10

    // Sheets / modals
    @State private var showAddNote: Bool = false
    @State private var editingNote: LessonNoteItem? = nil
    @State private var presentingPDF: LessonDocumentItem? = nil
    /// Page the PDF reader should land on when presented programmatically
    /// (e.g. a "jump to page" tap from My Notes). Cleared to nil after the
    /// reader dismisses so the next normal open uses saved reading
    /// progress instead.
    @State private var pdfJumpToPage: Int? = nil
    /// Note id passed through to the reader so it can pop the
    /// Figma-comment-style callout for that specific note on arrival.
    /// Cleared on reader dismiss alongside `pdfJumpToPage`.
    @State private var pdfFocusNoteId: String? = nil
    /// Drives the NavigationLink-based push of MyNotesView. We use a
    /// programmatic isActive binding instead of a NavigationLink wrapping
    /// a button so the existing "View notes" pill keeps its layout.
    @State private var showMyNotes: Bool = false
    /// Set while the notes popup is stepping aside for the compose sheet, so
    /// its dismissal doesn't discard the anchor the composer is about to use.
    @State private var handingOffToComposer: Bool = false
    /// Playback time captured at the moment the student tapped "Add note".
    /// Frozen for the lifetime of the compose sheet so the saved note is
    /// anchored to where the student paused to think — not to wherever the
    /// playhead has drifted to by the time they hit Save.
    @State private var noteCaptureSeconds: Int? = nil
    /// Anchor label ("mm:ss") shown by the post-save toast on the player.
    /// Set on successful save, cleared when the toast dismisses.
    @State private var savedToastTimestampLabel: String? = nil
    /// Drives the green "Note saved to My Notes" toast on the player.
    @State private var showSavedToast: Bool = false
    /// Drives the push of PlaybackSettingsView when the player gear icon
    /// is tapped.
    @State private var showPlaybackSettings: Bool = false
    /// Drives the push of the AI tutor. Same programmatic-isActive idiom
    /// as the settings / autoplay links below, so the back chevron and
    /// tab bar stay where they belong.
    @State private var showAiTutor: Bool = false
    /// Full-screen video mode: the video surface expands over the whole
    /// screen (edge to edge) and the lesson content below it is hidden.
    /// On iPhone entering fullscreen also rotates the scene to landscape.
    @State private var isVideoFullscreen: Bool = false
    /// True once the current lesson finished naturally. Combined with the
    /// global `autoplayNextLesson` preference, drives the auto-advance to
    /// `playback.nextLessonId` via a NavigationLink.
    @State private var didFinishPlayback: Bool = false
    /// A text neighbour queued for a push. Two pieces of state rather than
    /// one: SwiftUI needs the link mounted *with its destination* before the
    /// activation flips, or it silently drops the push.
    @State private var pendingTextLesson: LessonRef? = nil
    @State private var textLessonActive: Bool = false

    /// Shared preferences (speed / quality / autoplay / subtitles).
    @StateObject private var playbackPrefs: PlaybackPreferences = .shared

    init(
        courseId: String,
        lesson: LessonRef,
        instructorName: String,
        onSwitchLesson: @escaping (LessonRef) -> Void
    ) {
        self.courseId = courseId
        self.lesson = lesson
        self.instructorName = instructorName
        self.onSwitchLesson = onSwitchLesson
        _vm = StateObject(wrappedValue: LessonPlayerViewModel(
            courseId: courseId,
            lessonId: lesson.lessonId,
            locale: "en",
            alreadyCompleted: lesson.alreadyCompleted
        ))
    }

    private var lessonTitle: String { L10n.localized(locale, ar: lessonTitleAr, en: lessonTitleEn) }
    private var sectionTitle: String { L10n.localized(locale, ar: sectionTitleAr, en: sectionTitleEn) }

    // AI tutor enabled with free on-device AI
    private var hideAiTutor: Bool { false }

    /// Hides the Notes pill in the action row (2026-08). It is the only entry
    /// point for composing a *video*-anchored note, so hiding it retires that
    /// half of the note-taking flow — notes are now a document-side feature,
    /// reached from the PDF reader. See `hideNoteTypeSplit` in `MyNotesView`,
    /// which drops the matching Video / Document split from the list itself.
    ///
    /// Consequence worth knowing: a video-only lesson (no attached documents)
    /// now has no notes surface at all beyond the read-only leftovers below —
    /// the active-note callout, the inline notes section and the scrubber
    /// markers still render pre-existing notes and still seek on tap.
    ///
    /// Hidden rather than deleted: `openNotes()`, the compose sheet, the saved
    /// toast and `MyNotesView` are all still wired, so flipping this to `false`
    /// brings the whole flow back with no other edit.
    private var hideVideoNotes: Bool { true }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                videoSection

                if !isVideoFullscreen {
                    lessonContent
                }
            }
        }
        .statusBarHidden(isVideoFullscreen)
        .toolbar(.hidden, for: .navigationBar)
        // SwiftUI re-fires `.task` *and* `.task(id:)` every time the
        // view reappears — pushing PlaybackSettingsView (or any other
        // child) onto the NavigationStack disappears this view and
        // SwiftUI re-runs the task on pop. The `id:` parameter only
        // adds an additional restart trigger when the id changes; it
        // does NOT make the task "fire once and stay quiet on
        // reappear". An earlier attempt at this fix assumed it did,
        // which is why the bug came back.
        //
        // Guard with `player != nil`: when we already have a live
        // AVPlayer, the lesson is fully loaded and reappearing only
        // because the student popped back from a child screen. Skip
        // the re-fetch so we don't build a second AVPlayer that would
        // start the manifest from 0:00 and play on top of the one
        // `onAppear` is about to resume.
        .task(id: lessonId) {
            if player != nil { return }
            startTime = Date()
            await vm.loadState()
            await loadPlayback()
            await loadDocuments()
        }
        .onAppear {
            // Coming back from a pushed child (settings, notes, etc.) —
            // resume if we were playing when we left. First appearance is
            // a no-op because `player` is nil until `loadPlayback` runs.
            if wasPlayingBeforeDisappear, let player {
                player.play()
                player.rate = playbackPrefs.speed(forLesson: lessonId)
                wasPlayingBeforeDisappear = false
            }
        }
        .onDisappear {
            // Pause but DO NOT tear down observers — this fires for any
            // navigation push (e.g. Playback Settings), not just when the
            // student truly leaves the lesson. Observer teardown happens
            // inside `loadPlayback` whenever a fresh player is built.
            wasPlayingBeforeDisappear = player?.timeControlStatus == .playing
            player?.pause()
            // Flush progress on every disappear (push or true exit). Harmless
            // when it's only a child push — the server keeps the value
            // monotonic, so the report on pop/return can't lower it.
            reportWatchProgress()
        }
        .onChange(of: scenePhase) { phase in
            // App moved to the background — iOS may suspend or kill us without
            // another callback, so flush the furthest position now. `.background`
            // is the canonical "left the app" signal; transient `.inactive`
            // (control center, notifications) is intentionally ignored.
            if phase == .background {
                reportWatchProgress()
            }
        }
        .fullScreenCover(isPresented: $vm.showCompleteModal) {
            if let result = vm.completeResult {
                LessonCompleteView(
                    result: result,
                    locale: locale,
                    onNextLesson: nil,
                    onBackToCourse: {
                        vm.showCompleteModal = false
                        dismiss()
                    }
                )
            }
        }
        // Notes open as a popup over the paused video rather than as a
        // full-screen takeover: the student is looking something up mid-lesson,
        // and the video staying visible behind the sheet is the point.
        .sheet(
            isPresented: $showMyNotes,
            onDismiss: {
                // The frozen anchor belongs to this visit, so it's cleared when
                // the popup actually closes — not when the composer does, which
                // lets the student add several notes at the same anchor.
                if handingOffToComposer {
                    handingOffToComposer = false
                } else {
                    noteCaptureSeconds = nil
                }
                runPendingNoteJump()
            }
        ) {
            MyNotesView(
                vm: MyNotesViewModel(lessonId: lessonId),
                lessonNumber: lessonNumber,
                lessonTitle: lessonTitle,
                onJumpToVideoTimestamp: { ts, noteId in
                    pendingNoteJump = .video(seconds: ts, noteId: noteId)
                },
                onJumpToDocument: { docId, page, noteId in
                    pendingNoteJump = .document(
                        documentId: docId, page: page, noteId: noteId)
                },
                onEdit: { presentComposer(for: $0) },
                // Compose a new note anchored to where the video was paused.
                onAddNote: { presentComposer(for: nil) }
            )
            .adaptiveSheetChrome(background: MyCoursesPalette.background)
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteView(
                lessonTitle: lessonTitle,
                lessonNumber: lessonNumber,
                existing: editingNote,
                // Editing shows the note's own anchor — editing text never
                // re-anchors it. Composing uses the frozen capture, NOT live
                // `currentPlayerSeconds()`; see `noteCaptureSeconds`.
                timestampSeconds: editingNote?.timestampSeconds ?? noteCaptureSeconds,
                onSave: { content in
                    if let existing = editingNote {
                        return await vm.editNote(existing.id, content: content) != nil
                    } else {
                        return await vm.addVideoNote(
                            content: content,
                            timestampSeconds: noteCaptureSeconds ?? 0) != nil
                    }
                },
                onCancel: { showAddNote = false },
                // Saved successfully: close the compose sheet immediately
                // and hand the toast back to the host. The toast renders on
                // the player itself so the student sees both their note
                // (in the inline list) and the confirmation at the same
                // time.
                onSaved: {
                    let ts = noteCaptureSeconds
                    showAddNote = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if let ts {
                            savedToastTimestampLabel = String(format: "%d:%02d", ts / 60, ts % 60)
                        } else {
                            savedToastTimestampLabel = nil
                        }
                        showSavedToast = true
                    }
                },
                onViewNotes: {
                    showAddNote = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showMyNotes = true
                    }
                }
            )
        }
        .onChange(of: showAddNote) { presented in
            // Composer closed. The anchor is *not* dropped here — it belongs to
            // the notes popup that's about to come back, and `openNotes()`
            // re-freezes it on the next visit anyway. Only the edit target is
            // stale at this point.
            if !presented { editingNote = nil }
        }
        // Post-save toast pinned to the bottom of the player. Lives outside
        // the compose sheet so dismissing the sheet doesn't hide it.
        .overlay(alignment: .bottom) {
            if showSavedToast {
                PlayerNoteSavedToast(
                    timestampLabel: savedToastTimestampLabel,
                    onViewNotes: {
                        showSavedToast = false
                        showMyNotes = true
                    },
                    onDismiss: { showSavedToast = false }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showSavedToast)
        // Auto-dismiss the toast 5 s after it appears (parity with the old
        // in-sheet toast). SwiftUI cancels the task whenever the flag flips,
        // so a manual Dismiss / View notes tap tears the timer down too.
        .task(id: showSavedToast) {
            guard showSavedToast else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            guard showSavedToast else { return }
            showSavedToast = false
        }
        .fullScreenCover(
            item: $presentingPDF,
            // Picking a video note from inside the reader's MyNotesView
            // arms `pendingNoteJump` and dismisses the reader; this runs
            // the queued seek once the cover finishes animating out
            // (mirrors the showMyNotes onDismiss above).
            onDismiss: { runPendingNoteJump() }
        ) { doc in
            LessonPDFReaderView(
                courseId: courseId,
                lessonId: lessonId,
                document: doc,
                lessonNumber: lessonNumber,
                lessonTitle: lessonTitle,
                vm: vm,
                // Honoured exactly once on appear; the reader otherwise
                // restores the last saved reading-progress page.
                initialPageOverride: pdfJumpToPage,
                initialFocusNoteId: pdfFocusNoteId,
                onJumpToVideoTimestamp: { ts, noteId in
                    pendingNoteJump = .video(seconds: ts, noteId: noteId)
                }
            )
                .onDisappear {
                    Task {
                        // Refresh progress after the reader dismisses so the
                        // card updates without manual reload.
                        readingProgress = try? await LessonInteractionsAPI
                            .getReadingProgress(lessonId: lessonId, documentId: doc.id)
                    }
                    // Always clear the override so the next normal open
                    // doesn't accidentally re-use a stale jump target.
                    pdfJumpToPage = nil
                    pdfFocusNoteId = nil
                }
        }
        // Hidden NavigationLinks — pushed onto the parent NavigationStack
        // via programmatic `isActive` bindings. Using NavigationLinks (not
        // fullScreenCover) lets the back chevron + bottom tab bar stay in
        // their normal navigation positions, matching the Figma.
        .background(
            NavigationLink(isActive: $showPlaybackSettings) {
                PlaybackSettingsView(
                    lessonId: lessonId,
                    lessonTitle: lessonTitle,
                    prefs: playbackPrefs,
                    qualitySelectable: isAdaptiveStream
                )
            } label: { EmptyView() }
            .opacity(0)
        )
        .background(
            // AI tutor — opens Ask Droob AI directly.
            NavigationLink(isActive: $showAiTutor) {
                AskDroobAIView()
            } label: { EmptyView() }
            .opacity(0)
        )
        .background(
            // Push target for a *text* neighbour. Video neighbours never come
            // through here — they replace this screen in place.
            Group {
                if let ref = pendingTextLesson {
                    NavigationLink(isActive: $textLessonActive) {
                        textLessonDestination(ref)
                    } label: { EmptyView() }
                    .opacity(0)
                }
            }
        )
        .onChange(of: textLessonActive) { active in
            // Popped back off the documents screen — drop the target so the
            // link unmounts and a later push starts from a clean slate.
            if !active { pendingTextLesson = nil }
        }
        .onChange(of: didFinishPlayback) { finished in
            // Auto-advance once playback hits the end and the global
            // toggle is on. We only fire if a next lesson actually exists;
            // otherwise the student stays on the completion modal.
            guard finished else { return }
            if playbackPrefs.autoplayNextLesson, let next = playback?.nextLesson {
                if presentingPDF != nil {
                    // The student left this lesson's document open over the
                    // player. Dismiss it first, otherwise the next lesson
                    // arrives underneath the stale reader and the video/doc
                    // fall out of sync. Defer one runloop so the
                    // fullScreenCover finishes tearing down first — SwiftUI
                    // can't reliably dismiss a cover and navigate in the same
                    // transaction.
                    presentingPDF = nil
                    DispatchQueue.main.async { goToLesson(next) }
                } else {
                    goToLesson(next)
                }
            } else if vm.completeResult != nil {
                // Nothing to advance to. The lesson auto-completed silently at
                // 90% (see `autoCompleteIfWatchedEnough`) so the celebration
                // wouldn't interrupt the last stretch of video — the natural
                // end is where it belongs. `completeResult` is nil for a lesson
                // that was already finished before this visit, so re-watching
                // doesn't re-congratulate.
                vm.showCompleteModal = true
            }
            // Reset so a future seek-to-end + resume doesn't re-fire.
            didFinishPlayback = false
        }
        .onChange(of: playbackPrefs.quality(forLesson: lessonId)) { newQuality in
            // Live quality switch from the Settings screen — apply the new
            // peak-bitrate cap to the running item. AVPlayer adapts on the
            // next variant boundary (typically within a couple of seconds).
            // Progressive MP4 playback has no variants to switch between, so
            // we leave its item alone (the Settings screen disables the rows
            // in that case anyway; this guard covers a stale preference
            // written while a different, HLS lesson was open).
            guard isAdaptiveStream else { return }
            player?.currentItem?.preferredPeakBitRate =
                newQuality.preferredPeakBitsPerSecond
        }
        .onChange(of: playbackPrefs.subtitlesEnabled) { _ in applyCaptionPreference() }
        .onChange(of: playbackPrefs.subtitleLanguage) { _ in applyCaptionPreference() }
    }

    /// Whether the loaded stream has selectable renditions. Drives both the
    /// live peak-bitrate cap and whether the Settings screen offers the
    /// quality rows at all. Defaults to `true` before the playback payload
    /// lands (and for pre-`playback_kind` servers), matching the historical
    /// HLS-only behaviour.
    private var isAdaptiveStream: Bool {
        (playback?.playbackKind ?? .hls).isAdaptive
    }

    /// Applies the student's subtitle preference to the running item by
    /// selecting (or clearing) an option in the asset's legible
    /// AVMediaSelectionGroup. The caption tracks themselves are advertised by
    /// the HLS master manifest — the backend injects `#EXT-X-MEDIA:TYPE=
    /// SUBTITLES` renditions at render time — so once the item is ready the
    /// group is populated. With subtitles off we select `nil` to hide them.
    ///
    /// A progressive MP4 exposes whatever legible tracks the file itself
    /// carries (usually none), so this stays a safe no-op there rather than
    /// needing its own branch.
    private func applyCaptionPreference() {
        guard let item = player?.currentItem else { return }
        let asset = item.asset
        let enabled = playbackPrefs.subtitlesEnabled
        let lang = playbackPrefs.subtitleLanguage.lowercased()
        Task { @MainActor in
            guard let group = try? await asset.loadMediaSelectionGroup(for: .legible) else { return }
            guard enabled else {
                item.select(nil, in: group)
                return
            }
            let match = group.options.first { opt in
                if let tag = opt.extendedLanguageTag?.lowercased(), tag.hasPrefix(lang) { return true }
                if let id = opt.locale?.identifier.lowercased(), id.hasPrefix(lang) { return true }
                return false
            }
            item.select(match ?? group.options.first, in: group)
        }
    }

    // MARK: - Next-lesson routing

    /// Destination for the next lesson, chosen by its content type. A video
    /// Destination for a neighbour that can't be swapped in place. Only text
    /// lessons land here: they have no video surface, so pushing the documents
    /// screen is the same per-type routing the curriculum does
    /// (`CurriculumView.lessonRow`). Pushing a videoless lesson into the player
    /// would fail with "Video not found".
    @ViewBuilder
    private func textLessonDestination(_ ref: LessonRef) -> some View {
        LessonDocumentsView(
            courseId: courseId,
            lessonId: ref.lessonId,
            title: ref.title(locale: locale)
        )
    }

    // MARK: - Notes

    /// The single Notes entry point. Pausing here is what makes the anchor
    /// meaningful: the playhead is frozen for as long as the popup is up, so a
    /// note composed after a minute of reading still points at the moment the
    /// student stopped to look something up.
    private func openNotes() {
        player?.pause()
        noteCaptureSeconds = currentPlayerSeconds() ?? 0
        showMyNotes = true
    }

    /// Hands the notes popup over to the compose sheet. They're both sheets on
    /// this same view, and SwiftUI will not present a second one over the first
    /// — so the popup has to be down before the composer goes up, and the
    /// dismissal must not take the frozen anchor with it.
    private func presentComposer(for note: LessonNoteItem?) {
        editingNote = note
        handingOffToComposer = true
        showMyNotes = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showAddNote = true
        }
    }

    // MARK: - Lesson navigation

    /// Move to a neighbouring lesson. A video lesson replaces this screen in
    /// place (see `LessonPlayerView`); a text lesson is pushed, because the
    /// player has nothing to show for it.
    ///
    /// The outgoing lesson's watch progress is reported first either way —
    /// the swap tears this view down, and `onDisappear` is not a reliable
    /// place to catch that.
    private func goToLesson(_ ref: LessonRef) {
        reportWatchProgress()
        player?.pause()
        // The incoming lesson starts un-fullscreened, so put the scene back
        // upright before it arrives — see `requestOrientation`.
        if isVideoFullscreen { requestOrientation(fullscreen: false) }
        if ref.isVideo {
            onSwitchLesson(ref)
        } else {
            pendingTextLesson = ref
            DispatchQueue.main.async { textLessonActive = true }
        }
    }

    // MARK: - Lesson content (below the video)

    /// Everything under the video: active-note callout, meta, actions,
    /// notes, documents, Up Next. Split out of `body` so fullscreen video
    /// can drop it without touching the video surface's structural
    /// identity (which would tear down the AVPlayerLayer mid-playback).
    private var lessonContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let note = activeNote {
                    ActiveNoteCallout(note: note)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                lessonMeta
                actionRow
                // Hidden for now (2026-08): AI tutor paused platform-wide.
                if !hideAiTutor {
                    askAiRow
                }
                if !timestampedNotes.isEmpty {
                    InlineNotesSection(
                        notes: timestampedNotes,
                        activeNoteId: activeNote?.id,
                        onSelect: { note in
                            if let ts = note.timestampSeconds {
                                // Pin this note as the active
                                // selection so an adjacent note
                                // in the same window doesn't steal
                                // the highlight after the seek.
                                selectedNoteId = note.id
                                seekAndPlay(to: ts)
                            }
                        }
                    )
                    .transition(.opacity)
                }
                if let doc = requiredReading {
                    RequiredReadingCard(
                        document: doc,
                        progress: readingProgress,
                        lessonNumber: lessonNumber,
                        lessonTitle: lessonTitle,
                        onOpen: { presentingPDF = doc }
                    )
                }
                if !otherDocuments.isEmpty {
                    LessonMaterialsSection(
                        documents: otherDocuments,
                        onOpen: { presentingPDF = $0 }
                    )
                }
                // The "Up Next" card that used to sit here is gone: Next is a
                // control in the action row now, directly under the video,
                // and a second entry point at the bottom of the scroll was
                // just a longer way to reach the same lesson.
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Fullscreen

    /// Expand/collapse the video over the whole screen. On iPhone this also
    /// rotates the scene to landscape (and back to portrait on exit) —
    /// Info.plist already allows landscape, so no AppDelegate plumbing is
    /// needed. iPad is left alone: its windows rotate freely and forcing an
    /// orientation there fights Stage Manager/iPadOS windowing.
    private func toggleVideoFullscreen() {
        withAnimation(.easeInOut(duration: 0.25)) { isVideoFullscreen.toggle() }
        requestOrientation(fullscreen: isVideoFullscreen)
    }

    /// The scene-level half of fullscreen, split out because leaving a lesson
    /// has to undo it too. `isVideoFullscreen` is this view's state, so a lesson
    /// swap resets it to `false` — but the *scene* stays wherever it was last
    /// asked to go. Without this, autoplay advancing out of a fullscreen video
    /// lands the student on a portrait layout inside a landscape-locked window.
    private func requestOrientation(fullscreen: Bool) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }
        scene.requestGeometryUpdate(
            .iOS(interfaceOrientations: fullscreen ? .landscapeRight : .portrait)
        )
    }

    // MARK: - Video section

    private var videoSection: some View {
        ZStack {
            Color.black

            if let unavailable = videoUnavailable {
                // Both states render on the player's own opaque black plate,
                // so the gold/white foregrounds below stay correct in light
                // mode — this surface never flips with the color scheme.
                switch unavailable {
                case .processing:  processingPlaceholder
                case .error(let message): errorPlaceholder(message)
                }
            } else if isLoadingVideo {
                ProgressView().tint(.white)
            } else if let player = player {
                LessonVideoPlayer(
                    player: player,
                    lessonId: lessonId,
                    onPrevLesson: nil,
                    onNextLesson: playback?.nextLessonId != nil ? { /* future: navigate */ } : nil,
                    noteTimestamps: timestampedNotes.compactMap { $0.timestampSeconds },
                    activeNoteTimestamp: activeNote?.timestampSeconds,
                    onSeekToTimestamp: { ts in
                        // Tapping a scrubber dot is an explicit pick of
                        // the note at that timestamp — pin it so an
                        // overlapping later note can't steal the
                        // highlight once the playhead lands.
                        if let note = timestampedNotes.first(where: { $0.timestampSeconds == ts }) {
                            selectedNoteId = note.id
                        }
                        seekAndPlay(to: ts)
                    },
                    onOpenSettings: { showPlaybackSettings = true },
                    qualitySelectable: isAdaptiveStream,
                    isFullscreen: isVideoFullscreen,
                    onToggleFullscreen: { toggleVideoFullscreen() }
                )
            }

            // Back button + protected pill
            VStack {
                HStack {
                    Button {
                        // In fullscreen the chevron collapses back to the
                        // normal lesson layout instead of leaving the lesson.
                        if isVideoFullscreen {
                            toggleVideoFullscreen()
                        } else {
                            reportWatchProgress()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L10n.lessonPlayerProtected)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                }
                .padding(.top, isVideoFullscreen ? 16 : 52)
                .padding(.horizontal, 16)
                Spacer()
            }
        }
        .frame(height: isVideoFullscreen ? nil : 260)
        .frame(maxHeight: isVideoFullscreen ? .infinity : nil)
        .ignoresSafeArea(edges: isVideoFullscreen ? .all : [])
    }

    /// "Still encoding" state. Deliberately distinct from `errorPlaceholder`:
    /// nothing is broken, the lesson simply isn't watchable yet, so it gets a
    /// neutral gold gear-and-clock treatment instead of the red/orange warning
    /// triangle, and the action reads "check again" rather than "retry".
    private var processingPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundColor(Color.droobGold)
            Text(L10n.lessonPlayerProcessingTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Text(L10n.lessonPlayerProcessingMessage)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(L10n.lessonPlayerProcessingCheckAgain) { Task { await loadPlayback() } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.droobGold)
        }
    }

    private func errorPlaceholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button(L10n.lessonPlayerRetry) { Task { await loadPlayback() } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.droobGold)
        }
    }

    // MARK: - Lesson meta

    private var lessonMeta: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bidiJoin("\(L10n.lessonPlayerEyebrowLesson) \(lessonNumber)",
                          sectionTitle.uppercased()))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
                .tracking(0.8)

            Text(lessonTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)

            Text(metaSubtitle)
                .font(.system(size: 13))
                .foregroundColor(MyCoursesPalette.muted)
        }
    }

    private var metaSubtitle: String {
        var parts: [String] = []
        if !instructorName.isEmpty { parts.append(instructorName) }
        if let mins = playback?.durationMinutes, mins > 0 { parts.append("\(mins) min") }
        if let count = playback?.attendeesCount, count > 0 {
            parts.append(String(format: L10n.lessonPlayerAttendeesFmt, count))
        }
        return parts.map(\.bidiIsolated).joined(separator: " · ")
    }

    // MARK: - Action row (Previous · [Notes] · Next)
    //
    // Notes is hidden as of 2026-08 — see `hideVideoNotes` — so this is a
    // two-pill row in practice. The pills are equal-width, so they simply
    // grow to fill the space the middle one used to take.
    //
    // "Mark as finished" used to sit under these three on its own line. It was
    // removed in 2026-08: completion is automatic once the student reaches
    // `Self.autoCompleteFraction` of the video (see `attachPlayerObservers`),
    // so there is nothing left for the student to press.

    private var actionRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // `backward`/`forward` rather than `left`/`right`: these mirror
                // themselves in Arabic, where "previous" points the other way.
                outlinedPill(
                    icon: "chevron.backward",
                    title: L10n.lessonPlayerPreviousLesson,
                    enabled: playback?.prevLesson != nil
                ) {
                    if let prev = playback?.prevLesson { goToLesson(prev) }
                }

                // Hidden for now (2026-08): video-anchored notes retired.
                if !hideVideoNotes {
                    outlinedPill(icon: "note.text", title: L10n.lessonPlayerNotes) {
                        openNotes()
                    }
                }

                outlinedPill(
                    icon: "chevron.forward",
                    title: L10n.lessonPlayerNextLesson,
                    iconTrailing: true,
                    enabled: playback?.nextLesson != nil
                ) {
                    if let next = playback?.nextLesson { goToLesson(next) }
                }
            }
        }
    }

    // MARK: - Ask AI
    //
    // The AI tutor's entry point in the player. It gets its own full-width
    // row rather than a fourth pill in `actionRow`: three pills already
    // crowd that line at the Arabic string lengths, and "ask about what
    // I'm watching" is a different kind of action from note-taking.

    private var askAiRow: some View {
        Button {
            // Pause first — the student is about to read, and a video
            // talking over the tutor screen is the same annoyance the
            // note composer already avoids.
            player?.pause()
            showAiTutor = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.aiMultiEntryLesson)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            .foregroundColor(MyCoursesPalette.accent)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.droobGold.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MyCoursesPalette.accent.opacity(0.40), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Shared chrome for the two outlined pills (Add note / View notes).
    /// Kept here so width balancing inside the HStack is consistent.
    /// `enabled: false` keeps the pill in the layout but greys it out — at the
    /// first and last lesson of a course the row must not reflow, or Notes
    /// jumps sideways as the student moves through the curriculum.
    private func outlinedPill(
        icon: String,
        title: String,
        iconTrailing: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if !iconTrailing {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if iconTrailing {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundColor(.primary)
            .opacity(enabled ? 1 : 0.35)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(MyCoursesPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MyCoursesPalette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Network

    /// Puts the shared audio session into video-playback mode.
    ///
    /// Without this the app runs on the default `.soloAmbient` category, which
    /// obeys the hardware ringer switch: with the phone on silent the lesson
    /// plays with NO sound at all, which students read as "the app is broken".
    /// `.playback` / `.moviePlayback` ignores the switch, matching every other
    /// video app.
    ///
    /// Deliberately scoped to the lesson player and called at playback start —
    /// NOT app-wide. VoiceNoteRecorder / VoiceNotePlayer manage their own
    /// record/playback sessions and re-assert their category on each use, so
    /// setting this globally would fight them.
    private func activatePlaybackAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            // Non-fatal: playback still works, it just stays subject to the
            // ringer switch. Log rather than surfacing an error to the student.
            NSLog("[LessonPlayer] audio session setup failed: \(error.localizedDescription)")
        }
    }

    private func loadPlayback() async {
        isLoadingVideo = true
        videoUnavailable = nil
        tearDownPlayerObservers()
        // Explicitly stop the previous AVPlayer before its reference is
        // overwritten below. Dropping a strong reference to AVPlayer
        // does NOT immediately silence audio — the audio engine keeps
        // playing until the instance is actually deallocated, which can
        // be delayed by SwiftUI still holding the value through a
        // `let player: AVPlayer` parameter on the old `LessonVideoPlayer`
        // view as it tears down. Without this pause we briefly hear two
        // streams overlap on the Retry path.
        if let old = player {
            old.pause()
            old.replaceCurrentItem(with: nil)
        }
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/lessons/\(lessonId)/playback",
            method: .GET
        )
        do {
            let response: PlaybackResponse = try await AuthInterceptor.shared.execute(request)
            playback = response
            NSLog("[LessonPlayer] manifest_url=\(response.manifestUrl) kind=\(response.playbackKind.rawValue)")
            // The backend only hands back a manifest for READY videos, but it
            // may also report the pipeline state explicitly. Honour it when
            // present: anything pre-READY is "come back shortly", FAILED is a
            // real error.
            if let status = response.videoStatus, status != .ready {
                // Pre-READY = still in the pipeline (informational);
                // FAILED = the encode gave up (a real error, and NOT the same
                // thing as "not found" — the lesson does have a video).
                videoUnavailable = status.isPreparing
                    ? .processing
                    : .error(L10n.lessonPlayerErrorProcessingFailed)
                isLoadingVideo = false
                return
            }
            guard let url = URL(string: response.manifestUrl), let scheme = url.scheme else {
                videoUnavailable = .error(L10n.lessonPlayerErrorInvalidUrl)
                isLoadingVideo = false
                return
            }
            if scheme.lowercased() == "http" {
                NSLog("[LessonPlayer] WARNING: manifest is http; ATS likely blocks playback")
            }
            // Build via AVURLAsset so FairPlay (when the manifest is
            // encrypted) can attach its content-key session. Non-DRM streams
            // are unaffected — no key request ever fires.
            //
            // AVPlayer plays a progressive MP4 from a URL exactly the same
            // way it plays a manifest, so nothing below branches on the kind
            // except the two genuinely HLS-only knobs.
            let kind = response.playbackKind
            let asset = AVURLAsset(url: url)
            if kind == .hls {
                // FairPlay keys are delivered through the manifest's
                // #EXT-X-KEY; a progressive MP4 has no key request to route.
                FairPlayContentKeyManager.shared.prepareToPlay(asset)
            }
            let item = AVPlayerItem(asset: asset)
            if kind.isAdaptive {
                // Apply the per-lesson quality cap before the player starts —
                // HLS variant selection happens up-front, so setting this
                // after play() would briefly let the highest variant load.
                // `0` means adaptive (the .auto preset).
                //
                // Left untouched for a progressive MP4: there is only one
                // rendition to pick, and a non-zero cap there just throttles
                // the download of the single stream, which risks stalls
                // rather than saving anything.
                item.preferredPeakBitRate = playbackPrefs.quality(forLesson: lessonId)
                    .preferredPeakBitsPerSecond
            }
            let avPlayer = AVPlayer(playerItem: item)
            // Assign player FIRST so observers (in particular the periodic
            // time observer attached below) capture the correct instance.
            player = avPlayer
            attachPlayerObservers(item: item, player: avPlayer)
            // Take the audio session just before the first play() so the
            // ringer switch can't silence the lesson.
            activatePlaybackAudioSession()
            // Honour the per-lesson speed before play() so the very first
            // frame is at the chosen rate (avoids a 1× → 1.5× hiccup).
            let initialRate = playbackPrefs.speed(forLesson: lessonId)
            avPlayer.play()
            avPlayer.rate = initialRate
        } catch let error as DroobError {
            switch error {
            case .forbidden:
                videoUnavailable = .error(L10n.lessonPlayerErrorNotEnrolled)
            case .notFound(_, _):
                // The playback endpoint 404s whenever the lesson's video has
                // nothing playable yet — no HLS prefix and (on the
                // passthrough pipeline) no stored playback object — which is
                // exactly the state an in-flight upload/validate is in. The
                // player is only reachable for lessons the
                // curriculum marked as video lessons, so the row exists and
                // "not encoded yet" is by far the likeliest reading; an
                // explicit FAILED status (handled above) is what turns this
                // into a hard error.
                videoUnavailable = .processing
            case .unauthenticated:
                await AuthSession.shared.handleUnauthenticated()
            default:
                videoUnavailable = .error(error.errorDescription
                                          ?? L10n.lessonPlayerErrorUnknown)
            }
        } catch {
            videoUnavailable = .error(error.localizedDescription)
        }
        isLoadingVideo = false
    }

    private func attachPlayerObservers(item: AVPlayerItem, player: AVPlayer) {
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            switch item.status {
            case .failed:
                let err = item.error as NSError?
                let msg = err?.localizedDescription ?? L10n.lessonPlayerErrorUnknown
                NSLog("[LessonPlayer] item.status=failed error=\(err?.domain ?? "?")#\(err?.code ?? 0) \(msg)")
                Task { @MainActor in
                    videoUnavailable = .error(
                        String(format: L10n.lessonPlayerErrorPlaybackFailedFmt, msg))
                }
            case .readyToPlay:
                NSLog("[LessonPlayer] item.status=readyToPlay")
                Task { @MainActor in applyCaptionPreference() }
            default: break
            }
        }
        let nc = NotificationCenter.default
        let failed = nc.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { note in
            let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            let msg = err?.localizedDescription ?? L10n.lessonPlayerErrorUnknown
            Task { @MainActor in
                videoUnavailable = .error(
                    String(format: L10n.lessonPlayerErrorPlaybackStoppedFmt, msg))
            }
        }
        // Natural end of the lesson video. Sets `didFinishPlayback`; the
        // `.onChange` modifier in `body` decides whether to fire autoplay
        // based on the global toggle.
        let finished = nc.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in didFinishPlayback = true }
        }
        playerObservers = [failed, finished]

        // Parent-owned 0.5 s tick driving `currentSeconds`. The video-control
        // overlay has its own observer for the scrubber, but it's torn down
        // when the overlay auto-hides — keeping a separate one here means
        // the active-note callout and marker highlight keep updating even
        // when the controls are hidden.
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        periodicTimeToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let secs = CMTimeGetSeconds(time)
            guard secs.isFinite, secs >= 0 else { return }
            let rounded = Int(secs)
            if rounded != currentSeconds {
                currentSeconds = rounded
            }
            if rounded > furthestSeconds {
                furthestSeconds = rounded
            }
            autoCompleteIfWatchedEnough(reached: secs, item: item)
        }
    }

    /// Fraction of the video the student has to reach before the lesson counts
    /// as finished. Deliberately short of 1.0 — end credits, an outro card or a
    /// stray last second shouldn't be what stands between a student and their
    /// progress bar.
    private static let autoCompleteFraction: Double = 0.9

    /// Marks the lesson complete once playback passes
    /// `autoCompleteFraction` of its duration. Replaces the old manual
    /// "Mark as finished" button.
    ///
    /// Silent by design: the video is still playing at this point, so the
    /// celebration modal is deferred to the natural end of playback. The
    /// view model's own `!isCompleted, !isMarkingComplete` guard makes the
    /// repeated calls from the 0.5 s tick a no-op after the first one.
    private func autoCompleteIfWatchedEnough(reached seconds: Double, item: AVPlayerItem) {
        guard !vm.isCompleted, !vm.isMarkingComplete else { return }
        let total = CMTimeGetSeconds(item.duration)
        // Duration is NaN until the item loads, and 0/indefinite for a live
        // stream — neither can produce a meaningful threshold.
        guard total.isFinite, total > 0 else { return }
        guard seconds >= total * Self.autoCompleteFraction else { return }
        let elapsed = Int(Date().timeIntervalSince(startTime))
        Task { await vm.markComplete(timeSpent: elapsed, announce: false) }
    }

    private func tearDownPlayerObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        let nc = NotificationCenter.default
        for token in playerObservers { nc.removeObserver(token) }
        playerObservers = []
        if let token = periodicTimeToken {
            player?.removeTimeObserver(token)
            periodicTimeToken = nil
        }
    }

    /// Seeks the player to the supplied note timestamp and resumes playback.
    /// `toleranceBefore: .zero` keeps the seek frame-accurate so the active-
    /// note window math doesn't drift (a coarse seek could overshoot and
    /// briefly drop the note out of its ±10 s window).
    private func seekAndPlay(to seconds: Int) {
        guard let p = player else { return }
        let target = CMTime(seconds: Double(seconds), preferredTimescale: 600)
        // AVPlayer.play() always resumes at 1.0× — using it here would
        // wipe out a 1.5× / 2× speed the student picked before tapping
        // the note. Restore the persisted lesson speed instead; setting
        // rate to a non-zero value implicitly starts playback.
        let desiredRate = playbackPrefs.speed(forLesson: lessonId)
        p.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            p.rate = desiredRate
        }
        currentSeconds = seconds
    }

    // MARK: - Document derivations

    /// Lesson documents other than the one surfaced in the Required Reading
    /// card. These were already fetched into `documents` but never rendered,
    /// so a lesson with several attachments only ever exposed the first /
    /// required one — every other document was impossible to open from the
    /// player. Listing them here restores access to the full set.
    private var otherDocuments: [LessonDocumentItem] {
        documents.filter { $0.id != requiredReading?.id }
    }

    // MARK: - Note derivations

    /// Notes that have a video timestamp, sorted chronologically by anchor.
    /// PDF-only notes are intentionally excluded from the player-screen list
    /// — they live in the reader's notes UI.
    private var timestampedNotes: [LessonNoteItem] {
        vm.notes
            .filter { ($0.timestampSeconds ?? -1) >= 0 }
            .sorted { ($0.timestampSeconds ?? 0) < ($1.timestampSeconds ?? 0) }
    }

    /// Note whose anchor is within the active window of the playhead.
    ///
    /// An explicit user pick (`selectedNoteId`) wins as long as the
    /// playhead is still within that note's window — without this an
    /// overlapping later note would steal the highlight the instant
    /// the playhead lands on the tapped earlier note (e.g. T1=30s and
    /// T2=33s: tapping T1 seeks to 30s but both fall inside the ±10s
    /// window of the playhead, and a plain `max(by: ts)` would always
    /// surface T2). Falls back to the "latest anchor in window" rule
    /// when no note is explicitly selected.
    private var activeNote: LessonNoteItem? {
        let now = currentSeconds
        let window = activeNoteWindow
        let inWindow = timestampedNotes.filter { note in
            guard let ts = note.timestampSeconds else { return false }
            return abs(now - ts) <= window
        }
        if let id = selectedNoteId,
           let pinned = inWindow.first(where: { $0.id == id }) {
            return pinned
        }
        return inWindow.max(by: { ($0.timestampSeconds ?? 0) < ($1.timestampSeconds ?? 0) })
    }

    /// Executes whatever the student picked from MyNotesView once the
    /// cover has finished dismissing. The seek-and-play / fullScreenCover
    /// swap *must* run here (not inside the cover's callbacks) — SwiftUI
    /// silently cancels a second cover that's queued while the first one
    /// is still animating out.
    private func runPendingNoteJump() {
        guard let jump = pendingNoteJump else { return }
        pendingNoteJump = nil
        Task { await vm.refreshNotes() }
        switch jump {
        case .video(let ts, let noteId):
            selectedNoteId = noteId
            seekAndPlay(to: ts)
        case .document(let docId, let page, let noteId):
            if let doc = documents.first(where: { $0.id == docId }) {
                pdfJumpToPage = page
                pdfFocusNoteId = noteId
                presentingPDF = doc
            } else {
                // Docs list missed (cold start, or stale cache). Refetch
                // and retry the lookup before giving up — without this
                // the student lands on a blank player and assumes the
                // note is broken.
                Task {
                    await loadDocuments()
                    if let doc = documents.first(where: { $0.id == docId }) {
                        pdfJumpToPage = page
                        pdfFocusNoteId = noteId
                        presentingPDF = doc
                    }
                }
            }
        }
    }

    private func loadDocuments() async {
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/lessons/\(lessonId)/documents"
        )
        if let docs = try? await AuthInterceptor.shared.execute(request) as [LessonDocumentItem] {
            documents = docs
            requiredReading = docs.first(where: { $0.requiredReading }) ?? docs.first
            if let doc = requiredReading {
                readingProgress = try? await LessonInteractionsAPI
                    .getReadingProgress(lessonId: lessonId, documentId: doc.id)
            }
        }
    }

    private func currentPlayerSeconds() -> Int? {
        guard let p = player else { return nil }
        let seconds = CMTimeGetSeconds(p.currentTime())
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return Int(seconds)
    }

    /// Fire-and-forget report of the furthest position reached to the backend.
    /// Called when the student backs out, the app moves to the background, or
    /// the screen disappears. Safe to call repeatedly: the server keeps the
    /// stored value monotonic and clamps it to the video duration, so the
    /// redundant calls these three triggers produce never regress the value.
    private func reportWatchProgress() {
        guard furthestSeconds > 0 else { return }
        let body = WatchProgressBody(positionSeconds: furthestSeconds)
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/lessons/\(lessonId)/watch-progress",
            method: .POST,
            body: body
        )
        Task { try? await AuthInterceptor.shared.executeVoid(request) }
    }
}

/// Request body for the watch-progress endpoint. Explicit CodingKeys map to
/// the snake_case key the backend expects (the shared encoder does not apply
/// a snake_case conversion strategy).
private struct WatchProgressBody: Encodable {
    let positionSeconds: Int
    enum CodingKeys: String, CodingKey {
        case positionSeconds = "position_seconds"
    }
}

/// Queued action captured when the student taps a row in MyNotesView.
/// Run from the cover's `onDismiss` so chained fullScreenCover swaps
/// don't race the dismiss animation.
private enum PendingNoteJump {
    case video(seconds: Int, noteId: String)
    case document(documentId: String, page: Int, noteId: String)
}

// MARK: - Required Reading card

struct RequiredReadingCard: View {
    let document: LessonDocumentItem
    let progress: ReadingProgressState?
    let lessonNumber: String
    /// Lesson title shown as the card's main heading (per Figma — the file
    /// name itself is rarely meaningful, so we use the lesson title and
    /// drop the file name from the card entirely).
    let lessonTitle: String
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.droobGold.opacity(0.18))
                        .frame(width: 48, height: 56)
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 22))
                        .foregroundColor(MyCoursesPalette.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(bidiJoin("\(L10n.lessonPlayerEyebrowLesson) \(lessonNumber)",
                                  L10n.lessonReadingRequiredEyebrow))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.muted)
                        .tracking(0.8)
                    Text(lessonTitle.isEmpty ? cleanedFilename : lessonTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Text(document.metaLine)
                        .font(.system(size: 12))
                        .foregroundColor(MyCoursesPalette.muted)
                }
                Spacer()
            }

            if let pageCount = document.pageCount, pageCount > 0 {
                VStack(spacing: 4) {
                    HStack {
                        Text(L10n.lessonReadingProgressLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.muted)
                            .tracking(0.6)
                        Spacer()
                        Text(String(format: L10n.lessonReadingProgressFmt,
                                    progress?.maxPageReached ?? 0,
                                    pageCount))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.accent)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.droobGold.opacity(0.18))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(LinearGradient.droobBrand)
                                .frame(width: geo.size.width * fraction, height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }

            HStack(spacing: 10) {
                Button(action: onOpen) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(progress?.currentPage ?? 0 > 1
                             ? L10n.lessonReadingContinue
                             : L10n.lessonReadingStart)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(LinearGradient.droobBrand)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onOpen) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        // Nested control: the card itself is already
                        // `surface`, so reusing it here flattened the button
                        // into the card and left only the hairline to
                        // suggest a tap target.
                        .background(MyCoursesPalette.surfaceNested)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(MyCoursesPalette.stroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MyCoursesPalette.accent.opacity(0.3), lineWidth: 1)
        )
    }

    private var fraction: Double {
        guard let p = progress, let total = document.pageCount, total > 0 else { return 0 }
        return min(1.0, Double(p.maxPageReached) / Double(total))
    }

    /// Defensive fallback for environments where the lesson title is empty:
    /// strips a leading "{uuid}-" or "{uuid}_" prefix from the filename
    /// (some upload pipelines prepend the doc id) and drops the extension.
    private var cleanedFilename: String {
        var name = document.filename
        // Strip standard 8-4-4-4-12 UUID prefixes.
        let uuidPattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[-_ ]+"#
        if let r = name.range(of: uuidPattern, options: .regularExpression) {
            name.removeSubrange(r)
        }
        // Drop the extension.
        if let dot = name.lastIndex(of: ".") {
            name = String(name[..<dot])
        }
        return name.isEmpty ? document.filename : name
    }
}

// MARK: - Up Next row
//
// Currently unreferenced: Next moved into the action row under the video and
// the card at the bottom of the scroll went with it. Kept intact rather than
// deleted so bringing the card back is a one-line restore in `lessonContent`.

struct UpNextRow: View {
    let lessonNumber: String
    let titleEn: String
    let titleAr: String
    let locale: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MyCoursesPalette.surfaceRaised)
                    .frame(width: 44, height: 44)
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.lessonPlayerUpNext)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
                let title = L10n.localized(locale, ar: titleAr, en: titleEn)
                Text(bidiJoin(lessonNumber, title, separator: " — "))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .padding(14)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Active-note callout
//
// Surfaces the note whose timestamp falls inside the playhead's active
// window. The blue-bordered card matches the Figma "your note" treatment
// and is presentation-only — interaction (edit / delete / jump-to) is
// handled by the inline notes list and the existing sheet flows.

private struct ActiveNoteCallout: View {
    let note: LessonNoteItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(note.timestampLabel ?? "")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.blue)
                    Text(L10n.lessonPlayerYourNote)
                        .font(.system(size: 12))
                        .foregroundColor(MyCoursesPalette.muted)
                    Spacer(minLength: 0)
                }
                Text(note.content)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MyCoursesPalette.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.blue.opacity(0.55), lineWidth: 1.2)
        )
    }
}

// MARK: - Inline notes-on-lesson section
//
// Player-screen replica of the bottom-sheet notes list, limited to notes
// that have a video timestamp. Tapping a row seeks the player to that
// anchor and resumes playback. Stays in sync with the sheet because both
// read from `vm.notes`.

private struct InlineNotesSection: View {
    let notes: [LessonNoteItem]
    let activeNoteId: String?
    let onSelect: (LessonNoteItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: L10n.lessonPlayerNotesCountFmt, notes.count))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
                .tracking(0.8)

            VStack(spacing: 8) {
                ForEach(notes) { note in
                    InlineNoteRow(
                        note: note,
                        isActive: note.id == activeNoteId,
                        onTap: { onSelect(note) }
                    )
                }
            }
        }
    }
}

private struct InlineNoteRow: View {
    let note: LessonNoteItem
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(note.timestampLabel ?? "")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(note.content)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
            }
            .padding(12)
            .background(MyCoursesPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isActive ? Color.blue.opacity(0.55) : MyCoursesPalette.stroke,
                        lineWidth: isActive ? 1.2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lesson materials section
//
// Lists every lesson document beyond the one featured in the Required
// Reading card. Each row opens the same in-app PDF reader the card uses
// (via `presentingPDF`). Without this section the player only ever
// surfaced the first / required document, leaving the rest unreachable.

private struct LessonMaterialsSection: View {
    let documents: [LessonDocumentItem]
    let onOpen: (LessonDocumentItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.lessonMaterialsEyebrow)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
                .tracking(0.8)

            VStack(spacing: 8) {
                ForEach(documents) { doc in
                    LessonMaterialRow(document: doc, onTap: { onOpen(doc) })
                }
            }
        }
    }
}

private struct LessonMaterialRow: View {
    let document: LessonDocumentItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.droobGold.opacity(0.18))
                        .frame(width: 38, height: 44)
                    Image(systemName: iconName)
                        .font(.system(size: 16))
                        .foregroundColor(MyCoursesPalette.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.filename)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(document.metaLine)
                        .font(.system(size: 12))
                        .foregroundColor(MyCoursesPalette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            .padding(12)
            .background(MyCoursesPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MyCoursesPalette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        if document.mimeType == "application/pdf" { return "doc.richtext.fill" }
        if document.mimeType.hasPrefix("image/") { return "photo.fill" }
        return "doc.fill"
    }
}

// MARK: - Presentation detents helper

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
}
