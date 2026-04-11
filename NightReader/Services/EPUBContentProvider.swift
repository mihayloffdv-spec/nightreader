import Foundation
import UIKit

// MARK: - EPUBContentProvider
//
// Reads a pre-extracted EPUB directory (produced by EPUBImporter).
// Parses metadata and spine on init (parse-once). Content blocks
// are parsed on demand per page (XHTML → PositionedBlock).
//
// "Page" = one spine item (XHTML file), indexed by position in <spine>.

final class EPUBContentProvider: BookContentProvider {
    let format: BookFormat = .epub

    private let _title: String?
    private let _author: String?
    private let _cover: UIImage?
    private let spineURLs: [URL]
    private let spineTitles: [String?]
    private let baseDir: URL

    var pageCount: Int { spineURLs.count }
    var title: String? { _title }
    var author: String? { _author }
    var cover: UIImage? { _cover }

    var outline: [Chapter] {
        spineTitles.enumerated().compactMap { idx, maybeTitle in
            guard let t = maybeTitle, !t.isEmpty else { return nil }
            return Chapter(id: idx, title: t, pageIndex: idx,
                           level: 0, source: .formatNative, contentHash: nil)
        }
    }

    // MARK: - Init

    init(directory: URL) throws {
        self.baseDir = directory
        let epub = try EPUBDirectoryParser(directory: directory)
        self._title      = epub.title
        self._author     = epub.author
        self._cover      = epub.coverImage
        self.spineURLs   = epub.spineURLs
        self.spineTitles = epub.spineTitles
    }

    // MARK: - Protocol

    func contentBlocks(forPage index: Int) async throws -> [PositionedBlock] {
        guard index >= 0 && index < spineURLs.count else { return [] }
        let url = spineURLs[index]
        let xhtml = try String(contentsOf: url, encoding: .utf8)
        return XHTMLBlockParser.parse(xhtml: xhtml, pageIndex: index)
    }

    func plainText(forPage index: Int) async throws -> String {
        guard index >= 0 && index < spineURLs.count else { return "" }
        let url = spineURLs[index]
        let xhtml = try String(contentsOf: url, encoding: .utf8)
        return XHTMLBlockParser.plainText(from: xhtml)
    }
}

// MARK: - EPUBContentProviderError

enum EPUBContentProviderError: Error, LocalizedError {
    case missingContainerXML(URL)
    case missingOPF(String)
    case parseFailure(String?)

    var errorDescription: String? {
        switch self {
        case .missingContainerXML(let dir): return "container.xml не найден в \(dir.lastPathComponent)"
        case .missingOPF(let p):            return "OPF не найден: \(p)"
        case .parseFailure(let msg):        return "Ошибка разбора EPUB: \(msg ?? "неизвестная ошибка")"
        }
    }
}

// MARK: - EPUBDirectoryParser (parse-once)

private final class EPUBDirectoryParser {
    var title: String?
    var author: String?
    var coverImage: UIImage?
    var spineURLs: [URL] = []
    var spineTitles: [String?] = []

    init(directory: URL) throws {
        // 1. container.xml → OPF path
        let containerURL = directory.appendingPathComponent("META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            throw EPUBContentProviderError.missingContainerXML(directory)
        }
        let containerData = try Data(contentsOf: containerURL)
        let opfRelPath = try EPUBDirectoryParser.parseContainerXML(containerData)

        // 2. OPF → manifest, spine, metadata
        let opfURL = directory.appendingPathComponent(opfRelPath)
        guard FileManager.default.fileExists(atPath: opfURL.path) else {
            throw EPUBContentProviderError.missingOPF(opfRelPath)
        }
        let opfData = try Data(contentsOf: opfURL)
        let opfDir  = opfURL.deletingLastPathComponent()
        let opf     = try EPUBDirectoryParser.parseOPF(opfData)

        self.title  = opf.title
        self.author = opf.author

        // 3. Resolve spine URLs
        var urls: [URL] = []
        for idref in opf.spineItemRefs {
            if let href = opf.manifest[idref] {
                let resolved = opfDir.appendingPathComponent(href).standardized
                if FileManager.default.fileExists(atPath: resolved.path) {
                    urls.append(resolved)
                }
            }
        }
        self.spineURLs = urls

        // 4. Titles from NCX or nav.xhtml
        var titles: [String?] = Array(repeating: nil, count: urls.count)
        if let ncxHref = opf.ncxHref {
            let ncxURL = opfDir.appendingPathComponent(ncxHref)
            if let ncxData = try? Data(contentsOf: ncxURL) {
                let map = EPUBDirectoryParser.parseNCX(ncxData, opfDir: opfDir)
                for (i, url) in urls.enumerated() {
                    let key = url.lastPathComponent
                    titles[i] = map[key]
                }
            }
        }
        self.spineTitles = titles

        // 5. Cover image
        if let coverHref = opf.coverImageHref {
            let coverURL = opfDir.appendingPathComponent(coverHref).standardized
            if let data = try? Data(contentsOf: coverURL) {
                self.coverImage = UIImage(data: data)
            }
        }
    }

