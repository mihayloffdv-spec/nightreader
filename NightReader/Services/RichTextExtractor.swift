import PDFKit
import UIKit
import CoreGraphics

// MARK: - Rich Text Extractor
//
// Parses PDF content stream via CGPDFScanner to extract text WITH formatting.
// Unlike page.string (plain text), this preserves bold, italic, font size, and
// recovers drop cap characters that PDFKit silently drops.
//
// ┌─────────────────────────────────────────────────────────┐
// │              RichTextExtractor                           │
// │                                                         │
// │  extractRichText(page) → [RichTextRun]                  │
// │    ├── CGPDFScanner with Tf/Tj/TJ/Tm/Td callbacks      │
// │    ├── Font resolver: name → bold/italic/size           │
// │    ├── ToUnicode CMap decoding (body text fonts)        │
// │    ├── Encoding/Differences decoding (special fonts)    │
// │    └── Fallback: page.string for fonts without CMap     │
// │                                                         │
// │  buildAttributedString(runs, fontSize) → NSAttrString   │
// └─────────────────────────────────────────────────────────┘

// MARK: - Data types

struct RichTextRun {
    let text: String
    let isBold: Bool
    let isItalic: Bool
    let fontSize: CGFloat    // original PDF font size
    let fontName: String     // PDF internal font name
    let position: CGPoint    // position on page (for ordering)
    let isDropCap: Bool      // from special font (may need fallback)
}

enum RichTextExtractor {

    // MARK: - Public API

    /// Extract rich text runs from a PDF page, preserving font formatting.
    static func extractRichText(from page: PDFPage) -> [RichTextRun] {
        guard let cgPage = page.pageRef else { return [] }

        let ctx = ScanContext()
        ctx.pageBounds = cgPage.getBoxRect(.mediaBox)

        guard let table = CGPDFOperatorTableCreate() else { return [] }

        // Graphics state
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            guard let info else { return }
            let c = Unmanaged<ScanContext>.fromOpaque(info).takeUnretainedValue()
            c.stateStack.append(ScanContext.State(ctm: c.ctm, fontName: c.currentFontName, fontSize: c.currentFontSize))
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            guard let info else { return }
            let c = Unmanaged<ScanContext>.fromOpaque(info).takeUnretainedValue()
            if let s = c.stateStack.popLast() {
                c.ctm = s.ctm; c.currentFontName = s.fontName; c.currentFontSize = s.fontSize
            }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let info else { return }
            let c = Unmanaged<ScanContext>.fromOpaque(info).takeUnretainedValue()
            var a: CGPDFReal = 0, b: CGPDFReal = 0, cc: CGPDFReal = 0
            var d: CGPDFReal = 0, tx: CGPDFReal = 0, ty: CGPDFReal = 0
            CGPDFScannerPopNumber(scanner, &ty); CGPDFScannerPopNumber(scanner, &tx)
            CGPDFScannerPopNumber(scanner, &d); CGPDFScannerPopNumber(scanner, &cc)
            CGPDFScannerPopNumber(scanner, &b); CGPDFScannerPopNumber(scanner, &a)
            let m = CGAffineTransform(a: a, b: b, c: cc, d: d, tx: tx, ty: ty)
            c.ctm = m.concatenating(c.ctm)
        }

        // Text state
        CGPDFOperatorTableSetCallback(table, "BT") { _, info in
            guard let info else { return }
            let c = Unmanaged<ScanContext>.fromOpaque(info).takeUnretainedValue()
            c.textMatrix = .identity; c.lineMatrix = .identity
        }

