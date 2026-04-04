import XCTest
import PDFKit
@testable import NightReader

/// Diagnostic test to trace where text gets corrupted in the extraction pipeline.
final class TextExtractionTraceTests: XCTestCase {

    private func loadRealPDF() -> PDFDocument? {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docsDir.appendingPathComponent("Gipersegmentatsija_Trafika_53843917.pdf")
        if FileManager.default.fileExists(atPath: url.path) {
            return PDFDocument(url: url)
        }
        return nil
    }

    func testTraceExtractionPipeline() {
        guard let doc = loadRealPDF(), let page = doc.page(at: 4) else {
            XCTFail("Real PDF not found")
            return
        }

        // Step 1: Raw page.string
        let pageString = page.string ?? ""
        print("\n=== STEP 1: page.string ===")
        let lines = pageString.components(separatedBy: "\n")
        for (i, line) in lines.prefix(15).enumerated() {
            print("  [\(i)] \"\(line)\"")
        }

        // Check: does page.string have the missing chars?
        let hasOpyta = pageString.contains("Опыта") || pageString.contains("пыта")
        let hasPri = pageString.contains("При этом") || pageString.contains("ри этом")
        print("\n  Contains 'Опыта': \(pageString.contains("Опыта"))")
        print("  Contains 'пыта' (fragment): \(pageString.contains("пыта"))")
        print("  Contains 'При этом': \(pageString.contains("При этом"))")
        print("  Contains 'ри этом' (fragment): \(pageString.contains("ри этом"))")
        print("  Contains 'Кейсы': \(pageString.contains("Кейсы"))")
        print("  Contains 'ейсы' (fragment): \(pageString.contains("ейсы"))")

        // Step 2: After stripLeadingPageNumber
        let stripped = TextExtractor.stripLeadingPageNumber(from: pageString, pageIndex: 4)
        print("\n=== STEP 2: after stripLeadingPageNumber ===")
        print("  Length before: \(pageString.count), after: \(stripped.count)")
        print("  Removed: \(pageString.count - stripped.count) chars")

        // Step 3: After DropCapRecovery
        let pageBounds = page.bounds(for: .mediaBox)
        let textLines = TextExtractor.extractTextLines(from: page, pageBounds: pageBounds)
        let recovered = DropCapRecovery.recoverDropCaps(
            pageString: stripped, textLines: textLines, page: page, pageBounds: pageBounds
        )
        print("\n=== STEP 3: after DropCapRecovery ===")
        print("  Length: \(recovered.count)")
        if recovered != stripped {
            print("  CHANGED! Checking known words:")
            print("  Contains 'Опыта': \(recovered.contains("Опыта"))")
            print("  Contains 'При этом': \(recovered.contains("При этом"))")
            print("  Contains 'Кейсы': \(recovered.contains("Кейсы"))")
        } else {
            print("  NO CHANGE from strip step")
        }

        // Step 4: After splitIntoParagraphs
        let paragraphs = TextExtractor.splitIntoParagraphs(recovered)
        print("\n=== STEP 4: splitIntoParagraphs (\(paragraphs.count) blocks) ===")
        for (i, p) in paragraphs.prefix(10).enumerated() {
            let preview = p.prefix(70).replacingOccurrences(of: "\n", with: "↵")
            let firstChar = p.first(where: { $0.isLetter })
            let flag = (firstChar?.isLowercase == true) ? " ⚠️" : ""
            print("  [\(i)] \"\(preview)\"\(flag)")
        }

        // Step 5: What AttributedTextExtractor gives
        if let attrText = AttributedTextExtractor.extractAttributedText(from: page) {
            let attrStr = attrText.string
            print("\n=== STEP 5: AttributedTextExtractor ===")
            print("  Length: \(attrStr.count)")
            print("  Contains 'Опыта': \(attrStr.contains("Опыта"))")
            print("  Contains 'При этом': \(attrStr.contains("При этом"))")
            print("  Contains 'Кейсы': \(attrStr.contains("Кейсы"))")
            print("  First 200 chars: \(attrStr.prefix(200))")
        }

        // Also check pages 8-9
        for pi in [7, 8] {
            if let p = doc.page(at: pi), let s = p.string {
                let hasPoka = s.contains("Пока")
                let hasPres = s.contains("Пресловутые") || s.contains("ресловутые")
                let hasNeuro = s.contains("Нейросети") || s.contains("ейросети")
                let hasPri = s.contains("При этом") || s.contains("ри этом")
                print("\n=== PAGE \(pi) ===")
                print("  Contains 'Пока': \(hasPoka)")
                print("  Contains 'Пресловутые'/'ресловутые': \(s.contains("Пресловутые"))/\(s.contains("ресловутые"))")
                print("  Contains 'Нейросети'/'ейросети': \(s.contains("Нейросети"))/\(s.contains("ейросети"))")
                print("  Contains 'При этом'/'ри этом': \(s.contains("При этом"))/\(s.contains("ри этом"))")
                print("  First 200 chars: \(s.prefix(200))")
            }
        }

        // KEY ASSERTIONS: Where do the letters go missing?
        // If page.string has them but screen doesn't → bug in our processing
        // If page.string doesn't have them → Apple's PDFKit can't decode them
        XCTAssertTrue(pageString.contains("Опыта") || pageString.contains("пыта"),
                     "page.string should contain either 'Опыта' or 'пыта'")

        // THE CRITICAL QUESTION:
        let hasFullOpyta = pageString.contains("Опыта")
        let hasFullPri = pageString.contains("При этом")
        let hasFullKeysy = pageString.contains("Кейсы")

        if hasFullOpyta {
            // page.string IS correct → problem is in our splitIntoParagraphs/joinLines
            XCTFail("BUG IN OUR CODE: page.string has 'Опыта' but screen shows 'пыта'. Check splitIntoParagraphs/joinLines/display.")
        }
        // else: page.string also missing → Apple PDFKit problem, real drop cap issue

        if !hasFullOpyta && !hasFullPri && !hasFullKeysy {
            // Verify: these ARE real drop cap issues
            let hasFragmentOpyta = pageString.contains("пыта")
            let hasFragmentPri = pageString.contains("ри этом")
            let hasFragmentKeysy = pageString.contains("ейсы")
            XCTAssertTrue(hasFragmentOpyta || hasFragmentPri || hasFragmentKeysy,
                         "Should have at least one known fragment to confirm drop cap issue")
        }
    }