    // MARK: - container.xml

    private static func parseContainerXML(_ data: Data) throws -> String {
        let p = ContainerParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.parse()
        guard let path = p.opfPath else {
            throw EPUBContentProviderError.parseFailure("container.xml missing rootfile/@full-path")
        }
        return path
    }

    // MARK: - OPF

    private struct OPFData {
        var title: String?
        var author: String?
        var manifest: [String: String]    // id → href
        var spineItemRefs: [String]
        var ncxHref: String?
        var coverImageHref: String?
    }

    private static func parseOPF(_ data: Data) throws -> OPFData {
        let p = OPFSAXParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.parse()

        // Resolve cover image href
        var coverHref: String?
        if let coverId = p.coverItemId, let href = p.manifest[coverId] {
            let mt = p.manifestTypes[coverId] ?? ""
            if mt.hasPrefix("image/") { coverHref = href }
        }
        // Resolve NCX href
        let ncxHref: String? = {
            if let ncxId = p.ncxId, let href = p.manifest[ncxId] { return href }
            // EPUB3: look for nav item
            for (id, mt) in p.manifestTypes where mt == "application/xhtml+xml" {
                if let props = p.manifestProps[id], props.contains("nav") {
                    return p.manifest[id]
                }
            }
            return nil
        }()

        return OPFData(title: p.title, author: p.author,
                       manifest: p.manifest, spineItemRefs: p.spineItemRefs,
                       ncxHref: ncxHref, coverImageHref: coverHref)
    }

    // MARK: - NCX

    /// Returns filename (last path component) → navLabel text mapping.
    private static func parseNCX(_ data: Data, opfDir: URL) -> [String: String] {
        let p = NCXSAXParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.parse()
        var result: [String: String] = [:]
        for point in p.navPoints {
            if let src = point.src {
                // src may contain anchor: "chapter1.xhtml#section1" → "chapter1.xhtml"
                let file = src.components(separatedBy: "#").first ?? src
                let key = (file as NSString).lastPathComponent
                result[key] = point.label
            }
        }
        return result
    }
}

// MARK: - SAX parsers

private final class ContainerParser: NSObject, XMLParserDelegate {
    var opfPath: String?
    func parser(_ parser: XMLParser, didStartElement el: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        if local(qName ?? el) == "rootfile" { opfPath = attributes["full-path"] }
    }
    private func local(_ s: String) -> String { s.components(separatedBy: ":").last ?? s }
}

private final class OPFSAXParser: NSObject, XMLParserDelegate {
    var title: String?
    var author: String?
    var manifest: [String: String] = [:]       // id → href
    var manifestTypes: [String: String] = [:]  // id → media-type
    var manifestProps: [String: String] = [:]  // id → properties
    var spineItemRefs: [String] = []
    var coverItemId: String?
    var ncxId: String?

    private var text = ""
    private var inMeta = false
    private var inSpine = false

