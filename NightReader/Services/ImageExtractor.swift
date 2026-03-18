import PDFKit
import UIKit
import CoreGraphics

// MARK: - Image Extractor
//
// Scans PDF page content stream for XObject images and Form XObjects.
// Uses CGPDFScanner with operator callbacks to track CTM and extract images.
//
// ┌──────────────────────────────────────────────┐
// │              ImageExtractor                    │
// │                                                │
// │  scanPageContent(cgPage) → ScanResult         │
// │    ├── tracks CTM via q/Q/cm callbacks        │
// │    ├── extracts Image XObjects (Do callback)  │
// │    └── records Form XObject positions          │
// │                                                │
// │  extractCGImage(stream, dict) → CGImage?      │
// └──────────────────────────────────────────────┘

enum ImageExtractor {

    // MARK: - Scan result

    final class ScanResult {
        var ctm: CGAffineTransform = .identity
        var stateStack: [CGAffineTransform] = []
        var images: [ExtractedImage] = []       // Successfully extracted CGImages
        var imageRects: [CGRect] = []           // ALL image/form XObject positions (for snapshot fallback)
        var pageBounds: CGRect = .zero          // Page bounds for relative size filtering
    }

    // MARK: - Page content scanning

    /// Scan a PDF page for images, rectangles, lines, and font usage.
    static func scanPageContent(from cgPage: CGPDFPage) -> ScanResult {
        let context = ScanResult()
        context.pageBounds = cgPage.getBoxRect(.mediaBox)

        guard let operatorTable = CGPDFOperatorTableCreate() else { return context }

        // q — save graphics state
        CGPDFOperatorTableSetCallback(operatorTable, "q") { _, info in
            guard let info else { return }
            let ctx = Unmanaged<ScanResult>.fromOpaque(info).takeUnretainedValue()
            ctx.stateStack.append(ctx.ctm)
        }

        // Q — restore graphics state
        CGPDFOperatorTableSetCallback(operatorTable, "Q") { _, info in
            guard let info else { return }
            let ctx = Unmanaged<ScanResult>.fromOpaque(info).takeUnretainedValue()
            if let saved = ctx.stateStack.popLast() {
                ctx.ctm = saved
            }
        }

        // cm — concatenate matrix
        CGPDFOperatorTableSetCallback(operatorTable, "cm") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<ScanResult>.fromOpaque(info).takeUnretainedValue()
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
            let ctx = Unmanaged<ScanResult>.fromOpaque(info).takeUnretainedValue()

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
                   let cgImage = ImageExtractor.extractCGImage(from: pdfStream, dict: dict) {
                    ctx.images.append(ExtractedImage(cgImage: cgImage, rect: normalizedRect))
                }
            } else if subtypeStr == "Form" {
                // Form XObjects may contain images, diagrams, or complex compositions.
                // Skip only truly full-page forms (backgrounds, watermarks, templates)
                let isFullPage = normalizedRect.width > ctx.pageBounds.width * 0.9 &&
                                 normalizedRect.height > ctx.pageBounds.height * 0.9
                if !isFullPage {
                    ctx.imageRects.append(normalizedRect)
                }
            }
        }

        // IMPORTANT: CGPDFScannerScan is synchronous. passUnretained is safe here
        // because withExtendedLifetime keeps `context` alive until the scan completes.
        // Do NOT make this async without switching to passRetained/takeRetainedValue.
        let contentStream = CGPDFContentStreamCreateWithPage(cgPage)
        let opaqueCtx = Unmanaged.passUnretained(context).toOpaque()
        let scanner = CGPDFScannerCreate(contentStream, operatorTable, opaqueCtx)

        _ = withExtendedLifetime(context) {
            CGPDFScannerScan(scanner)
        }
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(contentStream)
        CGPDFOperatorTableRelease(operatorTable)

        return context
    }

    // MARK: - CGImage extraction

    /// Extract CGImage from a PDF image stream.
    static func extractCGImage(from stream: CGPDFStreamRef, dict: CGPDFDictionaryRef) -> CGImage? {
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
}
