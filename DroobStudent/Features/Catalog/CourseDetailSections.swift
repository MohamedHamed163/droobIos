import SwiftUI

// MARK: - Ratings & Reviews block
//
// Renders the big-number/histogram pair, a two-card review preview, and
// a "See all reviews" affordance. The histogram is always 5 rows even
// when some buckets are empty — the backend pads them in the DTO so
// the layout stays stable.

struct CourseReviewsBlock: View {
    let distribution: RatingDistribution
    let recentReviews: [CourseReviewItem]
    let locale: String
    let onSeeAll: () -> Void

    private var ar: Bool { locale == "ar" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.courseDetailRatingsTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 16) {
                summaryRow
                if !recentReviews.isEmpty {
                    Rectangle()
                        .fill(MyCoursesPalette.stroke)
                        .frame(height: 1)
                    ForEach(recentReviews) { review in
                        reviewCard(review)
                    }
                }
                if distribution.ratingCount > 0 {
                    seeAllButton
                }
            }
            .padding(16)
            .background(MyCoursesPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MyCoursesPalette.stroke, lineWidth: 1))
        }
    }

    // MARK: Summary

    private var summaryRow: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedAverage)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.primary)
                starRow(filled: filledStars(distribution.ratingAvg ?? 0))
                Text(String(format: L10n.courseDetailRatingsCountFmt, distribution.ratingCount))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            VStack(spacing: 6) {
                ForEach(distribution.buckets) { bucket in
                    histogramRow(bucket: bucket)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var formattedAverage: String {
        guard let avg = distribution.ratingAvg else { return "—" }
        return String(format: "%.1f", avg)
    }

    private func filledStars(_ value: Double) -> Int {
        let rounded = Int(value.rounded())
        return max(0, min(5, rounded))
    }

    private func starRow(filled: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < filled ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundColor(Color.droobGold)
            }
        }
    }

    private func histogramRow(bucket: RatingDistribution.Bucket) -> some View {
        HStack(spacing: 8) {
            Text("\(bucket.stars)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(MyCoursesPalette.muted)
                .frame(width: 8, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MyCoursesPalette.stroke)
                    Capsule()
                        .fill(Color.droobGold.opacity(0.85))
                        .frame(width: max(2, geo.size.width * CGFloat(bucket.percent) / 100))
                }
            }
            .frame(height: 6)
            Text("\(bucket.percent)%")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: Review card

    private func reviewCard(_ review: CourseReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ReviewAvatar(name: review.authorName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.authorName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    HStack(spacing: 6) {
                        starRow(filled: review.stars)
                        Text("·")
                            .foregroundColor(MyCoursesPalette.muted)
                        // Use `updatedAt` (which mirrors createdAt for
                        // never-edited rows) so an edited review shows
                        // the freshly-bumped timestamp, not the stale
                        // original submission date.
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
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: See all

    private var seeAllButton: some View {
        Button(action: onSeeAll) {
            HStack {
                Text(String(format: L10n.courseDetailSeeAllReviewsFmt, distribution.ratingCount))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(Color.droobGold)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Q&A card
//
// Single grouped surface holding 0..N question previews + the "See all"
// link as the final row, matching the Figma layout. Each question
// optionally renders a nested instructor reply card with the gold
// left-bar (the figma's instructor accent treatment). Divider lines
// separate rows so the card reads as a stack of related items rather
// than independent pills with gaps.

struct CourseQuestionsBlock: View {
    let questions: [CourseQuestionItem]
    let totalCount: Int
    let locale: String
    let onSeeAll: () -> Void

    private var ar: Bool { locale == "ar" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.courseDetailQaTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            if questions.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(questions.enumerated()), id: \.element.id) { idx, q in
                        questionRow(q)
                            .padding(16)
                        if idx < questions.count - 1 {
                            Rectangle()
                                .fill(MyCoursesPalette.stroke)
                                .frame(height: 1)
                        }
                    }
                    if totalCount > 0 {
                        Rectangle()
                            .fill(MyCoursesPalette.stroke)
                            .frame(height: 1)
                        seeAllRow
                            .padding(16)
                    }
                }
                .background(MyCoursesPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            }
        }
    }

    // MARK: Row

    @ViewBuilder
    private func questionRow(_ q: CourseQuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ReviewAvatar(name: q.authorName)
                VStack(alignment: .leading, spacing: 4) {
                    Text(q.authorName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(q.body)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let answer = q.instructorAnswer {
                instructorReply(answer)
            }
            Text(footerLine(for: q))
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
        }
    }

    private func footerLine(for q: CourseQuestionItem) -> String {
        let age = ReviewAgeFormatter.relative(from: q.createdAt)
        let upvotes = String(format: L10n.courseDetailQaUpvotesFmt, q.upvotesCount)
        return bidiJoin(age, upvotes)
    }

    /// Gold-tinted nested card under the question text — the figma's
    /// "instructor reply" treatment. The leading gold bar lives inside
    /// the rounded card; the card uses a slightly lifted background so
    /// it's visually distinct from the parent question row.
    private func instructorReply(_ answer: CourseAnswerItem) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Color.droobGold)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ReviewAvatar(name: answer.authorName)
                        .frame(width: 24, height: 24)
                    Text(answer.authorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.droobGold)
                    Text("·")
                        .foregroundColor(MyCoursesPalette.muted)
                    Text(L10n.courseDetailQaInstructorTag)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.droobGold)
                }
                Text(answer.body)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
        .background(Color.droobGold.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: See all

    private var seeAllRow: some View {
        Button(action: onSeeAll) {
            HStack {
                Text(String(format: L10n.courseDetailQaSeeAllFmt, totalCount))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: ar ? "chevron.left" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(Color.droobGold)
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 24))
                .foregroundColor(MyCoursesPalette.muted)
            Text(L10n.courseDetailQaPlaceholderBody)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }
}

// MARK: - "Questions you may ask" (pinned FAQs)
//
// Instructor-curated Q&A pairs that surface above the reviews block.
// Each row is an expandable disclosure: collapsed shows the question
// and a chevron, expanded reveals the instructor avatar + name + the
// answer text with the same gold-accent treatment as a real
// instructor reply in the Q&A card below.

struct CoursePinnedFaqsBlock: View {
    let faqs: [PinnedFaqItem]
    let instructorName: String
    let locale: String

    /// IDs of currently-expanded rows. Local state — the panel collapses
    /// on every detail re-open, matching the Figma's default "all
    /// collapsed except the second" treatment without persisting it.
    @State private var expanded: Set<String> = []

    private var ar: Bool { locale == "ar" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.courseDetailPinnedFaqsTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text(L10n.courseDetailPinnedFaqsSubtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
            }

            VStack(spacing: 8) {
                ForEach(faqs) { faq in
                    faqRow(faq)
                }
            }
        }
    }

    @ViewBuilder
    private func faqRow(_ faq: PinnedFaqItem) -> some View {
        let isOpen = expanded.contains(faq.id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isOpen { expanded.remove(faq.id) }
                    else { expanded.insert(faq.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(MyCoursesPalette.stroke, lineWidth: 1)
                            .background(Circle().fill(Color.droobGold.opacity(isOpen ? 0.14 : 0.06)))
                        Image(systemName: isOpen ? "minus" : "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.droobGold)
                    }
                    .frame(width: 26, height: 26)

                    Text(faq.question)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Rectangle()
                    .fill(MyCoursesPalette.stroke)
                    .frame(height: 1)
                instructorAnswer(faq)
                    .padding(16)
            }
        }
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    /// Mirrors the gold-tinted instructor-reply card from the Q&A
    /// block so a pinned FAQ visually reads as the instructor speaking,
    /// not as a generic info card.
    private func instructorAnswer(_ faq: PinnedFaqItem) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Color.droobGold)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ReviewAvatar(name: instructorName)
                        .frame(width: 24, height: 24)
                    Text(instructorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.droobGold)
                    Text("·")
                        .foregroundColor(MyCoursesPalette.muted)
                    Text(L10n.courseDetailQaInstructorTag)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.droobGold)
                }
                Text(faq.answer)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
        .background(Color.droobGold.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Review avatar (initials)

struct ReviewAvatar: View {
    let name: String
    /// Presigned avatar URL. When non-nil/non-blank the image loads over
    /// the initials disc and replaces it on `.success`; every other phase
    /// (loading, failure) leaves the gold-ring initials showing. Defaults
    /// to nil so all existing initials-only call sites are unchanged.
    var avatarUrl: String? = nil

    var body: some View {
        initialsDisc
            .overlay {
                if let url = avatarUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            Color.clear
                        }
                    }
                    .clipShape(Circle())
                }
            }
            .frame(width: 32, height: 32)
    }

    private var initialsDisc: some View {
        ZStack {
            Circle()
                .stroke(Color.droobGold.opacity(0.4), lineWidth: 1)
                .background(Circle().fill(Color.droobGold.opacity(0.12)))
            Text(initials(name))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color.droobGold)
        }
    }

    private func initials(_ raw: String) -> String {
        let words = raw.split(separator: " ", omittingEmptySubsequences: true)
        let firstTwo = words.prefix(2).compactMap { $0.first }
        let joined = String(firstTwo).uppercased()
        return joined.isEmpty ? "?" : joined
    }
}

