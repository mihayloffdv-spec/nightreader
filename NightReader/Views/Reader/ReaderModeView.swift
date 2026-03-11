import SwiftUI
import PDFKit

struct ReaderModeView: View {
    let document: PDFDocument?
    let theme: Theme
    let fontSize: Double
    let currentPageIndex: Int
    let onPageChange: (Int) -> Void
    let onTap: () -> Void

    @State private var pages: [Int] = []
    @State private var blocksByPage: [Int: [ContentBlock]] = [:]
    @State private var loadingPages: Set<Int> = []
    @State private var screenWidth: CGFloat = UIScreen.main.bounds.width

    // Serial queue for thread-safe CGPDFPage access
    private static let extractionQueue = DispatchQueue(label: "com.nightreader.extraction", qos: .userInitiated)

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(pages, id: \.self) { pageIndex in
                            pageSection(pageIndex: pageIndex, contentWidth: geo.size.width - 32)
                                .id(pageIndex)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .onAppear {
                    screenWidth = geo.size.width
                    loadPages()
                    // Scroll to current page
                    if currentPageIndex > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollProxy.scrollTo(currentPageIndex, anchor: .top)
                        }
                    }
                }
            }
        }
        .background(theme.bgColor)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onChange(of: fontSize) {
            // Clear extracted blocks so pages re-render with new font size
            blocksByPage.removeAll()
            loadingPages.removeAll()
        }
    }

    // MARK: - Page section

    @ViewBuilder
    private func pageSection(pageIndex: Int, contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let blocks = blocksByPage[pageIndex] {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block, contentWidth: contentWidth)
                }
            } else {
                ProgressView()
                    .tint(theme.textColor)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .onAppear {
                        extractPage(pageIndex, contentWidth: contentWidth)
                    }
            }

            // Page divider
            if pageIndex < (document?.pageCount ?? 1) - 1 {
                HStack {
                    Rectangle().frame(height: 0.5).opacity(0.2)
                    Text("Page \(pageIndex + 2)")
                        .font(.caption2)
                        .opacity(0.4)
                    Rectangle().frame(height: 0.5).opacity(0.2)
                }
                .foregroundStyle(theme.textColor)
                .padding(.vertical, 16)
            }
        }
        .onAppear {
            onPageChange(pageIndex)
            // Prefetch next page
            let next = pageIndex + 1
            if next < (document?.pageCount ?? 0), blocksByPage[next] == nil {
                extractPage(next, contentWidth: contentWidth)
            }
        }
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func blockView(_ block: ContentBlock, contentWidth: CGFloat) -> some View {
        switch block {
        case .text(let content):
            Text(content)
                .font(.system(size: fontSize, weight: .regular, design: .serif))
                .lineSpacing(fontSize * 0.5)
                .foregroundStyle(theme.textColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .image(let image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: contentWidth)
                .clipShape(RoundedRectangle(cornerRadius: 4))

        case .snapshot(let image):
            let aspect = image.size.height / image.size.width
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth, height: contentWidth * aspect)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Data loading

    private func loadPages() {
        guard let doc = document else { return }
        pages = Array(0..<doc.pageCount)
    }

    private func extractPage(_ pageIndex: Int, contentWidth: CGFloat) {
        guard let doc = document,
              !loadingPages.contains(pageIndex),
              blocksByPage[pageIndex] == nil else { return }

        // Check cache first
        if let cached = BlockCache.shared.blocks(forPage: pageIndex, width: contentWidth) {
            blocksByPage[pageIndex] = cached
            return
        }

        loadingPages.insert(pageIndex)

        // CGPDFPage is not thread-safe — serialize all PDF access on a single queue
        Self.extractionQueue.async {
            guard let page = doc.page(at: pageIndex) else {
                DispatchQueue.main.async { loadingPages.remove(pageIndex) }
                return
            }
            let blocks = PDFContentExtractor.extractBlocks(from: page, pageWidth: contentWidth)
            BlockCache.shared.store(blocks, forPage: pageIndex, width: contentWidth)
            DispatchQueue.main.async {
                blocksByPage[pageIndex] = blocks
                loadingPages.remove(pageIndex)
            }
        }
    }
}