        // Tf — set font
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            guard let info else { return }
            let c = Unmanaged<ScanContext>.fromOpaque(info).takeUnretainedValue()
            var size: CGPDFReal = 0
            var namePtr: UnsafePointer<CChar>?
            CGPDFScannerPopNumber(scanner, &size)
            CGPDFScannerPopName(scanner, &namePtr)
            guard let np = namePtr else { return }
            c.currentFontName = String(cString: np)
            c.currentFontSize = CGFloat(abs(size))
            c.loadFontInfo(scanner: scanner, fontNamePtr: np)
        }

        // Tm — set text matrix
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            guard let info else { return }
            let c = Unmanaged<ScanContext>.fromOpaque(info).takeUnretainedValue()
            var a: CGPDFReal = 0, b: CGPDFReal = 0, cc: CGPDFReal = 0
            var d: CGPDFReal = 0, tx: CGPDFReal = 0, ty: CGPDFReal = 0
            CGPDFScannerPopNumber(scanner, &ty); CGPDFScannerPopNumber(scanner, &tx)
            CGPDFScannerPopNumber(scanner, &d); CGPDFScannerPopNumber(scanner, &cc)
            CGPDFScannerPopNumber(scanner, &b); CGPDFScannerPopNumber(scanner, &a)
            let m = CGAffineTransform(a: a, b: b, c: cc, d: d, tx: tx, ty: ty)
            c.textMatrix = m; c.lineMatrix = m
        }

        // Td — translate text position
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            guard let info else { return }
            let c = Unmanaged<ScanContext>.fromOpaque(info).takeUnretainedValue()
            var tx: CGPDFReal = 0, ty: CGPDFReal = 0
            CGPDFScannerPopNumber(scanner, &ty); CGPDFScannerPopNumber(scanner, &tx)
            let t = CGAffineTransform(translationX: CGFloat(tx), y: CGFloat(ty))
            c.lineMatrix = t.concatenating(c.lineMatrix)
            c.textMatrix = c.lineMatrix
        }

        // TD — same as Td
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            guard let info else { return }
            let c = Unmanaged<ScanContext>.fromOpaque(info).takeUnretainedValue()
            var tx: CGPDFReal = 0, ty: CGPDFReal = 0
            CGPDFScannerPopNumber(scanner, &ty); CGPDFScannerPopNumber(scanner, &tx)
            let t = CGAffineTransform(translationX: CGFloat(tx), y: CGFloat(ty))
            c.lineMatrix = t.concatenating(c.lineMatrix)
            c.textMatrix = c.lineMatrix
        }

        // T* — move to start of next line
        CGPDFOperatorTableSetCallback(table, "T*") { _, info in
            guard let info else { return }
            let c = Unmanaged<ScanContext>.fromOpaque(info).takeUnretainedValue()
            let t = CGAffineTransform(translationX: 0, y: -c.currentFontSize)
            c.lineMatrix = t.concatenating(c.lineMatrix)
            c.textMatrix = c.lineMatrix
        }

        // Tj — show string
        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
            guard let info else { return }
            let c = Unmanaged<ScanContext>.fromOpaque(info).takeUnretainedValue()
            var pdfStr: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &pdfStr), let s = pdfStr else { return }
            c.recordTextRun(string: s)
        }

        // TJ — show array of strings/kerning
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
            guard let info else { return }
            let c = Unmanaged<ScanContext>.fromOpaque(info).takeUnretainedValue()
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array), let arr = array else { return }
            let count = CGPDFArrayGetCount(arr)
            for i in 0..<count {
                var pdfStr: CGPDFStringRef?
                if CGPDFArrayGetString(arr, i, &pdfStr), let s = pdfStr {
                    c.recordTextRun(string: s)
                }
            }
        }

        // ' — move to next line and show string
        CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
            guard let info else { return }
            let c = Unmanaged<ScanContext>.fromOpaque(info).takeUnretainedValue()
            let t = CGAffineTransform(translationX: 0, y: -c.currentFontSize)
            c.lineMatrix = t.concatenating(c.lineMatrix)
            c.textMatrix = c.lineMatrix
            var pdfStr: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &pdfStr), let s = pdfStr else { return }
            c.recordTextRun(string: s)
        }

        // Run scanner
        let ptr = Unmanaged.passUnretained(ctx).toOpaque()
        let contentStream = CGPDFContentStreamCreateWithPage(cgPage)
        let scanner = CGPDFScannerCreate(contentStream, table, ptr)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(contentStream)

        return ctx.runs
    }

    // MARK: - Build NSAttributedString

    /// Convert rich text runs into a formatted NSAttributedString.
    /// Groups runs into paragraphs by Y-position changes.
    static func buildAttributedString(
        from runs: [RichTextRun],
        baseFontSize: CGFloat,
        bodyFontName: String,
        headlineFontName: String,
        textColor: UIColor
    ) -> NSAttributedString {
        guard !runs.isEmpty else { return NSAttributedString() }

        let result = NSMutableAttributedString()

        // Sort runs by position: top-to-bottom (descending Y in PDF coords), then left-to-right
        let sorted = runs.sorted {
            if abs($0.position.y - $1.position.y) > 2 {
                return $0.position.y > $1.position.y // higher Y = earlier in page
            }
            return $0.position.x < $1.position.x
        }

        var lastY: CGFloat = sorted.first?.position.y ?? 0
        let medianFontSize = medianSize(of: sorted)

        for run in sorted {
            // Detect paragraph break: Y changed significantly
            let yDelta = abs(run.position.y - lastY)
            if yDelta > medianFontSize * 1.5 && result.length > 0 {
                result.append(NSAttributedString(string: "\n\n"))
            } else if yDelta > medianFontSize * 0.5 && result.length > 0 {
                // Line break within same paragraph
                result.append(NSAttributedString(string: " "))
            }
            lastY = run.position.y

            // Determine if this is a heading (significantly larger than body text)
            let isHeading = run.fontSize > medianFontSize * 1.3

            // Build font
            let targetSize = isHeading ? baseFontSize * 1.5 : baseFontSize
            let fontName = isHeading ? headlineFontName : bodyFontName
            var font: UIFont

            if let customFont = UIFont(name: fontName, size: targetSize) {
                font = customFont
            } else {
                font = UIFont.systemFont(ofSize: targetSize)
            }

            // Apply bold/italic
            if run.isBold || isHeading {
                if let boldDesc = font.fontDescriptor.withSymbolicTraits(.traitBold) {
                    font = UIFont(descriptor: boldDesc, size: targetSize)
                }
            }
            if run.isItalic {
                if let italicDesc = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
                    font = UIFont(descriptor: italicDesc, size: targetSize)
                }
            }
            if run.isBold && run.isItalic {
                if let biDesc = font.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
                    font = UIFont(descriptor: biDesc, size: targetSize)
                }
            }

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = targetSize * 0.8
            paragraphStyle.alignment = .natural

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]

            result.append(NSAttributedString(string: run.text, attributes: attrs))
        }

        return result
    }

    private static func medianSize(of runs: [RichTextRun]) -> CGFloat {
        let sizes = runs.map(\.fontSize).sorted()
        guard !sizes.isEmpty else { return 12 }
        return sizes[sizes.count / 2]
    }

    // MARK: - Scan Context

    private class ScanContext {
        struct State {
            var ctm: CGAffineTransform
            var fontName: String?
            var fontSize: CGFloat
        }

        var ctm: CGAffineTransform = .identity
        var stateStack: [State] = []
        var textMatrix: CGAffineTransform = .identity
        var lineMatrix: CGAffineTransform = .identity
        var currentFontName: String?
        var currentFontSize: CGFloat = 0
        var pageBounds: CGRect = .zero
        var runs: [RichTextRun] = []

        // Font info cache
        var fontInfoCache: [String: FontInfo] = [:]
        var checkedFonts: Set<String> = []

        struct FontInfo {
            var isBold: Bool
            var isItalic: Bool
            var isSpecial: Bool // no ToUnicode, no standard encoding
            var cmap: [UInt16: String] // character mapping
        }

        func loadFontInfo(scanner: OpaquePointer?, fontNamePtr: UnsafePointer<CChar>) {
            guard let fontName = currentFontName else { return }
            if fontInfoCache[fontName] != nil || checkedFonts.contains(fontName) { return }
            checkedFonts.insert(fontName)
            guard let scanner else { return }

            let contentStream = CGPDFScannerGetContentStream(scanner)
            guard let fontObj = CGPDFContentStreamGetResource(contentStream, "Font", fontNamePtr) else { return }
            var fontDict: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(fontObj, .dictionary, &fontDict), let fd = fontDict else { return }

            // Get BaseFont name for bold/italic detection
            var baseFontPtr: UnsafePointer<CChar>?
            CGPDFDictionaryGetName(fd, "BaseFont", &baseFontPtr)
            let baseFont = baseFontPtr.map { String(cString: $0) } ?? ""
            let lower = baseFont.lowercased()
            let isBold = lower.contains("bold") || lower.contains("heavy") || lower.contains("black")
            let isItalic = lower.contains("italic") || lower.contains("oblique")

            // Try ToUnicode CMap
            var toUnicodeObj: CGPDFObjectRef?
            if CGPDFDictionaryGetObject(fd, "ToUnicode", &toUnicodeObj), let tuObj = toUnicodeObj {
                var stream: CGPDFStreamRef?
                if CGPDFObjectGetValue(tuObj, .stream, &stream), let s = stream {
                    var format: CGPDFDataFormat = .raw
                    if let data = CGPDFStreamCopyData(s, &format) {
                        let cmap = parseCMap(data as Data)
                        if !cmap.isEmpty {
                            fontInfoCache[fontName] = FontInfo(
                                isBold: isBold, isItalic: isItalic,
                                isSpecial: false, cmap: cmap
                            )
                            return
                        }
                    }
                }
            }

            // Try Encoding/Differences
            var encodingObj: CGPDFObjectRef?
            if CGPDFDictionaryGetObject(fd, "Encoding", &encodingObj), let encObj = encodingObj {
                var encDict: CGPDFDictionaryRef?
                if CGPDFObjectGetValue(encObj, .dictionary, &encDict), let ed = encDict {
                    var diffsArray: CGPDFArrayRef?
                    if CGPDFDictionaryGetArray(ed, "Differences", &diffsArray), let diffs = diffsArray {
                        let mapping = parseDifferences(diffs)
                        if !mapping.isEmpty {
                            fontInfoCache[fontName] = FontInfo(
                                isBold: isBold, isItalic: isItalic,
                                isSpecial: true, cmap: mapping
                            )
                            return
                        }
                    }
                }
            }

            // No CMap, no Differences — mark as special (drop cap likely)
            fontInfoCache[fontName] = FontInfo(
                isBold: isBold, isItalic: isItalic,
                isSpecial: true, cmap: [:]
            )
        }

        func recordTextRun(string: CGPDFStringRef) {
            guard let fontName = currentFontName else { return }
            let info = fontInfoCache[fontName] ?? FontInfo(
                isBold: false, isItalic: false, isSpecial: false, cmap: [:]
            )

            // Decode string
            let text: String
            if !info.cmap.isEmpty {
                // Use CMap
                text = decodeWithCMap(string: string, cmap: info.cmap)
            } else if !info.isSpecial {
                // Standard font — use CGPDFStringCopyTextString
                if let cfStr = CGPDFStringCopyTextString(string) {
                    text = cfStr as String
                } else {
                    return
                }
            } else {
                // Special font without mapping — try CGPDFStringCopyTextString as fallback
                if let cfStr = CGPDFStringCopyTextString(string) {
                    let str = cfStr as String
                    if !str.isEmpty {
                        text = str
                    } else {
                        return // truly undecodable
                    }
                } else {
                    return
                }
            }

            guard !text.isEmpty else { return }

            let combined = textMatrix.concatenating(ctm)
            let position = CGPoint(x: combined.tx, y: combined.ty)

            runs.append(RichTextRun(
                text: text,
                isBold: info.isBold,
                isItalic: info.isItalic,
                fontSize: currentFontSize,
                fontName: fontName,
                position: position,
                isDropCap: info.isSpecial && info.cmap.isEmpty
            ))
        }

        private func decodeWithCMap(string: CGPDFStringRef, cmap: [UInt16: String]) -> String {
            guard let bytes = CGPDFStringGetBytePtr(string) else { return "" }
            let length = CGPDFStringGetLength(string)
            guard length > 0 else { return "" }

            var result = ""
            // Try two-byte first, fall back to single-byte
            var i = 0
            while i < length {
                if i + 1 < length {
                    let twoByte = UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
                    if let char = cmap[twoByte] {
                        result += char
                        i += 2
                        continue
                    }
                }
                let oneByte = UInt16(bytes[i])
                if let char = cmap[oneByte] {
                    result += char
                } else {
                    // Fall back to CGPDFString for this segment
                    if let cfStr = CGPDFStringCopyTextString(string) {
                        return cfStr as String
                    }
                }
                i += 1
            }
            return result
        }

        // MARK: - CMap parsing (simplified)

        func parseCMap(_ data: Data) -> [UInt16: String] {
            guard let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else { return [:] }
            var mapping: [UInt16: String] = [:]

            // Parse beginbfchar/endbfchar sections
            let pattern = #"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }

            let nsStr = str as NSString
            let matches = regex.matches(in: str, range: NSRange(location: 0, length: nsStr.length))

            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                let srcHex = nsStr.substring(with: match.range(at: 1))
                let dstHex = nsStr.substring(with: match.range(at: 2))

                guard let srcCode = UInt16(srcHex, radix: 16) else { continue }

                // Decode destination: pairs of bytes → UTF-16 code units
                var unicode = ""
                var j = 0
                while j + 3 < dstHex.count {
                    let startIdx = dstHex.index(dstHex.startIndex, offsetBy: j)
                    let endIdx = dstHex.index(startIdx, offsetBy: 4)
                    if let codeUnit = UInt16(String(dstHex[startIdx..<endIdx]), radix: 16),
                       let scalar = Unicode.Scalar(codeUnit) {
                        unicode += String(scalar)
                    }
                    j += 4
                }
                if j < dstHex.count && dstHex.count - j >= 4 {
                    let startIdx = dstHex.index(dstHex.startIndex, offsetBy: j)
                    let endIdx = dstHex.index(startIdx, offsetBy: min(4, dstHex.count - j))
                    if let codeUnit = UInt16(String(dstHex[startIdx..<endIdx]), radix: 16),
                       let scalar = Unicode.Scalar(codeUnit) {
                        unicode += String(scalar)
                    }
                }

                if !unicode.isEmpty {
                    mapping[srcCode] = unicode
                }
            }

            return mapping
        }

        /// Parse Encoding/Differences array → glyph name → Unicode mapping
        func parseDifferences(_ array: CGPDFArrayRef) -> [UInt16: String] {
            let glyphNameMap: [String: String] = [
                "afii10017": "А", "afii10018": "Б", "afii10019": "В", "afii10020": "Г",
                "afii10021": "Д", "afii10022": "Е", "afii10023": "Ё", "afii10024": "Ж",
                "afii10025": "З", "afii10026": "И", "afii10027": "Й", "afii10028": "К",
                "afii10029": "Л", "afii10030": "М", "afii10031": "Н", "afii10032": "О",
                "afii10033": "П", "afii10034": "Р", "afii10035": "С", "afii10036": "Т",
                "afii10037": "У", "afii10038": "Ф", "afii10039": "Х", "afii10040": "Ц",
                "afii10041": "Ч", "afii10042": "Ш", "afii10043": "Щ", "afii10044": "Ъ",
                "afii10045": "Ы", "afii10046": "Ь", "afii10047": "Э", "afii10048": "Ю",
                "afii10049": "Я",
                "afii10065": "а", "afii10066": "б", "afii10067": "в", "afii10068": "г",
                "afii10069": "д", "afii10070": "е", "afii10071": "ё", "afii10072": "ж",
                "afii10073": "з", "afii10074": "и", "afii10075": "й", "afii10076": "к",
                "afii10077": "л", "afii10078": "м", "afii10079": "н", "afii10080": "о",
                "afii10081": "п", "afii10082": "р", "afii10083": "с", "afii10084": "т",
                "afii10085": "у", "afii10086": "ф", "afii10087": "х", "afii10088": "ц",
                "afii10089": "ч", "afii10090": "ш", "afii10091": "щ", "afii10092": "ъ",
                "afii10093": "ы", "afii10094": "ь", "afii10095": "э", "afii10096": "ю",
                "afii10097": "я",
            ]

            var mapping: [UInt16: String] = [:]
            let count = CGPDFArrayGetCount(array)
            var currentCode: UInt16 = 0

            for i in 0..<count {
                var integer: CGPDFInteger = 0
                if CGPDFArrayGetInteger(array, i, &integer) {
                    currentCode = UInt16(integer)
                    continue
                }
                var namePtr: UnsafePointer<CChar>?
                if CGPDFArrayGetName(array, i, &namePtr), let np = namePtr {
                    let name = String(cString: np)
                    if let unicode = glyphNameMap[name] {
                        mapping[currentCode] = unicode
                    } else if name.count == 1 {
                        mapping[currentCode] = name
                    }
                    currentCode += 1
                }
            }

            return mapping
        }
    }
}
