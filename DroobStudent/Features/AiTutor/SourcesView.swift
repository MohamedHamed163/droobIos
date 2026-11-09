import SwiftUI

struct SourcesView: View {
    let sources: [TutorSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.sources)
                .font(.droobCaption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            ForEach(sources) { source in
                SourceRow(source: source)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct SourceRow: View {
    let source: TutorSource

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.caption)
                .foregroundColor(Color.droobPrimary)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(source.filename ?? "")
                        .font(.droobCaption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let page = source.page {
                        Text("\(L10n.page) \(page)")
                            .font(.droobCaption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.droobPrimary.opacity(0.15))
                            .foregroundColor(Color.droobPrimary)
                            .cornerRadius(4)
                    }
                }

                if let snippet = source.snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.droobCaption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}
