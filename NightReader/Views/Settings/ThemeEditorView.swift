import SwiftUI

struct ThemeEditorView: View {
    @Environment(\.dismiss) private var dismiss

    var editingTheme: Theme?
    var onSave: (Theme) -> Void

    @State private var name: String = ""
    @State private var bgColor: Color = Color(hex: "#0B120B")
    @State private var textColor: Color = Color(hex: "#E8E0D4")
    @State private var accentColor: Color = Color(hex: "#CC704B")

    var body: some View {
        NavigationStack {
            List {
                // Preview
                Section {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(bgColor)
                            .frame(height: 120)
                            .overlay {
                                VStack(spacing: 8) {
                                    Text("Preview Text")
                                        .font(.headline)
                                        .foregroundStyle(textColor)
                                    Text("This is how your theme will look while reading a book at night.")
                                        .font(.caption)
                                        .foregroundStyle(textColor.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 20)
                                }
                            }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                // Name
                Section("Name") {
                    TextField("Theme name", text: $name)
                }

                // Colors
                Section("Colors") {
                    ColorPicker("Background", selection: $bgColor, supportsOpacity: false)
                    ColorPicker("Text", selection: $textColor, supportsOpacity: false)
                    ColorPicker("Accent", selection: $accentColor, supportsOpacity: false)
                }
            }
            .navigationTitle(editingTheme == nil ? "New Theme" : "Edit Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let bgHex = bgColor.toHex()
                        let textHex = textColor.toHex()
                        let accentHex = accentColor.toHex()
                        // Derive elevated/sheet from bg (slightly lighter)
                        let theme = Theme(
                            id: editingTheme?.id ?? UUID().uuidString,
                            name: name.isEmpty ? "Custom" : name,
                            backgroundHex: bgHex,
                            backgroundElevatedHex: bgHex,
                            backgroundSheetHex: bgHex,
                            textPrimaryHex: textHex,
                            textSecondaryHex: textHex,
                            accentHex: accentHex,
                            accentMutedHex: accentHex,
                            surfaceHex: textHex,
                            surfaceLightHex: textHex,
                            highlightOpacity: 0.25,
                            headlineFontName: "Onest-Bold",
                            bodyFontName: "NotoSerif",
                            bodyFontAltName: "NotoSerif",
                            labelFontName: "Onest-Medium",
                            captionFontName: "Onest-Regular",
                            libraryTitle: "Library",
                            settingsTitle: "Settings",
                            settingsSubtitle: "",
                            buttonRadius: 24,
                            cardBorderAccent: true,
                            isBuiltIn: false
                        )
                        onSave(theme)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let theme = editingTheme {
                    name = theme.name
                    bgColor = theme.background
                    textColor = theme.textPrimary
                    accentColor = theme.accent
                }
            }
        }
    }
}
