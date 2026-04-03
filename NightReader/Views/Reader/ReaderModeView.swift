import SwiftUI
import PDFKit

struct ReaderModeView: View {
    let document: PDFDocument?
    let theme: Theme
    let fontSize: Double
    let fontFamily: ReaderFont
    var customFontOverride: String? = nil
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

    // extractionQueue moved to shared PageLoader service.
    // Keep this accessor for backward compatibility with ReaderViewModel.loadDocument().
    nonisolated(unsafe) static var extractionQueue: DispatchQueue { PageLoader.extractionQueue }

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
                .id("\(fontSize)_\(fontFamily.rawValue)_\(customFontOverride ?? "")")
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
        .background(Color(hex: "#0e150e"))
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
                    .tint(Color(hex: "#ffb599"))
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .padding(.horizontal, 24)
                    .onAppear {
                        extractPage(pageIndex, contentWidth: screenWidth)
                    }
            }

            // Page divider — border-t border-outline-variant/10, minimal
            if pageIndex < (document?.pageCount ?? 1) - 1 {
                Rectangle()
                    .fill(Color(hex: "#444843").opacity(0.1))
                    .frame(height: 1)
                    .padding(.vertical, 32)
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

    // MARK: - Font resolution
    // User's font choice takes priority over theme default.
    // If user picked a custom font name (from Settings pills), use it.
    // If they picked a standard ReaderFont (serif/sans/rounded), use nil to fall back to system.

    private var resolvedBodyFont: String? {
        if let override = customFontOverride,
           UIFont(name: override, size: 17) != nil {
            return override
        }
        return theme.bodyFontName
    }

    private var resolvedHeadlineFont: String? {
        theme.headlineFontName
    }

    // MARK: - Block rendering
    //
    // CSS values from HTML mockup:
    // Body:   Noto Serif 18px, leading-[1.8]=32.4px, color #dde5d8, space-y-8=32px
    // Heading: Plus Jakarta Sans extrabold, tracking-tight, text-4xl=36px
    // Image:  aspect-[16/9], rounded-xl, shadow-2xl

    private let onSurface = UIColor(Color(hex: "#dde5d8"))
    private let primaryColor = Color(hex: "#ffb599")

    @ViewBuilder
    private func blockView(_ block: ContentBlock, contentWidth: CGFloat) -> some View {
        switch block {
        case .text(let content):
            // text-lg=18px, leading-[1.8], space-y-8=32px, color on-surface
            ReaderTextBlock(
                text: content,
                style: .body,
                fontSize: fontSize,
                fontDesign: fontFamily.design,
                customFontName: resolvedBodyFont,
                textColor: onSurface,
                lineSpacing: fontSize * 0.8, // leading 1.8 → extra 0.8em
                onAIAction: onAIAction
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 32) // space-y-8
            .padding(.horizontal, 24) // px-6

        case .heading(let content):
            // font-headline extrabold text-4xl tracking-tight, mb-6=24px
            ReaderTextBlock(
                text: content,
                style: .heading,
                fontSize: max(fontSize * 1.6, 30), // text-4xl minimum
                fontDesign: fontFamily.design,
                customFontName: resolvedHeadlineFont,
                textColor: onSurface,
                lineSpacing: fontSize * 0.1, // leading-[1.1]
                onAIAction: onAIAction
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 24) // mb-6
            .padding(.horizontal, 24)

        case .image(let image):
            // aspect-[16/9] rounded-xl shadow-2xl, -mx-4
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth)
                .clipShape(RoundedRectangle(cornerRadius: 12)) // rounded-xl
                .shadow(color: .black.opacity(0.3), radius: 20, y: 8) // shadow-2xl
                .padding(.vertical, 16)

        case .snapshot(let image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
                .colorInvert()
                .colorMultiply(primaryColor)
                .padding(.vertical, 16)
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

    // MARK: - Page extraction (delegates to shared PageLoader)

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
    var customFontName: String? = nil
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
            // HTML: font-body text-lg leading-[1.8] — Noto Serif, natural alignment
            if let name = customFontName, let customFont = UIFont(name: name, size: fontSize) {
                font = customFont
            } else {
                font = ReaderModeView.uiFont(size: fontSize, design: fontDesign)
            }
            paragraphStyle.alignment = .natural
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.hyphenationFactor = 1.0
            // No firstLineHeadIndent — mockup uses space between paragraphs, not indent
        case .heading:
            if let name = customFontName, let customFont = UIFont(name: name, size: fontSize) {
                let boldDesc = customFont.fontDescriptor.withSymbolicTraits(.traitBold)
                font = boldDesc.map { UIFont(descriptor: $0, size: fontSize) } ?? customFont
            } else {
                let baseFont = ReaderModeView.uiFont(size: fontSize, design: fontDesign)
                let boldDesc = baseFont.fontDescriptor.withSymbolicTraits(.traitBold)
                font = boldDesc.map { UIFont(descriptor: $0, size: fontSize) }
                    ?? UIFont.boldSystemFont(ofSize: fontSize)
            }
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
