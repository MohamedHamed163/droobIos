import SwiftUI

// MARK: - Auth palette
//
// The new auth design uses a gold-on-near-black palette in dark mode and a
// warm cream palette in light mode. We resolve the colors at use site instead
// of going through the asset catalog so the screens stay self-contained and
// react to `colorScheme` changes triggered by the in-screen theme toggle.

struct AuthPalette {
    let background: Color
    let surface: Color
    let surfaceMuted: Color
    let text: Color
    let muted: Color
    let subtle: Color
    let line: Color
    let gold: Color
    let goldStrong: Color
    let goldSoft: Color

    static func resolve(_ scheme: ColorScheme) -> AuthPalette {
        if scheme == .light {
            return AuthPalette(
                background: Color(red: 0.969, green: 0.953, blue: 0.918),
                surface: Color.white,
                surfaceMuted: Color(red: 0.941, green: 0.918, blue: 0.875),
                text: Color(red: 0.082, green: 0.075, blue: 0.059),
                muted: Color(red: 0.435, green: 0.408, blue: 0.373),
                subtle: Color(red: 0.604, green: 0.569, blue: 0.518),
                line: Color(red: 0.098, green: 0.078, blue: 0.047, opacity: 0.10),
                gold: Color(red: 0.722, green: 0.588, blue: 0.353),
                goldStrong: Color(red: 0.776, green: 0.663, blue: 0.420),
                goldSoft: Color(red: 0.722, green: 0.588, blue: 0.353, opacity: 0.14)
            )
        }
        return AuthPalette(
            background: Color(red: 0.031, green: 0.031, blue: 0.031),
            surface: Color(red: 0.071, green: 0.071, blue: 0.071),
            surfaceMuted: Color(red: 0.098, green: 0.098, blue: 0.098),
            text: Color.white,
            muted: Color(red: 0.655, green: 0.631, blue: 0.604),
            subtle: Color(red: 0.408, green: 0.384, blue: 0.361),
            line: Color.white.opacity(0.08),
            gold: Color(red: 0.776, green: 0.663, blue: 0.420),
            goldStrong: Color(red: 0.878, green: 0.769, blue: 0.561),
            goldSoft: Color(red: 0.776, green: 0.663, blue: 0.420, opacity: 0.14)
        )
    }
}

// MARK: - Top toggle row

struct AuthHeaderBar: View {
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @AppStorage("appColorScheme") private var appColorScheme: String = AppColorSchemeDefault.code
    let palette: AuthPalette
    let onClearFocus: () -> Void

    var body: some View {
        HStack {
            // Logo mark
            ZStack {
                LinearGradient(
                    colors: [palette.gold, palette.goldStrong],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text("D")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(red: 0.035, green: 0.031, blue: 0.027))
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: palette.gold.opacity(0.25), radius: 14, x: 0, y: 14)

            Spacer()

            HStack(spacing: 8) {
                AuthChip(
                    icon: appColorScheme == "light" ? "sun.max.fill" : "moon.fill",
                    label: appColorScheme == "light" ? L10n.themeLight : L10n.themeDark,
                    palette: palette
                ) {
                    onClearFocus()
                    appColorScheme = appColorScheme == "light" ? "dark" : "light"
                }
                // Gated behind the same single flag as every other language
                // affordance. This chip is an un-gated *writer* of the
                // `appLocale` key, so leaving it un-gated would let a future
                // caller put the app back into English past the lock. It sits
                // inside the trailing `HStack`, so hiding it leaves no gap —
                // the theme chip simply keeps the corner.
                if !AppLocaleDefault.englishHidden {
                    AuthChip(
                        icon: nil,
                        label: appLocale == "ar" ? L10n.langEnglish : L10n.langArabic,
                        palette: palette
                    ) {
                        onClearFocus()
                        appLocale = appLocale == "ar" ? "en" : "ar"
                    }
                }
            }
        }
    }
}

