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

        // 1. Create offscreen bitmap
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

        // 2. Fill white background and render original page
        offscreenContext.setFillColor(UIColor.white.cgColor)
        offscreenContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        offscreenContext.scaleBy(x: scale, y: scale)
        originalPage.draw(with: box, to: offscreenContext)

        guard let originalImage = offscreenContext.makeImage() else {
            originalPage.draw(with: box, to: context)
            return
        }

        // 3. Apply Core Image filters
        guard let outputCGImage = DarkModeFilters.processImage(originalImage) else {
            originalPage.draw(with: box, to: context)
            return
        }

        // 4. Draw processed result to main context
        context.saveGState()
        context.draw(outputCGImage, in: bounds)
        context.restoreGState()
    }
}
