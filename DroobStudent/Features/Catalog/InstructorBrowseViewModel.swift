import Foundation
import SwiftUI

// MARK: - Model

/// One row in the instructor-first Explore list ("Browse N expert
/// instructors"). Mirrors the backend `StudentInstructorSummary` record —
/// identity plus the stats rolled up across the instructor's published
/// courses.
struct StudentInstructorSummary: Decodable, Identifiable, Equatable {
    let instructorId: String
    let displayName: String
    let professionalTitleEn: String?
    let professionalTitleAr: String?
    let avatarUrl: String?
    let studentsCount: Int
    let coursesCount: Int
    /// Students-weighted average (0…5), or `nil` when no course has ratings.
    let ratingAvg: Double?
    /// Whole years since the instructor's account was created.
    let yearsExperience: Int
    /// Bio the instructor set in Studio settings — shown on the browse card
    /// in place of the stat panel (2026-07). Nullable; both may be absent.
    let bioEn: String?
    let bioAr: String?

    var id: String { instructorId }

    enum CodingKeys: String, CodingKey {
        case instructorId = "instructor_id"
        case displayName = "display_name"
        case professionalTitleEn = "professional_title_en"
        case professionalTitleAr = "professional_title_ar"
        case avatarUrl = "avatar_url"
        case studentsCount = "students_count"
        case coursesCount = "courses_count"
        case ratingAvg = "rating_avg"
        case yearsExperience = "years_experience"
        case bioEn = "bio_en"
        case bioAr = "bio_ar"
    }

    func localizedTitle(locale: String) -> String? {
        L10n.localized(locale, ar: professionalTitleAr, en: professionalTitleEn)
    }

    /// Bio for the current language, falling back to the other language when
    /// one side is empty. `nil` when the instructor set no bio at all.
    func localizedBio(locale: String) -> String? {
        let primary = locale == "ar" ? bioAr : bioEn
        let fallback = locale == "ar" ? bioEn : bioAr
        if let p = primary, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return p
        }
        if let f = fallback, !f.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return f
        }
        return nil
    }

    /// Figma renders "10+ years"; cap the display at 10.
    var formattedYears: String {
        yearsExperience >= 10 ? "10+" : "\(yearsExperience)"
    }
}

// MARK: - View model

@MainActor
final class InstructorBrowseViewModel: ObservableObject {
    @Published var instructors: [StudentInstructorSummary] = []
    @Published var totalCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String? = nil
    @Published var hasNextPage: Bool = false

    /// Top courses per instructor, lazily fetched the first time a card is
    /// expanded. Keyed by `instructorId`. The card renders the first ~3.
    @Published var coursesByInstructor: [String: [CourseSummary]] = [:]
    /// Instructor ids whose course list is currently in flight — drives the
    /// inline spinner inside the expanded card.
    @Published var loadingCourses: Set<String> = []

    private var currentPage: Int = 0
    private let pageSize: Int = 20
    private var hasLoadedOnce = false

    /// Server-side search text currently applied to the list (sent as the
    /// `q` query param — backend matches name + professional title EN/AR).
    /// Empty = unfiltered browse.
    private(set) var activeQuery: String = ""
    /// In-flight debounce for `updateQuery(_:)` — cancelled by every new
    /// keystroke so only the final pause triggers a fetch.
    private var searchDebounceTask: Task<Void, Never>? = nil

    func loadInitial() async {
        await fetchPage(0)
    }

    func loadMore() async {
        guard hasNextPage, !isLoadingMore else { return }
        await fetchPage(currentPage + 1)
    }

    /// Debounced (~300 ms) server-side search. Called on every keystroke of
    /// the Explore search field; resets pagination and re-fetches page 0
    /// with the new `q` once the user pauses typing. The server response is
    /// the source of truth, so instructors beyond the loaded pages are
    /// findable.
    func updateQuery(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        searchDebounceTask?.cancel()
        if trimmed == activeQuery { return }
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }
            self.activeQuery = trimmed
            await self.fetchPage(0)
        }
    }

    /// Lazily loads the instructor's courses (via the full profile endpoint)
    /// the first time their card is expanded. No-op once cached or in flight.
    func loadCourses(for instructorId: String) async {
        if coursesByInstructor[instructorId] != nil { return }
        if loadingCourses.contains(instructorId) { return }
        loadingCourses.insert(instructorId)

        let request = APIRequest(path: "/v1/student/instructors/\(instructorId)")
        do {
            let profile: InstructorPublicProfile =
                try await AuthInterceptor.shared.execute(request)
            coursesByInstructor[instructorId] = profile.courses
        } catch let error where APIClient.isCancellationError(error) {
            // leave uncached so a later expand retries
        } catch let error as DroobError {
            if case .unauthenticated(_, _) = error {
                await AuthSession.shared.handleUnauthenticated()
            }
        } catch {
            // swallow — the expanded card degrades to "no courses"
        }
        loadingCourses.remove(instructorId)
    }

    private func fetchPage(_ page: Int) async {
        if page == 0 {
            if !hasLoadedOnce { isLoading = true }
            errorMessage = nil
        } else {
            isLoadingMore = true
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "size", value: "\(pageSize)")
        ]
        if !activeQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: activeQuery))
        }
        let request = APIRequest(
            path: "/v1/student/instructors",
            method: .GET,
            queryItems: queryItems
        )

        do {
            let result: SpringPage<StudentInstructorSummary> =
                try await AuthInterceptor.shared.execute(request)
            if page == 0 {
                instructors = result.content
            } else {
                instructors.append(contentsOf: result.content)
            }
            totalCount = result.totalElements
            currentPage = result.number
            hasNextPage = result.hasNextPage
            hasLoadedOnce = true
        } catch let error where APIClient.isCancellationError(error) {
            isLoading = false
            isLoadingMore = false
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
        isLoadingMore = false
    }
}
