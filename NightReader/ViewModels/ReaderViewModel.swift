import Foundation
import PDFKit
import SwiftUI

@Observable
final class ReaderViewModel {
    let book: Book
    var document: PDFDocument?
    var isDarkModeEnabled = true
    var dimmerOpacity: Double = 0
    var toolbarVisible = true
    var currentPage: Int = 0

    private var hideToolbarTask: Task<Void, Never>?

    init(book: Book) {
        self.book = book
        self.dimmerOpacity = AppSettings.shared.defaultDimmerOpacity
        self.document = PDFDocument(url: book.fileURL)
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
            try? await Task.sleep(for: .seconds(3))
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

    func toggleDarkMode() {
        isDarkModeEnabled.toggle()
    }
}