    func testCheckAllPages() {
        guard let doc = loadRealPDF() else { return }

        var realDropCaps: [String] = []
        var ourBugs: [String] = []

        for pi in 0..<min(doc.pageCount, 20) {
            guard pi < doc.pageCount, let page = doc.page(at: pi), let s = page.string else { continue }
            
            // Check specific words
            let checks: [(String, String)] = [
                ("Пока", "ока"), ("Пресловутые", "ресловутые"),
                ("Нейросети", "ейросети"), ("При этом", "ри этом"),
                ("На чисто", "а чисто"), ("Конечно", "онечно")
            ]
            
            for (full, fragment) in checks {
                if s.contains(fragment) {
                    let hasFull = s.contains(full)
                    if hasFull {
                        ourBugs.append("Page \(pi): '\(full)' in page.string → OUR BUG")
                    } else {
                        realDropCaps.append("Page \(pi): '\(fragment)' (should be '\(full)') → REAL DROP CAP")
                    }
                }
            }
        }

        // Report
        if !ourBugs.isEmpty {
            XCTFail("OUR CODE bugs: \(ourBugs.joined(separator: "; "))")
        }
        if !realDropCaps.isEmpty {
            XCTFail("REAL drop caps found (page.string missing chars): \(realDropCaps.joined(separator: "; "))")
        }
        // If both empty → no problems found in first 20 pages (or words not present)
    }

    /// Search ALL pages for lowercase-start sentences after periods
    /// This catches "предложения. а него" type issues
    func testFindMidSentenceMissingChars() {
        guard let doc = loadRealPDF() else { return }

        var issues: [String] = []

        for pi in 0..<min(doc.pageCount, 30) {
            guard let page = doc.page(at: pi), let s = page.string else { continue }

            // Find patterns: ". lowercase" where lowercase is NOT a common word
            let commonLower: Set<String> = ["и","а","в","с","к","о","у","на","не","но","по","из","за","до","от","же","ни","то","что","как","так","это","все","для","при","без","или","где","чем","вы","мы","он","она","они","да","нет","уже","ведь","тут","там"]

            // Regex: period + space(s) + lowercase letter
            if let regex = try? NSRegularExpression(pattern: "\\.\\s+([а-я]\\S{0,15})") {
                let ns = s as NSString
                for match in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                    let word = ns.substring(with: match.range(at: 1))
                    let firstWord = word.components(separatedBy: " ").first ?? word
                    if !commonLower.contains(firstWord.lowercased()) && firstWord.count >= 2 {
                        // This is suspicious — sentence after period starting lowercase
                        // Check if it's a fragment (missing first char)
                        if TextExtractor.isFragment(firstWord) {
                            issues.append("Page \(pi): '\(word)' after period — likely missing first char(s)")
                        }
                    }
                }
            }
        }

        if !issues.isEmpty {
            // Don't fail — just report
            print("\n=== MID-SENTENCE MISSING CHARS ===")
            for issue in issues.prefix(20) {
                print("  \(issue)")
            }
            print("Total: \(issues.count) suspicious patterns")
            // These are REAL drop cap issues in page.string — not our processing bug
        }
    }
}
