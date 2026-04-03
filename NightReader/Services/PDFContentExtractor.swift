import PDFKit
import UIKit

// MARK: - PDF Content Extractor (Orchestrator)
//
// Thin orchestrator that coordinates the extraction pipeline.
// All heavy lifting is delegated to focused modules:
//
// ┌─────────────────────────────────────────────────────────┐
// │              PDFContentExtractor                         │
// │                                                         │
// │  extractBlocks(page, pageWidth) → [ContentBlock]       │
// │    1. LayoutAnalyzer.assessTextQuality()  → poor? snap  │
// │    2. ImageExtractor.scanPageContent()    → imgs, rects │
// │    3. TextExtractor.extractTextLines()    → lines       │
// │    4. LayoutAnalyzer.detectMultiColumnLayout() → snap?  │
// │    5. TextExtractor.recoverDropCaps()     → clean text  │
// │    6. LayoutAnalyzer.detectHeadings()     → heading set │
// │    7. LayoutAnalyzer.detectGapContent()   → gap regions │
// │    8. LayoutAnalyzer.interleaveTextAndImages() → blocks │
// │       OR LayoutAnalyzer.classifyParagraphs()            │
// └─────────────────────────────────────────────────────────┘
//
// Modules:
//   ContentTypes.swift   — shared types (ContentBlock, ExtractedImage, BlockCache)
//   TextExtractor.swift  — text extraction, paragraph splitting, drop cap recovery
//   ImageExtractor.swift — CGPDFScanner, XObject extraction
//   LayoutAnalyzer.swift — headings, columns, gaps, interleaving
//   PageRenderer.swift   — region/full-page rendering, image scaling

enum PDFContentExtractor {

    /// Extract content blocks from a PDF page for Reader Mode display.
    static func extractBlocks(from page: PDFPage, pageWidth: CGFloat) -> [ContentBlock] {
        let pageBounds = page.bounds(for: .mediaBox)

        // 1. Assess text quality — poor text means scanned/garbled page → snapshot
        let quality = LayoutAnalyzer.assessTextQuality(page: page, pageBounds: pageBounds)
        if quality == .poor {
            if let image = PageRenderer.renderFullPage(page, fitWidth: pageWidth) {
                return [.snapshot(image)]
            }
            return []
        }

        // 2. Scan page content stream for XObject images and form XObjects
        let scanResult: ImageExtractor.ScanResult
        if let cgPage = page.pageRef {
            scanResult = ImageExtractor.scanPageContent(from: cgPage)
        } else {
            scanResult = ImageExtractor.ScanResult()
        }

        // 3. Extract positioned text lines for layout analysis
        let textLines = TextExtractor.extractTextLines(from: page, pageBounds: pageBounds)

        // 4. Multi-column layout → full page snapshot (text reflow won't work)
        let isMultiColumn = !textLines.isEmpty &&
            LayoutAnalyzer.detectMultiColumnLayout(textLines: textLines, pageBounds: pageBounds)
        if isMultiColumn {
            if let image = PageRenderer.renderFullPage(page, fitWidth: pageWidth) {
                return [.snapshot(image)]
            }
            return []
        }

        // 5. Rich text extraction disabled — CMap parser doesn't handle all PDF encodings yet.
        // TODO: Fix RichTextExtractor CMap decoding for custom-encoded Cyrillic fonts,
        // then re-enable. The infrastructure (RichTextExtractor, RichTextBlock) is ready.

        // 5b. Plain text extraction (reliable, loses formatting)
        guard let pageString = page.string,
              !pageString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let image = PageRenderer.renderFullPage(page, fitWidth: pageWidth) {
                return [.snapshot(image)]
            }
            return []
        }
        let pageIndex = page.document?.index(for: page)
        let strippedPageString = TextExtractor.stripLeadingPageNumber(from: pageString, pageIndex: pageIndex)
        let fullText = DropCapRecovery.recoverDropCaps(
            pageString: strippedPageString,
            textLines: textLines,
            page: page,
            pageBounds: pageBounds
        )

        // 6. Detect heading lines based on font size
        let headingTexts = LayoutAnalyzer.detectHeadings(textLines: textLines)

        // 7. Detect visual content in large gaps between text lines
        let gapSnapshots = LayoutAnalyzer.detectGapContent(
            textLines: textLines, page: page,
            pageBounds: pageBounds, pageWidth: pageWidth
        )

        // 8. Merge gap regions into image rects (skip overlaps with existing XObjects)
        var allImageRects = scanResult.imageRects
        let allImages = scanResult.images
        for gap in gapSnapshots {
            let overlapsExisting = scanResult.imageRects.contains { $0.intersects(gap.rect) }
            if !overlapsExisting {
                allImageRects.append(gap.rect)
            }
        }

        #if DEBUG
        let debugPageIndex = pageIndex ?? -1
        print("[PDFExtractor] Page \(debugPageIndex): textLines=\(textLines.count), xobjectRects=\(scanResult.imageRects.count), gapRegions=\(gapSnapshots.count), headings=\(headingTexts.count)")
        if !headingTexts.isEmpty {
            print("[PDFExtractor]   headings: \(headingTexts)")
        }
        let preview = String(fullText.prefix(100)).replacingOccurrences(of: "\n", with: "↵")
        print("[PDFExtractor]   text preview: \(preview)...")
        #endif

        // 9. Build content blocks
        if allImageRects.isEmpty {
            // Text-only page
            let blocks = LayoutAnalyzer.classifyParagraphs(
                TextExtractor.splitIntoParagraphs(fullText),
                headingTexts: headingTexts
            )
            #if DEBUG
            print("[PDFExtractor]   → \(blocks.count) blocks (text-only)")
            #endif
            return blocks
        }

        // Interleave text paragraphs with images by Y position
        let blocks = LayoutAnalyzer.interleaveTextAndImages(
            fullText: fullText,
            textLines: textLines,
            extractedImages: allImages,
            imageRects: allImageRects,
            page: page,
            pageBounds: pageBounds,
            pageWidth: pageWidth,
            headingTexts: headingTexts
        )
        #if DEBUG
        let blockTypes = blocks.map { b -> String in
            switch b {
            case .text(let t): return "text(\(t.prefix(30)))"
            case .heading(let t): return "heading(\(t.prefix(30)))"
            case .richText(let a): return "richText(\(a.string.prefix(30)))"
            case .image: return "image"
            case .snapshot: return "snapshot"
            }
        }
        print("[PDFExtractor]   → \(blocks.count) blocks: \(blockTypes)")
        #endif
        return blocks
    }
}
