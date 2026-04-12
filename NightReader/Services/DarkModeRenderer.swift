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
        // Reuse existing overlay if present (covers both fully-applied and
        // mid-fade-out states — see rapid toggle race fix below).
        if let invertView = pdfView.viewWithTag(invertTag) as? UIView,
           let tintView   = pdfView.viewWithTag(tintTag)   as? UIView {
            // Cancel any in-flight fade-out by removing pending animations
            // and re-targeting alpha=1. Without this, a fade-out completion
            // would later removeFromSuperview() the views we just "kept".
            invertView.layer.removeAllAnimations()
            tintView.layer.removeAllAnimations()
            tintView.backgroundColor = theme.tintUIColor

            let restore = {
                invertView.alpha = 1
                tintView.alpha = 1
            }
            if animated {
                UIView.animate(
                    withDuration: toggleDuration,
                    delay: 0,
                    options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState],
                    animations: restore
                )
            } else {
                restore()
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
            options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            invertView.alpha = 1
            tintView.alpha = 1
        }
    }

    static func removeDarkMode(from pdfView: PDFView, animated: Bool = true) {
        let invertView = pdfView.viewWithTag(invertTag)
        let tintView = pdfView.viewWithTag(tintTag)

        guard invertView != nil || tintView != nil else { return }

        guard animated else {
            invertView?.removeFromSuperview()
            tintView?.removeFromSuperview()
            return
        }

        UIView.animate(
            withDuration: toggleDuration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState],
            animations: {
                invertView?.alpha = 0
                tintView?.alpha = 0
            },
            completion: { finished in
                // Only remove if the fade-out actually completed AND nothing
                // else re-applied dark mode to the same views. Without this
                // guard, a rapid simple→off→simple sequence could orphan the
                // .simple state with no overlay.
                guard finished else { return }
                if let v = invertView, v.alpha == 0 { v.removeFromSuperview() }
                if let v = tintView,   v.alpha == 0 { v.removeFromSuperview() }
            }
        )
    }

    /// Updates the multiply tint color when the user changes theme while
    /// dark mode is already active. Called from ReaderViewModel.setTheme.
    /// No-op if dark mode is not currently applied.
    static func updateTint(on pdfView: PDFView, theme: Theme) {
        guard let tintView = pdfView.viewWithTag(tintTag) else { return }
        tintView.backgroundColor = theme.tintUIColor
    }
}
