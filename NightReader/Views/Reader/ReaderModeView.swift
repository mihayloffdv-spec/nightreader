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
    var onHighlight: ((String) -> Void)? = nil       // highlight text selection

    @State private var pages: [Int] = []
    @State private var blocksByPage: [Int: [ContentBlock]] = [:]
    @State private var loadingPages: Set<Int> = []
    @State private var screenWidth: CGFloat = 0
    @State private var isInitialScroll = true
    @State private var scrolledBlockID: Int?
    @State private var saveTask: Task<Void, Never>?
    @State private var joinedPairs: Set<Int> = []  // endPage values of already-joined pairs
    @State private var showSmartHighlightTooltip = false

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
        .background(theme.surfaceLowest)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .overlay(alignment: .top) {
            if showSmartHighlightTooltip {
                smartHighlightTooltip
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation { showSmartHighlightTooltip = false } }
                    .task {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation { showSmartHighlightTooltip = false }
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartHighlightsReady)) { _ in
            if !UserDefaults.standard.bool(forKey: "hasSeenSmartHighlightIntro") {
                withAnimation(.easeInOut(duration: 0.3)) { showSmartHighlightTooltip = true }
                UserDefaults.standard.set(true, forKey: "hasSeenSmartHighlightIntro")
            }
        }
    }

    private var smartHighlightTooltip: some View {
        HStack(spacing: 8) {
            Text("✦")
                .font(.system(size: 16))
            Text("AI highlighted key ideas in this chapter. Check the ✦ AI tab in Notebook.")
                .font(.custom("Onest", size: 13))
        }
        .foregroundStyle(theme.textPrimary)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule().fill(theme.backgroundElevated)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        )
        .padding(.top, 60)
        .padding(.horizontal, 24)
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
                    .tint(theme.primary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .padding(.horizontal, 24)
                    .onAppear {
                        extractPage(pageIndex, contentWidth: screenWidth)
                    }
            }

            // No page divider — text flows as continuous stream
            // Pages are invisible boundaries, reader sees one seamless document
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

    private var onSurface: UIColor { UIColor(theme.onSurface) }
    private var primaryColor: Color { theme.primary }

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
                onHighlight: onHighlight,
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

        case .richText(let attrString):
            // Rich text block — preserves bold/italic from PDF
            RichTextBlock(
                attributedText: attrString,
                fontSize: fontSize,
                customFontName: resolvedBodyFont,
                textColor: onSurface,
                onAIAction: onAIAction
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 32)
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

    /// Callback for highlight creation from context menu.
    var onHighlight: ((String) -> Void)?

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

        // Highlight action
        let highlightAction = UIAction(
            title: "Highlight",
            image: UIImage(systemName: "highlighter")
        ) { [weak self] _ in
            guard let self, let text = self.selectedText, !text.isEmpty else { return }
            self.onHighlight?(text)
        }
        builder.insertChild(UIMenu(title: "", options: .displayInline, children: [highlightAction]), atStartOfMenu: .root)
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
    var onHighlight: ((String) -> Void)? = nil
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
        tv.onHighlight = onHighlight
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

// MARK: - Rich Text Block (preserves bold/italic from PDF)

private struct RichTextBlock: UIViewRepresentable {
    let attributedText: NSAttributedString
    let fontSize: CGFloat
    var customFontName: String? = nil
    let textColor: UIColor
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
        // Re-apply fonts at the user's chosen size with the chosen custom font
        let mutable = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: mutable.length)

        mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let originalFont = value as? UIFont else { return }
            let traits = originalFont.fontDescriptor.symbolicTraits
            let isBold = traits.contains(.traitBold)
            let isItalic = traits.contains(.traitItalic)

            // Determine target size (headings stay proportionally larger)
            let originalSize = originalFont.pointSize
            let isHeading = originalSize > fontSize * 1.2
            let targetSize = isHeading ? fontSize * 1.5 : fontSize

            // Build font with user's choice
            var font: UIFont
            if let name = customFontName, let customFont = UIFont(name: name, size: targetSize) {
                font = customFont
            } else {
                font = UIFont.systemFont(ofSize: targetSize)
            }

            if isBold {
                if let d = font.fontDescriptor.withSymbolicTraits(.traitBold) {
                    font = UIFont(descriptor: d, size: targetSize)
                }
            }
            if isItalic {
                if let d = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
                    font = UIFont(descriptor: d, size: targetSize)
                }
            }
            if isBold && isItalic {
                if let d = font.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
                    font = UIFont(descriptor: d, size: targetSize)
                }
            }

            mutable.addAttribute(.font, value: font, range: range)
        }

        // Apply text color and paragraph style
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = fontSize * 0.8
        paragraphStyle.alignment = .natural

        mutable.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        if tv.attributedText != mutable {
            tv.attributedText = mutable
        }
        tv.onAIAction = onAIAction
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReaderTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}
