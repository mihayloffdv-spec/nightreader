import SwiftUI

// MARK: - Theme
//
// Full design token system. Each theme defines colors, fonts, and UI personality.
//
// ┌─────────────────────────────────────────────┐
// │                  Theme                       │
// │                                             │
// │  Colors (10 tokens)                         │
// │  ├── background / elevated / sheet          │
// │  ├── textPrimary / textSecondary            │
// │  ├── accent / accentMuted                   │
// │  └── surface / surfaceLight / highlightBg   │
// │                                             │
// │  Fonts (5 tokens)                           │
// │  ├── headlineFont (display, titles)         │
// │  ├── bodyFont / bodyFontAlt (reading)       │
// │  └── labelFont / captionFont (UI)           │
// │                                             │
// │  UI Language (theme personality)            │
// │  └── libraryTitle, settingsTitle, etc.      │
// │                                             │
// │  Style (component shapes)                   │
// │  └── buttonRadius, cardBorderAccent         │
// └─────────────────────────────────────────────┘

struct Theme: Identifiable, Codable, Hashable {
    let id: String
    let name: String

    // MARK: - Colors

    let backgroundHex: String
    let backgroundElevatedHex: String
    let backgroundSheetHex: String
    let textPrimaryHex: String
    let textSecondaryHex: String
    let accentHex: String
    let accentMutedHex: String
    let surfaceHex: String
    let surfaceLightHex: String
    let highlightOpacity: Double

    // MARK: - Day Mode Colors

    let dayBackgroundHex: String
    let dayTextPrimaryHex: String
    let dayTextSecondaryHex: String
    let dayAccentHex: String
    let dayHighlightHex: String
    let dayDividerHex: String

    // MARK: - Day Mode UI

    let dayTitle: String           // "Reading Sanctuary"

    // MARK: - Fonts

    let headlineFontName: String
    let bodyFontName: String
    let bodyFontAltName: String
    let labelFontName: String
    let captionFontName: String

    // MARK: - UI Language

    let libraryTitle: String
    let settingsTitle: String
    let settingsSubtitle: String

    // MARK: - Style

    let buttonRadius: Double
    let cardBorderAccent: Bool
    let isBuiltIn: Bool

    // MARK: - Computed Colors

    var background: Color { Color(hex: backgroundHex) }
    var backgroundElevated: Color { Color(hex: backgroundElevatedHex) }
    var backgroundSheet: Color { Color(hex: backgroundSheetHex) }
    var textPrimary: Color { Color(hex: textPrimaryHex) }
    var textSecondary: Color { Color(hex: textSecondaryHex) }
    var accent: Color { Color(hex: accentHex) }
    var accentMuted: Color { Color(hex: accentMutedHex) }
    var surface: Color { Color(hex: surfaceHex) }
    var surfaceLight: Color { Color(hex: surfaceLightHex) }
    var highlightColor: Color { Color(hex: accentHex).opacity(highlightOpacity) }

    var accentUIColor: UIColor { UIColor(Color(hex: accentHex)) }
    var backgroundUIColor: UIColor { UIColor(Color(hex: backgroundHex)) }

    // Day mode computed colors
    var dayBackground: Color { Color(hex: dayBackgroundHex) }
    var dayTextPrimary: Color { Color(hex: dayTextPrimaryHex) }
    var dayTextSecondary: Color { Color(hex: dayTextSecondaryHex) }
    var dayAccent: Color { Color(hex: dayAccentHex) }
    var dayHighlight: Color { Color(hex: dayHighlightHex) }
    var dayDivider: Color { Color(hex: dayDividerHex) }

    // MARK: - Backward compatibility

    var bgColor: Color { background }
    var textColor: Color { textPrimary }
    var tintColor: Color { accent }
    var bgColorHex: String { backgroundHex }
    var textColorHex: String { textPrimaryHex }
    var tintColorHex: String { accentHex }
    var tintUIColor: UIColor { accentUIColor }

    // MARK: - Font Helpers

    func headlineFont(size: CGFloat) -> Font {
        .custom(headlineFontName, size: size).bold()
    }

    func bodyFont(size: CGFloat) -> Font {
        .custom(bodyFontName, size: size)
    }

    func bodyFontAlt(size: CGFloat) -> Font {
        .custom(bodyFontAltName, size: size)
    }

    func labelFont(size: CGFloat) -> Font {
        .custom(labelFontName, size: size).weight(.medium)
    }

    func captionFont(size: CGFloat) -> Font {
        .custom(captionFontName, size: size)
    }

    func headlineUIFont(size: CGFloat) -> UIFont {
        // Variable fonts: use family name + traits
        if let font = UIFont(name: headlineFontName, size: size) {
            let desc = font.fontDescriptor.withSymbolicTraits(.traitBold)
            return desc.map { UIFont(descriptor: $0, size: size) } ?? font
        }
        return .systemFont(ofSize: size, weight: .bold)
    }

    func bodyUIFont(size: CGFloat) -> UIFont {
        UIFont(name: bodyFontName, size: size) ?? .systemFont(ofSize: size)
    }

