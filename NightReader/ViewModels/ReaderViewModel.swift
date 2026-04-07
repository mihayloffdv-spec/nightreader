import Foundation
@preconcurrency import PDFKit
@preconcurrency import SwiftUI

// MARK: - ReaderViewModel (Core)
//
// Document, navigation, theme, rendering, bookmarks.
// AI logic in ReaderViewModel+AI.swift
// Highlights in ReaderViewModel+Highlights.swift
// Session tracking in ReaderViewModel+Session.swift

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
    var showSearch = false
    var showTOC = false
    var goToPageIndex: Int?
    var goToSelectionValue: PDFSelection?
    var isLoading = true
    var loadError: String?
    var isReaderMode = true
    var isDayMode = false
    var readerFontSize: Double = AppSettings.shared.readerFontSize
    var readerFontFamily: ReaderFont = AppSettings.shared.currentReaderFont
    var readerCustomFontName: String { AppSettings.shared.readerFontFamily }
    var cropMargin: Double = 0
    var totalWordCount: Int = 0
    var chapters: [Chapter] = []
    var currentChapter: Chapter?
    var chapterProgress: Double = 0

    // Highlight state (methods in +Highlights.swift)
    var annotationStore: AnnotationStore?
    var showAnnotationList = false
    var showAnnotationSheet = false
    var showExportShare = false
    var pendingHighlightText: String = ""
    var pendingHighlightBounds: [[CGFloat]] = []
    var pendingReaction: String = ""
    var pendingAction: String = ""
    var highlightColor: HighlightColor = .yellow
    var exportURL: URL?

    // AI state (methods in +AI.swift)
    var showAISheet = false
    var showAPIKeySettings = false
    var aiActionType: AIActionType = .explain
    var aiSelectedText: String = ""
    var aiResponseState: AIResponseState = .idle
    internal var aiTask: Task<Void, Never>?
    var smartHighlightsEnabled: Bool = AppSettings.shared.smartHighlightsEnabled
    var isAnalyzingChapter = false
    internal var analysisTask: Task<Void, Never>?
    internal var analysisDebounceTask: Task<Void, Never>?
    internal var lastAnalyzedChapterIndex: Int?
    var showChat = false
    var chatMessages: [ChatMessage] = []
    var chatInputText: String = ""
    internal var chatTask: Task<Void, Never>?
    var showChapterReview = false
    var currentChapterReview: ChapterReview?
    var isGeneratingQuestions = false
    internal var reviewedChapters: Set<Int> = []
    static let maxAITextLength = 2000

    // Argument Map state
    var showArgumentMap = false
    var currentArgumentMap: ArgumentMap?
    var isGeneratingArgumentMap = false

    // Session state (methods in +Session.swift)
    var showPostReadingReview = false
    var isNearEndOfBook: Bool { progressFraction > 0.95 }
    var showSessionRecap = false
    var sessionHighlightCount: Int = 0
    var sessionDuration: TimeInterval = 0
    internal var sessionStartTime: Date?
    internal var sessionBackgroundTime: TimeInterval = 0
    internal var backgroundEnteredAt: Date?
    internal var sessionBackgroundObserver: Any?
    internal var sessionForegroundObserver: Any?

    private var hideToolbarTask: Task<Void, Never>?
    private(set) var originalDocument: PDFDocument?

    var originalDoc: PDFDocument? { originalDocument }

    var estimatedReadingMinutes: Int {
        max(1, totalWordCount / 200)
    }

    init(book: Book) {
        self.book = book
        self.renderingMode = book.renderingMode
        self.cropMargin = book.cropMargin
        self.selectedTheme = AppSettings.shared.currentTheme
        self.dimmerOpacity = AppSettings.shared.defaultDimmerOpacity
        self.annotationStore = AnnotationStore(
            bookId: book.id.uuidString,
            title: book.title,
            author: book.author
        )
    }

    // MARK: - Document Loading

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
            if book.totalPages == 0 {
                book.totalPages = doc.pageCount
            }
            if renderingMode == .smart {
                applySmartMode()
            } else {
                self.document = doc
            }
            isLoading = false
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

    // MARK: - Navigation & Progress

    var isDarkModeEnabled: Bool { renderingMode != .off }

    var isCurrentPageBookmarked: Bool { book.bookmarks.contains(currentPage) }

    var progressText: String {
        guard book.totalPages > 0 else { return "" }
        return "\(currentPage + 1) / \(book.totalPages)"
    }

    var progressFraction: Double {
        guard book.totalPages > 0 else { return 0 }
        return Double(currentPage + 1) / Double(book.totalPages)
    }

    func goToPage(_ pageIndex: Int) { goToPageIndex = pageIndex }

    func goToSelection(_ selection: PDFSelection) { goToSelectionValue = selection }

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

    // MARK: - Toolbar

    func toggleToolbar() {
        toolbarVisible.toggle()
        if toolbarVisible { scheduleHideToolbar() }
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

    func cancelHideToolbar() { hideToolbarTask?.cancel() }

    // MARK: - Bookmarks

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

    // MARK: - Reader Mode / Day Mode

    func toggleReaderMode() {
        scheduleHideToolbar()
        isReaderMode.toggle()
        if !isReaderMode { isDayMode = false }
        goToPageIndex = currentPage
    }

    func toggleDayMode() {
        scheduleHideToolbar()
        isDayMode.toggle()
        if isDayMode && !isReaderMode { isReaderMode = true }
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

    // MARK: - Theme & Rendering

    func setRenderingMode(_ mode: RenderingMode) {
        scheduleHideToolbar()
        renderingMode = mode
        book.renderingMode = mode
        AppSettings.shared.defaultRenderingMode = mode.rawValue
        if mode == .smart { applySmartMode() } else { restoreOriginalDocument() }
    }

    func setTheme(_ theme: Theme) {
        scheduleHideToolbar()
        selectedTheme = theme
        AppSettings.shared.defaultThemeId = theme.id
        DarkModePDFPage.invalidateCache()
        if renderingMode == .smart { applySmartMode() }
    }

    // MARK: - Chapter Info

    internal func updateChapterInfo() {
        let previousChapter = currentChapter
        currentChapter = ChapterDetector.currentChapter(forPage: currentPage, in: chapters)
        chapterProgress = ChapterDetector.chapterProgress(
            forPage: currentPage, in: chapters, totalPages: book.totalPages
        )

        if let current = currentChapter, current.id != previousChapter?.id {
            triggerSmartHighlightAnalysis(for: current)
            if let prev = previousChapter, chapterProgress < 0.1 {
                offerChapterReview(for: prev)
            }
        }
    }

    // MARK: - Smart Mode Rendering

    private static let smartModeQueue = DispatchQueue(
        label: "com.nightreader.smart-mode",
        qos: .userInitiated
    )

    private func applySmartMode() {
        guard let original = originalDocument else { return }
        let savedPage = currentPage
        let theme = selectedTheme
        isLoading = true
        let safeOriginal = original
        Task.detached { [weak self] in
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                ReaderViewModel.smartModeQueue.async {
                    let smartDoc = PDFDocument()
                    for i in 0..<safeOriginal.pageCount {
                        guard let page = safeOriginal.page(at: i) else { continue }
                        let smartPage = DarkModePDFPage(wrapping: page, pageIndex: i, theme: theme)
                        smartDoc.insert(smartPage, at: i)
                    }
                    DispatchQueue.main.async {
                        self?.document = smartDoc
                        self?.isLoading = false
                        if savedPage > 0 { self?.goToPageIndex = savedPage }
                        cont.resume()
                    }
                }
            }
        }
    }

    private func restoreOriginalDocument() { document = originalDocument }

    nonisolated static func countWords(in document: PDFDocument) -> Int {
        var total = 0
        for i in 0..<document.pageCount {
            if let text = document.page(at: i)?.string {
                total += text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            }
        }
        return total
    }

    // MARK: - Diagnostics

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
