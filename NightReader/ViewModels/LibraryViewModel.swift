import Foundation
import SwiftData
import SwiftUI

@Observable
final class LibraryViewModel {
    var showImporter = false
    var errorMessage: String?

    // MARK: - Import

    func importBook(from url: URL, context: ModelContext) {
        do {
            _ = try BookImportService.importBook(from: url, context: context)
        } catch {
            errorMessage = error.localizedDescription
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
