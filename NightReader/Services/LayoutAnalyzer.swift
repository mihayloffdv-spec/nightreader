import PDFKit
import UIKit

// MARK: - Layout Analyzer
//
// Analyzes PDF page layout: headings, gaps, multi-column, text quality.
// Assembles final content blocks from text + images.
//
// ┌──────────────────────────────────────────┐
// │           LayoutAnalyzer                  │
// │                                          │
// │  assessTextQuality(page) → good/poor     │
// │  detectMultiColumnLayout(lines) → bool   │
// │  detectHeadings(lines) → Set<String>     │
// │  detectGapContent(lines, page) → [Gap]   │
// │  classifyParagraphs(paras, headings)     │
// │  interleaveTextAndImages(text, images..) │
// └──────────────────────────────────────────┘

enum LayoutAnalyzer {

    // MARK: - Text quality assessment

    enum TextQuality {
        case good, poor
    }

    static func assessTextQuality(page: PDFPage, pageBounds: CGRect) -> TextQuality {
        let text = page.string ?? ""
        let charCount = text.count

        if charCount < 30 {
            return .poor
        }

        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        if words.isEmpty { return .poor }

        let reasonableWords = words.filter { $0.count >= 2 && $0.count <= 25 }
        let ratio = Double(reasonableWords.count) / Double(words.count)
        if ratio < 0.3 { return .poor }

        return .good
    }

    // MARK: - Multi-column detection

    /// Detect multi-column layout by clustering text line left margins.
    static func detectMultiColumnLayout(textLines: [(bounds: CGRect, text: String)], pageBounds: CGRect) -> Bool {
        guard textLines.count >= 6 else { return false }

        // Cluster left margins (X positions)
        let leftMargins = textLines.map { $0.bounds.minX }
        let sorted = leftMargins.sorted()

        // Find distinct margin clusters (gap > 15% of page width between clusters)
        let clusterGap = pageBounds.width * 0.15
        var clusters: [[CGFloat]] = [[sorted[0]]]

        for i in 1..<sorted.count {
            if sorted[i] - sorted[i - 1] > clusterGap {
                clusters.append([sorted[i]])
            } else {
                clusters[clusters.count - 1].append(sorted[i])
            }
        }

        // Filter clusters with enough lines (at least 3 each)
        let significantClusters = clusters.filter { $0.count >= 3 }

        // Multi-column if 2+ distinct margin clusters with sufficient horizontal separation
        // AND vertical overlap (lines at the same Y in both clusters = side-by-side columns)
        if significantClusters.count >= 2 {
            let firstClusterAvg = significantClusters[0].reduce(0, +) / CGFloat(significantClusters[0].count)
            let secondClusterAvg = significantClusters[1].reduce(0, +) / CGFloat(significantClusters[1].count)
            guard abs(secondClusterAvg - firstClusterAvg) > pageBounds.width * 0.25 else { return false }

            // Verify vertical overlap: true columns have lines at overlapping Y positions
            let halfGap = clusterGap / 2
            let col1Lines = textLines.filter { abs($0.bounds.minX - firstClusterAvg) < halfGap }
            let col2Lines = textLines.filter { abs($0.bounds.minX - secondClusterAvg) < halfGap }
            let col2MidYs = col2Lines.map { $0.bounds.midY }.sorted()
            let hasVerticalOverlap = col1Lines.contains { line1 in
                let target = line1.bounds.midY
                // Binary search for nearest midY in col2
                var lo = 0, hi = col2MidYs.count - 1
                while lo <= hi {
                    let mid = (lo + hi) / 2
                    if abs(col2MidYs[mid] - target) < 20 { return true }
                    if col2MidYs[mid] < target { lo = mid + 1 } else { hi = mid - 1 }
                }
                return false
            }
            return hasVerticalOverlap
        }

        return false
    }

    // MARK: - Heading detection

    /// Detect heading lines by comparing line heights to the median.
    /// Lines significantly taller than typical body text are likely headings.
    static func detectHeadings(textLines: [(bounds: CGRect, text: String)]) -> Set<String> {
        guard textLines.count >= 3 else { return [] }

        let heights = textLines.map { $0.bounds.height }.sorted()
        let medianHeight = heights[heights.count / 2]
        guard medianHeight > 0 else { return [] }

        let bulletPrefixes: [Character] = ["•", "·", "‣", "▪", "▸", "-", "–", "—"]
        var headingTexts = Set<String>()
        for line in textLines {
            let heightRatio = line.bounds.height / medianHeight
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Heading: significantly larger font AND reasonably short text
            // Exclude:
            //  - bullet/list lines (symbols inflate line height)
            //  - multi-line entries (contain \n — these are tall selections, not headings)
            //  - entries starting with punctuation (garbage from styled text)
            //  - very short entries (< 5 chars — likely garbage)
            if heightRatio > 1.25 && text.count >= 5 && text.count < 120 {
                let startsWithBullet = text.first.map { bulletPrefixes.contains($0) || $0.isNumber } ?? false
                let containsNewline = text.contains("\n")
                let startsWithPunctuation = text.first?.isPunctuation == true || text.first?.isSymbol == true
                if !startsWithBullet && !containsNewline && !startsWithPunctuation {
                    headingTexts.insert(text)
                }
            }
        }
        return headingTexts
    }

    // MARK: - Gap content detection (vector charts, diagrams)

    struct GapRegion {
        let rect: CGRect
    }

