import Foundation
import UIKit

// MARK: - FB2ContentProvider
//
// Parses FB2 XML once at init, stores all sections in memory.
// contentBlocks(forPage:) is O(1) lookup — no re-parsing per call.
//
// "Page" = top-level <section> index in <body>.
//
// FB2 structure:
//   <FictionBook>
//     <description><title-info> — metadata
//     <body>
//       <section>          ← page 0
//         <title><p>…</p></title>
//         <p>…</p>
//       </section>
//         <section>        ← page 1
//         …
//       </section>
//     </body>
//     <binary id="cover.jpg" …>BASE64</binary>
//   </FictionBook>

final class FB2ContentProvider: BookContentProvider {
    let format: BookFormat = .fb2

    private let _title: String?
    private let _author: String?
    private let _cover: UIImage?
    private let sections: [[PositionedBlock]]   // index → blocks (parse-once)
    private let sectionTitles: [String?]         // parallel to sections

    var pageCount: Int { sections.count }
    var title: String? { _title }
    var author: String? { _author }
    var cover: UIImage? { _cover }

    var outline: [Chapter] {
        sectionTitles.enumerated().compactMap { idx, maybeTitle in
            guard let t = maybeTitle, !t.isEmpty else { return nil }
            return Chapter(
                id: idx,
                title: t,
                pageIndex: idx,
                level: 0,
                source: .formatNative,
                contentHash: nil
            )
        }
    }

    // MARK: - Init

    init(url: URL) throws {
        let parser = FB2Parser()
        try parser.parse(url: url)

        self._title = parser.title
        self._author = parser.author
        self._cover = parser.coverImage
        self.sections = parser.sections
        self.sectionTitles = parser.sectionTitles
    }

    // MARK: - Protocol

    func contentBlocks(forPage index: Int) async throws -> [PositionedBlock] {
        guard index >= 0 && index < sections.count else { return [] }
        return sections[index]
    }

    func plainText(forPage index: Int) async throws -> String {
        guard index >= 0 && index < sections.count else { return "" }
        return sections[index].compactMap { block in
            switch block.content {
            case .text(let s), .heading(let s): return s
            case .richText(let a): return a.string
            case .image, .snapshot: return nil
            }
        }.joined(separator: " ")
    }
}

// MARK: - FB2 Error

enum FB2ContentProviderError: Error, LocalizedError {
    case parseFailure(String?)
    case unreadable(URL)

    var errorDescription: String? {
        switch self {
        case .parseFailure(let msg):
            return "Ошибка чтения FB2: \(msg ?? "неизвестная ошибка")"
        case .unreadable(let url):
            return "Не удалось открыть файл: \(url.lastPathComponent)"
        }
    }
}

// MARK: - FB2Parser (SAX, parse-once)

private final class FB2Parser: NSObject, XMLParserDelegate {

    // Results
    var title: String?
    var author: String?
    var coverImage: UIImage?
    var sections: [[PositionedBlock]] = []
    var sectionTitles: [String?] = []

    // Parse state
    private var currentPath: [String] = []
    private var currentText = ""
    private var inBody = false
    private var inTitle = false         // <title> inside section
    private var inDescription = false
    private var sectionDepth = 0        // top-level sections only

    // Cover
    private var coverBinaryId: String?
    private var binaryId: String?
    private var binaryContentType: String?
    private var binaryBuffer = ""
    private var inBinary = false

    // Per-section accumulation
    private var currentSectionBlocks: [PositionedBlock] = []
    private var currentSectionTitle: String?
    private var currentCharOffset = 0
    private var currentSectionIndex = 0

    // Author accumulation
    private var firstName = ""
    private var lastName = ""
    private var middleName = ""

    // MARK: - Public entry

