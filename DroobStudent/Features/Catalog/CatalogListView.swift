import SwiftUI

struct CatalogListView: View {
    @StateObject private var viewModel = CatalogViewModel()
    @Environment(\.appLocale) private var locale
    @Binding var deepLinkCourseId: String?
    @State private var navigateToCourseId: String? = nil
    @State private var query: String = ""

    init(deepLinkCourseId: Binding<String?> = .constant(nil)) {
        _deepLinkCourseId = deepLinkCourseId
    }

    private var filteredCourses: [CourseSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return viewModel.courses }
        return viewModel.courses.filter {
            $0.localizedTitle(locale: locale).lowercased().contains(trimmed)
                || $0.instructorName.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleBlock
                    searchField
                    content
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .droobBounceBasedOnSize()
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if viewModel.courses.isEmpty {
                await viewModel.loadInitial()
            }
        }
        .refreshable { await viewModel.loadInitial() }
        .onChange(of: deepLinkCourseId) { newId in
            if let id = newId {
                navigateToCourseId = id
                deepLinkCourseId = nil
            }
        }
        .background(
            NavigationLink(
                destination: Group {
                    if let id = navigateToCourseId {
                        CourseDetailView(courseId: id)
                    }
                },
                isActive: Binding(
                    get: { navigateToCourseId != nil },
                    set: { if !$0 { navigateToCourseId = nil } }
                )
            ) { EmptyView() }
        )
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text(L10n.catalogTitlePrefix)
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)
            + Text(L10n.catalogTitleAccent)
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(Color.droobGold))

            Text(L10n.catalogSubtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MyCoursesPalette.muted)
            TextField("", text: $query, prompt: Text(L10n.catalogSearchPlaceholder)
                .foregroundColor(MyCoursesPalette.muted))
                .font(.system(size: 14))
                .foregroundColor(MyCoursesPalette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(MyCoursesPalette.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(MyCoursesPalette.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            CatalogSkeletonView()
                .transaction { $0.animation = nil }
        } else if let error = viewModel.errorMessage, viewModel.courses.isEmpty {
            ErrorBanner(message: error) {
                Task { await viewModel.loadInitial() }
            }
            .padding(.top, 32)
        } else if viewModel.courses.isEmpty {
            emptyState
        } else if filteredCourses.isEmpty {
            searchEmptyState
        } else {
            courseList
        }
    }

    private var courseList: some View {
        LazyVStack(spacing: 16) {
            ForEach(filteredCourses) { course in
                NavigationLink {
                    CourseDetailView(courseId: course.id)
                } label: {
                    CourseCard(course: course, locale: locale)
                }
                .buttonStyle(.plain)
            }

            if viewModel.hasNextPage && query.isEmpty {
                if viewModel.isLoadingMore {
                    ProgressView()
                        .tint(Color.droobGold)
                        .padding(.vertical, 12)
                } else {
                    Button {
                        Task { await viewModel.loadMore() }
                    } label: {
                        Text(L10n.loadMore)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.droobGold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .overlay(Capsule().stroke(Color.droobGold.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .onAppear { Task { await viewModel.loadMore() } }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(MyCoursesPalette.surface)
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(MyCoursesPalette.stroke, lineWidth: 1))
                Image(systemName: "books.vertical")
                    .font(.system(size: 34))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            VStack(spacing: 8) {
                Text(L10n.catalogEmptyTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                Text(L10n.catalogEmptyBody)
                    .font(.system(size: 14))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(MyCoursesPalette.muted)
            Text(L10n.catalogNoMatch(query.bidiIsolated))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}

// MARK: - Course Card (catalog)

struct CourseCard: View {
    let course: CourseSummary
    let locale: String

    private var coverSymbol: String {
        let symbols = ["graduationcap.fill", "book.fill", "paintbrush.fill",
                       "chart.bar.fill", "lightbulb.fill", "laptopcomputer",
                       "globe", "function"]
        return symbols[abs(course.id.hashValue) % symbols.count]
    }

    private var coverGradient: LinearGradient {
        let palettes: [[Color]] = [
            [Color(red: 0.22, green: 0.13, blue: 0.05), Color(red: 0.12, green: 0.08, blue: 0.04)],
            [Color(red: 0.05, green: 0.18, blue: 0.14), Color(red: 0.03, green: 0.10, blue: 0.07)],
            [Color(red: 0.18, green: 0.10, blue: 0.05), Color(red: 0.10, green: 0.06, blue: 0.03)],
            [Color(red: 0.08, green: 0.14, blue: 0.22), Color(red: 0.04, green: 0.08, blue: 0.13)],
            [Color(red: 0.20, green: 0.10, blue: 0.20), Color(red: 0.10, green: 0.05, blue: 0.10)],
        ]
        let colors = palettes[abs(course.id.hashValue) % palettes.count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    coverGradient
                    Image(systemName: coverSymbol)
                        .font(.system(size: 40, weight: .regular))
                        .foregroundColor(Color.droobGold.opacity(0.9))
                }
                .frame(height: 130)
                .clipShape(RoundedCorners(radius: 16, corners: [.topLeft, .topRight]))

                priceBadge
                    .padding(12)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(course.localizedTitle(locale: locale))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let subtitle = course.localizedSubtitle(locale: locale), !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(MyCoursesPalette.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 6) {
                    instructorAvatar
                    Text(course.instructorName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MyCoursesPalette.muted)
                        .lineLimit(1)
                }

                ctaRow
            }
            .padding(16)
        }
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1)
        )
    }

    /// Small (20pt) instructor avatar shown before the instructor name.
    /// Loads the presigned URL over a gold-tinted initials disc and
    /// replaces it on success; any other phase (nil URL, load failure)
    /// leaves the initials fallback — the person.fill glyph is retired in
    /// favour of a real avatar treatment.
    private var instructorAvatar: some View {
        let shape = Circle()
        return ZStack {
            shape.fill(Color.droobGold.opacity(0.12))
            Text(instructorInitials(course.instructorName))
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.droobGold)
            if let url = course.instructorAvatarUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.clear
                    }
                }
                .frame(width: 20, height: 20)
                .clipShape(shape)
            }
        }
        .frame(width: 20, height: 20)
        .overlay(shape.stroke(Color.droobGold.opacity(0.3), lineWidth: 0.5))
    }

    private func instructorInitials(_ name: String) -> String {
        let words = name.split(separator: " ", omittingEmptySubsequences: true)
        let letters = words.prefix(2).compactMap { $0.first }
        let joined = String(letters).uppercased()
        return joined.isEmpty ? "?" : joined
    }

    private var priceBadge: some View {
        // Hidden for now (2026-07): pricing removed from app for ALL users,
        // not just auto-enroll students. Previous gate kept below so it can
        // be restored:
        // let hidePricing = AuthSession.shared.currentUser?.isAutoEnroll ?? false
        let hidePricing = true
        return Group {
            if course.enrolled {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                    Text(L10n.enrolled)
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(MyCoursesPalette.success)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(MyCoursesPalette.success.opacity(0.18))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(MyCoursesPalette.success.opacity(0.45), lineWidth: 1))
            } else if !hidePricing {
                // Normal student: show the price (renders "FREE" when the
                // course is free via CurrencyFormat).
                Text(course.formattedPrice.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MyCoursesPalette.success)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(MyCoursesPalette.success.opacity(0.15))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(MyCoursesPalette.success.opacity(0.45), lineWidth: 1))
            }
        }
    }

    private var ctaRow: some View {
        HStack {
            Spacer()
            Text(course.enrolled
                 ? "\(L10n.myCoursesContinueLearning) →"
                 : "\(L10n.enroll) →")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(LinearGradient.droobBrand)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.top, 4)
    }
}

// MARK: - Skeleton loading (dark)

private struct CatalogSkeletonView: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    MCSkeletonBlock(height: 130, cornerRadius: 0)
                    VStack(alignment: .leading, spacing: 12) {
                        MCSkeletonBlock(height: 16, cornerRadius: 4, width: 220)
                        MCSkeletonBlock(height: 11, cornerRadius: 3, width: 150)
                        MCSkeletonBlock(height: 11, cornerRadius: 3, width: 100)
                        MCSkeletonBlock(height: 38, cornerRadius: 19)
                    }
                    .padding(16)
                }
                .background(MyCoursesPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            }
        }
    }
}