    func parser(_ parser: XMLParser, didStartElement el: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        let name = local(qName ?? el)
        switch name {
        case "metadata": inMeta  = true
        case "spine":    inSpine = true; ncxId = attributes["toc"]
        case "item":
            if let id = attributes["id"], let href = attributes["href"] {
                manifest[id] = href
                manifestTypes[id] = attributes["media-type"] ?? ""
                if let props = attributes["properties"] { manifestProps[id] = props }
            }
        case "itemref":
            if inSpine, let idref = attributes["idref"] { spineItemRefs.append(idref) }
        case "meta":
            if inMeta {
                let n = attributes["name"] ?? ""
                let c = attributes["content"] ?? ""
                if n == "cover" { coverItemId = c }
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }

    func parser(_ parser: XMLParser, didEndElement el: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = local(qName ?? el)
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title":    if inMeta && title  == nil { title  = t.nilIfEmpty }
        case "creator":  if inMeta && author == nil { author = t.nilIfEmpty }
        case "metadata": inMeta  = false
        case "spine":    inSpine = false
        default: break
        }
        text = ""
    }

    private func local(_ s: String) -> String { s.components(separatedBy: ":").last ?? s }
}

private struct NavPoint {
    var label: String?
    var src: String?
}

private final class NCXSAXParser: NSObject, XMLParserDelegate {
    var navPoints: [NavPoint] = []
    private var current = NavPoint()
    private var inNavLabel = false
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement el: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        let name = local(qName ?? el)
        switch name {
        case "navPoint":  current = NavPoint()
        case "navLabel":  inNavLabel = true
        case "content":   current.src = attributes["src"]
        case "a":         if current.src == nil { current.src = attributes["href"] }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }

    func parser(_ parser: XMLParser, didEndElement el: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = local(qName ?? el)
        switch name {
        case "text":
            if inNavLabel { current.label = text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        case "navLabel":  inNavLabel = false
        case "navPoint":  navPoints.append(current)
        case "li":
            // EPUB3 nav
            if current.label != nil || current.src != nil { navPoints.append(current) }
            current = NavPoint()
        default: break
        }
        text = ""
    }

    private func local(_ s: String) -> String { s.components(separatedBy: ":").last ?? s }
}

// MARK: - XHTML block parser

private enum XHTMLBlockParser {

    /// Heading elements
    private static let headingTags: Set<String> = ["h1","h2","h3","h4","h5","h6","title"]
    /// Block-level elements that delimit paragraphs
    private static let blockTags:   Set<String> = ["p","div","section","article","blockquote",
                                                     "li","dt","dd","caption","td","th","pre"]

    static func parse(xhtml: String, pageIndex: Int) -> [PositionedBlock] {
        let normalized = preprocess(xhtml)
        guard let data = normalized.data(using: .utf8) else { return [] }

        let delegate = BlockCollector()
        let xml = XMLParser(data: data)
        xml.delegate = delegate
        xml.shouldProcessNamespaces = false
        xml.parse()

        var blocks: [PositionedBlock] = []
        var offset = 0
        for (tag, raw) in delegate.blocks {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let kind: ContentBlock = headingTags.contains(tag) ? .heading(text) : .text(text)
            let len = text.utf16.count
            blocks.append(PositionedBlock(
                id: "\(pageIndex)-\(offset)",
                startCharOffset: offset,
                endCharOffset: offset + len,
                content: kind
            ))
            offset += len + 1
        }
        return blocks
    }

