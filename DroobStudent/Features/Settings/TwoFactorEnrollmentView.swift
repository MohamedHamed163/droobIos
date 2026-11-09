import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

/// Step 1 of 2FA enrolment: shows the QR code (and the Base32 secret as a
/// fallback) plus a 6-digit input field. On successful verification the
/// caller closes this sheet and presents the recovery-codes view.
struct TwoFactorEnrollmentView: View {
    let enrollment: TwoFactorEnrollResponse
    let onCancel: () -> Void
    let onVerified: (String) async -> Void

    /// Live error from the view model. Surfacing it here keeps validation
    /// inline with the input field, matching how authenticator apps handle
    /// "wrong code" errors.
    let error: String?
    let isVerifying: Bool

    @State private var code: String = ""
    @State private var copiedSecret = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                MyCoursesPalette.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        qrCard
                        secretFallback
                        codeField
                        verifyButton
                        if let error {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(MyCoursesPalette.danger)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.cancel, action: onCancel)
                        .foregroundColor(MyCoursesPalette.muted)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { codeFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            (Text(L10n.twoFaEnableLine1).font(.system(size: 24, weight: .bold)).foregroundColor(MyCoursesPalette.textPrimary)
            + Text(L10n.twoFaTitle)
                .font(.system(size: 24, weight: .bold))
                // Gold as ink on the page background — the ramp, not the fill.
                .foregroundColor(MyCoursesPalette.accent))
            Text(L10n.twoFaEnrollSubtitle)
                .font(.system(size: 13))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.bottom, 4)
    }

    // MARK: - QR

    private var qrCard: some View {
        VStack(spacing: 0) {
            if let image = QRCodeRenderer.image(for: enrollment.otpauthUri) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(16)
                    // Stays white in both themes — the quiet zone around the
                    // modules has to be light or scanners lose the QR.
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Text(L10n.twoFaQrFailed)
                    .foregroundColor(MyCoursesPalette.danger)
                    .padding()
            }
        }
        .padding(16)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    // MARK: - Manual-entry fallback

    private var secretFallback: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.twoFaManualSecret)
                .font(.system(size: 12))
                .foregroundColor(MyCoursesPalette.muted)
            HStack {
                Text(enrollment.secretBase32)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    UIPasteboard.general.string = enrollment.secretBase32
                    withAnimation { copiedSecret = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedSecret = false
                    }
                } label: {
                    Text(copiedSecret ? "Copied" : "Copy")
                        .font(.system(size: 12, weight: .semibold))
                        // Ink on the raised secret field, not a gold pill.
                        .foregroundColor(MyCoursesPalette.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(MyCoursesPalette.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 6-digit input

    private var codeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.twoFaCodeField)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MyCoursesPalette.muted)
            TextField("123 456", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($codeFocused)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundColor(MyCoursesPalette.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .background(MyCoursesPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
                .onChange(of: code) { newValue in
                    // Strip non-digits, cap to 6 chars.
                    let filtered = String(newValue.filter(\.isNumber).prefix(6))
                    if filtered != newValue { code = filtered }
                }
        }
    }

    // MARK: - Verify CTA

    private var verifyButton: some View {
        Button {
            Task { await onVerified(code) }
        } label: {
            HStack {
                Spacer()
                if isVerifying {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(
                            tint: Color(red: 0.08, green: 0.06, blue: 0.04)))
                } else {
                    Text(L10n.twoFaVerifyEnable)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                }
                Spacer()
            }
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.878, green: 0.769, blue: 0.561),
                        Color(red: 0.776, green: 0.663, blue: 0.420)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(code.count == 6 && !isVerifying ? 1.0 : 0.5))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(code.count != 6 || isVerifying)
    }
}

// MARK: - QR rendering

/// Tiny CIQRCodeGenerator wrapper. We use SwiftUI's `.interpolation(.none)`
/// so the upscaled QR stays crisp instead of getting bilinear-blurred.
enum QRCodeRenderer {
    static func image(for string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        // Render at ~10× so the QR is high-DPI on retina.
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaled = output.transformed(by: transform)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
