import Foundation
import SwiftData
import UIKit

// MARK: - EPUBImporter
//
// Imports .epub files into the app.
// Storage layout:
//   Documents/<fileName>                            — original .epub (consistent with PDF/FB2)
//   Application Support/books/epub/{book.id}/       — extracted EPUB directory
//     META-INF/container.xml
//     <OPF-dir>/content.opf (or package.opf, etc.)
//     <OPF-dir>/<chapters>.xhtml
//
// EPUBContentProvider reads from the extracted directory at book.contentURL.

// MARK: - Errors

enum EPUBImportError: Error, LocalizedError {
    case notAnEPUB
    case missingContainerXML
    case missingOPF(String)
    case parseFailure(String?)

    var errorDescription: String? {
        switch self {
        case .notAnEPUB:               return "Файл не является EPUB"
        case .missingContainerXML:     return "В EPUB отсутствует META-INF/container.xml"
        case .missingOPF(let path):    return "OPF файл не найден: \(path)"
        case .parseFailure(let msg):   return "Ошибка разбора EPUB: \(msg ?? "неизвестная ошибка")"
        }
    }
}

// MARK: - EPUBImporter

struct EPUBImporter {

    static func importEPUB(from sourceURL: URL, context: ModelContext) throws -> Book {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        guard sourceURL.pathExtension.lowercased() == "epub" else {
            throw EPUBImportError.notAnEPUB
        }

        // 1. Open the ZIP archive
        let zip = try MiniZip(url: sourceURL)

        // 2. Quick metadata parse directly from ZIP entries (no full extraction yet)
        let meta = try parseMetadata(from: zip)

        // 3. Copy original to Documents
        let docsDir = Book.documentsDirectory
        let fileName = uniqueFileName(for: sourceURL.lastPathComponent, in: docsDir)
        let destDocs = docsDir.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destDocs)

        // 4. Create Book to get its stable UUID (used as directory name)
        let title = meta.title?.nilIfEmpty
            ?? PDFImportService.cleanFilename((fileName as NSString).deletingPathExtension)
        let book = Book(
            title: title,
            author: meta.author,
            fileName: fileName,
            totalPages: meta.spineCount
        )
        book.format = .epub

        // 5. Extract all EPUB content to Application Support under book.id
        let destDir = book.contentURL   // = .../books/epub/{uuid}/
        do {
            try zip.extractAll(to: destDir)
        } catch {
            try? FileManager.default.removeItem(at: destDocs)
            try? FileManager.default.removeItem(at: destDir)
            throw error
        }

        // 6. Persist
        context.insert(book)
        do {
            try context.save()
        } catch {
            try? FileManager.default.removeItem(at: destDocs)
            try? FileManager.default.removeItem(at: destDir)
            throw error
        }

        return book
    }

    // MARK: - Metadata from ZIP

    private struct Metadata {
        var title: String?
        var author: String?
        var spineCount: Int
    }

    private static func parseMetadata(from zip: MiniZip) throws -> Metadata {
        // container.xml → OPF path
        guard let containerData = try zip.extract(named: "META-INF/container.xml") else {
            throw EPUBImportError.missingContainerXML
        }
        let opfPath = try parseContainerXML(containerData)

        // OPF → title, author, spine
        guard let opfData = try zip.extract(named: opfPath) else {
            throw EPUBImportError.missingOPF(opfPath)
        }
        let opf = try parseOPF(opfData)

        return Metadata(title: opf.title, author: opf.author, spineCount: opf.spineCount)
    }

    // MARK: - container.xml

    /// Returns the rootfile full-path attribute from META-INF/container.xml
    private static func parseContainerXML(_ data: Data) throws -> String {
        let parser = ContainerXMLParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        guard let path = parser.opfPath else {
            throw EPUBImportError.parseFailure("container.xml не содержит rootfile/@full-path")
        }
        return path
    }

    // MARK: - OPF

    private struct OPFResult {
        var title: String?
        var author: String?
        var spineCount: Int
    }

    private static func parseOPF(_ data: Data) throws -> OPFResult {
        let parser = OPFParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return OPFResult(title: parser.title, author: parser.author,
                         spineCount: parser.spineItemRefs.count)
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

// MARK: - container.xml SAX parser

private final class ContainerXMLParser: NSObject, XMLParserDelegate {
    var opfPath: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        let name = (qName ?? elementName).components(separatedBy: ":").last ?? elementName
        if name == "rootfile" {
            opfPath = attributes["full-path"]
        }
    }
}

// MARK: - OPF SAX parser

private final class OPFParser: NSObject, XMLParserDelegate {
    var title: String?
    var author: String?
    var spineItemRefs: [String] = []

    // Manifest: id → href
    private var manifest: [String: String] = [:]
    private var currentText = ""
    private var inMetadata = false
    private var inSpine = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        let name = local(qName ?? elementName)
        currentText = ""
        switch name {
        case "metadata": inMetadata = true
        case "spine":    inSpine    = true
        case "item":
            if let id = attributes["id"], let href = attributes["href"] {
                manifest[id] = href
            }
        case "itemref":
            if inSpine, let idref = attributes["idref"] {
                spineItemRefs.append(idref)
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = local(qName ?? elementName)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title":   if inMetadata && title  == nil { title  = text.nilIfEmpty }
        case "creator": if inMetadata && author == nil { author = text.nilIfEmpty }
        case "metadata": inMetadata = false
        case "spine":    inSpine    = false
        default: break
        }
        currentText = ""
    }

    private func local(_ qName: String) -> String {
        qName.components(separatedBy: ":").last ?? qName
    }
}

// MARK: - String helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
