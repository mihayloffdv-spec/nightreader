import SwiftUI
import PDFKit

struct ReaderModeView: View {
    let document: PDFDocument?
    var provider: (any BookContentProvider)? = nil
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
    var smartHighlightTexts: [String] = []            // AI highlight texts for pencil marks

    @State private var showSmartHighlightTooltip = false

    // extractionQueue moved to shared PageLoader service.
    // Keep this accessor for backward compatibility with ReaderViewModel.loadDocument().
    nonisolated(unsafe) static var extractionQueue: DispatchQueue { PageLoader.extractionQueue }

    var body: some View {
        PagedContentView(
            document: document,
            provider: provider,
            currentPageIndex: currentPageIndex,
            savedBlockID: savedBlockID,
            goToPageIndex: $goToPageIndex,
            onPageChange: onPageChange,
            onTap: onTap,
            scrollViewID: "\(fontSize)_\(fontFamily.rawValue)_\(customFontOverride ?? "")",
            contentPadding: EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0),
            backgroundColor: theme.surfaceLowest,
            progressTint: theme.primary,
            header: { EmptyView() },
            blockContent: { block, pageIndex, screenWidth in
                blockView(block, pageIndex: pageIndex, contentWidth: screenWidth)
            }
        )
        .overlay(alignment: .top) {
            if showSmartHighlightTooltip {
                smartHighlightTooltip
                    .transition(.softTop)
                    .onTapGesture { withAnimation(.softMenu) { showSmartHighlightTooltip = false } }
                    .task {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation(.softMenu) { showSmartHighlightTooltip = false }
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartHighlightsReady)) { _ in
            if !UserDefaults.standard.bool(forKey: "hasSeenSmartHighlightIntro") {
                withAnimation(.softMenu) { showSmartHighlightTooltip = true }
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

    // MARK: - Font resolution

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

    private var onSurface: UIColor { UIColor(theme.onSurface) }
    private var primaryColor: Color { theme.primary }

    /// Normalize text for fuzzy comparison: lowercase, collapse whitespace,
    /// strip punctuation so minor differences between Claude's output and the
    /// actual PDF text don't cause misses.
    private func normalizeForMatch(_ text: String) -> String {
        let allowed = CharacterSet.letters.union(.decimalDigits).union(.whitespaces)
        let filtered = text.unicodeScalars.filter { allowed.contains($0) }
        let cleaned = String(String.UnicodeScalarView(filtered))
        return cleaned.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    /// Check if a text block contains any AI smart highlight text.
    /// Uses multiple strategies: full substring match, then first-N-words match
    /// (in case Claude truncated or paraphrased the ending).
    private func hasSmartHighlight(in blockText: String) -> Bool {
        guard !smartHighlightTexts.isEmpty else { return false }
        let normalizedBlock = normalizeForMatch(blockText)
        guard !normalizedBlock.isEmpty else { return false }

        for highlight in smartHighlightTexts {
            let normalizedHL = normalizeForMatch(highlight)
            guard !normalizedHL.isEmpty else { continue }

            // Strategy 1: full substring match
            if normalizedBlock.contains(normalizedHL) { return true }

            // Strategy 2: first 8 words of the highlight appear in the block
            let words = normalizedHL.split(separator: " ")
            if words.count >= 6 {
                let prefix = words.prefix(min(8, words.count)).joined(separator: " ")
                if normalizedBlock.contains(prefix) { return true }
            }
        }
        return false
    }

    @ViewBuilder
    private func blockView(_ block: ContentBlock, pageIndex: Int, contentWidth: CGFloat) -> some View {
        // First page is almost always a cover. Render it as-is (no inversion, no tint)
        // so the cover looks natural even in dark mode.
        let isCover = pageIndex == 0
        switch block {
        case .text(let content):
            ReaderTextBlock(
                text: content,
                style: .body,
                fontSize: fontSize,
                fontDesign: fontFamily.design,
                customFontName: resolvedBodyFont,
                onHighlight: onHighlight,
                onTap: onTap,
                textColor: onSurface,
                lineSpacing: fontSize * 0.8,
                onAIAction: onAIAction
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 32)
            .padding(.horizontal, 24)
            .modifier(SmartHighlightBackground(
                isActive: hasSmartHighlight(in: content),
                accent: theme.accent
            ))

        case .heading(let content):
            ReaderTextBlock(
                text: content,
                style: .heading,
                fontSize: max(fontSize * 1.6, 30),
                fontDesign: fontFamily.design,
                customFontName: resolvedHeadlineFont,
                onTap: onTap,
                textColor: onSurface,
                lineSpacing: fontSize * 0.1,
                onAIAction: onAIAction
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .padding(.horizontal, 24)

        case .richText(let attrString):
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
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
                .padding(.vertical, 16)

        case .snapshot(let image):
            // Invert only if this is monochrome text on a light background.
            // Graphic pages (covers, illustrations, colored diagrams) render as-is
            // so they don't look like a cursed Instagram filter in dark mode.
            let shouldInvert = !isCover && SnapshotCache.isMonochromeText(image)
            if shouldInvert {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: contentWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
                    .colorInvert()
                    .colorMultiply(primaryColor)
                    .padding(.vertical, 16)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: contentWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                    .padding(.vertical, 16)
            }
        }
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
}

// MARK: - Smart Highlight Background
//
// Visual style for AI-identified paragraphs. A translucent accent background
// with a glow and a solid left-edge bar. Distinct from user highlights
// (which color a specific text range) so readers understand "AI noticed this
// whole paragraph" vs "you highlighted this sentence."

private struct SmartHighlightBackground: ViewModifier {
    let isActive: Bool
    let accent: Color

    func body(content: Content) -> some View {
        if isActive {
            content
                .background(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        // Translucent accent fill across the whole paragraph
                        RoundedRectangle(cornerRadius: 6)
                            .fill(accent.opacity(0.12))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 0)
                            .shadow(color: accent.opacity(0.25), radius: 8, y: 0)

                        // Bold left-edge bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accent)
                            .frame(width: 4)
                            .padding(.leading, 12)
                            .padding(.vertical, 4)
                            .shadow(color: accent.opacity(0.6), radius: 6)
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - Tap-through UITextView (passes single taps to parent for toolbar toggle)

private class ReaderTextView: UITextView, UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                          shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Allow quick-highlight tap to coexist with UITextView's built-in gestures
        if gestureRecognizer === quickHighlightTap { return false }
        return false
    }

    var onHighlight: ((String) -> Void)?
    var onAIAction: ((AIActionType, String) -> Void)?

    /// Quick-annotate: double-tap on existing selection → instant highlight without bottom sheet.
    private lazy var quickHighlightTap: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleQuickHighlight))
        tap.numberOfTapsRequired = 2
        tap.delegate = self
        return tap
    }()

    private var quickHighlightInstalled = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if !quickHighlightInstalled {
            addGestureRecognizer(quickHighlightTap)
            quickHighlightInstalled = true
        }
        installToolbarTapIfNeeded()
    }

    @objc private func handleQuickHighlight(_ gesture: UITapGestureRecognizer) {
        guard let text = selectedText, !text.isEmpty else { return }
        onHighlight?(text)
        // Deselect after quick highlight
        selectedTextRange = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Callback for toolbar toggle (forwarded from taps on text area with no selection).
    var onTap: (() -> Void)?

    /// Tap recognizer that fires toolbar toggle when there's no selection.
    /// UITextView swallows single-tap events even when its gesture recognizers decline,
    /// so SwiftUI's .onTapGesture on the parent never fires. This explicit recognizer
    /// catches those taps and forwards them.
    private lazy var toolbarTap: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleToolbarTap))
        tap.numberOfTapsRequired = 1
        tap.delegate = self
        return tap
    }()

    private var toolbarTapInstalled = false

    private func installToolbarTapIfNeeded() {
        guard !toolbarTapInstalled else { return }
        addGestureRecognizer(toolbarTap)
        // toolbarTap must wait for double-tap to fail (don't steal double-taps)
        for gr in gestureRecognizers ?? [] {
            if let tap = gr as? UITapGestureRecognizer, tap.numberOfTapsRequired == 2 {
                toolbarTap.require(toFail: tap)
            }
        }
        toolbarTap.require(toFail: quickHighlightTap)
        toolbarTapInstalled = true
    }

    @objc private func handleToolbarTap(_ gesture: UITapGestureRecognizer) {
        onTap?()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Quick-highlight: only fires when there's already a selection
        if gestureRecognizer === quickHighlightTap {
            return selectedRange.length > 0
        }
        // Toolbar tap: only fires when there's NO selection
        if gestureRecognizer === toolbarTap {
            return selectedRange.length == 0
        }
        // Long press always allowed (starts text selection)
        if gestureRecognizer is UILongPressGestureRecognizer { return true }
        if let tap = gestureRecognizer as? UITapGestureRecognizer {
            // Double-tap always allowed (word select)
            if tap.numberOfTapsRequired == 2 { return true }
            // Single tap from UITextView internals: only if there's selection to deselect
            if tap.numberOfTapsRequired == 1 { return selectedRange.length > 0 }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

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

        let highlightAction = UIAction(
            title: "Highlight",
            image: UIImage(systemName: "highlighter")
        ) { [weak self] _ in
            guard let self, let text = self.selectedText, !text.isEmpty else { return }
            self.onHighlight?(text)
        }
        builder.insertChild(UIMenu(title: "", options: .displayInline, children: [highlightAction]), atStartOfMenu: .root)
    }

    private var selectedText: String? {
        guard selectedRange.length > 0,
              let text = self.text,
              let range = Range(selectedRange, in: text) else { return nil }
        return String(text[range])
    }
}

// MARK: - Text blocks

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
    var onTap: (() -> Void)? = nil
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
        tv.onTap = onTap
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
            if let name = customFontName, let customFont = UIFont(name: name, size: fontSize) {
                font = customFont
            } else {
                font = ReaderModeView.uiFont(size: fontSize, design: fontDesign)
            }
            paragraphStyle.alignment = .natural
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.hyphenationFactor = 1.0
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

// MARK: - Rich Text Block

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
        let mutable = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: mutable.length)

        mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let originalFont = value as? UIFont else { return }
            let traits = originalFont.fontDescriptor.symbolicTraits
            let isBold = traits.contains(.traitBold)
            let isItalic = traits.contains(.traitItalic)

            let originalSize = originalFont.pointSize
            let isHeading = originalSize > fontSize * 1.2
            let targetSize = isHeading ? fontSize * 1.5 : fontSize

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
