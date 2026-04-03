import XCTest
@testable import NightReader

final class ThemeSystemTests: XCTestCase {

    // MARK: - Theme definitions

    func testThreeBuiltInThemes() {
        XCTAssertEqual(Theme.allBuiltIn.count, 3)
        XCTAssertEqual(Theme.allBuiltIn[0].id, "deepForest")
        XCTAssertEqual(Theme.allBuiltIn[1].id, "classicMidnight")
        XCTAssertEqual(Theme.allBuiltIn[2].id, "minimalistSlate")
    }

    func testThemesHaveDifferentColors() {
        let df = Theme.deepForest
        let cm = Theme.classicMidnight
        let ms = Theme.minimalistSlate

        // Backgrounds must differ
        XCTAssertNotEqual(df.backgroundHex, cm.backgroundHex)
        XCTAssertNotEqual(cm.backgroundHex, ms.backgroundHex)
        XCTAssertNotEqual(df.backgroundHex, ms.backgroundHex)

        // Accents must differ
        XCTAssertNotEqual(df.accentHex, cm.accentHex)
        XCTAssertNotEqual(cm.accentHex, ms.accentHex)
    }

    func testThemesHaveDifferentFonts() {
        let df = Theme.deepForest
        let cm = Theme.classicMidnight
        let ms = Theme.minimalistSlate

        // Headline fonts must differ
        XCTAssertNotEqual(df.headlineFontName, cm.headlineFontName)
        XCTAssertNotEqual(cm.headlineFontName, ms.headlineFontName)

        // Body fonts must differ
        XCTAssertNotEqual(df.bodyFontName, cm.bodyFontName)
        XCTAssertNotEqual(cm.bodyFontName, ms.bodyFontName)
    }

    func testThemesHaveDifferentUILanguage() {
        let df = Theme.deepForest
        let cm = Theme.classicMidnight

        XCTAssertNotEqual(df.libraryTitle, cm.libraryTitle)
        XCTAssertEqual(df.libraryTitle, "Private Collection")
        XCTAssertEqual(cm.libraryTitle, "The Midnight Library")
    }

    // MARK: - Font loading

    func testOnestFontLoads() {
        let font = UIFont(name: "Onest", size: 17)
        XCTAssertNotNil(font, "Onest font should load. Check Info.plist UIAppFonts and font file in bundle.")
        if let font {
            XCTAssertTrue(font.familyName.contains("Onest") || font.fontName.contains("Onest"),
                         "Loaded font should be Onest, got: \(font.fontName) / \(font.familyName)")
        }
    }

    func testNotoSerifFontLoads() {
        let font = UIFont(name: "Noto Serif", size: 17)
        XCTAssertNotNil(font, "Noto Serif font should load")
    }

    func testLiterataFontLoads() {
        let font = UIFont(name: "Literata", size: 17)
        XCTAssertNotNil(font, "Literata font should load")
    }

    func testManropeFontLoads() {
        let font = UIFont(name: "Manrope", size: 17)
        XCTAssertNotNil(font, "Manrope font should load")
    }

    func testPTSerifFontLoads() {
        let font = UIFont(name: "PT Serif", size: 17)
        // PT Serif is static (not variable), try PostScript name too
        let fontPS = UIFont(name: "PTSerif-Regular", size: 17)
        XCTAssertTrue(font != nil || fontPS != nil,
                     "PT Serif should load by family or PostScript name")
    }

    func testInterFontLoads() {
        let font = UIFont(name: "Inter", size: 17)
        XCTAssertNotNil(font, "Inter font should load")
    }

    func testSourceSerif4FontLoads() {
        let font = UIFont(name: "Source Serif 4", size: 17)
        XCTAssertNotNil(font, "Source Serif 4 font should load")
    }

    func testSpectralFontLoads() {
        // Spectral is static, use PostScript name
        let font = UIFont(name: "Spectral", size: 17)
        let fontPS = UIFont(name: "Spectral-Regular", size: 17)
        XCTAssertTrue(font != nil || fontPS != nil,
                     "Spectral should load by family or PostScript name")
    }

    func testEBGaramondFontLoads() {
        let font = UIFont(name: "EB Garamond", size: 17)
        XCTAssertNotNil(font, "EB Garamond font should load")
    }

    // MARK: - Theme font helpers

    func testDeepForestHeadlineFontReturnsCustomFont() {
        let theme = Theme.deepForest
        let uiFont = theme.headlineUIFont(size: 34)
        // Should NOT be system font
        XCTAssertFalse(uiFont.fontName.contains(".SFUI"),
                      "Headline font should not be system font, got: \(uiFont.fontName)")
    }

    func testClassicMidnightBodyFontReturnsCustomFont() {
        let theme = Theme.classicMidnight
        let uiFont = theme.bodyUIFont(size: 17)
        XCTAssertFalse(uiFont.fontName.contains(".SFUI"),
                      "Body font should not be system font, got: \(uiFont.fontName)")
    }

    // MARK: - Backward compatibility

    func testBackwardCompatProperties() {
        let theme = Theme.deepForest
        XCTAssertEqual(theme.bgColorHex, theme.backgroundHex)
        XCTAssertEqual(theme.textColorHex, theme.textPrimaryHex)
        XCTAssertEqual(theme.tintColorHex, theme.accentHex)
    }

    // MARK: - Theme lookup

    func testFindByIdWorks() {
        let found = Theme.find(byId: "deepForest")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Deep Forest")
    }

    func testFindByIdReturnsNilForOldThemes() {
        XCTAssertNil(Theme.find(byId: "midnight"))
        XCTAssertNil(Theme.find(byId: "sepia"))
        XCTAssertNil(Theme.find(byId: "forest"))
    }

    // MARK: - Color hex

    func testColorHexRoundTrip() {
        let theme = Theme.deepForest
        XCTAssertEqual(theme.backgroundHex, "#0B120B")
        XCTAssertEqual(theme.accentHex, "#CC704B")
    }

    // MARK: - Print available fonts (diagnostic)

    func testPrintAvailableFonts() {
        let families = ["Onest", "Noto Serif", "Literata", "Manrope", "PT Serif", "Inter",
                        "Source Serif 4", "Spectral", "EB Garamond"]
        for family in families {
            let names = UIFont.fontNames(forFamilyName: family)
            print("Family '\(family)': \(names)")
        }
    }
}
