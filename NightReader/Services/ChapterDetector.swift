import PDFKit

// MARK: - Chapter model

struct Chapter: Identifiable {
    let id: Int          // 0-based index
    let title: String
    let pageIndex: Int   // First page of this chapter
    let level: Int       // 0 = top-level, 1 = sub-chapter
    let source: Source

    enum Source {
        case pdfOutline    // From embedded PDF TOC
        case autoDetected  // From heading detection
    }
}

// MARK: - Chapter detector
//
// Builds a chapter list from a PDF document.
// Priority: PDF outline (if present) > auto-detected headings.
//
//  ┌───────────────┐     ┌───────────────────┐
//  │ PDFDocument   │────▶│ ChapterDetector    │
//  │ .outlineRoot  │     │                    │
//  └───────────────┘     │  1. Try outline    │
//                        │  2. Scan headings  │
//  ┌───────────────┐     │     per page       │
//  │ LayoutAnalyzer│────▶│  3. Merge & sort   │
//  │ .detectHeadings│    └────────┬────────────┘
//  └───────────────┘              │
//                        ┌────────▼────────────┐
//                        │ [Chapter]            │
//                        └─────────────────────┘

enum ChapterDetector {

    /// Detect chapters from a PDF document.
    /// Runs on the caller's thread — call from a background queue for large documents.
    static func detectChapters(in document: PDFDocument) -> [Chapter] {
        // 1. Try embedded PDF outline first
        let outlineChapters = chaptersFromOutline(document)
        if !outlineChapters.isEmpty {
            return outlineChapters.sorted { $0.pageIndex < $1.pageIndex }
        }

        // 2. Fall back to auto-detection via heading analysis
        // (already sorted by page iteration order)
        return chaptersFromHeadings(document)
    }

    // MARK: - PDF Outline

    private static func chaptersFromOutline(_ document: PDFDocument) -> [Chapter] {
        guard let root = document.outlineRoot, root.numberOfChildren > 0 else { return [] }
        var chapters: [Chapter] = []
        flattenOutline(root, document: document, level: 0, into: &chapters)
        return chapters
    }

    private static func flattenOutline(
        _ item: PDFOutline,
        document: PDFDocument,
        level: Int,
        into chapters: inout [Chapter]
    ) {
        for i in 0..<item.numberOfChildren {
            guard let child = item.child(at: i) else { continue }
            let pageIndex: Int
            if let page = child.destination?.page {
                pageIndex = document.index(for: page)
            } else {
                pageIndex = 0
            }
            chapters.append(Chapter(
                id: chapters.count,
                title: child.label ?? "Untitled",
                pageIndex: pageIndex,
                level: level,
                source: .pdfOutline
            ))
            // Only go 2 levels deep to avoid noise
            if level < 1 && child.numberOfChildren > 0 {
                flattenOutline(child, document: document, level: level + 1, into: &chapters)
            }
        }
    }

    // MARK: - Auto-detection from headings

    private static func chaptersFromHeadings(_ document: PDFDocument) -> [Chapter] {
        var chapters: [Chapter] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            let pageBounds = page.bounds(for: .mediaBox)
            let textLines = TextExtractor.extractTextLines(from: page, pageBounds: pageBounds)
            let headingTexts = LayoutAnalyzer.detectHeadings(textLines: textLines)

            // Take headings that appear in the top half of the page (likely chapter titles)
            let pageHeight = pageBounds.height
            for line in textLines {
                let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard headingTexts.contains(text) else { continue }
                // In PDF coordinates, Y increases upward — top third means Y > 2/3 of height
                let isNearTop = line.bounds.midY > pageHeight * 0.5
                if isNearTop {
                    chapters.append(Chapter(
                        id: chapters.count,
                        title: text,
                        pageIndex: pageIndex,
                        level: 0,
                        source: .autoDetected
                    ))
                    // Only one chapter heading per page
                    break
                }
            }
        }

        return chapters
    }

    // MARK: - Chapter lookup

    /// Find the current chapter for a given page index.
    static func currentChapter(forPage pageIndex: Int, in chapters: [Chapter]) -> Chapter? {
        // Find the last chapter whose pageIndex <= current page
        chapters.last { $0.pageIndex <= pageIndex }
    }

    /// Calculate progress within the current chapter (0.0 - 1.0).
    static func chapterProgress(forPage pageIndex: Int, in chapters: [Chapter], totalPages: Int) -> Double {
        guard let current = currentChapter(forPage: pageIndex, in: chapters) else { return 0 }
        let currentIdx = chapters.firstIndex(where: { $0.id == current.id }) ?? 0
        let nextPageIndex: Int
        if currentIdx + 1 < chapters.count {
            nextPageIndex = chapters[currentIdx + 1].pageIndex
        } else {
            nextPageIndex = totalPages
        }
        let chapterLength = nextPageIndex - current.pageIndex
        guard chapterLength > 0 else { return 1.0 }
        return Double(pageIndex - current.pageIndex) / Double(chapterLength)
    }
}
