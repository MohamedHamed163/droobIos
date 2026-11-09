import SwiftUI
import UIKit

// MARK: - Figma color tokens
//
// All tokens resolve dynamically based on the active `UIUserInterfaceStyle`
// (driven by SwiftUI's `.preferredColorScheme(...)`), so the auth screens
// flip cleanly when the user taps the Dark / Light chip. Dark values come
// from the Figma; light values mirror the cream-on-warm palette the
// previous `AuthPalette` used so the light theme stays visually
// continuous with the rest of the app.

enum AuthFigmaColors {
    /// Page background — pure black on dark, warm cream on light.
    static let bg = dyn(
        dark:  UIColor.black,
        light: UIColor(red: 0.969, green: 0.953, blue: 0.918, alpha: 1.0)
    )
    /// Card / OTP-box surface.
    static let surface = dyn(
        dark:  UIColor(red: 0x1C / 255.0, green: 0x1C / 255.0, blue: 0x1E / 255.0, alpha: 1.0),
        light: UIColor.white
    )
    /// Chip surface — slightly lifted from the page bg.
    static let chipBg = dyn(
        dark:  UIColor(red: 0x2C / 255.0, green: 0x2C / 255.0, blue: 0x2E / 255.0, alpha: 1.0),
        light: UIColor(red: 0.941, green: 0.918, blue: 0.875, alpha: 1.0)
    )
    /// Inline-row separators.
    static let divider = dyn(
        dark:  UIColor(red:  84 / 255.0, green:  84 / 255.0, blue:  88 / 255.0, alpha: 0.36),
        light: UIColor(red:  60 / 255.0, green:  60 / 255.0, blue:  67 / 255.0, alpha: 0.36)
    )
    /// Primary text — white in dark, near-black warm in light.
    static let textPrimary = dyn(
        dark:  UIColor.white,
        light: UIColor(red: 0.082, green: 0.075, blue: 0.059, alpha: 1.0)
    )
    /// Subtitle / muted text — rgba(235,235,245,0.60) in dark.
    static let muted = dyn(
        dark:  UIColor(red: 235 / 255.0, green: 235 / 255.0, blue: 245 / 255.0, alpha: 0.60),
        light: UIColor(red:  60 / 255.0, green:  60 / 255.0, blue:  67 / 255.0, alpha: 0.60)
    )
    /// Brand gold (kept stable across themes; reads on both bgs).
    static let gold        = Color(red: 0.776, green: 0.663, blue: 0.420)
    static let goldStrong  = Color(red: 0.878, green: 0.769, blue: 0.561)
    /// Primary CTA gradient stops — Figma `Button-gradient`.
    /// 90deg LTR: #C6A96B at 29.33% → #605234 at 94.71%.
    static let buttonGradStart = Color(red: 0xC6 / 255.0, green: 0xA9 / 255.0, blue: 0x6B / 255.0)
    static let buttonGradEnd   = Color(red: 0x60 / 255.0, green: 0x52 / 255.0, blue: 0x34 / 255.0)
    /// Error red — Apple's adaptive system red.
    static let errorRed = dyn(
        dark:  UIColor(red: 0xFF / 255.0, green: 0x45 / 255.0, blue: 0x3A / 255.0, alpha: 1.0),
        light: UIColor(red: 0xFF / 255.0, green: 0x3B / 255.0, blue: 0x30 / 255.0, alpha: 1.0)
    )
    static let errorRedBg = dyn(
        dark:  UIColor(red: 0xFF / 255.0, green: 0x45 / 255.0, blue: 0x3A / 255.0, alpha: 0.09),
        light: UIColor(red: 0xFF / 255.0, green: 0x3B / 255.0, blue: 0x30 / 255.0, alpha: 0.09)
    )
    static let successGreen = Color(red: 0.20, green: 0.83, blue: 0.45)
    /// Translucent chrome behind the chip bar.
    static let chromeBg = dyn(
        dark:  UIColor(red:  28 / 255.0, green:  28 / 255.0, blue:  30 / 255.0, alpha: 0.88),
        light: UIColor(red: 255 / 255.0, green: 255 / 255.0, blue: 255 / 255.0, alpha: 0.78)
    )

