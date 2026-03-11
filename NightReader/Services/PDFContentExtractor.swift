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

        // Extract text lines sorted top-to-bottom
        guard let fullSelection = page.selection(for: pageBounds),
              let lineSelections = fullSelection.selectionsByLine() as [PDFSelection]?,
              !lineSelections.isEmpty else {
            if let image = renderFullPage(page, fitWidth: pageWidth) {
                return [.snapshot(image)]
            }
            return []
        }

        var textLines: [(bounds: CGRect, text: String)] = []
        for lineSel in lineSelections {
            let bounds = lineSel.bounds(for: page)
            let text = lineSel.string ?? ""
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textLines.append((bounds, text))
            }
        }

        guard !textLines.isEmpty else {
            if let image = renderFullPage(page, fitWidth: pageWidth) {
                return [.snapshot(image)]
            }
            return []
        }

        // Sort top-to-bottom (PDF coords: higher Y = higher on page)
        textLines.sort { $0.bounds.maxY > $1.bounds.maxY }

        // Extract embedded raster images with their positions
        let extractedImages: [ExtractedImage]
        if let cgPage = page.pageRef {
            extractedImages = Self.extractImages(from: cgPage)
        } else {
            extractedImages = []
        }

        // Build content blocks with gap-based detection
        var blocks: [ContentBlock] = []
        let gapThreshold: CGFloat = 30

        // Gap from page top to first text line
        let pageTop = pageBounds.maxY
        let firstLineTop = textLines[0].bounds.maxY
        if pageTop - firstLineTop > gapThreshold {
            let gapRect = CGRect(
                x: pageBounds.minX, y: firstLineTop,
                width: pageBounds.width, height: pageTop - firstLineTop
            )
            blocks.append(contentsOf: resolveGap(gapRect, page: page, pageWidth: pageWidth, images: extractedImages))
        }

        // Process text lines and gaps
        var pendingText = ""
        for i in 0..<textLines.count {
            let line = textLines[i]
            pendingText += (pendingText.isEmpty ? "" : "\n") + line.text

            if i + 1 < textLines.count {
                let thisBottom = line.bounds.minY
                let nextTop = textLines[i + 1].bounds.maxY
                let gap = thisBottom - nextTop

                if gap > gapThreshold {
                    // Flush pending text
                    if !pendingText.isEmpty {
                        blocks.append(.text(pendingText))
                        pendingText = ""
                    }
                    // Resolve gap — use extracted image if available, else snapshot
                    let gapRect = CGRect(
                        x: pageBounds.minX, y: nextTop,
                        width: pageBounds.width, height: gap
                    )
                    blocks.append(contentsOf: resolveGap(gapRect, page: page, pageWidth: pageWidth, images: extractedImages))
                }
            }
        }

        // Flush remaining text
        if !pendingText.isEmpty {
            blocks.append(.text(pendingText))
        }

        // Gap from last text line to page bottom
        let lastLineBottom = textLines.last!.bounds.minY
        let pageBottom = pageBounds.minY
        if lastLineBottom - pageBottom > gapThreshold {
            let gapRect = CGRect(
                x: pageBounds.minX, y: pageBottom,
                width: pageBounds.width, height: lastLineBottom - pageBottom
            )
            blocks.append(contentsOf: resolveGap(gapRect, page: page, pageWidth: pageWidth, images: extractedImages))
        }

        return blocks
    }

    // MARK: - Gap resolution: prefer extracted images over snapshots

    /// Check if an extracted image falls within the gap. If so, use it directly.
    /// Otherwise, render the gap region as a snapshot.
    private static func resolveGap(
        _ gapRect: CGRect,
        page: PDFPage,
        pageWidth: CGFloat,
        images: [ExtractedImage]
    ) -> [ContentBlock] {
        // Find images that overlap with this gap (at least 50% of their area inside the gap)
        let matchingImages = images.filter { img in
            let intersection = img.rect.intersection(gapRect)
            guard !intersection.isNull else { return false }
            let overlapArea = intersection.width * intersection.height
            let imageArea = img.rect.width * img.rect.height
            return imageArea > 0 && overlapArea / imageArea > 0.5
        }.sorted { $0.rect.maxY > $1.rect.maxY } // top-to-bottom

        if !matchingImages.isEmpty {
            // Use extracted images directly
            return matchingImages.map { extracted in
                let uiImage = UIImage(cgImage: extracted.cgImage)
                return .image(uiImage)
            }
        }

        // No matching extracted images — fall back to region snapshot
        if let img = renderRegion(of: page, region: gapRect, fitWidth: pageWidth) {
            return [.snapshot(img)]
        }
        return []
    }

    // MARK: - CGPDFScanner image extraction

    /// Extract all raster images from a PDF page with their positions.
    private static func extractImages(from cgPage: CGPDFPage) -> [ExtractedImage] {
        let context = ScannerContext()

        guard let operatorTable = CGPDFOperatorTableCreate() else { return [] }

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
            ctx.ctm = ctx.ctm.concatenating(matrix)
        }

        // Do — invoke XObject (images are drawn here)
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

            // Check subtype is Image
            var subtypePtr: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dict, "Subtype", &subtypePtr),
                  let subtype = subtypePtr,
                  String(cString: subtype) == "Image" else { return }

            // Skip very small images (icons, bullets, decorations < 20px)
            var width: CGPDFInteger = 0, height: CGPDFInteger = 0
            CGPDFDictionaryGetInteger(dict, "Width", &width)
            CGPDFDictionaryGetInteger(dict, "Height", &height)
            guard width > 20 && height > 20 else { return }

            // Image is drawn in a 1×1 unit square, CTM transforms it
            let imageRect = CGRect(x: 0, y: 0, width: 1, height: 1).applying(ctx.ctm)
            // Skip tiny rendered images (< 20pt on page)
            guard imageRect.width > 20 && imageRect.height > 20 else { return }

            // Extract the actual CGImage
            guard let cgImage = extractCGImageFromStream(pdfStream, dict: dict) else { return }

            ctx.images.append(ExtractedImage(cgImage: cgImage, rect: imageRect))
        }

        let contentStream = CGPDFContentStreamCreateWithPage(cgPage)
        let opaqueCtx = Unmanaged.passUnretained(context).toOpaque()
        let scanner = CGPDFScannerCreate(contentStream, operatorTable, opaqueCtx)

        _ = withExtendedLifetime(context) {
            CGPDFScannerScan(scanner)
        }
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(contentStream)

        return context.images
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

    // MARK: - Scanner context (tracks CTM for image positions)

    private class ScannerContext {
        var ctm: CGAffineTransform = .identity
        var stateStack: [CGAffineTransform] = []
        var images: [ExtractedImage] = []
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
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: outputSize))

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
