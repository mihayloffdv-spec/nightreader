import UIKit
import PDFKit

struct DarkModeRenderer {

    private static let invertTag = 88001
    private static let tintTag = 88002

    /// Animation duration for dark mode fade in/out. The defining UX moment of the app.
    /// Must feel like a dimmer, not a switch. 0.25s is the sweet spot — fast enough
    /// to not feel laggy, slow enough that the eye can perceive the transition.
    private static let toggleDuration: TimeInterval = 0.25

    static func applyDarkMode(to pdfView: PDFView, theme: Theme, animated: Bool = true) {
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
        invertView.alpha = animated ? 0 : 1
        pdfView.addSubview(invertView)

        // Layer 2: Theme tint via multiply blend
        let tintView = UIView(frame: pdfView.bounds)
        tintView.tag = tintTag
        tintView.isUserInteractionEnabled = false
        tintView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tintView.backgroundColor = theme.tintUIColor
        tintView.layer.compositingFilter = "multiplyBlendMode"
        tintView.alpha = animated ? 0 : 1
        pdfView.addSubview(tintView)

        guard animated else { return }
        UIView.animate(
            withDuration: toggleDuration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            invertView.alpha = 1
            tintView.alpha = 1
        }
    }

    static func removeDarkMode(from pdfView: PDFView, animated: Bool = true) {
        let invertView = pdfView.viewWithTag(invertTag)
        let tintView = pdfView.viewWithTag(tintTag)

        guard animated, invertView != nil || tintView != nil else {
            invertView?.removeFromSuperview()
            tintView?.removeFromSuperview()
            return
        }

        UIView.animate(
            withDuration: toggleDuration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: {
                invertView?.alpha = 0
                tintView?.alpha = 0
            },
            completion: { _ in
                invertView?.removeFromSuperview()
                tintView?.removeFromSuperview()
            }
        )
    }
}
