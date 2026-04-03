import XCTest
import SwiftUI
@testable import NightReader

// MARK: - Тесты для Theme

final class ThemeTests: XCTestCase {

    // MARK: - Встроенные темы

    /// В приложении 6 встроенных тем
    func testAllBuiltIn_hasSixThemes() {
        XCTAssertEqual(Theme.allBuiltIn.count, 6)
    }

    /// Поиск темы по ID — находит "midnight"
    func testFindById_midnight() {
        let theme = Theme.find(byId: "midnight")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme?.name, "Midnight")
        XCTAssertEqual(theme?.id, "midnight")
    }

    /// Поиск несуществующей темы — возвращает nil
    func testFindById_nonexistent() {
        let theme = Theme.find(byId: "nonexistent")
        XCTAssertNil(theme)
    }

    // MARK: - Color hex init

    /// "#FF0000" — красный цвет (R=1, G=0, B=0)
    func testColorHexInit_red() {
        let color = Color(hex: "#FF0000")
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    /// "#000000" — чёрный цвет (R=0, G=0, B=0)
    func testColorHexInit_black() {
        let color = Color(hex: "#000000")
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    // MARK: - Color toHex roundtrip

    /// Конвертация Color → hex → Color должна сохранять значения
    func testColorToHex_roundtrip() {
        let originalHex = "#FF8040"
        let color = Color(hex: originalHex)
        let resultHex = color.toHex()
        XCTAssertEqual(resultHex, originalHex)
    }

    // MARK: - Пользовательские темы (UserDefaults)

    /// Ключ для очистки после теста
    private let customThemesKey = "customThemes"

    override func tearDown() {
        // Очищаем UserDefaults после каждого теста
        UserDefaults.standard.removeObject(forKey: customThemesKey)
        super.tearDown()
    }

    /// Сохранение и загрузка пользовательских тем
    func testCustomThemes_saveAndLoadCycle() {
        // Очищаем кэш и UserDefaults перед тестом
        UserDefaults.standard.removeObject(forKey: customThemesKey)

        let theme1 = Theme(
            id: "test_theme_1",
            name: "Тестовая 1",
            bgColorHex: "#112233",
            textColorHex: "#AABBCC",
            tintColorHex: "#DDEEFF",
            isBuiltIn: false
        )
        let theme2 = Theme(
            id: "test_theme_2",
            name: "Тестовая 2",
            bgColorHex: "#334455",
            textColorHex: "#667788",
            tintColorHex: "#99AABB",
            isBuiltIn: false
        )

        // Сохраняем темы
        Theme.saveCustomThemes([theme1, theme2])

        // Загружаем и проверяем
        let loaded = Theme.loadCustomThemes()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "Тестовая 1")
        XCTAssertEqual(loaded[1].name, "Тестовая 2")
        XCTAssertEqual(loaded[0].id, "test_theme_1")
        XCTAssertEqual(loaded[1].bgColorHex, "#334455")
    }
}
