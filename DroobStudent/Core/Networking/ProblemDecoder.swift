import Foundation

// MARK: - ProblemDecoder
// Maps raw HTTP errors / ProblemEnvelope to typed DroobError values.

enum ProblemDecoder {
    static func decode(data: Data, statusCode: Int, decoder: JSONDecoder = JSONDecoder()) -> DroobError {
        if let envelope = try? decoder.decode(ProblemEnvelope.self, from: data) {
            return map(problem: envelope.error, statusCode: statusCode)
        }
        return httpFallback(statusCode: statusCode)
    }

    static func map(problem: ProblemDetail, statusCode: Int) -> DroobError {
        switch problem.code {
        case "UNAUTHENTICATED":
            return .unauthenticated(message: problem.message, messageAr: problem.messageAr)
        case "FORBIDDEN":
            // Carry the server's bilingual problem detail through so
            // call sites can show the domain reason (e.g. "You were
            // removed from this room by a host and can't rejoin")
            // instead of the generic "Access denied" fallback. Same
            // shape as `.notFound` / `.unauthenticated`.
            return .forbidden(message: problem.message,
                              messageAr: problem.messageAr)
        case "NOT_FOUND":
            // Carry the server's bilingual problem detail through so
            // call sites can show the domain reason (e.g. "Incorrect
            // passcode") instead of the generic "Resource not found"
            // fallback. The fallback still kicks in when the server
            // didn't include a message — same shape as
            // `.unauthenticated`.
            return .notFound(message: problem.message,
                             messageAr: problem.messageAr)
        case "CONFLICT":
            return .conflict(message: problem.message, messageAr: problem.messageAr)
        case "INTERNAL_ERROR":
            return .serverError(message: problem.message, messageAr: problem.messageAr)
        case "VALIDATION_ERROR":
            return .httpError(statusCode: statusCode, problem: problem)
        case "PLAN_QUOTA_EXCEEDED":
            return .httpError(statusCode: statusCode, problem: problem)
        default:
            return .httpError(statusCode: statusCode, problem: problem)
        }
    }

    static func httpFallback(statusCode: Int) -> DroobError {
        switch statusCode {
        case 401: return .unauthenticated(message: nil, messageAr: nil)
        case 403: return .forbidden(message: nil, messageAr: nil)
        case 404: return .notFound(message: nil, messageAr: nil)
        case 409: return .conflict(message: "Conflict", messageAr: nil)
        case 500...: return .serverError(message: "Server error", messageAr: nil)
        default: return .unknown
        }
    }
}
