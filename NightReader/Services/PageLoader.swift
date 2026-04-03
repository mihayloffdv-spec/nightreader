import PDFKit

// MARK: - Page Loader
//
// Shared page extraction service used by both ReaderModeView and DayModeReadingView.
// Handles: cache lookup → PDF extraction → cross-page paragraph joining.
//
// ┌──────────────┐     ┌─────────────┐     ┌───────────┐
// │ ReaderModeView│────▶│ PageLoader  │────▶│ BlockCache│
// │ DayModeReading│────▶│             │     └───────────┘
// └──────────────┘     │ extractPage │
//                      │ joinCrossPage│
//                      └──────┬──────┘
//                             │
//                      ┌──────▼──────┐
//                      │PDFContent-  │
//                      │Extractor    │
//                      └─────────────┘

enum PageLoader {

    /// Serial queue for thread-safe PDF access (CGPDFPage is not thread-safe).
    nonisolated(unsafe) static let extractionQueue = DispatchQueue(
        label: "com.nightreader.extraction",
        qos: .userInitiated
    )

    /// Extract blocks for a page. Checks cache first, then extracts from PDF.
    /// Calls completion on main queue with the extracted blocks.
    static func extractPage(
        _ pageIndex: Int,
        from document: PDFDocument,
        contentWidth: CGFloat,
        loadingPages: inout Set<Int>,
        blocksByPage: inout [Int: [ContentBlock]]
    ) -> Bool {
        guard !loadingPages.contains(pageIndex),
              blocksByPage[pageIndex] == nil else { return false }

        // Check cache first
        if let cached = BlockCache.shared.blocks(forPage: pageIndex, width: contentWidth) {
            blocksByPage[pageIndex] = cached
            return false // no async work needed
        }

        loadingPages.insert(pageIndex)
        return true // caller should dispatch async extraction
    }

    /// Perform the actual extraction on extractionQueue. Call from Task.detached or similar.
    static func performExtraction(
        pageIndex: Int,
        document: PDFDocument,
        contentWidth: CGFloat,
        completion: @escaping ([ContentBlock]) -> Void
    ) {
        extractionQueue.async {
            guard let page = document.page(at: pageIndex) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let blocks = PDFContentExtractor.extractBlocks(from: page, pageWidth: contentWidth)
            BlockCache.shared.store(blocks, forPage: pageIndex, width: contentWidth)
            DispatchQueue.main.async { completion(blocks) }
        }
    }

    // MARK: - Cross-page paragraph joining

    /// When a paragraph spans two pages, merge the last text block of page N
    /// with the first text block of page N+1.
    static func joinCrossPageParagraphs(
        _ pageIndex: Int,
        blocksByPage: inout [Int: [ContentBlock]],
        joinedPairs: inout Set<Int>,
        screenWidth: CGFloat
    ) {
        // Try joining with previous page
        if pageIndex > 0 {
            tryJoin(endPage: pageIndex - 1, startPage: pageIndex,
                    blocksByPage: &blocksByPage, joinedPairs: &joinedPairs, screenWidth: screenWidth)
        }
        // Try joining with next page
        if let nextBlocks = blocksByPage[pageIndex + 1], !nextBlocks.isEmpty {
            tryJoin(endPage: pageIndex, startPage: pageIndex + 1,
                    blocksByPage: &blocksByPage, joinedPairs: &joinedPairs, screenWidth: screenWidth)
        }
    }

    private static func tryJoin(
        endPage: Int,
        startPage: Int,
        blocksByPage: inout [Int: [ContentBlock]],
        joinedPairs: inout Set<Int>,
        screenWidth: CGFloat
    ) {
        guard !joinedPairs.contains(endPage) else { return }

        guard var endBlocks = blocksByPage[endPage], !endBlocks.isEmpty,
              var startBlocks = blocksByPage[startPage], !startBlocks.isEmpty else { return }

        guard case .text(let tail) = endBlocks.last else { return }
        guard case .text(let head) = startBlocks.first else { return }

        let trimmedTail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHead = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTail.isEmpty, !trimmedHead.isEmpty else { return }

        let sentenceEnders: Set<Character> = [".", "!", "?", "»", "\"", "'", "…"]
        guard let lastChar = trimmedTail.last, !sentenceEnders.contains(lastChar) else { return }
        guard let firstChar = trimmedHead.first, firstChar.isLowercase else { return }

        let joined = trimmedTail + " " + trimmedHead
        endBlocks[endBlocks.count - 1] = .text(joined)
        startBlocks.removeFirst()

        blocksByPage[endPage] = endBlocks
        blocksByPage[startPage] = startBlocks
        joinedPairs.insert(endPage)

        BlockCache.shared.store(endBlocks, forPage: endPage, width: screenWidth)
        BlockCache.shared.store(startBlocks, forPage: startPage, width: screenWidth)
    }
}
