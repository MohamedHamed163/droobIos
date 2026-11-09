import SwiftUI

// MARK: - Rate this course
//
// Bottom sheet hosted from the course detail screen's Q&A block.
// Matches the Figma "How was the course?" flow: a header card with the
// course thumbnail + instructor, the rating prompt, 1–5 tappable stars
// with a dynamic adjective label, an optional review body with a live
// character counter, and a thanks-state with a preview of the just-saved
// review.

struct RateCourseSheet: View {
    let courseTitle: String
    let instructorName: String
    let coverUrl: String?
    let existing: CourseReviewItem?
    let onSubmit: (Int, String?) async -> Bool
    let onClose: () -> Void

    @State private var stars: Int
    @State private var reviewBody: String
    @State private var submitting: Bool = false
    @State private var succeeded: Bool = false
    @State private var errorMessage: String? = nil
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    private let maxLength: Int = 500

    init(courseTitle: String,
         instructorName: String,
         coverUrl: String?,
         existing: CourseReviewItem?,
         onSubmit: @escaping (Int, String?) async -> Bool,
         onClose: @escaping () -> Void) {
        self.courseTitle = courseTitle
        self.instructorName = instructorName
        self.coverUrl = coverUrl
        self.existing = existing
        self.onSubmit = onSubmit
        self.onClose = onClose
        _stars = State(initialValue: existing?.stars ?? 0)
        _reviewBody = State(initialValue: existing?.body ?? "")
    }

    private var ar: Bool { appLocale == "ar" }
    private var overLimit: Bool { reviewBody.count > maxLength }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            if succeeded {
                successView
                    .transition(.opacity)
            } else {
                editView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: succeeded)
    }

    // MARK: - Edit state

    private var editView: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerTile
            Divider().overlay(MyCoursesPalette.stroke)

            VStack(spacing: 6) {
                Text(L10n.courseDetailRateSheetQuestion)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                Text(L10n.courseDetailRateSheetPrompt)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            starPicker
                .padding(.top, -2)

            ratingLabel
                .frame(maxWidth: .infinity)
                .frame(height: 18)

            bodyField

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            submitButton
                .padding(.top, 2)

            Button(action: onClose) {
                Text(L10n.courseDetailRateSheetCancel)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: Header tile

    private var headerTile: some View {
        HStack(spacing: 12) {
            coverThumb
            VStack(alignment: .leading, spacing: 2) {
                Text(courseTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(instructorName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var coverThumb: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let urlString = coverUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        coverPlaceholder
                    }
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(shape)
        .overlay(shape.stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient.droobBrand
            Image(systemName: "book.closed.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
        }
    }

    // MARK: Stars

    private var starPicker: some View {
        HStack(spacing: 14) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    withAnimation(.easeInOut(duration: 0.1)) { stars = value }
                } label: {
                    Image(systemName: value <= stars ? "star.fill" : "star")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundColor(value <= stars ? Color.droobGold : MyCoursesPalette.muted.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var ratingLabel: some View {
        if let text = ratingAdjective(for: stars) {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.droobGold)
                .transition(.opacity)
        } else {
            Color.clear
        }
    }

    private func ratingAdjective(for value: Int) -> String? {
        switch value {
        case 5: return L10n.courseDetailRateSheetLabel5
        case 4: return L10n.courseDetailRateSheetLabel4
        case 3: return L10n.courseDetailRateSheetLabel3
        case 2: return L10n.courseDetailRateSheetLabel2
        case 1: return L10n.courseDetailRateSheetLabel1
        default: return nil
        }
    }

    // MARK: Body field

    private var bodyField: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack(alignment: .topLeading) {
            TextEditor(text: $reviewBody)
                .modifier(HiddenScrollBackground())
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 26)
                .frame(minHeight: 120)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary)

            if reviewBody.isEmpty {
                Text(L10n.courseDetailRateSheetPlaceholder)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }

            counterLabel
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(false)
        }
        .background(MyCoursesPalette.surface)
        .clipShape(shape)
        .overlay(shape.stroke(overLimit ? Color.red.opacity(0.85) : MyCoursesPalette.stroke,
                              lineWidth: overLimit ? 1.5 : 1))
    }

    private var counterLabel: some View {
        HStack(spacing: 2) {
            Text("\(reviewBody.count)")
                .foregroundColor(overLimit ? Color.red : MyCoursesPalette.muted)
            Text(" / \(maxLength)")
                .foregroundColor(MyCoursesPalette.muted)
        }
        .font(.system(size: 12, weight: .semibold))
    }

    // MARK: Submit

    private var submitButton: some View {
        Button {
            Task { await runSubmit() }
        } label: {
            HStack(spacing: 8) {
                if submitting {
                    ProgressView()
                        .tint(Color(red: 0.08, green: 0.06, blue: 0.04))
                }
                Text(L10n.courseDetailRateSheetSubmitButton)
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient.droobBrand
                    .opacity(submitDisabled ? 0.4 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(submitDisabled)
    }

    private var submitDisabled: Bool {
        submitting || stars < 1 || overLimit
    }

    private func runSubmit() async {
        guard !submitDisabled else { return }
        submitting = true
        errorMessage = nil
        let trimmed = reviewBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: String? = trimmed.isEmpty ? nil : trimmed
        let ok = await onSubmit(stars, payload)
        submitting = false
        if ok {
            withAnimation { succeeded = true }
        } else {
            errorMessage = L10n.coursesGenericError
        }
    }

    // MARK: - Success state

    private var successView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(MyCoursesPalette.success.opacity(0.16))
                    .frame(width: 84, height: 84)
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(MyCoursesPalette.success)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text(String(format: L10n.courseDetailRateSheetThanksFmt, firstNameForGreeting))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                Text(L10n.courseDetailRateSheetSuccessSubtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { v in
                    Image(systemName: v <= stars ? "star.fill" : "star")
                        .font(.system(size: 22))
                        .foregroundColor(Color.droobGold)
                }
            }
            .padding(.top, 2)

            reviewPreviewCard
                .padding(.top, 4)

            Spacer(minLength: 0)

            Button(action: onClose) {
                HStack(spacing: 8) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(L10n.courseDetailRateSheetBackToCourse)
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(LinearGradient.droobBrand)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation { succeeded = false }
            } label: {
                Text(L10n.courseDetailRateSheetEditReview)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var reviewPreviewCard: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let trimmed = reviewBody.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ReviewAvatar(name: authorNameForPreview)
                VStack(alignment: .leading, spacing: 2) {
                    Text(authorNameForPreview)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(L10n.courseDetailReviewAgeJustNow)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(MyCoursesPalette.muted)
                }
                Spacer()
            }
            if !trimmed.isEmpty {
                Text("\u{201C}\(trimmed)\u{201D}")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MyCoursesPalette.surface)
        .clipShape(shape)
        .overlay(shape.stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    private var authorNameForPreview: String {
        AuthSession.shared.currentUser?.displayName ?? L10n.courseDetailRateSheetYouFallback
    }

    private var firstNameForGreeting: String {
        let full = AuthSession.shared.currentUser?.displayName ?? L10n.courseDetailRateSheetYouFallback
        let first = full.split(separator: " ").first.map(String.init) ?? full
        return first
    }
}

// MARK: - Scroll background helper
//
// `scrollContentBackground` only exists on iOS 16+. Wrapping it in a
// modifier keeps the call sites tidy and lets the iOS 15 fallback skip
// the call without an inline #available check inside the view body.

private struct HiddenScrollBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}
