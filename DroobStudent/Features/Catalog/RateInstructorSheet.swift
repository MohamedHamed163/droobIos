import SwiftUI

// MARK: - Rate this instructor
//
// Bottom sheet hosted from the instructor profile's Reviews tab. Mirrors
// RateCourseSheet but scopes the rating to the instructor: "How was your
// experience with {instructor}?" with 1–5 stars, an optional body, and a
// thanks-state. The backend upserts, so re-opening with an existing
// review pre-fills the stars/body for editing.

struct RateInstructorSheet: View {
    let instructorName: String
    let avatarUrl: String?
    let existing: InstructorReview?
    let onSubmit: (Int, String?) async -> Bool
    let onClose: () -> Void

    @State private var stars: Int
    @State private var reviewBody: String
    @State private var submitting: Bool = false
    @State private var succeeded: Bool = false
    @State private var errorMessage: String? = nil
    @FocusState private var bodyFocused: Bool
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    private let maxLength: Int = 500

    init(instructorName: String,
         avatarUrl: String?,
         existing: InstructorReview?,
         onSubmit: @escaping (Int, String?) async -> Bool,
         onClose: @escaping () -> Void) {
        self.instructorName = instructorName
        self.avatarUrl = avatarUrl
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
            // Compose form fills the whole screen (figma 1933:8534).
            MyCoursesPalette.background.ignoresSafeArea()
            editView

            // Success confirmation slides up as a bottom sheet over a dimmed
            // backdrop (figma 1933:8797 "Overlay+OverlayBlur").
            if succeeded {
                successOverlay.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: succeeded)
    }

    // MARK: - Edit state

    private var editView: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerTile
            Divider().overlay(MyCoursesPalette.stroke)

            VStack(spacing: 6) {
                Text(String(format: L10n.instructorReviewSheetQuestionFmt, instructorName))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                Text(L10n.instructorReviewSheetPrompt)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)

            // YOUR RATING — stars sit inside a bordered tile, the adjective
            // ("Great") sits beneath it (figma 1923:6939).
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel(L10n.instructorReviewSheetYourRating)
                starPicker
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(MyCoursesPalette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
                ratingLabel.frame(maxWidth: .infinity).frame(height: 18)
            }

