import PDFKit
import UIKit

// MARK: - PDFContentProvider
//
// Adapts existing PDFContentExtractor to the BookContentProvider protocol.
// All heavy extraction logic stays in PDFContentExtractor — this is a thin wrapper.
//
//  ┌──────────────────────────────────────────────┐
//  │  PDFContentProvider                           │
//  │                                              │
//  │  init(url:) — opens PDFDocument              │
//  │                                              │
//  │  contentBlocks(forPage:)                     │
//  │    → PDFContentExtractor.extractBlocks()     │
//  │    → wrap each ContentBlock as PositionedBlock│
//  │      (id = "pdf-\(pageIndex)-\(i)", offsets=0)│
//  │                                              │
//  │  plainText(forPage:)                         │
//  │    → PDFPage.string + whitespace normalize   │
//  └──────────────────────────────────────────────┘

final class PDFContentProvider: BookContentProvider {
    private let document: PDFDocument

    let format: BookFormat = .pdf

    var pageCount: Int { document.pageCount }

    var title: String? {
        document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
    }

    var author: String? {
        document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
    }

    var cover: UIImage? { nil }  // PDF cover generated from first page by LibraryViewModel

    var outline: [Chapter] { [] }  // PDFContentProvider returns no outline;
                                   // ReaderViewModel uses ChapterDetector for PDF

    init(url: URL) throws {
        guard let doc = PDFDocument(url: url) else {
            throw PDFContentProviderError.unreadable(url)
        }
        self.document = doc
    }

    /// Access the underlying PDFDocument for features that need it directly
    /// (e.g. search, dark mode renderer, ChapterDetector).
    var pdfDocument: PDFDocument { document }

    // MARK: - Protocol conformance

    func contentBlocks(forPage index: Int) async throws -> [PositionedBlock] {
        guard let page = document.page(at: index) else { return [] }
        let blocks = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // pageWidth 0 → PDFContentExtractor uses full page width
                let extracted = PDFContentExtractor.extractBlocks(from: page, pageWidth: 0)
                continuation.resume(returning: extracted)
            }
        }
        return blocks.enumerated().map { i, block in
            PositionedBlock(
                id: "pdf-\(index)-\(i)",
                startCharOffset: 0,
                endCharOffset: 0,
                content: block
            )
        }
    }

    func plainText(forPage index: Int) async throws -> String {
        guard let page = document.page(at: index) else { return "" }
        let raw = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: page.string ?? "")
            }
        }
        return Self.normalizeWhitespace(raw)
    }

    // MARK: - Helpers

    /// Collapse runs of whitespace to single space, strip leading/trailing.
    static func normalizeWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Error

enum PDFContentProviderError: Error, LocalizedError {
    case unreadable(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            return "Не удалось открыть PDF: \(url.lastPathComponent)"
        }
    }
}
