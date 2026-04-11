import Foundation
import SwiftData
import SwiftUI

@Observable
final class LibraryViewModel {
    var showImporter = false
    var isImporting = false
    var errorMessage: String?

    // MARK: - Import

    @MainActor
    func importBook(from url: URL, context: ModelContext) {
        isImporting = true
        Task {
            do {
                _ = try BookImportService.importBook(from: url, context: context)
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }

    // MARK: - Scan

    @MainActor
    func scanForUntrackedBooks(context: ModelContext) {
        Task {
            BookImportService.scanForUntrackedBooks(context: context)
        }
    }

    // MARK: - Delete

    func deleteBook(_ book: Book, context: ModelContext) {
        do {
            try BookImportService.deleteBook(book, context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
