import SwiftUI

// MARK: - ProfileViewModel

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var stats: StudentProgressStats? = nil
    @Published var deviceCount: Int? = nil
    @Published var twoFactorEnabled: Bool? = nil
    @Published var unreadInboxCount: Int? = nil
    @Published var enrolledCount: Int? = nil
    @Published var error: String? = nil

    /// Lightweight wire shape for the unread-count endpoint.
    private struct UnreadCountResponse: Decodable { let unread: Int }

    func load() async {
        error = nil
        // Fetch progress, security status, device list and inbox unread
        // count in parallel so every Profile subtitle populates from a
        // single load() call.
        async let statsReq: StudentProgressStats = AuthInterceptor.shared.execute(
            APIRequest(path: "/v1/student/progress"))
        async let securityReq: SecurityStatus = AuthInterceptor.shared.execute(
            APIRequest(path: "/v1/student/settings/security"))
        async let devicesReq: [StudentDevice] = AuthInterceptor.shared.execute(
            APIRequest(path: "/v1/student/settings/devices"))
        async let unreadReq: UnreadCountResponse = AuthInterceptor.shared.execute(
            APIRequest(path: "/v1/student/notifications/unread-count"))
        async let enrollReq: [EnrolledCourse] = AuthInterceptor.shared.execute(
            APIRequest(path: "/v1/student/enrollments"))

        // Each leg fails independently — a missing /progress shouldn't blank
        // out the device count, and vice versa.
        do {
            stats = try await statsReq
        } catch let e where APIClient.isCancellationError(e) {
            // Pull-to-refresh cancelled.
            return
        } catch let e as DroobError {
            if case .unauthenticated(_, _) = e { AuthSession.shared.handleUnauthenticated(); return }
            else { self.error = e.errorDescription }
        } catch let e {
            self.error = e.localizedDescription
        }

        do { twoFactorEnabled = (try await securityReq).twoFactorEnabled }
        catch { /* leave nil → renders "—" */ }

        do { deviceCount = (try await devicesReq).count }
        catch { /* leave nil → renders "—" */ }

        do { unreadInboxCount = (try await unreadReq).unread }
        catch { /* leave nil → renders "—" */ }

        do { enrolledCount = (try await enrollReq).count }
        catch { /* leave nil → banner hides the number */ }
    }
}

// MARK: - ProfileView (dark Figma-aligned)

