import Foundation
import SwiftUI

// MARK: - L10n
// Typed localization keys. Reads from Localizable.strings in the active locale bundle.

enum L10n {
    // MARK: - Auth
    static var login: String { loc("auth.login") }
    static var register: String { loc("auth.register") }
    static var logout: String { loc("auth.logout") }
    static var email: String { loc("auth.email") }
    static var password: String { loc("auth.password") }
    static var displayName: String { loc("auth.display_name") }
    static var loginButton: String { loc("auth.login_button") }
    static var registerButton: String { loc("auth.register_button") }
    static var noAccount: String { loc("auth.no_account") }
    static var haveAccount: String { loc("auth.have_account") }
    static var welcomeBack: String { loc("auth.welcome_back") }
    static var createAccount: String { loc("auth.create_account") }
    static var authKicker: String { loc("auth.kicker") }
    static var signInTitle: String { loc("auth.sign_in_title") }
    static var signInSubtitle: String { loc("auth.sign_in_subtitle") }
    static var signUpTitle: String { loc("auth.sign_up_title") }
    static var signUpSubtitle: String { loc("auth.sign_up_subtitle") }
    static var emailPlaceholder: String { loc("auth.email_placeholder") }
    static var passwordPlaceholder: String { loc("auth.password_placeholder") }
    static var fullNamePlaceholder: String { loc("auth.full_name_placeholder") }
    static var continueWithApple: String { loc("auth.continue_apple") }
    static var continueWithGoogle: String { loc("auth.continue_google") }
    static var forgotPassword: String { loc("auth.forgot_password") }
    static var signInLink: String { loc("auth.sign_in_link") }
    static var signUpLink: String { loc("auth.sign_up_link") }
    static var themeDark: String { loc("auth.theme_dark") }
    static var themeLight: String { loc("auth.theme_light") }
    static var langArabic: String { loc("auth.lang_arabic") }
    static var langEnglish: String { loc("auth.lang_english") }

    // MARK: - Catalog
    static var catalog: String { loc("catalog.title") }
    static var courses: String { loc("catalog.courses") }
    static var loadMore: String { loc("catalog.load_more") }
    static var enrolled: String { loc("catalog.enrolled") }
    static var enroll: String { loc("catalog.enroll") }
    static var price: String { loc("catalog.price") }
    static var free: String { loc("catalog.free") }

    // MARK: - Course Detail
    static var courseDetail: String { loc("course.detail") }
    static var sections: String { loc("course.sections") }
    static var lessons: String { loc("course.lessons") }
    static var instructor: String { loc("course.instructor") }
    static var subscribeNow: String { loc("course.subscribe_now") }
    static var alreadyEnrolled: String { loc("course.already_enrolled") }
    static var confirmSubscribe: String { loc("course.confirm_subscribe") }
    static var confirmSubscribeMessage: String { loc("course.confirm_subscribe_message") }
    static var confirm: String { loc("general.confirm") }
    static var cancel: String { loc("general.cancel") }
    static var close: String { loc("general.close") }
    static var subscribeSuccess: String { loc("course.subscribe_success") }

    // MARK: - My Courses
    static var myCourses: String { loc("my_courses.title") }
    static var noEnrollments: String { loc("my_courses.no_enrollments") }
    static var browseCatalog: String { loc("my_courses.browse_catalog") }
    static var myCoursesTitleMy: String { loc("my_courses.title_my") }
    static var myCoursesTitleCourses: String { loc("my_courses.title_courses") }
    static var myCoursesEnrolled: String { loc("my_courses.enrolled_word") }
    static var myCoursesCompletedShort: String { loc("my_courses.completed_word") }
    static var myCoursesFilterAll: String { loc("my_courses.filter_all") }
    static var myCoursesFilterInProgress: String { loc("my_courses.filter_in_progress") }
    static var myCoursesFilterCompleted: String { loc("my_courses.filter_completed") }
    static var myCoursesFilterEmpty: String { loc("my_courses.filter_empty") }
    static var myCoursesEmptySubtitle: String { loc("my_courses.empty_subtitle") }
    static var myCoursesContinueLearning: String { loc("my_courses.continue_learning") }
    static var myCoursesCompletedCertEarned: String { loc("my_courses.completed_cert_earned") }
    static var myCoursesInProgressBadge: String { loc("my_courses.badge_in_progress") }
    static var myCoursesNotStarted: String { loc("my_courses.badge_not_started") }
    static var myCoursesDone: String { loc("my_courses.badge_done") }
    static var myCoursesCompletedFilter: String { loc("my_courses.completed_filter") }
    /// Footer line under the enrolled list — explains that progress
    /// keeps working offline once lessons are downloaded. Shown only on
    /// the "My Courses" tab.
    static var myCoursesOfflineFooter: String { loc("my_courses.offline_footer") }
    /// Trailing label on a row whose course is 100 % complete, sat in
    /// place of the "X / Y" fraction other rows show.
    static var myCoursesCompleteLabel: String { loc("my_courses.complete_label") }
    /// "%1$d enrolled · %2$d completed" — subtitle under the big title
    /// on the My Courses screen. Two positional integers so the Arabic
    /// translation can reorder them.
    static var myCoursesSubtitleFmt: String { loc("my_courses.subtitle_fmt") }
    static var lessonsLowercase: String { loc("course.lessons_lower") }

    // MARK: - Course Detail v2
    static var courseBestseller: String { loc("course.bestseller") }
    static var courseCategoryUxUi: String { loc("course.category_ux_ui") }
    static var courseYourProgress: String { loc("course.your_progress") }
    static var courseProgressOf: String { loc("course.progress_of") }
    static var courseProgressNext: String { loc("course.progress_next") }
    static var courseInstructorSubtitle: String { loc("course.instructor_subtitle") }
    static var courseModule: String { loc("course.module") }
    static var courseInProgressLower: String { loc("course.in_progress_lower") }
    static var courseNotStartedLower: String { loc("course.not_started_lower") }

    // MARK: - Lesson
    static var lesson: String { loc("lesson.title") }
    static var videoLesson: String { loc("lesson.video") }
    static var documentLesson: String { loc("lesson.document") }
    static var textLesson: String { loc("lesson.text") }
    static var noDocuments: String { loc("lesson.no_documents") }
    static var documents: String { loc("lesson.documents") }

    // MARK: - Lesson player (V43 redesign)
    static var lessonPlayerRetry: String { loc("lesson_player.retry") }
    static var lessonPlayerProtected: String { loc("lesson_player.protected") }
    static var lessonPlayerAddNote: String { loc("lesson_player.add_note") }
    static var lessonPlayerViewNotes: String { loc("lesson_player.view_notes") }
    static var lessonPlayerPreviousLesson: String { loc("lesson_player.previous_lesson") }
    static var lessonPlayerNextLesson: String { loc("lesson_player.next_lesson") }
    static var lessonPlayerNotes: String { loc("lesson_player.notes") }
    static var lessonPlayerNewNote: String { loc("lesson_player.new_note") }
    static var lessonPlayerMarkFinished: String { loc("lesson_player.mark_finished") }
    static var lessonPlayerNoteSavedTitle: String { loc("lesson_player.note_saved_title") }
    /// Format: "Pinned to %@" — the trailing argument is a mm:ss timestamp.
    static var lessonPlayerNoteSavedPinnedFmt: String { loc("lesson_player.note_saved_pinned_fmt") }
    static var lessonPlayerNoteSavedDismiss: String { loc("lesson_player.note_saved_dismiss") }
    static var lessonPlayerMarkDone: String { loc("lesson_player.mark_done") }
    static var lessonPlayerCompleted: String { loc("lesson_player.completed") }
    static var lessonPlayerUpNext: String { loc("lesson_player.up_next") }
    /// Format: "%d attendees" — meta row under the lesson title.
    static var lessonPlayerAttendeesFmt: String { loc("lesson_player.attendees_fmt") }
    /// Eyebrow inside the blue active-note callout (e.g. "your note").
    static var lessonPlayerYourNote: String { loc("lesson_player.your_note") }
    /// Format: "%d NOTES ON THIS LESSON" — section header for the inline
    /// timestamped-notes list under the action row.
    static var lessonPlayerNotesCountFmt: String { loc("lesson_player.notes_count_fmt") }
    /// Eyebrow label preceding the lesson number, e.g. "LESSON 3.2 · ALGEBRA".
    static var lessonPlayerEyebrowLesson: String { loc("lesson_player.eyebrow_lesson") }

    // MARK: - Lesson player — video unavailable
    //
    // Two distinct families. The `processing.*` strings describe a lesson
    // whose video is still moving through the upload/encode pipeline —
    // nothing is broken and there is nothing for the student to fix — while
    // the `error.*` strings are genuine failures. Keeping them apart is the
    // whole point: a still-encoding lesson used to render the hard error
    // "Video not found", which reads as a bug.
    static var lessonPlayerProcessingTitle: String { loc("lesson_player.processing_title") }
    static var lessonPlayerProcessingMessage: String { loc("lesson_player.processing_message") }
    static var lessonPlayerProcessingCheckAgain: String { loc("lesson_player.processing_check_again") }
    /// `VideoStatus.FAILED` — the encode ran and gave up. Deliberately not a
    /// "video not found" message: the lesson does have a video, the pipeline
    /// just couldn't produce a playable rendition. Every *pre*-READY status
    /// (and the 404 an unencoded lesson returns) routes to the processing
    /// state instead, so this string only ever means a real failure.
    static var lessonPlayerErrorProcessingFailed: String { loc("lesson_player.error_processing_failed") }
    static var lessonPlayerErrorInvalidUrl: String { loc("lesson_player.error_invalid_url") }
    static var lessonPlayerErrorNotEnrolled: String { loc("lesson_player.error_not_enrolled") }
    static var lessonPlayerErrorUnknown: String { loc("lesson_player.error_unknown") }
    /// Format: "Playback failed: %@" — the argument is the AVFoundation
    /// error description, which iOS already localises.
    static var lessonPlayerErrorPlaybackFailedFmt: String { loc("lesson_player.error_playback_failed_fmt") }
    /// Format: "Playback stopped: %@" — same, for a mid-stream stall.
    static var lessonPlayerErrorPlaybackStoppedFmt: String { loc("lesson_player.error_playback_stopped_fmt") }

    // MARK: - Viewer presence guard (anti-sharing / anti-recording)
    static var presenceGuardContinue: String { loc("presence_guard.continue") }
    static var presenceGuardNoFaceTitle: String { loc("presence_guard.no_face_title") }
    static var presenceGuardNoFaceMessage: String { loc("presence_guard.no_face_message") }
    static var presenceGuardMultipleTitle: String { loc("presence_guard.multiple_title") }
    static var presenceGuardMultipleMessage: String { loc("presence_guard.multiple_message") }
    static var presenceGuardWrongPersonTitle: String { loc("presence_guard.wrong_person_title") }
    static var presenceGuardWrongPersonMessage: String { loc("presence_guard.wrong_person_message") }
    static var presenceGuardLowLightTitle: String { loc("presence_guard.low_light_title") }
    static var presenceGuardLowLightMessage: String { loc("presence_guard.low_light_message") }
    static var presenceGuardRecordingTitle: String { loc("presence_guard.recording_title") }
    static var presenceGuardRecordingMessage: String { loc("presence_guard.recording_message") }
    // Live HUD + alert banners
    static var presenceHudRecording: String { loc("presence_guard.hud_recording") }
    /// Format: "%d people in view" — multiple-viewers alert banner.
    static var presenceAlertMultipleFmt: String { loc("presence_guard.alert_multiple_fmt") }
    static var presenceAlertPhone: String { loc("presence_guard.alert_phone") }
    // Consent screen
    static var presenceConsentTitle: String { loc("presence_consent.title") }
    static var presenceConsentSubtitle: String { loc("presence_consent.subtitle") }
    static var presenceConsentBullet1Title: String { loc("presence_consent.bullet1_title") }
    static var presenceConsentBullet1Body: String { loc("presence_consent.bullet1_body") }
    static var presenceConsentBullet2Title: String { loc("presence_consent.bullet2_title") }
    static var presenceConsentBullet2Body: String { loc("presence_consent.bullet2_body") }
    static var presenceConsentBullet3Title: String { loc("presence_consent.bullet3_title") }
    static var presenceConsentBullet3Body: String { loc("presence_consent.bullet3_body") }
    static var presenceConsentBullet4Title: String { loc("presence_consent.bullet4_title") }
    static var presenceConsentBullet4Body: String { loc("presence_consent.bullet4_body") }
    static var presenceConsentAccept: String { loc("presence_consent.accept") }
    static var presenceConsentDecline: String { loc("presence_consent.decline") }
    static var presenceCameraRequiredTitle: String { loc("presence_camera_required.title") }
    static var presenceCameraRequiredMessage: String { loc("presence_camera_required.message") }
    static var presenceCameraRequiredButton: String { loc("presence_camera_required.button") }
    static var privacyTiltHint: String { loc("presence_guard.tilt_hint") }

    // MARK: - Content protection (screen recording / capture)
    static var captureBlockedTitle: String { loc("capture.blocked_title") }
    static var captureBlockedMessage: String { loc("capture.blocked_message") }
    static var captureBlockedExternalMessage: String { loc("capture.blocked_external_message") }
    static var captureScreenOffTitle: String { loc("capture.screen_off_title") }
    static var captureScreenOffMessage: String { loc("capture.screen_off_message") }
    static var securityContentProtectionSection: String { loc("security.content_protection_section") }
    static var securityScreenRecordRow: String { loc("security.screen_record_row") }
    static var securityScreenRecordOn: String { loc("security.screen_record_on") }
    static var securityScreenRecordOff: String { loc("security.screen_record_off") }
    // Account deletion
    static var securityDeleteConfirmTitle: String { loc("security.delete_confirm_title") }
    static var securityDeleteConfirmMessage: String { loc("security.delete_confirm_message") }
    static var integrityBlockedTitle: String { loc("integrity.blocked_title") }
    static var integrityBlockedMessage: String { loc("integrity.blocked_message") }
    static var fullScreenRequiredTitle: String { loc("fullscreen.required_title") }
    static var fullScreenRequiredMessage: String { loc("fullscreen.required_message") }

    static var lessonReadingRequiredEyebrow: String { loc("lesson.reading_required_eyebrow") }
    static var lessonReadingProgressLabel: String { loc("lesson.reading_progress_label") }
    /// Format: "p.%d of %d" — progress text on the Required Reading card.
    static var lessonReadingProgressFmt: String { loc("lesson.reading_progress_fmt") }
    static var lessonReadingStart: String { loc("lesson.reading_start") }
    static var lessonReadingContinue: String { loc("lesson.reading_continue") }
    /// Eyebrow above the list of supplementary lesson documents shown
    /// beneath the Required Reading card in the player.
    static var lessonMaterialsEyebrow: String { loc("lesson.materials_eyebrow") }

    static var lessonAddNoteTitleAdd: String { loc("lesson.add_note_title_add") }
    static var lessonAddNoteTitleEdit: String { loc("lesson.add_note_title_edit") }
    static var lessonAddNoteCancel: String { loc("lesson.add_note_cancel") }
    static var lessonAddNoteSave: String { loc("lesson.add_note_save") }
    static var lessonAddNotePlaceholder: String { loc("lesson.add_note_placeholder") }
    static var lessonAddNoteFailed: String { loc("lesson.add_note_failed") }
    /// Eyebrow on the selected-text card when no page anchor is known.
    static var lessonAddNoteSelectedTextLabel: String { loc("lesson.add_note_selected_text_label") }
    /// Format: "SELECTED TEXT · P.%d" — eyebrow on the selected-text card
    /// inside the Add Note compose sheet (PDF reader entry).
    static var lessonAddNoteSelectedTextPageFmt: String { loc("lesson.add_note_selected_text_page_fmt") }
    /// Format: "Page %d · %@" — left-hand label on the Add Note footer
    /// when the note is anchored to a PDF page.
    static var lessonAddNoteFooterPageFmt: String { loc("lesson.add_note_footer_page_fmt") }

    static var lessonNotesListTitle: String { loc("lesson.notes_list_title") }
    static var lessonNotesListAdd: String { loc("lesson.notes_list_add") }
    static var lessonNotesListEmpty: String { loc("lesson.notes_list_empty") }
    static var lessonNotesEdit: String { loc("lesson.notes_edit") }
    static var lessonNotesDelete: String { loc("lesson.notes_delete") }
    // Playback Settings (May 2026)
    static var playbackSettingsBackLabel: String   { loc("playback_settings.back") }
    static var playbackSettingsTitle: String       { loc("playback_settings.title") }
    static var playbackSettingsSpeed: String       { loc("playback_settings.speed") }
    static var playbackSettingsSpeedFooter: String { loc("playback_settings.speed_footer") }
    static var playbackSettingsQuality: String     { loc("playback_settings.quality") }
    static var playbackSettingsQualityFooter: String { loc("playback_settings.quality_footer") }
    /// Shown instead of the normal quality footer when the lesson streams as
    /// a single progressive file (no adaptive renditions to choose between).
    static var playbackSettingsQualitySingle: String { loc("playback_settings.quality_single") }
    static var playbackSettingsQualityLow: String     { loc("playback_settings.quality_low") }
    static var playbackSettingsQualityLowSub: String  { loc("playback_settings.quality_low_sub") }
    static var playbackSettingsQualityMed: String     { loc("playback_settings.quality_med") }
    static var playbackSettingsQualityMedSub: String  { loc("playback_settings.quality_med_sub") }
    static var playbackSettingsQualityHigh: String    { loc("playback_settings.quality_high") }
    static var playbackSettingsQualityHighSub: String { loc("playback_settings.quality_high_sub") }
    static var playbackSettingsOptions: String        { loc("playback_settings.options") }
    static var playbackSettingsAutoplay: String       { loc("playback_settings.autoplay") }
    static var playbackSettingsSubtitles: String      { loc("playback_settings.subtitles") }
    static var playbackSettingsSubtitlesUnavailable: String { loc("playback_settings.subtitles_unavailable") }

