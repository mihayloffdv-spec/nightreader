import PDFKit

// MARK: - Chapter

struct Chapter: Identifiable {
    let id: Int          // 0-based index
    let title: String
    let pageIndex: Int   // First page (PDF) or spine/section index (EPUB/FB2)
    let level: Int       // 0 = top-level, 1 = sub-chapter
    let source: Source

    /// Stable hash of first 200 chars of chapter text.
    /// Survives chapter reindexing (heuristic changes, outline updates).
    var contentHash: String?

    enum Source {
        case pdfOutline    // From embedded PDF TOC
        case autoDetected  // From heading detection
        case formatNative  // From EPUB spine / FB2 section metadata
    }

    /// Compute content hash from PDF document. Used by PDFContentProvider only.
    static func computeHash(pageIndex: Int, document: PDFDocument) -> String {
        let text = document.page(at: pageIndex)?.string ?? ""
        let prefix = String(text.prefix(200))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
        var hash: UInt64 = 5381
        for byte in prefix.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    /// Compute content hash from plain text. Used by EPUB/FB2 providers.
    static func computeHash(fromText text: String) -> String {
        let prefix = String(text.prefix(200))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
        var hash: UInt64 = 5381
        for byte in prefix.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}
