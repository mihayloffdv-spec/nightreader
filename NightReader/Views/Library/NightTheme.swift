import SwiftUI

/// Color palette derived from the Van Gogh "Starry Night" splash design:
/// deep navy/cobalt backgrounds, golden-amber accents, soft cream text.
enum NightTheme {
    // MARK: - Backgrounds
    /// Near-black navy — main app background
    static let background = Color(hex: "#0B1026")
    /// Slightly lighter — card/cell backgrounds
    static let cardBackground = Color(hex: "#121B38")
    /// Surface for sheets/overlays
    static let surfaceBackground = Color(hex: "#0F1730")

    // MARK: - Text
    /// Warm cream — primary readable text
    static let primaryText = Color(hex: "#E8DFC8")
    /// Muted blue-gray — secondary info
    static let secondaryText = Color(hex: "#7B8DA8")
    /// Dimmed — tertiary/meta
    static let tertiaryText = Color(hex: "#4A5A74")

    // MARK: - Accent (golden tones from the painting)
    /// Golden amber — buttons, highlights, active elements
    static let accent = Color(hex: "#D4A840")
    /// Softer gold — star icons, subtle highlights
    static let accentSoft = Color(hex: "#C49A38")
    /// Cobalt blue — secondary accent from swirls
    static let accentBlue = Color(hex: "#2856A0")

    // MARK: - Progress bar
    static let progressTrack = Color(hex: "#1A2848")
    static let progressFill = Color(hex: "#D4A840")

    // MARK: - UI Colors (for UIKit interop)
    static let backgroundUI = UIColor(red: 0.043, green: 0.063, blue: 0.149, alpha: 1) // #0B1026
}
