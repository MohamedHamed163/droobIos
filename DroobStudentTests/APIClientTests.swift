import XCTest
@testable import DroobStudent

final class APIClientTests: XCTestCase {

    // MARK: - ApiEnvelope decoding

    func testDecodeApiEnvelope() throws {
        let json = """
        {
          "data": {"access_token": "abc", "refresh_token": "xyz", "expires_in": 900},
          "meta": {"request_id": "req-1", "server_time": "2024-01-01T00:00:00Z"}
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ApiEnvelope<AuthTokens>.self, from: json)
        XCTAssertEqual(envelope.data.accessToken, "abc")
        XCTAssertEqual(envelope.data.refreshToken, "xyz")
        XCTAssertEqual(envelope.data.expiresIn, 900)
        XCTAssertEqual(envelope.meta?.requestId, "req-1")
    }

    func testDecodeProblemEnvelope() throws {
        let json = """
        {
          "error": {
            "code": "NOT_FOUND",
            "message": "Course not found",
            "message_ar": "الدورة غير موجودة",
            "details": {},
            "field": null,
            "retryable": false
          },
          "meta": {"request_id": "req-2", "server_time": "2024-01-01T00:00:00Z"}
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ProblemEnvelope.self, from: json)
        XCTAssertEqual(envelope.error.code, "NOT_FOUND")
        XCTAssertEqual(envelope.error.message, "Course not found")
        XCTAssertEqual(envelope.error.messageAr, "الدورة غير موجودة")
        XCTAssertFalse(envelope.error.retryable)
    }

    // MARK: - ProblemDecoder mapping

    func testProblemDecoderMapsNotFound() throws {
        let json = """
        {
          "error": {"code": "NOT_FOUND", "message": "Not found", "retryable": false},
          "meta": {}
        }
        """.data(using: .utf8)!

        let error = ProblemDecoder.decode(data: json, statusCode: 404)
        if case .notFound = error {} else {
            XCTFail("Expected .notFound but got \(error)")
        }
    }

    func testProblemDecoderMapsUnauthenticated() throws {
        let json = """
        {
          "error": {"code": "UNAUTHENTICATED", "message": "Unauthorized", "retryable": false},
          "meta": {}
        }
        """.data(using: .utf8)!

        let error = ProblemDecoder.decode(data: json, statusCode: 401)
        if case .unauthenticated(_, _) = error {} else {
            XCTFail("Expected .unauthenticated but got \(error)")
        }
    }

    func testProblemDecoderMapsConflict() throws {
        let json = """
        {
          "error": {"code": "CONFLICT", "message": "Email already registered", "retryable": false},
          "meta": {}
        }
        """.data(using: .utf8)!

        let error = ProblemDecoder.decode(data: json, statusCode: 409)
        if case .conflict(let msg) = error {
            XCTAssertEqual(msg, "Email already registered")
        } else {
            XCTFail("Expected .conflict but got \(error)")
        }
    }

    // MARK: - DroobError descriptions

    func testDroobErrorDescriptions() {
        XCTAssertNotNil(DroobError.notFound(message: nil, messageAr: nil).errorDescription)
        XCTAssertNotNil(DroobError.forbidden(message: nil, messageAr: nil).errorDescription)
        XCTAssertNotNil(DroobError.unauthenticated(message: nil, messageAr: nil).errorDescription)
        XCTAssertNotNil(DroobError.invalidURL.errorDescription)
        XCTAssertNotNil(DroobError.unknown.errorDescription)
    }

    // MARK: - Spring Page decoding

    func testDecodeSpringPage() throws {
        let json = """
        {
          "data": {
            "content": [
              {
                "id": "uuid-1",
                "title_en": "ML Course",
                "title_ar": "دورة الذكاء",
                "subtitle_en": "Learn ML",
                "subtitle_ar": "تعلم الذكاء",
                "cover_url": null,
                "instructor_name": "Droob",
                "price_cents": 14900,
                "currency": "SAR",
                "enrolled": false
              }
            ],
            "totalElements": 1,
            "totalPages": 1,
            "number": 0,
            "size": 20
          },
          "meta": {}
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ApiEnvelope<SpringPage<CourseSummary>>.self, from: json)
        XCTAssertEqual(envelope.data.content.count, 1)
        XCTAssertEqual(envelope.data.content[0].titleEn, "ML Course")
        XCTAssertEqual(envelope.data.totalElements, 1)
        XCTAssertFalse(envelope.data.hasNextPage)
    }

    // MARK: - Playback response decoding (playback_kind)

    /// The minimum payload the playback endpoint has always returned. Extra
    /// fields are appended per-test.
    private func playbackJSON(extra: String = "") -> Data {
        """
        {
          "manifest_url": "https://cdn.example.com/v/1/master.m3u8",
          "attendees_count": 12\(extra)
        }
        """.data(using: .utf8)!
    }

    /// A server that predates `playback_kind` must keep working: absent field
    /// means HLS, which is the only thing those servers ever served.
    func testPlaybackKindDefaultsToHLSWhenAbsent() throws {
        let response = try JSONDecoder().decode(
            PlaybackResponse.self, from: playbackJSON())
        XCTAssertNil(response.playbackKindRaw)
        XCTAssertEqual(response.playbackKind, .hls)
        XCTAssertTrue(response.playbackKind.isAdaptive)
    }

    func testPlaybackKindMP4IsDecodedAndNotAdaptive() throws {
        let response = try JSONDecoder().decode(
            PlaybackResponse.self,
            from: playbackJSON(extra: #", "playback_kind": "MP4""#))
        XCTAssertEqual(response.playbackKind, .mp4)
        XCTAssertFalse(response.playbackKind.isAdaptive)
    }

    func testPlaybackKindHLSIsDecoded() throws {
        let response = try JSONDecoder().decode(
            PlaybackResponse.self,
            from: playbackJSON(extra: #", "playback_kind": "HLS""#))
        XCTAssertEqual(response.playbackKind, .hls)
    }

    /// An unknown future value must neither fail the decode nor be treated as
    /// progressive — fall back to the historical HLS behaviour.
    func testUnknownPlaybackKindFallsBackToHLS() throws {
        let response = try JSONDecoder().decode(
            PlaybackResponse.self,
            from: playbackJSON(extra: #", "playback_kind": "DASH""#))
        XCTAssertEqual(response.playbackKind, .hls)
    }

    /// Case-insensitive so a lowercase spelling from any other producer of
    /// this payload still maps.
    func testLowercasePlaybackKindIsAccepted() throws {
        let response = try JSONDecoder().decode(
            PlaybackResponse.self,
            from: playbackJSON(extra: #", "playback_kind": "mp4""#))
        XCTAssertEqual(response.playbackKind, .mp4)
    }

    /// `playback_kind` is orthogonal to `video_status` — a passthrough video
    /// still reports READY, and the pre-READY states still gate the player.
    func testPlaybackKindCoexistsWithVideoStatus() throws {
        let response = try JSONDecoder().decode(
            PlaybackResponse.self,
            from: playbackJSON(
                extra: #", "playback_kind": "MP4", "video_status": "READY""#))
        XCTAssertEqual(response.playbackKind, .mp4)
        XCTAssertEqual(response.videoStatus, .ready)
    }
}
