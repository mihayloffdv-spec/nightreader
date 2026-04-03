import SwiftUI
import PDFKit

struct ReaderModeView: View {
    let document: PDFDocument?
    let theme: Theme
    let fontSize: Double
    let fontFamily: ReaderFont
    let currentPageIndex: Int
    let savedBlockID: Int
    @Binding var goToPageIndex: Int?
    let onPageChange: (Int, Int) -> Void  // (pageIndex, blockID)
    let onTap: () -> Void
    let onAIAction: (AIActionType, String) -> Void  // (action, selectedText)

    @State private var pages: [Int] = []
    @State private var blocksByPage: [Int: [ContentBlock]] = [:]
    @State private var loadingPages: Set<Int> = []
    @State private var screenWidth: CGFloat = 0
    @State private var isInitialScroll = true
    @State private var scrolledBlockID: Int?
    @State private var saveTask: Task<Void, Never>?
    @State private var joinedPairs: Set<Int> = []  // endPage values of already-joined pairs

    // Очередь для потокобезопасного доступа к CGPDFPage (PDFDocument НЕ потокобезопасен).
    // nonisolated(unsafe) потому что DispatchQueue сам по себе потокобезопасен,
    // а SwiftUI View наследует @MainActor изоляцию, откуда мы обращаемся из Task.detached.
    nonisolated(unsafe) static let extractionQueue = DispatchQueue(label: "com.nightreader.extraction", qos: .userInitiated)

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(pages, id: \.self) { pageIndex in
                            pageSection(pageIndex: pageIndex, screenWidth: geo.size.width)
                        }
                    }
                    // No horizontal padding here — text blocks handle their own padding,
                    // images extend to full screen width.
                    .padding(.vertical, 20)
                }
                .scrollPosition(id: $scrolledBlockID, anchor: .top)
                // Force full rebuild when font size or family changes
                .id("\(fontSize)_\(fontFamily.rawValue)")
                .onAppear {
                    screenWidth = geo.size.width
                    loadPages()
                    // Restore saved block-level position, fall back to page-level
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
                    // Debounce: save position at most once per 0.5s to avoid
                    // hammering SwiftData on every scroll frame
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
        .background(theme.bgColor)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: - Page section

    @ViewBuilder
    private func pageSection(pageIndex: Int, screenWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let blocks = blocksByPage[pageIndex] {
                ForEach(Array(blocks.enumerated()), id: \.offset) { offset, block in
                    blockView(block, contentWidth: screenWidth)
                        .id(pageIndex * 10000 + offset)
                }
            } else {
                ProgressView()
                    .tint(theme.textColor)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .padding(.horizontal, 24)
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
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
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
            ReaderTextBlock(
                text: content,
                style: .body,
                fontSize: fontSize,
                fontDesign: fontFamily.design,
                textColor: UIColor(theme.textColor),
                lineSpacing: fontSize * 0.15,
                onAIAction: onAIAction
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, fontSize * 0.15)
            .padding(.horizontal, 24)

        case .heading(let content):
            ReaderTextBlock(
                text: content,
                style: .heading,
                fontSize: fontSize * 1.3,
                fontDesign: fontFamily.design,
                textColor: UIColor(theme.textColor),
                lineSpacing: fontSize * 0.1,
                onAIAction: onAIAction
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.horizontal, 24)

        case .image(let image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth)
                .clipShape(RoundedRectangle(cornerRadius: 4))

        case .snapshot(let image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .colorInvert()
                .colorMultiply(theme.tintColor)
        }
    }

    // MARK: - Data loading

    private func loadPages() {
        guard let doc = document else { return }
        pages = Array(0..<doc.pageCount)
    }

    static func uiFont(size: CGFloat, design: Font.Design) -> UIFont {
        let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        switch design {
        case .serif:
            if let desc = base.withDesign(.serif) {
                return UIFont(descriptor: desc, size: size)
            }
        case .rounded:
            if let desc = base.withDesign(.rounded) {
                return UIFont(descriptor: desc, size: size)
            }
        default:
            break
        }
        return UIFont.systemFont(ofSize: size)
    }

    // MARK: - Cross-page paragraph joining

    /// When a paragraph spans two pages, merge the last text block of page N
    /// with the first text block of page N+1.
    private func joinCrossPageParagraphs(_ pageIndex: Int) {
        // Try joining with previous page
        if pageIndex > 0 {
            tryJoin(endPage: pageIndex - 1, startPage: pageIndex)
        }
        // Try joining with next page
        if let nextBlocks = blocksByPage[pageIndex + 1], !nextBlocks.isEmpty {
            tryJoin(endPage: pageIndex, startPage: pageIndex + 1)
        }
    }

    private func tryJoin(endPage: Int, startPage: Int) {
        // Prevent double-joining the same page pair
        guard !joinedPairs.contains(endPage) else { return }

        guard var endBlocks = blocksByPage[endPage], !endBlocks.isEmpty,
              var startBlocks = blocksByPage[startPage], !startBlocks.isEmpty else { return }

        // Last block of endPage must be .text
        guard case .text(let tail) = endBlocks.last else { return }
        // First block of startPage must be .text
        guard case .text(let head) = startBlocks.first else { return }

        let trimmedTail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHead = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTail.isEmpty, !trimmedHead.isEmpty else { return }

        // Check: tail doesn't end with sentence-ending punctuation AND head starts lowercase
        let sentenceEnders: Set<Character> = [".", "!", "?", "»", "\"", "'", "…"]
        guard let lastChar = trimmedTail.last, !sentenceEnders.contains(lastChar) else { return }
        guard let firstChar = trimmedHead.first, firstChar.isLowercase else { return }

        // Merge: append head to tail, remove head from startPage
        let joined = trimmedTail + " " + trimmedHead
        endBlocks[endBlocks.count - 1] = .text(joined)
        startBlocks.removeFirst()

        blocksByPage[endPage] = endBlocks
        blocksByPage[startPage] = startBlocks
        joinedPairs.insert(endPage)

        // Update cache so joined blocks survive page eviction/reload
        BlockCache.shared.store(endBlocks, forPage: endPage, width: screenWidth)
        BlockCache.shared.store(startBlocks, forPage: startPage, width: screenWidth)
    }

    // MARK: - Page extraction

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
                joinCrossPageParagraphs(pageIndex)
            }
        }
    }
}

