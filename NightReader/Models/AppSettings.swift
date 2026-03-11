import Foundation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var defaultThemeId: String {
        get { UserDefaults.standard.string(forKey: "defaultThemeId") ?? Theme.midnight.id }
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
        Theme.allBuiltIn.first { $0.id == defaultThemeId } ?? .midnight
    }

    var readerFontSize: Double {
        get {
            let val = UserDefaults.standard.double(forKey: "readerFontSize")
            return val > 0 ? val : 18
        }
        set { UserDefaults.standard.set(newValue, forKey: "readerFontSize") }
    }

    var currentRenderingMode: RenderingMode {
        RenderingMode(rawValue: defaultRenderingMode) ?? .simple
    }
}