    // MyNotesView (V45)
    static var lessonNotesFilterAll: String      { loc("lesson.notes_filter_all") }
    static var lessonNotesFilterDocument: String { loc("lesson.notes_filter_document") }
    static var lessonNotesFilterVideo: String    { loc("lesson.notes_filter_video") }
    static var lessonNotesTypeVideo: String      { loc("lesson.notes_type_video") }
    static var lessonNotesTypeDocument: String   { loc("lesson.notes_type_document") }
    static var lessonNotesDateToday: String      { loc("lesson.notes_date_today") }
    static var lessonNotesDateYesterday: String  { loc("lesson.notes_date_yesterday") }
    /// Format: "%d NOTES · %d SOURCES" — subtitle strip under the filter pills.
    static var lessonNotesSubtitleFmt: String    { loc("lesson.notes_subtitle_fmt") }
    /// Format: "p.%d" — anchor pill text on document notes.
    static var lessonNotesPagePrefixFmt: String  { loc("lesson.notes_page_prefix_fmt") }
    /// Format: "YOUR NOTE · PAGE %d" — eyebrow on the bottom-anchored
    /// note caption shown over a PDF page.
    static var lessonNotesCalloutEyebrowFmt: String { loc("lesson.notes_callout_eyebrow_fmt") }
    /// "YOUR NOTE" — eyebrow fallback when the note has no pinned page.
    static var lessonNotesCalloutEyebrow: String    { loc("lesson.notes_callout_eyebrow") }

    // PDF reader (V43 redesign)
    /// Format: "LESSON %@" — eyebrow next to the back button, e.g. "LESSON 3.2".
    static var lessonPdfEyebrowFmt: String { loc("lesson_pdf.eyebrow_fmt") }
    /// Format: "PDF · Page %d of %d" — subtitle under the title.
    static var lessonPdfPageOfFmt: String { loc("lesson_pdf.page_of_fmt") }
    static var lessonPdfPagesLabel: String { loc("lesson_pdf.pages_label") }
    static var lessonPdfPrev: String { loc("lesson_pdf.prev") }
    static var lessonPdfNext: String { loc("lesson_pdf.next") }
    static var lessonPdfAddNote: String { loc("lesson_pdf.add_note") }
    /// Short bottom-bar label under the compose icon (Figma 1695 reader bar).
    static var lessonPdfAdd: String { loc("lesson_pdf.add") }
    static var lessonPdfMyNotes: String { loc("lesson_pdf.my_notes") }
    static var lessonPdfInvalidUrl: String { loc("lesson_pdf.invalid_url") }
    static var lessonPdfOpenFailed: String { loc("lesson_pdf.open_failed") }
    // In-document Cmd-F-style search (magnifying-glass icon in the
    // PDF reader header).
    static var lessonPdfSearchPlaceholder: String { loc("lesson_pdf.search_placeholder") }
    static var lessonPdfSearchNoMatches: String { loc("lesson_pdf.search_no_matches") }
    static var lessonPdfSearchMatchCountFmt: String { loc("lesson_pdf.search_match_count_fmt") }
    /// "Notes" — label on the bottom-bar pill that opens the
    /// "Notes on this page" sheet.
    static var lessonPdfNotesPill: String { loc("lesson_pdf.notes_pill") }

    // MARK: - Document note flow (June 2026 redesign)
    // Two-field compose sheet, "Notes on this page" sheet, and the
    // save / delete toasts that replace the single-field Add Note flow
    // for PDF-anchored notes.
    static var docNoteNewTitle: String  { loc("lesson.doc_note_new_title") }
    static var docNoteEditTitle: String { loc("lesson.doc_note_edit_title") }
    /// Format: "Note %d of %d · Page %d".
    static var docNoteSubtitleFmt: String { loc("lesson.doc_note_subtitle_fmt") }
    static var docNoteContentLabel: String  { loc("lesson.doc_note_content_label") }
    static var docNoteYourNoteLabel: String { loc("lesson.doc_note_your_note_label") }
    static var docNoteOptional: String { loc("lesson.doc_note_optional") }
    static var docNotePasteHint: String { loc("lesson.doc_note_paste_hint") }
    static var docNoteContentPlaceholder: String  { loc("lesson.doc_note_content_placeholder") }
    static var docNoteYourNotePlaceholder: String { loc("lesson.doc_note_your_note_placeholder") }
    /// Format: "%d / %d words" — per-field word counter.
    static var docNoteWordsFmt: String { loc("lesson.doc_note_words_fmt") }
    static var docNoteHelper: String { loc("lesson.doc_note_helper") }
    static var docNoteDelete: String { loc("lesson.doc_note_delete") }
    static var docNoteDeleteTitle: String { loc("lesson.doc_note_delete_title") }
    /// Format: "This permanently deletes the note on page %d. This cannot be undone."
    static var docNoteDeleteMessageFmt: String { loc("lesson.doc_note_delete_message_fmt") }
    static var docNoteDeleteKeep: String { loc("lesson.doc_note_delete_keep") }
    static var docNoteDeleteDiscard: String { loc("lesson.doc_note_delete_discard") }

    // "Notes on this page" sheet
    static var notesOnPageTitle: String { loc("lesson.notes_on_page_title") }
    /// Format: "Page %d · %@".
    static var notesOnPageSubtitleFmt: String { loc("lesson.notes_on_page_subtitle_fmt") }
    static var notesOnPageEmpty: String { loc("lesson.notes_on_page_empty") }
    static var notesOnPageAdd: String { loc("lesson.notes_on_page_add") }
    static var notesAllLink: String { loc("lesson.notes_all_link") }
    static var notesSeeAll: String { loc("lesson.notes_see_all") }

    // Save / delete toasts
    static var noteSavedToMyNotes: String { loc("lesson.note_saved_to_my_notes") }
    static var noteDeletedToast: String { loc("lesson.note_deleted_toast") }
    static var noteUndo: String { loc("lesson.note_undo") }

    // MARK: - AI Tutor
    static var aiTutor: String { loc("ai_tutor.title") }
    static var askQuestion: String { loc("ai_tutor.ask_question") }
    static var askPlaceholder: String { loc("ai_tutor.placeholder") }
    static var send: String { loc("ai_tutor.send") }
    static var streaming: String { loc("ai_tutor.streaming") }
    static var sources: String { loc("ai_tutor.sources") }
    static var page: String { loc("ai_tutor.page") }
    static var feedbackThumbsUp: String { loc("ai_tutor.thumbs_up") }
    static var feedbackThumbsDown: String { loc("ai_tutor.thumbs_down") }
    static var selectCourse: String { loc("ai_tutor.select_course") }
    /// Compact form for the course-picker button, where the full
    /// "Select an enrolled course…" sentence doesn't fit.
    static var aiTutorSelectCourseShort: String { loc("ai_tutor.select_course_short") }
    static var aiTutorErrorSelectCourse: String { loc("ai_tutor.error_select_course") }
    static var aiTutorErrorUnknown: String { loc("ai_tutor.error_unknown") }
    static var aiTutorErrorConfig: String { loc("ai_tutor.error_config") }
    static var aiTutorErrorEncoding: String { loc("ai_tutor.error_encoding") }
    static var aiTutorErrorStream: String { loc("ai_tutor.error_stream") }
    /// "Error: %@" — banner + bubble copy for a failed single-model turn.
    static func aiTutorError(_ message: String) -> String {
        String(format: loc("ai_tutor.error_fmt"), message)
    }
    /// "\n[Error: %@]" — appended to a partially-streamed answer when the
    /// stream itself reports a failure mid-flight.
    static func aiTutorStreamErrorInline(_ message: String) -> String {
        String(format: loc("ai_tutor.error_stream_inline_fmt"), message)
    }

    // MARK: - AI Tutor · multi-model ask
    static var aiMultiTitle: String { loc("ai_multi.title") }
    static var aiMultiEntryTitle: String { loc("ai_multi.entry_title") }
    static var aiMultiEntrySubtitle: String { loc("ai_multi.entry_subtitle") }
    static var aiMultiEntryLesson: String { loc("ai_multi.entry_lesson") }
    static var aiMultiOpenChat: String { loc("ai_multi.open_chat") }
    static var aiMultiModeFast: String { loc("ai_multi.mode_fast") }
    static var aiMultiModeDeep: String { loc("ai_multi.mode_deep") }
    static var aiMultiModeFastHint: String { loc("ai_multi.mode_fast_hint") }
    static var aiMultiModeDeepHint: String { loc("ai_multi.mode_deep_hint") }
    static var aiMultiModelsLabel: String { loc("ai_multi.models_label") }
    static var aiMultiModelsAuto: String { loc("ai_multi.models_auto") }
    static var aiMultiModelsCompareAll: String { loc("ai_multi.models_compare_all") }
    static var aiMultiModelsCompareAllHint: String { loc("ai_multi.models_compare_all_hint") }
    static var aiMultiModelsPickerTitle: String { loc("ai_multi.models_picker_title") }
    static var aiMultiModelsCapHintFast: String { loc("ai_multi.models_cap_hint_fast") }
    static var aiMultiModelsCapHintDeep: String { loc("ai_multi.models_cap_hint_deep") }
    static var aiMultiModelsLoading: String { loc("ai_multi.models_loading") }
    static var aiMultiModelsEmpty: String { loc("ai_multi.models_empty") }
    static var aiMultiModelsError: String { loc("ai_multi.models_error") }
    static var aiMultiModelVision: String { loc("ai_multi.model_vision") }
    static var aiMultiModelFastDefault: String { loc("ai_multi.model_fast_default") }
    static var aiMultiVisionFilterNote: String { loc("ai_multi.vision_filter_note") }
    static var aiMultiQuestionPlaceholder: String { loc("ai_multi.question_placeholder") }
    static var aiMultiAsk: String { loc("ai_multi.ask") }
    static var aiMultiWaitingSubtitle: String { loc("ai_multi.waiting_subtitle") }
    static var aiMultiWaitingCancel: String { loc("ai_multi.waiting_cancel") }
    static var aiMultiStatusTimeout: String { loc("ai_multi.status_timeout") }
    static var aiMultiStatusRateLimited: String { loc("ai_multi.status_rate_limited") }
    static var aiMultiStatusError: String { loc("ai_multi.status_error") }
    static var aiMultiStatusTimeoutHint: String { loc("ai_multi.status_timeout_hint") }
    static var aiMultiStatusRateLimitedHint: String { loc("ai_multi.status_rate_limited_hint") }
    static var aiMultiStatusErrorHint: String { loc("ai_multi.status_error_hint") }
    static var aiMultiBestBadge: String { loc("ai_multi.best_badge") }
    static var aiMultiBestRationaleTitle: String { loc("ai_multi.best_rationale_title") }
    static var aiMultiCopy: String { loc("ai_multi.copy") }
    static var aiMultiCopied: String { loc("ai_multi.copied") }
    static var aiMultiEmptyTitle: String { loc("ai_multi.empty_title") }
    static var aiMultiEmptySubtitle: String { loc("ai_multi.empty_subtitle") }
    static var aiMultiErrorAllFailed: String { loc("ai_multi.error_all_failed") }
    static var aiMultiErrorGeneric: String { loc("ai_multi.error_generic") }
    /// Label for an answer row the server returned without a usable model id.
    static var aiMultiUnknownModel: String { loc("ai_multi.unknown_model") }
    static var aiMultiErrorEmptyQuestion: String { loc("ai_multi.error_empty_question") }
    static var aiMultiAttachPhoto: String { loc("ai_multi.attach_photo") }
    static var aiMultiPhotoAttached: String { loc("ai_multi.photo_attached") }
    static var aiMultiPhotoRemove: String { loc("ai_multi.photo_remove") }
    static var aiMultiPhotoUploading: String { loc("ai_multi.photo_uploading") }
    static var aiMultiPhotoNotImage: String { loc("ai_multi.photo_not_image") }
    static var aiMultiRatingThanks: String { loc("ai_multi.rating_thanks") }

    // MARK: AI Tutor · hub
    //
    // The bottom-bar AI entry has no course context, so it opens a hub that
    // resolves the course first. These strings cover the hub's three states
    // (loading / picker / no enrollments) plus the bar item's accessibility
    // label — the item is deliberately unlabelled visually, so VoiceOver is
    // the only place its name is spoken.
    static var aiHubTitle: String { loc("ai_hub.title") }
    static var aiHubTabA11y: String { loc("ai_hub.tab_a11y") }
    static var aiHubTabA11yHint: String { loc("ai_hub.tab_a11y_hint") }
    static var aiHubHeadline: String { loc("ai_hub.headline") }
    static var aiHubSubheadline: String { loc("ai_hub.subheadline") }
    static var aiHubPickCourse: String { loc("ai_hub.pick_course") }
    static var aiHubPickCourseHint: String { loc("ai_hub.pick_course_hint") }
    static var aiHubLoading: String { loc("ai_hub.loading") }
    static var aiHubEmptyTitle: String { loc("ai_hub.empty_title") }
    static var aiHubEmptyBody: String { loc("ai_hub.empty_body") }
    static var aiHubEmptyCta: String { loc("ai_hub.empty_cta") }
    static var aiHubClose: String { loc("ai_hub.close") }

    /// "Asking %d models…" — waiting-state headline. Every form is its own
    /// key because Arabic's 1 / 2 / 3–10 / 11+ split doesn't survive a bare
    /// %d substitution — see `countedForm`.
    static func aiMultiWaitingTitle(_ count: Int) -> String {
        countedForm(count,
                    one: "ai_multi.waiting_title_one",
                    two: "ai_multi.waiting_title_two",
                    fewFmt: "ai_multi.waiting_title_fmt",
                    manyFmt: "ai_multi.waiting_title_many_fmt")
    }
    /// Waiting headline when the server picks the models and the client
    /// therefore has no count to name.
    static var aiMultiWaitingTitleUnknown: String { loc("ai_multi.waiting_title_unknown") }
    /// "%d selected" — model-picker summary. Reachable at 2 and 3 by design
    /// (DEEP caps hand-picking at 3), which is exactly the dual/plural
    /// boundary in Arabic, so it takes the same four-form treatment.
    static func aiMultiModelsSelected(_ count: Int) -> String {
        countedForm(count,
                    one: "ai_multi.models_selected_one",
                    two: "ai_multi.models_selected_two",
                    fewFmt: "ai_multi.models_selected_fmt",
                    manyFmt: "ai_multi.models_selected_many_fmt")
    }

    /// Picks the grammatically correct key for a count.
    ///
    /// Arabic splits four ways where English splits two: 1 is singular, 2
    /// takes the *dual* (نموذجين), 3–10 take the broken plural (نماذج), and
    /// 11+ (and 0) go back to a singular noun in the accusative (نموذجًا).
    /// English simply maps `one` to the singular and the other three to the
    /// same plural wording, so both locale files stay natural without the
    /// call sites knowing which language they're in.
    ///
    /// The `one` and `two` keys carry their number in the copy, so they take
    /// no format argument; `few`/`many` substitute `%d`.
    private static func countedForm(_ count: Int,
                                    one: String,
                                    two: String,
                                    fewFmt: String,
                                    manyFmt: String) -> String {
        switch count {
        case 1:      return loc(one)
        case 2:      return loc(two)
        case 3...10: return String(format: loc(fewFmt), count)
        default:     return String(format: loc(manyFmt), count)
        }
    }
    /// "%1$d of %2$d" — pager position above the answer cards.
    static func aiMultiAnswerPosition(_ index: Int, _ total: Int) -> String {
        String(format: loc("ai_multi.answer_position_fmt"), index, total)
    }
    /// "%@ s" — per-answer latency. The number is pre-formatted by the
    /// caller so the decimal separator follows the app locale.
    static func aiMultiLatency(_ seconds: String) -> String {
        String(format: loc("ai_multi.latency_fmt"), seconds)
    }
    /// "%1$d of %2$d answered" — summary line under a DEEP result set.
    static func aiMultiAnsweredSummary(_ ok: Int, _ total: Int) -> String {
        String(format: loc("ai_multi.answered_summary_fmt"), ok, total)
    }

    /// Language code the app is currently rendering in ("en" / "ar").
    /// Exposed so networking call sites can send a matching
    /// `Accept-Language` — the AI tutor needs the models to answer in the
    /// language the student is reading, which is the *app* locale and not
    /// necessarily the device's.
    static var currentLanguageCode: String {
        UserDefaults.standard.string(forKey: AppLocaleDefault.storageKey)
            ?? AppLocaleDefault.code
    }

    // MARK: - Profile
    static var profile: String { loc("profile.title") }
    static var language: String { loc("profile.language") }
    static var english: String { loc("profile.english") }
    static var arabic: String { loc("profile.arabic") }

    // MARK: - Home
    static var greetingMorning: String { loc("home.greeting_morning") }
    static var greetingAfternoon: String { loc("home.greeting_afternoon") }
    static var greetingEvening: String { loc("home.greeting_evening") }
    /// "Welcome to" prefix for the empty-state header (e.g. "Welcome to Droob, Noor").
    static var welcomeToPrefix: String { loc("home.welcome_prefix") }
    static var continueLearningKicker: String { loc("home.continue_learning") }
    static var continueLearningInProgress: String { loc("home.in_progress") }
    static var continueButton: String { loc("home.continue_button") }
    static var statStreak: String { loc("home.stat_streak") }
    static var statStreakUnit: String { loc("home.stat_streak_unit") }
    static var statWatch: String { loc("home.stat_watch") }
    static var statQuizAvg: String { loc("home.stat_quiz_avg") }
    static var statCourses: String { loc("home.stat_courses") }
    static var myCoursesHeader: String { loc("home.my_courses") }
    static var seeAll: String { loc("home.see_all") }
    static var nextSession: String { loc("home.next_session") }
    static var nextSessionAll: String { loc("home.next_session_all") }
    static var joinSessionButton: String { loc("home.join_session") }
    // Empty state
    static var homeEmptyTitle: String { loc("home.empty_title") }
    static var homeEmptySubtitle: String { loc("home.empty_subtitle") }
    static var homeBrowseCourses: String { loc("home.browse_courses") }
    static var homeRecommended: String { loc("home.recommended") }
    /// Format string for the "Because you enrolled in {X}" pill on the
    /// home "Recommended for you" card. {@code %@} = the prereq course's
    /// localized title (the course the student already owns that drove
    /// the match).
    static var homeRecommendedReasonFmt: String { loc("home.recommended_reason_fmt") }
    /// Format string for the meta line under a Recommended card —
    /// "{Instructor} · {N} lessons".
    static var homeRecommendedMetaFmt: String { loc("home.recommended_meta_fmt") }
    /// Format string for course-card meta — "%1$d lessons · %2$@h · ★ %3$@"
    /// where %1 = lesson count (Int), %2 = duration in hours (String),
    /// %3 = rating (String).
    static var homeCourseMetaFmt: String { loc("home.course_meta_fmt") }
    /// Format string for "X enrolled" suffix on catalog rows.
    static var homeEnrolledCountFmt: String { loc("home.enrolled_count_fmt") }