    func parse(url: URL) throws {
        guard let parser = XMLParser(contentsOf: url) else {
            throw FB2ContentProviderError.unreadable(url)
        }
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        if !parser.parse() {
            throw FB2ContentProviderError.parseFailure(parser.parserError?.localizedDescription)
        }
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes: [String: String] = [:]) {

        let name = localName(elementName, qName: qName)
        currentPath.append(name)

        // Only reset text for block-level elements. Inline tags like <emphasis>,
        // <strong>, <a>, <strikethrough> must NOT reset — they appear inside <p>.
        let blockTags: Set<String> = [
            "body", "description", "section", "title", "p", "v", "subtitle",
            "coverpage", "image", "binary", "book-title", "first-name",
            "middle-name", "last-name", "author"
        ]
        if blockTags.contains(name) {
            currentText = ""
        }

        switch name {
        case "body":
            inBody = true
        case "description":
            inDescription = true
        case "section":
            if inBody {
                sectionDepth += 1
                if sectionDepth == 1 {
                    // Start a new top-level section
                    currentSectionBlocks = []
                    currentSectionTitle = nil
                    currentCharOffset = 0
                }
            }
        case "title":
            if inBody && sectionDepth >= 1 {
                inTitle = true
            }
        case "coverpage":
            break  // children handled by image tag
        case "image":
            if inDescription {
                // coverpage image reference
                let href = attributes["href"] ?? attributes["l:href"] ?? ""
                coverBinaryId = href.hasPrefix("#") ? String(href.dropFirst()) : href
            }
        case "binary":
            binaryId = attributes["id"]
            binaryContentType = attributes["content-type"]
            binaryBuffer = ""
            inBinary = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inBinary {
            binaryBuffer += string
        } else {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {

        let name = localName(elementName, qName: qName)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "book-title":
            if inDescription { title = text }
        case "first-name":
            if inDescription { firstName = text }
        case "middle-name":
            if inDescription { middleName = text }
        case "last-name":
            if inDescription { lastName = text }
        case "author":
            if inDescription {
                var parts = [firstName, middleName, lastName].filter { !$0.isEmpty }
                author = parts.joined(separator: " ")
                firstName = ""; middleName = ""; lastName = ""
            }
        case "description":
            inDescription = false
        case "body":
            inBody = false
        case "title":
            if inBody && inTitle {
                currentSectionTitle = text.isEmpty ? nil : text
                inTitle = false
                // Heading block
                if !text.isEmpty {
                    let block = PositionedBlock(
                        id: "\(currentSectionIndex)-\(currentCharOffset)",
                        startCharOffset: currentCharOffset,
                        endCharOffset: currentCharOffset + text.utf16.count,
                        content: .heading(text)
                    )
                    currentSectionBlocks.append(block)
                    currentCharOffset += text.utf16.count + 1 // +1 for separator
                }
            }
        case "p", "v", "subtitle":
            if inBody && sectionDepth >= 1 && !text.isEmpty {
                let block = PositionedBlock(
                    id: "\(currentSectionIndex)-\(currentCharOffset)",
                    startCharOffset: currentCharOffset,
                    endCharOffset: currentCharOffset + text.utf16.count,
                    content: inTitle ? .heading(text) : .text(text)
                )
                currentSectionBlocks.append(block)
                currentCharOffset += text.utf16.count + 1
            }
        case "section":
            if inBody {
                if sectionDepth == 1 {
                    // Commit the top-level section
                    sections.append(currentSectionBlocks)
                    sectionTitles.append(currentSectionTitle)
                    currentSectionIndex += 1
                }
                sectionDepth -= 1
            }
        case "binary":
            if inBinary, let bid = binaryId {
                if bid == coverBinaryId {
                    let clean = binaryBuffer
                        .components(separatedBy: .whitespacesAndNewlines)
                        .joined()
                    if let data = Data(base64Encoded: clean) {
                        coverImage = UIImage(data: data)
                    }
                }
                inBinary = false
                binaryId = nil
                binaryBuffer = ""
            }
        default:
            break
        }

        currentText = ""
        if !currentPath.isEmpty { currentPath.removeLast() }
    }

    // MARK: - Helpers

    /// Strip namespace prefix (e.g. "l:href" → "href", or use localName from parser).
    private func localName(_ elementName: String, qName: String?) -> String {
        // XMLParser with shouldProcessNamespaces=true gives us the local name in elementName
        return elementName
    }
}