// MARK: - Relative age formatter
//
// SwiftUI's RelativeDateTimeFormatter is fine in English but produces
// awkward fragments in Arabic ("منذ -3 يوم" etc. on some locales). The
// localized strings give us explicit control over both languages and
// keep the review-card copy consistent with the rest of the screen.

enum ReviewAgeFormatter {
    static func relative(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60:
            return L10n.courseDetailReviewAgeJustNow
        case 60..<3600:
            return String(format: L10n.courseDetailReviewAgeMinutesFmt, seconds / 60)
        case 3600..<86_400:
            return String(format: L10n.courseDetailReviewAgeHoursFmt, seconds / 3600)
        case 86_400..<604_800:
            return String(format: L10n.courseDetailReviewAgeDaysFmt, seconds / 86_400)
        case 604_800..<2_592_000:
            return String(format: L10n.courseDetailReviewAgeWeeksFmt, seconds / 604_800)
        default:
            return String(format: L10n.courseDetailReviewAgeMonthsFmt, seconds / 2_592_000)
        }
    }
}

// MARK: - Compact age formatter (Q&A screen)
//
// Tighter relative-time output for the full Q&A list — the figma uses
// "2h ago", "Yesterday", "Apr 14" rather than the more verbose review
// formatter above. Inside 7 days we render in hours/days; "Yesterday"
// is a named single day; older entries fall to a month/day calendar
// stamp so the screen stays scannable.

enum QaAgeFormatter {
    static func relative(from date: Date, locale: String = L10n.currentLanguageCode) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60:
            return L10n.qaAgeJustNow
        case 60..<3600:
            return String(format: L10n.qaAgeMinutesFmt, seconds / 60)
        case 3600..<86_400:
            return String(format: L10n.qaAgeHoursFmt, seconds / 3600)
        case 86_400..<172_800:
            return L10n.qaAgeYesterday
        case 172_800..<604_800:
            return String(format: L10n.qaAgeDaysFmt, seconds / 86_400)
        default:
            // Calendar stamp ("Apr 14") for anything older than a week.
            // Locale-aware so Arabic gets the right month name.
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: locale)
            fmt.setLocalizedDateFormatFromTemplate("MMM d")
            return fmt.string(from: date)
        }
    }
}
