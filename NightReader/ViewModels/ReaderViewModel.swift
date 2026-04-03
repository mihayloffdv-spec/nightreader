import Foundation
@preconcurrency import PDFKit
@preconcurrency import SwiftUI

@MainActor @Observable
final class ReaderViewModel {
    let book: Book
    var document: PDFDocument?
    var renderingMode: RenderingMode
    var selectedTheme: Theme
    var dimmerOpacity: Double = 0
    var toolbarVisible = true
    var currentPage: Int = 0
    var showThemePicker = false
    var showAnnotationList = false
    var showSearch = false
    var showTOC = false
    var showExportShare = false
    var highlightColor: HighlightColor = .yellow
    var exportURL: URL?
    var goToPageIndex: Int?
    var goToSelectionValue: PDFSelection?
    var isLoading = true
    var loadError: String?
    var isReaderMode = false
    var isDayMode = false
    var readerFontSize: Double = AppSettings.shared.readerFontSize
    var readerFontFamily: ReaderFont = AppSettings.shared.currentReaderFont
    var cropMargin: Double = 0
    var totalWordCount: Int = 0
    var chapters: [Chapter] = []
    var currentChapter: Chapter?
    var chapterProgress: Double = 0

    // AI features state
    var showAISheet = false
    var showAPIKeySettings = false
    var aiActionType: AIActionType = .explain
    var aiSelectedText: String = ""
    var aiResponseState: AIResponseState = .idle
    private var aiTask: Task<Void, Never>?

    private var hideToolbarTask: Task<Void, Never>?
    private var sessionStartTime: Date?
    private(set) var originalDocument: PDFDocument?

    /// Original (unprocessed) document for Reader Mode.
    var originalDoc: PDFDocument? { originalDocument }

    /// Estimated reading time in minutes (200 wpm average).
    var estimatedReadingMinutes: Int {
        max(1, totalWordCount / 200)
    }

    init(book: Book) {
        self.book = book
        self.renderingMode = book.renderingMode
        self.cropMargin = book.cropMargin
        self.selectedTheme = AppSettings.shared.currentTheme
        self.dimmerOpacity = AppSettings.shared.defaultDimmerOpacity
    }