private struct AuthChip: View {
    let icon: String?
    let label: String
    let palette: AuthPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(palette.text)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(palette.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(palette.line, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Title block

struct AuthTitleBlock: View {
    let title: String
    let subtitle: String
    let palette: AuthPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.authKicker)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundColor(palette.gold)

            Text(title)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(palette.text)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(palette.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Input field

struct AuthInputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var submitLabel: SubmitLabel = .next
    var autocapitalization: TextInputAutocapitalization = .sentences
    var autocorrection: Bool = true
    let palette: AuthPalette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(palette.gold)
                .frame(width: 22)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(size: 15))
            .foregroundColor(palette.text)
            .tint(palette.gold)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled(!autocorrection)
            .submitLabel(submitLabel)
            .modifier(OptionalContentType(type: textContentType))
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }
}

private struct OptionalContentType: ViewModifier {
    let type: UITextContentType?
    func body(content: Content) -> some View {
        if let type = type {
            content.textContentType(type)
        } else {
            content
        }
    }
}

// MARK: - Buttons

struct AuthPrimaryButton: View {
    let title: String
    let isLoading: Bool
    let palette: AuthPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.035, green: 0.031, blue: 0.027)))
                } else {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(red: 0.035, green: 0.031, blue: 0.027))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(
                    colors: [palette.gold, palette.goldStrong],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: palette.gold.opacity(0.22), radius: 12, x: 0, y: 12)
        }
        .buttonStyle(.pressable)
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1)
    }
}

struct AuthSecondaryButton: View {
    let title: String
    var icon: String? = nil
    var useGoogleLogo: Bool = false
    let palette: AuthPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if useGoogleLogo {
                    GoogleLogo()
                        .frame(width: 18, height: 18)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(palette.text)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Google G logo (multi-color, drawn with Canvas)

struct GoogleLogo: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let lineWidth = s * 0.22
            let radius = (s - lineWidth) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            let blue = Color(red: 66/255, green: 133/255, blue: 244/255)
            let red = Color(red: 234/255, green: 67/255, blue: 53/255)
            let yellow = Color(red: 251/255, green: 188/255, blue: 5/255)
            let green = Color(red: 52/255, green: 168/255, blue: 83/255)

            func arc(from a: Double, to b: Double, color: Color) {
                var path = Path()
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(a),
                    endAngle: .degrees(b),
                    clockwise: false
                )
                context.stroke(path, with: .color(color), lineWidth: lineWidth)
            }

            arc(from: 215, to: 320, color: red)        // top
            arc(from: 320, to: 30,  color: blue)       // right
            arc(from: 30,  to: 130, color: green)      // bottom-right
            arc(from: 130, to: 215, color: yellow)     // bottom-left

            // Inner horizontal bar (the cross of the G)
            let barHeight = lineWidth * 0.95
            let barRect = CGRect(
                x: center.x + radius * 0.15,
                y: center.y - barHeight / 2,
                width: radius - radius * 0.05,
                height: barHeight
            )
            context.fill(Path(barRect), with: .color(blue))
        }
    }
}

// MARK: - Game Over overlay (placeholder for unimplemented forgot-password flow)

struct GameOverOverlay: View {
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 0.3
    @State private var rotation: Double = -8
    @State private var glitch: CGFloat = 0
    @State private var subtitleOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 6) {
                Text("GAME")
                    .offset(x: glitch)
                Text("OVER")
                    .offset(x: -glitch)
            }
            .font(.system(size: 64, weight: .black))
            .tracking(2)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.32, blue: 0.32),
                        Color(red: 0.78, green: 0.10, blue: 0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: Color.red.opacity(0.55), radius: 24, x: 0, y: 0)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))

            VStack {
                Spacer()
                VStack(spacing: 10) {
                    Text("Password reset isn't wired up yet.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Tap anywhere to continue")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundColor(.white.opacity(0.45))
                }
                .multilineTextAlignment(.center)
                .padding(.bottom, 64)
                .opacity(subtitleOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.5)) {
                scale = 1
                rotation = 0
            }
            withAnimation(.easeIn(duration: 0.45).delay(0.55)) {
                subtitleOpacity = 1
            }
            withAnimation(
                .easeInOut(duration: 0.09)
                .repeatForever(autoreverses: true)
                .delay(0.6)
            ) {
                glitch = 5
            }
        }
        .transition(.opacity)
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.22)) {
            isPresented = false
        }
    }
}

// MARK: - Error banner

struct AuthErrorBanner: View {
    let message: String
    let palette: AuthPalette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(Color(red: 0.878, green: 0.353, blue: 0.353))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(red: 0.878, green: 0.353, blue: 0.353).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(red: 0.878, green: 0.353, blue: 0.353).opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Background

struct AuthBackground: View {
    let palette: AuthPalette

    var body: some View {
        ZStack {
            palette.background
            RadialGradient(
                colors: [palette.gold.opacity(0.10), Color.clear],
                center: UnitPoint(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}
