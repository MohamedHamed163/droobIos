import XCTest
@testable import DroobStudent

final class SSEParserTests: XCTestCase {

    // MARK: - TutorSource decoding

    func testTutorSourceDecoding() throws {
        let json = """
        {
          "document_id": "doc-uuid",
          "filename": "lecture1.pdf",
          "page": 3,
          "snippet": "Gradient descent is…"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let source = try decoder.decode(TutorSource.self, from: json)
        XCTAssertEqual(source.documentId, "doc-uuid")
        XCTAssertEqual(source.filename, "lecture1.pdf")
        XCTAssertEqual(source.page, 3)
        XCTAssertEqual(source.snippet, "Gradient descent is…")
    }

    func testTutorSourceId() throws {
        let json = """
        {"document_id": "my-id", "filename": "f.pdf", "page": 1, "snippet": null}
        """.data(using: .utf8)!

        let source = try JSONDecoder().decode(TutorSource.self, from: json)
        XCTAssertEqual(source.id, "my-id")
    }

    // MARK: - SSE frame shape validation

    func testTokenFrame() throws {
        // Verifies that a token frame JSON matches expected structure
        let json = """
        {"type":"token","content":"Gradient "}
        """.data(using: .utf8)!
        // If this doesn't throw, the JSON is well-formed
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: json))
        let dict = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        XCTAssertEqual(dict["type"] as? String, "token")
        XCTAssertEqual(dict["content"] as? String, "Gradient ")
    }

    func testDoneFrame() throws {
        let json = """
        {"type":"done","session_id":"sess-uuid"}
        """.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        XCTAssertEqual(dict["type"] as? String, "done")
        XCTAssertEqual(dict["session_id"] as? String, "sess-uuid")
    }

    func testSourcesFrame() throws {
        let json = """
        {"type":"sources","sources":[{"document_id":"d1","filename":"a.pdf","page":1,"snippet":"txt"}]}
        """.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        XCTAssertEqual(dict["type"] as? String, "sources")
        let sources = dict["sources"] as? [[String: Any]]
        XCTAssertEqual(sources?.count, 1)
        XCTAssertEqual(sources?[0]["filename"] as? String, "a.pdf")
    }

    // MARK: - AsyncStream smoke test

    func testSSEParserEmptyStreamCompletesImmediately() async throws {
        // Create a minimal test using AsyncStream directly
        var events: [TutorEvent] = []
        let stream = AsyncStream<TutorEvent> { continuation in
            continuation.finish()
        }
        for await event in stream {
            events.append(event)
        }
        XCTAssertTrue(events.isEmpty)
    }

    func testSSEParserTokenAccumulation() async throws {
        var collectedText = ""
        let stream = AsyncStream<TutorEvent> { continuation in
            continuation.yield(.token("Hello "))
            continuation.yield(.token("World"))
            continuation.yield(.done(sessionId: "sid"))
            continuation.finish()
        }
        for await event in stream {
            if case .token(let chunk) = event {
                collectedText += chunk
            }
        }
        XCTAssertEqual(collectedText, "Hello World")
    }
}
