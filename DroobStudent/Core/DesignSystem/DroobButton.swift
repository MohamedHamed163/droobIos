import SwiftUI

// MARK: - PressableButtonStyle
//
// Applies opacity + subtle scale on press so any button using it gets
// consistent visual feedback regardless of its label content.

struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97
    var pressedOpacity: Double = 0.75

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - DroobButton

struct DroobButton: View {
    enum Style {
        case primary, secondary, destructive, ghost
    }

    let title: String
    let style: Style
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    init(
        _ title: String,
        style: Style = .primary,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
                } else {
                    Text(title)
                        .font(.droobHeadline)
                        .foregroundColor(foregroundColor)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(backgroundColor)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(borderColor, lineWidth: style == .secondary ? 1.5 : 0)
            )
        }
        .buttonStyle(.pressable)
        .disabled(isLoading || isDisabled)
        .opacity((isLoading || isDisabled) ? 0.6 : 1)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return Color.droobPrimary
        case .secondary: return Color.clear
        case .destructive: return Color.red
        case .ghost: return Color.clear
        }
    }

    /// Ink painted on the gold `.primary` fill.
    ///
    /// Gold is a light surface in both schemes (#C6A96B light, #D9BC88 dark), so
    /// white on it was 2.3:1 / 1.8:1 — failing in *both*. A warm near-black
    /// reads 8.4:1 on the light gold and 10.3:1 on the dark one, and matches the
    /// dark-on-gold ink the CTA gradients elsewhere already use.
    private static let onGold = Color(red: 0.08, green: 0.06, blue: 0.04)  // #140F0A

    private var foregroundColor: Color {
        switch style {
        case .primary: return Self.onGold
        case .secondary: return Color.droobPrimary
        // Kept white: `.destructive` sits on a saturated system red, which is a
        // dark fill in both schemes.
        case .destructive: return .white
        case .ghost: return Color.droobPrimary
        }
    }

    private var borderColor: Color {
        switch style {
        case .secondary: return Color.droobPrimary
        default: return .clear
        }
    }
}

// MARK: - Loading overlay modifier

struct LoadingOverlay: ViewModifier {
    let isLoading: Bool
    let message: String?

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isLoading)
            if isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    if let message = message {
                        Text(message)
                            .foregroundColor(.white)
                            .font(.droobSubheadline)
                    }
                }
                .padding(32)
                .background(Color.black.opacity(0.7))
                .cornerRadius(16)
            }
        }
    }
}

extension View {
    func loadingOverlay(isLoading: Bool, message: String? = nil) -> some View {
        modifier(LoadingOverlay(isLoading: isLoading, message: message))
    }

    /// Disables ScrollView bounce when the content fits the viewport, on iOS where supported.
    /// On iOS < 16.4, returns self unchanged.
    @ViewBuilder
    func droobBounceBasedOnSize() -> some View {
        if #available(iOS 16.4, *) {
            self.scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}

// MARK: - Error banner

struct ErrorBanner: View {
    let message: String
    let onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.red)
            Text(message)
                .font(.droobSubheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            if let onRetry = onRetry {
                DroobButton(L10n.retry, style: .secondary, action: onRetry)
                    .frame(width: 160)
            }
        }
        .padding()
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(icon: String, title: String, subtitle: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.droobTitle2)
                .multilineTextAlignment(.center)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.droobSubheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle = actionTitle, let action = action {
                DroobButton(actionTitle, action: action)
                    .frame(width: 200)
                    .padding(.top, 8)
            }
        }
        .padding(32)
    }
}
