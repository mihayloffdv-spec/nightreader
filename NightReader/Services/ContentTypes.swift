import PDFKit
import UIKit

// MARK: - Content block types

enum ContentBlock {
    case text(String)
    case heading(String)   // Detected heading (larger font size in PDF)
    case richText(NSAttributedString) // Formatted text with bold/italic preserved
    case image(UIImage)    // Extracted raster image from PDF
    case snapshot(UIImage)  // Rendered region snapshot (tables, diagrams, etc.)
}

// MARK: - Positioned block
//
// Wraps ContentBlock with character-offset anchoring for EPUB/FB2.
// PDF providers populate id only (offsets are 0); EPUB/FB2 providers populate all fields.
//
//   id = "\(pageIndex)-\(startCharOffset)" — stable ScrollViewReader anchor
//   startCharOffset / endCharOffset — UTF-16 code unit offsets into plainText(forPage:) output

struct PositionedBlock {
    var id: String
    var startCharOffset: Int
    var endCharOffset: Int   // exclusive
    var content: ContentBlock
}

// MARK: - Extracted image with position

struct ExtractedImage {
    let cgImage: CGImage
    let rect: CGRect  // Position in PDF page coordinates
}

// MARK: - Block cache

final class BlockCache {
    static let shared = BlockCache()

    private let cache = NSCache<NSString, CachedBlocks>()

    private init() {
        cache.countLimit = 30  // ~30 pages
        cache.totalCostLimit = 60 * 1024 * 1024  // ~60MB

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    func blocks(forPage pageIndex: Int, width: CGFloat) -> [ContentBlock]? {
        let key = "\(pageIndex)_\(Int(width.rounded()))" as NSString
        return cache.object(forKey: key)?.blocks
    }

    func clearAll() {
        cache.removeAllObjects()
    }

    func store(_ blocks: [ContentBlock], forPage pageIndex: Int, width: CGFloat) {
        let key = "\(pageIndex)_\(Int(width.rounded()))" as NSString
        let cost = blocks.reduce(0) { sum, block in
            switch block {
            case .text, .heading, .richText: return sum + 256
            case .image(let img), .snapshot(let img):
                let bytes = Int(img.size.width * img.scale * img.size.height * img.scale * 4)
                return sum + bytes
            }
        }
        cache.setObject(CachedBlocks(blocks: blocks), forKey: key, cost: cost)
    }

    func invalidate() {
        cache.removeAllObjects()
    }
}

private class CachedBlocks: NSObject {
    let blocks: [ContentBlock]
    init(blocks: [ContentBlock]) { self.blocks = blocks }
}

// MARK: - Shared helpers

/// Check if a trimmed string is garbage (very short, no letters).
func isGarbageText(_ trimmed: String) -> Bool {
    trimmed.count <= 3 && trimmed.allSatisfy({ !$0.isLetter || $0.isWhitespace })
}

/// Classify a single paragraph as heading or body text.
func classifyBlock(_ trimmed: String, headingTexts: Set<String>) -> ContentBlock? {
    guard !trimmed.isEmpty else { return nil }
    if isGarbageText(trimmed) { return nil }

    if trimmed.count >= 5 && trimmed.count < 120 && headingTexts.contains(where: { heading in
        heading.count >= 5 && (trimmed.hasPrefix(heading) || heading.hasPrefix(trimmed)) &&
        Double(min(trimmed.count, heading.count)) / Double(max(trimmed.count, heading.count)) > 0.5
    }) {
        return .heading(trimmed)
    }
    return .text(trimmed)
}
