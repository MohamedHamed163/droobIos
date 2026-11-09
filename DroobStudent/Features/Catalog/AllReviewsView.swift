import SwiftUI

// MARK: - All reviews list
//
// Pushed from the inline "See all X reviews" link on the course detail
// screen. Fetches paginated reviews from `/v1/student/courses/{id}/reviews`
// and reuses the same review-card visuals as the inline preview so the
// list feels like a natural expansion rather than a new screen.

struct AllReviewsView: View {
    let courseId: String
    let courseTitle: String

    @StateObject private var vm: AllReviewsViewModel
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @Environment(\.dismiss) private var dismiss

    init(courseId: String, courseTitle: String) {
        self.courseId = courseId
        self.courseTitle = courseTitle
        _vm = StateObject(wrappedValue: AllReviewsViewModel(courseId: courseId))
    }

    private var ar: Bool { appLocale == "ar" }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Color.clear.frame(height: 8)
                    Text(courseTitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(MyCoursesPalette.muted)
                    if vm.isLoading && vm.reviews.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            MCSkeletonBlock(height: 96, cornerRadius: 14)
                        }
                    } else if vm.reviews.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.reviews) { review in
                            reviewCard(review)
                        }
                        if vm.hasNextPage {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(Color.droobGold)
                                    .onAppear { Task { await vm.loadMore() } }
                                Spacer()
                            }
                            .padding(.vertical, 16)
                        }
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle(L10n.courseDetailAllReviewsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadInitial() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "star")
                .font(.system(size: 32))
                .foregroundColor(MyCoursesPalette.muted)
            Text(L10n.courseDetailAllReviewsEmpty)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func reviewCard(_ review: CourseReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ReviewAvatar(name: review.authorName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.authorName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: i < review.stars ? "star.fill" : "star")
                                .font(.system(size: 10))
                                .foregroundColor(Color.droobGold)
                        }
                        Text("·").foregroundColor(MyCoursesPalette.muted)
                        // Use `updatedAt` so the relative-time label
                        // reflects the most recent edit (equal to
                        // `createdAt` for unedited reviews) — see
                        // CourseReviewItem doc comments.
                        Text(ReviewAgeFormatter.relative(from: review.updatedAt))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(MyCoursesPalette.muted)
                    }
                }
                Spacer()
            }
            if let body = review.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }
}

// MARK: - View model (paginated reviews)

@MainActor
final class AllReviewsViewModel: ObservableObject {
    @Published var reviews: [CourseReviewItem] = []
    @Published var isLoading: Bool = false
    @Published var hasNextPage: Bool = false
    @Published var errorMessage: String? = nil

    private let courseId: String
    private var currentPage: Int = 0
    private let pageSize: Int = 20

    init(courseId: String) {
        self.courseId = courseId
    }

    func loadInitial() async {
        currentPage = 0
        await fetchPage(0)
    }

    func loadMore() async {
        guard hasNextPage, !isLoading else { return }
        await fetchPage(currentPage + 1)
    }

    private func fetchPage(_ page: Int) async {
        isLoading = true
        let request = APIRequest(
            path: "/v1/student/courses/\(courseId)/reviews",
            method: .GET,
            queryItems: [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "size", value: "\(pageSize)")
            ])
        do {
            let result: SpringPage<CourseReviewItem> = try await AuthInterceptor.shared.execute(request)
            if page == 0 {
                reviews = result.content
            } else {
                reviews.append(contentsOf: result.content)
            }
            currentPage = result.number
            hasNextPage = result.hasNextPage
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
}
