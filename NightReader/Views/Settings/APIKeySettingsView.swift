import SwiftUI

// MARK: - API Key Settings View
//
// Allows the user to enter and save their Claude API key.
// Key is stored in iOS Keychain (encrypted).

struct APIKeySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        if showKey {
                            TextField("sk-ant-...", text: $apiKey)
                                .font(.system(.body, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("sk-ant-...", text: $apiKey)
                                .font(.system(.body, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Claude API Key")
                } footer: {
                    Text("Ключ хранится в зашифрованном виде в iOS Keychain. Получить ключ можно на console.anthropic.com")
                }

                Section {
                    Button {
                        if KeychainManager.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            saved = true
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

                    if KeychainManager.hasAPIKey {
                        Button(role: .destructive) {
                            KeychainManager.deleteAPIKey()
                            apiKey = ""
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
                if let existing = KeychainManager.getAPIKey() {
                    apiKey = existing
                }
            }
        }
    }
}
