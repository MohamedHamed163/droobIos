import Foundation

// MARK: - TutorEvent

enum TutorEvent {
    case token(String)
    case sources([TutorSource])
    case done(sessionId: String)
    case error(String)
}

struct TutorSource: Decodable, Identifiable, Equatable {
    let documentId: String?
    let filename: String?
    let page: Int?
    let snippet: String?

    var id: String { documentId ?? "\(filename ?? "")-\(page ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case filename, page, snippet
    }
}

// MARK: - Raw SSE frame shapes

private struct SSEFrame: Decodable {
    let type: String
    let content: String?
    let sources: [TutorSource]?
    let sessionId: String?
    let message: String?
    enum CodingKeys: String, CodingKey {
        case type, content, sources, message
        case sessionId = "session_id"
    }
}

// MARK: - SSEParser

enum SSEParser {
    /// Parse URLSession.AsyncBytes line-by-line and emit TutorEvent values.
    static func stream(from bytes: URLSession.AsyncBytes) -> AsyncStream<TutorEvent> {
        AsyncStream { continuation in
            Task {
                let decoder = JSONDecoder()

                do {
                    for try await line in bytes.lines {
                        if line.hasPrefix("data:") {
                            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if payload == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            if let data = payload.data(using: .utf8),
                               let frame = try? decoder.decode(SSEFrame.self, from: data) {
                                if let event = mapFrame(frame) {
                                    continuation.yield(event)
                                    if case .done = event {
                                        continuation.finish()
                                        return
                                    }
                                    if case .error = event {
                                        continuation.finish()
                                        return
                                    }
                                }
                            }
                        } else {
                            // blank line or comment — ignore
                            continue
                        }
                    }
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                }
                continuation.finish()
            }
        }
    }

    private static func mapFrame(_ frame: SSEFrame) -> TutorEvent? {
        switch frame.type {
        case "token":
            return .token(frame.content ?? "")
        case "sources":
            return .sources(frame.sources ?? [])
        case "done":
            return .done(sessionId: frame.sessionId ?? "")
        case "error":
            return .error(frame.message ?? "Stream error")
        default:
            return nil
        }
    }
}
