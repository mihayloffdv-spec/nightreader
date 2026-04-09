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

        let documentsDir = Book.documentsDirectory
        let fileName = uniqueFileName(for: sourceURL.lastPathComponent, in: documentsDir)
        let destURL = documentsDir.appendingPathComponent(fileName)

        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        let document = PDFDocument(url: destURL)
        let title = extractCleanTitle(document: document, fileName: fileName)
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
        let documentsDir = Book.documentsDirectory
        let existingBooks = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let trackedFiles = Set(existingBooks.map(\.fileName))

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: documentsDir.path) else { return }
        for file in files where file.hasSuffix(".pdf") && !trackedFiles.contains(file) {
            let url = documentsDir.appendingPathComponent(file)
            let document = PDFDocument(url: url)
            let title = extractCleanTitle(document: document, fileName: file)
            let author = document?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
            let pageCount = document?.pageCount ?? 0

            let book = Book(title: title, author: author, fileName: file, totalPages: pageCount)
            context.insert(book)
        }
        try? context.save()
    }

    /// Extract a readable book title. Prefers PDF metadata, but falls back to
    /// cleaning the filename (strip extension, underscores, trailing numeric IDs).
    /// Rejects metadata titles that look like garbage (filename copies, empty, single chars).
    static func extractCleanTitle(document: PDFDocument?, fileName: String) -> String {
        let metadataTitle = (document?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileStem = (fileName as NSString).deletingPathExtension

        // Reject garbage metadata: empty, untitled, just whitespace, or identical to filename stem
        if let meta = metadataTitle,
           !meta.isEmpty,
           meta.count >= 3,
           meta.lowercased() != "untitled",
           !meta.lowercased().hasPrefix("microsoft word"),
           meta != fileStem,
           !meta.contains("_") || meta.contains(" ") {
            return meta
        }

        return cleanFilename(fileStem)
    }

    /// Turn `Gipersegmentatsija_Trafika_53843917` into `Gipersegmentatsija Trafika`.
    static func cleanFilename(_ stem: String) -> String {
        // Replace underscores and dashes with spaces
        var cleaned = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        // Strip trailing numeric IDs (e.g. " 53843917" at the end)
        while let last = cleaned.split(separator: " ").last,
              last.count >= 5,
              last.allSatisfy({ $0.isNumber }) {
            cleaned = cleaned.split(separator: " ").dropLast().joined(separator: " ")
        }

        // Collapse multiple spaces
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? stem : cleaned
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
