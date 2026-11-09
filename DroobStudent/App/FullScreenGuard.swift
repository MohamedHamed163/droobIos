import SwiftUI
import UIKit

// MARK: - FullScreenGuard (iPad full-screen-only — legacy Split View)
//
// Blacks out the app on iPad if it's shown SMALLER than the screen (classic
// Split View / Slide Over on iPadOS ≤ 18, where the window genuinely gets a
// smaller size). On iPhone this never triggers.
//
// iPadOS 26 NOTE: the new windowing scales the app inside a window at the
// compositor level, and every geometry API (`window.bounds`, `screen.bounds`,
// `screen.nativeBounds`) keeps reporting the FULL screen size — so a windowed
// app is indistinguishable from full-screen in code (verified empirically:
// cover stays 1.00 when windowed). There is no API to detect it, so this guard
// is a no-op on iPadOS 26 and only protects the older Split View model.
// Content is protected at ANY window size by `.captureProtected()` +
// `.screenshotRedacted()`, which don't depend on the window being full.

extension View {
    func fullScreenOnlyOniPad() -> some View {
        modifier(IPadFullScreenModifier())
    }
}

private struct IPadFullScreenModifier: ViewModifier {
    @State private var windowed = false
    @State private var pendingDim: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .overlay {
                if windowed { IPadFullScreenCover().zIndex(40) }
            }
            .background(WindowGeometryProbe { isFull in handle(isFull) })
    }

    private func handle(_ isFull: Bool) {
        // The probe can call this from `updateUIView` / `layoutSubviews`, which
        // run DURING a SwiftUI view update. Mutating @State there triggers
        // "Modifying state during view update" (undefined behavior), so defer
        // every state change to the next runloop tick.
        DispatchQueue.main.async {
            if isFull {
                pendingDim?.cancel(); pendingDim = nil
                if windowed { withAnimation(.easeInOut(duration: 0.2)) { windowed = false } }
            } else {
                guard !windowed, pendingDim == nil else { return }
                let item = DispatchWorkItem {
                    withAnimation(.easeInOut(duration: 0.2)) { windowed = true }
                    pendingDim = nil
                }
                pendingDim = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
            }
        }
    }
}

private struct WindowGeometryProbe: UIViewRepresentable {
    let onResult: (Bool) -> Void

    func makeUIView(context: Context) -> ProbeView { ProbeView(onResult: onResult) }
    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onResult = onResult
        uiView.measure()
    }

    final class ProbeView: UIView {
        var onResult: (Bool) -> Void
        init(onResult: @escaping (Bool) -> Void) {
            self.onResult = onResult
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.measure() }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            measure()
        }

        func measure() {
            guard UIDevice.current.userInterfaceIdiom == .pad else { onResult(true); return }
            guard let window = window, let screen = window.windowScene?.screen else { return }
            let win = window.bounds.size
            let scr = screen.bounds.size
            guard win.width > 200, win.height > 200,
                  scr.width > 200, scr.height > 200 else { return }
            let coverW = win.width / scr.width
            let coverH = win.height / scr.height
            onResult(coverW >= 0.95 && coverH >= 0.95)
        }
    }
}

private struct IPadFullScreenCover: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text(L10n.fullScreenRequiredTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(L10n.fullScreenRequiredMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .transition(.opacity)
    }
}
