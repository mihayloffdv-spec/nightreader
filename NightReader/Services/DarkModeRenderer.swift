import UIKit
import PDFKit

struct DarkModeRenderer {

    private static let invertTag = 88001
    private static let tintTag = 88002

    static func applyDarkMode(to pdfView: PDFView, theme: Theme) {
        guard pdfView.viewWithTag(invertTag) == nil else {
            // Already applied — just update tint color
            if let tintView = pdfView.viewWithTag(tintTag) {
                tintView.backgroundColor = theme.tintUIColor
            }
            return
        }

        // Layer 1: Invert via difference blend
        let invertView = UIView(frame: pdfView.bounds)
        invertView.tag = invertTag
        invertView.isUserInteractionEnabled = false
        invertView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        invertView.backgroundColor = .white
        invertView.layer.compositingFilter = "differenceBlendMode"
        pdfView.addSubview(invertView)

        // Layer 2: Theme tint via multiply blend
        let tintView = UIView(frame: pdfView.bounds)
        tintView.tag = tintTag
        tintView.isUserInteractionEnabled = false
        tintView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tintView.backgroundColor = theme.tintUIColor
        tintView.layer.compositingFilter = "multiplyBlendMode"
        pdfView.addSubview(tintView)
    }

    static func removeDarkMode(from pdfView: PDFView) {
        pdfView.viewWithTag(invertTag)?.removeFromSuperview()
        pdfView.viewWithTag(tintTag)?.removeFromSuperview()
    }
}
