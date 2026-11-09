import Foundation
import SwiftUI

// MARK: - WelcomeAccountCreatedView
//
// Shown once, immediately after a brand-new user completes email
// verification. Matches the Figma "new account success" screen
// (node 1925:8251): green checkmark hero, "Your journey starts here.",
// Welcome <name>, account card, an instructor-framed "What is waiting
// for you" list, and a single pinned "Meet your Instructors" CTA.
//
// Content scrolls; the CTA stays pinned to the bottom.

@MainActor
final class WelcomeAccountCreatedViewModel: ObservableObject {
    /// Total published-instructor count from the catalog. `nil` until the
    /// fetch resolves; the row falls back to a number-less label meanwhile.
    @Published var instructorCount: Int? = nil

    func loadInstructorCount() async {
        // size=1 — we only need `totalElements`, not the rows themselves.
        let request = APIRequest(
            path: "/v1/student/instructors",
            method: .GET,
            queryItems: [
                URLQueryItem(name: "page", value: "0"),
                URLQueryItem(name: "size", value: "1")
            ]
        )
        do {
            let result: SpringPage<StudentInstructorSummary> =
                try await AuthInterceptor.shared.execute(request)
            instructorCount = result.totalElements
        } catch {
            // Silent degrade — the row renders "Expert Instructors".
        }
    }
}

struct WelcomeAccountCreatedView: View {
    let displayName: String
    let email: String
    var onMeetInstructors: () -> Void

    @StateObject private var vm = WelcomeAccountCreatedViewModel()
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    private var isArabic: Bool { appLocale == "ar" }

    private var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }

    private var instructorRowTitle: String {
        if let count = vm.instructorCount {
            return L10n.welcomeExpertInstructors(count)
        }
        return L10n.welcomeExpertInstructorsPlain
    }

    var body: some View {
        ZStack(alignment: .top) {
            AuthFigmaColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        Color.clear.frame(height: 12)
                        successHero
                        accountCard
                        whatsWaitingSection
                        Color.clear.frame(height: 12)
                    }
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom) { bottomBar }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.loadInstructorCount() }
    }

    // MARK: Hero

    private var successHero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .strokeBorder(
                        AuthFigmaColors.successGreen.opacity(0.28),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 4])
                    )
                    .frame(width: 130, height: 130)
                Circle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle().stroke(AuthFigmaColors.successGreen, lineWidth: 2)
                    )
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(AuthFigmaColors.successGreen)
            }

            Text(L10n.welcomeNewAccountBadge)
                .font(BrandFont.sansBold(size: 11, isArabic: isArabic))
                .tracking(2.2)
                .foregroundColor(AuthFigmaColors.gold)

            (
                Text(L10n.welcomeJourneyLine1)
                    .font(BrandFont.display(size: 32, isArabic: isArabic))
                    .foregroundColor(AuthFigmaColors.textPrimary)
                +
                Text(L10n.welcomeJourneyLine2)
                    .font(BrandFont.display(size: 32, isArabic: isArabic))
                    .foregroundColor(AuthFigmaColors.gold)
            )
            .multilineTextAlignment(.center)
            .tracking(isArabic ? 0 : -0.8)

            Text(L10n.welcomeGreeting(firstName))
                .font(BrandFont.displaySemiBold(size: 24, isArabic: isArabic))
                .foregroundColor(AuthFigmaColors.gold)

            Text(L10n.welcomeReadyBody)
                .font(BrandFont.display(size: 14, isArabic: isArabic))
                .foregroundColor(AuthFigmaColors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    // MARK: Account card

    private var accountCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AuthFigmaColors.chipBg)
                Text(String(firstName.prefix(1)).uppercased())
                    .font(BrandFont.displaySemiBold(size: 20, isArabic: isArabic))
                    .foregroundColor(AuthFigmaColors.gold)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName.isEmpty ? firstName : displayName)
                    .font(BrandFont.displaySemiBold(size: 16, isArabic: isArabic))
                    .foregroundColor(AuthFigmaColors.textPrimary)
                Text(email)
                    .font(BrandFont.sans(size: 12, isArabic: isArabic))
                    .foregroundColor(AuthFigmaColors.muted)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                Text(L10n.welcomeNewBadge)
                    .font(BrandFont.sansMedium(size: 11, isArabic: isArabic))
            }
            .foregroundColor(AuthFigmaColors.gold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().stroke(AuthFigmaColors.gold.opacity(0.45), lineWidth: 1)
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AuthFigmaColors.surface)
        )
    }

    // MARK: What is waiting for you

    private var whatsWaitingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L10n.welcomeWaitingHeader)
            VStack(spacing: 10) {
                waitingRow(
                    icon: "person.2.fill",
                    iconStyle: .goldGradient,
                    title: instructorRowTitle,
                    subtitle: L10n.welcomeCategories
                )
                waitingRow(
                    icon: "bubble.left.and.bubble.right.fill",
                    iconStyle: .tint(Color(red: 0.188, green: 0.820, blue: 0.345)),
                    title: L10n.welcomeLiveQaTitle,
                    subtitle: L10n.welcomeLiveQaBody
                )
                waitingRow(
                    icon: "chart.bar.fill",
                    iconStyle: .tint(Color(red: 1.0, green: 0.624, blue: 0.039)),
                    title: L10n.welcomeTrackTitle,
                    subtitle: L10n.welcomeTrackBody
                )
            }
        }
    }

    private enum WaitingIconStyle {
        /// Gold gradient fill with a white glyph (the lead "instructors" row).
        case goldGradient
        /// Translucent tinted fill with a glyph in the same accent.
        case tint(Color)
    }

    @ViewBuilder
    private func waitingIcon(_ icon: String, style: WaitingIconStyle) -> some View {
        switch style {
        case .goldGradient:
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(
                        colors: [AuthFigmaColors.goldStrong, AuthFigmaColors.gold],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 38, height: 38)
        case .tint(let accent):
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
            }
            .frame(width: 38, height: 38)
        }
    }

    private func waitingRow(icon: String, iconStyle: WaitingIconStyle, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            waitingIcon(icon, style: iconStyle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BrandFont.displaySemiBold(size: 15, isArabic: isArabic))
                    .foregroundColor(AuthFigmaColors.textPrimary)
                Text(subtitle)
                    .font(BrandFont.sans(size: 12, isArabic: isArabic))
                    .foregroundColor(AuthFigmaColors.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AuthFigmaColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: Pinned CTA

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AuthFigmaColors.divider)
                .frame(height: 1)
            AuthPrimaryGold(
                title: L10n.welcomeMeetInstructors,
                loadingTitle: "",
                isLoading: false,
                isDisabled: false,
                leadingSystemImage: "person.2.fill",
                action: onMeetInstructors
            )
            .padding(.horizontal, 18)
            .padding(.top, 15)
            .padding(.bottom, 8)
        }
        .background(AuthFigmaColors.bg)
    }

    // MARK: Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(BrandFont.sansBold(size: 11, isArabic: isArabic))
            .tracking(2)
            .foregroundColor(AuthFigmaColors.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    WelcomeAccountCreatedView(
        displayName: "Nour Al-Rashid",
        email: "nour@droob.co",
        onMeetInstructors: {}
    )
}
