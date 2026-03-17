import SwiftUI
import PDFKit

struct ReaderModeView: View {
    let document: PDFDocument?
    let theme: Theme
    let fontSize: Double
    let fontFamily: ReaderFont
    let currentPageIndex: Int
    @Binding var goToPageIndex: Int?
    let onPageChange: (Int) -> Void
    let onTap: () -> Void

    @State private var pages: [Int] = []
    @State private var blocksByPage: [Int: [ContentBlock]] = [:]
    @State private var loadingPages: Set<Int> = []
    @State private var screenWidth: CGFloat = UIScreen.main.bounds.width
    @State private var isInitialScroll = true

    // Serial queue for thread-safe CGPDFPage access
    private static let extractionQueue = DispatchQueue(label: "com.nightreader.extraction", qos: .userInitiated)

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(pages, id: \.self) { pageIndex in
                            pageSection(pageIndex: pageIndex, screenWidth: geo.size.width)
                                .id(pageIndex)
                        }
                    }
                    // No horizontal padding here — text blocks handle their own padding,
                    // images extend to full screen width.
                    .padding(.vertical, 20)
                }
                // Force full rebuild when font size or family changes
                .id("\(fontSize)_\(fontFamily.rawValue)")
                .onAppear {
                    screenWidth = geo.size.width
                    loadPages()
                    // Scroll to current page
                    if currentPageIndex > 0 {
                        isInitialScroll = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollProxy.scrollTo(currentPageIndex, anchor: .top)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isInitialScroll = false
                            }
                        }
                    } else {
                        isInitialScroll = false
                    }
                }
                .onChange(of: goToPageIndex) { _, newValue in
                    if let page = newValue {
                        withAnimation {
                            scrollProxy.scrollTo(page, anchor: .top)
                        }
                        goToPageIndex = nil
                    }
                }
            }
        }
        .background(theme.bgColor)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: - Page section

    @ViewBuilder
    private func pageSection(pageIndex: Int, screenWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let blocks = blocksByPage[pageIndex] {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block, contentWidth: screenWidth)
                }
            } else {
                ProgressView()
                    .tint(theme.textColor)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .padding(.horizontal, 16)
                    .onAppear {
                        extractPage(pageIndex, contentWidth: screenWidth)
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
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            if !isInitialScroll {
                onPageChange(pageIndex)
            }
            // Prefetch next page
            let next = pageIndex + 1
            if next < (document?.pageCount ?? 0), blocksByPage[next] == nil {
                extractPage(next, contentWidth: screenWidth)
            }
        }
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func blockView(_ block: ContentBlock, contentWidth: CGFloat) -> some View {
        switch block {
        case .text(let content):
            Text(content)
                .font(.system(size: fontSize, weight: .regular, design: fontFamily.design))
                .lineSpacing(fontSize * 0.4)
                .foregroundStyle(theme.textColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, fontSize * 0.3)
                .padding(.horizontal, 16)

        case .heading(let content):
            Text(content)
                .font(.system(size: fontSize * 1.3, weight: .bold, design: fontFamily.design))
                .lineSpacing(fontSize * 0.3)
                .foregroundStyle(theme.textColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.horizontal, 16)

        case .image(let image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 4))

        case .snapshot(let image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
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
            #if DEBUG
            print("[ReaderMode] Page \(pageIndex): loaded from cache (\(cached.count) blocks)")
            #endif
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
