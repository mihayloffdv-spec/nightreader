import SwiftUI

struct Theme: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let bgColorHex: String
    let textColorHex: String
    let tintColorHex: String
    let isBuiltIn: Bool

    var bgColor: Color { Color(hex: bgColorHex) }
    var textColor: Color { Color(hex: textColorHex) }
    var tintColor: Color { Color(hex: tintColorHex) }

    var tintUIColor: UIColor {
        UIColor(Color(hex: tintColorHex))
    }

    // MARK: - Built-in themes

    static let midnight = Theme(
        id: "midnight", name: "Midnight",
        bgColorHex: "#0D0D0D", textColorHex: "#D4D4C8", tintColorHex: "#FFF0D4",
        isBuiltIn: true
    )

    static let sepia = Theme(
        id: "sepia", name: "Sepia",
        bgColorHex: "#1A1408", textColorHex: "#D4C4A0", tintColorHex: "#F5E6C8",
        isBuiltIn: true
    )

    static let forest = Theme(
        id: "forest", name: "Forest",
        bgColorHex: "#0A1A0A", textColorHex: "#A8D4A8", tintColorHex: "#C8F0C8",
        isBuiltIn: true
    )

    static let ocean = Theme(
        id: "ocean", name: "Ocean",
        bgColorHex: "#0A0F1A", textColorHex: "#A8C4D4", tintColorHex: "#C8DCF0",
        isBuiltIn: true
    )

    static let sunset = Theme(
        id: "sunset", name: "Sunset",
        bgColorHex: "#1A0F0A", textColorHex: "#D4B4A0", tintColorHex: "#F0D4C0",
        isBuiltIn: true
    )

    static let paper = Theme(
        id: "paper", name: "Paper",
        bgColorHex: "#1A1A14", textColorHex: "#E0E0D0", tintColorHex: "#FFFFF0",
        isBuiltIn: true
    )

    static let allBuiltIn: [Theme] = [.midnight, .sepia, .forest, .ocean, .sunset, .paper]

    // MARK: - Custom themes (UserDefaults)

    private static let customThemesKey = "customThemes"

    static func loadCustomThemes() -> [Theme] {
        guard let data = UserDefaults.standard.data(forKey: customThemesKey),
              let themes = try? JSONDecoder().decode([Theme].self, from: data) else { return [] }
        return themes
    }

    static func saveCustomThemes(_ themes: [Theme]) {
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
