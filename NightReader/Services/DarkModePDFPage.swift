import UIKit
import PDFKit
import CoreImage

class DarkModePDFPage: PDFPage {

    private let originalPage: PDFPage
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(wrapping page: PDFPage) {
        self.originalPage = page
        super.init()
    }

    override var numberOfCharacters: Int {
        originalPage.numberOfCharacters
    }

    override func bounds(for box: PDFDisplayBox) -> CGRect {
        originalPage.bounds(for: box)
    }

    override var string: String? {
        originalPage.string
    }

    override func selection(for rect: CGRect) -> PDFSelection? {
        originalPage.selection(for: rect)
    }

    override func selection(from startPoint: CGPoint, to endPoint: CGPoint) -> PDFSelection? {
        originalPage.selection(from: startPoint, to: endPoint)
    }

    override func selection(for range: NSRange) -> PDFSelection? {
        originalPage.selection(for: range)
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        let bounds = self.bounds(for: box)
        let scale: CGFloat = 2.0

        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)

        guard width > 0, height > 0 else {
            originalPage.draw(with: box, to: context)
            return
        }

        // 1. Render original page to offscreen bitmap
        guard let offscreenContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            originalPage.draw(with: box, to: context)
            return
        }

        offscreenContext.setFillColor(UIColor.white.cgColor)
        offscreenContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        offscreenContext.scaleBy(x: scale, y: scale)
        originalPage.draw(with: box, to: offscreenContext)

        guard let originalImage = offscreenContext.makeImage() else {
            originalPage.draw(with: box, to: context)
            return
        }

        // 2. Apply CIFilter chain
        let ciImage = CIImage(cgImage: originalImage)
        guard let processed = Self.applyFilterChain(to: ciImage),
              let outputCGImage = Self.ciContext.createCGImage(processed, from: processed.extent) else {
            originalPage.draw(with: box, to: context)
            return
        }

        // 3. Draw processed result
        context.saveGState()
        context.draw(outputCGImage, in: bounds)
        context.restoreGState()
    }

    private static func applyFilterChain(to image: CIImage) -> CIImage? {
        var result = image

        // Invert colors
        guard let invertFilter = CIFilter(name: "CIColorInvert") else { return nil }
        invertFilter.setValue(result, forKey: kCIInputImageKey)
        guard let inverted = invertFilter.outputImage else { return nil }
        result = inverted

        // Adjust brightness, contrast, saturation
        guard let adjustFilter = CIFilter(name: "CIColorControls") else { return nil }
        adjustFilter.setValue(result, forKey: kCIInputImageKey)
        adjustFilter.setValue(-0.1, forKey: kCIInputBrightnessKey)
        adjustFilter.setValue(0.85, forKey: kCIInputContrastKey)
        adjustFilter.setValue(-0.1, forKey: kCIInputSaturationKey)
        guard let adjusted = adjustFilter.outputImage else { return nil }
        result = adjusted

        // Warm shift
        guard let tempFilter = CIFilter(name: "CITemperatureAndTint") else { return nil }
        tempFilter.setValue(result, forKey: kCIInputImageKey)
        tempFilter.setValue(CIVector(x: 4000, y: 0), forKey: "inputNeutral")
        tempFilter.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
        guard let warmed = tempFilter.outputImage else { return nil }

        return warmed
    }
}
