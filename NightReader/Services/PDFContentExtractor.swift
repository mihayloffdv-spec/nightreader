import PDFKit
import UIKit
import CoreGraphics

// MARK: - Content block types

enum ContentBlock {
    case text(String)
    case image(UIImage)    // Extracted raster image from PDF
    case snapshot(UIImage)  // Rendered region snapshot (tables, diagrams, etc.)
}

// MARK: - Extracted image with position

private struct ExtractedImage {
    let cgImage: CGImage
    let rect: CGRect  // Position in PDF page coordinates
}

// MARK: - Block cache

final class BlockCache {
    static let shared = BlockCache()

    private let cache = NSCache<NSString, CachedBlocks>()

    private init() {
        cache.countLimit = 30  // ~30 pages
        cache.totalCostLimit = 60 * 1024 * 1024  // ~60MB

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    func blocks(forPage pageIndex: Int, width: CGFloat) -> [ContentBlock]? {
        let key = "\(pageIndex)_\(Int(width.rounded()))" as NSString
        return cache.object(forKey: key)?.blocks
    }

    func store(_ blocks: [ContentBlock], forPage pageIndex: Int, width: CGFloat) {
        let key = "\(pageIndex)_\(Int(width.rounded()))" as NSString
        let cost = blocks.reduce(0) { sum, block in
            switch block {
            case .text: return sum + 256
            case .image(let img), .snapshot(let img):
                let bytes = Int(img.size.width * img.scale * img.size.height * img.scale * 4)
                return sum + bytes
            }
        }
        cache.setObject(CachedBlocks(blocks: blocks), forKey: key, cost: cost)
    }

    func invalidate() {
        cache.removeAllObjects()
    }
}

private class CachedBlocks: NSObject {
    let blocks: [ContentBlock]
    init(blocks: [ContentBlock]) { self.blocks = blocks }
}

// MARK: - PDF Content Extractor

final class PDFContentExtractor {

    /// Extract content blocks from a single PDF page.
    /// Returns an ordered array of text, image, and snapshot blocks (top to bottom).
    static func extractBlocks(from page: PDFPage, pageWidth: CGFloat) -> [ContentBlock] {
        let pageBounds = page.bounds(for: .mediaBox)

        // Assess text quality — if poor, render entire page as snapshot
        let quality = assessTextQuality(page: page, pageBounds: pageBounds)
        if quality == .poor {
            if let image = renderFullPage(page, fitWidth: pageWidth) {
                return [.snapshot(image)]
            }
            return []
        }

        // Scan page content: images, rectangles, lines, fonts
        let scanResult: ScannerContext
        if let cgPage = page.pageRef {
            scanResult = Self.scanPageContent(from: cgPage)
        } else {
            scanResult = ScannerContext()
        }

        // Get line selections for layout analysis (multi-column, complex regions)
        var textLines: [(bounds: CGRect, text: String)] = []
        if let fullSelection = page.selection(for: pageBounds),
           let lineSelections = fullSelection.selectionsByLine() as [PDFSelection]? {
            for lineSel in lineSelections {
                let bounds = lineSel.bounds(for: page)
                let text = lineSel.string ?? ""
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    textLines.append((bounds, text))
                }
            }
            textLines.sort { $0.bounds.maxY > $1.bounds.maxY }
        }

        // Detect multi-column layout → full page snapshot (text reflow won't work)
        let isMultiColumn = !textLines.isEmpty && detectMultiColumnLayout(textLines: textLines, pageBounds: pageBounds)
        if isMultiColumn {
            if let image = renderFullPage(page, fitWidth: pageWidth) {
                return [.snapshot(image)]
            }
            return []
        }

        // === New approach: use page.string for reliable text extraction ===
        // page.string captures ALL characters including styled/offset first letters
        // that selectionsByLine() misses due to spatial splitting
        guard let fullText = page.string,
              !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let image = renderFullPage(page, fitWidth: pageWidth) {
                return [.snapshot(image)]
            }
            return []
        }

        // If no images/forms on the page, just split text into paragraphs
        if scanResult.imageRects.isEmpty {
            return splitIntoParagraphs(fullText).map { .text($0) }
        }