    // MARK: - Home → Ask Droob AI hero card
    //
    // The card is pure advertising: it reflects no live AI state, so every
    // string here is a constant. The four phrases each name something the
    // feature genuinely does (solve, read a PDF, export a solutions sheet,
    // explain step by step) and rotate in this fixed order — a card the
    // student sees every day should be predictable.
    static var homeAiHeroEyebrow: String { loc("home.ai_hero.eyebrow") }
    static var homeAiHeroTitle: String { loc("home.ai_hero.title") }
    static var homeAiHeroCta: String { loc("home.ai_hero.cta") }
    static var homeAiHeroPhrase1: String { loc("home.ai_hero.phrase_1") }
    static var homeAiHeroPhrase2: String { loc("home.ai_hero.phrase_2") }
    static var homeAiHeroPhrase3: String { loc("home.ai_hero.phrase_3") }
    static var homeAiHeroPhrase4: String { loc("home.ai_hero.phrase_4") }
    /// The whole card's VoiceOver label. Deliberately the **completed** copy
    /// for all four phrases: a screen reader must never encounter the
    /// half-typed streaming line.
    static var homeAiHeroA11y: String { loc("home.ai_hero.a11y") }
    static var homeAiHeroA11yHint: String { loc("home.ai_hero.a11y_hint") }
    // Figma Courses tab (segmented control)
    static var coursesSegmentMine: String { loc("courses.segment_mine") }
    static var coursesSegmentExplore: String { loc("courses.segment_explore") }
    static var coursesCountFmt: String { loc("courses.count_fmt") }

    // Enrolled tab redesign (instructor-grouped, stats bar)
    static var enrolledSubtitleFmt: String { loc("enrolled.subtitle_fmt") }
    static var enrolledStatCourses: String { loc("enrolled.stat_courses") }
    static var enrolledStatInProgress: String { loc("enrolled.stat_in_progress") }
    static var enrolledStatCompleted: String { loc("enrolled.stat_completed") }
    static var enrolledStatPending: String { loc("enrolled.stat_pending") }
    static var enrolledCourseSingular: String { loc("enrolled.course_singular") }
    static var enrolledCoursePlural: String { loc("enrolled.course_plural") }
    static var enrolledPercentComplete: String { loc("enrolled.percent_complete") }
    static var enrolledLiveSessionsFmt: String { loc("enrolled.live_sessions_fmt") }
    static var enrolledLiveSessionSingularFmt: String { loc("enrolled.live_session_singular_fmt") }
    static var enrolledCompleted: String { loc("enrolled.completed") }
    static var enrolledPendingApproval: String { loc("enrolled.pending_approval") }
    static var enrolledDiscoverMore: String { loc("enrolled.discover_more") }
    // Enrolled tab — empty state ("Welcome to Droob" onboarding)
    static var enrolledEmptyWelcomePrefix: String { loc("enrolled.empty_welcome_prefix") }
    static var enrolledEmptyHowTitle: String { loc("enrolled.empty_how_title") }
    static var enrolledEmptyPickTitle: String { loc("enrolled.empty_pick_title") }
    static var enrolledEmptyPickSubtitle: String { loc("enrolled.empty_pick_subtitle") }
    static var enrolledEmptyRequestTitle: String { loc("enrolled.empty_request_title") }
    static var enrolledEmptyRequestSubtitle: String { loc("enrolled.empty_request_subtitle") }
    static var enrolledEmptyBrowseAllFmt: String { loc("enrolled.empty_browse_all_fmt") }
    // Explore → instructor-first browse
    static var exploreSegmentInstructors: String { loc("explore.segment_instructors") }
    static var exploreSegmentCourses: String { loc("explore.segment_courses") }
    static var exploreBrowseInstructorsFmt: String { loc("explore.browse_instructors_fmt") }
    static var exploreInstructorStudentsFmt: String { loc("explore.instructor_students_fmt") }
    static var exploreInstructorCoursesFmt: String { loc("explore.instructor_courses_fmt") }
    static var exploreInstructorsCountFmt: String { loc("explore.instructors_count_fmt") }
    static var exploreStatYears: String { loc("explore.stat_years") }
    static var exploreStatRating: String { loc("explore.stat_rating") }
    static var exploreStatStudents: String { loc("explore.stat_students") }
    static var exploreStatCourses: String { loc("explore.stat_courses") }
    static var exploreViewCourses: String { loc("explore.view_courses") }
    static var exploreNoCourses: String { loc("explore.no_courses") }
    static var exploreNewBadge: String { loc("explore.new_badge") }
    static var exploreSeeAllCoursesFmt: String { loc("explore.see_all_courses_fmt") }
    static var exploreSeeAll: String { loc("explore.see_all") }
    static var coursesSort: String { loc("courses.sort") }
    static var coursesFilter: String { loc("courses.filter") }
    static var coursesAllChip: String { loc("courses.all_chip") }
    // Sort options on the Explore tab
    static var coursesSortTitle: String { loc("courses.sort_title") }
    static var coursesSortDone: String { loc("courses.sort_done") }
    static var coursesSortRecentlyAdded: String { loc("courses.sort_recently_added") }
    static var coursesSortMostPopular: String { loc("courses.sort_most_popular") }
    static var coursesSortHighestRated: String { loc("courses.sort_highest_rated") }
    static var coursesSortPriceLowHigh: String { loc("courses.sort_price_low_high") }
    static var coursesSortPriceHighLow: String { loc("courses.sort_price_high_low") }
    // My Courses sort options — client-side ordering of enrolled rows
    static var mineSortRecentlyActive: String { loc("my_courses.sort_recently_active") }
    static var mineSortRecentlyEnrolled: String { loc("my_courses.sort_recently_enrolled") }
    static var mineSortProgressHighLow: String { loc("my_courses.sort_progress_high_low") }
    // Filter options on the Explore tab
    static var coursesFilterTitle: String { loc("courses.filter_title") }
    static var coursesFilterAll: String { loc("courses.filter_all") }
    static var coursesFilterFree: String { loc("courses.filter_free") }
    static var coursesFilterPaid: String { loc("courses.filter_paid") }
    static var coursesFilterEnrolled: String { loc("courses.filter_enrolled") }
    // Multi-section filter sheet (Figma)
    static var coursesFilterSheetTitle: String { loc("courses.filter_sheet_title") }
    static var coursesFilterClearAll: String { loc("courses.filter_clear_all") }
    static var coursesFilterApply: String { loc("courses.filter_apply") }
    static var coursesFilterSectionPrice: String { loc("courses.filter_section_price") }
    static var coursesFilterSectionRating: String { loc("courses.filter_section_rating") }
    static var coursesFilterSectionLevel: String { loc("courses.filter_section_level") }
    static var coursesFilterPriceAny: String { loc("courses.filter_price_any") }
    static var coursesFilterPriceUnder50: String { loc("courses.filter_price_under_50") }
    static var coursesFilterPrice50To100: String { loc("courses.filter_price_50_100") }
    static var coursesFilterPrice100Plus: String { loc("courses.filter_price_100_plus") }
    static var coursesFilterRatingAny: String { loc("courses.filter_rating_any") }
    static var coursesFilterRating45: String { loc("courses.filter_rating_45") }
    static var coursesFilterRating40: String { loc("courses.filter_rating_40") }
    static var coursesFilterRating35: String { loc("courses.filter_rating_35") }
    static var coursesFilterLevelAll: String { loc("courses.filter_level_all") }
    static var coursesFilterLevelBeginner: String { loc("courses.filter_level_beginner") }
    static var coursesFilterLevelIntermediate: String { loc("courses.filter_level_intermediate") }
    static var coursesFilterLevelAdvanced: String { loc("courses.filter_level_advanced") }
    // Figma course detail sheet
    static var courseDetailSheetVideoLessonsHoursFmt: String { loc("course_detail.video_lessons_hours_fmt") }
    static var courseDetailSheetCertificate: String { loc("course_detail.certificate") }
    static var courseDetailSheetOfflineDownloads: String { loc("course_detail.offline_downloads") }
    static var courseDetailSheetApplePay: String { loc("course_detail.apple_pay") }
    static var courseDetailSheetOr: String { loc("course_detail.or") }
    static var courseDetailSheetEnrolWithCardFmt: String { loc("course_detail.enrol_with_card_fmt") }
    static var courseDetailSheetFooterGuarantee: String { loc("course_detail.footer_guarantee") }
    static var courseDetailSheetEnrollFreeCta: String { loc("course_detail.enroll_free_cta") }
    static var courseDetailSheetEnrollFreeFailed: String { loc("course_detail.enroll_free_failed") }
    // Course detail screen (full-screen)
    static var courseDetailCurriculumTitle: String { loc("course_detail.curriculum_title") }
    static var courseDetailCurriculumEmpty: String { loc("course_detail.curriculum_empty") }
    // Full curriculum screen (CurriculumView) — the deeper screen pushed from
    // course detail. Shares `course_detail.curriculum_title` and `course.module`
    // with the card above it so the two screens can never drift apart.
    static var curriculumModuleQuiz: String { loc("curriculum.module_quiz") }
    static var curriculumQuizPrompt: String { loc("curriculum.quiz_prompt") }
    /// "%d questions" — subtitle under a module-quiz row.
    static func curriculumQuizQuestions(_ n: Int) -> String {
        countedForm(n,
                    one: "curriculum.quiz_questions_one",
                    two: "curriculum.quiz_questions_two",
                    fewFmt: "curriculum.quiz_questions_fmt",
                    manyFmt: "curriculum.quiz_questions_many_fmt")
    }
    static var courseDetailRatingsTitle: String { loc("course_detail.ratings_title") }
    static var courseDetailRatingsCountFmt: String { loc("course_detail.ratings_count_fmt") }
    static var courseDetailSeeAllReviewsFmt: String { loc("course_detail.see_all_reviews_fmt") }
    static var courseDetailReviewAgeJustNow: String { loc("course_detail.review_age_just_now") }
    static var courseDetailReviewAgeMinutesFmt: String { loc("course_detail.review_age_minutes_fmt") }
    static var courseDetailReviewAgeHoursFmt: String { loc("course_detail.review_age_hours_fmt") }
    static var courseDetailReviewAgeDaysFmt: String { loc("course_detail.review_age_days_fmt") }
    static var courseDetailReviewAgeWeeksFmt: String { loc("course_detail.review_age_weeks_fmt") }
    static var courseDetailReviewAgeMonthsFmt: String { loc("course_detail.review_age_months_fmt") }
    static var courseDetailQaTitle: String { loc("course_detail.qa_title") }
    static var courseDetailRateThisCourse: String { loc("course_detail.rate_this_course") }
    static var courseDetailAskAQuestion: String { loc("course_detail.ask_a_question") }
    static var courseDetailRateSheetTitle: String { loc("course_detail.rate_sheet_title") }
    static var courseDetailRateSheetPlaceholder: String { loc("course_detail.rate_sheet_placeholder") }
    static var courseDetailRateSheetSubmit: String { loc("course_detail.rate_sheet_submit") }
    static var courseDetailRateSheetOnlyEnrolled: String { loc("course_detail.rate_sheet_only_enrolled") }
    static var courseDetailRateSheetThanks: String { loc("course_detail.rate_sheet_thanks") }
    static var courseDetailRateSheetQuestion: String { loc("course_detail.rate_sheet_question") }
    static var courseDetailRateSheetPrompt: String { loc("course_detail.rate_sheet_prompt") }
    static var courseDetailRateSheetSubmitButton: String { loc("course_detail.rate_sheet_submit_button") }
    static var courseDetailRateSheetCancel: String { loc("course_detail.rate_sheet_cancel") }
    static var courseDetailRateSheetLabel1: String { loc("course_detail.rate_sheet_label_1") }
    static var courseDetailRateSheetLabel2: String { loc("course_detail.rate_sheet_label_2") }
    static var courseDetailRateSheetLabel3: String { loc("course_detail.rate_sheet_label_3") }
    static var courseDetailRateSheetLabel4: String { loc("course_detail.rate_sheet_label_4") }
    static var courseDetailRateSheetLabel5: String { loc("course_detail.rate_sheet_label_5") }
    static var courseDetailRateSheetThanksFmt: String { loc("course_detail.rate_sheet_thanks_fmt") }
    static var courseDetailRateSheetSuccessSubtitle: String { loc("course_detail.rate_sheet_success_subtitle") }
    static var courseDetailRateSheetBackToCourse: String { loc("course_detail.rate_sheet_back_to_course") }
    static var courseDetailRateSheetEditReview: String { loc("course_detail.rate_sheet_edit_review") }
    static var courseDetailRateSheetYouFallback: String { loc("course_detail.rate_sheet_you_fallback") }
    // Enrollment requests (ADR-0006: request → instructor approval)
    static var enrollRequestRequestToEnroll: String { loc("enroll_request.request_to_enroll") }
    // Pre-login course preview (guest browse) CTA + hint.
    static var courseGuestSignInToEnroll: String { loc("course.guest_sign_in_to_enroll") }
    static var courseGuestPreviewHint: String { loc("course.guest_preview_hint") }
    static var guestBrowseTitle: String { loc("guest.browse_title") }
    static var guestBrowseSignIn: String { loc("guest.browse_sign_in") }
    static var loginBrowseCoursesGuest: String { loc("login.browse_courses_guest") }
    /// "Tell %@ why you want to join · they review each request"
    static var enrollRequestSubtitlePersonalFmt: String { loc("enroll_request.subtitle_personal_fmt") }
    /// "Note to %@"
    static var enrollRequestNoteToFmt: String { loc("enroll_request.note_to_fmt") }
    static var enrollRequestSentBanner: String { loc("enroll_request.sent_banner") }
    static var enrollRequestPendingButton: String { loc("enroll_request.pending_button") }
    static var enrollRequestPendingSubtitle: String { loc("enroll_request.pending_subtitle") }
    static var enrollRequestSheetTitleCreate: String { loc("enroll_request.sheet_title_create") }
    static var enrollRequestSheetTitleEdit: String { loc("enroll_request.sheet_title_edit") }
    static var enrollRequestSheetPromptCreate: String { loc("enroll_request.sheet_prompt_create") }
    static var enrollRequestSheetPromptEdit: String { loc("enroll_request.sheet_prompt_edit") }
    static var enrollRequestNotePlaceholder: String { loc("enroll_request.note_placeholder") }
    static var enrollRequestSubmitCreate: String { loc("enroll_request.submit_create") }
    static var enrollRequestSubmitEdit: String { loc("enroll_request.submit_edit") }
    static var enrollRequestCancelRequest: String { loc("enroll_request.cancel_request") }
    static var enrollRequestClose: String { loc("enroll_request.close") }
    static var enrollRequestSuccessTitle: String { loc("enroll_request.success_title") }
    static var enrollRequestSuccessSubtitle: String { loc("enroll_request.success_subtitle") }
    static var enrollRequestBackToCourse: String { loc("enroll_request.back_to_course") }
    static var enrollRequestCancelConfirmTitle: String { loc("enroll_request.cancel_confirm_title") }
    static var enrollRequestCancelConfirmMessage: String { loc("enroll_request.cancel_confirm_message") }
    static var enrollRequestCancelConfirmYes: String { loc("enroll_request.cancel_confirm_yes") }
    static var enrollRequestCancelConfirmNo: String { loc("enroll_request.cancel_confirm_no") }
    /// Shown when approval polling finds the instructor rejected the request.
    static var enrollRequestDecisionRejected: String { loc("enroll_request.decision_rejected") }
    /// Shown when approval polling finds the request was withdrawn/cancelled.
    static var enrollRequestDecisionCancelled: String { loc("enroll_request.decision_cancelled") }
    /// Replaces "Awaiting instructor approval" once the poll ceiling stops the loop.
    static var enrollRequestPollStoppedHint: String { loc("enroll_request.poll_stopped_hint") }
    /// Manual refresh offered after the poll ceiling.
    static var enrollRequestCheckNow: String { loc("enroll_request.check_now") }
    static var courseDetailAllReviewsTitle: String { loc("course_detail.all_reviews_title") }
    static var courseDetailAllReviewsEmpty: String { loc("course_detail.all_reviews_empty") }
    static var courseDetailQaPlaceholderTitle: String { loc("course_detail.qa_placeholder_title") }
    static var courseDetailQaPlaceholderBody: String { loc("course_detail.qa_placeholder_body") }
    /// "%d upvotes" — figma footer line under each question card.
    static var courseDetailQaUpvotesFmt: String { loc("course_detail.qa_upvotes_fmt") }
    /// "Instructor" tag rendered next to the instructor's reply name.
    static var courseDetailQaInstructorTag: String { loc("course_detail.qa_instructor_tag") }
    /// "See all %d questions" — bottom-row link in the Q&A card.
    static var courseDetailQaSeeAllFmt: String { loc("course_detail.qa_see_all_fmt") }
    /// "Questions you may ask" — instructor-curated FAQ section title.
    static var courseDetailPinnedFaqsTitle: String { loc("course_detail.pinned_faqs_title") }
    /// "Answered by your instructor" — subtitle under the FAQ title.
    static var courseDetailPinnedFaqsSubtitle: String { loc("course_detail.pinned_faqs_subtitle") }
    // Q&A screen (figma-accurate full list)
    static var qaScreenSubtitleFmt: String { loc("qa.subtitle_fmt") }
    static var qaScreenAskPlaceholder: String { loc("qa.ask_placeholder") }
    static var qaScreenFilterAll: String { loc("qa.filter_all") }
    static var qaScreenFilterAnswered: String { loc("qa.filter_answered") }
    static var qaScreenFilterUnanswered: String { loc("qa.filter_unanswered") }
    static var qaScreenFilterMine: String { loc("qa.filter_mine") }
    static var qaStatusAnswered: String { loc("qa.status_answered") }
    static var qaStatusUnanswered: String { loc("qa.status_unanswered") }
    static var qaEmptyState: String { loc("qa.empty_state") }
    static var qaAskSheetTitle: String { loc("qa.ask_sheet_title") }
    static var qaAskSheetPlaceholder: String { loc("qa.ask_sheet_placeholder") }
    static var qaAskSheetSubmit: String { loc("qa.ask_sheet_submit") }
    // Compact relative-time formatter
    static var qaAgeJustNow: String { loc("qa.age_just_now") }
    static var qaAgeMinutesFmt: String { loc("qa.age_minutes_fmt") }
    static var qaAgeHoursFmt: String { loc("qa.age_hours_fmt") }
    static var qaAgeYesterday: String { loc("qa.age_yesterday") }
    static var qaAgeDaysFmt: String { loc("qa.age_days_fmt") }
    // Instructor profile + chat
    static var instructorProfileStudents: String { loc("instructor_profile.students") }
    static var instructorProfileCourses: String { loc("instructor_profile.courses") }
    static var instructorProfileRating: String { loc("instructor_profile.rating") }
    static var instructorProfileYears: String { loc("instructor_profile.years") }
    static var instructorProfileAbout: String { loc("instructor_profile.about") }
    static var instructorProfileBioPlaceholder: String { loc("instructor_profile.bio_placeholder") }
    static var instructorProfileMessage: String { loc("instructor_profile.message") }
    static var instructorProfileCoursesSection: String { loc("instructor_profile.courses_section") }
    static var instructorProfileActiveNow: String { loc("instructor_profile.active_now") }
    static var instructorProfileActiveMinFmt: String { loc("instructor_profile.active_min_fmt") }
    static var instructorProfileActiveHourFmt: String { loc("instructor_profile.active_hour_fmt") }
    static var instructorProfileActiveDayFmt: String { loc("instructor_profile.active_day_fmt") }
    static var instructorProfileTabCourses: String { loc("instructor_profile.tab_courses") }
    static var instructorProfileTabEnrolled: String { loc("instructor_profile.tab_enrolled") }
    static var instructorProfileTabPending: String { loc("instructor_profile.tab_pending") }
    static var instructorProfileTabReviews: String { loc("instructor_profile.tab_reviews") }
    static var instructorProfileViewCourse: String { loc("instructor_profile.view_course") }
    static var instructorProfileReviewsCountFmt: String { loc("instructor_profile.reviews_count_fmt") }
    static var instructorProfileCoursesEmpty: String { loc("instructor_profile.courses_empty") }
    static var instructorProfileEnrolledEmpty: String { loc("instructor_profile.enrolled_empty") }
    static var instructorProfilePendingEmpty: String { loc("instructor_profile.pending_empty") }
    static var instructorProfilePendingPill: String { loc("instructor_profile.pending_pill") }
    static var instructorProfileStartLearningFmt: String { loc("instructor_profile.start_learning_fmt") }
    static var instructorProfileEnrolledEmptySub: String { loc("instructor_profile.enrolled_empty_sub") }
    static var instructorProfileYourNote: String { loc("instructor_profile.your_note") }
    static var instructorProfileEditNote: String { loc("instructor_profile.edit_note") }
    static var instructorProfileWaitingJustNow: String { loc("instructor_profile.waiting_just_now") }
    static var instructorProfileWaitingHoursFmt: String { loc("instructor_profile.waiting_hours_fmt") }
    static var instructorProfileWaitingDaysFmt: String { loc("instructor_profile.waiting_days_fmt") }
    static var instructorProfileWaitingWeeksFmt: String { loc("instructor_profile.waiting_weeks_fmt") }
    static var instructorProfileAllReviewsFmt: String { loc("instructor_profile.all_reviews_fmt") }
    static var instructorProfileEnrollFirst: String { loc("instructor_profile.enroll_first") }
    static var instructorProfileEnrolledHeaderFmt: String { loc("instructor_profile.enrolled_header_fmt") }
    static var instructorProfileEnrolledInProgressFmt: String { loc("instructor_profile.enrolled_in_progress_fmt") }
    static var instructorProfileEnrolledCompletedFmt: String { loc("instructor_profile.enrolled_completed_fmt") }
    static var instructorProfileEnrolledOfLessonsFmt: String { loc("instructor_profile.enrolled_of_lessons_fmt") }
    static var instructorProfileProgress: String { loc("instructor_profile.progress") }
    static var instructorProfileNextLesson: String { loc("instructor_profile.next_lesson") }
    static var instructorProfileReviewAction: String { loc("instructor_profile.review_action") }
    static var instructorProfileAllLessonsCompletedFmt: String { loc("instructor_profile.all_lessons_completed_fmt") }
    static var instructorProfileSeeOtherCoursesFmt: String { loc("instructor_profile.see_other_courses_fmt") }
    static var instructorReviewRateButton: String { loc("instructor_review.rate_button") }
    static var instructorReviewEditButton: String { loc("instructor_review.edit_button") }
    static var instructorReviewEmpty: String { loc("instructor_review.empty") }
    static var instructorReviewSheetQuestionFmt: String { loc("instructor_review.sheet_question_fmt") }
    static var instructorReviewSheetPrompt: String { loc("instructor_review.sheet_prompt") }
    static var instructorReviewSheetRoleLabel: String { loc("instructor_review.sheet_role_label") }
    static var instructorReviewSheetPlaceholder: String { loc("instructor_review.sheet_placeholder") }
    static var instructorReviewSheetSuccessSubtitle: String { loc("instructor_review.sheet_success_subtitle") }
    static var instructorReviewYourReviewBadge: String { loc("instructor_review.your_review_badge") }
    static var instructorReviewCardEdit: String { loc("instructor_review.card_edit") }
    static var instructorReviewCardDelete: String { loc("instructor_review.card_delete") }
    static var instructorReviewDeleteConfirmTitle: String { loc("instructor_review.delete_confirm_title") }
    static var instructorReviewDeleteConfirmMessage: String { loc("instructor_review.delete_confirm_message") }
    static var instructorReviewDeleteConfirmAction: String { loc("instructor_review.delete_confirm_action") }
    static var instructorReviewDeleteFailed: String { loc("instructor_review.delete_failed") }
    static var instructorReviewSheetYourRating: String { loc("instructor_review.sheet_your_rating") }
    static var instructorReviewSheetYourReview: String { loc("instructor_review.sheet_your_review") }
    static var instructorReviewSheetOptionalFmt: String { loc("instructor_review.sheet_optional_fmt") }
    static var instructorReviewSheetPostButton: String { loc("instructor_review.sheet_post_button") }
    static var instructorReviewSuccessEditButton: String { loc("instructor_review.success_edit_button") }
    static var chatComposerPlaceholder: String { loc("chat.composer_placeholder") }
    static var chatDayToday: String { loc("chat.day_today") }
    static var chatDayYesterday: String { loc("chat.day_yesterday") }
    static var chatSeenFmt: String { loc("chat.seen_fmt") }
    static var chatAttachmentTitle: String { loc("chat.attachment_title") }
    static var chatAttachmentGalleryTitle: String { loc("chat.attachment_gallery_title") }
    static var chatAttachmentGallerySubtitle: String { loc("chat.attachment_gallery_subtitle") }
    static var chatAttachmentDocumentsTitle: String { loc("chat.attachment_documents_title") }
    static var chatAttachmentDocumentsSubtitle: String { loc("chat.attachment_documents_subtitle") }
    static var chatAttachmentCancel: String { loc("chat.attachment_cancel") }
    static var chatAttachmentUploading: String { loc("chat.attachment_uploading") }
    static var chatAttachmentErrorEmpty: String { loc("chat.attachment_error_empty") }
    static var chatAttachmentErrorTooLargeFmt: String { loc("chat.attachment_error_too_large_fmt") }
    static var chatAttachmentErrorUnsupported: String { loc("chat.attachment_error_unsupported") }
    static var chatAttachmentErrorNetwork: String { loc("chat.attachment_error_network") }
    static var chatAttachmentErrorGeneric: String { loc("chat.attachment_error_generic") }
    static var chatDocumentDefault: String { loc("chat.document_default") }
    static var chatVoiceRecording: String { loc("chat.voice_recording") }
    static var chatVoiceMicDeniedTitle: String { loc("chat.voice_mic_denied_title") }
    static var chatVoiceMicDeniedBody: String { loc("chat.voice_mic_denied_body") }
    static var chatVoiceMicDeniedOk: String { loc("chat.voice_mic_denied_ok") }
    static var coursesGenericError: String { loc("course_detail.generic_error") }
    // Confirm payment sheet
    static var confirmPaymentTitle: String { loc("confirm_payment.title") }
    static var confirmPaymentLifetimeAccess: String { loc("confirm_payment.lifetime_access") }
    static var confirmPaymentCoursePrice: String { loc("confirm_payment.course_price") }
    static var confirmPaymentLimitedOffer: String { loc("confirm_payment.limited_offer") }
    static var confirmPaymentTotal: String { loc("confirm_payment.total") }
    static var confirmPaymentDoubleClickFaceId: String { loc("confirm_payment.double_click_face_id") }
    static var confirmPaymentSecuredFooter: String { loc("confirm_payment.secured_footer") }
    static var confirmPaymentCancel: String { loc("confirm_payment.cancel") }
    // Payment complete
    static var paymentCompleteTitle: String { loc("payment_complete.title") }
    static var paymentCompleteFullAccessFmt: String { loc("payment_complete.full_access_fmt") }
    static var paymentCompleteAmount: String { loc("payment_complete.amount") }
    static var paymentCompleteTransactionId: String { loc("payment_complete.transaction_id") }
    static var paymentCompletePaymentMethod: String { loc("payment_complete.payment_method") }
    static var paymentCompleteStartLearning: String { loc("payment_complete.start_learning") }
    static var paymentCompleteViewReceipt: String { loc("payment_complete.view_receipt") }
    static var paymentCompleteMethodApplePay: String { loc("payment_complete.method_apple_pay") }
    static var paymentCompleteMethodCardFmt: String { loc("payment_complete.method_card_fmt") }
    // Receipt screen
    static var receiptNavBack: String { loc("receipt.nav_back") }
    static var receiptTitle: String { loc("receipt.title") }
    static var receiptPaymentSuccessful: String { loc("receipt.payment_successful") }
    static var receiptItemsSection: String { loc("receipt.items_section") }
    static var receiptTransactionSection: String { loc("receipt.transaction_section") }
    static var receiptCourseEnrolment: String { loc("receipt.course_enrolment") }
    static var receiptTaxFmt: String { loc("receipt.tax_fmt") }
    static var receiptTotal: String { loc("receipt.total") }
    static var receiptDate: String { loc("receipt.date") }
    static var receiptDownloadPdf: String { loc("receipt.download_pdf") }
    static var receiptRequestRefund: String { loc("receipt.request_refund") }
    static var receiptRefundRequestedPill: String { loc("receipt.refund_requested_pill") }
    static var receiptRefundApprovedPill: String { loc("receipt.refund_approved_pill") }
    static var receiptRefundDeniedPill: String { loc("receipt.refund_denied_pill") }
    // PDF download modals
    static var receiptDownloadPreparingTitle: String { loc("receipt.download_preparing_title") }
    static var receiptDownloadPreparingSubtitle: String { loc("receipt.download_preparing_subtitle") }
    static var receiptDownloadedTitle: String { loc("receipt.downloaded_title") }
    static var receiptDownloadedSubtitle: String { loc("receipt.downloaded_subtitle") }
    static var receiptDownloadDone: String { loc("receipt.downloaded_done") }
    // Refund flow
    static var refundNavTitle: String { loc("refund.nav_title") }
    static var refundReasonHeader: String { loc("refund.reason_header") }
    static var refundReasonIntro: String { loc("refund.reason_intro") }
    static var refundReasonChangedMyMind: String { loc("refund.reason_changed_my_mind") }
    static var refundReasonCourseNotAsExpected: String { loc("refund.reason_course_not_as_expected") }
    static var refundReasonAccidentalPurchase: String { loc("refund.reason_accidental_purchase") }
    static var refundReasonOther: String { loc("refund.reason_other") }
    static var refundContinueButton: String { loc("refund.continue_button") }
    static var refundConfirmHeader: String { loc("refund.confirm_header") }
    static var refundConfirmCopy: String { loc("refund.confirm_copy") }
    static var refundConfirmAgree: String { loc("refund.confirm_agree") }
    static var refundConfirmSubmit: String { loc("refund.confirm_submit") }
    static var refundSummaryHeader: String { loc("refund.summary_header") }
    static var refundSummaryCourse: String { loc("refund.summary_course") }
    static var refundSummaryAmount: String { loc("refund.summary_amount") }
    static var refundSummaryTransaction: String { loc("refund.summary_transaction") }
    static var refundSummaryReason: String { loc("refund.summary_reason") }
    static var refundSummaryFooter: String { loc("refund.summary_footer") }
    static var refundSubmittedNavTitle: String { loc("refund.submitted_nav_title") }
    static var refundSubmittedTitle: String { loc("refund.submitted_title") }
    static var refundSubmittedSubtitle: String { loc("refund.submitted_subtitle") }
    static var refundSubmittedBackToReceipt: String { loc("refund.submitted_back_to_receipt") }
    static var refundOtherNotePlaceholder: String { loc("refund.other_note_placeholder") }

