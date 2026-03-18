import PDFKit
import UIKit
import CoreGraphics

// MARK: - Page Renderer
//
// Renders PDF page regions and full pages to UIImage.
//
// ┌────────────────────────────────────┐
// │         PageRenderer               │
// │                                    │
// │  renderRegion(page, region, width) │
// │  renderFullPage(page, width)       │
// │  scaleImageToWidth(cgImage, width) │
// └────────────────────────────────────┘

enum PageRenderer {

    /// Scale a CGImage to a target width (points), preserving aspect ratio.
    /// Produces a @2x UIImage for Retina displays.
    static func scaleImageToWidth(_ cgImage: CGImage, targetWidth: CGFloat) -> UIImage {
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let scale: CGFloat = 2.0 // Retina
        let aspectRatio = srcH / max(srcW, 1)
        let targetH = targetWidth * aspectRatio

        let pixelW = Int(targetWidth * scale)
        let pixelH = Int(targetH * scale)

        // If the source is already close to target size, skip re-rendering
        if abs(srcW - CGFloat(pixelW)) < 4 && abs(srcH - CGFloat(pixelH)) < 4 {
            return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetWidth, height: targetH))
        return renderer.image { ctx in
            let drawRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetH)
            UIImage(cgImage: cgImage).draw(in: drawRect)
        }
    }

    /// Render a specific region of a PDF page to a UIImage.
    static func renderRegion(of page: PDFPage, region: CGRect, fitWidth: CGFloat) -> UIImage? {
        guard let cgPage = page.pageRef,
              region.width > 0 && region.height > 0,
              region.width.isFinite && region.height.isFinite else { return nil }

        // Scale so the REGION fills fitWidth (not the whole page)
        let scaleFactor = fitWidth / region.width
        let outputSize = CGSize(
            width: fitWidth,
            height: region.height * scaleFactor
        )
        // Use 2x scale, but reduce if the resulting bitmap would be too large
        var scale: CGFloat = 2.0
        while scale > 0.5 {
            let pw = Int(ceil(outputSize.width * scale))
            let ph = Int(ceil(outputSize.height * scale))
            if pw > 0 && ph > 0 && pw <= 8192 && ph <= 8192 { break }
            scale *= 0.5
        }

        let pixelW = Int(ceil(outputSize.width * scale))
        let pixelH = Int(ceil(outputSize.height * scale))
        guard pixelW > 0, pixelH > 0 else { return nil }

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
        // Translate FIRST so region.origin maps to (0,0), THEN draw.
        // No clip needed — the context is already sized to the region.
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
