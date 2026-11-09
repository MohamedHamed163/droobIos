import SwiftUI

struct FeedbackButtons: View {
    @Binding var selectedRating: String?
    let onFeedback: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            FeedbackButton(
                systemImage: "hand.thumbsup.fill",
                rating: "UP",
                selectedRating: selectedRating,
                onTap: { onFeedback("UP") }
            )
            FeedbackButton(
                systemImage: "hand.thumbsdown.fill",
                rating: "DOWN",
                selectedRating: selectedRating,
                onTap: { onFeedback("DOWN") }
            )
        }
    }
}

struct FeedbackButton: View {
    let systemImage: String
    let rating: String
    let selectedRating: String?
    let onTap: () -> Void

    private var isSelected: Bool { selectedRating == rating }
    private var isOtherSelected: Bool { selectedRating != nil && selectedRating != rating }

    var body: some View {
        Button(action: onTap) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundColor(isSelected
                                 ? (rating == "UP" ? .green : .red)
                                 : .secondary)
                .padding(6)
                .background(
                    isSelected
                    ? (rating == "UP" ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    : Color.clear
                )
                .cornerRadius(6)
                .opacity(isOtherSelected ? 0.4 : 1.0)
        }
        .disabled(selectedRating != nil)
        .accessibilityLabel(rating == "UP" ? L10n.feedbackThumbsUp : L10n.feedbackThumbsDown)
    }
}
