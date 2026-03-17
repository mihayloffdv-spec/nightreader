import Foundation
import PDFKit
import SwiftUI

@Observable
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
    var readerFontSize: Double = AppSettings.shared.readerFontSize
    var readerFontFamily: ReaderFont = AppSettings.shared.currentReaderFont

    private var hideToolbarTask: Task<Void, Never>?
    private(set) var originalDocument: PDFDocument?

    /// Original (unprocessed) document for Reader Mode.
    var originalDoc: PDFDocument? { originalDocument }

    init(book: Book) {
        self.book = book
        self.renderingMode = book.renderingMode
        self.selectedTheme = AppSettings.shared.currentTheme
        self.dimmerOpacity = AppSettings.shared.defaultDimmerOpacity
    }

    @MainActor
    func loadDocument() async {
        isLoading = true
        BlockCache.shared.invalidate()
        let url = book.fileURL
        let doc = await Task.detached {
            PDFDocument(url: url)
        }.value

        if let doc {
            self.originalDocument = doc
            if renderingMode == .smart {
                applySmartMode()
            } else {
                self.document = doc
            }
            isLoading = false
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

    func toggleReaderMode() {
        scheduleHideToolbar()
        isReaderMode.toggle()
        // Navigate to the same page in the new mode
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

    private func applySmartMode() {
        guard let original = originalDocument else { return }
        let savedPage = currentPage
        let theme = selectedTheme
        isLoading = true
        Task.detached {
            let smartDoc = PDFDocument()
            for i in 0..<original.pageCount {
                guard let page = original.page(at: i) else { continue }
                let smartPage = DarkModePDFPage(wrapping: page, theme: theme)
                smartDoc.insert(smartPage, at: i)
            }
            await MainActor.run { [weak self] in
                self?.document = smartDoc
                self?.isLoading = false
                if savedPage > 0 {
                    self?.goToPageIndex = savedPage
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
            let report = PDFContentExtractor.diagnoseDropCaps(document: doc)
            await MainActor.run { [weak self] in
                self?.diagnosticReport = report
                self?.isRunningDiagnostics = false
                print(report)
            }
        }
    }
    #endif
}
