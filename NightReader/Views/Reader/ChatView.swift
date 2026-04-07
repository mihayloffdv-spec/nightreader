import SwiftUI

// MARK: - AI Chat View
//
// Ask questions about the book. Claude answers with chapter context.
// Simple message list + text input.

struct ChatView: View {
    @Bindable var viewModel: ReaderViewModel
    let theme: Theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if viewModel.chatMessages.isEmpty {
                                emptyState
                            }
                            ForEach(viewModel.chatMessages) { msg in
                                messageBubble(msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: viewModel.chatMessages.count) { _, _ in
                        if let last = viewModel.chatMessages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider().foregroundStyle(theme.surface)

                // Input bar
                HStack(spacing: 12) {
                    TextField("Ask about the book...", text: $viewModel.chatInputText, axis: .vertical)
                        .font(theme.bodyFont(size: 15))
                        .lineLimit(1...4)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(theme.surfaceContainerHigh)
                        )

                    Button {
                        viewModel.sendChatMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(
                                viewModel.chatInputText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? theme.surface : theme.accent
                            )
                    }
                    .disabled(viewModel.chatInputText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(theme.background)
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
            .toolbarBackground(theme.background, for: .navigationBar)
        }
    }

    private func messageBubble(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.role == "user" { Spacer(minLength: 60) }

            VStack(alignment: msg.role == "user" ? .trailing : .leading, spacing: 4) {
                if msg.role == "assistant" {
                    Text("✦ AI")
                        .font(theme.captionFont(size: 10))
                        .textCase(.uppercase)
                        .tracking(1.5)
                        .foregroundStyle(theme.accent)
                }
                Text(msg.content)
                    .font(theme.bodyFont(size: 15))
                    .foregroundStyle(theme.onSurface)
                    .textSelection(.enabled)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(msg.role == "user" ? theme.accent.opacity(0.15) : theme.surfaceContainerLow)
            )

            if msg.role == "assistant" { Spacer(minLength: 60) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(theme.surface)
            Text("Ask anything about the book")
                .font(theme.labelFont(size: 15))
                .foregroundStyle(theme.onSurfaceVariant)
            Text("AI will use the current chapter as context")
                .font(theme.captionFont(size: 12))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