    // MARK: - Tabs
    static var tabHome: String { loc("tab.home") }
    static var tabCourses: String { loc("tab.courses") }
    static var tabSessions: String { loc("tab.sessions") }
    static var tabMessages: String { loc("tab.messages") }
    /// Title of the iOS-auto-generated "More" tab (5th tab when ≥ 6 root
    /// tabs exist). Patched into UIKit at runtime, see `MainTabView.renameMoreTab`.
    static var tabMore: String { loc("tab.more") }

    // MARK: - Catalog header
    /// "Browse " prefix that pairs with the gold "Catalog" accent in the header title.
    static var catalogTitlePrefix: String { loc("catalog.title_prefix") }
    static var catalogTitleAccent: String { loc("catalog.title_accent") }
    static var catalogSubtitle: String { loc("catalog.subtitle") }
    static var catalogSearchPlaceholder: String { loc("catalog.search_placeholder") }
    static var catalogBrowseEntryTitle: String { loc("catalog.browse_entry_title") }
    static var catalogBrowseEntrySubtitle: String { loc("catalog.browse_entry_subtitle") }

    // MARK: - Messages screen
    static var messagesScreenTitle: String { loc("messages.screen_title") }
    static var messagesTabInbox: String { loc("messages.tab_inbox") }
    static var messagesTabInboxFmt: String { loc("messages.tab_inbox_fmt") }
    static var messagesTabAnnouncements: String { loc("messages.tab_announcements") }
    static var messagesEmptyTitle: String { loc("messages.empty_title") }
    static var messagesEmptySubtitle: String { loc("messages.empty_subtitle") }
    static var announcementsEmptyTitle: String { loc("messages.announcements_empty_title") }
    static var announcementsEmptySubtitle: String { loc("messages.announcements_empty_subtitle") }
    static var messagesPreviewEmpty: String { loc("messages.preview_empty") }

    // MARK: - Sessions feature
    static var sessionsTitleLive: String { loc("sessions.title_live") }
    static var sessionsTitleSessions: String { loc("sessions.title_sessions") }
    static var sessionsEmptyTitle: String { loc("sessions.empty_title") }
    static var sessionsEmptySubtitle: String { loc("sessions.empty_subtitle") }
    static var sessionsJoinNow: String { loc("sessions.join_now") }
    /// Sessions tab title — single word per the new Figma.
    static var sessionsTitle: String { loc("sessions.title") }
    static var sessionsUpcomingHeader: String { loc("sessions.upcoming_header") }
    static var sessionsDurationMinFmt: String { loc("sessions.duration_min_fmt") }
    static var sessionsDurationHrFmt: String { loc("sessions.duration_hr_fmt") }
    static var sessionsDurationHrMinFmt: String { loc("sessions.duration_hr_min_fmt") }
    static var sessionsJoin: String { loc("sessions.join") }
    static var sessionsRemind: String { loc("sessions.remind") }
    static var sessionsRemindPermissionDenied: String { loc("sessions.remind_permission_denied") }
    static var sessionsRemindTooClose: String { loc("sessions.remind_too_close") }
    static var sessionsRemindGenericError: String { loc("sessions.remind_generic_error") }

    // MARK: - Messages feature
    static var messagesTitle: String { loc("messages.title") }
    static var messagesOnline: String { loc("messages.online") }
    static var messagesPlaceholder: String { loc("messages.placeholder") }

    // MARK: - Profile (extras for the Figma redesign)
    static var profileStudent: String { loc("profile.student_pill") }
    static var profileStreakDaysSuffix: String { loc("profile.streak_days_suffix") }
    static var profileAccountSection: String { loc("profile.account_section") }
    static var profileSecuritySection: String { loc("profile.security_section") }
    static var profileEditProfile: String { loc("profile.edit_profile") }
    static var profileEditSubtitle: String { loc("profile.edit_subtitle") }
    static var profileNotifications: String { loc("profile.notifications_row") }
    static var profileNotificationsSubtitle: String { loc("profile.notifications_subtitle") }
    static var profileInbox: String { loc("profile.inbox_row") }
    static var profileInboxAllCaught: String { loc("profile.inbox_all_caught") }
    static var profileInboxUnreadSuffix: String { loc("profile.inbox_unread_suffix") }
    static var profilePassword2FA: String { loc("profile.password_2fa_row") }
    static var profilePassword2FAEnabled: String { loc("profile.password_2fa_enabled") }
    static var profilePassword2FADisabled: String { loc("profile.password_2fa_disabled") }
    static var profileDevices: String { loc("profile.devices_row") }
    static var profileDevicesActiveSuffix: String { loc("profile.devices_active_suffix") }
    static var profileSignOut: String { loc("profile.sign_out") }
    static var profileSignOutConfirm: String { loc("profile.sign_out_confirm") }
    static var profileFooterVersion: String { loc("profile.footer_version") }

    // MARK: - Profile (Figma redesign — account fields + settings hub)
    static var profileEnrolledCoursesLabel: String { loc("profile.enrolled_courses_label") }
    static var profilePersonalInfoSection: String { loc("profile.personal_info_section") }
    static var profileUsernameRow: String { loc("profile.username_row") }
    static var profileContactSection: String { loc("profile.contact_section") }
    static var profileEmailRow: String { loc("profile.email_row") }
    static var profileSettingsSection: String { loc("profile.settings_section") }
    static var profileLearningSection: String { loc("profile.learning_section") }

    // MARK: - Edit Username / Email sheets
    static var editSave: String { loc("edit.save") }
    static var editUsernameTitle: String { loc("edit.username_title") }
    static var editUsernameSectionLabel: String { loc("edit.username_section_label") }
    static var editUsernamePlaceholder: String { loc("edit.username_placeholder") }
    static var editUsernameEmpty: String { loc("edit.username_empty") }
    static var editEmailTitle: String { loc("edit.email_title") }
    static var editEmailCurrentLabel: String { loc("edit.email_current_label") }
    static var editEmailCurrentRow: String { loc("edit.email_current_row") }
    static var editEmailNewLabel: String { loc("edit.email_new_label") }
    static var editEmailNewPlaceholder: String { loc("edit.email_new_placeholder") }
    static var editEmailHelper: String { loc("edit.email_helper") }
    /// "We sent a 6-digit code to %@" — %@ is the new address.
    static var editEmailCodeSentFmt: String { loc("edit.email_code_sent_fmt") }
    static var editEmailCodeLabel: String { loc("edit.email_code_label") }
    static var editEmailCodePlaceholder: String { loc("edit.email_code_placeholder") }
    static var editEmailVerify: String { loc("edit.email_verify") }