// MARK: - Tap-through UITextView (passes single taps to parent for toolbar toggle)

private class ReaderTextView: UITextView {

    /// Callback for AI actions (explain/translate) from context menu.
    var onAIAction: ((AIActionType, String) -> Void)?

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Long press → always allow (starts text selection)
        if gestureRecognizer is UILongPressGestureRecognizer { return true }
        if let tap = gestureRecognizer as? UITapGestureRecognizer {
            // Double-tap → select word
            if tap.numberOfTapsRequired == 2 { return true }
            // Single tap → only if there's an active selection to deselect
            if tap.numberOfTapsRequired == 1 { return selectedRange.length > 0 }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    // Add "Explain" and "Translate" to the text selection context menu
    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)

        let explainAction = UIAction(
            title: AIActionType.explain.menuTitle,
            image: UIImage(systemName: AIActionType.explain.menuIcon)
        ) { [weak self] _ in
            guard let self, let text = self.selectedText, !text.isEmpty else { return }
            self.onAIAction?(.explain, text)
        }

        let translateAction = UIAction(
            title: AIActionType.translate.menuTitle,
            image: UIImage(systemName: AIActionType.translate.menuIcon)
        ) { [weak self] _ in
            guard let self, let text = self.selectedText, !text.isEmpty else { return }
            self.onAIAction?(.translate, text)
        }

        let aiMenu = UIMenu(title: "AI", image: UIImage(systemName: "sparkles"), children: [explainAction, translateAction])
        builder.insertChild(aiMenu, atStartOfMenu: .root)
    }

    /// Get the currently selected text.
    private var selectedText: String? {
        guard selectedRange.length > 0,
              let text = self.text,
              let range = Range(selectedRange, in: text) else { return nil }
        return String(text[range])
    }
}

// MARK: - Универсальный текстовый блок (body / heading)

private enum ReaderTextStyle {
    case body
    case heading
}

private struct ReaderTextBlock: UIViewRepresentable {
    let text: String
    let style: ReaderTextStyle
    let fontSize: CGFloat
    let fontDesign: Font.Design
    let textColor: UIColor
    let lineSpacing: CGFloat
    let onAIAction: (AIActionType, String) -> Void

    func makeUIView(context: Context) -> ReaderTextView {
        let tv = ReaderTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.backgroundColor = .clear
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.tintColor = UIColor.systemBlue.withAlphaComponent(0.6)
        tv.onAIAction = onAIAction
        return tv
    }

    func updateUIView(_ tv: ReaderTextView, context: Context) {
        let font: UIFont
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        switch style {
        case .body:
            font = ReaderModeView.uiFont(size: fontSize, design: fontDesign)
            paragraphStyle.alignment = .justified
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.hyphenationFactor = 0.7
            attributes[.kern] = fontSize * 0.01
        case .heading:
            let baseFont = ReaderModeView.uiFont(size: fontSize, design: fontDesign)
            let boldDesc = baseFont.fontDescriptor.withSymbolicTraits(.traitBold)
            font = boldDesc.map { UIFont(descriptor: $0, size: fontSize) }
                ?? UIFont.boldSystemFont(ofSize: fontSize)
            paragraphStyle.alignment = .natural
        }

        attributes[.font] = font

        let newText = NSAttributedString(string: text, attributes: attributes)
        if tv.attributedText != newText {
            tv.attributedText = newText
        }
        tv.onAIAction = onAIAction
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReaderTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}