    @MainActor
    func loadDocument() async {
        isLoading = true
        BlockCache.shared.invalidate()
        let url = book.fileURL
        let doc: PDFDocument? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: PDFDocument(url: url))
            }
        }

        if let doc {
            self.originalDocument = doc
            // Update page count if it was 0 (e.g. imported without opening)
            if book.totalPages == 0 {
                book.totalPages = doc.pageCount
            }
            if renderingMode == .smart {
                applySmartMode()
            } else {
                self.document = doc
            }
            isLoading = false
            // Подсчёт слов и глав на extractionQueue
            // (PDFDocument не потокобезопасен — доступ сериализован)
            let countDoc = doc
            Task.detached { [weak self] in
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    ReaderModeView.extractionQueue.async {
                        let count = ReaderViewModel.countWords(in: countDoc)
                        let detectedChapters = ChapterDetector.detectChapters(in: countDoc)
                        DispatchQueue.main.async {
                            self?.totalWordCount = count
                            self?.chapters = detectedChapters
                            self?.updateChapterInfo()
                            cont.resume()
                        }
                    }
                }
            }
        } else {
            loadError = "File is missing or corrupted."
            isLoading = false
        }
    }

    var isDarkModeEnabled: Bool {
        renderingMode != .off
    }

    var isCurrentPageBookmarked: Bool {
        book.bookmarks.contains(currentPage)
    }

    var progressText: String {
        guard book.totalPages > 0 else { return "" }
        return "\(currentPage + 1) / \(book.totalPages)"
    }

    var progressFraction: Double {
        guard book.totalPages > 0 else { return 0 }
        return Double(currentPage + 1) / Double(book.totalPages)
    }

    func toggleToolbar() {
        toolbarVisible.toggle()
        if toolbarVisible {
            scheduleHideToolbar()
        }
    }

    func scheduleHideToolbar() {
        hideToolbarTask?.cancel()
        hideToolbarTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.25)) {
                    toolbarVisible = false
                }
            }
        }
    }

    func cancelHideToolbar() {
        hideToolbarTask?.cancel()
    }

    func savePosition(pageIndex: Int, scrollOffset: Double) {
        book.lastPageIndex = pageIndex
        book.scrollOffsetY = scrollOffset
        book.lastReadDate = Date()
        if book.totalPages > 0 {
            book.readProgress = Double(pageIndex + 1) / Double(book.totalPages)
        }
        currentPage = pageIndex
        updateChapterInfo()
    }

    func setRenderingMode(_ mode: RenderingMode) {
        scheduleHideToolbar()
        renderingMode = mode
        book.renderingMode = mode
        AppSettings.shared.defaultRenderingMode = mode.rawValue

        if mode == .smart {
            applySmartMode()
        } else {
            restoreOriginalDocument()
        }
    }

    func setTheme(_ theme: Theme) {
        scheduleHideToolbar()
        selectedTheme = theme
        AppSettings.shared.defaultThemeId = theme.id
        DarkModePDFPage.invalidateCache()
        if renderingMode == .smart {
            applySmartMode()
        }
    }

    func toggleBookmark() {
        scheduleHideToolbar()
        var marks = book.bookmarks
        if marks.contains(currentPage) {
            marks.remove(currentPage)
        } else {
            marks.insert(currentPage)
        }
        book.bookmarks = marks
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func exportAnnotations() {
        scheduleHideToolbar()
        guard let document else { return }
        if let url = ExportService.exportAnnotationsToFile(from: document, title: book.title) {
            exportURL = url
            showExportShare = true
        } else {
            loadError = "Failed to export annotations."
        }
    }

    func goToPage(_ pageIndex: Int) {
        goToPageIndex = pageIndex
    }

    func goToSelection(_ selection: PDFSelection) {
        goToSelectionValue = selection
    }

    // MARK: - Reading Time Tracking

    func startReadingSession() {
        sessionStartTime = Date()
    }

    func stopReadingSession() {
        guard let start = sessionStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        // Only count sessions longer than 5 seconds (ignore accidental opens)
        if elapsed > 5 {
            book.totalReadingTime += elapsed
        }
        sessionStartTime = nil
    }

    func toggleReaderMode() {
        scheduleHideToolbar()
        isReaderMode.toggle()
        if !isReaderMode { isDayMode = false }
        goToPageIndex = currentPage
    }

    func toggleDayMode() {
        scheduleHideToolbar()
        isDayMode.toggle()
        if isDayMode && !isReaderMode {
            isReaderMode = true
        }
        goToPageIndex = currentPage
    }

    func setReaderFontSize(_ size: Double) {
        readerFontSize = size
        AppSettings.shared.readerFontSize = size
        BlockCache.shared.invalidate()
    }

    func setReaderFontFamily(_ font: ReaderFont) {
        readerFontFamily = font
        AppSettings.shared.readerFontFamily = font.rawValue
    }

    func setCropMargin(_ margin: Double) {
        cropMargin = margin
        book.cropMargin = margin
    }

    // MARK: - AI Actions

    /// Request AI explanation for selected text.
    func requestExplain(text: String) {
        requestAIAction(.explain, text: text)
    }

    /// Request AI translation for selected text.
    func requestTranslate(text: String) {
        requestAIAction(.translate, text: text)
    }

    private static let maxAITextLength = 2000

    private func requestAIAction(_ action: AIActionType, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Cap input size to avoid excessive API costs and token limit errors
        guard trimmed.count <= Self.maxAITextLength else {
            aiActionType = action
            aiSelectedText = String(trimmed.prefix(200))
            aiResponseState = .error("Выберите фрагмент короче \(Self.maxAITextLength) символов.")
            showAISheet = true
            return
        }

        // Check API key first
        guard KeychainManager.hasAPIKey else {
            showAPIKeySettings = true
            return
        }

        aiActionType = action
        aiSelectedText = trimmed
        aiResponseState = .loading
        showAISheet = true

        aiTask?.cancel()
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.aiTask = nil }
            do {
                let response: String
                switch action {
                case .explain:
                    response = try await ClaudeAPIService.explain(text: trimmed)
                case .translate:
                    response = try await ClaudeAPIService.translate(text: trimmed)
                }
                guard !Task.isCancelled else { return }
                self.aiResponseState = .success(response)
            } catch {
                guard !Task.isCancelled else { return }
                self.aiResponseState = .error(error.localizedDescription)
            }
        }
    }

    /// Retry the last AI action.
    func retryAIAction() {
        requestAIAction(aiActionType, text: aiSelectedText)
    }

    /// Dismiss AI sheet and reset state.
    func dismissAISheet() {
        aiTask?.cancel()
        aiTask = nil
        showAISheet = false
        aiResponseState = .idle
    }

    private func updateChapterInfo() {
        currentChapter = ChapterDetector.currentChapter(forPage: currentPage, in: chapters)
        chapterProgress = ChapterDetector.chapterProgress(
            forPage: currentPage, in: chapters, totalPages: book.totalPages
        )
    }

    nonisolated private static func countWords(in document: PDFDocument) -> Int {
        var total = 0
        for i in 0..<document.pageCount {
            if let text = document.page(at: i)?.string {
                total += text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            }
        }
        return total
    }

    private func applySmartMode() {
        guard let original = originalDocument else { return }
        let savedPage = currentPage
        let theme = selectedTheme
        isLoading = true
        // Сериализуем доступ к PDFDocument через extractionQueue
        let safeOriginal = original
        Task.detached { [weak self] in
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                ReaderModeView.extractionQueue.async {
                    let smartDoc = PDFDocument()
                    for i in 0..<safeOriginal.pageCount {
                        guard let page = safeOriginal.page(at: i) else { continue }
                        let smartPage = DarkModePDFPage(wrapping: page, theme: theme)
                        smartDoc.insert(smartPage, at: i)
                    }
                    DispatchQueue.main.async {
                        self?.document = smartDoc
                        self?.isLoading = false
                        if savedPage > 0 {
                            self?.goToPageIndex = savedPage
                        }
                        cont.resume()
                    }
                }
            }
        }
    }

    private func restoreOriginalDocument() {
        document = originalDocument
    }

    #if DEBUG
    var diagnosticReport: String?
    var isRunningDiagnostics = false

    func runDropCapDiagnostics() {
        guard let doc = originalDocument ?? document else { return }
        isRunningDiagnostics = true
        diagnosticReport = nil
        BlockCache.shared.clearAll()
        Task.detached {
            let report = DropCapRecovery.diagnoseDropCaps(document: doc)
            await MainActor.run { [weak self] in
                self?.diagnosticReport = report
                self?.isRunningDiagnostics = false
                print(report)
            }
        }
    }
    #endif
}
