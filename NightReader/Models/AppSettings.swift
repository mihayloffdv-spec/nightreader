import Foundation

/// Режим автоматического переключения темы.
enum AutoSwitchMode: String {
    case manual
    case schedule
    case device
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var defaultThemeId: String {
        get { UserDefaults.standard.string(forKey: "defaultThemeId") ?? Theme.deepForest.id }
        set { UserDefaults.standard.set(newValue, forKey: "defaultThemeId") }
    }

    var defaultDimmerOpacity: Double {
        get { UserDefaults.standard.double(forKey: "defaultDimmerOpacity") }
        set { UserDefaults.standard.set(newValue, forKey: "defaultDimmerOpacity") }
    }

    var defaultRenderingMode: String {
        get { UserDefaults.standard.string(forKey: "defaultRenderingMode") ?? RenderingMode.simple.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: "defaultRenderingMode") }
    }

    var currentTheme: Theme {
        if let t = Theme.find(byId: defaultThemeId) { return t }
        // Clear stale ID from old app version (midnight, sepia, etc.)
        defaultThemeId = Theme.deepForest.id
        return .deepForest
    }

    var readerFontSize: Double {
        get {
            let val = UserDefaults.standard.double(forKey: "readerFontSize")
            return val > 0 ? val : 18
        }
        set { UserDefaults.standard.set(newValue, forKey: "readerFontSize") }
    }

    var readerFontFamily: String {
        get { UserDefaults.standard.string(forKey: "readerFontFamily") ?? ReaderFont.serif.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: "readerFontFamily") }
    }

    var currentReaderFont: ReaderFont {
        ReaderFont(rawValue: readerFontFamily) ?? .serif
    }

    var currentRenderingMode: RenderingMode {
        RenderingMode(rawValue: defaultRenderingMode) ?? .simple
    }

    // MARK: - Auto Theme Switching

    var autoSwitchMode: AutoSwitchMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "autoSwitchMode") ?? "manual"
            return AutoSwitchMode(rawValue: raw) ?? .manual
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "autoSwitchMode") }
    }

    var darkStartHour: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: "darkStartHour")
            return val == 0 && !UserDefaults.standard.bool(forKey: "darkStartHourSet") ? 22 : val
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "darkStartHour")
            UserDefaults.standard.set(true, forKey: "darkStartHourSet")
        }
    }

    var darkEndHour: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: "darkEndHour")
            return val == 0 && !UserDefaults.standard.bool(forKey: "darkEndHourSet") ? 7 : val
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "darkEndHour")
            UserDefaults.standard.set(true, forKey: "darkEndHourSet")
        }
    }

    /// ID of the preferred dark theme for auto-switch.
    var darkThemeId: String {
        get { UserDefaults.standard.string(forKey: "darkThemeId") ?? Theme.deepForest.id }
        set { UserDefaults.standard.set(newValue, forKey: "darkThemeId") }
    }

    /// ID of the preferred light/day theme for auto-switch.
    var lightThemeId: String {
        get { UserDefaults.standard.string(forKey: "lightThemeId") ?? Theme.minimalistSlate.id }
        set { UserDefaults.standard.set(newValue, forKey: "lightThemeId") }
    }

    /// Returns the appropriate theme based on auto-switch mode.
    func resolvedTheme(isDarkAppearance: Bool) -> Theme {
        switch autoSwitchMode {
        case .schedule:
            let hour = Calendar.current.component(.hour, from: Date())
            let isDarkTime: Bool
            if darkStartHour > darkEndHour {
                isDarkTime = hour >= darkStartHour || hour < darkEndHour
            } else {
                isDarkTime = hour >= darkStartHour && hour < darkEndHour
            }
            let themeId = isDarkTime ? darkThemeId : lightThemeId
            return Theme.find(byId: themeId) ?? .deepForest
        case .device:
            let themeId = isDarkAppearance ? darkThemeId : lightThemeId
            return Theme.find(byId: themeId) ?? .deepForest
        case .manual:
            return currentTheme
        }
    }
}