    // MARK: - Settings hub (1.4)
    static var settingsTitle: String { loc("settings.title") }
    static var settingsAccountSection: String { loc("settings.account_section") }
    static var settingsNotifications: String { loc("settings.notifications") }
    static var settingsSecurity: String { loc("settings.security") }
    static var settingsPayments: String { loc("settings.payments") }
    static var settingsLanguage: String { loc("settings.language") }
    static var settingsPreferencesSection: String { loc("settings.preferences_section") }
    static var settingsDarkMode: String { loc("settings.dark_mode") }
    static var settingsAutoplay: String { loc("settings.autoplay") }
    static var settingsSupportSection: String { loc("settings.support_section") }
    static var settingsHelpSupport: String { loc("settings.help_support") }

    // MARK: - Language screen (1.4.3)
    static var languageTitle: String { loc("language.title") }
    static var languageSectionLabel: String { loc("language.section_label") }
    static var languageEnglishOption: String { loc("language.english_option") }
    static var languageArabicOption: String { loc("language.arabic_option") }
    static var languageSubtitlesSection: String { loc("language.subtitles_section") }
    static var languageAutoShowSubtitles: String { loc("language.auto_show_subtitles") }
    static var languageAutoShowSubtitlesSubtitle: String { loc("language.auto_show_subtitles_subtitle") }
    static var languageSubtitleLanguage: String { loc("language.subtitle_language") }

    // MARK: - Help & Support (1.4.4)
    static var helpSupportTitle: String { loc("help.title") }
    static var helpContactUsSection: String { loc("help.contact_us_section") }
    static var helpEmailSupport: String { loc("help.email_support") }
    static var helpEmailSubject: String { loc("help.email_subject") }

    // MARK: - Stat tile labels
    static var statTileCourses: String { loc("profile.stat_courses") }
    static var statTileLessons: String { loc("profile.stat_lessons") }
    static var statTileCerts: String { loc("profile.stat_certs") }
    static var statTileAvg: String { loc("profile.stat_avg") }

    // MARK: - Security & Devices
    static var securityScreenTitle: String { loc("security.screen_title") }
    static var securityAccountSecured: String { loc("security.account_secured") }
    static var securitySecuredSubtitle: String { loc("security.secured_subtitle") }
    static var securityNotSecuredSubtitle: String { loc("security.not_secured_subtitle") }
    static var securityChangePassword: String { loc("security.change_password") }
    static var securityChangePasswordSave: String { loc("security.change_password_save") }
    static var securityCurrentPassword: String { loc("security.current_password") }
    static var securityNewPassword: String { loc("security.new_password") }
    static var securityConfirmPassword: String { loc("security.confirm_password") }
    static var securityPasswordTooShort: String { loc("security.password_too_short") }
    static var securityPasswordNeedsNumberOrSymbol: String { loc("security.password_needs_number_or_symbol") }
    static var securityPasswordsDontMatch: String { loc("security.passwords_dont_match") }
    static var securityPasswordReqLength: String { loc("security.password_req_length") }
    static var securityPasswordReqNumber: String { loc("security.password_req_number") }
    static var securityDangerZone: String { loc("security.danger_zone") }
    static var securityDeleteAccountRow: String { loc("security.delete_account_row") }
    static var securityDeleteAccountSubtitle: String { loc("security.delete_account_subtitle") }
    static var securityDeleteAccountTitle: String { loc("security.delete_account_title") }
    static var securityDeleteAccountWarning: String { loc("security.delete_account_warning") }
    static var securityDeleteAccountConfirm: String { loc("security.delete_account_confirm") }
    static var securityDeleteAccountAcknowledge: String { loc("security.delete_account_acknowledge") }
    static var securityLastChangedNever: String { loc("security.last_changed_never") }
    static var securityLastChangedPrefix: String { loc("security.last_changed_prefix") }
    static var securityTwoFactorRow: String { loc("security.two_factor_row") }
    static var securityTwoFactorEnabledVia: String { loc("security.two_factor_enabled_via") }
    static var securityTwoFactorDisabled: String { loc("security.two_factor_disabled") }
    static var securityActiveDevices: String { loc("security.active_devices") }
    static var securitySignOutAll: String { loc("security.sign_out_all") }
    static var securityCurrentDevice: String { loc("security.current_device") }
    static var securitySignOut: String { loc("security.sign_out") }
    static var securityDeviceLimitTitle: String { loc("security.device_limit_title") }
    static var securityDeviceLimitMessage: String { loc("security.device_limit_message") }

    // MARK: - 2FA enrolment / disable / recovery / challenge
    static var twoFactorEnableTitlePrefix: String { loc("twofactor.enable_title_prefix") }
    static var twoFactorEnableTitleAccent: String { loc("twofactor.enable_title_accent") }
    static var twoFactorEnableSubtitle: String { loc("twofactor.enable_subtitle") }
    static var twoFactorManualEntryHint: String { loc("twofactor.manual_entry_hint") }
    static var twoFactorCopy: String { loc("twofactor.copy") }
    static var twoFactorCopied: String { loc("twofactor.copied") }
    static var twoFactor6DigitLabel: String { loc("twofactor.six_digit_label") }
    static var twoFactorVerifyEnable: String { loc("twofactor.verify_enable") }
    static var twoFactorDisableTitlePrefix: String { loc("twofactor.disable_title_prefix") }
    static var twoFactorDisableTitleAccent: String { loc("twofactor.disable_title_accent") }
    static var twoFactorDisableSubtitle: String { loc("twofactor.disable_subtitle") }
    static var twoFactorDisableButton: String { loc("twofactor.disable_button") }
    static var twoFactorRecoveryTitle: String { loc("twofactor.recovery_title") }
    static var twoFactorRecoveryAccent: String { loc("twofactor.recovery_accent") }
    static var twoFactorRecoverySubtitle: String { loc("twofactor.recovery_subtitle") }
    static var twoFactorRecoveryWarning: String { loc("twofactor.recovery_warning") }
    static var twoFactorCopyAll: String { loc("twofactor.copy_all") }
    static var twoFactorCopiedAll: String { loc("twofactor.copied_all") }
    static var twoFactorShare: String { loc("twofactor.share") }
    static var twoFactorChallengePrefix: String { loc("twofactor.challenge_prefix") }
    static var twoFactorChallengeAccent: String { loc("twofactor.challenge_accent") }
    static var twoFactorChallengeAuthHint: String { loc("twofactor.challenge_auth_hint") }
    static var twoFactorChallengeRecoveryHint: String { loc("twofactor.challenge_recovery_hint") }
    static var twoFactorVerifySignIn: String { loc("twofactor.verify_sign_in") }
    static var twoFactorUseRecovery: String { loc("twofactor.use_recovery") }
    static var twoFactorUseAuthenticator: String { loc("twofactor.use_authenticator") }

    // MARK: - Notification preferences screen
    static var notificationsScreenTitle: String { loc("notifications.screen_title") }
    static var notificationsSectionLearning: String { loc("notifications.section_learning") }
    static var notificationsSectionSessions: String { loc("notifications.section_sessions") }
    static var notificationsSectionMarketing: String { loc("notifications.section_marketing") }
    static var notifLessonReminders: String { loc("notifications.lesson_reminders") }
    static var notifLessonRemindersSubtitle: String { loc("notifications.lesson_reminders_subtitle") }
    static var notifStreakAlerts: String { loc("notifications.streak_alerts") }
    static var notifStreakAlertsSubtitle: String { loc("notifications.streak_alerts_subtitle") }
    static var notifCourseUpdates: String { loc("notifications.course_updates") }
    static var notifCourseUpdatesSubtitle: String { loc("notifications.course_updates_subtitle") }
    static var notifQuizResults: String { loc("notifications.quiz_results") }
    static var notifQuizResultsSubtitle: String { loc("notifications.quiz_results_subtitle") }
    static var notifLiveSession: String { loc("notifications.live_session") }
    static var notifLiveSessionSubtitle: String { loc("notifications.live_session_subtitle") }
    static var notifNewMessages: String { loc("notifications.new_messages") }
    static var notifNewMessagesSubtitle: String { loc("notifications.new_messages_subtitle") }
    static var notifNewCourse: String { loc("notifications.new_course") }
    static var notifPromotions: String { loc("notifications.promotions") }

    // MARK: - Inbox
    static var inboxTitle: String { loc("inbox.title") }
    static var inboxMarkAllRead: String { loc("inbox.mark_all_read") }
    static var inboxEmptyTitle: String { loc("inbox.empty_title") }
    static var inboxEmptySubtitle: String { loc("inbox.empty_subtitle") }
    static var inboxKindLessonReminderTitle: String { loc("inbox.kind_lesson_reminder_title") }
    static var inboxKindStreakTitle: String { loc("inbox.kind_streak_title") }
    static var inboxKindQuizResultTitle: String { loc("inbox.kind_quiz_result_title") }
    static var inboxKindLiveSessionTitle: String { loc("inbox.kind_live_session_title") }
    static var inboxKindNewMessageTitle: String { loc("inbox.kind_new_message_title") }
    static var inboxKindNewCourseTitle: String { loc("inbox.kind_new_course_title") }
    static var inboxKindPromotionTitle: String { loc("inbox.kind_promotion_title") }
    static var inboxKindUnknownTitle: String { loc("inbox.kind_unknown_title") }
    static var inboxKindNewLessonTitle: String { loc("inbox.kind_new_lesson_title") }
    static var inboxKindCourseUpdatedTitle: String { loc("inbox.kind_course_updated_title") }
    static var inboxKindRevisionTitle: String { loc("inbox.kind_revision_title") }
    static var inboxKindEnrollmentApprovedTitle: String { loc("inbox.kind_enrollment_approved_title") }
    static var inboxKindNewQuizTitle: String { loc("inbox.kind_new_quiz_title") }
    static var inboxKindSessionStartingTitle: String { loc("inbox.kind_session_starting_title") }
    static var inboxKindSessionScheduledTitle: String { loc("inbox.kind_session_scheduled_title") }
    static var inboxKindSessionCancelledTitle: String { loc("inbox.kind_session_cancelled_title") }
    static var inboxKindSessionRescheduledTitle: String { loc("inbox.kind_session_rescheduled_title") }
    static var inboxKindInstructorReplyTitle: String { loc("inbox.kind_instructor_reply_title") }
    static var inboxKindAnnouncementTitle: String { loc("inbox.kind_announcement_title") }
    static var inboxAnnouncementFromFmt: String { loc("inbox.announcement_from_fmt") }
    static var inboxKindStudyRoomMessageTitle: String { loc("inbox.kind_study_room_message_title") }
    static var inboxKindStudyRoomJoinedTitle: String { loc("inbox.kind_study_room_joined_title") }
    static var inboxKindStudyRoomEndedTitle: String { loc("inbox.kind_study_room_ended_title") }
    static var inboxKindStudyRoomWaitlistRequestTitle: String { loc("inbox.kind_study_room_waitlist_request_title") }
    static var inboxKindStudyRoomWaitlistApprovedTitle: String { loc("inbox.kind_study_room_waitlist_approved_title") }
    static var inboxKindStudyRoomWaitlistRejectedTitle: String { loc("inbox.kind_study_room_waitlist_rejected_title") }
    static var inboxKindStudyRoomRemovedTitle: String { loc("inbox.kind_study_room_removed_title") }
    static var inboxKindStudyRoomPromotedTitle: String { loc("inbox.kind_study_room_promoted_title") }
    static var inboxKindStudyRoomBecameHostTitle: String { loc("inbox.kind_study_room_became_host_title") }
    // Tabs
    static var inboxTabAll: String { loc("inbox.tab_all") }
    static var inboxTabUnread: String { loc("inbox.tab_unread") }
    static var inboxTabMessages: String { loc("inbox.tab_messages") }
    static var inboxTabCourses: String { loc("inbox.tab_courses") }
    static var inboxTabSessions: String { loc("inbox.tab_sessions") }
    static var inboxTabQuizzes: String { loc("inbox.tab_quizzes") }
    static var inboxTabStudyRooms: String { loc("inbox.tab_study_rooms") }
    // Inline actions
    static var inboxActionJoin: String { loc("inbox.action_join") }
    // Caught-up / filtered empty states + swipe delete
    static var inboxCaughtUpTitle: String { loc("inbox.caught_up_title") }
    static var inboxCaughtUpSubtitle: String { loc("inbox.caught_up_subtitle") }
    static var inboxFilterEmptyTitle: String { loc("inbox.filter_empty_title") }
    static var inboxDelete: String { loc("inbox.delete") }
    static var inboxClearAll: String { loc("inbox.clear_all") }

    // MARK: - OTP code entry (post-register / post-login-unverified / reset)
    static var otpBack: String { loc("otp.back") }
    static var otpTitle: String { loc("otp.title") }
    /// "We sent a 6-digit code to %@" — printf-style email substitution.
    static var otpSubtitleFmt: String { loc("otp.subtitle_fmt") }
    static var otpVerify: String { loc("otp.verify") }
    static var otpVerifying: String { loc("otp.verifying") }
    static var otpDidntReceive: String { loc("otp.didnt_receive") }
    static var otpResendCode: String { loc("otp.resend_code") }
    /// "Resend Code · %@" where %@ is the M:SS countdown.
    static var otpResendCooldownFmt: String { loc("otp.resend_cooldown_fmt") }
    static var otpResendingBanner: String { loc("otp.resending_banner") }
    /// Shown on the OTP screen when a passwordless-login user has 2FA enabled
    /// — we don't have a TOTP push from the verify screen yet, so we ask
    /// them to fall back to password login.
    static var otpTotpRequiredFallback: String { loc("otp.totp_required_fallback") }

    // MARK: - Email-OTP (passwordless) sign in / sign up
    /// Unused since 2026-07 — the "sign in with email code" button was removed
    /// from the login screen. Kept (with its strings) so the wording is still
    /// there if the entry point ever comes back.
    static var emailOtpLoginCta: String { loc("email_otp.login_cta") }
    /// CTA on the REGISTER screen that switches to email-code sign-up.
    static var emailOtpRegisterCta: String { loc("email_otp.register_cta") }
    static var emailOtpLoginEmailTitle: String { loc("email_otp.login_email_title") }
    static var emailOtpLoginEmailSubtitle: String { loc("email_otp.login_email_subtitle") }
    static var emailOtpSendCode: String { loc("email_otp.send_code") }
    static var emailOtpSending: String { loc("email_otp.sending") }
    static var emailOtpRegisterEmailTitle: String { loc("email_otp.register_email_title") }
    static var emailOtpRegisterEmailSubtitle: String { loc("email_otp.register_email_subtitle") }
    static var emailOtpUsePasswordInstead: String { loc("email_otp.use_password_instead") }

    // MARK: - Display name prompt (new passwordless registrations)
    static var displayNameTitle: String { loc("display_name.title") }
    static var displayNameSubtitle: String { loc("display_name.subtitle") }
    static var displayNameLabel: String { loc("display_name.label") }
    static var displayNamePlaceholder: String { loc("display_name.placeholder") }
    static var displayNameContinue: String { loc("display_name.continue") }
    static var displayNameContinuing: String { loc("display_name.continuing") }

    // MARK: - Login screen (Figma redesign)
    static var loginTitle: String { loc("login.title") }
    static var loginSubtitle: String { loc("login.subtitle") }
    static var loginEmailLabel: String { loc("login.email_label") }
    static var loginEmailPlaceholder: String { loc("login.email_placeholder") }
    static var loginPasswordLabel: String { loc("login.password_label") }
    static var loginPasswordPlaceholder: String { loc("login.password_placeholder") }
    static var loginForgot: String { loc("login.forgot") }
    static var loginShow: String { loc("login.show") }
    static var loginHide: String { loc("login.hide") }
    static var loginKeepSignedIn: String { loc("login.keep_signed_in") }
    static var loginSignIn: String { loc("login.sign_in") }
    static var loginSigningIn: String { loc("login.signing_in") }
    static var loginTryAgain: String { loc("login.try_again") }
    static var loginResetPassword: String { loc("login.reset_password") }
    /// Tiny "or" centered between rules.
    static var loginOr: String { loc("login.or") }
    static var loginSocialGoogle: String { loc("login.social_google") }
    static var loginSocialApple: String { loc("login.social_apple") }
    static var loginNoAccountPrefix: String { loc("login.no_account_prefix") }
    static var loginSignUpLink: String { loc("login.sign_up_link") }
    static var loginErrIncorrect: String { loc("login.err_incorrect") }
    /// Banner copy for a rejected-credentials login attempt (Figma error state):
    /// "Wrong email or password. Try again, or reset your password."
    static var loginErrWrongCredentials: String { loc("login.err_wrong_credentials") }
    static var loginErrAttemptsFmt: String { loc("login.err_attempts_fmt") }
    static var loginErrMissingFields: String { loc("login.err_missing_fields") }
    static var loginErrVerifyEmail: String { loc("login.err_verify_email") }
    static var loginErrVerifyPassword: String { loc("login.err_verify_password") }
    static var loginErrCaptchaDismissed: String { loc("login.err_captcha_dismissed") }
    /// Shown when the account is pinned to a different device. Only an admin
    /// can move it, so the copy points at support rather than offering a retry.
    static var loginErrDeviceNotAuthorized: String { loc("login.err_device_not_authorized") }

    // MARK: - Networking errors
    //
    // `DroobError.localizedArabicDescription` reads these for the classes of
    // failure the server sends no `message_ar` for (transport, decode, 409,
    // 5xx). They exist in `en.lproj` too, so nothing renders a raw key if the
    // English branch is ever pointed at them.
    static var errNetwork: String { loc("err.network") }
    static var errRequestFailed: String { loc("err.request_failed") }
    static var errBadResponse: String { loc("err.bad_response") }
    static var errInvalidURL: String { loc("err.invalid_url") }
    static var errLoginAgain: String { loc("err.login_again") }
    static var errAccessDenied: String { loc("err.access_denied") }
    static var errNotFound: String { loc("err.not_found") }
    static var errConflict: String { loc("err.conflict") }
    static var errServer: String { loc("err.server") }
    static var errUnknown: String { loc("err.unknown") }
    // Face ID / Touch ID login.
    static var loginBiometricFaceID: String { loc("login.biometric_face_id") }
    static var loginBiometricTouchID: String { loc("login.biometric_touch_id") }
    static var loginBiometricReason: String { loc("login.biometric_reason") }
    // Security screen toggle.
    static var securityBiometricRow: String { loc("security.biometric_row") }
    static var securityBiometricEnabled: String { loc("security.biometric_enabled") }
    static var securityBiometricDisabled: String { loc("security.biometric_disabled") }
    static var securityBiometricEnrollReason: String { loc("security.biometric_enroll_reason") }