    /// Detect large vertical gaps between text lines that likely contain visual content
    /// (vector-drawn charts, diagrams, tables) not captured by XObject scanning.
    static func detectGapContent(
        textLines: [(bounds: CGRect, text: String)],
        page: PDFPage,
        pageBounds: CGRect,
        pageWidth: CGFloat
    ) -> [GapRegion] {
        guard textLines.count >= 2 else { return [] }

        // textLines are sorted by maxY descending (top-to-bottom in PDF coords)
        // Calculate typical line spacing
        var lineSpacings: [CGFloat] = []
        for i in 1..<textLines.count {
            let gap = textLines[i - 1].bounds.minY - textLines[i].bounds.maxY
            if gap > 0 {
                lineSpacings.append(gap)
            }
        }
        guard !lineSpacings.isEmpty else { return [] }

        let sortedSpacings = lineSpacings.sorted()
        let medianSpacing = sortedSpacings[sortedSpacings.count / 2]
        // A gap must be at least 3x median spacing and at least 40pt to be visual content
        let gapThreshold = max(medianSpacing * 3, 40)

        var gaps: [GapRegion] = []
        for i in 1..<textLines.count {
            let topLineBottom = textLines[i - 1].bounds.minY
            let bottomLineTop = textLines[i].bounds.maxY
            let gapHeight = topLineBottom - bottomLineTop

            if gapHeight > gapThreshold && gapHeight.isFinite && gapHeight < pageBounds.height {
                // Build a rect covering this gap region (full page width)
                let gapRect = CGRect(
                    x: pageBounds.minX,
                    y: bottomLineTop,
                    width: pageBounds.width,
                    height: gapHeight
                )
                gaps.append(GapRegion(rect: gapRect))
            }
        }

        // Also check gap between page top and first text line
        let firstLineTop = textLines.first!.bounds.maxY
        let topGap = pageBounds.maxY - firstLineTop
        if topGap > gapThreshold && topGap.isFinite && topGap < pageBounds.height {
            gaps.append(GapRegion(rect: CGRect(
                x: pageBounds.minX,
                y: firstLineTop,
                width: pageBounds.width,
                height: topGap
            )))
        }

        return gaps
    }

    // MARK: - Paragraph classification

    /// Classify paragraphs as headings or body text based on detected heading lines.
    static func classifyParagraphs(_ paragraphs: [String], headingTexts: Set<String>) -> [ContentBlock] {
        paragraphs.compactMap { para in
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            return classifyBlock(trimmed, headingTexts: headingTexts)
        }
    }

    // MARK: - Text + image interleaving

    /// Interleave text paragraphs with images based on Y positions.
    /// Uses extracted CGImages when available, falls back to rendering snapshots.
    static func interleaveTextAndImages(
        fullText: String,
        textLines: [(bounds: CGRect, text: String)],
        extractedImages: [ExtractedImage],
        imageRects: [CGRect],
        page: PDFPage,
        pageBounds: CGRect,
        pageWidth: CGFloat,
        headingTexts: Set<String> = []
    ) -> [ContentBlock] {
        let paragraphs = TextExtractor.splitIntoParagraphs(fullText)
        let pageHeight = pageBounds.height

        // Build image blocks: use CGImage if available, snapshot otherwise
        struct PositionedImage {
            let block: ContentBlock
            let fraction: CGFloat  // 0 = top of page, 1 = bottom
        }

        var positionedImages: [PositionedImage] = []
        for rect in imageRects {
            let fraction = 1.0 - (rect.midY - pageBounds.minY) / pageHeight
            let clampedFraction = min(max(fraction, 0), 1)

            // Check if we have a matching extracted CGImage for this rect
            if let extracted = extractedImages.first(where: { $0.rect.intersects(rect) }) {
                // Scale the raw CGImage to pageWidth — PDF images may have arbitrary
                // native pixel dimensions unrelated to screen size
                let uiImage = PageRenderer.scaleImageToWidth(extracted.cgImage, targetWidth: pageWidth)
                positionedImages.append(PositionedImage(block: .image(uiImage), fraction: clampedFraction))
            } else {
                // Render the region as a snapshot
                if let img = PageRenderer.renderRegion(of: page, region: rect, fitWidth: pageWidth) {
                    positionedImages.append(PositionedImage(block: .snapshot(img), fraction: clampedFraction))
                }
            }
        }

        // Sort images top-to-bottom (ascending fraction)
        positionedImages.sort { $0.fraction < $1.fraction }

        guard !paragraphs.isEmpty else {
            return positionedImages.map { $0.block }
        }

        // Build interleaved blocks
        var blocks: [ContentBlock] = []
        var nextImageIdx = 0

        for (paraIdx, para) in paragraphs.enumerated() {
            let paraFraction = CGFloat(paraIdx) / CGFloat(max(paragraphs.count - 1, 1))

            // Insert images that should appear before this paragraph
            while nextImageIdx < positionedImages.count,
                  positionedImages[nextImageIdx].fraction <= paraFraction + 0.05 {
                blocks.append(positionedImages[nextImageIdx].block)
                nextImageIdx += 1
            }

            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if let block = classifyBlock(trimmed, headingTexts: headingTexts) {
                blocks.append(block)
            }
        }

        // Append remaining images at the end
        while nextImageIdx < positionedImages.count {
            blocks.append(positionedImages[nextImageIdx].block)
            nextImageIdx += 1
        }

        return blocks
    }
}
