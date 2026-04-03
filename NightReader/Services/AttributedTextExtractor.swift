import PDFKit
import UIKit

// MARK: - Attributed Text Extractor
//
// Uses PDFSelection.attributedString (Apple's internal decoder) to extract
// text WITH formatting from PDF pages. This preserves bold, italic, and
// font size information that page.string loses.
//
// Unlike our CGPDFScanner-based RichTextExtractor, this uses Apple's
// built-in font decoder which handles all encoding types correctly
// (including custom Cyrillic encodings without ToUnicode maps).
//
// ┌─────────────────────────────────────────────────────┐
// │         AttributedTextExtractor                      │
// │                                                     │
// │  extractAttributedText(page) → NSAttributedString?  │
// │    └── PDFSelection.attributedString (Apple decoder) │
// │                                                     │
// │  splitIntoBlocks(attrString) → [ContentBlock]       │
// │    ├── Detect headings by font size                  │
// │    └── Split paragraphs by newlines + font changes   │
// └─────────────────────────────────────────────────────┘

enum AttributedTextExtractor {

    /// Extract attributed text from a PDF page using Apple's built-in decoder.
    /// Returns nil if the page has no selectable text.
    static func extractAttributedText(from page: PDFPage) -> NSAttributedString? {
        let bounds = page.bounds(for: .mediaBox)
        guard let selection = page.selection(for: bounds) else { return nil }

        // PDFSelection.attributedString uses Apple's internal font decoder
        // which correctly handles all encoding types
        guard let attrString = selection.attributedString else { return nil }
        guard attrString.length > 10 else { return nil }

        return attrString
    }

    /// Split attributed string into ContentBlocks, detecting headings by font size.
    static func splitIntoBlocks(
        _ attrString: NSAttributedString,
        headingThreshold: CGFloat = 1.3
    ) -> [ContentBlock] {
        let fullText = attrString.string
        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        // Find the median body font size
        let medianSize = findMedianFontSize(in: attrString)
        let headingSize = medianSize * headingThreshold

        // Split by paragraphs (double newline or significant font size change)
        var blocks: [ContentBlock] = []
        let paragraphs = splitIntoParagraphs(attrString)

        for para in paragraphs {
            let trimmedString = para.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedString.isEmpty else { continue }

            // Check if this paragraph is a heading (dominant font size > threshold)
            let dominantSize = findDominantFontSize(in: para)

            if dominantSize > headingSize && trimmedString.count < 200 {
                // It's a heading — use .richText to preserve formatting
                blocks.append(.richText(para))
            } else {
                // Body text — use .richText to preserve bold/italic
                blocks.append(.richText(para))
            }
        }

        return blocks
    }

    // MARK: - Paragraph splitting

    /// Split attributed string into paragraphs by newlines.
    private static func splitIntoParagraphs(_ attrString: NSAttributedString) -> [NSAttributedString] {
        let fullText = attrString.string
        var paragraphs: [NSAttributedString] = []

        // Split on double newlines first, then on single newlines with context
        let nsString = fullText as NSString
        var currentStart = 0

        // Find paragraph breaks: blank lines or significant vertical spacing
        let lines = fullText.components(separatedBy: .newlines)
        var lineStart = 0

        var currentParagraphStart = 0
        var lastNonEmptyEnd = 0

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineEnd = lineStart + line.count

            if trimmed.isEmpty {
                // Empty line = paragraph break
                if lastNonEmptyEnd > currentParagraphStart {
                    let range = NSRange(location: currentParagraphStart, length: lastNonEmptyEnd - currentParagraphStart)
                    if range.location + range.length <= attrString.length {
                        let sub = attrString.attributedSubstring(from: range)
                        if !sub.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            paragraphs.append(sub)
                        }
                    }
                }
                currentParagraphStart = lineEnd + 1 // skip newline
            } else {
                lastNonEmptyEnd = lineEnd
            }

            lineStart = lineEnd + 1 // +1 for newline character
        }

        // Last paragraph
        if lastNonEmptyEnd > currentParagraphStart {
            let range = NSRange(location: currentParagraphStart, length: min(lastNonEmptyEnd - currentParagraphStart, attrString.length - currentParagraphStart))
            if range.location + range.length <= attrString.length && range.length > 0 {
                let sub = attrString.attributedSubstring(from: range)
                if !sub.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    paragraphs.append(sub)
                }
            }
        }

        // If no paragraph breaks found, return the whole thing as one block
        if paragraphs.isEmpty && attrString.length > 0 {
            paragraphs.append(attrString)
        }

        return paragraphs
    }

    // MARK: - Font analysis

    /// Find the median font size in an attributed string (body text size).
    private static func findMedianFontSize(in attrString: NSAttributedString) -> CGFloat {
        var sizes: [CGFloat] = []
        let range = NSRange(location: 0, length: attrString.length)

        attrString.enumerateAttribute(.font, in: range) { value, attrRange, _ in
            if let font = value as? UIFont {
                // Weight by character count
                for _ in 0..<attrRange.length {
                    sizes.append(font.pointSize)
                }
            }
        }

        guard !sizes.isEmpty else { return 12 }
        sizes.sort()
        return sizes[sizes.count / 2]
    }

    /// Find the dominant (most common) font size in a paragraph.
    private static func findDominantFontSize(in attrString: NSAttributedString) -> CGFloat {
        var sizeCount: [CGFloat: Int] = [:]
        let range = NSRange(location: 0, length: attrString.length)

        attrString.enumerateAttribute(.font, in: range) { value, attrRange, _ in
            if let font = value as? UIFont {
                sizeCount[font.pointSize, default: 0] += attrRange.length
            }
        }

        return sizeCount.max(by: { $0.value < $1.value })?.key ?? 12
    }
}
