import XCTest
import SwiftUI
@testable import NightReader

// MARK: - Тесты для Theme

/// Helper to create a test theme with all required fields
private func makeTestTheme(id: String, name: String, bg: String = "#112233", text: String = "#AABBCC", accent: String = "#DDEEFF") -> Theme {
    Theme(
        id: id, name: name,
        backgroundHex: bg, backgroundElevatedHex: bg, backgroundSheetHex: bg,
        textPrimaryHex: text, textSecondaryHex: text,
        accentHex: accent, accentMutedHex: accent,
        surfaceHex: text, surfaceLightHex: text,
        highlightOpacity: 0.25,
        dayBackgroundHex: "#F5F0E8", dayTextPrimaryHex: "#2C2C2C",
        dayTextSecondaryHex: "#8A8A8A", dayAccentHex: "#4D5B4D",
        dayHighlightHex: accent, dayDividerHex: "#D8D0C4", dayTitle: "Test",
        headlineFontName: "Onest", bodyFontName: "Noto Serif",
        bodyFontAltName: "Noto Serif", labelFontName: "Onest", captionFontName: "Onest",
        libraryTitle: "Test", settingsTitle: "Test", settingsSubtitle: "",
        buttonRadius: 24, cardBorderAccent: true, isBuiltIn: false
    )
}

final class ThemeTests: XCTestCase {

    // MARK: - Встроенные темы

    /// В приложении 3 встроенные темы
    func testAllBuiltIn_hasThreeThemes() {
        XCTAssertEqual(Theme.allBuiltIn.count, 3)
    }

    /// Поиск темы по ID — находит "deepForest"
    func testFindById_deepForest() {
        let theme = Theme.find(byId: "deepForest")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme?.name, "Deep Forest")
    }

    /// Поиск несуществующей темы — возвращает nil
    func testFindById_nonexistent() {
        XCTAssertNil(Theme.find(byId: "nonexistent"))
    }

    /// Старые темы не находятся
    func testFindById_oldThemesGone() {
        XCTAssertNil(Theme.find(byId: "midnight"))
        XCTAssertNil(Theme.find(byId: "sepia"))
    }

    // MARK: - Color hex init

    func testColorHexInit_red() {
        let color = Color(hex: "#FF0000")
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    func testColorHexInit_black() {
        let color = Color(hex: "#000000")
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0.0, accuracy: 0.01)
    }

    func testColorToHex_roundtrip() {
        let originalHex = "#FF8040"
        let color = Color(hex: originalHex)
        let resultHex = color.toHex()
        XCTAssertEqual(resultHex, originalHex)
    }

    // MARK: - Пользовательские темы

    private let customThemesKey = "customThemes"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: customThemesKey)
        super.tearDown()
    }

    func testCustomThemes_saveAndLoadCycle() {
        UserDefaults.standard.removeObject(forKey: customThemesKey)

        let theme1 = makeTestTheme(id: "test1", name: "Тестовая 1", bg: "#112233")
        let theme2 = makeTestTheme(id: "test2", name: "Тестовая 2", bg: "#334455")

        Theme.saveCustomThemes([theme1, theme2])

        let loaded = Theme.loadCustomThemes()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "Тестовая 1")
        XCTAssertEqual(loaded[1].name, "Тестовая 2")
    }
}
