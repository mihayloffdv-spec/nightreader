import UIKit
import PDFKit

struct DarkModeRenderer {

    private static let invertTag = 88001
    private static let tintTag = 88002

    static func applyDarkMode(to pdfView: PDFView) {
        guard pdfView.viewWithTag(invertTag) == nil else { return }

        // Layer 1: Invert via difference blend
        let invertView = UIView(frame: pdfView.bounds)
        invertView.tag = invertTag
        invertView.isUserInteractionEnabled = false
        invertView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        invertView.backgroundColor = .white
        invertView.layer.compositingFilter = "differenceBlendMode"
        pdfView.addSubview(invertView)

        // Layer 2: Warm tint via multiply blend
        let tintView = UIView(frame: pdfView.bounds)
        tintView.tag = tintTag
        tintView.isUserInteractionEnabled = false
        tintView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tintView.backgroundColor = UIColor(red: 1.0, green: 0.94, blue: 0.83, alpha: 1.0)
        tintView.layer.compositingFilter = "multiplyBlendMode"
        pdfView.addSubview(tintView)
    }

    static func removeDarkMode(from pdfView: PDFView) {
        pdfView.viewWithTag(invertTag)?.removeFromSuperview()
        pdfView.viewWithTag(tintTag)?.removeFromSuperview()
    }
}
