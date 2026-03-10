import UIKit
import PDFKit
import CoreImage

class DarkModePDFPage: PDFPage {

    private let originalPage: PDFPage
    private let theme: Theme
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(wrapping page: PDFPage, theme: Theme = .midnight) {
        self.originalPage = page
        self.theme = theme
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
        guard let processed = applyFilterChain(to: ciImage),
              let outputCGImage = Self.ciContext.createCGImage(processed, from: processed.extent) else {
            originalPage.draw(with: box, to: context)
            return
        }

        // 3. Draw processed result
        context.saveGState()
        context.draw(outputCGImage, in: bounds)
        context.restoreGState()
    }

    private func applyFilterChain(to image: CIImage) -> CIImage? {
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

        // Apply theme tint via CIColorMatrix
        let tintColor = theme.tintUIColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        tintColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        guard let matrixFilter = CIFilter(name: "CIColorMatrix") else { return nil }
        matrixFilter.setValue(result, forKey: kCIInputImageKey)
        matrixFilter.setValue(CIVector(x: r, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrixFilter.setValue(CIVector(x: 0, y: g, z: 0, w: 0), forKey: "inputGVector")
        matrixFilter.setValue(CIVector(x: 0, y: 0, z: b, w: 0), forKey: "inputBVector")
        guard let tinted = matrixFilter.outputImage else { return nil }

        return tinted
    }
}
