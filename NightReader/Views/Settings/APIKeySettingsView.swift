import SwiftUI

// MARK: - API Key Settings View
//
// Allows the user to enter and save their Claude API key.
// Key is stored in iOS Keychain (encrypted).
// Security: never loads existing key into @State — only accepts new input.

struct APIKeySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var saved = false
    @State private var hasExistingKey = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if hasExistingKey && apiKey.isEmpty {
                        // Show masked placeholder — never load actual key into memory
                        HStack {
                            Text("sk-ant-••••••••••••")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    } else {
                        SecureField("sk-ant-...", text: $apiKey)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Text("Claude API Key")
                } footer: {
                    if hasExistingKey && apiKey.isEmpty {
                        Text("Ключ сохранён. Введите новый ключ, чтобы заменить.")
                    } else {
                        Text("Ключ хранится в зашифрованном виде в iOS Keychain. Получить ключ можно на console.anthropic.com")
                    }
                }

                Section {
                    Button {
                        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        if KeychainManager.saveAPIKey(trimmed) {
                            saved = true
                            hasExistingKey = true
                            apiKey = ""  // clear from memory immediately
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if saved {
                                Label("Сохранено", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Text("Сохранить")
                            }
                            Spacer()
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if hasExistingKey {
                        Button(role: .destructive) {
                            KeychainManager.deleteAPIKey()
                            apiKey = ""
                            hasExistingKey = false
                        } label: {
                            HStack {
                                Spacer()
                                Text("Удалить ключ")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("AI Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .onAppear {
                hasExistingKey = KeychainManager.hasAPIKey
            }
        }
    }
}
