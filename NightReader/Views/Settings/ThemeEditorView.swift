import SwiftUI

struct ThemeEditorView: View {
    @Environment(\.dismiss) private var dismiss

    var editingTheme: Theme?
    var onSave: (Theme) -> Void

    @State private var name: String = ""
    @State private var bgColor: Color = Color(hex: "#0D0D0D")
    @State private var textColor: Color = Color(hex: "#D4D4C8")
    @State private var tintColor: Color = Color(hex: "#FFF0D4")

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
                    ColorPicker("Tint", selection: $tintColor, supportsOpacity: false)
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
                        let theme = Theme(
                            id: editingTheme?.id ?? UUID().uuidString,
                            name: name.isEmpty ? "Custom" : name,
                            bgColorHex: bgColor.toHex(),
                            textColorHex: textColor.toHex(),
                            tintColorHex: tintColor.toHex(),
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
                    bgColor = theme.bgColor
                    textColor = theme.textColor
                    tintColor = theme.tintColor
                }
            }
        }
    }
}
