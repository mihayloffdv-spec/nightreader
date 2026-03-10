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

    static let midnight = Theme(
        id: "midnight", name: "Midnight",
        bgColorHex: "#0D0D0D", textColorHex: "#D4D4C8", tintColorHex: "#D4D4C8",
        isBuiltIn: true
    )

    static let allBuiltIn: [Theme] = [.midnight]
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
}
