import SwiftUI

// MARK: - Annotation Sheet (pixel-perfect from spec)
//
// Bottom sheet for adding reaction and action to a highlight.
// Two optional fields, "Готово" button.

struct AnnotationSheetView: View {
    let highlightText: String
    let theme: Theme
    @Binding var reaction: String
    @Binding var action: String
    let onSave: () -> Void
    let onDismiss: () -> Void

    // Colors from HTML mockup
    private let surfaceContainerLow = Color(hex: "#161d16")
    private let surfaceContainerHigh = Color(hex: "#242c24")
    private let onSurface = Color(hex: "#dde5d8")
    private let onSurfaceVariant = Color(hex: "#c5c7c1")
    private let primary = Color(hex: "#ffb599")
    private let onPrimary = Color(hex: "#5a1c00")
    private let accentDark = Color(hex: "#bd6440")
    private let outlineVariant = Color(hex: "#444843")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Highlighted text preview
                    Text("\u{201C}\(highlightText.prefix(200))\(highlightText.count > 200 ? "..." : "")\u{201D}")
                        .font(.custom("Noto Serif", size: 15))
                        .italic()
                        .foregroundStyle(onSurfaceVariant)
                        .lineLimit(3)

                    // Reaction field
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Почему зацепило?", systemImage: "theatermasks")
                            .font(.custom("Onest", size: 13).bold())
                            .foregroundStyle(primary)

                        TextEditor(text: $reaction)
                            .font(.custom("Noto Serif", size: 15))
                            .foregroundStyle(onSurface)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 60)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(surfaceContainerHigh)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(outlineVariant.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }

                    // Action field
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Что сделать?", systemImage: "bolt")
                            .font(.custom("Onest", size: 13).bold())
                            .foregroundStyle(primary)

                        TextEditor(text: $action)
                            .font(.custom("Noto Serif", size: 15))
                            .foregroundStyle(onSurface)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 60)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(surfaceContainerHigh)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(outlineVariant.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }

                    // Save button
                    Button(action: onSave) {
                        Text("Готово")
                            .font(.custom("Onest", size: 16).bold())
                            .foregroundStyle(onPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(
                                        LinearGradient(
                                            colors: [primary, accentDark],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    }
                }
                .padding(24)
            }
            .background(surfaceContainerLow)
            .navigationTitle("Аннотация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { onDismiss() }
                        .foregroundStyle(primary)
                }
            }
        }
    }
}