struct ProfileView: View {
    @EnvironmentObject private var authSession: AuthSession
    @StateObject private var vm = ProfileViewModel()
    @StateObject private var accountVM = ProfileSettingsViewModel()
    @State private var showLogoutConfirm = false
    @State private var isLoggingOut = false
    @State private var showEditUsername = false
    @State private var showEditEmail = false

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    avatarHeader.padding(.top, 8)
                    enrolledBanner
                    personalInfoSection
                    contactSection
                    settingsSection
                    extrasSection
                    signOutButton
                    versionFooter
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await vm.load()
            await accountVM.load()
        }
        .refreshable {
            await vm.load()
            await accountVM.load()
        }
        .sheet(isPresented: $showEditUsername) {
            EditUsernameSheet(vm: accountVM)
        }
        .sheet(isPresented: $showEditEmail) {
            EditEmailSheet(vm: accountVM)
        }
        .confirmationDialog(
            L10n.logout,
            isPresented: $showLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.logout, role: .destructive) {
                Task {
                    isLoggingOut = true
                    await authSession.logout()
                    isLoggingOut = false
                }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.profileSignOutConfirm)
        }
    }

    // MARK: - Avatar (per Figma — no photo upload)

    private var avatarHeader: some View {
        VStack(spacing: 10) {
            AvatarBadge(initials: initials, size: 96)
            Text(displayName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(MyCoursesPalette.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Enrolled banner (informational, not tappable)

    private var enrolledBanner: some View {
        HStack {
            Spacer()
            VStack(spacing: 2) {
                Text(vm.enrolledCount.map(String.init) ?? "—")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(MyCoursesPalette.accent)
                Text(L10n.profileEnrolledCoursesLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(MyCoursesPalette.textPrimary)
            }
            Spacer()
        }
        .padding(.vertical, 14)
        // The brown/gold sheen is all alpha, so on its own it composited
        // against the page — near-black in dark (the intended warm band) but
        // white in light, where it turned to mud under gold text. Laying a
        // damped sheen over an opaque surface keeps it a warm band in both
        // themes and keeps the count readable on top of it.
        .background(
            ZStack {
                MyCoursesPalette.surfaceRaised
                LinearGradient(
                    colors: [
                        Color.droobDarkBrown.opacity(0.55),
                        Color.droobGold.opacity(0.18),
                        Color.droobDarkBrown.opacity(0.55),
                    ],
                    startPoint: .leading, endPoint: .trailing)
                    .opacity(0.35)
            })
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyCoursesPalette.accent.opacity(0.35), lineWidth: 1))
    }

    // MARK: - PERSONAL INFO (Username → edit display name)

    private var personalInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(text: L10n.profilePersonalInfoSection)
            SettingsCard {
                Button {
                    showEditUsername = true
                } label: {
                    HStack {
                        Text(L10n.profileUsernameRow)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(MyCoursesPalette.textPrimary)
                        Spacer()
                        Text(displayName)
                            .font(.system(size: 15))
                            .foregroundColor(MyCoursesPalette.muted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - CONTACT (Email → verified change flow)

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(text: L10n.profileContactSection)
            SettingsCard {
                Button {
                    accountVM.resetEmailFlow()
                    showEditEmail = true
                } label: {
                    HStack {
                        Text(L10n.profileEmailRow)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(MyCoursesPalette.textPrimary)
                        Spacer()
                        Text(email)
                            .font(.system(size: 15))
                            .foregroundColor(MyCoursesPalette.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.muted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - SETTINGS (hub for notifications/security/payments/language/help)

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(text: L10n.profileSettingsSection)
            SettingsCard {
                NavigationLink {
                    SettingsView()
                } label: {
                    ProfileNavRow(
                        icon: "gearshape.fill",
                        title: L10n.settingsTitle,
                        subtitle: nil)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Extras carried over from the pre-Figma profile
    //
    // The Figma redesign drops the at-a-glance learning stats and the inbox
    // shortcut. They're genuinely useful and have no home in the new Settings
    // hub, so they live here under their own eyebrow rather than being lost.

    private var extrasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(text: L10n.profileLearningSection)
            statsRow
            SettingsCard {
                NavigationLink {
                    NotificationsInboxView()
                } label: {
                    ProfileNavRow(
                        icon: "tray.fill",
                        title: L10n.profileInbox,
                        subtitle: vm.unreadInboxCount.map {
                            $0 == 0
                                ? L10n.profileInboxAllCaught
                                : "\($0)\(L10n.profileInboxUnreadSuffix)"
                        } ?? "—")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            statTile(value: vm.enrolledCount.map { "\($0)" } ?? "—", label: L10n.statTileCourses)
            statTile(value: vm.stats.map { "\($0.lessonsCompleted)" } ?? "—", label: L10n.statTileLessons)
            statTile(value: vm.stats.map { "\($0.certificatesCount)" } ?? "—", label: L10n.statTileCerts)
            statTile(value: vm.stats.map { "\($0.learningScore)%" } ?? "—", label: L10n.statTileAvg)
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    // MARK: - Developer section (DEBUG / TestFlight only)

    // MARK: - Sign out

    private var signOutButton: some View {
        Button(role: .destructive) {
            showLogoutConfirm = true
        } label: {
            HStack {
                Spacer()
                if isLoggingOut {
                    ProgressView().tint(MyCoursesPalette.danger)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                    Text(L10n.profileSignOut)
                        .font(.system(size: 14, weight: .semibold))
                }
                Spacer()
            }
            // Danger ink on the subtle-danger plate. `Color.red.opacity(0.9)`
            // on a 12% red wash both composited against the page: on the light
            // page that is #FF564C on near-white, ~3.2:1. The two danger tokens
            // are the same pairing tuned per theme.
            .foregroundColor(MyCoursesPalette.danger)
            .padding(.vertical, 14)
            .background(MyCoursesPalette.dangerSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MyCoursesPalette.danger.opacity(0.25), lineWidth: 1))
        }
        .padding(.top, 4)
    }

    private var versionFooter: some View {
        Text(String(format: L10n.profileFooterVersion, appVersion))
            .font(.system(size: 11))
            .foregroundColor(MyCoursesPalette.muted)
            .padding(.top, 6)
    }

    // MARK: - Helpers

    /// Prefer the freshly-loaded settings profile; fall back to the cached
    /// `/auth/me` snapshot so the name shows instantly on first paint.
    private var displayName: String {
        accountVM.profile?.displayName ?? authSession.currentUser?.displayName ?? "—"
    }

    private var email: String {
        accountVM.profile?.email ?? authSession.currentUser?.email ?? ""
    }

    private var initials: String {
        let parts = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let joined = parts.map { String($0) }.joined().uppercased()
        return joined.isEmpty ? "··" : joined
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "2.4.1"
    }
}

// MARK: - Avatar badge (gold ring + centered initials + green check)

private struct AvatarBadge: View {
    let initials: String
    var size: CGFloat = 64

    var body: some View {
        // Initials sit centered on the gold-ringed surface; the green
        // checkmark is overlaid as a separate corner badge so its offset
        // doesn't shift the initials.
        Circle()
            .fill(MyCoursesPalette.surface)
            .frame(width: size, height: size)
            .overlay(
                // Outer "shiny" gold ring with a subtle inner glow.
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.droobLightGold,
                                Color.droobGold,
                                Color.droobDarkBrown,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing),
                        lineWidth: 2.5)
            )
            .overlay(
                // Initials are ink on `surface`, not on the ring.
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundColor(MyCoursesPalette.accent)
            )
            .overlay(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(MyCoursesPalette.success)
                        .overlay(Circle().stroke(MyCoursesPalette.background, lineWidth: 2))
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.13, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: size * 0.28, height: size * 0.28)
                .offset(x: 2, y: 2)
            }
    }
}

// MARK: - Reusable row

struct ProfileNavRow: View {
    let icon: String
    /// Icon tile is a 20% wash on the card surface, so the glyph on it is
    /// gold *ink* — the accent ramp, not the fill gold.
    var iconBg: Color = MyCoursesPalette.accent.opacity(0.20)
    var iconTint: Color = MyCoursesPalette.accent
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconBg)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconTint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(MyCoursesPalette.muted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

