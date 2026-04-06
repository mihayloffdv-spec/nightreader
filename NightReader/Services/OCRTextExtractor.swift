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

    /// Use page.string as base and fill in missing characters from OCR.
    ///
    /// ONLY fixes words that are at TRUE sentence starts (after . ! ? or start of text).
    /// Does NOT modify lowercase words after commas, colons, etc.
    static func mergeWithPageString(ocrText: String, pageString: String) -> String {
        let ocrLines = ocrText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Collect all OCR words for lookup
        var ocrWords: [String] = []
        for line in ocrLines {
            ocrWords.append(contentsOf: line.components(separatedBy: " ").filter { $0.count >= 3 })
        }

        // Work on the full pageString to check true sentence boundaries
        let sentenceEnders: Set<Character> = [".", "!", "?", "…"]
        var result = pageString
        var fixes = 0

        // Find lowercase words at true sentence starts
        // Pattern: (sentence-ending punctuation + whitespace) then lowercase word
        // Also: very start of the text
        if let regex = try? NSRegularExpression(pattern: "(?:^|[.!?…]\\s+)([а-яa-z]\\S{1,20})", options: []) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))

            // Process in reverse order so replacements don't shift ranges
            for match in matches.reversed() {
                let fragmentRange = match.range(at: 1)
                let fragment = ns.substring(with: fragmentRange)

                guard fragment.count >= 2 else { continue }
                guard let firstChar = fragment.first, firstChar.isLowercase else { continue }

                let fragmentLower = fragment.lowercased()

                // Look for an OCR word that starts with uppercase and ends with this fragment
                for ocrWord in ocrWords {
                    guard let ocrFirst = ocrWord.first, ocrFirst.isUppercase else { continue }
                    let ocrLower = ocrWord.lowercased()

                    guard ocrLower.hasSuffix(fragmentLower) else { continue }
                    guard ocrLower.count > fragmentLower.count else { continue }
                    guard ocrLower.count <= fragmentLower.count + 3 else { continue } // max 3 chars missing

                    // Verify exact match
                    let missingCount = ocrWord.count - fragment.count
                    let missingChars = String(ocrWord.prefix(missingCount))

                    if (missingChars.lowercased() + fragmentLower) == ocrLower {
                        let replacement = missingChars + fragment
                        result = (result as NSString).replacingCharacters(in: fragmentRange, with: replacement)
                        fixes += 1
                        #if DEBUG
                        print("[OCR] Fixed: '\(fragment)' → '\(replacement)'")
                        #endif
                        break
                    }
                }
            }
        }

        #if DEBUG
        if fixes > 0 {
            print("[OCR] Applied \(fixes) fixes from OCR")
        }
        #endif

        return result
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
