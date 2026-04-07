import SwiftUI
import PDFKit

// MARK: - Paged Content View
//
// Shared scroll+pagination infrastructure for ReaderModeView and DayModeReadingView.
// Handles: page loading, async extraction, caching, scroll position save/restore,
// debounced position updates, prefetching, and go-to-page navigation.
//
// Each caller provides:
//   - blockContent: how to render a ContentBlock (different styling per mode)
//   - header: optional header view (DayMode has chapter header)
//   - scrollViewID: string that forces rebuild on font changes

struct PagedContentView<BlockContent: View, Header: View>: View {
    let document: PDFDocument?
    let currentPageIndex: Int
    let savedBlockID: Int
    @Binding var goToPageIndex: Int?
    let onPageChange: (Int, Int) -> Void
    let onTap: () -> Void
    let scrollViewID: String
    let contentPadding: EdgeInsets
    let backgroundColor: Color
    let progressTint: Color
    @ViewBuilder let header: () -> Header
    @ViewBuilder let blockContent: (ContentBlock, CGFloat) -> BlockContent

    @State private var pages: [Int] = []
    @State private var blocksByPage: [Int: [ContentBlock]] = [:]
    @State private var loadingPages: Set<Int> = []
    @State private var isInitialScroll = true
    @State private var scrolledBlockID: Int?
    @State private var saveTask: Task<Void, Never>?
    @State private var joinedPairs: Set<Int> = []
    @State private var screenWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header()

                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(pages, id: \.self) { pageIndex in
                                pageSection(pageIndex: pageIndex, screenWidth: geo.size.width)
                            }
                        }
                        .padding(contentPadding)
                    }
                }
                .scrollPosition(id: $scrolledBlockID, anchor: .top)
                .id(scrollViewID)
                .onAppear {
                    screenWidth = geo.size.width
                    loadPages()
                    let targetID = savedBlockID > 0 ? savedBlockID : currentPageIndex * 10000
                    if targetID > 0 {
                        isInitialScroll = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollProxy.scrollTo(targetID, anchor: .top)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isInitialScroll = false
                            }
                        }
                    } else {
                        isInitialScroll = false
                    }
                }
                .onChange(of: scrolledBlockID) { _, newID in
                    guard !isInitialScroll, let blockID = newID else { return }
                    saveTask?.cancel()
                    saveTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        let pageIndex = blockID / 10000
                        onPageChange(pageIndex, blockID)
                    }
                }
                .onChange(of: goToPageIndex) { _, newValue in
                    if let page = newValue {
                        let targetID = page * 10000
                        withAnimation {
                            scrollProxy.scrollTo(targetID, anchor: .top)
                        }
                        goToPageIndex = nil
                    }
                }
            }
        }
        .background(backgroundColor)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: - Page Section

    @ViewBuilder
    private func pageSection(pageIndex: Int, screenWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let blocks = blocksByPage[pageIndex] {
                ForEach(Array(blocks.enumerated()), id: \.offset) { offset, block in
                    blockContent(block, screenWidth)
                        .id(pageIndex * 10000 + offset)
                }
            } else {
                ProgressView()
                    .tint(progressTint)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .onAppear {
                        extractPage(pageIndex, contentWidth: screenWidth)
                    }
            }
        }
        .onAppear {
            let next = pageIndex + 1
            if next < (document?.pageCount ?? 0), blocksByPage[next] == nil {
                extractPage(next, contentWidth: screenWidth)
            }
        }
    }

    // MARK: - Data Loading

    private func loadPages() {
        guard let doc = document else { return }
        pages = Array(0..<doc.pageCount)
    }

    private func extractPage(_ pageIndex: Int, contentWidth: CGFloat) {
        guard let doc = document else { return }
        let needsAsync = PageLoader.extractPage(
            pageIndex, from: doc, contentWidth: contentWidth,
            loadingPages: &loadingPages, blocksByPage: &blocksByPage
        )
        guard needsAsync else { return }

        PageLoader.performExtraction(pageIndex: pageIndex, document: doc, contentWidth: contentWidth) { blocks in
            blocksByPage[pageIndex] = blocks
            loadingPages.remove(pageIndex)
            PageLoader.joinCrossPageParagraphs(
                pageIndex, blocksByPage: &blocksByPage,
                joinedPairs: &joinedPairs, screenWidth: screenWidth
            )
        }
    }
}
