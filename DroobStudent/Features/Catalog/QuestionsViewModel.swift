import Foundation
import SwiftUI

// MARK: - Filter chip
//
// Mirrors the backend `QuestionFilter` enum (sent over the wire as
// lowercased rawValue). Kept iOS-side so the chip row can drive an
// async load without inventing parallel state.

enum QuestionsFilter: String, CaseIterable, Hashable {
    case all, answered, unanswered, mine

    var label: String {
        switch self {
        case .all:        return L10n.qaScreenFilterAll
        case .answered:   return L10n.qaScreenFilterAnswered
        case .unanswered: return L10n.qaScreenFilterUnanswered
        case .mine:       return L10n.qaScreenFilterMine
        }
    }

    /// Wire token sent as the `filter` query param. The controller
    /// normalises to uppercase, so either case works — we send the
    /// lowercased rawValue for readability in logs.
    var apiValue: String { rawValue }
}

// MARK: - View model

@MainActor
final class QuestionsViewModel: ObservableObject {
    let courseId: String

    @Published var questions: [CourseQuestionItem] = []
    @Published var totalCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasNextPage: Bool = false
    @Published var errorMessage: String? = nil
    @Published var filter: QuestionsFilter = .all

    private var currentPage: Int = 0
    private let pageSize: Int = 20

    init(courseId: String) {
        self.courseId = courseId
    }

    /// Reload from page 0 under the current filter. Used by both first
    /// paint and chip-switch — chip changes update `filter` then call
    /// this, so the URL always reflects what the chip claims.
    func loadInitial() async {
        await fetchPage(0)
    }

    /// Switch chip + reload. No-op when the requested filter already
    /// matches the active one so re-tapping the same chip doesn't
    /// re-fetch.
    func applyFilter(_ next: QuestionsFilter) async {
        if filter == next { return }
        filter = next
        await fetchPage(0)
    }

    func loadMore() async {
        guard hasNextPage, !isLoadingMore else { return }
        await fetchPage(currentPage + 1)
    }

    /// Submit a new question and prepend it to the local list. Returns
    /// `true` on success so the compose sheet can dismiss. We don't
    /// re-fetch from page 0 because that would bump the user out of
    /// any pagination they've done — instead we mutate the in-memory
    /// list and let the next natural reload reconcile.
    func submit(body: String) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/questions",
            method: .POST,
            body: SubmitQuestionBody(body: trimmed))
        do {
            let created: CourseQuestionItem =
                try await AuthInterceptor.shared.execute(request)
            // Prepend so the new row shows immediately at the top
            // regardless of the active filter (a brand-new question
            // belongs in "All" and "Mine" but not "Answered" — we
            // still prepend; the next reload will reconcile).
            questions.insert(created, at: 0)
            totalCount += 1
            return true
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = error.errorDescription
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: Internal

    private func fetchPage(_ page: Int) async {
        if page == 0 {
            isLoading = true
            errorMessage = nil
        } else {
            isLoadingMore = true
        }
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/questions",
            method: .GET,
            queryItems: [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "size", value: "\(pageSize)"),
                URLQueryItem(name: "filter", value: filter.apiValue)
            ])
        do {
            let result: SpringPage<CourseQuestionItem> =
                try await AuthInterceptor.shared.execute(request)
            if page == 0 {
                questions = result.content
            } else {
                questions.append(contentsOf: result.content)
            }
            totalCount = result.totalElements
            currentPage = result.number
            hasNextPage = result.hasNextPage
        } catch let error where APIClient.isCancellationError(error) {
            // Pull-to-refresh task cancelled — silently bail.
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        isLoadingMore = false
    }

    /// Wire body for `POST /questions`. Matches the Java
    /// `SubmitQuestionRequest` record: a single non-blank `body` field.
    private struct SubmitQuestionBody: Encodable {
        let body: String
    }
}
