import UIKit

// MARK: - Snapshot cache (NSCache keyed by CGImage pointer)
//
// SwiftUI re-evaluates views on every scroll frame. Without a cache,
// isMonochromeText() would run on every frame. We key by the CGImage pointer
// so each unique image is analyzed once.

enum SnapshotCache {
    private static let cache: NSCache<NSNumber, NSNumber> = {
        let c = NSCache<NSNumber, NSNumber>()
        c.countLimit = 60
        return c
    }()

    static func isMonochromeText(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let key = NSNumber(value: UInt(bitPattern: ObjectIdentifier(cgImage).hashValue))
        if let cached = cache.object(forKey: key) {
            return cached.boolValue
        }
        let result = SnapshotColorAnalyzer.isMonochromeText(image)
        cache.setObject(NSNumber(value: result), forKey: key)
        return result
    }
}

// MARK: - Snapshot Color Analyzer
//
// Determines whether a rendered page snapshot is "monochrome text" (dark text on
// a light background — safe to invert for dark mode) or "graphic content" (colored
// illustrations, covers, diagrams — should NOT be inverted).
//
// Used by ReaderModeView to decide whether to apply colorInvert + colorMultiply
// to snapshot blocks. Without this check, covers and graphic pages look like
// a cursed Instagram filter in dark mode.

enum SnapshotColorAnalyzer {

    /// Returns true if the snapshot looks like monochrome text on a light background.
    /// Uses a coarse grid sample to stay cheap (~16x16 = 256 pixels regardless of
    /// image size).
    static func isMonochromeText(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return false }

        // Sample a 16x16 grid of pixels across the image
        let samplesPerSide = 16
        let totalSamples = samplesPerSide * samplesPerSide

        // Render into a 1-byte-per-channel RGBA buffer at the sample grid size
        let bytesPerPixel = 4
        let bytesPerRow = samplesPerSide * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: samplesPerSide * samplesPerSide * bytesPerPixel)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: samplesPerSide,
            height: samplesPerSide,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: samplesPerSide, height: samplesPerSide))

        // Analyze sampled pixels
        var lightPixels = 0      // near-white
        var darkPixels = 0       // near-black
        var colorfulPixels = 0   // high saturation

        for i in 0..<totalSamples {
            let r = Int(pixels[i * bytesPerPixel])
            let g = Int(pixels[i * bytesPerPixel + 1])
            let b = Int(pixels[i * bytesPerPixel + 2])

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let range = maxC - minC

            // Saturation-ish: how far from grayscale
            // If the difference between channels is large, pixel is "colorful"
            if range > 40 {
                colorfulPixels += 1
            }

            // Light = all channels bright
            if r > 200 && g > 200 && b > 200 {
                lightPixels += 1
            }
            // Dark = all channels dim
            else if r < 60 && g < 60 && b < 60 {
                darkPixels += 1
            }
        }

        let lightFraction = Double(lightPixels) / Double(totalSamples)
        let colorfulFraction = Double(colorfulPixels) / Double(totalSamples)

        // Heuristic:
        // - A real text page has ~60%+ light (white paper) and <5% colorful
        // - A cover or graphic has <40% light OR >10% colorful
        let isLightBackground = lightFraction > 0.55
        let isNotColorful = colorfulFraction < 0.08

        return isLightBackground && isNotColorful
    }
}