    // MARK: - Register screen (Figma redesign)
    static var registerBack: String { loc("register.back") }
    static var registerTitle: String { loc("register.title") }
    static var registerSubtitle: String { loc("register.subtitle") }
    static var registerSectionInfo: String { loc("register.section_info") }
    static var registerFirstName: String { loc("register.first_name") }
    static var registerLastName: String { loc("register.last_name") }
    static var registerEmail: String { loc("register.email") }
    static var registerPassword: String { loc("register.password") }
    static var registerPasswordPlaceholder: String { loc("register.password_placeholder") }
    static var registerPasswordHint: String { loc("register.password_hint") }
    static var registerCreateAccount: String { loc("register.create_account") }
    static var registerCreatingAccount: String { loc("register.creating_account") }
    static var registerTermsPrefix: String { loc("register.terms_prefix") }
    static var registerTermsOfService: String { loc("register.terms_of_service") }
    static var registerTermsAnd: String { loc("register.terms_and") }
    static var registerPrivacyPolicy: String { loc("register.privacy_policy") }
    static var registerTermsSuffix: String { loc("register.terms_suffix") }

    // MARK: - Legal screens (Terms of Service, Privacy Policy)
    static var legalTermsTitle: String { loc("legal.terms_title") }
    static var legalTermsUpdated: String { loc("legal.terms_updated") }
    static var legalPrivacyTitle: String { loc("legal.privacy_title") }
    static var legalPrivacyUpdated: String { loc("legal.privacy_updated") }

    // MARK: - Forgot Password (Figma redesign — single-step → OTP)
    static var forgotBack: String { loc("forgot.back") }
    static var forgotTitle: String { loc("forgot.title_line1") }
    static var forgotDescription: String { loc("forgot.description") }
    static var forgotEmailSection: String { loc("forgot.email_section") }
    static var forgotEmailLabel: String { loc("forgot.email_label") }
    static var forgotEmailPlaceholder: String { loc("forgot.email_placeholder") }
    static var forgotHint: String { loc("forgot.hint") }
    static var forgotSendButton: String { loc("forgot.send_button") }
    static var forgotSending: String { loc("forgot.sending") }
    static var forgotErrorEmpty: String { loc("forgot.error_empty") }
    static var forgotSentNeutral: String { loc("forgot.sent_neutral") }
    static var forgotHaveCode: String { loc("forgot.have_code") }

    // MARK: - Splash & Onboarding
    static var brandName: String { loc("brand.name") }
    static var splashTagline: String { loc("splash.tagline") }
    // Slide 1 — Learn at your own pace
    static var onbSlide1Title: String { loc("onboarding.slide1_title") }
    static var onbSlide1Description: String { loc("onboarding.slide1_description") }
    static var onbSlide1CTA: String { loc("onboarding.slide1_cta") }
    // Slide 2 — Track your real progress
    static var onbSlide2Title: String { loc("onboarding.slide2_title") }
    static var onbSlide2Description: String { loc("onboarding.slide2_description") }
    static var onbSlide2CTA: String { loc("onboarding.slide2_cta") }
    // Slide 3 — Join live sessions & office hours
    static var onbSlide3Title: String { loc("onboarding.slide3_title") }
    static var onbSlide3Description: String { loc("onboarding.slide3_description") }
    static var onbSlide3CTA: String { loc("onboarding.slide3_cta") }
    // Illustration card copy (mocked for onboarding, not localised data)
    static var onbMyCoursesTitle: String { loc("onboarding.my_courses_title") }
    static var onbMyCoursesSubtitle: String { loc("onboarding.my_courses_subtitle") }
    // The three sample course rows on slide 1. Localised like the rest of the
    // card — they were English literals while every other word on the slide was
    // Arabic, which is exactly where the eye lands first.
    static var onbSampleCourse1: String { loc("onboarding.sample_course_1") }
    static var onbSampleCourse2: String { loc("onboarding.sample_course_2") }
    static var onbSampleCourse3: String { loc("onboarding.sample_course_3") }

    // Shown instead of the app when it is launched on a Mac.
    static var macUnsupportedTitle: String { loc("mac_unsupported.title") }
    static var macUnsupportedBody: String { loc("mac_unsupported.body") }
    static var onbStreakLabel: String { loc("onboarding.streak_label") }
    static var onbStreakSubtitle: String { loc("onboarding.streak_subtitle") }
    static var onbProgressThisCourse: String { loc("onboarding.progress_this_course") }
    static var onbStatsStreak: String { loc("onboarding.stats_streak") }
    static var onbStatsWatchTime: String { loc("onboarding.stats_watch_time") }
    static var onbStatsQuizAvg: String { loc("onboarding.stats_quiz_avg") }
    static var onbInstructorRole: String { loc("onboarding.instructor_role") }
    static var onbBadgeLive: String { loc("onboarding.badge_live") }
    static var onbSessionViewers: String { loc("onboarding.session_viewers") }
    static var onbSessionDuration: String { loc("onboarding.session_duration") }
    static var onbSessionStartedAgo: String { loc("onboarding.session_started_ago") }
    static var onbJoinButton: String { loc("onboarding.join_button") }
    static var onbOfficeHoursTitle: String { loc("onboarding.office_hours_title") }
    static var onbOfficeHoursTime: String { loc("onboarding.office_hours_time") }
    static var onbBookButton: String { loc("onboarding.book_button") }

    // MARK: - General
    static var loading: String { loc("general.loading") }
    static var error: String { loc("general.error") }
    static var retry: String { loc("general.retry") }
    static var ok: String { loc("general.ok") }
    static var empty: String { loc("general.empty") }
    static var done: String { loc("general.done") }
    static var save: String { loc("general.save") }
    static var back: String { loc("general.back") }

    // MARK: - Study Rooms
    static var studyTogetherTitle: String { loc("study_rooms.together_title") }
    static var studyTogetherSubtitle: String { loc("study_rooms.together_subtitle") }
    static var studyTogetherRoomsLive: String { loc("study_rooms.rooms_live_fmt") }
    static var studyTogetherOneRoomLive: String { loc("study_rooms.one_room_live") }
    static var studyRoomsListTitle: String { loc("study_rooms.list_title") }
    static var studyRoomsEmptyTitle: String { loc("study_rooms.empty_title") }
    static var studyRoomsEmptySubtitle: String { loc("study_rooms.empty_subtitle") }
    static var studyRoomsCreateCta: String { loc("study_rooms.create_cta") }
    static var studyRoomsJoinByCodeCta: String { loc("study_rooms.join_by_code_cta") }
    static var studyRoomsParticipantsFmt: String { loc("study_rooms.participants_fmt") }
    // Create / Join entry screen
    static var studyRoomsCreateTab: String { loc("study_rooms.create_tab") }
    static var studyRoomsJoinTab: String { loc("study_rooms.join_tab") }
    static var studyRoomsCoverLabel: String { loc("study_rooms.cover_label") }
    static var studyRoomsRoomNameLabel: String { loc("study_rooms.room_name_label") }
    static var studyRoomsRoomNamePlaceholder: String { loc("study_rooms.room_name_placeholder") }
    static var studyRoomsWhatStudyLabel: String { loc("study_rooms.what_study_label") }
    static var studyRoomsWhatStudyPlaceholder: String { loc("study_rooms.what_study_placeholder") }
    static var studyRoomsPrivacyLabel: String { loc("study_rooms.privacy_label") }
    static var studyRoomsPrivacyPublic: String { loc("study_rooms.privacy_public") }
    static var studyRoomsPrivacyPrivate: String { loc("study_rooms.privacy_private") }
    static var studyRoomsPrivacyHelpPublic: String { loc("study_rooms.privacy_help_public") }
    static var studyRoomsPrivacyHelpPrivate: String { loc("study_rooms.privacy_help_private") }
    static var studyRoomsCreateButton: String { loc("study_rooms.create_button") }
    static var studyRoomsCodeFieldLabel: String { loc("study_rooms.code_field_label") }
    static var studyRoomsCodeFieldHelper: String { loc("study_rooms.code_field_helper") }
    static var studyRoomsCodeFieldPlaceholder: String { loc("study_rooms.code_field_placeholder") }
    static var studyRoomsPrivateBannerTitle: String { loc("study_rooms.private_banner_title") }
    static var studyRoomsPrivateBannerSubtitle: String { loc("study_rooms.private_banner_subtitle") }
    static var studyRoomsRoomCodeChip: String { loc("study_rooms.room_code_chip") }
    static var studyRoomsInviteAction: String { loc("study_rooms.invite_action") }
    static var studyRoomsRoomMembersFmt: String { loc("study_rooms.room_members_fmt") }
    static var studyRoomsRoomOneMember: String { loc("study_rooms.room_one_member") }
    static var studyRoomsToday: String { loc("study_rooms.today") }
    static var studyRoomsYesterday: String { loc("study_rooms.yesterday") }
    static var studyRoomsJoinedSuffix: String { loc("study_rooms.joined_suffix") }
    /// Suffix word for the SYSTEM_MEMBER_LEFT pill. Mirrors
    /// {@link studyRoomsJoinedSuffix} — the existing
    /// `studyRoomsMemberLeftFmt` is the longer "X left the room"
    /// system line, which doesn't fit the WhatsApp-style compact
    /// pill we now render in chat history.
    static var studyRoomsLeftSuffix: String { loc("study_rooms.left_suffix") }
    /// Suffix for the SYSTEM_HOST_CHANGED pill rendered after a
    /// dedicated host-promotion flow (no leaver). Reused by the
    /// non-new-host viewer half of HOST_TRANSFERRED — "...Y is now
    /// the host".
    static var studyRoomsIsNowHostSuffix: String { loc("study_rooms.is_now_host_suffix") }
    /// "You" pronoun used in the actor-is-me variant of system
    /// pills (e.g. "You joined" / "You left"). Pulled out so the
    /// English / Arabic copy can diverge from the longer
    /// "you are now the host" line in the combined transfer pill.
    static var studyRoomsSystemActorYou: String { loc("study_rooms.system_actor_you") }
    /// Non-new-host viewer's combined HOST_TRANSFERRED pill —
    /// "{prev} left · {new} is now the host". Counterpart to
    /// `studyRoomsCombinedLeftAndHostFmt`, which is the new
    /// host's "you are now" variant.
    static var studyRoomsCombinedLeftAndOtherHostFmt: String {
        loc("study_rooms.combined_left_and_other_host_fmt")
    }
    /// Neutral fallback rendered in system pills when the server
    /// payload is missing a subject display name (e.g. the user was
    /// purged between row creation and the page fetch). "The host"
    /// in English, equivalent in Arabic.
    static var studyRoomsHostFallback: String { loc("study_rooms.host_fallback") }
    // Join tab — code input + paste + list metadata
    static var studyRoomsEnterCodeTitle: String { loc("study_rooms.enter_code_title") }
    static var studyRoomsPasteCode: String { loc("study_rooms.paste_code") }
    static var studyRoomsOrJoinPublic: String { loc("study_rooms.or_join_public") }
    static var studyRoomsSearchPlaceholder: String { loc("study_rooms.search_placeholder") }
    static var studyRoomsRoomsHeaderFmt: String { loc("study_rooms.rooms_header_fmt") }
    static var studyRoomsRoomsHeaderOne: String { loc("study_rooms.rooms_header_one") }
    static var studyRoomsHostedByFmt: String { loc("study_rooms.hosted_by_fmt") }
    static var studyRoomsJoinAction: String { loc("study_rooms.join_action") }
    /// Action shown on a public-rooms row the user has already joined —
    /// opens the room instead of (re-)joining it.
    static var studyRoomsOpenAction: String { loc("study_rooms.open_action") }
    static var studyRoomsNoRoomsTitle: String { loc("study_rooms.no_rooms_title") }
    static var studyRoomsNoRoomsSubtitle: String { loc("study_rooms.no_rooms_subtitle") }
    static var studyRoomsNoMatchTitle: String { loc("study_rooms.no_match_title") }
    static var studyRoomsNoMatchSubtitleFmt: String { loc("study_rooms.no_match_subtitle_fmt") }
    static var studyRoomsCreateInsteadFmt: String { loc("study_rooms.create_instead_fmt") }
    // Joining loading screen
    static var studyRoomsJoiningTitle: String { loc("study_rooms.joining_title") }
    static var studyRoomsCancel: String { loc("study_rooms.cancel") }
    // Relative time helpers
    static var studyRoomsAgoNow: String { loc("study_rooms.ago_now") }
    static var studyRoomsAgoMinFmt: String { loc("study_rooms.ago_min_fmt") }
    static var studyRoomsAgoHourFmt: String { loc("study_rooms.ago_hour_fmt") }
    static var studyRoomsAgoDayFmt: String { loc("study_rooms.ago_day_fmt") }
    // Settings + all-members + waitlist + documents
    static var studyRoomsSettingsTitle: String { loc("study_rooms.settings_title") }
    static var studyRoomsDone: String { loc("study_rooms.done") }
    static var studyRoomsSubtitleCreatedYou: String { loc("study_rooms.subtitle_created_you") }
    static var studyRoomsSubtitleCreatedByFmt: String { loc("study_rooms.subtitle_created_by_fmt") }
    static var studyRoomsMembersSection: String { loc("study_rooms.members_section") }
    static var studyRoomsViewAllMembers: String { loc("study_rooms.view_all_members") }
    static var studyRoomsViewWaitlist: String { loc("study_rooms.view_waitlist") }
    static var studyRoomsInviteToRoom: String { loc("study_rooms.invite_to_room") }
    static var studyRoomsGeneralSection: String { loc("study_rooms.general_section") }
    static var studyRoomsSharedContent: String { loc("study_rooms.shared_content") }
    static var studyRoomsDocumentsAndFiles: String { loc("study_rooms.documents_and_files") }
    static var studyRoomsLeaveRoom: String { loc("study_rooms.leave_room") }
    static var studyRoomsAllMembersTitle: String { loc("study_rooms.all_members_title") }
    static var studyRoomsHostSection: String { loc("study_rooms.host_section") }
    static var studyRoomsHostYou: String { loc("study_rooms.host_you") }
    static var studyRoomsHostCreatedRoom: String { loc("study_rooms.host_created_room") }
    /// Title-case role label shown under a co-host's name in the
    /// members list. Distinct from:
    ///   * `studyRoomsCoHostBadge` ("CO-HOST") — the uppercase pill
    ///     badge used in selection rows (e.g. pass-host picker).
    ///   * `studyRoomsMakeCoHost` ("Make co-host") — the *action*
    ///     menu item that promotes a member. Earlier code reused the
    ///     action copy here, which made the role label read "Make
    ///     co-host" under the member's name — wrong tense and
    ///     wrong intent.
    static var studyRoomsCoHostRoleLabel: String { loc("study_rooms.co_host_role_label") }
    static var studyRoomsMembersHeaderFmt: String { loc("study_rooms.members_header_fmt") }
    static var studyRoomsActionsForFmt: String { loc("study_rooms.actions_for_fmt") }
    static var studyRoomsMakeCoHost: String { loc("study_rooms.make_co_host") }
    static var studyRoomsDemoteCoHost: String { loc("study_rooms.demote_co_host") }
    static var studyRoomsRemoveFromRoom: String { loc("study_rooms.remove_from_room") }
    static var studyRoomsActionCancel: String { loc("study_rooms.action_cancel") }
    static var studyRoomsWaitlistTitle: String { loc("study_rooms.waitlist_title") }
    static var studyRoomsWaitlistHostView: String { loc("study_rooms.waitlist_host_view") }
    static var studyRoomsWaitingPeopleFmt: String { loc("study_rooms.waiting_people_fmt") }
    static var studyRoomsApproveAll: String { loc("study_rooms.approve_all") }
    static var studyRoomsJustArrived: String { loc("study_rooms.just_arrived") }
    static var studyRoomsMinWaitFmt: String { loc("study_rooms.min_wait_fmt") }
    static var studyRoomsHrWaitFmt: String { loc("study_rooms.hr_wait_fmt") }
    static var studyRoomsWaitlistEmpty: String { loc("study_rooms.waitlist_empty") }
    static var studyRoomsDocumentsTitle: String { loc("study_rooms.documents_title") }
    /// Placeholder for the search bar on the Documents and Files screen
    /// inside a study room. Distinct from `studyRoomsSearchPlaceholder`
    /// ("Search rooms"), which is the rooms-list copy and was being
    /// reused here by mistake — the student is inside one room
    /// filtering its files, not looking for other rooms.
    static var studyRoomsDocumentsSearchPlaceholder: String { loc("study_rooms.documents_search_placeholder") }
    static var studyRoomsDocumentsCountFmt: String { loc("study_rooms.documents_count_fmt") }
    static var studyRoomsDocumentsOneFmt: String { loc("study_rooms.documents_one_fmt") }
    static var studyRoomsDocumentsFoundFmt: String { loc("study_rooms.documents_found_fmt") }
    static var studyRoomsDocumentsNoResultsTitle: String { loc("study_rooms.documents_no_results_title") }
    static var studyRoomsDocumentsNoResultsSubtitleFmt: String { loc("study_rooms.documents_no_results_subtitle_fmt") }
    static var studyRoomsDocumentsFilter: String { loc("study_rooms.documents_filter") }
    static var studyRoomsDocumentsEmpty: String { loc("study_rooms.documents_empty") }
    static var studyRoomsUploaderYou: String { loc("study_rooms.uploader_you") }
    // Pending join landing
    static var studyRoomsPendingTitle: String { loc("study_rooms.pending_title") }
    static var studyRoomsPendingSubtitleFmt: String { loc("study_rooms.pending_subtitle_fmt") }
    static var studyRoomsPendingNotifyMe: String { loc("study_rooms.pending_notify_me") }
    static var studyRoomsPendingBack: String { loc("study_rooms.pending_back") }
    // Leave-room sheets + pass-host picker + host badges + new-host banner
    static var studyRoomsLeaveSheetTitle: String { loc("study_rooms.leave_sheet_title") }
    static var studyRoomsLeaveSheetSubtitleMember: String { loc("study_rooms.leave_sheet_subtitle_member") }
    static var studyRoomsLeaveSheetSubtitleHostFmt: String { loc("study_rooms.leave_sheet_subtitle_host_fmt") }
    static var studyRoomsPassHostAndLeave: String { loc("study_rooms.pass_host_and_leave") }
    static var studyRoomsPassHostSubtitleFmt: String { loc("study_rooms.pass_host_subtitle_fmt") }
    static var studyRoomsPassHostSubtitleAuto: String { loc("study_rooms.pass_host_subtitle_auto") }
    static var studyRoomsJustLeave: String { loc("study_rooms.just_leave") }
    static var studyRoomsJustLeaveSubtitle: String { loc("study_rooms.just_leave_subtitle") }
    static var studyRoomsJustLeaveSubtitleNoCoHost: String { loc("study_rooms.just_leave_subtitle_no_co_host") }
    static var studyRoomsStayInRoom: String { loc("study_rooms.stay_in_room") }
    static var studyRoomsLeaveConfirmTitle: String { loc("study_rooms.leave_confirm_title") }
    static var studyRoomsLeaveConfirmDetail: String { loc("study_rooms.leave_confirm_detail") }
    static var studyRoomsLeaveNowCta: String { loc("study_rooms.leave_now_cta") }
    static var studyRoomsPassHostTitle: String { loc("study_rooms.pass_host_title") }
    static var studyRoomsPassHostBannerFmt: String { loc("study_rooms.pass_host_banner_fmt") }
    static var studyRoomsPassHostSectionLabel: String { loc("study_rooms.pass_host_section_label") }
    static var studyRoomsCoHostBadge: String { loc("study_rooms.co_host_badge") }
    static var studyRoomsMakeHostAndLeaveFmt: String { loc("study_rooms.make_host_and_leave_fmt") }
    static var studyRoomsYoureHostBadge: String { loc("study_rooms.youre_host_badge") }
    static var studyRoomsHostRoleBadge: String { loc("study_rooms.host_role_badge") }
    /// Gold badge next to the instructor's name in instructor-created
    /// rooms (2026-07 anonymized rooms).
    static var studyRoomsInstructorRoleBadge: String { loc("study_rooms.instructor_role_badge") }
    /// Localized alias for anonymized peers — "Student %d" — used in
    /// place of the wire `sender_name` when `sender_anon_index` is set.
    static var studyRoomsAnonStudentFmt: String { loc("study_rooms.anon_student_fmt") }
    static var studyRoomsBecameHostBannerTitle: String { loc("study_rooms.became_host_banner_title") }
    static var studyRoomsBecameHostBannerFmt: String { loc("study_rooms.became_host_banner_fmt") }
    static var studyRoomsCombinedLeftAndHostFmt: String { loc("study_rooms.combined_left_and_host_fmt") }
    // Documents empty state
    static var studyRoomsDocumentsEmptyTitle: String { loc("study_rooms.documents_empty_title") }
    static var studyRoomsDocumentsEmptySubtitle: String { loc("study_rooms.documents_empty_subtitle") }
    static var studyRoomsDocumentsEmptyCta: String { loc("study_rooms.documents_empty_cta") }
    /// Read-only empty-state copy for a CLOSED room's documents list —
    /// no upload CTA, since files can't be added to an ended room.
    static var studyRoomsDocumentsEmptyClosedTitle: String { loc("study_rooms.documents_empty_closed_title") }
    static var studyRoomsDocumentsEmptyClosedSubtitle: String { loc("study_rooms.documents_empty_closed_subtitle") }
    static var studyRoomsJoinByCodeBtn: String { loc("study_rooms.join_by_code_btn") }
    static var studyRoomsBrowsePublic: String { loc("study_rooms.browse_public") }
    // Success screen
    static var studyRoomsReadyTitlePrefix: String { loc("study_rooms.ready_title_prefix") }
    static var studyRoomsReadyTitleSuffix: String { loc("study_rooms.ready_title_suffix") }
    static var studyRoomsReadySubtitlePublicFmt: String { loc("study_rooms.ready_subtitle_public_fmt") }
    static var studyRoomsReadySubtitlePrivateFmt: String { loc("study_rooms.ready_subtitle_private_fmt") }
    static var studyRoomsEnterRoom: String { loc("study_rooms.enter_room") }
    static var studyRoomsShare: String { loc("study_rooms.share") }
    // Invite sheet
    static var studyRoomsInviteSheetTitle: String { loc("study_rooms.invite_sheet_title") }
    static var studyRoomsInviteRoomLinkLabel: String { loc("study_rooms.invite_room_link_label") }
    static var studyRoomsInviteCopy: String { loc("study_rooms.invite_copy") }
    static var studyRoomsInviteCopied: String { loc("study_rooms.invite_copied") }
    static var studyRoomsInviteCodeLabel: String { loc("study_rooms.invite_code_label") }
    // In-room chat
    static var studyRoomsHeaderJustYou: String { loc("study_rooms.header_just_you") }
    static var studyRoomsHeaderStudyingFmt: String { loc("study_rooms.header_studying_fmt") }
    static var studyRoomsPinnedPrefix: String { loc("study_rooms.pinned_prefix") }
    static var studyRoomsEmptyAlone: String { loc("study_rooms.empty_alone") }
    static var studyRoomsEmptyAloneSubtitle: String { loc("study_rooms.empty_alone_subtitle") }
    /// Empty-state title shown when the room has other members but
    /// no messages yet. Counterpart to `studyRoomsEmptyAlone` ("The
    /// room is all yours") — using that copy with multiple members
    /// present misled users into thinking they were alone.
    static var studyRoomsEmptyWithOthersTitle: String { loc("study_rooms.empty_with_others_title") }
    static var studyRoomsEmptyWithOthersSubtitle: String { loc("study_rooms.empty_with_others_subtitle") }
    /// Empty-state copy for a CLOSED room with no messages. The live
    /// empty states ("all yours" / "no messages yet") all carry invite
    /// prompts, which are nonsense for an ended room you can't invite
    /// anyone to — so closed rooms get their own read-only copy.
    static var studyRoomsEmptyEndedTitle: String { loc("study_rooms.empty_ended_title") }
    static var studyRoomsEmptyEndedSubtitle: String { loc("study_rooms.empty_ended_subtitle") }
    static var studyRoomsInviteClassmates: String { loc("study_rooms.invite_classmates") }
    static var studyRoomsSayHi: String { loc("study_rooms.say_hi") }
    static var studyRoomsSayHiMessage: String { loc("study_rooms.say_hi_message") }
    static var studyRoomsComposerPlaceholder: String { loc("study_rooms.composer_placeholder") }
    static var studyRoomsMemberJoinedFmt: String { loc("study_rooms.member_joined_fmt") }
    static var studyRoomsMemberLeftFmt: String { loc("study_rooms.member_left_fmt") }
    static var studyRoomsHostChangedFmt: String { loc("study_rooms.host_changed_fmt") }
    static var studyRoomsRoomClosed: String { loc("study_rooms.room_closed") }
    static var studyRoomsLinkPendingHostApproval: String { loc("study_rooms.link_pending_host_approval") }
    static var studyRoomsLinkEnrollmentRequired: String { loc("study_rooms.link_enrollment_required") }