            // YOUR REVIEW — label on the left, live "Optional · X / 500"
            // counter on the right, then the bordered text area.
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    sectionLabel(L10n.instructorReviewSheetYourReview)
                    Spacer(minLength: 8)
                    Text(String(format: L10n.instructorReviewSheetOptionalFmt,
                                reviewBody.count, maxLength))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(overLimit ? .red : MyCoursesPalette.muted)
                }
                bodyField
            }

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            buttonRow.padding(.top, 2)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(Color.droobGold)
    }

    // MARK: Cancel + Post Review

    private var buttonRow: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Text(L10n.courseDetailRateSheetCancel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 110)
                    .frame(height: 52)
                    .background(MyCoursesPalette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                Task { await runSubmit() }
            } label: {
                HStack(spacing: 8) {
                    if submitting {
                        ProgressView().tint(Color(red: 0.08, green: 0.06, blue: 0.04))
                    }
                    Text(L10n.instructorReviewSheetPostButton)
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(LinearGradient.droobBrand.opacity(submitDisabled ? 0.4 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(submitDisabled)
        }
    }

    // MARK: Header tile

    private var headerTile: some View {
        HStack(spacing: 12) {
            avatarThumb
            VStack(alignment: .leading, spacing: 2) {
                Text(instructorName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(L10n.instructorReviewSheetRoleLabel)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var avatarThumb: some View {
        let shape = Circle()
        Group {
            if let urlString = avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: ReviewAvatar(name: instructorName)
                    }
                }
            } else {
                ReviewAvatar(name: instructorName)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(shape)
        .overlay(shape.stroke(MyCoursesPalette.stroke, lineWidth: 1))
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
                .focused($bodyFocused)
                .modifier(RateInstructorHiddenScrollBackground())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 120)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary)

            if reviewBody.isEmpty {
                Text(L10n.instructorReviewSheetPlaceholder)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }
        }
        .background(MyCoursesPalette.surface)
        .clipShape(shape)
        .overlay(shape.stroke(overLimit ? Color.red.opacity(0.85) : MyCoursesPalette.stroke,
                              lineWidth: overLimit ? 1.5 : 1))
    }

    // MARK: Submit

    private var submitDisabled: Bool { submitting || stars < 1 || overLimit }

    private func runSubmit() async {
        guard !submitDisabled else { return }
        // editView stays mounted under the success overlay, so the text editor
        // would keep first responder and the keyboard would cover the
        // confirmation's action button. Drop focus synchronously on the tap
        // (before any await) — resigning after the async suspension point is
        // unreliable and SwiftUI drops the @FocusState change on its own.
        bodyFocused = false
        Self.dismissKeyboard()
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

    private static func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Success state

    private var successOverlay: some View {
        ZStack(alignment: .bottom) {
            // Dimmed/blurred backdrop over the compose form.
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            successCard
                .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var successCard: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(MyCoursesPalette.textTertiary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            greenCheck.padding(.top, 2)

            VStack(spacing: 6) {
                Text(String(format: L10n.courseDetailRateSheetThanksFmt, firstNameForGreeting))
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(Color.droobGold)
                Text(L10n.instructorReviewSheetSuccessSubtitle)
                    .font(.system(size: 14, weight: .regular))
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

            reviewPreviewCard.padding(.top, 4)

            VStack(spacing: 6) {
                Button(action: onClose) {
                    Text(L10n.enrollRequestBackToCourse)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(LinearGradient.droobBrand)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { succeeded = false }
                } label: {
                    Text(L10n.instructorReviewSuccessEditButton)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background(MyCoursesPalette.background)
        .clipShape(TopRoundedShape(radius: 28))
        .overlay(TopRoundedShape(radius: 28).stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    // Green check disc — figma 1933:8802: 80pt circle, green/50 @10% fill,
    // 2pt @22% border, plus a faint 1pt outer ring at -6pt (@~8%).
    private var greenCheck: some View {
        ZStack {
            Circle()
                .fill(Self.checkGreen.opacity(0.10))
                .frame(width: 80, height: 80)
                .overlay(Circle().stroke(Self.checkGreen.opacity(0.22), lineWidth: 2))
                .overlay(
                    Circle()
                        .stroke(Self.checkGreen.opacity(0.22), lineWidth: 1)
                        .opacity(0.35)
                        .padding(-6)
                )
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Self.checkGreen)
        }
    }

    // The just-submitted review, echoed back so the confirmation mirrors how
    // it will appear in the list (figma 1933:8798 preview card).
    private var reviewPreviewCard: some View {
        let trimmed = reviewBody.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ReviewAvatar(name: currentUserName)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentUserName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .lineLimit(1)
                    Text(ReviewAgeFormatter.relative(from: Date()))
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(MyCoursesPalette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            if !trimmed.isEmpty {
                Text(trimmed)
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(MyCoursesPalette.textPrimary.opacity(0.85))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MyCoursesPalette.surfaceRaised)   // was #2C2C2E
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    private static let checkGreen = Color(red: 0.188, green: 0.820, blue: 0.345)  // #30D158

    private var currentUserName: String {
        AuthSession.shared.currentUser?.displayName ?? L10n.courseDetailRateSheetYouFallback
    }

    private var firstNameForGreeting: String {
        let full = AuthSession.shared.currentUser?.displayName ?? L10n.courseDetailRateSheetYouFallback
        return full.split(separator: " ").first.map(String.init) ?? full
    }
}

// MARK: - Scroll background helper

private struct RateInstructorHiddenScrollBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}
