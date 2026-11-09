import Foundation
import SwiftUI

// MARK: - Model

/// One row in the instructor Ratings & Reviews list. Mirrors the backend
/// `InstructorReviewDto` — identical shape to `CourseReviewItem` but kept
/// distinct so the instructor-scoped surface can evolve independently.
struct InstructorReview: Decodable, Identifiable, Equatable {
    let id: String
    let authorName: String
    let authorAvatarUrl: String?
    let stars: Int
    let body: String?
    let createdAt: Date
    let updatedAt: Date
    /// True when this row was authored by the signed-in student. Drives the
    /// "Your review" badge and the edit/delete affordances on the profile.
    let isMine: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case authorName = "author_name"
        case authorAvatarUrl = "author_avatar_url"
        case stars
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isMine = "is_mine"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        authorName      = try c.decode(String.self, forKey: .authorName)
        authorAvatarUrl = try c.decodeIfPresent(String.self, forKey: .authorAvatarUrl)
        stars           = try c.decode(Int.self, forKey: .stars)
        body            = try c.decodeIfPresent(String.self, forKey: .body)
        let created     = try c.decode(Date.self, forKey: .createdAt)
        createdAt       = created
        updatedAt       = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? created
        isMine          = try c.decodeIfPresent(Bool.self, forKey: .isMine) ?? false
    }
}

// MARK: - View model

@MainActor
final class InstructorReviewsViewModel: ObservableObject {
    let instructorId: String

    @Published var reviews: [InstructorReview] = []
    @Published var distribution: RatingDistribution = .empty
    @Published var isLoading: Bool = false
    @Published var hasNextPage: Bool = false
    @Published var errorMessage: String? = nil
    /// The caller's own existing review, surfaced so the composer opens in
    /// edit mode (the backend upserts, so there's only ever one per pair).
    @Published var myReview: InstructorReview? = nil

    private var currentPage: Int = 0
    private let pageSize: Int = 20
    private var hasLoadedOnce = false

    init(instructorId: String) {
        self.instructorId = instructorId
    }

    func loadInitial() async {
        if hasLoadedOnce { return }
        await loadSummary()
        await fetchPage(0)
        hasLoadedOnce = true
    }

    func reload() async {
        await loadSummary()
        await fetchPage(0)
    }

    func loadMore() async {
        guard hasNextPage, !isLoading else { return }
        await fetchPage(currentPage + 1)
    }

    private func loadSummary() async {
        let request = APIRequest(
            path: "/v1/student/instructors/\(instructorId)/reviews/summary")
        if let result: RatingDistribution = try? await AuthInterceptor.shared.execute(request) {
            distribution = result
        }
    }

    private func fetchPage(_ page: Int) async {
        isLoading = true
        let request = APIRequest(
            path: "/v1/student/instructors/\(instructorId)/reviews",
            method: .GET,
            queryItems: [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "size", value: "\(pageSize)")
            ])
        do {
            let result: SpringPage<InstructorReview> =
                try await AuthInterceptor.shared.execute(request)
            if page == 0 {
                reviews = result.content
                // The backend flags the caller's own row; surface it so the
                // profile can lift it out, badge it, and open the composer in
                // edit mode. Page 0 always carries it (newest-activity first).
                myReview = result.content.first(where: { $0.isMine }) ?? myReview
            } else {
                reviews.append(contentsOf: result.content)
            }
            currentPage = result.number
            hasNextPage = result.hasNextPage
        } catch let error where APIClient.isCancellationError(error) {
            isLoading = false
            return
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
    }

    private struct SubmitBody: Encodable {
        let stars: Int
        let body: String?
    }

    /// Upserts the caller's review and refreshes the list + histogram so
    /// the new/edited row and the recomputed average appear without a
    /// manual reload. Returns `true` on success.
    func submit(stars: Int, body: String?) async -> Bool {
        let request = APIRequest(
            path: "/v1/student/instructors/\(instructorId)/reviews",
            method: .POST,
            body: SubmitBody(stars: stars, body: body))
        do {
            let saved: InstructorReview = try await AuthInterceptor.shared.execute(request)
            myReview = saved
            await reload()
            return true
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            }
            return false
        } catch {
            return false
        }
    }

    /// Deletes the caller's review and refreshes the list + histogram so the
    /// row and the recomputed average drop away immediately. Returns `true`
    /// on success.
    func delete() async -> Bool {
        let request = APIRequest(
            path: "/v1/student/instructors/\(instructorId)/reviews",
            method: .DELETE)
        do {
            try await AuthInterceptor.shared.executeVoid(request)
            myReview = nil
            await reload()
            return true
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            }
            return false
        } catch {
            return false
        }
    }
}
