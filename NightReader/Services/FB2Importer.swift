import Foundation
import SwiftData
import UIKit

// MARK: - FB2Importer
//
// Imports .fb2 files into the app.
// Storage layout:
//   Documents/<fileName>           — original file kept here (consistent with PDF)
//   Application Support/books/fb2/<fileName> — content copy used by FB2ContentProvider
//
// .fb2.zip: decompression requires ZIPFoundation (not yet added). Import fails with
// FB2ImportError.zipNotSupported until that dependency is added (Step 7).

enum FB2ImportError: Error, LocalizedError {
    case unreadable(URL)
    case parseFailure(String?)
    case zipNotSupported

    var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            return "Не удалось открыть файл: \(url.lastPathComponent)"
        case .parseFailure(let msg):
            return "Ошибка чтения FB2: \(msg ?? "неизвестная ошибка")"
        case .zipNotSupported:
            return "Импорт .fb2.zip пока не поддерживается"
        }
    }
}

struct FB2Importer {

    // MARK: - Public entry

    static func importFB2(from sourceURL: URL, context: ModelContext) throws -> Book {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        // Handle .fb2.zip: extract the .fb2 file from the archive to a temp location
        let fb2URL: URL
        var tempExtracted: URL?
        let ext = sourceURL.pathExtension.lowercased()
        if ext == "zip" || sourceURL.lastPathComponent.lowercased().hasSuffix(".fb2.zip") {
            let zip = try MiniZip(url: sourceURL)
            guard let fb2Entry = zip.entries.first(where: {
                $0.name.lowercased().hasSuffix(".fb2") && !$0.name.contains("/")
            }) ?? zip.entries.first(where: { $0.name.lowercased().hasSuffix(".fb2") }) else {
                throw FB2ImportError.parseFailure("ZIP не содержит .fb2 файла")
            }
            let fb2Data = try zip.extract(fb2Entry)
            let tmpDir = FileManager.default.temporaryDirectory
            let tmpFile = tmpDir.appendingPathComponent((fb2Entry.name as NSString).lastPathComponent)
            try fb2Data.write(to: tmpFile, options: .atomic)
            fb2URL = tmpFile
            tempExtracted = tmpFile
        } else {
            fb2URL = sourceURL
        }
        defer { if let tmp = tempExtracted { try? FileManager.default.removeItem(at: tmp) } }

        // 1. Copy .fb2 to Documents (consistent storage with PDF)
        let docsDir = Book.documentsDirectory
        let fb2Name = (fb2URL.lastPathComponent as NSString).deletingPathExtension + ".fb2"
        let fileName = uniqueFileName(for: fb2Name, in: docsDir)
        let destDocs = docsDir.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: fb2URL, to: destDocs)

        // 2. Mirror copy to Application Support for FB2ContentProvider
        let fb2Dir = Book.applicationSupportDirectory.appendingPathComponent("books/fb2")
        try FileManager.default.createDirectory(at: fb2Dir, withIntermediateDirectories: true)
        let destAppSupport = fb2Dir.appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: destDocs, to: destAppSupport)
        } catch {
            try? FileManager.default.removeItem(at: destDocs)
            throw error
        }

        // 3. Quick metadata parse (reuses FB2ContentProvider's parser)
        let meta: (title: String?, author: String?, pageCount: Int)
        do {
            let provider = try FB2ContentProvider(url: destAppSupport)
            meta = (provider.title, provider.author, provider.pageCount)
        } catch {
            // Rollback both copies on parse failure
            try? FileManager.default.removeItem(at: destDocs)
            try? FileManager.default.removeItem(at: destAppSupport)
            throw FB2ImportError.parseFailure(error.localizedDescription)
        }

        let title = meta.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? PDFImportService.cleanFilename((fileName as NSString).deletingPathExtension)

        // 4. Persist Book
        let book = Book(
            title: title,
            author: meta.author,
            fileName: fileName,
            totalPages: meta.pageCount
        )
        book.format = .fb2

        context.insert(book)
        do {
            try context.save()
        } catch {
            try? FileManager.default.removeItem(at: destDocs)
            try? FileManager.default.removeItem(at: destAppSupport)
            throw error
        }

        return book
    }

    // MARK: - Helpers

    private static func uniqueFileName(for original: String, in directory: URL) -> String {
        var name = original
        var counter = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            let stem = (original as NSString).deletingPathExtension
            let ext  = (original as NSString).pathExtension
            name = "\(stem)_\(counter).\(ext)"
            counter += 1
        }
        return name
    }
}

// MARK: - String helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
