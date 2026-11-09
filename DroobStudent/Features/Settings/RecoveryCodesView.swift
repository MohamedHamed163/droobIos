import SwiftUI
import UIKit

/// Shown exactly once after a successful 2FA enrolment (or after the user
/// regenerates the codes). Recovery codes are single-use plaintext strings
/// — there is **no way to retrieve them again** from the server, so the UI
/// nags the user to save them before tapping Done.
struct RecoveryCodesView: View {
    let codes: [String]
    let onDone: () -> Void
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        header
                        warning
                        codeGrid
                        actions
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.done, action: onDone)
                        .foregroundColor(MyCoursesPalette.accent)
                }
            }
            .navigationBarBackButtonHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled() // force the user to acknowledge
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundColor(MyCoursesPalette.success)
            (Text(L10n.recoverySaveLine1)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)
            + Text(L10n.recoveryLine2)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(MyCoursesPalette.accent))
            .multilineTextAlignment(.center)
            Text(L10n.recoverySubtitle)
                .font(.system(size: 13))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: 10) {
            // The amber #FF9E40 was a dark-mode glow — 1.5:1 on the cream
            // plate, i.e. an invisible glyph. Joins the card's gold ink voice
            // rather than becoming a new adaptive tint nobody else shares.
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(MyCoursesPalette.accent)
            // `droobLightGold` is a dark-mode ink; on the light plate it is
            // barely above the plate itself (~1.4:1), so the copy takes the
            // accent ramp — same single gold voice `DeviceLimitCard` uses.
            Text(L10n.recoveryWarning)
                .font(.system(size: 12))
                .foregroundColor(MyCoursesPalette.accent)
                .lineSpacing(2)
            Spacer(minLength: 0)
        }
        .padding(14)
        // Opaque plate: a 10% gold wash over the light page is indistinguishable
        // from the page, so the banner lost its shape. In dark, 10% gold over
        // near-black is what `surfaceRaised` already resolves to.
        .background(MyCoursesPalette.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyCoursesPalette.accent.opacity(0.30), lineWidth: 1))
    }

    private var codeGrid: some View {
        // 2-column grid feels balanced for 10 codes — each row holds two
        // 11-char strings without truncation.
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(codes, id: \.self) { code in
                Text(code)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(MyCoursesPalette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(MyCoursesPalette.stroke, lineWidth: 1))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = codes.joined(separator: "\n")
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copied = false
                }
            } label: {
                // Outlined pill, not a gold plate: label and hairline are both
                // ink on `surface`, so both take the accent ramp.
                Text(copied ? L10n.recoveryCopied : L10n.recoveryCopyAll)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(MyCoursesPalette.surface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(MyCoursesPalette.accent.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)

            ShareLink(item: codes.joined(separator: "\n")) {
                Text(L10n.share)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(MyCoursesPalette.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(MyCoursesPalette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}
