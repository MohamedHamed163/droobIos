import SwiftUI

// MARK: - WelcomeBackView
//
// Shown once, immediately after a returning user completes the
// reset-password OTP. Matches the Figma "new user signing success"
// screen on the right side of the flow card — green checkmark,
// "Welcome back, <Name>", account card, 3 stat tiles, and two CTAs
// ("Go to Dashboard" + "Continue Last Course").
//
// Loads `/v1/student/dashboard` on appear to populate stats and the
// continue-learning target. While loading the stats render as
// placeholders ("—") so the page doesn't pop.

@MainActor
final class WelcomeBackViewModel: ObservableObject {
    @Published var enrolledCount: Int = 0
    @Published var streakDays: Int = 0
    @Published var averageProgressPct: Int = 0
    @Published var continueCourseId: String? = nil
    @Published var continueLessonId: String? = nil
    @Published var isLoading: Bool = true

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let dash: HomeDashboard = try await AuthInterceptor.shared.execute(
                APIRequest(path: "/v1/student/dashboard", method: .GET))
            enrolledCount = dash.enrolledCount
            streakDays = dash.streakDays
            if let cont = dash.continueLearning {
                continueCourseId = cont.id
                continueLessonId = cont.nextLessonId
                averageProgressPct = Int(cont.progressPct)
            } else {
                averageProgressPct = dash.enrolledCount == 0 ? 0
                    : Int(round(Double(dash.completedCount) * 100.0 / Double(dash.enrolledCount)))
            }
        } catch {
            // Silent degrade — the screen renders with zeros, the
            // "Continue Last Course" button stays disabled.
        }
    }
}

struct WelcomeBackView: View {
    let displayName: String
    let email: String
    var onGoToDashboard: () -> Void
    var onContinueLastCourse: (_ courseId: String) -> Void

    @StateObject private var vm = WelcomeBackViewModel()
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    private var isArabic: Bool { appLocale == "ar" }

    private var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }

    var body: some View {
        ZStack(alignment: .top) {
            AuthFigmaColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 28) {
                        Color.clear.frame(height: 18)
                        successHero
                        accountCard
                        statsRow
                        VStack(spacing: 12) {
                            AuthPrimaryGold(
                                title: L10n.welcomeGoToDashboard,
                                loadingTitle: "",
                                isLoading: false,
                                isDisabled: false,
                                leadingSystemImage: "house.fill",
                                action: onGoToDashboard
                            )
                            continueButton
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.load() }
    }

    // MARK: Hero

    private var successHero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 104, height: 104)
                Circle()
                    .stroke(AuthFigmaColors.successGreen, lineWidth: 2.5)
                    .frame(width: 104, height: 104)
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(AuthFigmaColors.successGreen)
            }
            .shadow(color: AuthFigmaColors.successGreen.opacity(0.35), radius: 24, x: 0, y: 0)

            VStack(spacing: 4) {
                Text(L10n.welcomeBackLine)
                    .font(BrandFont.display(size: 30, isArabic: isArabic))
                    .foregroundColor(AuthFigmaColors.textPrimary)
                Text("\(firstName).")
                    .font(BrandFont.displaySemiBold(size: 30, isArabic: isArabic))
                    .foregroundColor(AuthFigmaColors.gold)
            }
            .multilineTextAlignment(.center)

            Text(L10n.welcomeBackBody)
                .font(BrandFont.display(size: 14, isArabic: isArabic))
                .foregroundColor(AuthFigmaColors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
        }
    }

    // MARK: Account card

    private var accountCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(AuthFigmaColors.chipBg)
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
            ZStack {
                Circle()
                    .stroke(AuthFigmaColors.successGreen, lineWidth: 1.5)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AuthFigmaColors.successGreen)
            }
            .frame(width: 24, height: 24)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AuthFigmaColors.surface)
        )
    }

    // MARK: Stats row

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(
                value: "\(vm.enrolledCount)",
                label: L10n.welcomeStatCourses,
                progressKind: .bar(fraction: vm.enrolledCount > 0 ? 0.4 : 0),
                accent: AuthFigmaColors.gold
            )
            statCard(
                value: "\(vm.streakDays)",
                label: L10n.welcomeStatStreak,
                progressKind: .dots(filled: min(vm.streakDays, 5), total: 5),
                accent: AuthFigmaColors.gold
            )
            statCard(
                value: "\(vm.averageProgressPct)%",
                label: L10n.welcomeStatProgress,
                progressKind: .bar(fraction: CGFloat(vm.averageProgressPct) / 100),
                accent: AuthFigmaColors.successGreen
            )
        }
    }

    private enum StatProgress {
        case bar(fraction: CGFloat)
        case dots(filled: Int, total: Int)
    }

    private func statCard(value: String, label: String, progressKind: StatProgress, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(BrandFont.displaySemiBold(size: 24, isArabic: isArabic))
                .foregroundColor(AuthFigmaColors.textPrimary)
            Text(label)
                .font(BrandFont.display(size: 12, isArabic: isArabic))
                .foregroundColor(AuthFigmaColors.muted)

            switch progressKind {
            case .bar(let fraction):
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(accent)
                            .frame(width: max(0, min(1, fraction)) * geo.size.width)
                    }
                }
                .frame(height: 4)
            case .dots(let filled, let total):
                HStack(spacing: 4) {
                    ForEach(0..<total, id: \.self) { i in
                        Circle()
                            .fill(i < filled ? accent : Color.white.opacity(0.18))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AuthFigmaColors.surface)
        )
    }

    // MARK: Continue CTA

    private var continueButton: some View {
        let enabled = vm.continueCourseId != nil
        return Button {
            if let id = vm.continueCourseId { onContinueLastCourse(id) }
        } label: {
            HStack(spacing: 8) {
                Text(L10n.welcomeContinueLastCourse)
                    .font(BrandFont.displaySemiBold(size: 16, isArabic: isArabic))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(AuthFigmaColors.textPrimary)
            .opacity(enabled ? 1 : 0.45)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AuthFigmaColors.surface)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

#Preview {
    WelcomeBackView(
        displayName: "Nour Al-Rashid",
        email: "nour@droob.co",
        onGoToDashboard: {},
        onContinueLastCourse: { _ in }
    )
}