        // With images: interleave text paragraphs and images by Y position
        return interleaveTextAndImages(
            fullText: fullText,
            textLines: textLines,
            extractedImages: scanResult.images,
            imageRects: scanResult.imageRects,
            page: page,
            pageBounds: pageBounds,
            pageWidth: pageWidth
        )
    }

    // MARK: - Text paragraph splitting

    /// Split full page text into paragraphs using multiple heuristics:
    /// 1. Blank lines → always break
    /// 2. Short lines → likely heading or paragraph end
    /// 3. Sentence-ending punctuation + next line starts with capital → paragraph break
    private static func splitIntoParagraphs(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        let nonEmptyLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
                                 .filter { !$0.isEmpty }
        guard !nonEmptyLines.isEmpty else { return [] }

        // Find typical line length to detect short (paragraph-ending) lines
        let lengths = nonEmptyLines.map { $0.count }
        let sortedLengths = lengths.sorted()
        let typicalLength = sortedLengths[min(sortedLengths.count * 3 / 4, sortedLengths.count - 1)]
        let shortThreshold = max(typicalLength * 2 / 3, 15)

        // Build array of non-empty trimmed lines with their indices for lookahead
        struct IndexedLine { let index: Int; let text: String }
        var indexedLines: [IndexedLine] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                indexedLines.append(IndexedLine(index: i, text: trimmed))
            }
        }

        var paragraphs: [String] = []
        var currentLines: [String] = []

        for (idx, il) in indexedLines.enumerated() {
            // Check for blank lines between previous and current non-empty line
            if idx > 0 {
                let prevLineIndex = indexedLines[idx - 1].index
                let hasBlankBetween = (il.index - prevLineIndex) > 1
                if hasBlankBetween && !currentLines.isEmpty {
                    paragraphs.append(joinLines(currentLines))
                    currentLines = []
                }
            }

            currentLines.append(il.text)

            // Determine if this line ends a paragraph
            let isShortLine = il.text.count < shortThreshold
            let sentenceEndings: [Character] = [".", "!", "?", ":", "»"]
            let endsWithSentence = il.text.last.map { sentenceEndings.contains($0) } ?? false

            // Look ahead: does next line start with uppercase?
            let nextStartsUpper: Bool
            if idx + 1 < indexedLines.count {
                nextStartsUpper = indexedLines[idx + 1].text.first?.isUppercase == true
            } else {
                nextStartsUpper = false
            }

            let shouldBreak = isShortLine ||
                              (endsWithSentence && nextStartsUpper && currentLines.count >= 2)

            if shouldBreak {
                paragraphs.append(joinLines(currentLines))
                currentLines = []
            }
        }

        if !currentLines.isEmpty {
            paragraphs.append(joinLines(currentLines))
        }

        return paragraphs.filter { !$0.isEmpty }
    }

    /// Join lines handling hyphenated word breaks: "технол-" + "огия" → "технология"
    /// Preserves compound words like "из-за" by only dehyphenating when next line starts lowercase.
    private static func joinLines(_ lines: [String]) -> String {
        guard lines.count > 1 else { return lines.first ?? "" }
        var result = ""
        for (i, line) in lines.enumerated() {
            if i > 0 {
                let endsWithHyphen = result.hasSuffix("-") || result.hasSuffix("\u{00AD}")
                let startsLowercase = line.first?.isLowercase == true
                if endsWithHyphen && startsLowercase {
                    // Word wrapped with hyphen: "технол-" + "огия" → "технология"
                    result.removeLast() // remove hyphen/soft-hyphen
                } else {
                    result += " "
                }
            }
            result += line
        }
        return result
    }

    // MARK: - Text + image interleaving

    /// Interleave text paragraphs with images based on Y positions.
    /// Uses extracted CGImages when available, falls back to rendering snapshots.
    private static func interleaveTextAndImages(
        fullText: String,
        textLines: [(bounds: CGRect, text: String)],
        extractedImages: [ExtractedImage],
        imageRects: [CGRect],
        page: PDFPage,
        pageBounds: CGRect,
        pageWidth: CGFloat
    ) -> [ContentBlock] {
        let paragraphs = splitIntoParagraphs(fullText)
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
                let uiImage = UIImage(cgImage: extracted.cgImage)
                positionedImages.append(PositionedImage(block: .image(uiImage), fraction: clampedFraction))
            } else {
                // Render the region as a snapshot
                if let img = renderRegion(of: page, region: rect, fitWidth: pageWidth) {
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

            blocks.append(.text(para))
        }

        // Append remaining images at the end
        while nextImageIdx < positionedImages.count {
            blocks.append(positionedImages[nextImageIdx].block)
            nextImageIdx += 1
        }

        return blocks
    }

    // MARK: - CGPDFScanner content extraction

    /// Scan a PDF page for images, rectangles, lines, and font usage.
    private static func scanPageContent(from cgPage: CGPDFPage) -> ScannerContext {
        let context = ScannerContext()
        context.pageBounds = cgPage.getBoxRect(.mediaBox)

        guard let operatorTable = CGPDFOperatorTableCreate() else { return context }

        // q — save graphics state
        CGPDFOperatorTableSetCallback(operatorTable, "q") { _, info in
            guard let info else { return }
            let ctx = Unmanaged<ScannerContext>.fromOpaque(info).takeUnretainedValue()
            ctx.stateStack.append(ctx.ctm)
        }

        // Q — restore graphics state
        CGPDFOperatorTableSetCallback(operatorTable, "Q") { _, info in
            guard let info else { return }
            let ctx = Unmanaged<ScannerContext>.fromOpaque(info).takeUnretainedValue()
            if let saved = ctx.stateStack.popLast() {
                ctx.ctm = saved
            }
        }

        // cm — concatenate matrix
        CGPDFOperatorTableSetCallback(operatorTable, "cm") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<ScannerContext>.fromOpaque(info).takeUnretainedValue()
            var a: CGPDFReal = 0, b: CGPDFReal = 0, c: CGPDFReal = 0
            var d: CGPDFReal = 0, tx: CGPDFReal = 0, ty: CGPDFReal = 0
            CGPDFScannerPopNumber(scanner, &ty)
            CGPDFScannerPopNumber(scanner, &tx)
            CGPDFScannerPopNumber(scanner, &d)
            CGPDFScannerPopNumber(scanner, &c)
            CGPDFScannerPopNumber(scanner, &b)
            CGPDFScannerPopNumber(scanner, &a)
            let matrix = CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
            // PDF spec: CTM' = M × CTM (new matrix applied first, then existing CTM)
            ctx.ctm = matrix.concatenating(ctx.ctm)
        }

        // Do — invoke XObject (images and form XObjects are drawn here)
        CGPDFOperatorTableSetCallback(operatorTable, "Do") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<ScannerContext>.fromOpaque(info).takeUnretainedValue()

            var namePtr: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &namePtr), let name = namePtr else { return }

            let contentStream = CGPDFScannerGetContentStream(scanner)
            guard let xobject = CGPDFContentStreamGetResource(contentStream, "XObject", name)
            else { return }

            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(xobject, .stream, &stream), let pdfStream = stream else { return }
            guard let dict = CGPDFStreamGetDictionary(pdfStream) else { return }

            var subtypePtr: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dict, "Subtype", &subtypePtr),
                  let subtype = subtypePtr else { return }

            let subtypeStr = String(cString: subtype)

            // XObject is drawn in a 1×1 unit square, CTM transforms it
            let xobjRect = CGRect(x: 0, y: 0, width: 1, height: 1).applying(ctx.ctm)
            // Skip tiny rendered objects (< 30pt on page)
            guard abs(xobjRect.width) > 30 && abs(xobjRect.height) > 30 else { return }
            let normalizedRect = xobjRect.standardized

            if subtypeStr == "Image" {
                // Always record the rect so we can render as snapshot if CGImage fails
                ctx.imageRects.append(normalizedRect)

                // Try to extract CGImage (may fail for complex color spaces)
                var width: CGPDFInteger = 0, height: CGPDFInteger = 0
                CGPDFDictionaryGetInteger(dict, "Width", &width)
                CGPDFDictionaryGetInteger(dict, "Height", &height)
                if width > 20 && height > 20,
                   let cgImage = extractCGImageFromStream(pdfStream, dict: dict) {
                    ctx.images.append(ExtractedImage(cgImage: cgImage, rect: normalizedRect))
                }
            } else if subtypeStr == "Form" {
                // Form XObjects may contain images, diagrams, or complex compositions.
                // Skip only truly full-page forms (backgrounds, watermarks, templates)
                // by checking if the form covers ~the entire page dimensions
                let isFullPage = normalizedRect.width > ctx.pageBounds.width * 0.9 &&
                                 normalizedRect.height > ctx.pageBounds.height * 0.9
                if !isFullPage {
                    ctx.imageRects.append(normalizedRect)
                }
            }
        }

        let contentStream = CGPDFContentStreamCreateWithPage(cgPage)
        let opaqueCtx = Unmanaged.passUnretained(context).toOpaque()
        let scanner = CGPDFScannerCreate(contentStream, operatorTable, opaqueCtx)

        _ = withExtendedLifetime(context) {
            CGPDFScannerScan(scanner)
        }
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(contentStream)

        return context
    }

    /// Extract CGImage from a PDF image stream.
    fileprivate static func extractCGImage(from stream: CGPDFStreamRef, dict: CGPDFDictionaryRef) -> CGImage? {
        var format: CGPDFDataFormat = .raw
        guard let data = CGPDFStreamCopyData(stream, &format) else { return nil }

        // JPEG — create directly
        if format == .JPEG2000 || format == .jpegEncoded {
            guard let provider = CGDataProvider(data: data) else { return nil }
            return CGImage(
                jpegDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        }

        // Raw pixel data — reconstruct CGImage
        var width: CGPDFInteger = 0, height: CGPDFInteger = 0, bpc: CGPDFInteger = 0
        CGPDFDictionaryGetInteger(dict, "Width", &width)
        CGPDFDictionaryGetInteger(dict, "Height", &height)
        CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bpc)
        guard width > 0, height > 0, bpc > 0 else { return nil }

        // Determine color space
        let colorSpace: CGColorSpace
        var csNamePtr: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(dict, "ColorSpace", &csNamePtr), let csName = csNamePtr {
            switch String(cString: csName) {
            case "DeviceGray": colorSpace = CGColorSpaceCreateDeviceGray()
            case "DeviceCMYK": colorSpace = CGColorSpace(name: CGColorSpace.genericCMYK) ?? CGColorSpaceCreateDeviceRGB()
            default: colorSpace = CGColorSpaceCreateDeviceRGB()
            }
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB()
        }

        let components = colorSpace.numberOfComponents
        let bitsPerPixel = Int(bpc) * components
        let bytesPerRow = (Int(width) * bitsPerPixel + 7) / 8

        guard let provider = CGDataProvider(data: data) else { return nil }

        return CGImage(
            width: Int(width),
            height: Int(height),
            bitsPerComponent: Int(bpc),
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    // MARK: - Scanner context (tracks CTM, paths, fonts for detection)

    private class ScannerContext {
        var ctm: CGAffineTransform = .identity
        var stateStack: [CGAffineTransform] = []
        var images: [ExtractedImage] = []       // Successfully extracted CGImages
        var imageRects: [CGRect] = []           // ALL image/form XObject positions (for snapshot fallback)
        var pageBounds: CGRect = .zero          // Page bounds for relative size filtering
    }

    /// Detect multi-column layout by clustering text line left margins.
    private static func detectMultiColumnLayout(textLines: [(bounds: CGRect, text: String)], pageBounds: CGRect) -> Bool {
        guard textLines.count >= 6 else { return false }

        // Cluster left margins (X positions)
        let leftMargins = textLines.map { $0.bounds.minX }
        let sorted = leftMargins.sorted()

        // Find distinct margin clusters (gap > 30% of page width between clusters)
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

    // MARK: - Rendering

    /// Render a specific region of a PDF page to a UIImage.
    static func renderRegion(of page: PDFPage, region: CGRect, fitWidth: CGFloat) -> UIImage? {
        guard let cgPage = page.pageRef,
              region.width > 0 && region.height > 0 else { return nil }

        let pageBounds = page.bounds(for: .mediaBox)
        let scaleFactor = fitWidth / pageBounds.width
        let outputSize = CGSize(
            width: fitWidth,
            height: region.height * scaleFactor
        )
        let scale: CGFloat = 2.0

        let pixelW = Int(ceil(outputSize.width * scale))
        let pixelH = Int(ceil(outputSize.height * scale))
        guard pixelW > 0, pixelH > 0, pixelW < 8192, pixelH < 8192 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        // Clear with transparent background (avoids white blocks in dark themes)
        ctx.clear(CGRect(origin: .zero, size: outputSize))

        ctx.scaleBy(x: scaleFactor, y: scaleFactor)
        // Clip in PDF coords before translating (clip is in current user space)
        ctx.clip(to: region)
        ctx.translateBy(x: -region.origin.x, y: -region.origin.y)
        ctx.drawPDFPage(cgPage)

        guard let cgImage = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    /// Render a full PDF page fitted to a given width.
    static func renderFullPage(_ page: PDFPage, fitWidth: CGFloat) -> UIImage? {
        guard let cgPage = page.pageRef else { return nil }
        let mediaBox = page.bounds(for: .mediaBox)
        let aspect = mediaBox.height / mediaBox.width
        let outputSize = CGSize(width: fitWidth, height: fitWidth * aspect)
        let scale: CGFloat = 2.0

        let pixelW = Int(ceil(outputSize.width * scale))
        let pixelH = Int(ceil(outputSize.height * scale))
        guard pixelW > 0, pixelH > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: outputSize))

        let drawTransform = cgPage.getDrawingTransform(
            .mediaBox,
            rect: CGRect(origin: .zero, size: outputSize),
            rotate: 0,
            preserveAspectRatio: true
        )
        ctx.concatenate(drawTransform)
        ctx.drawPDFPage(cgPage)

        guard let cgImage = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}

// Free function accessible from C callbacks (can't capture Self in C closures)
private func extractCGImageFromStream(_ stream: CGPDFStreamRef, dict: CGPDFDictionaryRef) -> CGImage? {
    PDFContentExtractor.extractCGImage(from: stream, dict: dict)
}
