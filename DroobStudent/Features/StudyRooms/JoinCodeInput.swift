import SwiftUI
import UIKit

/// 6-digit boxed input for the room code, with an explicit `Paste`
/// button beneath. Visually: three boxes, an em-dash gap, three boxes.
/// Internally: a single hidden `TextField` captures the input so the
/// keyboard, autofill and shortcuts (Paste, ⌘V) all just work; the
/// boxes are read-only renderers driven by the underlying string.
struct JoinCodeInput: View {
    /// Canonical 6-character form (no hyphen). Parent binds and reads
    /// this — the view trims to 6 alphanumerics on input.
    @Binding var code: String
    /// Called once the user has typed all 6 characters. The parent
    /// uses this to fire the join request (no manual submit button).
    var onComplete: ((String) -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // Hidden text field — receives the actual keyboard
                // input. Behind the boxes; tapping any box gives it
                // focus.
                TextField("", text: $code)
                    .textContentType(.oneTimeCode) // SMS / clipboard autofill
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($focused)
                    .opacity(0.001) // not 0 — must remain hit-testable
                    .frame(width: 1, height: 1)
                    .onChange(of: code) { newValue in
                        let clean = JoinCodeFormat.strip(newValue)
                        let capped = String(clean.prefix(6))
                        if capped != newValue { code = capped }
                        if capped.count == 6 { onComplete?(capped) }
                    }

                HStack(spacing: 8) {
                    digitBox(at: 0)
                    digitBox(at: 1)
                    digitBox(at: 2)
                    Text("—")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(MyCoursesPalette.textTertiary)
                    digitBox(at: 3)
                    digitBox(at: 4)
                    digitBox(at: 5)
                }
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
            }

            Button {
                let raw = UIPasteboard.general.string ?? ""
                let normalised = JoinCodeFormat.strip(raw)
                if !normalised.isEmpty {
                    code = String(normalised.prefix(6))
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12, weight: .semibold))
                    Text(L10n.studyRoomsPasteCode)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(MyCoursesPalette.muted)
            }
            .buttonStyle(.plain)
        }
        .onAppear { focused = true }
    }

    @ViewBuilder
    private func digitBox(at index: Int) -> some View {
        // Character at `index` if any, else empty.
        let char: String = {
            guard index < code.count else { return "" }
            let i = code.index(code.startIndex, offsetBy: index)
            return String(code[i])
        }()
        // Highlight the active (first-empty) box with a gold ring.
        let isActive = focused && code.count == index
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MyCoursesPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isActive
                            ? MyCoursesPalette.accent.opacity(0.85)
                            : MyCoursesPalette.stroke,
                            lineWidth: isActive ? 1.5 : 1))
            Text(char)
                .font(.system(size: 24, weight: .bold,
                              design: .monospaced))
                .foregroundColor(MyCoursesPalette.accent)
        }
        .frame(width: 48, height: 60)
    }
}