    // Messages-tab rebuild (Chats / Rooms switcher, sub-filters, status pills, empty states)
    static var messagesSwitcherChats: String { loc("messages.switcher_chats") }
    static var messagesSwitcherRooms: String { loc("messages.switcher_rooms") }
    static var messagesRoomsFilterAll: String { loc("messages.rooms_filter_all") }
    static var messagesRoomsFilterRunning: String { loc("messages.rooms_filter_running") }
    static var messagesRoomsFilterEnded: String { loc("messages.rooms_filter_ended") }
    static var messagesRoomStatusLive: String { loc("messages.room_status_live") }
    static var messagesRoomStatusEnded: String { loc("messages.room_status_ended") }
    static var messagesHostBadgeShort: String { loc("messages.host_badge_short") }
    static var messagesCoHostBadgeShort: String { loc("messages.co_host_badge_short") }
    static var messagesNoChatsTitle: String { loc("messages.no_chats_title") }
    static var messagesNoChatsSubtitle: String { loc("messages.no_chats_subtitle") }
    static var messagesNoChatsCta: String { loc("messages.no_chats_cta") }
    static var messagesNoRoomsTitle: String { loc("messages.no_rooms_title") }
    static var messagesNoRoomsSubtitle: String { loc("messages.no_rooms_subtitle") }
    static var messagesNoRoomsCta: String { loc("messages.no_rooms_cta") }
    static var messagesNoEndedRoomsTitle: String { loc("messages.no_ended_rooms_title") }
    static var messagesNoEndedRoomsSubtitle: String { loc("messages.no_ended_rooms_subtitle") }

    // "You're the last one here" sheet (host is alone — confirmation
    // before closing the room permanently).
    static var studyRoomsLastOneTitle: String { loc("study_rooms.last_one_title") }
    static var studyRoomsLastOneSubtitle: String { loc("study_rooms.last_one_subtitle") }
    static var studyRoomsLastOneDetail: String { loc("study_rooms.last_one_detail") }
    static var studyRoomsLastOneStay: String { loc("study_rooms.last_one_stay") }
    static var studyRoomsLastOneLeaveAndClose: String { loc("study_rooms.last_one_leave_and_close") }

    // Closed-room read-only banner in the chat composer.
    static var studyRoomsClosedBannerTitle: String { loc("study_rooms.closed_banner_title") }
    static var studyRoomsClosedBannerSubtitle: String { loc("study_rooms.closed_banner_subtitle") }
    static var studyRoomsRoomEndedExit: String { loc("study_rooms.room_ended_exit") }

    // Removed-member read-only banner — shown in lieu of the composer
    // when a host has kicked the viewer but the room is still ACTIVE.
    static var studyRoomsRemovedBannerTitle: String { loc("study_rooms.removed_banner_title") }
    static var studyRoomsRemovedBannerSubtitle: String { loc("study_rooms.removed_banner_subtitle") }

    // Left-room read-only banner — shown in lieu of the composer when
    // the viewer left a still-ACTIVE room on their own.
    static var studyRoomsLeftBannerTitle: String { loc("study_rooms.left_banner_title") }
    static var studyRoomsLeftBannerSubtitle: String { loc("study_rooms.left_banner_subtitle") }

    // MARK: - Internal
    // MARK: - Quiz (section quiz flow — intro → play → finishing → result → review)
    static var quizNavTitle:           String { loc("quiz.nav_title") }
    static var quizSectionQuiz:        String { loc("quiz.section_quiz") }
    static var quizMcq:                String { loc("quiz.mcq") }
    static var quizQuestions:          String { loc("quiz.questions") }
    static var quizPassMark:           String { loc("quiz.pass_mark") }
    static var quizBestScore:          String { loc("quiz.best_score") }
    static var quizStart:              String { loc("quiz.start") }
    static var quizRetake:             String { loc("quiz.retake") }
    static var quizReviewLessonFirst:  String { loc("quiz.review_lesson_first") }
    static var quizReviewPastGrade:    String { loc("quiz.review_past_grade") }
    static var quizReviewPastGrades:   String { loc("quiz.review_past_grades") }
    static var quizPastGradesTitle:    String { loc("quiz.past_grades_title") }
    static var quizNoPastAttempts:     String { loc("quiz.no_past_attempts") }
    static var quizPassedBadge:        String { loc("quiz.passed_badge") }
    static var quizFailedBadge:        String { loc("quiz.failed_badge") }
    static var quizTapToSelectSingle:  String { loc("quiz.tap_to_select_single") }
    static var quizTapToSelectMulti:   String { loc("quiz.tap_to_select_multiple") }
    static var quizSubmitAnswer:       String { loc("quiz.submit_answer") }
    static var quizSkip:               String { loc("quiz.skip") }
    static var quizPrev:               String { loc("quiz.prev") }
    static var quizNext:               String { loc("quiz.next") }
    static var quizFinish:             String { loc("quiz.finish") }
    static var quizLastQuestionNudge:  String { loc("quiz.last_question_nudge") }
    static var quizFinishingTitle:     String { loc("quiz.finishing_title") }
    static var quizQuizComplete:       String { loc("quiz.quiz_complete") }
    static var quizWellDone:           String { loc("quiz.well_done") }
    static var quizWellDoneSoFar:      String { loc("quiz.well_done_so_far") }
    static var quizYouPassed:          String { loc("quiz.you_passed") }
    static var quizNotThisTime:        String { loc("quiz.not_this_time") }
    static var quizYouDidntPass:       String { loc("quiz.you_didnt_pass") }
    static var quizFlawless:           String { loc("quiz.flawless") }
    static var quizPerfectScore:       String { loc("quiz.perfect_score") }
    static var quizCorrect:            String { loc("quiz.correct") }
    static var quizWrong:              String { loc("quiz.wrong") }
    static var quizQuestionBreakdown:  String { loc("quiz.question_breakdown") }
    static var quizReviewAnswers:      String { loc("quiz.review_answers") }
    static var quizExit:               String { loc("quiz.exit") }
    static var quizFilterAll:          String { loc("quiz.filter_all") }
    static var quizFilterCorrect:      String { loc("quiz.filter_correct") }
    static var quizFilterWrong:        String { loc("quiz.filter_wrong") }
    static var quizTapToReview:        String { loc("quiz.tap_to_review") }
    static var quizReviewOnly:         String { loc("quiz.review_only") }
    static var quizYourAnswer:         String { loc("quiz.your_answer") }
    static var quizYouMissedThis:      String { loc("quiz.you_missed_this") }
    static var quizCorrectAnswer:      String { loc("quiz.correct_answer") }
    static var quizConfirmFinishTitle: String { loc("quiz.confirm_finish_title") }
    static var quizConfirmFinishCta:   String { loc("quiz.confirm_finish_cta") }
    static var quizCancel:             String { loc("quiz.cancel") }

    // Review-before-submit screen
    static var quizAnswered:           String { loc("quiz.answered") }
    static var quizAllComplete:        String { loc("quiz.all_complete") }
    static var quizReadyToSubmit:      String { loc("quiz.ready_to_submit") }
    static var quizUnansweredSubtitle: String { loc("quiz.unanswered_subtitle") }
    static var quizJumpBackTo:         String { loc("quiz.jump_back_to") }
    static var quizLookingGoodTitle:   String { loc("quiz.looking_good_title") }
    static var quizLookingGoodBody:    String { loc("quiz.looking_good_body") }
    static var quizAllAnswered:        String { loc("quiz.all_answered") }
    static var quizSubmitQuiz:         String { loc("quiz.submit_quiz") }
    static var quizSubmitAnyway:       String { loc("quiz.submit_anyway") }
    static var quizGoBack:             String { loc("quiz.go_back") }

