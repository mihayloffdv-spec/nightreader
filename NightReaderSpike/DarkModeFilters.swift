import UIKit
import CoreImage
import PDFKit

enum DarkModeStyle: String, CaseIterable, Identifiable {
    case off = "Off"
    case simple = "Simple"
    case smart = "Smart"

    var id: String { rawValue }
}

// MARK: - Approach E helpers

struct DarkModeFilters {

    private static let invertTag = 99887
    private static let tintTag = 99888

    // MARK: - Approach E: Compositing filter overlays (iOS-compatible)
    // Two separate views with compositingFilter on their own layer:
    // 1. White view with "differenceBlendMode" → inverts colors below
    // 2. Warm cream view with "multiplyBlendMode" → tints the inverted result

    static func applySimpleDarkMode(to pdfView: PDFView) {
        guard pdfView.viewWithTag(invertTag) == nil else { return }

        // Inversion layer: white + difference = invert
        let invertView = UIView(frame: pdfView.bounds)
        invertView.tag = invertTag
        invertView.isUserInteractionEnabled = false
        invertView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        invertView.backgroundColor = .white
        invertView.layer.compositingFilter = "differenceBlendMode"
        pdfView.addSubview(invertView)

        // Warm tint layer: cream + multiply = warm tint
        let tintView = UIView(frame: pdfView.bounds)
        tintView.tag = tintTag
        tintView.isUserInteractionEnabled = false
        tintView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tintView.backgroundColor = UIColor(red: 1.0, green: 0.94, blue: 0.83, alpha: 1.0)
        tintView.layer.compositingFilter = "multiplyBlendMode"
        pdfView.addSubview(tintView)
    }

    static func removeSimpleDarkMode(from pdfView: PDFView) {
        pdfView.viewWithTag(invertTag)?.removeFromSuperview()
        pdfView.viewWithTag(tintTag)?.removeFromSuperview()
    }

    // MARK: - Approach D: Smart filter chain (used in DarkModePDFPage)

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func applySmartDarkModeFilter(to image: CIImage) -> CIImage? {
        var result = image

        // 1. Invert colors
        guard let invertFilter = CIFilter(name: "CIColorInvert") else { return nil }
        invertFilter.setValue(result, forKey: kCIInputImageKey)
        guard let inverted = invertFilter.outputImage else { return nil }
        result = inverted

        // 2. Adjust brightness, contrast, saturation
        guard let adjustFilter = CIFilter(name: "CIColorControls") else { return nil }
        adjustFilter.setValue(result, forKey: kCIInputImageKey)
        adjustFilter.setValue(-0.1, forKey: kCIInputBrightnessKey)
        adjustFilter.setValue(0.85, forKey: kCIInputContrastKey)
        adjustFilter.setValue(-0.1, forKey: kCIInputSaturationKey)
        guard let adjusted = adjustFilter.outputImage else { return nil }
        result = adjusted

        // 3. Warm shift via CITemperatureAndTint
        guard let tempFilter = CIFilter(name: "CITemperatureAndTint") else { return nil }
        tempFilter.setValue(result, forKey: kCIInputImageKey)
        tempFilter.setValue(CIVector(x: 4000, y: 0), forKey: "inputNeutral")
        tempFilter.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
        guard let warmed = tempFilter.outputImage else { return nil }

        return warmed
    }

    static func processImage(_ cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        guard let processed = applySmartDarkModeFilter(to: ciImage) else { return nil }
        return ciContext.createCGImage(processed, from: processed.extent)
    }
}
