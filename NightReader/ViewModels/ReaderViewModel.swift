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

    private var hideToolbarTask: Task<Void, Never>?
    private var originalDocument: PDFDocument?

    init(book: Book) {
        self.book = book
        self.renderingMode = book.renderingMode
        self.selectedTheme = AppSettings.shared.currentTheme
        self.dimmerOpacity = AppSettings.shared.defaultDimmerOpacity
        let doc = PDFDocument(url: book.fileURL)
        self.document = doc
        self.originalDocument = doc
    }

    var isDarkModeEnabled: Bool {
        renderingMode != .off
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
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled {
                toolbarVisible = false
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
        selectedTheme = theme
        AppSettings.shared.defaultThemeId = theme.id
    }

    private func applySmartMode() {
        guard let original = originalDocument else { return }
        let smartDoc = PDFDocument()
        for i in 0..<original.pageCount {
            guard let page = original.page(at: i) else { continue }
            let smartPage = DarkModePDFPage(wrapping: page)
            smartDoc.insert(smartPage, at: i)
        }
        document = smartDoc
    }

    private func restoreOriginalDocument() {
        document = originalDocument
    }
}
