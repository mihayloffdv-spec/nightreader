import Foundation
import SwiftData
import SwiftUI

@Observable
final class LibraryViewModel {
    var showImporter = false
    var errorMessage: String?

    func importPDF(from url: URL, context: ModelContext) {
        do {
            _ = try PDFImportService.importPDF(from: url, context: context)
        } catch {
            errorMessage = "Failed to import PDF: \(error.localizedDescription)"
        }
    }

    func deleteBook(_ book: Book, context: ModelContext) {
        let fileURL = book.fileURL
        context.delete(book)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
