import Foundation
import PDFKit
import SwiftData
import UIKit

// MARK: - BookImportService
//
// Unified import entry point for all book formats (PDF, FB2, EPUB).
// Routes by file extension, delegates to format-specific importers.
//
// Also handles cleanup on deletion:
//   - Original file in Documents/
//   - Content copy in Application Support/books/{format}/
//   - Annotations JSON in Application Support/annotations/

struct BookImportService {

    // MARK: - Import

    /// Import a book from any supported format. Routes by file extension.
    static func importBook(from sourceURL: URL, context: ModelContext) throws -> Book {
        let ext = sourceURL.pathExtension.lowercased()
        let isFB2Zip = sourceURL.lastPathComponent.lowercased().hasSuffix(".fb2.zip")
        switch ext {
        case "pdf":
            return try PDFImportService.importPDF(from: sourceURL, context: context)
        case "fb2":
            return try FB2Importer.importFB2(from: sourceURL, context: context)
        case "zip" where isFB2Zip:
            return try FB2Importer.importFB2(from: sourceURL, context: context)
        case "epub":
            return try EPUBImporter.importEPUB(from: sourceURL, context: context)
        default:
            throw BookImportError.unsupportedFormat(ext)
        }
    }

    // MARK: - Delete

    /// Removes the book from SwiftData, deletes all associated files and annotations.
    static func deleteBook(_ book: Book, context: ModelContext) throws {
        let fileURL    = book.fileURL
        let contentURL = book.contentURL
        let format     = book.format
        let bookId     = book.id.uuidString

        context.delete(book)
        try context.save()

        // 1. Remove original file from Documents
        try? FileManager.default.removeItem(at: fileURL)

        // 2. Remove format-specific content from Application Support
        switch format {
        case .fb2, .epub:
            try? FileManager.default.removeItem(at: contentURL)
        case .pdf:
            break // PDF contentURL == fileURL, already removed
        }

        // 3. Remove annotations JSON
        deleteAnnotations(bookId: bookId)
    }

    // MARK: - Scan

    /// Scans Documents/ for book files not yet tracked in SwiftData.
    /// Supports PDF (existing) and FB2 files.
    static func scanForUntrackedBooks(context: ModelContext) {
        let docsDir = Book.documentsDirectory
        let existing = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let tracked = Set(existing.map(\.fileName))

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: docsDir.path) else { return }

        for file in files {
            guard !tracked.contains(file) else { continue }
            let ext = (file as NSString).pathExtension.lowercased()
            let url = docsDir.appendingPathComponent(file)

            switch ext {
            case "pdf":
                PDFImportService.scanSinglePDF(file: file, url: url, context: context)
            case "fb2":
                scanSingleFB2(file: file, url: url, context: context)
            default:
                continue
            }
        }
        try? context.save()
    }

    // MARK: - Helpers

    /// Turn filenames into readable titles. Shared by all importers.
    static func cleanFilename(_ stem: String) -> String {
        PDFImportService.cleanFilename(stem)
    }

    // MARK: - Private

    private static func deleteAnnotations(bookId: String) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let annotationFile = appSupport
            .appendingPathComponent("annotations")
            .appendingPathComponent("\(bookId).json")
        try? FileManager.default.removeItem(at: annotationFile)
    }

    private static func scanSingleFB2(file: String, url: URL, context: ModelContext) {
        // Create AppSupport copy so book.contentURL resolves correctly
        let fb2Dir = Book.applicationSupportDirectory.appendingPathComponent("books/fb2")
        try? FileManager.default.createDirectory(at: fb2Dir, withIntermediateDirectories: true)
        let destAppSupport = fb2Dir.appendingPathComponent(file)
        if !FileManager.default.fileExists(atPath: destAppSupport.path) {
            try? FileManager.default.copyItem(at: url, to: destAppSupport)
        }

        guard let provider = try? FB2ContentProvider(url: destAppSupport) else { return }
        let title = provider.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = (title?.isEmpty == false ? title : nil)
            ?? cleanFilename((file as NSString).deletingPathExtension)
        let book = Book(
            title: cleanTitle,
            author: provider.author,
            fileName: file,
            totalPages: provider.pageCount
        )
        book.format = .fb2
        context.insert(book)
    }
}

// MARK: - PDFImportService scan helper

extension PDFImportService {
    /// Scan a single untracked PDF and insert into context (no save — caller saves).
    static func scanSinglePDF(file: String, url: URL, context: ModelContext) {
        let document = PDFKit.PDFDocument(url: url)
        let title = extractCleanTitle(document: document, fileName: file)
        let author = document?.documentAttributes?[PDFKit.PDFDocumentAttribute.authorAttribute] as? String
        let pageCount = document?.pageCount ?? 0
        let book = Book(title: title, author: author, fileName: file, totalPages: pageCount)
        context.insert(book)
    }
}

// MARK: - Errors

enum BookImportError: Error, LocalizedError {
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Формат .\(ext) не поддерживается"
        }
    }
}
