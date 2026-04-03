import SwiftUI

// MARK: - Settings View (pixel-perfect from HTML mockup)
//
// Translated 1:1 from Stitch HTML/CSS source.

struct SettingsView: View {
    // Exact colors from HTML tailwind config
    private let bg = Color(hex: "#0B120B")
    private let surface = Color(hex: "#0e150e")
    private let surfaceContainerLow = Color(hex: "#161d16")
    private let surfaceContainer = Color(hex: "#1a211a")
    private let surfaceContainerHigh = Color(hex: "#242c24")
    private let surfaceContainerHighest = Color(hex: "#2f372e")
    private let onSurface = Color(hex: "#dde5d8")
    private let onSurfaceVariant = Color(hex: "#c5c7c1")
    private let primary = Color(hex: "#ffb599")
    private let onPrimary = Color(hex: "#5a1c00")
    private let accent = Color(hex: "#CC704B")
    private let outlineVariant = Color(hex: "#444843")

    @State private var fontSize: Double = AppSettings.shared.readerFontSize
    @State private var fontFamily: String = AppSettings.shared.readerFontFamily
    @State private var atmosphericGlow: Double = AppSettings.shared.defaultDimmerOpacity
    @State private var selectedThemeId: String = AppSettings.shared.defaultThemeId

    private var theme: Theme { AppSettings.shared.currentTheme }

    var body: some View {
        ZStack {
            Color(hex: "#0e150e").ignoresSafeArea()

            // Ambient background blurs
            Circle().fill(primary.opacity(0.05)).frame(width: 400, height: 400)
                .blur(radius: 120).offset(x: 100, y: -200)
            Circle().fill(Color(hex: "#b9ccb0").opacity(0.05)).frame(width: 300, height: 300)
                .blur(radius: 100).offset(x: -100, y: 200)

            ScrollView {
                VStack(alignment: .leading, spacing: 48) { // space-y-12
                    // Header section
                    headerSection

                    // Preview card
                    previewCard

                    // Settings grid (space-y via gap-10 = 40px)
                    VStack(alignment: .leading, spacing: 40) {
                        typefaceSection
                        fontScaleSection
                        atmosphericGlowSection
                        windDownSection
                    }
                }
                .padding(.top, 16) // pt-24 minus header
                .padding(.bottom, 128) // pb-32
                .padding(.horizontal, 24) // px-6
            }
        }
        .onChange(of: selectedThemeId) { _, _ in
            fontFamily = AppSettings.shared.readerFontFamily
            fontSize = AppSettings.shared.readerFontSize
            atmosphericGlow = AppSettings.shared.defaultDimmerOpacity
        }
    }

    // MARK: - Header (space-y-2)

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // "PREFERENCES" — xs uppercase tracking-[0.15em] primary/70 bold
            Text("Preferences")
                .font(.custom("Onest", size: 12).bold())
                .textCase(.uppercase)
                .tracking(1.8) // 0.15em * 12
                .foregroundStyle(primary.opacity(0.7))

            // "Reading Interface" — 4xl extrabold tracking-tight
            Text("Reading Interface")
                .font(.custom("Onest", size: 36).weight(.heavy))
                .tracking(-0.4)
                .foregroundStyle(onSurface)

            // Subtitle — text-lg leading-relaxed on-surface-variant
            Text("Fine-tune your nocturnal sanctuary for the perfect focus.")
                .font(.custom("Noto Serif", size: 18))
                .foregroundStyle(onSurfaceVariant)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Preview Card

