import XCTest
@testable import DroobStudent

final class CatalogViewModelTests: XCTestCase {

    // MARK: - CourseSummary decoding

    func testCourseSummaryDecoding() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000021",
          "title_en": "Introduction to Machine Learning",
          "title_ar": "مقدمة في تعلم الآلة",
          "subtitle_en": "Learn ML",
          "subtitle_ar": "تعلم الذكاء",
          "cover_url": null,
          "instructor_name": "Droob Academy",
          "price_cents": 14900,
          "currency": "SAR",
          "enrolled": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let course = try decoder.decode(CourseSummary.self, from: json)
        XCTAssertEqual(course.id, "00000000-0000-0000-0000-000000000021")
        XCTAssertEqual(course.titleEn, "Introduction to Machine Learning")
        XCTAssertEqual(course.titleAr, "مقدمة في تعلم الآلة")
        XCTAssertEqual(course.instructorName, "Droob Academy")
        XCTAssertEqual(course.priceCents, 14900)
        XCTAssertEqual(course.currency, "SAR")
        XCTAssertFalse(course.enrolled)
    }

    func testCourseSummaryLocalizedTitle() throws {
        let json = """
        {
          "id": "1", "title_en": "English Title", "title_ar": "عنوان عربي",
          "cover_url": null, "instructor_name": "Instructor",
          "price_cents": 0, "currency": "SAR", "enrolled": true
        }
        """.data(using: .utf8)!

        let course = try JSONDecoder().decode(CourseSummary.self, from: json)
        XCTAssertEqual(course.localizedTitle(locale: "en"), "English Title")
        XCTAssertEqual(course.localizedTitle(locale: "ar"), "عنوان عربي")
    }

    func testCourseSummaryFormattedPriceFree() throws {
        let json = """
        {
          "id": "1", "title_en": "T", "title_ar": "T",
          "cover_url": null, "instructor_name": "I",
          "price_cents": 0, "currency": "SAR", "enrolled": false
        }
        """.data(using: .utf8)!

        let course = try JSONDecoder().decode(CourseSummary.self, from: json)
        XCTAssertEqual(course.formattedPrice, L10n.free)
    }

    func testCourseSummaryFormattedPricePaid() throws {
        let json = """
        {
          "id": "1", "title_en": "T", "title_ar": "T",
          "cover_url": null, "instructor_name": "I",
          "price_cents": 14900, "currency": "SAR", "enrolled": false
        }
        """.data(using: .utf8)!

        let course = try JSONDecoder().decode(CourseSummary.self, from: json)
        XCTAssertTrue(course.formattedPrice.contains("SAR"))
        XCTAssertTrue(course.formattedPrice.contains("149"))
    }

    // MARK: - lesson_count / enrollment_count

    /// Server-shaped payload — both counts are read straight off the
    /// wire and surfaced on the Explore card's meta + trailing label.
    func testCourseSummaryDecodesLessonAndEnrollmentCount() throws {
        let json = """
        {
          "id": "1", "title_en": "UX/UI Fundamentals", "title_ar": "أساسيات",
          "cover_url": null, "instructor_name": "Dr. Layla Hassan",
          "price_cents": 8900, "currency": "SAR", "enrolled": false,
          "rating_avg": 4.8, "rating_count": 42,
          "lesson_count": 32, "enrollment_count": 84
        }
        """.data(using: .utf8)!

        let course = try JSONDecoder().decode(CourseSummary.self, from: json)
        XCTAssertEqual(course.lessonCount, 32)
        XCTAssertEqual(course.enrollmentCount, 84)
    }

    /// Backwards compatibility: legacy fixtures (and the existing
    /// minimal-payload tests in this file) omit the new fields. The
    /// decoder must default both to 0 rather than throw, so older
    /// snapshots keep deserialising while the backend rolls out.
    func testCourseSummaryDefaultsCountsToZeroWhenAbsent() throws {
        let json = """
        {
          "id": "1", "title_en": "T", "title_ar": "T",
          "cover_url": null, "instructor_name": "I",
          "price_cents": 0, "currency": "SAR", "enrolled": false
        }
        """.data(using: .utf8)!

        let course = try JSONDecoder().decode(CourseSummary.self, from: json)
        XCTAssertEqual(course.lessonCount, 0)
        XCTAssertEqual(course.enrollmentCount, 0)
    }

    // MARK: - SpringPage

    func testSpringPageHasNextPage() {
        let page = SpringPage<CourseSummary>(
            content: [], totalElements: 100, totalPages: 5, number: 0, size: 20
        )
        XCTAssertTrue(page.hasNextPage)
    }

    func testSpringPageLastPageNoNext() {
        let page = SpringPage<CourseSummary>(
            content: [], totalElements: 40, totalPages: 2, number: 1, size: 20
        )
        XCTAssertFalse(page.hasNextPage)
    }

    func testSpringPageSinglePageNoNext() {
        let page = SpringPage<CourseSummary>(
            content: [], totalElements: 4, totalPages: 1, number: 0, size: 20
        )
        XCTAssertFalse(page.hasNextPage)
    }

    // MARK: - CourseDetail decoding

    func testCourseDetailDecoding() throws {
        let json = """
        {
          "id": "course-uuid",
          "title_en": "React Dev",
          "title_ar": "تطوير ريآكت",
          "description_en": "Learn React from scratch",
          "description_ar": "تعلم ريآكت من الصفر",
          "cover_url": null,
          "instructor_name": "Droob Academy",
          "price_cents": 9900,
          "currency": "SAR",
          "enrolled": true,
          "sections": [
            {
              "id": "sect-1",
              "title_en": "Introduction",
              "title_ar": "المقدمة",
              "sort_order": 1,
              "lessons": [
                {
                  "id": "lesson-1",
                  "title_en": "What is React?",
                  "title_ar": "ما هو ريآكت؟",
                  "sort_order": 1,
                  "type": "video"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let course = try JSONDecoder().decode(CourseDetail.self, from: json)
        XCTAssertEqual(course.id, "course-uuid")
        XCTAssertTrue(course.enrolled)
        XCTAssertEqual(course.sections.count, 1)
        XCTAssertEqual(course.sections[0].lessons.count, 1)
        XCTAssertTrue(course.sections[0].lessons[0].isVideo)
    }

    // MARK: - LessonSummary

    func testLessonSummaryIsVideo() throws {
        let json = """
        {"id":"l1","title_en":"Video","title_ar":"فيديو","sort_order":1,"type":"video"}
        """.data(using: .utf8)!
        let lesson = try JSONDecoder().decode(LessonSummary.self, from: json)
        XCTAssertTrue(lesson.isVideo)
    }

    func testLessonSummaryIsText() throws {
        let json = """
        {"id":"l2","title_en":"Text","title_ar":"نص","sort_order":2,"type":"text"}
        """.data(using: .utf8)!
        let lesson = try JSONDecoder().decode(LessonSummary.self, from: json)
        XCTAssertFalse(lesson.isVideo)
    }

    // MARK: - StudentSession.nextForHome (Home features upcoming sessions only)

    private func makeSession(id: String, startsAt: Date, status: String = "SCHEDULED") -> StudentSession {
        let iso = ISO8601DateFormatter().string(from: startsAt)
        let json = """
        {
          "id": "\(id)", "title_en": "T", "title_ar": "T",
          "description_en": null, "description_ar": null,
          "starts_at": "\(iso)", "duration_minutes": 60,
          "platform": "ZOOM", "join_url": "https://example.com",
          "status": "\(status)", "instructor_name": "I"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(StudentSession.self, from: json)
    }

    func testNextForHomeReturnsUpcomingSession() {
        let now = Date()
        let upcoming = makeSession(id: "a", startsAt: now.addingTimeInterval(30 * 60))
        let result = StudentSession.nextForHome(from: [upcoming], now: now)
        XCTAssertEqual(result?.id, "a")
    }

    func testNextForHomeSkipsLiveSession() {
        let now = Date()
        // A live (already started) session is "current", not upcoming — Home
        // skips it so it surfaces only in the Sessions tab's live banner.
        let live = makeSession(id: "live", startsAt: now.addingTimeInterval(-3 * 60), status: "LIVE")
        let result = StudentSession.nextForHome(from: [live], now: now)
        XCTAssertNil(result)
    }

    func testNextForHomeSkipsSessionPastStartEvenWhenNotLive() {
        let now = Date()
        // Start time reached but the backend hasn't flipped it to LIVE yet —
        // still "current" for Home, so the genuinely-next upcoming one wins.
        let started = makeSession(id: "started", startsAt: now.addingTimeInterval(-1 * 60))
        let upcoming = makeSession(id: "upcoming", startsAt: now.addingTimeInterval(60 * 60))
        let result = StudentSession.nextForHome(from: [started, upcoming], now: now)
        XCTAssertEqual(result?.id, "upcoming")
    }

    func testNextForHomeSkipsOngoingInFavourOfUpcoming() {
        let now = Date()
        let ongoing = makeSession(id: "ongoing", startsAt: now.addingTimeInterval(-7 * 60), status: "LIVE")
        let upcoming = makeSession(id: "upcoming", startsAt: now.addingTimeInterval(120 * 60))
        let result = StudentSession.nextForHome(from: [ongoing, upcoming], now: now)
        XCTAssertEqual(result?.id, "upcoming")
    }

    func testNextForHomeReturnsNilWhenOnlyCurrentSessions() {
        let now = Date()
        let ongoing = makeSession(id: "ongoing", startsAt: now.addingTimeInterval(-30 * 60), status: "LIVE")
        let result = StudentSession.nextForHome(from: [ongoing], now: now)
        XCTAssertNil(result)
    }

    // MARK: - Home aggregate (GET /v1/student/home)

    /// Mirrors the production date strategy (APIClient): ISO-8601 with or
    /// without fractional seconds, so `starts_at` parses like it would live.
    private func homeDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        let isoMs = ISO8601DateFormatter(); isoMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        dec.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            if let v = isoMs.date(from: s) { return v }
            if let v = iso.date(from: s) { return v }
            throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(), debugDescription: "bad date \(s)")
        }
        return dec
    }

    func testStudentHomePayloadDecoding() throws {
        let json = """
        {
          "greeting": {
            "first_name": "Noor",
            "display_name": "Noor Rahman",
            "initials": "NR",
            "unread_notifications_count": 2
          },
          "continue_learning": [
            {
              "id": "00000000-0000-0000-0000-000000000023",
              "title_en": "UX/UI Fundamentals",
              "title_ar": "أساسيات",
              "instructor_name": "Dr. Layla Hassan",
              "progress_pct": 84.0,
              "lesson_count": 32,
              "completed_lesson_count": 27,
              "next_lesson_title_en": "Motion Principles",
              "next_lesson_title_ar": "مبادئ الحركة",
              "total_duration_seconds": 54600
            }
          ],
          "recommended_courses": [],
          "explore_instructors": [
            {
              "instructor_id": "55555555-0000-0000-0000-000000000001",
              "display_name": "Prof. Sara Nasser",
              "professional_title_en": "Digital Marketing",
              "students_count": 1200,
              "courses_count": 3,
              "rating_avg": 4.7,
              "years_experience": 5
            }
          ],
          "next_session": {
            "id": "66666666-0000-0000-0000-000000000001",
            "title_en": "Session — UX/UI",
            "title_ar": "جلسة",
            "starts_at": "2026-06-25T15:00:00Z",
            "duration_minutes": 60,
            "status": "SCHEDULED",
            "instructor_name": "Dr. Layla Hassan",
            "can_join": true
          }
        }
        """.data(using: .utf8)!

        let home = try homeDecoder().decode(StudentHomePayload.self, from: json)

        XCTAssertEqual(home.greeting.firstName, "Noor")
        XCTAssertEqual(home.greeting.initials, "NR")
        XCTAssertEqual(home.greeting.unreadNotificationsCount, 2)

        XCTAssertEqual(home.continueLearning.count, 1)
        let course = home.continueLearning[0]
        XCTAssertEqual(course.progressPct, 84.0, accuracy: 0.001)
        XCTAssertEqual(course.totalDurationSeconds, 54600)
        XCTAssertEqual(course.localizedNextLessonTitle(locale: "en"), "Motion Principles")

        XCTAssertTrue(home.recommendedCourses.isEmpty)

        XCTAssertEqual(home.exploreInstructors.count, 1)
        XCTAssertEqual(home.exploreInstructors[0].studentsCount, 1200)
        XCTAssertEqual(home.exploreInstructors[0].ratingAvg ?? 0, 4.7, accuracy: 0.001)

        XCTAssertEqual(home.nextSession?.titleEn, "Session — UX/UI")
        XCTAssertEqual(home.nextSession?.durationMinutes, 60)
        XCTAssertTrue(home.nextSession?.canJoin ?? false)
    }

    func testStudentHomePayloadNullNextSessionAndEmptyArrays() throws {
        let json = """
        {
          "greeting": { "first_name": "Noor", "display_name": "Noor", "initials": "N", "unread_notifications_count": 0 }
        }
        """.data(using: .utf8)!

        let home = try homeDecoder().decode(StudentHomePayload.self, from: json)
        XCTAssertEqual(home.greeting.initials, "N")
        XCTAssertTrue(home.continueLearning.isEmpty)
        XCTAssertTrue(home.recommendedCourses.isEmpty)
        XCTAssertTrue(home.exploreInstructors.isEmpty)
        XCTAssertNil(home.nextSession)
    }

    /// total_duration_seconds defaults to 0 when an older backend omits it.
    func testEnrolledCourseToleratesMissingTotalDuration() throws {
        let json = """
        {
          "id": "1", "title_en": "T", "title_ar": "T",
          "instructor_name": "I", "progress_pct": 50.0,
          "lesson_count": 10, "completed_lesson_count": 5
        }
        """.data(using: .utf8)!

        let course = try JSONDecoder().decode(EnrolledCourse.self, from: json)
        XCTAssertEqual(course.totalDurationSeconds, 0)
        XCTAssertEqual(course.progressPct, 50.0, accuracy: 0.001)
    }
}