    static func quizQuestionNOfN(_ current: Int, _ total: Int) -> String {
        String(format: loc("quiz.question_n_of_n"), current, total)
    }
    static func quizAttemptNumber(_ n: Int) -> String {
        String(format: loc("quiz.attempt_number"), n)
    }
    static func quizSelectedOfTotal(_ selected: Int, _ total: Int) -> String {
        String(format: loc("quiz.selected_of_total"), selected, total)
    }
    static func quizFinishingSubtitle(_ n: Int) -> String {
        String(format: loc("quiz.finishing_subtitle"), n)
    }
    static func quizScoreOutOf(_ correct: Int, _ total: Int) -> String {
        String(format: loc("quiz.score_out_of"), correct, total)
    }
    static func quizUnansweredWarning(_ n: Int) -> String {
        String(format: loc("quiz.unanswered_warning"), n)
    }
    static func quizFilterCount(_ label: String, _ n: Int) -> String {
        String(format: loc("quiz.filter_count"), label, n)
    }
    static func quizUnansweredTitle(_ n: Int) -> String {
        String(format: loc("quiz.unanswered_title"), n)
    }
    static func quizAllAnsweredSubtitle(_ n: Int) -> String {
        String(format: loc("quiz.all_answered_subtitle"), n)
    }
    static func quizNAnswered(_ n: Int) -> String {
        String(format: loc("quiz.n_answered"), n)
    }
    static func quizNSkipped(_ n: Int) -> String {
        String(format: loc("quiz.n_skipped"), n)
    }
    static func quizQuestionLabel(_ n: Int) -> String {
        String(format: loc("quiz.question_label"), n)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Arabic-only pass
    //
    // Keys added when the app went Arabic-only. Every one of these replaced a
    // hardcoded English literal in a view; the English value is still carried
    // in `en.lproj` so `AppLocaleDefault.englishHidden = false` restores the
    // bilingual app rather than leaving these surfaces stranded in Arabic.
    // ─────────────────────────────────────────────────────────────────

    // Settings
    static var settingsSubtitles: String { loc("settings.subtitles") }
    static var settingsDeveloperSection: String { loc("settings.developer_section") }
    static var settingsTestDetection: String { loc("settings.test_detection") }
    static var share: String { loc("general.share") }

    // Lesson complete
    static var lessonCompleteTitle: String { loc("lesson_complete.title") }
    static func lessonCompleteXp(_ xp: Int) -> String {
        String(format: loc("lesson_complete.xp_earned"), xp)
    }
    static var lessonCompleteNextLesson: String { loc("lesson_complete.next_lesson") }
    static var lessonCompleteBackToCourse: String { loc("lesson_complete.back_to_course") }
    static var lessonCompleteProgressLabel: String { loc("lesson_complete.progress_label") }

    // Login chrome
    static var turnstileVerifying: String { loc("turnstile.verifying") }
    static var playbackCertificateError: String { loc("playback.certificate_error") }

    // Catalog empty states
    static var catalogEmptyTitle: String { loc("catalog.empty_title") }
    static var catalogEmptyBody: String { loc("catalog.empty_body") }
    static func catalogNoMatch(_ query: String) -> String {
        String(format: loc("catalog.no_match"), query)
    }

    // Registration + password validation
    static var authErrFirstName: String { loc("auth.err_first_name") }
    static var authErrEmail: String { loc("auth.err_email") }
    static var authErrPasswordRule: String { loc("auth.err_password_rule") }
    static var authErrEmailTaken: String { loc("auth.err_email_taken") }
    static var authErrPasswordShort: String { loc("auth.err_password_short") }
    static var authErrPasswordNoDigit: String { loc("auth.err_password_no_digit") }
    static var authErrPasswordMismatch: String { loc("auth.err_password_mismatch") }

    // Password reset
    static var resetDoneTitle: String { loc("reset.done_title") }
    static var resetDoneBody: String { loc("reset.done_body") }
    static var resetTitle: String { loc("reset.title") }
    static var resetSubtitle: String { loc("reset.subtitle") }
    static var resetHint: String { loc("reset.hint") }
    static var resetStrength: String { loc("reset.strength") }
    static var resetStrengthWeak: String { loc("reset.strength_weak") }
    static var resetStrengthFair: String { loc("reset.strength_fair") }
    static var resetStrengthGood: String { loc("reset.strength_good") }
    static var resetStrengthStrong: String { loc("reset.strength_strong") }
    static var resetSectionNewPassword: String { loc("reset.section_new_password") }
    static var resetFieldPassword: String { loc("reset.field_password") }
    static var resetFieldConfirm: String { loc("reset.field_confirm") }
    static var resetUpdateButton: String { loc("reset.update_button") }
    static var resetUpdating: String { loc("reset.updating") }

    // Two-factor
    static var totpTitleLine1: String { loc("totp.title_line1") }
    static var totpTitleLine2: String { loc("totp.title_line2") }
    static var totpSubtitle: String { loc("totp.subtitle") }
    static var totpVerifySignIn: String { loc("totp.verify_sign_in") }
    static var totpUseRecovery: String { loc("totp.use_recovery") }
    static var twoFaEnableLine1: String { loc("two_fa.enable_line1") }
    static var twoFaTitle: String { loc("two_fa.title") }
    static var twoFaEnrollSubtitle: String { loc("two_fa.enroll_subtitle") }
    static var twoFaQrFailed: String { loc("two_fa.qr_failed") }
    static var twoFaManualSecret: String { loc("two_fa.manual_secret") }
    static var twoFaCodeField: String { loc("two_fa.code_field") }
    static var twoFaVerifyEnable: String { loc("two_fa.verify_enable") }
    static var twoFaDisableLine1: String { loc("two_fa.disable_line1") }
    static var twoFaDisableSubtitle: String { loc("two_fa.disable_subtitle") }
    static var twoFaDisableAction: String { loc("two_fa.disable_action") }
    static var recoverySaveLine1: String { loc("recovery.save_line1") }
    static var recoveryLine2: String { loc("recovery.line2") }
    static var recoverySubtitle: String { loc("recovery.subtitle") }
    static var recoveryWarning: String { loc("recovery.warning") }
    static var recoveryCopyAll: String { loc("recovery.copy_all") }
    static var recoveryCopied: String { loc("recovery.copied") }

    // Post-signup / returning-user covers
    static var welcomeNewAccountBadge: String { loc("welcome.new_account_badge") }
    static var welcomeJourneyLine1: String { loc("welcome.journey_line1") }
    static var welcomeJourneyLine2: String { loc("welcome.journey_line2") }
    static func welcomeGreeting(_ name: String) -> String {
        String(format: loc("welcome.greeting"), name)
    }
    static var welcomeReadyBody: String { loc("welcome.ready_body") }
    static var welcomeNewBadge: String { loc("welcome.new_badge") }
    static var welcomeWaitingHeader: String { loc("welcome.waiting_header") }
    static var welcomeCategories: String { loc("welcome.categories") }
    static var welcomeLiveQaTitle: String { loc("welcome.live_qa_title") }
    static var welcomeLiveQaBody: String { loc("welcome.live_qa_body") }
    static var welcomeTrackTitle: String { loc("welcome.track_title") }
    static var welcomeTrackBody: String { loc("welcome.track_body") }
    static var welcomeMeetInstructors: String { loc("welcome.meet_instructors") }
    static func welcomeExpertInstructors(_ count: Int) -> String {
        String(format: loc("welcome.expert_instructors_count"), count)
    }
    static var welcomeExpertInstructorsPlain: String { loc("welcome.expert_instructors") }
    static var welcomeBackLine: String { loc("welcome.back_line") }
    static var welcomeBackBody: String { loc("welcome.back_body") }
    static var welcomeGoToDashboard: String { loc("welcome.go_to_dashboard") }
    static var welcomeStatCourses: String { loc("welcome.stat_courses") }
    static var welcomeStatStreak: String { loc("welcome.stat_streak") }
    static var welcomeStatProgress: String { loc("welcome.stat_progress") }
    static var welcomeContinueLastCourse: String { loc("welcome.continue_last_course") }

    // Study rooms
    static var studyRoomEmptyLine1: String { loc("study_room.empty_line1") }
    static var studyRoomEmptyLine2: String { loc("study_room.empty_line2") }
    static var studyRoomSharedNotes: String { loc("study_room.shared_notes") }

    // Notification inbox + local push
    static var notifInstructor: String { loc("notif.instructor") }
    static func notifScore(_ pct: Int) -> String {
        String(format: loc("notif.score"), pct)
    }
    static var notifNewQuiz: String { loc("notif.new_quiz") }
    static var notifInboxLiveSession: String { loc("notif.live_session") }
    static func notifStartsInMinutes(_ title: String, _ minutes: Int) -> String {
        String(format: loc("notif.starts_in_minutes"), title, minutes)
    }
    static var notifSessionLive: String { loc("notif.session_live") }
    static func notifCoursesInProgress(_ count: Int) -> String {
        String(format: loc("notif.courses_in_progress"), count)
    }
    static var notifPickUpWhereLeft: String { loc("notif.pick_up_where_left") }
    static func notifKeepStreakDays(_ days: Int) -> String {
        String(format: loc("notif.keep_streak_days"), days)
    }
    static var notifKeepStreak: String { loc("notif.keep_streak") }
    static var pushLiveSessionTitle: String { loc("push.live_session_title") }
    static func pushLiveSessionBody(_ title: String) -> String {
        String(format: loc("push.live_session_body"), title)
    }

    // Security — device sessions
    static var securityActiveNow: String { loc("security.active_now") }
    static func securityActiveAgo(_ relative: String) -> String {
        String(format: loc("security.active_ago"), relative)
    }

    // Messages — relative timestamps on conversation rows
    static var messagesNow: String { loc("messages.now") }
    static func messagesMinutesAgo(_ n: Int) -> String {
        String(format: loc("messages.minutes_ago"), n)
    }
    static func messagesHoursAgo(_ n: Int) -> String {
        String(format: loc("messages.hours_ago"), n)
    }

    static var totpUseAuthenticator: String { loc("totp.use_authenticator") }

    // MARK: - Server content: primary language, then the other one
    //
    // Course, section and lesson titles come from the backend in two columns.
    // Every call site was a bare `locale == "ar" ? titleAr : titleEn`, which was
    // survivable while the app was bilingual — a student on English still saw
    // *something*. Under the Arabic lock the English branch is dead, so a course
    // whose `title_ar` the instructor left blank rendered as an EMPTY title
    // instead of degrading to the English one. `InstructorBrowseViewModel`
    // already had the right shape; these two put it everywhere.

    /// The value for `locale`, falling back to the other language when the
    /// primary side is missing or blank.
    static func localized(_ locale: String, ar: String?, en: String?) -> String? {
        let primary = locale == "ar" ? ar : en
        let secondary = locale == "ar" ? en : ar
        if let p = primary, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return p
        }
        if let s = secondary, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
        return nil
    }

    /// Non-optional variant for fields the backend always sends.
    static func localized(_ locale: String, ar: String, en: String) -> String {
        localized(locale, ar: Optional(ar), en: Optional(en))
            ?? (locale == "ar" ? ar : en)
    }

    /// A file size in the app's language.
    ///
    /// The three chat/document call sites used `ByteCountFormatter`, whose
    /// `string(fromByteCount:countStyle:)` convenience has no locale hook at
    /// all: it always emits Latin digits and a Latin "KB"/"MB", so an
    /// Arabic-only app still showed "2.4 MB". `ByteCountFormatStyle` does take
    /// a locale, and on iOS 18 it is available everywhere.
    ///
    /// Ask Droob AI deliberately keeps its own `Strings.size` — that feature
    /// does not use the string table at all, by an explicit decision recorded
    /// in AskDroobAIViewModel — so this is for everything outside it.
    static func fileSize(_ bytes: Int64) -> String {
        bytes.formatted(
            .byteCount(style: .file)
                .locale(Locale(identifier: currentLanguageCode)))
    }

    /// A course price.
    ///
    /// Was `"\(amount) \(currency)"` — Latin digits and a Latin ISO code glued
    /// together with no `NumberFormatter` at all, on every price surface in the
    /// catalog. `.currency` gives Arabic-Indic digits and the Arabic currency
    /// name under an Arabic locale, and the same "399 SAR" shape under English.
    static func price(cents: Int, currency: String) -> String {
        let amount = Decimal(cents) / 100
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: currentLanguageCode)
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        // Course prices are whole riyals on this platform; ".00" on every card
        // is noise.
        formatter.maximumFractionDigits = cents % 100 == 0 ? 0 : 2
        if let text = formatter.string(from: amount as NSNumber) {
            return text
        }
        // A currency code the formatter does not know: keep the old shape
        // rather than showing nothing.
        return "\(cents / 100) \(currency)"
    }

    // Presence-guard debug panel (visible on TestFlight)
    static var guardWatermark: String { loc("guard.watermark") }
    static var guardSideDim: String { loc("guard.side_dim") }
    static var guardTiltDim: String { loc("guard.tilt_dim") }
    static var guardPresence: String { loc("guard.presence") }
    static var guardPhoneRec: String { loc("guard.phone_rec") }
    static var guardBlockRecording: String { loc("guard.block_recording") }
    static var guardLayersTitle: String { loc("guard.layers_title") }
    static var guardLayersHint: String { loc("guard.layers_hint") }
    static var guardSampleVideo: String { loc("guard.sample_video") }
    static var guardHarness: String { loc("guard.harness") }
    static var guardResetConsent: String { loc("guard.reset_consent") }
    static var guardSimulate: String { loc("guard.simulate") }
    static var guardSectionOverlay: String { loc("guard.section_overlay") }
    static var guardSectionCamera: String { loc("guard.section_camera") }
    static var guardSectionAppWide: String { loc("guard.section_app_wide") }

    // Onboarding illustration cards. Filler content, but every new user sees
    // it, and the labels around it already went through L10n.
    static var onbDemoInstructorName: String { loc("onb.demo_instructor_name") }
    static var onbDemoInstructorInitials: String { loc("onb.demo_instructor_initials") }
    static var onbDemoSessionTitle: String { loc("onb.demo_session_title") }
    static var onbDemoMonth: String { loc("onb.demo_month") }

    private static func loc(_ key: String) -> String {
        let appLocale = currentLanguageCode
        // Backend override wins first so wording can change without an App
        // Store release. Falls through to the bundled Localizable.strings
        // baseline when there's no override for this key+locale (offline
        // default). See LocalizationOverrides.
        if let override = LocalizationOverrides.shared.value(forKey: key, locale: appLocale) {
            return override
        }
        if let path = Bundle.main.path(forResource: appLocale, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(key, bundle: bundle, comment: "")
        }
        return NSLocalizedString(key, bundle: .main, comment: "")
    }
}

// MARK: - App locale default (single source of truth)
//
// Droob is an Arabic-first platform: a fresh install opens in Arabic even on an
// English phone, so the DEVICE language is deliberately not consulted anywhere.
// While `englishHidden` is on this is a LOCK, not just a default — English is
// unreachable, and a stored "en" from before the lock is overwritten rather
// than honoured, so a user who had picked English is moved to Arabic instead of
// being stranded in a language the picker can no longer reach.
//
// Every fallback in the app funnels through here — `L10n.loc`, the
// `\.appLocale` environment key, the UIKit semantic-content pass in
// `DroobStudentApp`, the push-token locale, and all 40+
// `@AppStorage("appLocale")` declarations, whose SwiftUI default applies
// whenever nothing is stored yet. They must agree or the first launch renders
// Arabic in one place and English in another.
//
// Lives in L10n.swift rather than its own file because the Xcode project has
// no filesystem-synchronized group (see the note further down): a new .swift
// file on disk is not compiled and fails at link time.
enum AppLocaleDefault {
    /// UserDefaults key the language toggle persists the user's choice under.
    static let storageKey = "appLocale"
    /// Language used until the user chooses one.
    static let code = "ar"

    /// English is hidden for now — the app ships Arabic-only.
    ///
    /// Nothing English was deleted: `en.lproj`, every English string and the
    /// picker row are all still here, so flipping this to `false` restores the
    /// bilingual app exactly as it was.
    static let englishHidden = true

    /// Pins the stored locale to `code` while `englishHidden` is on.
    ///
    /// This one write *is* the lock. Overwriting the key — rather than
    /// registering a default, which only applies when the key is **absent** —
    /// is what reaches a user who already chose English, and it lands on all
    /// ~45 `@AppStorage("appLocale")` sites, `L10n.loc`, `AppLocaleKey`, the
    /// semantic-content pass and the push-token locale at once, since every one
    /// of them reads this same key. Must run before the first `body`.
    static func lockIfNeeded() {
        guard englishHidden else {
            // Flag flipped back: hand the system chrome to the device language
            // again. Without this removal the forced Arabic below would outlive
            // the flag, because it is a *persisted* write.
            UserDefaults.standard.removeObject(forKey: systemLanguagesKey)
            return
        }
        UserDefaults.standard.set(code, forKey: storageKey)
        lockSystemLanguage()
    }

    /// Is the app in Arabic right now?
    ///
    /// For code with no view context — view models, error mapping, formatters,
    /// background work. Views should keep reading `\.appLocale` instead; this
    /// gives the non-view layer exactly one reader rather than a hand-rolled
    /// `UserDefaults.standard.string(forKey:) ?? code` per file.
    static var isArabic: Bool {
        (UserDefaults.standard.string(forKey: storageKey) ?? code) == "ar"
    }

    /// The locale a **stored** artefact should be *presented* in.
    ///
    /// Sessions archived before the lock carry `locale == "en"`, and rendering
    /// them against that stored value put English dates, English counts and
    /// English exported sheets inside an Arabic-only Library — permanently,
    /// because nothing ever rewrites the stored value. While `englishHidden` is
    /// on, presentation follows the app; the stored locale is left untouched on
    /// disk, so flipping the flag back restores each session's own language
    /// rather than having rewritten history.
    static func presentationLocale(_ stored: String) -> String {
        englishHidden ? code : stored
    }

    /// The `appLocale` key only reaches strings that go through `L10n.loc`.
    /// Everything UIKit and Foundation supply for themselves — the photo
    /// picker's "Cancel", the document browser, `QLPreviewController`, the share
    /// sheet, `SFSafariViewController`, and every `DateFormatter` or
    /// `NumberFormatter` left on `Locale.autoupdatingCurrent` — follows
    /// `AppleLanguages`, i.e. the DEVICE. On an English phone that painted
    /// English system chrome through the middle of an Arabic-only app.
    ///
    /// Writing our own app domain (never the global one) overrides it for this
    /// process only. It is one write, gated by the same flag, and removed again
    /// the moment the flag goes back to `false`.
    private static let systemLanguagesKey = "AppleLanguages"

    private static func lockSystemLanguage() {
        let defaults = UserDefaults.standard
        // Idempotent: an unconditional write here would dirty the defaults
        // database on every single launch.
        guard defaults.stringArray(forKey: systemLanguagesKey) != [code] else { return }
        defaults.set([code], forKey: systemLanguagesKey)
    }
}

/// Same shape as `AppLocaleDefault`, for the light/dark preference.
///
/// The app ships **light** and follows only an explicit in-app choice — never
/// the device's system appearance. Keeping the default in one place means the
/// several `@AppStorage("appColorScheme")` declarations can't drift apart.
enum AppColorSchemeDefault {
    /// UserDefaults key the Light/Dark toggle persists the user's choice under.
    static let storageKey = "appColorScheme"
    /// Scheme used until the user chooses one.
    static let code = "light"
}

// MARK: - Environment Key for app locale override

struct AppLocaleKey: EnvironmentKey {
    /// Computed (not a stored `let`) so it reflects a stored preference written
    /// after first access, and falls back to Arabic — never the device language.
    static var defaultValue: String {
        UserDefaults.standard.string(forKey: AppLocaleDefault.storageKey)
            ?? AppLocaleDefault.code
    }
}

extension EnvironmentValues {
    var appLocale: String {
        get { self[AppLocaleKey.self] }
        set { self[AppLocaleKey.self] = newValue }
    }
}

// ─────────────────────────────────────────────────────────────────────
// Bidi isolation lives here rather than in its own file because the Xcode
// project has no filesystem-synchronized group: a new .swift file on disk
// is NOT compiled until it is added to project.pbxproj by hand, and a
// missing entry fails as "undefined symbol" at link time — invisible to
// `swiftc -parse`. Keeping this in an already-referenced file removes that
// failure mode, and localization is where it belongs anyway.
// ─────────────────────────────────────────────────────────────────────

// MARK: - Bidirectional text isolation
//
// Arabic course and lesson titles come back mixed with Latin runs — lesson
// numbers ("3.2"), Latin course codes, instructor names typed in English. When
// those are interpolated into one string the Unicode bidi algorithm reorders
// the whole line as a single paragraph, and the result is visibly wrong:
//
//   "3.2 — مقدمة في التفاضل"     renders as   "مقدمة في التفاضل — 3.2"
//   "الوحدة 1 · Calculus"        splits the number away from its label
//
// The number has not moved in the *string*; it moves on screen, because a
// neutral character (the dash, the interpunct, a space) between a Latin run and
// an Arabic run inherits direction from its surroundings and drags the runs
// with it.
//
// The fix is to wrap each interpolated value in an isolate so it resolves its
// own direction and cannot reorder against its neighbours. FSI (First Strong
// Isolate, U+2068) picks the direction from the value's own first strong
// character, which is exactly right when we do not know at compile time whether
// a title is Arabic or Latin. PDI (U+2069) closes it.
//
// This is the same mechanism the web app already relies on for KaTeX
// (`unicode-bidi: isolate` in index.css) — formulas there had the identical
// problem, where `x²` rendered as `²x` under the Arabic UI.

extension String {

    /// Wraps the string in a Unicode isolate so it keeps its own direction when
    /// interpolated next to text of the opposite direction.
    ///
    /// Use on every *value* going into a mixed-direction string — not on the
    /// finished sentence, which would isolate the whole thing and change
    /// nothing:
    ///
    /// ```swift
    /// Text("\(lessonNumber.bidiIsolated) — \(title.bidiIsolated)")
    /// ```
    ///
    /// Empty strings are returned untouched: wrapping nothing just adds two
    /// invisible characters that can still affect neighbouring runs.
    var bidiIsolated: String {
        isEmpty ? self : "\u{2068}\(self)\u{2069}"
    }
}

/// Joins pre-isolated parts with a separator, skipping blanks.
///
/// Most of our mixed-direction strings are "number · title" or
/// "number — title", where either side can be absent. Doing it by hand tends to
/// leave a dangling separator when the number is empty, so this centralises
/// both the isolation and the blank handling.
///
/// - Parameters:
///   - parts: values to join; blank entries are dropped
///   - separator: literal placed between parts (already directionally neutral)
/// - Returns: the joined string with each part isolated
func bidiJoin(_ parts: String?..., separator: String = " · ") -> String {
    parts
        .compactMap { $0 }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map(\.bidiIsolated)
        .joined(separator: separator)
}