    private var previewCard: some View {
        ZStack(alignment: .topTrailing) {
            // Ghost icon top-right: auto_stories 8xl opacity-20
            Image(systemName: "book.fill")
                .font(.system(size: 80))
                .foregroundStyle(onSurface.opacity(0.05))
                .padding(16)

            VStack(alignment: .leading, spacing: 16) {
                // "LIVE PREVIEW" — sm bold primary/80 uppercase tracking-widest
                Text("Live Preview")
                    .font(.custom("Onest", size: 14).bold())
                    .textCase(.uppercase)
                    .tracking(4)
                    .foregroundStyle(primary.opacity(0.8))

                // Border-left content
                VStack(alignment: .leading, spacing: 16) {
                    // Quote — 2xl leading-relaxed italic medium
                    Text("\u{201C}The forest breathes in the deep of the night, a silent witness to the stories carved in shadows.\u{201D}")
                        .font(.custom(previewFontName, size: 24).weight(.medium))
                        .italic()
                        .foregroundStyle(onSurface)
                        .lineSpacing(6)

                    // Explanation — on-surface-variant leading-relaxed
                    Text("Adjust the settings below to see how the typography and atmosphere shift to match your current environment.")
                        .font(.custom("Noto Serif", size: 16))
                        .foregroundStyle(onSurfaceVariant)
                        .lineSpacing(4)
                }
                .padding(.leading, 24)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(primary.opacity(0.2))
                        .frame(width: 2)
                }
                .padding(.vertical, 8)
            }
            .padding(32) // p-8
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(surfaceContainerLow)
        )
        .shadow(color: .black.opacity(0.3), radius: 20)
    }

    // MARK: - Typeface Section

    private var typefaceSection: some View {
        VStack(alignment: .leading, spacing: 24) { // space-y-6
            // Header: icon + title
            HStack(spacing: 12) {
                Image(systemName: "textformat")
                    .foregroundStyle(primary)
                Text("Typeface")
                    .font(.custom("Onest", size: 18).bold())
                    .foregroundStyle(onSurface)
            }

            // Font cards
            VStack(spacing: 16) { // gap-4
                // Jakarta Sans (selected)
                fontCard(
                    fontName: theme.headlineFontName,
                    displayName: "Jakarta Sans",
                    subtitle: "Modern & Precise",
                    fontForDisplay: "Onest",
                    isSelected: fontFamily == theme.headlineFontName
                )

                // Source Serif
                fontCard(
                    fontName: theme.bodyFontName,
                    displayName: "Source Serif",
                    subtitle: "Warm & Humanist",
                    fontForDisplay: "Noto Serif",
                    isSelected: fontFamily == theme.bodyFontName
                )
            }
        }
    }

    private func fontCard(fontName: String, displayName: String, subtitle: String,
                          fontForDisplay: String, isSelected: Bool) -> some View {
        Button {
            fontFamily = fontName
            AppSettings.shared.readerFontFamily = fontName
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.custom(fontForDisplay, size: 20).bold())
                    .foregroundStyle(onSurface)

                Text(subtitle)
                    .font(.custom("Onest", size: 12))
                    .textCase(.uppercase)
                    .tracking(-0.4) // tracking-tighter
                    .foregroundStyle(onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20) // p-5
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? surfaceContainerHigh : surfaceContainerLow)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? primary : outlineVariant.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
    }

    // MARK: - Font Scale

    private var fontScaleSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header with current value
            HStack {
                HStack(spacing: 12) {
                    Image(systemName: "textformat.size")
                        .foregroundStyle(primary)
                    Text("Font Scale")
                        .font(.custom("Onest", size: 18).bold())
                        .foregroundStyle(onSurface)
                }
                Spacer()
                Text("\(Int(fontSize))px")
                    .font(.custom("Onest", size: 14).bold())
                    .foregroundStyle(primary)
            }

            // Slider card
            VStack(spacing: 16) {
                Slider(value: $fontSize, in: 12...32, step: 1)
                    .tint(primary)
                    .onChange(of: fontSize) { _, val in
                        AppSettings.shared.readerFontSize = val
                    }

                // A labels
                HStack {
                    Text("A")
                        .font(.custom("Onest", size: 10).bold())
                        .textCase(.uppercase)
                        .foregroundStyle(onSurfaceVariant)
                    Spacer()
                    Text("A")
                        .font(.custom("Onest", size: 18).bold())
                        .textCase(.uppercase)
                        .foregroundStyle(onSurfaceVariant)
                }
            }
            .padding(24) // p-6
            .background(RoundedRectangle(cornerRadius: 12).fill(surfaceContainerLow))
        }
    }

    // MARK: - Atmospheric Glow

    private var atmosphericGlowSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: "paintpalette")
                    .foregroundStyle(primary)
                Text("Atmospheric Glow")
                    .font(.custom("Onest", size: 18).bold())
                    .foregroundStyle(onSurface)
            }

            VStack(spacing: 32) { // space-y-8
                // Gradient preview bar: from-[#0B120B] via-[#1a211a] to-[#241c1a]
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#0B120B"), surfaceContainer, Color(hex: "#241c1a")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(height: 48) // h-12
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(outlineVariant.opacity(0.1), lineWidth: 1)
                        )

                    // Indicator line (center)
                    Rectangle()
                        .fill(primary)
                        .frame(width: 4, height: 64) // w-1 h-16
                        .clipShape(RoundedRectangle(cornerRadius: 9999))
                        .shadow(color: primary.opacity(0.5), radius: 7)
                        .offset(x: CGFloat(atmosphericGlow * 100 - 50)) // rough position
                }

                Slider(value: $atmosphericGlow, in: 0...0.8)
                    .tint(primary)
                    .onChange(of: atmosphericGlow) { _, val in
                        AppSettings.shared.defaultDimmerOpacity = val
                    }

                // Labels: xs headline bold uppercase tracking-widest
                HStack {
                    Text("Deep Moss")
                        .font(.custom("Onest", size: 12).bold())
                        .textCase(.uppercase)
                        .tracking(4)
                        .foregroundStyle(onSurfaceVariant)
                    Spacer()
                    Text("Warm Charcoal")
                        .font(.custom("Onest", size: 12).bold())
                        .textCase(.uppercase)
                        .tracking(4)
                        .foregroundStyle(onSurfaceVariant)
                }
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 12).fill(surfaceContainerLow))
        }
    }

    // MARK: - Wind-down Mode
    // TODO: Wire to actual dimming timer. For now visual placeholder matching mockup.

    private var windDownSection: some View {
        // p-6 rounded-xl bg-surface-container-highest, border-l-4 border-primary
        HStack(spacing: 16) {
            // Icon circle: w-12 h-12 bg-primary/10
            ZStack {
                Circle()
                    .fill(primary.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: "moon.fill")
                    .foregroundStyle(primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Wind-down Mode")
                    .font(.custom("Onest", size: 16).bold())
                    .foregroundStyle(onSurface)
                Text("Gradually dim warmth as night progresses.")
                    .font(.custom("Onest", size: 12))
                    .foregroundStyle(onSurfaceVariant)
            }

            Spacer()

            // Toggle: w-14 h-8 bg-primary rounded-full
            Toggle("", isOn: .constant(true))
                .tint(primary)
                .labelsHidden()
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(surfaceContainerHighest)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(primary)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private var previewFontName: String {
        if UIFont(name: fontFamily, size: 17) != nil { return fontFamily }
        return "Noto Serif"
    }
}