    static func plainText(from xhtml: String) -> String {
        let normalized = preprocess(xhtml)
        guard let data = normalized.data(using: .utf8) else { return "" }
        let delegate = BlockCollector()
        let xml = XMLParser(data: data)
        xml.delegate = delegate
        xml.shouldProcessNamespaces = false
        xml.parse()
        return delegate.blocks
            .map { $0.1.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Preprocessing

    /// Normalise XHTML so XMLParser doesn't choke on common HTML entities and doctypes.
    private static func preprocess(_ xhtml: String) -> String {
        var s = xhtml

        // Strip doctype declarations
        if let r = s.range(of: "<!DOCTYPE", options: .caseInsensitive),
           let end = s[r.lowerBound...].range(of: ">") {
            s.removeSubrange(r.lowerBound ..< end.upperBound)
        }

        // Replace named HTML entities not defined in XML.
        // Full map covers Latin-1 supplement + common typography.
        let entities: [String: String] = [
            "nbsp": "\u{00A0}", "iexcl": "¡", "cent": "¢", "pound": "£",
            "curren": "¤", "yen": "¥", "brvbar": "¦", "sect": "§",
            "uml": "¨", "copy": "©", "ordf": "ª", "laquo": "«",
            "not": "¬", "shy": "\u{00AD}", "reg": "®", "macr": "¯",
            "deg": "°", "plusmn": "±", "sup2": "²", "sup3": "³",
            "acute": "´", "micro": "µ", "para": "¶", "middot": "·",
            "cedil": "¸", "sup1": "¹", "ordm": "º", "raquo": "»",
            "frac14": "¼", "frac12": "½", "frac34": "¾", "iquest": "¿",
            "Agrave": "À", "Aacute": "Á", "Acirc": "Â", "Atilde": "Ã",
            "Auml": "Ä", "Aring": "Å", "AElig": "Æ", "Ccedil": "Ç",
            "Egrave": "È", "Eacute": "É", "Ecirc": "Ê", "Euml": "Ë",
            "Igrave": "Ì", "Iacute": "Í", "Icirc": "Î", "Iuml": "Ï",
            "ETH": "Ð", "Ntilde": "Ñ", "Ograve": "Ò", "Oacute": "Ó",
            "Ocirc": "Ô", "Otilde": "Õ", "Ouml": "Ö", "times": "×",
            "Oslash": "Ø", "Ugrave": "Ù", "Uacute": "Ú", "Ucirc": "Û",
            "Uuml": "Ü", "Yacute": "Ý", "THORN": "Þ", "szlig": "ß",
            "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã",
            "auml": "ä", "aring": "å", "aelig": "æ", "ccedil": "ç",
            "egrave": "è", "eacute": "é", "ecirc": "ê", "euml": "ë",
            "igrave": "ì", "iacute": "í", "icirc": "î", "iuml": "ï",
            "eth": "ð", "ntilde": "ñ", "ograve": "ò", "oacute": "ó",
            "ocirc": "ô", "otilde": "õ", "ouml": "ö", "divide": "÷",
            "oslash": "ø", "ugrave": "ù", "uacute": "ú", "ucirc": "û",
            "uuml": "ü", "yacute": "ý", "thorn": "þ", "yuml": "ÿ",
            "mdash": "—", "ndash": "–", "hellip": "…",
            "lsquo": "\u{2018}", "rsquo": "\u{2019}",
            "ldquo": "\u{201C}", "rdquo": "\u{201D}",
            "bull": "•", "trade": "™", "dagger": "†", "Dagger": "‡",
            "permil": "‰", "lsaquo": "‹", "rsaquo": "›",
            "euro": "€", "thinsp": "\u{2009}", "ensp": "\u{2002}", "emsp": "\u{2003}",
        ]
        // Replace known named entities with their Unicode equivalents
        for (name, value) in entities {
            s = s.replacingOccurrences(of: "&\(name);", with: value)
        }
        // Any remaining unknown named entities: replace with space to preserve word boundaries
        s = s.replacingOccurrences(of: #"&[a-zA-Z][a-zA-Z0-9]*;"#,
                                   with: " ", options: .regularExpression)

        // Wrap in a root element if needed (bare XHTML body fragments)
        if !s.contains("<html") && !s.contains("<body") {
            s = "<root>\(s)</root>"
        }
        return s
    }
}

// MARK: - BlockCollector (SAX)

private final class BlockCollector: NSObject, XMLParserDelegate {
    var blocks: [(String, String)] = []  // (tag, accumulated text)

    private static let blockTags:   Set<String> = ["p","div","section","article","blockquote",
                                                     "li","dt","dd","caption","td","th","pre",
                                                     "h1","h2","h3","h4","h5","h6"]
    private static let ignoredTags: Set<String> = ["style","script","head","meta","link"]

    private var tagStack: [String] = []
    private var textStack: [String] = [""]
    private var ignored = 0

    func parser(_ parser: XMLParser, didStartElement el: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        let tag = (qName ?? el).lowercased().components(separatedBy: ":").last ?? el.lowercased()
        tagStack.append(tag)
        if BlockCollector.ignoredTags.contains(tag) { ignored += 1 }
        if BlockCollector.blockTags.contains(tag) { textStack.append("") }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) {
        guard ignored == 0, !textStack.isEmpty else { return }
        textStack[textStack.count - 1] += s
    }

    func parser(_ parser: XMLParser, didEndElement el: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let tag = (qName ?? el).lowercased().components(separatedBy: ":").last ?? el.lowercased()
        if BlockCollector.ignoredTags.contains(tag) { ignored = max(0, ignored - 1) }
        if BlockCollector.blockTags.contains(tag), textStack.count > 1 {
            let text = textStack.removeLast()
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append((tag, text))
            }
        }
        if !tagStack.isEmpty { tagStack.removeLast() }
    }
}

// MARK: - String helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
