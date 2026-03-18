import SwiftUI

// MARK: - AI Action Bottom Sheet
//
// Shows AI response (explanation or translation) in a draggable bottom sheet.
// Supports loading, success, and error states.

struct AIActionSheet: View {
    let actionType: AIActionType
    let selectedText: String
    let state: AIResponseState
    let theme: Theme
    let onDismiss: () -> Void
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Selected text (quoted)
                    Text("«\(selectedText.prefix(200))\(selectedText.count > 200 ? "…" : "")»")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                        .padding(.horizontal)

                    Divider()

                    // Response content
                    switch state {
                    case .idle:
                        EmptyView()

                    case .loading:
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(.primary)
                                Text("Думаю…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 40)

                    case .success(let response):
                        Text(response)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(.horizontal)

                    case .error(let message):
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title)
                                .foregroundStyle(.orange)

                            Text(message)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                if message.contains("ключ") {
                                    Button("Настройки") {
                                        onOpenSettings()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                                Button("Повторить") {
                                    onRetry()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(actionType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { onDismiss() }
                }
            }
        }
    }
}
