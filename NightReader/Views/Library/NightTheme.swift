import SwiftUI

/// Color palette inspired by the "Elegant NightReader" Canva design:
/// deep dark navy background, muted gray icons/text, minimal whitespace.
enum NightTheme {
    // MARK: - Backgrounds
    static let background = Color(hex: "#1C2836")
    static let cardBackground = Color(hex: "#243040")
    static let surfaceBackground = Color(hex: "#212D3B")

    // MARK: - Text
    static let primaryText = Color(hex: "#C8CCD0")
    static let secondaryText = Color(hex: "#7A8494")
    static let tertiaryText = Color(hex: "#505C6C")

    // MARK: - Accent
    static let accent = Color(hex: "#8A9AAC")
    static let moonGray = Color(hex: "#9AA4B0")
    static let starColor = Color(hex: "#B0BAC6")

    // MARK: - Progress bar
    static let progressTrack = Color(hex: "#2A3848")
    static let progressFill = Color(hex: "#6A7A8C")

    // MARK: - UI Colors (for UIKit interop)
    static let backgroundUI = UIColor(red: 0.11, green: 0.157, blue: 0.212, alpha: 1)
}