    func labelUIFont(size: CGFloat) -> UIFont {
        UIFont(name: labelFontName, size: size) ?? .systemFont(ofSize: size, weight: .medium)
    }

    // MARK: - Built-in Themes

    static let deepForest = Theme(
        id: "deepForest",
        name: "Deep Forest",
        backgroundHex: "#0B120B",
        backgroundElevatedHex: "#141E14",
        backgroundSheetHex: "#111A11",
        textPrimaryHex: "#E8E0D4",
        textSecondaryHex: "#9A938A",
        accentHex: "#CC704B",
        accentMutedHex: "#8B5A3A",
        surfaceHex: "#4D5B4D",
        surfaceLightHex: "#8B9D83",
        highlightOpacity: 0.25,
        dayBackgroundHex: "#F5F0E8",
        dayTextPrimaryHex: "#2C2C2C",
        dayTextSecondaryHex: "#8A8A8A",
        dayAccentHex: "#4D5B4D",
        dayHighlightHex: "#CC704B",
        dayDividerHex: "#D8D0C4",
        dayTitle: "Reading Sanctuary",
        headlineFontName: "Onest",
        bodyFontName: "Noto Serif",
        bodyFontAltName: "Source Serif 4",
        labelFontName: "Onest",
        captionFontName: "Onest",
        libraryTitle: "Private Collection",
        settingsTitle: "Reading Interface",
        settingsSubtitle: "Fine-tune your nocturnal sanctuary for the perfect focus.",
        buttonRadius: 24,
        cardBorderAccent: true,
        isBuiltIn: true
    )

    static let classicMidnight = Theme(
        id: "classicMidnight",
        name: "Classic Midnight",
        backgroundHex: "#121212",
        backgroundElevatedHex: "#1E1E1E",
        backgroundSheetHex: "#181818",
        textPrimaryHex: "#F0E6D2",
        textSecondaryHex: "#8A7E6C",
        accentHex: "#FFBF00",
        accentMutedHex: "#907335",
        surfaceHex: "#2A2520",
        surfaceLightHex: "#00DCFF",
        highlightOpacity: 0.2,
        dayBackgroundHex: "#FAF6EE",
        dayTextPrimaryHex: "#1A1A1A",
        dayTextSecondaryHex: "#7A7A7A",
        dayAccentHex: "#907335",
        dayHighlightHex: "#FFBF00",
        dayDividerHex: "#E0D8C8",
        dayTitle: "The Reading Room",
        headlineFontName: "Noto Serif",
        bodyFontName: "Literata",
        bodyFontAltName: "Noto Serif",
        labelFontName: "Inter",
        captionFontName: "Inter",
        libraryTitle: "The Midnight Library",
        settingsTitle: "Reading Preferences",
        settingsSubtitle: "Curate your midnight reading experience.",
        buttonRadius: 8,
        cardBorderAccent: true,
        isBuiltIn: true
    )

    static let minimalistSlate = Theme(
        id: "minimalistSlate",
        name: "Minimalist Slate",
        backgroundHex: "#1A1C1E",
        backgroundElevatedHex: "#242628",
        backgroundSheetHex: "#1F2123",
        textPrimaryHex: "#E8E4DC",
        textSecondaryHex: "#7A756E",
        accentHex: "#D4AF37",
        accentMutedHex: "#877645",
        surfaceHex: "#2E3034",
        surfaceLightHex: "#97B0FF",
        highlightOpacity: 0.2,
        dayBackgroundHex: "#F2F0ED",
        dayTextPrimaryHex: "#1A1C1E",
        dayTextSecondaryHex: "#8A8580",
        dayAccentHex: "#877645",
        dayHighlightHex: "#D4AF37",
        dayDividerHex: "#DDD8D0",
        dayTitle: "The Quiet Study",
        headlineFontName: "Manrope",
        bodyFontName: "PT Serif",
        bodyFontAltName: "Spectral",
        labelFontName: "Manrope",
        captionFontName: "Manrope",
        libraryTitle: "Your Library",
        settingsTitle: "Reading Preferences",
        settingsSubtitle: "Calibrate the quiet.",
        buttonRadius: 24,
        cardBorderAccent: false,
        isBuiltIn: true
    )

    static let allBuiltIn: [Theme] = [.deepForest, .classicMidnight, .minimalistSlate]

    // MARK: - Custom themes (UserDefaults + кэш)

    private static let customThemesKey = "customThemes"
    private static var _customThemesCache: [Theme]?

    static func loadCustomThemes() -> [Theme] {
        if let cached = _customThemesCache { return cached }
        guard let data = UserDefaults.standard.data(forKey: customThemesKey),
              let themes = try? JSONDecoder().decode([Theme].self, from: data) else { return [] }
        _customThemesCache = themes
        return themes
    }

    static func saveCustomThemes(_ themes: [Theme]) {
        _customThemesCache = themes
        if let data = try? JSONEncoder().encode(themes) {
            UserDefaults.standard.set(data, forKey: customThemesKey)
        }
    }

    static var allThemes: [Theme] {
        allBuiltIn + loadCustomThemes()
    }

    static func find(byId id: String) -> Theme? {
        allThemes.first { $0.id == id }
    }
}

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255
        let b = Double(rgbValue & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
