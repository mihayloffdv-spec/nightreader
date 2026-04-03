import SwiftUI

// MARK: - Settings View (Deep Forest design)
//
// Full-screen settings with live preview, font pills, sliders.
// Matches the "Reading Interface" mockup.

struct SettingsView: View {
    private var theme: Theme { AppSettings.shared.currentTheme }

    @State private var selectedThemeId: String = AppSettings.shared.defaultThemeId
    @State private var fontSize: Double = AppSettings.shared.readerFontSize
    @State private var fontFamily: String = AppSettings.shared.readerFontFamily
    @State private var atmosphericGlow: Double = AppSettings.shared.defaultDimmerOpacity

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PREFERENCES")
                            .font(theme.captionFont(size: 11))
                            .foregroundStyle(theme.textSecondary)
                            .kerning(2)

                        Text(theme.settingsTitle)
                            .font(theme.headlineFont(size: 28))
                            .foregroundStyle(theme.textPrimary)

                        if !theme.settingsSubtitle.isEmpty {
                            Text(theme.settingsSubtitle)
                                .font(theme.captionFont(size: 14))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    .padding(.top, 16)

                    // Live Preview
                    livePreview

                    // Typeface
                    typefaceSection

                    // Font Scale
                    fontScaleSection

                    // Atmospheric Glow
                    atmosphericGlowSection

                    // Wind-down Mode
                    windDownSection

                    // Theme picker
                    themePickerSection

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 24)
            }
        }
        .onChange(of: selectedThemeId) { _, _ in
            // Reset local @State snapshots when theme changes
            // so font pills and sliders reflect the new theme's defaults
            fontFamily = AppSettings.shared.readerFontFamily
            fontSize = AppSettings.shared.readerFontSize
            atmosphericGlow = AppSettings.shared.defaultDimmerOpacity
        }
    }

    // MARK: - Live Preview

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIVE PREVIEW")
                .font(theme.captionFont(size: 11))
                .foregroundStyle(theme.textSecondary)
                .kerning(2)

            RoundedRectangle(cornerRadius: 16)
                .fill(theme.backgroundElevated)
                .overlay(
                    Text("\u{201C}The forest breathes in the deep of the night, a silent witness to the stories carved in shadows.\u{201D}")
                        .font(.custom(previewFontName, size: fontSize))
                        .italic()
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(24)
                )
                .frame(height: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.surface.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: - Typeface

    private var typefaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Typeface", systemImage: "textformat")
                .font(theme.labelFont(size: 15))
                .foregroundStyle(theme.textPrimary)

            // Primary font choice
            HStack(spacing: 12) {
                fontPill(name: theme.headlineFontName, displayName: displayFontName(theme.headlineFontName), isSelected: fontFamily == theme.headlineFontName)
                fontPill(name: theme.bodyFontName, displayName: displayFontName(theme.bodyFontName), isSelected: fontFamily == theme.bodyFontName)
            }

            // Secondary font choices
            HStack(spacing: 12) {
                fontPill(name: theme.bodyFontAltName, displayName: displayFontName(theme.bodyFontAltName), isSelected: fontFamily == theme.bodyFontAltName)
            }
        }
    }

    private func fontPill(name: String, displayName: String, isSelected: Bool) -> some View {
        Button {
            fontFamily = name
            AppSettings.shared.readerFontFamily = name
        } label: {
            Text(displayName)
                .font(.custom(name, size: 15))
                .foregroundStyle(isSelected ? theme.background : theme.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? theme.accent : theme.backgroundElevated)
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : theme.surface.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: - Font Scale

    private var fontScaleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Font Scale", systemImage: "textformat.size")
                .font(theme.labelFont(size: 15))
                .foregroundStyle(theme.textPrimary)

            HStack(spacing: 16) {
                Text("Tt")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)

                Slider(value: $fontSize, in: 14...28, step: 1)
                    .tint(theme.accent)
                    .onChange(of: fontSize) { _, newValue in
                        AppSettings.shared.readerFontSize = newValue
                    }

                Text("Tt")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    // MARK: - Atmospheric Glow

    private var atmosphericGlowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Atmospheric Glow", systemImage: "sun.max")
                .font(theme.labelFont(size: 15))
                .foregroundStyle(theme.textPrimary)

            Slider(value: $atmosphericGlow, in: 0...0.8)
                .tint(theme.accent)
                .onChange(of: atmosphericGlow) { _, newValue in
                    AppSettings.shared.defaultDimmerOpacity = newValue
                }

            HStack {
                Text("DEEP MOSS")
                    .font(theme.captionFont(size: 10))
                    .foregroundStyle(theme.textSecondary)
                    .kerning(1)
                Spacer()
                Text("WARM EMBER")
                    .font(theme.captionFont(size: 10))
                    .foregroundStyle(theme.textSecondary)
                    .kerning(1)
            }
        }
    }

    // MARK: - Wind-down Mode
    // TODO: Wire windDownMode to a timer that gradually increases dimmer over 30 min.
    // Needs: AppSettings persistence, ReaderViewModel timer, gradual opacity animation.

    private var windDownSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label("Wind-down Mode", systemImage: "moon.fill")
                    .font(theme.labelFont(size: 15))
                    .foregroundStyle(theme.textSecondary)

                Text("Coming soon")
                    .font(theme.captionFont(size: 12))
                    .foregroundStyle(theme.textSecondary.opacity(0.5))
            }

            Spacer()

            Toggle("", isOn: .constant(false))
                .tint(theme.accent)
                .labelsHidden()
                .disabled(true)
        }
        .opacity(0.5)
    }

    // MARK: - Theme Picker

    private var themePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Theme", systemImage: "paintpalette")
                .font(theme.labelFont(size: 15))
                .foregroundStyle(theme.textPrimary)

            HStack(spacing: 16) {
                ForEach(Theme.allBuiltIn) { t in
                    Button {
                        selectedThemeId = t.id
                        AppSettings.shared.defaultThemeId = t.id
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: t.accentHex))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(selectedThemeId == t.id ? theme.textPrimary : Color.clear, lineWidth: 2)
                                        .padding(-3)
                                )

                            Text(t.name)
                                .font(theme.captionFont(size: 10))
                                .foregroundStyle(selectedThemeId == t.id ? theme.textPrimary : theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var previewFontName: String {
        fontFamily.isEmpty ? theme.bodyFontName : fontFamily
    }

    private func displayFontName(_ name: String) -> String {
        // Clean up family name for display
        name.replacingOccurrences(of: " 4", with: "")
    }
}
