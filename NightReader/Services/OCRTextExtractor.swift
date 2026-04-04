import PDFKit
import UIKit
import Vision

// MARK: - OCR Text Extractor
//
// Systemtic fix for missing characters in PDF text extraction.
// Apple can RENDER all characters correctly but can't DECODE some fonts.
// Solution: render page as image → OCR with Vision → get complete text.
//
// ┌─────────────────────────────────────────────────────────┐
// │              OCRTextExtractor                            │
// │                                                         │
// │  extractText(page) → String                             │
// │    1. Render page to UIImage (Apple draws all chars)     │
// │    2. VNRecognizeTextRequest (Russian + English)         │
// │    3. Return OCR text sorted by position                 │
// │                                                         │
// │  mergeWithPageString(ocrText, pageString) → String       │
// │    Compare OCR vs page.string, fill in missing chars     │
// └─────────────────────────────────────────────────────────┘

enum OCRTextExtractor {

    // MARK: - Full page OCR

    /// Render a PDF page and OCR it to get complete text.
    /// This catches characters that page.string misses due to font encoding issues.
    static func extractText(from page: PDFPage) -> String? {
        guard let image = renderPage(page) else { return nil }
        guard let cgImage = image.cgImage else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ru", "en"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            print("[OCR] Failed: \(error)")
            #endif
            return nil
        }

        guard let results = request.results else { return nil }

        // Sort by Y position (top to bottom), then X (left to right)
        let sorted = results.sorted { a, b in
            let aY = 1 - a.boundingBox.midY // invert Y (Vision uses bottom-left origin)
            let bY = 1 - b.boundingBox.midY
            if abs(aY - bY) > 0.01 { return aY < bY }
            return a.boundingBox.midX < b.boundingBox.midX
        }

        let text = sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    // MARK: - Merge OCR with page.string

    /// Use page.string as base (it has better paragraph structure) and fill in
    /// missing characters from OCR text.
    ///
    /// Strategy: find lines in page.string that start with lowercase (suspicious),
    /// look for the same fragment in OCR text, and prepend the missing chars.
    static func mergeWithPageString(ocrText: String, pageString: String) -> String {
        let ocrLines = ocrText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var result = pageString

        // Build OCR lookup: lowercase-trimmed fragments → full OCR line
        // This lets us find "ебрант" in OCR and recover "Себрант"
        var ocrLookup: [String: String] = [:]
        for ocrLine in ocrLines {
            // Index by substrings of 5-15 chars for fuzzy matching
            let words = ocrLine.components(separatedBy: " ")
            for word in words where word.count >= 3 {
                ocrLookup[word.lowercased()] = ocrLine
            }
        }

        // Find suspicious fragments in page.string and fix them
        let pageLines = result.components(separatedBy: "\n")
        var fixedLines: [String] = []
        var fixes = 0

        for pageLine in pageLines {
            let trimmed = pageLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { fixedLines.append(pageLine); continue }

            // Find words that start with lowercase after sentence boundary
            var fixedLine = pageLine
            let words = trimmed.components(separatedBy: " ")

            for (wi, word) in words.enumerated() {
                guard word.count >= 2 else { continue }
                guard let first = word.first, first.isLowercase else { continue }

                // Is this word at the start of a sentence? (after period, or start of line)
                let isAfterPeriod = wi > 0 && words[wi-1].hasSuffix(".")
                let isLineStart = wi == 0

                guard isAfterPeriod || isLineStart else { continue }

                // Look for this fragment in OCR text
                let fragment = word.lowercased()
                for (ocrKey, ocrLine) in ocrLookup {
                    if ocrKey.contains(fragment) || fragment.contains(ocrKey) {
                        // Found in OCR. Find the full word in OCR line
                        let ocrWords = ocrLine.components(separatedBy: " ")
                        for ocrWord in ocrWords {
                            let ocrLower = ocrWord.lowercased()
                            if ocrLower.hasSuffix(fragment) && ocrLower.count > fragment.count {
                                // OCR has more chars at the beginning!
                                let missingCount = ocrLower.count - fragment.count
                                let missingChars = String(ocrWord.prefix(missingCount))

                                // Verify: the missing chars + fragment = the OCR word
                                if (missingChars + word).lowercased() == ocrLower {
                                    fixedLine = fixedLine.replacingOccurrences(
                                        of: word,
                                        with: missingChars + word,
                                        options: [],
                                        range: fixedLine.range(of: word)
                                    )
                                    fixes += 1
                                    #if DEBUG
                                    let pageIndex = "?"
                                    print("[OCR] Fixed: '\(word)' → '\(missingChars + word)'")
                                    #endif
                                }
                                break
                            }
                        }
                        break
                    }
                }
            }

            fixedLines.append(fixedLine)
        }

        #if DEBUG
        if fixes > 0 {
            print("[OCR] Applied \(fixes) fixes from OCR")
        }
        #endif

        return fixedLines.joined(separator: "\n")
    }

    // MARK: - Page rendering

    /// Render a PDF page to a high-resolution UIImage.
    /// Uses getDrawingTransform for correct coordinate handling.
    private static func renderPage(_ page: PDFPage, scale: CGFloat = 2.0) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = bounds.width * scale
        let height = bounds.height * scale

        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), true, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }

        // White background
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Scale and draw
        context.scaleBy(x: scale, y: scale)

        // Use getDrawingTransform for correct coordinate handling
        let transform = page.transform(for: .mediaBox)
        context.concatenate(transform)

        // Draw the page
        if let cgPage = page.pageRef {
            context.drawPDFPage(cgPage)
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}
