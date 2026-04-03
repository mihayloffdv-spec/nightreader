import SwiftUI
import PDFKit

// MARK: - Day Mode Reading View (Deep Forest "Clean Sanctuary" design)
//
// Light reading mode. Warm cream background, dark text, editorial layout.
// Chapter header with title + author info, then reflowed text.
//
// ┌─────────────────────────────────────────┐
// │  ≡  Reading Sanctuary            ⚙     │  ← top bar (green accent)
// │                                         │
// │  CHAPTER IV                             │
// │  The Silent Growth                      │
// │  of Moss                                │
// │  ───────────────────                    │
// │  ○ Elias Thorne                         │
// │    12 min read · Sanctuary Archives     │
// │  ───────────────────                    │
// │                                         │
// │  In the deep, shaded corridors of the   │
// │  subterranean conservatory, time        │
// │  behaves differently...                 │
// │                                         │
// └─────────────────────────────────────────┘

struct DayModeReadingView: View {
    let document: PDFDocument?
    let theme: Theme
    let book: Book
    let fontSize: Double
    let currentPageIndex: Int
    let savedBlockID: Int
    @Binding var goToPageIndex: Int?
    let chapters: [Chapter]
    let currentChapter: Chapter?
    let onPageChange: (Int, Int) -> Void
    let onTap: () -> Void
    let onAIAction: (AIActionType, String) -> Void
    let onOpenSettings: () -> Void

    @State private var pages: [Int] = []
    @State private var blocksByPage: [Int: [ContentBlock]] = [:]
    @State private var loadingPages: Set<Int> = []
    @State private var isInitialScroll = true
    @State private var scrolledBlockID: Int?
    @State private var saveTask: Task<Void, Never>?
    @State private var joinedPairs: Set<Int> = []

    var body: some View {
        ZStack {
            theme.dayBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                dayTopBar

                // Content
                GeometryReader { geo in
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                // Chapter header (first page only)
                                chapterHeader
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 24)

                                // Text content
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(pages, id: \.self) { pageIndex in
                                        dayPageSection(pageIndex: pageIndex, screenWidth: geo.size.width)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.bottom, 40)
                            }
                        }
                        .scrollPosition(id: $scrolledBlockID, anchor: .top)
                        .id("\(fontSize)")
                        .onAppear {
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
                                withAnimation {
                                    scrollProxy.scrollTo(page * 10000, anchor: .top)
                                }
                                goToPageIndex = nil
                            }
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: - Top Bar

    private var dayTopBar: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .font(.title3)
                .foregroundStyle(theme.dayTextSecondary)

            Text(theme.dayTitle)
                .font(theme.headlineFont(size: 18))
                .foregroundStyle(theme.dayAccent)

            Spacer()

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(theme.dayTextSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Chapter Header

    private var chapterHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Chapter label
            if let chapter = currentChapter {
                Text("CHAPTER \(romanNumeral(chapter.id + 1))")
                    .font(theme.captionFont(size: 12))
                    .foregroundStyle(theme.dayTextSecondary)
                    .kerning(3)
                    .padding(.top, 24)

                // Chapter title
                Text(chapter.title)
                    .font(theme.headlineFont(size: 32))
                    .foregroundStyle(theme.dayTextPrimary)
            } else {
                Text(book.title)
                    .font(theme.headlineFont(size: 32))
                    .foregroundStyle(theme.dayTextPrimary)
                    .padding(.top, 24)
            }

            // Divider
            Rectangle()
                .fill(theme.dayDivider)
                .frame(height: 1)

            // Author info
            HStack(spacing: 12) {
                // Author avatar placeholder (circle with initial)
                Circle()
                    .fill(theme.dayDivider)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String((book.author ?? "A").prefix(1)).uppercased())
                            .font(theme.labelFont(size: 16))
                            .foregroundStyle(theme.dayTextSecondary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(book.author ?? "Unknown Author")
                        .font(theme.labelFont(size: 15))
                        .foregroundStyle(theme.dayTextPrimary)

                    Text("\(estimatedReadTime) min read · Sanctuary Archives")
                        .font(theme.captionFont(size: 13))
                        .foregroundStyle(theme.dayTextSecondary)
                }
            }

            // Divider
            Rectangle()
                .fill(theme.dayDivider)
                .frame(height: 1)
        }
    }

    // MARK: - Page Section

    @ViewBuilder
    private func dayPageSection(pageIndex: Int, screenWidth: CGFloat) -> some View {
        if let blocks = blocksByPage[pageIndex] {
            ForEach(Array(blocks.enumerated()), id: \.offset) { offset, block in
                dayBlockView(block, contentWidth: screenWidth - 48)
                    .id(pageIndex * 10000 + offset)
            }
        } else {
            ProgressView()
                .tint(theme.dayAccent)
                .frame(maxWidth: .infinity, minHeight: 100)
                .onAppear {
                    extractPage(pageIndex, contentWidth: screenWidth - 48)
                }
        }
    }

    // MARK: - Block View

    @ViewBuilder
    private func dayBlockView(_ block: ContentBlock, contentWidth: CGFloat) -> some View {
        switch block {
        case .text(let content):
            Text(content)
                .font(.custom(theme.bodyFontName, size: fontSize))
                .foregroundStyle(theme.dayTextPrimary)
                .lineSpacing(fontSize * 0.45)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, fontSize * 0.3)

        case .heading(let content):
            Text(content)
                .font(theme.headlineFont(size: fontSize * 1.3))
                .foregroundStyle(theme.dayTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .padding(.bottom, 4)

        case .image(let image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.vertical, 8)

        case .snapshot(let image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.vertical, 8)
        }
    }

    // MARK: - Data Loading

    private func loadPages() {
        guard let doc = document else { return }
        pages = Array(0..<doc.pageCount)
    }

    private func extractPage(_ pageIndex: Int, contentWidth: CGFloat) {
        guard let doc = document,
              !loadingPages.contains(pageIndex),
              blocksByPage[pageIndex] == nil else { return }

        if let cached = BlockCache.shared.blocks(forPage: pageIndex, width: contentWidth) {
            blocksByPage[pageIndex] = cached
            return
        }

        loadingPages.insert(pageIndex)
        ReaderModeView.extractionQueue.async {
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

    // MARK: - Helpers

    private var estimatedReadTime: Int {
        let totalPages = document?.pageCount ?? 1
        return max(1, totalPages * 2) // rough estimate: 2 min per page
    }

    private func romanNumeral(_ n: Int) -> String {
        let values = [(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),
                      (100,"C"),(90,"XC"),(50,"L"),(40,"XL"),
                      (10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")]
        var result = ""
        var remaining = n
        for (value, numeral) in values {
            while remaining >= value {
                result += numeral
                remaining -= value
            }
        }
        return result
    }
}
