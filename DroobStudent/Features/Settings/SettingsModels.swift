import Foundation

// MARK: - Notification preferences

/// Every field the server tracks is still decoded, but only `courseUpdates`
/// has a control on the Notifications screen: as of 2026-08 the backend
/// suppresses every notification kind except course-content changes, so a
/// toggle for any of the others would be a switch wired to nothing.
struct NotificationPrefs: Decodable, Equatable {
    var lessonReminders: Bool
    var streakAlerts: Bool
    var quizResults: Bool
    var courseUpdates: Bool
    var liveSessionReminders: Bool
    var newMessages: Bool
    var newCourseAlerts: Bool
    var promotionsOffers: Bool

    enum CodingKeys: String, CodingKey {
        case lessonReminders     = "lesson_reminders"
        case streakAlerts        = "streak_alerts"
        case quizResults         = "quiz_results"
        case courseUpdates       = "course_updates"
        case liveSessionReminders = "live_session_reminders"
        case newMessages         = "new_messages"
        case newCourseAlerts     = "new_course_alerts"
        case promotionsOffers    = "promotions_offers"
    }
}

/// Patch body — every field optional so we can ship a single-key update.
struct NotificationPrefsUpdate: Encodable {
    var lessonReminders: Bool? = nil
    var streakAlerts: Bool? = nil
    var quizResults: Bool? = nil
    var courseUpdates: Bool? = nil
    var liveSessionReminders: Bool? = nil
    var newMessages: Bool? = nil
    var newCourseAlerts: Bool? = nil
    var promotionsOffers: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case lessonReminders     = "lesson_reminders"
        case streakAlerts        = "streak_alerts"
        case quizResults         = "quiz_results"
        case courseUpdates       = "course_updates"
        case liveSessionReminders = "live_session_reminders"
        case newMessages         = "new_messages"
        case newCourseAlerts     = "new_course_alerts"
        case promotionsOffers    = "promotions_offers"
    }
}

// MARK: - Account profile (display name + email)

/// `GET /v1/student/settings/profile`. `display_name` is what the UI labels
/// "Username"; `email_verified` reflects whether the address has been
/// confirmed (an in-flight email change does not flip it until confirmed).
struct StudentProfile: Decodable, Equatable {
    let displayName: String
    let email: String
    let emailVerified: Bool

    enum CodingKeys: String, CodingKey {
        case displayName   = "display_name"
        case email
        case emailVerified = "email_verified"
    }
}

struct UpdateProfileBody: Encodable {
    let displayName: String
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct RequestEmailChangeBody: Encodable {
    let newEmail: String
    enum CodingKeys: String, CodingKey {
        case newEmail = "new_email"
    }
}

struct ConfirmEmailChangeBody: Encodable {
    let code: String
}

// MARK: - Security status

struct SecurityStatus: Decodable, Equatable {
    let twoFactorEnabled: Bool
    let strongPassword: Bool
    let passwordChangedAt: Date?
    let deviceLimit: Int

    enum CodingKeys: String, CodingKey {
        case twoFactorEnabled    = "two_factor_enabled"
        case strongPassword      = "strong_password"
        case passwordChangedAt   = "password_changed_at"
        case deviceLimit         = "device_limit"
    }
}

struct ChangePasswordBody: Encodable {
    let currentPassword: String
    let newPassword: String
    enum CodingKeys: String, CodingKey {
        case currentPassword = "current_password"
        case newPassword     = "new_password"
    }
}

// MARK: - 2FA enrolment / verify / disable

/// Result of `POST /v1/student/settings/security/two-factor/enroll`.
struct TwoFactorEnrollResponse: Decodable {
    /// Base32-encoded shared secret. Shown to the user as a manual-entry
    /// fallback when QR scanning isn't available.
    let secretBase32: String
    /// `otpauth://` URI we render as a QR code for authenticator apps.
    let otpauthUri: String

    enum CodingKeys: String, CodingKey {
        case secretBase32 = "secret_base32"
        case otpauthUri   = "otpauth_uri"
    }
}

/// Result of `/verify` (enrolment) and `/recovery-codes/regenerate`. Carries
/// the freshly-generated **single-use** recovery codes — surface them to
/// the user immediately and forget them; they are never returned again.
struct TwoFactorVerifyResponse: Decodable {
    let twoFactorEnabled: Bool
    let recoveryCodes: [String]

    enum CodingKeys: String, CodingKey {
        case twoFactorEnabled = "two_factor_enabled"
        case recoveryCodes    = "recovery_codes"
    }
}

struct TwoFactorVerifyRequest: Encodable {
    let code: String
}

struct TwoFactorDisableRequest: Encodable {
    /// Either a current 6-digit TOTP code or one of the unused recovery
    /// codes. Both kinds are accepted server-side because a user who lost
    /// their authenticator must still be able to disable.
    let code: String
}

// MARK: - Devices

struct StudentDevice: Decodable, Identifiable, Equatable {
    let id: String
    let label: String
    let location: String?
    let isCurrent: Bool
    let lastActiveAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case location
        case isCurrent    = "is_current"
        case lastActiveAt = "last_active_at"
    }

    /// Returns "نشط الآن" for the current device, else a relative short
    /// description.
    ///
    /// The formatter is pinned to the app locale, not left on
    /// `Locale.autoupdatingCurrent`: it used to follow the DEVICE while the
    /// prefix beside it was hardcoded English, so one label could come out
    /// half in one language and half in another.
    var activityDescription: String {
        if isCurrent { return L10n.securityActiveNow }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: L10n.currentLanguageCode)
        formatter.unitsStyle = .short
        return L10n.securityActiveAgo(
            formatter.localizedString(for: lastActiveAt, relativeTo: Date()))
    }
}

/// Profile stats (re-uses the existing /v1/student/progress endpoint).
struct StudentProgressStats: Decodable, Equatable {
    let learningScore: Int
    let cohortPercentile: Int
    let xpThisWeek: Int
    let streakDays: Int
    let watchTimeHours: Int
    let lessonsCompleted: Int
    let certificatesCount: Int

    enum CodingKeys: String, CodingKey {
        case learningScore     = "learning_score"
        case cohortPercentile  = "cohort_percentile"
        case xpThisWeek        = "xp_this_week"
        case streakDays        = "streak_days"
        case watchTimeHours    = "watch_time_hours"
        case lessonsCompleted  = "lessons_completed"
        case certificatesCount = "certificates_count"
    }
}