    /// Helper: SwiftUI Color that resolves through the current
    /// `UITraitCollection.userInterfaceStyle`. SwiftUI updates the bound
    /// view automatically when `.preferredColorScheme` changes.
    private static func dyn(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - Locale helper
//
// Fraunces has no Arabic glyph coverage, so every typography call site
// branches on this flag and falls back to the system serif italic for ar.

private func isArabicLocale() -> Bool {
    L10n.currentLanguageCode == "ar"
}

// MARK: - Chip bar (Dark / EN)
//
// Edge-to-edge translucent strip at the very top of every auth screen.
// Surface: `rgba(28,28,30,0.88)` with a 10pt backdrop blur and a thin
// `rgba(84,84,88,0.36)` bottom border — pulled straight from Figma.
//
// The two chips (theme + locale) sit inside with 14pt horizontal padding.
// Hosting screens should place this OUTSIDE the ScrollView so it remains
// fixed at the top while content scrolls behind it.

struct AuthChipBar: View {
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @AppStorage("appColorScheme") private var appColorScheme: String = AppColorSchemeDefault.code
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AuthChip(
                icon: appColorScheme == "light" ? "sun.max.fill" : "moon.fill",
                label: appColorScheme == "light" ? L10n.themeLight : L10n.themeDark
            ) {
                onTap()
                appColorScheme = appColorScheme == "light" ? "dark" : "light"
            }
            Spacer()
            // Same gate as `AuthHeaderBar`: an un-gated writer of the
            // `appLocale` key must not survive the lock. The `Spacer()` above
            // keeps the theme chip pinned to its edge with the globe gone, so
            // hiding it leaves no dead space.
            if !AppLocaleDefault.englishHidden {
                AuthChip(
                    icon: "globe",
                    label: appLocale.uppercased()
                ) {
                    onTap()
                    appLocale = appLocale == "ar" ? "en" : "ar"
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(
            // Translucent surface that lets content blur through if it
            // scrolls under. `.ultraThinMaterial` provides the system blur;
            // the colored overlay matches the Figma tokens (dark variant
            // = `color-grey-1188`, light variant = warm white).
            ZStack {
                AuthFigmaColors.chromeBg.background(.ultraThinMaterial)
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AuthFigmaColors.divider)
                .frame(height: 1)
        }
    }
}

private struct AuthChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String?
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(label)
                    .font(BrandFont.display(size: 13, isArabic: isArabicLocale()))
            }
            .foregroundColor(AuthFigmaColors.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                colorScheme == .dark
                    ? Color.white.opacity(0.06)
                    : Color.black.opacity(0.05)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Back link
//
// Gold "< Sign In" or "< Back" affordance that sits between the chip bar
// and the screen title.

struct AuthBackLink: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(BrandFont.display(size: 17, isArabic: isArabicLocale()))
            }
            .foregroundColor(AuthFigmaColors.gold)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Logo
//
// Brand "D" mark, optionally with a radial gold glow underneath. The Sign-In
// screen uses the glow; the smaller header logos don't.

struct AuthLogo: View {
    var size: CGFloat = 72
    var showGlow: Bool = true

    var body: some View {
        ZStack {
            if showGlow {
                RadialGradient(
                    colors: [AuthFigmaColors.gold.opacity(0.40), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.85
                )
                .frame(width: size * 1.9, height: size * 1.9)
                .blur(radius: 8)
            }
            Image("DroobLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.30, style: .continuous))
                .shadow(color: AuthFigmaColors.gold.opacity(0.25), radius: 12, x: 0, y: 6)
        }
    }
}

// MARK: - Section header (e.g. "YOUR INFO")
//
// Spec: Fraunces italic 13pt, letter-spacing 0.26, uppercase, muted color.

struct AuthSectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(BrandFont.display(size: 13, isArabic: isArabicLocale()))
            .tracking(isArabicLocale() ? 0 : 0.26)
            .textCase(.uppercase)
            .foregroundColor(AuthFigmaColors.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Inline row card
//
// Groups one or more `InlineRow`s inside a #1C1C1E 16-radius surface.
// Rows are responsible for their own dividers via the `InlineRowGroup`
// helper below — keeps callsites declarative ("just hand me three fields").

struct InlineRowCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(AuthFigmaColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Inline row
//
// One label-on-leading-edge / value-on-trailing-edge field. Tap anywhere on
// the row to focus the input. Supports normal text, secure text, an optional
// trailing button (e.g. "Show"), and a red error state that recolors both
// the label and the bottom divider.

struct InlineRow: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var autocap: TextInputAutocapitalization = .sentences
    var autocorrection: Bool = true
    var submitLabel: SubmitLabel = .next
    var isError: Bool = false
    /// Hides the value below an asterisk render even when `isSecure == false`.
    /// Used by the password row to drive its `Show / Hide` toggle.
    var revealSecure: Bool = false
    var trailing: AnyView? = nil
    var showDivider: Bool = true

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(label)
                    .font(BrandFont.display(size: 17, isArabic: isArabicLocale()))
                    .foregroundColor(isError ? AuthFigmaColors.errorRed : AuthFigmaColors.textPrimary)

                Spacer(minLength: 12)

                Group {
                    if isSecure && !revealSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(BrandFont.display(size: 17, isArabic: isArabicLocale()))
                .foregroundColor(AuthFigmaColors.muted)
                .tint(AuthFigmaColors.gold)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled(!autocorrection)
                .submitLabel(submitLabel)
                .modifier(OptionalContentTypeModifier(type: contentType))
                .multilineTextAlignment(.trailing)
                .focused($focused)

                if let trailing {
                    trailing
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            if showDivider {
                Rectangle()
                    .fill(AuthFigmaColors.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
    }
}

private struct OptionalContentTypeModifier: ViewModifier {
    let type: UITextContentType?
    func body(content: Content) -> some View {
        if let type { content.textContentType(type) } else { content }
    }
}

// MARK: - Primary gold button
//
// 56pt-tall full-width capsule with the brand gold gradient. Used as the
// hero CTA on every auth screen (Sign In / Create Account / Send Code /
// Verify). Shows a spinner + label while `isLoading == true`.

struct AuthPrimaryGold: View {
    let title: String
    var loadingTitle: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var height: CGFloat = 56
    var leadingSystemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(
                            tint: Color(red: 0.08, green: 0.06, blue: 0.04)))
                        .scaleEffect(0.9)
                    Text(loadingTitle ?? title)
                        .font(BrandFont.displaySemiBold(size: 17, isArabic: isArabicLocale()))
                } else {
                    if let leadingSystemImage {
                        Image(systemName: leadingSystemImage)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(title)
                        .font(BrandFont.displaySemiBold(size: 17, isArabic: isArabicLocale()))
                }
            }
            .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(LinearGradient.droobButtonGradient
                .opacity((isLoading || isDisabled) ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isDisabled)
    }
}

// MARK: - Shared button gradient
//
// Figma `Button-gradient`: 90deg, `#C6A96B` at 29.33% → `#605234` at 94.71%.
// Centralized so every primary CTA in the auth + onboarding flows draws
// from the same definition.

extension LinearGradient {
    static let droobButtonGradient = LinearGradient(
        stops: [
            .init(color: AuthFigmaColors.buttonGradStart, location: 0.2933),
            .init(color: AuthFigmaColors.buttonGradEnd,   location: 0.9471),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Secondary dark button
//
// 50pt-tall flat button on #1C1C1E. Used for "Reset Password" beneath the
// error-state CTA. Centered Fraunces italic 17pt.

struct AuthSecondaryDark: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BrandFont.display(size: 17, isArabic: isArabicLocale()))
                .foregroundColor(AuthFigmaColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(AuthFigmaColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Error banner
//
// Translucent-red surface above the form on error. Two stacked lines:
// the bold title + optional secondary detail (e.g. "2 attempts remaining
// before your account is locked.").

struct AuthFigmaErrorBanner: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BrandFont.display(size: 14, isArabic: isArabicLocale()))
                    .foregroundColor(AuthFigmaColors.errorRed)
                if let detail {
                    Text(detail)
                        .font(BrandFont.display(size: 14, isArabic: isArabicLocale()))
                        .foregroundColor(AuthFigmaColors.errorRed.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundColor(AuthFigmaColors.errorRed)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuthFigmaColors.errorRedBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Or divider (used by Sign In)
//
// Horizontal rule with centered "or" label.

struct AuthOrDivider: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
            Text(label)
                .font(BrandFont.display(size: 13, isArabic: isArabicLocale()))
                .foregroundColor(AuthFigmaColors.muted)
                .fixedSize()
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
    }
}

// MARK: - Social button (Google / Apple)
//
// Dark surface, brand icon on left, label centered. 56pt tall.

struct AuthSocialButton<Icon: View>: View {
    let icon: () -> Icon
    let label: String
    let action: () -> Void

    init(label: String, action: @escaping () -> Void, @ViewBuilder icon: @escaping () -> Icon) {
        self.label = label
        self.action = action
        self.icon = icon
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon()
                Text(label)
                    .font(BrandFont.display(size: 17, isArabic: isArabicLocale()))
                    .foregroundColor(AuthFigmaColors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(AuthFigmaColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - OTP code field (6 separate boxes)
//
// Six 46×56 `#1C1C1E`-filled boxes. User types one digit at a time and focus
// auto-advances to the next box; backspace on an empty box moves focus back
// (requires the UIKit-backed `BackspaceTextField` below — SwiftUI's plain
// `TextField` doesn't surface the empty-delete event).

struct OTPCodeField: View {
    @Binding var code: String
    var digitCount: Int = 6
    var isError: Bool = false
    var onComplete: ((String) -> Void)? = nil

    @State private var digits: [String] = []
    @FocusState private var focusedIndex: Int?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<digitCount, id: \.self) { i in
                box(at: i)
            }
        }
        .onAppear {
            if digits.count != digitCount {
                digits = Array(repeating: "", count: digitCount)
            }
            seedFromCode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedIndex = firstEmptyIndex() ?? 0
            }
        }
        .onChange(of: code) { newValue in
            // External update (e.g. SMS autofill via parent paste).
            if newValue.count == digitCount, newValue != digits.joined() {
                seedFromCode()
            }
        }
    }

    private func box(at index: Int) -> some View {
        BackspaceTextField(
            text: Binding(
                get: { digits[safe: index] ?? "" },
                set: { newVal in handleInput(at: index, newVal: newVal) }
            ),
            onBackspaceWhenEmpty: {
                if index > 0 {
                    focusedIndex = index - 1
                }
            },
            keyboardType: .numberPad,
            // Adaptive: white digits on dark surface, near-black on light.
            textColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.white
                    : UIColor(red: 0.082, green: 0.075, blue: 0.059, alpha: 1.0)
            },
            font: otpDigitFont(size: 24),
            isFirstField: index == 0
        )
        .frame(width: 46, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AuthFigmaColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isError ? AuthFigmaColors.errorRed.opacity(0.6) :
                        (focusedIndex == index ? AuthFigmaColors.gold.opacity(0.6) : Color.clear),
                    lineWidth: 1)
        )
        .focused($focusedIndex, equals: index)
        .onTapGesture { focusedIndex = index }
    }

    private func handleInput(at index: Int, newVal: String) {
        let filtered = newVal.filter(\.isNumber)
        if filtered.isEmpty {
            // Deletion handled by BackspaceTextField.onBackspaceWhenEmpty.
            digits[index] = ""
        } else if filtered.count == digitCount {
            // Pasted full code into one box — distribute.
            for (i, ch) in filtered.prefix(digitCount).enumerated() {
                digits[i] = String(ch)
            }
            focusedIndex = digitCount - 1
        } else {
            // Single digit (or user typed over an existing digit).
            digits[index] = String(filtered.suffix(1))
            if index < digitCount - 1 {
                focusedIndex = index + 1
            }
        }
        let joined = digits.joined()
        code = joined
        if joined.count == digitCount {
            onComplete?(joined)
        }
    }

    private func seedFromCode() {
        if digits.count != digitCount {
            digits = Array(repeating: "", count: digitCount)
        }
        for i in 0..<digitCount {
            let charIndex = code.index(code.startIndex, offsetBy: i, limitedBy: code.endIndex)
            if let charIndex, charIndex < code.endIndex {
                digits[i] = String(code[charIndex])
            } else {
                digits[i] = ""
            }
        }
    }

    private func firstEmptyIndex() -> Int? {
        digits.firstIndex(where: { $0.isEmpty })
    }

    /// UIKit twin of `BrandFont.display` — OTP boxes are UIKit-backed, so they
    /// need a `UIFont` rather than a SwiftUI `Font`. Upright in both locales.
    private func otpDigitFont(size: CGFloat) -> UIFont {
        if isArabicLocale() {
            return UIFont.systemFont(ofSize: size, weight: .regular)
        }
        return UIFont(name: BrandFont.interRegular, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .regular)
    }
}

// MARK: - UIKit-backed text field with empty-delete callback
//
// SwiftUI's `TextField` doesn't fire a change event when the user hits
// backspace on an already-empty field, so we drop down to UIKit and
// override `deleteBackward()`. Used solely by `OTPCodeField` to support
// "back-stepping" focus through empty boxes.

private struct BackspaceTextField: UIViewRepresentable {
    @Binding var text: String
    var onBackspaceWhenEmpty: () -> Void
    var keyboardType: UIKeyboardType = .default
    var textColor: UIColor = .white
    var font: UIFont
    var isFirstField: Bool = false

    final class Coordinator: NSObject, UITextFieldDelegate {
        let parent: BackspaceTextField
        init(_ parent: BackspaceTextField) { self.parent = parent }

        @objc func editingChanged(_ tf: UITextField) {
            parent.text = tf.text ?? ""
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> InnerTextField {
        let tf = InnerTextField()
        tf.delegate = context.coordinator
        tf.keyboardType = keyboardType
        tf.textColor = textColor
        tf.font = font
        tf.textAlignment = .center
        tf.tintColor = .clear  // hide caret in single-digit boxes
        tf.borderStyle = .none
        tf.backgroundColor = .clear
        if isFirstField {
            tf.textContentType = .oneTimeCode  // SMS autofill on box 0
        }
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        tf.onDeleteBackwardWhenEmpty = onBackspaceWhenEmpty
        return tf
    }

    func updateUIView(_ uiView: InnerTextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.font = font
        uiView.textColor = textColor
        uiView.onDeleteBackwardWhenEmpty = onBackspaceWhenEmpty
    }

    final class InnerTextField: UITextField {
        var onDeleteBackwardWhenEmpty: () -> Void = {}
        override func deleteBackward() {
            if text?.isEmpty ?? true {
                onDeleteBackwardWhenEmpty()
            }
            super.deleteBackward()
        }
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
