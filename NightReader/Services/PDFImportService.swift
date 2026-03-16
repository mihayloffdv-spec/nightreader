import Foundation
import PDFKit
import SwiftData
import UIKit

struct PDFImportService {

    static func importPDF(from sourceURL: URL, context: ModelContext) throws -> Book {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = uniqueFileName(for: sourceURL.lastPathComponent, in: documentsDir)
        let destURL = documentsDir.appendingPathComponent(fileName)

        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        let document = PDFDocument(url: destURL)
        let title = document?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
            ?? sourceURL.deletingPathExtension().lastPathComponent
        let author = document?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
        let pageCount = document?.pageCount ?? 0

        let book = Book(
            title: title,
            author: author,
            fileName: fileName,
            totalPages: pageCount
        )
        context.insert(book)
        do {
            try context.save()
        } catch {
            try? FileManager.default.removeItem(at: destURL)
            throw error
        }

        return book
    }

    /// Scans Documents for PDFs not yet tracked in SwiftData (useful for testing)
    static func scanForUntrackedPDFs(context: ModelContext) {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let existingBooks = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let trackedFiles = Set(existingBooks.map(\.fileName))

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: documentsDir.path) else { return }
        for file in files where file.hasSuffix(".pdf") && !trackedFiles.contains(file) {
            let url = documentsDir.appendingPathComponent(file)
            let document = PDFDocument(url: url)
            let title = document?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
                ?? (file as NSString).deletingPathExtension
            let author = document?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
            let pageCount = document?.pageCount ?? 0

            let book = Book(title: title, author: author, fileName: file, totalPages: pageCount)
            context.insert(book)
        }
        try? context.save()
    }

    private static func uniqueFileName(for original: String, in directory: URL) -> String {
        var name = original
        var counter = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            let stem = (original as NSString).deletingPathExtension
            let ext = (original as NSString).pathExtension
            name = "\(stem)_\(counter).\(ext)"
            counter += 1
        }
        return name
    }
}
