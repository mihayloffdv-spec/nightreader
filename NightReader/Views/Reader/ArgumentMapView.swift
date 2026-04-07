import SwiftUI

// MARK: - Argument Map View
//
// Visual representation of a chapter's argument structure.
// Shows thesis → evidence → conclusion as a tree/flow diagram.
//
// ┌───────────────────────────────────┐
// │  ✦ Argument Map                   │
// │  Chapter: The Silent Growth       │
// │                                   │
// │  THESIS                           │
// │  ┃ "Growth requires patience..."  │
// │  ┃                                │
// │  EVIDENCE                         │
// │  ├─ "Studies show that..."        │
// │  ├─ "In 1987, researchers..."     │
// │  └─ "The moss colony doubled..." │
// │                                   │
// │  CONCLUSION                       │
// │  ┃ "Therefore, sustained..."      │
// └───────────────────────────────────┘

struct ArgumentMapView: View {
    let argumentMap: ArgumentMap
    let theme: Theme
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Chapter title
                    if let title = argumentMap.chapterTitle {
                        Text(title)
                            .font(theme.headlineFont(size: 22))
                            .foregroundStyle(theme.textPrimary)
                    }

                    // Thesis
                    argumentSection(
                        label: "ТЕЗИС",
                        icon: "target",
                        color: theme.accent,
                        items: [argumentMap.thesis]
                    )

                    // Evidence
                    argumentSection(
                        label: "ДОКАЗАТЕЛЬСТВА",
                        icon: "list.bullet",
                        color: theme.textSecondary,
                        items: argumentMap.evidence,
                        showConnectors: true
                    )

                    // Conclusion
                    argumentSection(
                        label: "ВЫВОД",
                        icon: "checkmark.circle",
                        color: theme.accent,
                        items: [argumentMap.conclusion]
                    )
                }
                .padding(24)
            }
            .background(theme.backgroundSheet)
            .navigationTitle("✦ Argument Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func argumentSection(
        label: String,
        icon: String,
        color: Color,
        items: [String],
        showConnectors: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(theme.captionFont(size: 12))
                    .foregroundStyle(color)
                    .kerning(2)
            }

            // Items
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 12) {
                    // Connector line
                    VStack(spacing: 0) {
                        if showConnectors {
                            let isLast = index == items.count - 1
                            Text(isLast ? "└" : "├")
                                .font(.system(size: 16, design: .monospaced))
                                .foregroundStyle(theme.textSecondary.opacity(0.5))
                        } else {
                            Rectangle()
                                .fill(color.opacity(0.5))
                                .frame(width: 3)
                        }
                    }
                    .frame(width: 16)

                    // Text
                    Text(item)
                        .font(.custom(theme.bodyFontName, size: 16))
                        .foregroundStyle(theme.textPrimary)
                        .lineSpacing(6)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.surfaceContainer)
        )
    }
}
