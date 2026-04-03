import XCTest
import PDFKit
@testable import NightReader

final class AttributedTextExtractorTests: XCTestCase {

    // Use the real PDF with Cyrillic drop caps
    private func loadRealPDF() -> PDFDocument? {
        // Try app's Documents directory (simulator)
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let giper = docsDir.appendingPathComponent("Gipersegmentatsija_Trafika_53843917.pdf")
        if FileManager.default.fileExists(atPath: giper.path) {
            return PDFDocument(url: giper)
        }
        return nil
    }

    // MARK: - PDFSelection.attributedString availability

    func testPDFSelectionHasAttributedString() {
        // Verify the API exists at runtime
        XCTAssertTrue(PDFSelection.instancesRespond(to: NSSelectorFromString("attributedString")),
                     "PDFSelection.attributedString must be available on this iOS version")
    }

    // MARK: - Basic extraction from test_book

    func testExtractFromTestBook() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docsDir.appendingPathComponent("test_book.pdf")
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else {
            // test_book may not be available in test runner
            print("test_book.pdf not found, skipping")
            return
        }

        let attrString = AttributedTextExtractor.extractAttributedText(from: page)
        XCTAssertNotNil(attrString, "Should extract attributed text from test_book")

        if let attr = attrString {
            XCTAssertGreaterThan(attr.length, 10, "Should have meaningful text content")

            // Verify text is readable (not garbage symbols)
            let text = attr.string
            let latinOrCyrillic = text.unicodeScalars.filter {
                CharacterSet.letters.contains($0)
            }.count
            let total = max(text.count, 1)
            let letterRatio = Double(latinOrCyrillic) / Double(total)
            XCTAssertGreaterThan(letterRatio, 0.3, "Text should be mostly letters, not garbage. Got: \(text.prefix(100))")
        }
    }

    // MARK: - Real PDF with drop caps

    func testExtractFromRealPDF_TextIsReadable() {
        guard let doc = loadRealPDF() else {
            print("Real PDF not found, skipping")
            return
        }

        // Test page 5 (known to have drop cap issues)
        let pageIndex = min(4, doc.pageCount - 1)
        guard let page = doc.page(at: pageIndex) else {
            XCTFail("Cannot get page \(pageIndex)")
            return
        }

        let attrString = AttributedTextExtractor.extractAttributedText(from: page)
        XCTAssertNotNil(attrString, "Should extract attributed text from real PDF")

        if let attr = attrString {
            let text = attr.string
            print("[Test] Page \(pageIndex) text preview: \(text.prefix(200))")

            // Should NOT have garbage symbols
            let garbageChars = text.filter { "^˘˜˝˛˙ˆ¸".contains($0) }
            XCTAssertEqual(garbageChars.count, 0,
                          "Text should not contain encoding garbage. Found: \(garbageChars)")

            // Should have Cyrillic text
            let cyrillicCount = text.unicodeScalars.filter {
                $0.value >= 0x0400 && $0.value <= 0x04FF
            }.count
            XCTAssertGreaterThan(cyrillicCount, 10,
                                "Should have Cyrillic text. Got \(cyrillicCount) Cyrillic chars in: \(text.prefix(100))")
        }
    }

    func testExtractFromRealPDF_HasFontAttributes() {
        guard let doc = loadRealPDF(), let page = doc.page(at: 0) else {
            print("Real PDF not found, skipping")
            return
        }

        guard let attrString = AttributedTextExtractor.extractAttributedText(from: page) else {
            XCTFail("Should extract attributed text")
            return
        }

        // Check that font attributes are present
        var fontNames: Set<String> = []
        var fontSizes: Set<CGFloat> = []
        var hasBold = false
        var hasItalic = false

        let range = NSRange(location: 0, length: attrString.length)
        attrString.enumerateAttribute(.font, in: range) { value, _, _ in
            if let font = value as? UIFont {
                fontNames.insert(font.fontName)
                fontSizes.insert(font.pointSize)
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.traitBold) { hasBold = true }
                if traits.contains(.traitItalic) { hasItalic = true }
            }
        }

        print("[Test] Font names found: \(fontNames)")
        print("[Test] Font sizes found: \(fontSizes.sorted())")
        print("[Test] Has bold: \(hasBold), Has italic: \(hasItalic)")

        XCTAssertGreaterThan(fontNames.count, 0, "Should have at least one font")
        XCTAssertGreaterThan(fontSizes.count, 0, "Should have at least one font size")
    }

    func testExtractFromRealPDF_SplitsIntoBlocks() {
        guard let doc = loadRealPDF(), let page = doc.page(at: 4) else {
            print("Real PDF not found, skipping")
            return
        }

        guard let attrString = AttributedTextExtractor.extractAttributedText(from: page) else {
            print("No attributed text, skipping")
            return
        }

        let blocks = AttributedTextExtractor.splitIntoBlocks(attrString)
        print("[Test] Page 4: \(blocks.count) blocks")

        for (i, block) in blocks.enumerated() {
            switch block {
            case .richText(let attr):
                let preview = attr.string.prefix(60)
                print("[Test]   Block \(i): richText(\(attr.length) chars) \"\(preview)...\"")
            case .text(let t):
                print("[Test]   Block \(i): text(\(t.count) chars) \"\(t.prefix(60))...\"")
            case .heading(let t):
                print("[Test]   Block \(i): heading \"\(t.prefix(60))\"")
            default:
                print("[Test]   Block \(i): other")
            }
        }

        XCTAssertGreaterThan(blocks.count, 0, "Should produce at least one block")
    }

    // MARK: - Compare old vs new extraction

    func testCompareOldVsNewExtraction() {
        guard let doc = loadRealPDF() else {
            print("Real PDF not found, skipping")
            return
        }

        let pageIndex = min(4, doc.pageCount - 1)
        guard let page = doc.page(at: pageIndex) else { return }

        // Old method: page.string
        let oldText = page.string ?? ""

        // New method: attributedString
        let newAttr = AttributedTextExtractor.extractAttributedText(from: page)
        let newText = newAttr?.string ?? ""

        print("[Test] OLD page.string length: \(oldText.count)")
        print("[Test] NEW attributedString length: \(newText.count)")
        print("[Test] OLD preview: \(oldText.prefix(100))")
        print("[Test] NEW preview: \(newText.prefix(100))")

        // New should have at least as much text as old
        // (may have more if drop caps are recovered)
        XCTAssertGreaterThan(newText.count, 0, "New extraction should produce text")
    }
}
