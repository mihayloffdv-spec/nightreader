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

    var currentTheme: Theme {
        Theme.allBuiltIn.first { $0.id == defaultThemeId } ?? .midnight
    }
}
