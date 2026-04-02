import PDFKit
import UIKit
import CoreGraphics
import Vision

// MARK: - Text Extractor
//
// Extracts and processes text from PDF pages:
// - Line extraction via PDFSelection API
// - Paragraph splitting and dehyphenation
// - Drop cap recovery (CMap parsing + OCR fallback + dictionary)
// - Diagnostics for debugging text quality
//
// ┌──────────────────────────────────────────────────────┐
// │                  TextExtractor                        │
// │                                                      │
// │  extractTextLines(page) → [(bounds, text)]           │
// │  splitIntoParagraphs(text) → [String]                │
// │  recoverDropCaps(pageString, lines, page) → String   │
// │    ├── Strategy 1: CMap font decoding                │
// │    ├── Strategy 2: OCR (render page → crop → Vision) │
// │    └── Strategy 3: Dictionary-based fragment repair   │
// │  diagnoseDropCaps(document) → report                 │
// └──────────────────────────────────────────────────────┘

enum TextExtractor {

    // MARK: - Shared constants

    /// Consonant clusters that can start a valid Russian word.
    /// Used by fragment detection (diagnostics + live recovery) to identify truncated words.
    private static let validRussianConsonantStarts: Set<String> = [
        // Two-letter clusters:
        "бл", "бр",
        "вб", "вв", "вг", "вд", "вз", "вк", "вл", "вм", "вн", "вп", "вр", "вс", "вт", "вх", "вц", "вч", "вш",
        "гл", "гн", "гр",
        "дв", "дл", "дн", "др",
        "жг", "жд", "жж", "жм", "жр",
        "зб", "зв", "зг", "зд", "зл", "зм", "зн", "зр",
        "кв", "кл", "кн", "кр", "кс",
        "лж", "лл", "льн",
        "мг", "мл", "мн", "мр", "мс", "мш",
        "пл", "пн", "пр", "пс", "пт", "пш",
        "рж",
        "сб", "св", "сг", "сд", "сж", "сз", "ск", "сл", "см", "сн", "сп", "ср", "ст", "сх", "сц", "сч", "сш", "съ",
        "тв", "тл", "тр", "тщ",
        "фл", "фр",
        "хв", "хл", "хм", "хн", "хр",
        "чв", "чл", "чм", "чр", "чт",
        "шв", "шк", "шл", "шм", "шн", "шп", "шр", "шт",
        "щр",
        // Three-letter clusters:
        "взб", "взв", "взг", "взд", "взл", "взм", "взр", "взъ",
        "вск", "всп", "вст", "всх",
        "здр",
        "скв", "скл", "скр", "слл",
        "спл", "спр",
        "стр", "ств",
        "шпр",
    ]

    /// Vowel-start bigrams that indicate a likely truncated fragment (e.g., "ейсы" from "Кейсы").
    private static let fragmentVowelStarts: Set<String> = ["ей", "ой", "ый", "ий", "ёт", "ют", "ят", "ут"]

    /// Russian vowels.
    private static let russianVowels: Set<Character> = ["а", "е", "ё", "и", "о", "у", "ы", "э", "ю", "я"]

    /// Check if a word looks like a truncated fragment (missing first letter(s)).
    static func isFragment(_ word: String) -> Bool {
        let lower = word.lowercased()
        guard let first = lower.first else { return false }
        if russianVowels.contains(first) {
            let prefix2 = String(lower.prefix(2))
            return fragmentVowelStarts.contains(prefix2)
        }
        // Extract leading consonant cluster
        var clusterEnd = lower.startIndex
        while clusterEnd < lower.endIndex {
            let ch = lower[clusterEnd]
            if russianVowels.contains(ch) || ch == "ь" || ch == "ъ" { break }
            clusterEnd = lower.index(after: clusterEnd)
        }
        if clusterEnd <= lower.startIndex { return false }
        let cluster = String(lower[lower.startIndex..<clusterEnd])
        if cluster.count <= 1 { return false } // single consonant is always valid
        return !validRussianConsonantStarts.contains(cluster)
    }

    // MARK: - Text line extraction

    /// Strip leading page number from page text (e.g., "6\nГлобальная..." → "Глобальная...")
    static func stripLeadingPageNumber(from pageString: String, pageIndex: Int? = nil) -> String {
        var text = pageString

        // Case 1: page number on its own line at the top
        if let firstNewline = text.firstIndex(of: "\n") {
            let firstLine = text[text.startIndex..<firstNewline]
                .trimmingCharacters(in: .whitespaces)
            if firstLine.count <= 4 && firstLine.allSatisfy({ $0.isNumber || $0.isWhitespace }) {
                text = String(text[text.index(after: firstNewline)...])
            }
        }

        // Case 2: page number inline at start ("6 Глобальная..." → "Глобальная...")
        // Only strip if the number matches expected page number (±1 for 0-based/1-based)
        if let pageIndex = pageIndex {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let expectedNumbers = [pageIndex, pageIndex + 1, pageIndex - 1].filter { $0 > 0 }
            for expected in expectedNumbers {
                let numStr = "\(expected)"
                if trimmed.hasPrefix(numStr) {
                    let afterNum = trimmed.dropFirst(numStr.count)
                    if let next = afterNum.first, (next == " " || next == "\t" || next == "\n") {
                        // Verify the text after the number starts with a letter (not more digits)
                        let rest = afterNum.drop(while: { $0.isWhitespace })
                        if let firstChar = rest.first, firstChar.isLetter {
                            text = String(rest)
                            break
                        }
                    }
                }
            }
        }

        // Case 3: page number on its own line at the bottom
        if let lastNewline = text.lastIndex(of: "\n") {
            let lastLine = text[text.index(after: lastNewline)...]
                .trimmingCharacters(in: .whitespaces)
            if lastLine.count <= 4 && !lastLine.isEmpty && lastLine.allSatisfy({ $0.isNumber || $0.isWhitespace }) {
                text = String(text[..<lastNewline])
            }
        }

        return text
    }

    /// Extract sorted text lines from a PDF page using selectionsByLine().
    static func extractTextLines(from page: PDFPage, pageBounds: CGRect) -> [(bounds: CGRect, text: String)] {
        var textLines: [(bounds: CGRect, text: String)] = []
        if let fullSelection = page.selection(for: pageBounds),
           let lineSelections = fullSelection.selectionsByLine() as [PDFSelection]? {
            for lineSel in lineSelections {
                let bounds = lineSel.bounds(for: page)
                let text = lineSel.string ?? ""
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    textLines.append((bounds, text))
                }
            }
            textLines.sort { $0.bounds.maxY > $1.bounds.maxY }
        }
        return textLines
    }

    // MARK: - Text paragraph splitting

    /// Split full page text into paragraphs using multiple heuristics:
    /// 1. Blank lines → always break
    /// 2. Short lines → likely heading or paragraph end
    /// 3. Sentence-ending punctuation + next line starts with capital → paragraph break
    static func splitIntoParagraphs(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        let nonEmptyLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
                                 .filter { !$0.isEmpty }
        guard !nonEmptyLines.isEmpty else { return [] }

        // Find typical line length to detect short (paragraph-ending) lines
        let lengths = nonEmptyLines.map { $0.count }
        let sortedLengths = lengths.sorted()
        let typicalLength = sortedLengths[min(sortedLengths.count * 3 / 4, sortedLengths.count - 1)]
        let shortThreshold = max(typicalLength / 2, 20)

        // Build array of non-empty trimmed lines with their indices for lookahead
        struct IndexedLine { let index: Int; let text: String }
        var indexedLines: [IndexedLine] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                indexedLines.append(IndexedLine(index: i, text: trimmed))
            }
        }

        var paragraphs: [String] = []
        var currentLines: [String] = []

        for (idx, il) in indexedLines.enumerated() {
            // Check for blank lines between previous and current non-empty line
            if idx > 0 {
                let prevLineIndex = indexedLines[idx - 1].index
                let hasBlankBetween = (il.index - prevLineIndex) > 1
                if hasBlankBetween && !currentLines.isEmpty {
                    paragraphs.append(joinLines(currentLines))
                    currentLines = []
                }
            }

            currentLines.append(il.text)

            // Determine if this line ends a paragraph
            let isShortLine = il.text.count < shortThreshold
            let sentenceEndings: [Character] = [".", "!", "?", ":", "»"]
            let endsWithSentence = il.text.last.map { sentenceEndings.contains($0) } ?? false

            // Look ahead: does next line start with uppercase?
            let nextStartsUpper: Bool
            if idx + 1 < indexedLines.count {
                nextStartsUpper = indexedLines[idx + 1].text.first?.isUppercase == true
            } else {
                nextStartsUpper = false
            }

            let shouldBreak = (isShortLine && endsWithSentence) ||
                              (endsWithSentence && nextStartsUpper && currentLines.count >= 3)

            if shouldBreak {
                paragraphs.append(joinLines(currentLines))
                currentLines = []
            }
        }

        if !currentLines.isEmpty {
            paragraphs.append(joinLines(currentLines))
        }

        return paragraphs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Join lines handling hyphenated word breaks: "технол-" + "огия" → "технология"
    /// Preserves compound words like "из-за" by only dehyphenating when next line starts lowercase.
    static func joinLines(_ lines: [String]) -> String {
        guard lines.count > 1 else { return lines.first ?? "" }
        var result = ""
        for (i, line) in lines.enumerated() {
            if i > 0 {
                let endsWithHyphen = result.hasSuffix("-") || result.hasSuffix("\u{00AD}")
                let startsLowercase = line.first?.isLowercase == true
                if endsWithHyphen && startsLowercase {
                    // Word wrapped with hyphen: "технол-" + "огия" → "технология"
                    result.removeLast() // remove hyphen/soft-hyphen
                } else {
                    result += " "
                }
            }
            result += line
        }
        return result
    }

    // MARK: - Drop cap recovery

    /// Recover dropped first characters (drop caps) by parsing font ToUnicode CMaps.
    ///
    /// page.string is the cleanest text source but drops styled/decorated first letters
    /// because PDFKit can't decode the special fonts used for drop caps.
    /// This method directly parses the font's ToUnicode CMap table to find the correct
    /// Unicode characters, then inserts them at the right positions.
    static func recoverDropCaps(
        pageString: String,
        textLines: [(bounds: CGRect, text: String)],
        page: PDFPage,
        pageBounds: CGRect
    ) -> String {
        guard !textLines.isEmpty, let cgPage = page.pageRef else { return pageString }

        var text = pageString

        // Extract characters from special fonts via ToUnicode CMap parsing
        let cmapChars = extractCMapCharacters(from: cgPage)

        #if DEBUG
        let pageIndex = page.document?.index(for: page) ?? -1
        if !cmapChars.isEmpty {
            let charSummary = cmapChars.map { "'\($0.char)' y=\(Int($0.position.y))" }.joined(separator: ", ")
            print("[PDFExtractor] Page \(pageIndex): \(cmapChars.count) special font chars: \(charSummary)")
        } else {
            print("[PDFExtractor] Page \(pageIndex): no special font chars found")
        }
        #endif

        var insertions = 0
        let hasCMapChars = !cmapChars.isEmpty

        // Collect lines that need recovery
        struct RecoveryCandidate {
            let searchPrefix: String
            let matchingLine: (bounds: CGRect, text: String)
        }
        var candidates: [RecoveryCandidate] = []

        // Common Russian words that legitimately start lowercase after punctuation
        let commonLower = Set(["и", "а", "в", "с", "к", "о", "у", "на", "не", "но", "по", "из", "за", "до", "от", "же", "ни", "ещё", "ее", "его", "их", "её", "то", "что", "как", "так", "это", "все", "всё", "для", "при", "без", "или", "где", "чем", "вот", "вы", "мы", "он", "она", "они", "оно", "ему", "ей", "им", "нас", "вас", "да", "нет", "уже", "ведь", "тут", "там", "тем", "тот", "эта", "эти", "той", "том", "еще"])

        // Pass 1: Lines starting with lowercase letter (existing logic)
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 3 else { continue }

            // Find the first letter in the line (may be after digits/punctuation like "3) ")
            guard let firstLetterIdx = trimmed.firstIndex(where: { $0.isLetter }) else { continue }
            let firstLetter = trimmed[firstLetterIdx]
            guard firstLetter.isLowercase else { continue }

            // Use text starting from first letter as searchPrefix (skip "3) " etc.)
            let fromFirstLetter = String(trimmed[firstLetterIdx...])
            let searchPrefix = String(fromFirstLetter.prefix(min(15, fromFirstLetter.count)))

            guard let matchingLine = textLines.first(where: {
                let t = $0.text.trimmingCharacters(in: .whitespaces)
                return t.hasPrefix(searchPrefix) || t.contains(searchPrefix)
            }) else { continue }

            candidates.append(RecoveryCandidate(searchPrefix: searchPrefix, matchingLine: matchingLine))
        }

        // Pass 2: Mid-line drops — lowercase word after sentence-ending punctuation
        // Match single-char words too (e.g., ". о есть" where "Т" was dropped from "То")
        if let midLineRegex = try? NSRegularExpression(pattern: "[.!?»]\\s+[«\"„]?([а-яa-z]\\S*)", options: []) {
            let nsText = text as NSString
            let matches = midLineRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let wordRange = match.range(at: 1)
                let wordStr = nsText.substring(with: wordRange)

                guard let firstIdx = wordStr.firstIndex(where: { $0.isLetter }),
                      wordStr[firstIdx].isLowercase else { continue }
                let word = String(wordStr[firstIdx...].prefix(while: { $0.isLetter }))

                // For multi-char common words (и, на, но, etc.) skip — they're valid lowercase starts.
                // For single-char words (о, а, в...) allow through — CMap/OCR will verify
                // whether there's actually a missing character (e.g., "о" → "То").
                if word.count > 1 && commonLower.contains(word) { continue }

                let fromWord = String(wordStr[firstIdx...])
                let searchPrefix = String(fromWord.prefix(min(15, fromWord.count)))

                if candidates.contains(where: { $0.searchPrefix == searchPrefix }) { continue }

                guard let matchingLine = textLines.first(where: {
                    let t = $0.text.trimmingCharacters(in: .whitespaces)
                    return t.contains(searchPrefix)
                }) else { continue }

                candidates.append(RecoveryCandidate(searchPrefix: searchPrefix, matchingLine: matchingLine))
            }
        }

        // Render the full page ONCE for OCR (only if we have candidates and CMap didn't help)
        var renderedPage: (image: CGImage, scale: CGFloat, outputSize: CGSize)?

        for candidate in candidates {
            var insertStr: String? = nil
            let searchPrefix = candidate.searchPrefix
            let matchingLine = candidate.matchingLine

            // Strategy 1: Try CMap characters if available
            if hasCMapChars {
                let lineY = matchingLine.bounds.midY
                let yTolerance = matchingLine.bounds.height * 3.0

                let cmapCandidates = cmapChars.filter { cmapChar in
                    abs(cmapChar.position.y - lineY) < yTolerance
                }.sorted { abs($0.position.y - lineY) < abs($1.position.y - lineY) }

                if let best = cmapCandidates.first(where: { cmapChar in
                    guard let ch = cmapChar.char.first, ch.isLetter else { return false }
                    return ch.isUppercase || cmapChar.fontSize > matchingLine.bounds.height * 1.2
                }) {
                    let bestChar = best.char.first!
                    insertStr = String(bestChar.isUppercase ? bestChar : Character(String(bestChar).uppercased()))
                    #if DEBUG
                    print("[PDFExtractor] CMap match: '\(searchPrefix.prefix(15))' → '\(insertStr!)' at y=\(Int(best.position.y))")
                    #endif
                }
            }

            let isLikelyFragment = isFragment(searchPrefix)

            // Strategy 2: OCR — render full page once, crop each line
            if insertStr == nil {
                if renderedPage == nil {
                    renderedPage = renderPageForOCR(page)
                }
                guard let rendered = renderedPage else { continue }

                let extendLeft: CGFloat = matchingLine.bounds.height * 2.5
                let ocrBounds = CGRect(
                    x: max(matchingLine.bounds.minX - extendLeft, pageBounds.minX),
                    y: matchingLine.bounds.minY - 2,
                    width: matchingLine.bounds.width + extendLeft + 4,
                    height: matchingLine.bounds.height + 4
                )

                if let ocrText = ocrFromRenderedPage(
                    rendered.image,
                    pdfBounds: ocrBounds,
                    page: page,
                    imageSize: rendered.outputSize,
                    imageScale: rendered.scale
                ) {
                    let ocrTrimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !ocrTrimmed.isEmpty else { continue }

                    let shortPrefix = String(searchPrefix.prefix(min(6, searchPrefix.count))).lowercased()
                    if ocrTrimmed.lowercased().hasPrefix(shortPrefix) {
                        if isLikelyFragment {
                            #if DEBUG
                            print("[PDFExtractor] OCR shows same broken text for fragment '\(searchPrefix.prefix(15))' — retrying wider")
                            #endif
                            let wideBounds = CGRect(
                                x: pageBounds.minX,
                                y: matchingLine.bounds.minY - 2,
                                width: matchingLine.bounds.maxX - pageBounds.minX + 4,
                                height: matchingLine.bounds.height + 4
                            )
                            if let wideOCR = ocrFromRenderedPage(
                                rendered.image,
                                pdfBounds: wideBounds,
                                page: page,
                                imageSize: rendered.outputSize,
                                imageScale: rendered.scale
                            ) {
                                let wideTrimmed = wideOCR.trimmingCharacters(in: .whitespacesAndNewlines)
                                let wideLower = wideTrimmed.lowercased()
                                if let foundRange = wideLower.range(of: shortPrefix) {
                                    let foundStart = foundRange.lowerBound
                                    if foundStart > wideLower.startIndex {
                                        let charBeforeIdx = wideTrimmed.index(before: foundStart)
                                        let charBefore = wideTrimmed[charBeforeIdx]
                                        if charBefore.isLetter {
                                            insertStr = String(charBefore).uppercased()
                                            #if DEBUG
                                            print("[PDFExtractor] Wide OCR found: '\(searchPrefix.prefix(15))' → '\(insertStr!)' (OCR: '\(wideTrimmed.prefix(50))')")
                                            #endif
                                        }
                                    }
                                }
                            }
                        } else {
                            #if DEBUG
                            print("[PDFExtractor] OCR confirms continuation: '\(searchPrefix.prefix(15))'")
                            #endif
                            continue
                        }
                    } else {
                        let ocrLower = ocrTrimmed.lowercased()
                        let searchLower = shortPrefix

                        if let foundRange = ocrLower.range(of: searchLower) {
                            let foundStart = foundRange.lowerBound
                            if foundStart > ocrLower.startIndex {
                                let charBeforeIdx = ocrTrimmed.index(before: foundStart)
                                let charBefore = ocrTrimmed[charBeforeIdx]
                                if charBefore.isLetter {
                                    let upper = String(charBefore).uppercased()
                                    insertStr = upper
                                    #if DEBUG
                                    print("[PDFExtractor] OCR found: '\(searchPrefix.prefix(15))' → '\(upper)' (OCR: '\(ocrTrimmed.prefix(30))')")
                                    #endif
                                }
                            } else {
                                #if DEBUG
                                print("[PDFExtractor] OCR confirms continuation (B): '\(searchPrefix.prefix(15))'")
                                #endif
                            }
                        } else {
                            #if DEBUG
                            print("[PDFExtractor] OCR no match: prefix='\(searchPrefix.prefix(12))' OCR='\(ocrTrimmed.prefix(30))'")
                            #endif
                        }
                    }
                }
            }

            // Strategy 3: Dictionary-based fragment repair
            if insertStr == nil {
                insertStr = guessMissingPrefix(fragment: searchPrefix)
                #if DEBUG
                if let s = insertStr {
                    print("[PDFExtractor] Fragment repair: '\(searchPrefix.prefix(15))' → '\(s)' (dictionary)")
                }
                #endif
            }

            if let s = insertStr {
                while tryInsertStr(s, beforeTextMatching: searchPrefix, in: &text) {
                    insertions += 1
                }
            }
        }

        // Fix doubled uppercase characters (e.g., "ГГлобальная" → "Глобальная")
        fixDoubledCharacters(&text)

        #if DEBUG
        let resultLines = text.components(separatedBy: .newlines)
        var warnings = 0
        for (i, rLine) in resultLines.enumerated() {
            let trimmed = rLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 3,
                  let f = trimmed.first,
                  f.isLowercase && f.isLetter else { continue }
            let isParagraphStart = i == 0 || resultLines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty
            guard isParagraphStart else { continue }
            let word = String(trimmed.prefix(while: { $0.isLetter }))
            print("[PDFExtractor] ⚠️ STILL LOWERCASE paragraph start: '\(word)' in '\(trimmed.prefix(40))'")
            warnings += 1
        }
        print("[PDFExtractor] CMap recovery: \(insertions) insertions, \(warnings) remaining warnings")
        #endif

        return text
    }

    // MARK: - Insertion helpers

    /// Try to insert a string (1+ chars) before text matching the given continuation string.
    private static func tryInsertStr(_ prefix: String, beforeTextMatching continuation: String, in text: inout String) -> Bool {
        let searchLengths = [20, 12, 8, 5, 3]
        for searchLen in searchLengths {
            guard continuation.count >= searchLen else { continue }
            let searchStr = String(continuation.prefix(searchLen))

            var searchStart = text.startIndex
            while let range = text.range(of: searchStr, range: searchStart..<text.endIndex) {
                let pos = range.lowerBound

                let isAtBoundary = pos == text.startIndex || {
                    let prev = text[text.index(before: pos)]
                    return prev.isWhitespace || prev.isNewline || prev.isPunctuation
                }()

                if isAtBoundary {
                    if text[pos...].hasPrefix(prefix + searchStr) {
                        searchStart = range.upperBound
                        continue
                    }
                    if text.distance(from: text.startIndex, to: pos) >= prefix.count {
                        let prefixStart = text.index(pos, offsetBy: -prefix.count)
                        if String(text[prefixStart..<pos]) == prefix {
                            searchStart = range.upperBound
                            continue
                        }
                    }

                    text.insert(contentsOf: prefix, at: pos)
                    return true
                }

                searchStart = range.upperBound
            }
        }
        return false
    }

    /// Fix doubled uppercase characters that appear in page.string due to font encoding issues.
    private static func fixDoubledCharacters(_ text: inout String) {
        guard let regex = try? NSRegularExpression(
            pattern: "([А-ЯA-ZЁ])\\1([а-яa-zё])", options: []
        ) else { return }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches.reversed() {
            let fullRange = match.range(at: 0)
            let charRange = match.range(at: 1)
            let lowerRange = match.range(at: 2)

            if fullRange.location > 0 {
                let prevCharRange = NSRange(location: fullRange.location - 1, length: 1)
                let prevChar = nsText.substring(with: prevCharRange)
                if let p = prevChar.first, p.isLetter { continue }
            }

            let replacement = nsText.substring(with: charRange) + nsText.substring(with: lowerRange)
            text = (text as NSString).replacingCharacters(in: fullRange, with: replacement)
            #if DEBUG
            print("[PDFExtractor] Fixed doubled char: '\(nsText.substring(with: fullRange))' → '\(replacement)'")
            #endif
        }
    }

    // MARK: - Dictionary-based fragment repair

    /// Guess the missing prefix for a word fragment using common Russian word patterns.
    private static func guessMissingPrefix(fragment: String) -> String? {
        let lower = fragment.lowercased()

        let prefixRules: [(prefix: String, insert: String)] = [
            ("тсюда", "О"), ("ткуда", "О"), ("ткры", "О"), ("тдав", "О"), ("тдать", "О"),
            ("тдел", "О"), ("тказ", "О"), ("тклик", "О"), ("тклон", "О"), ("тлич", "О"),
            ("тнош", "О"), ("тправ", "О"), ("трасл", "О"), ("тсут", "О"), ("тчёт", "О"),
            ("тчет", "О"), ("тзыв", "О"), ("тобр", "О"), ("тсеч", "О"), ("тсек", "О"),
            ("тслеж", "О"), ("тток", "О"), ("ттал", "О"), ("тпугив", "О"), ("тпуг", "О"),
            ("бщ", "О"), ("бъяв", "О"), ("бъект", "О"), ("бъём", "О"), ("бъем", "О"),
            ("бязат", "О"), ("бласт", "О"), ("бслуж", "О"), ("бсужд", "О"), ("бучен", "О"),
            ("бнаруж", "О"), ("бновл", "О"), ("бработ", "О"), ("бразо", "О"), ("братн", "О"),
            ("бращ", "О"), ("бзор", "О"), ("бход", "О"), ("бсто", "О"), ("бман", "О"),
            ("нлайн", "О"), ("ффер", "О"), ("ффлайн", "О"), ("ффици", "О"),
            ("иловой", "С"), ("иловые", "С"), ("иловых", "С"), ("иловая", "С"), ("илов", "С"),
            ("истем", "С"), ("ервис", "С"), ("айт", "С"),
            ("о ним", "П"), ("о нем", "П"), ("о нём", "П"), ("о ней", "П"), ("о сути", "П"),
            ("о факту", "П"), ("о данным", "П"), ("о результат", "П"), ("о итог", "П"),
            ("о сравнен", "П"), ("о правил", "П"), ("о запрос", "П"),
            ("ример", "П"), ("рактик", "П"), ("родаж", "П"), ("ричин", "П"), ("роцент", "П"),
            ("роблем", "П"), ("отому", "П"), ("оэтому", "П"), ("осетител", "П"),
            ("редложен", "П"), ("ервый", "П"), ("ервая", "П"), ("ервое", "П"),
            ("ейсы", "К"), ("ейс", "К"), ("ейтер", "К"),
            ("ейронк", "Н"), ("ейросет", "Н"), ("ейрон", "Н"),
            ("ятый", "П"), ("ятая", "П"), ("ятое", "П"), ("ять", "П"), ("яток", "П"),
            ("зкая", "Ни"), ("зкий", "Ни"), ("зкое", "Ни"), ("зких", "Ни"), ("зком", "Ни"), ("зко", "Ни"),
        ]

        for rule in prefixRules {
            if lower.hasPrefix(rule.prefix) {
                return rule.insert
            }
        }

        return nil
    }

    // MARK: - OCR fallback for unresolvable fonts

    /// Render the full PDF page and return the image + scale factor.
    private static func renderPageForOCR(_ page: PDFPage) -> (image: CGImage, scale: CGFloat, outputSize: CGSize)? {
        guard let cgPage = page.pageRef else { return nil }
        let mediaBox = page.bounds(for: .mediaBox)
        let fitWidth: CGFloat = 800
        let aspect = mediaBox.height / mediaBox.width
        let outputSize = CGSize(width: fitWidth, height: fitWidth * aspect)
        let scale: CGFloat = 2.0

        let pixelW = Int(ceil(outputSize.width * scale))
        let pixelH = Int(ceil(outputSize.height * scale))
        guard pixelW > 0, pixelH > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: outputSize))

        let drawTransform = cgPage.getDrawingTransform(
            .mediaBox,
            rect: CGRect(origin: .zero, size: outputSize),
            rotate: 0,
            preserveAspectRatio: true
        )
        ctx.concatenate(drawTransform)
        ctx.drawPDFPage(cgPage)

        guard let cgImage = ctx.makeImage() else { return nil }
        return (cgImage, scale, outputSize)
    }

    /// Crop a region from the rendered page image and OCR it.
    private static func ocrFromRenderedPage(
        _ fullImage: CGImage,
        pdfBounds: CGRect,
        page: PDFPage,
        imageSize: CGSize,
        imageScale: CGFloat
    ) -> String? {
        guard let cgPage = page.pageRef else { return nil }

        let drawTransform = cgPage.getDrawingTransform(
            .mediaBox,
            rect: CGRect(origin: .zero, size: imageSize),
            rotate: 0,
            preserveAspectRatio: true
        )

        let transformed = pdfBounds.applying(drawTransform)

        let totalHeight = imageSize.height * imageScale
        let pixelX = transformed.minX * imageScale
        let pixelY = totalHeight - (transformed.maxY * imageScale)
        let pixelW = transformed.width * imageScale
        let pixelH = transformed.height * imageScale

        let cropRect = CGRect(x: pixelX, y: pixelY, width: pixelW, height: pixelH)
            .intersection(CGRect(x: 0, y: 0, width: CGFloat(fullImage.width), height: CGFloat(fullImage.height)))
        guard cropRect.width > 4, cropRect.height > 4 else { return nil }

        guard let cropped = fullImage.cropping(to: cropRect) else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ru", "en"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
        try? handler.perform([request])

        guard let results = request.results else { return nil }

        let ocrText = results.compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ocrText.isEmpty ? nil : ocrText
    }

    // MARK: - CMap character extraction

    /// Character extracted from a font's ToUnicode CMap with its position on the page.
    struct CMapChar {
        let char: String
        let position: CGPoint
        let fontSize: CGFloat
    }

    /// Parsed font encoding.
    private struct FontCMap {
        var mapping: [UInt16: String]
        var isTwoByte: Bool
        var isSpecial: Bool
    }

    /// Context for the text extraction scanner.
    private class TextScanContext {
        var ctm: CGAffineTransform = .identity
        var stateStack: [(ctm: CGAffineTransform, fontName: String?, fontSize: CGFloat)] = []
        var textMatrix: CGAffineTransform = .identity
        var lineMatrix: CGAffineTransform = .identity
        var currentFontName: String?
        var currentFontSize: CGFloat = 0
        var fontCMaps: [String: FontCMap] = [:]
        var checkedFonts: Set<String> = []
        var results: [CMapChar] = []

        func loadCMapIfNeeded(scanner: OpaquePointer?, fontNamePtr: UnsafePointer<CChar>) {
            guard let fontName = currentFontName else { return }
            if fontCMaps[fontName] != nil || checkedFonts.contains(fontName) { return }
            checkedFonts.insert(fontName)
            guard let scanner else { return }

            let contentStream = CGPDFScannerGetContentStream(scanner)
            guard let fontObj = CGPDFContentStreamGetResource(contentStream, "Font", fontNamePtr) else { return }
            var fontDict: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(fontObj, .dictionary, &fontDict), let fd = fontDict else { return }

            // Try 1: ToUnicode CMap
            var toUnicodeObj: CGPDFObjectRef?
            if CGPDFDictionaryGetObject(fd, "ToUnicode", &toUnicodeObj), let tuObj = toUnicodeObj {
                var toUnicodeStream: CGPDFStreamRef?
                if CGPDFObjectGetValue(tuObj, .stream, &toUnicodeStream), let tuStream = toUnicodeStream {
                    var format: CGPDFDataFormat = .raw
                    if let data = CGPDFStreamCopyData(tuStream, &format) {
                        let cmap = TextScanContext.parseCMap(data as Data)
                        if !cmap.mapping.isEmpty {
                            fontCMaps[fontName] = FontCMap(
                                mapping: cmap.mapping, isTwoByte: cmap.isTwoByte, isSpecial: false
                            )
                            return
                        }
                    }
                }
            }

            // Try 2: Encoding/Differences
            #if DEBUG
            var subtypePtr: UnsafePointer<CChar>?
            var baseFontPtr: UnsafePointer<CChar>?
            CGPDFDictionaryGetName(fd, "Subtype", &subtypePtr)
            CGPDFDictionaryGetName(fd, "BaseFont", &baseFontPtr)
            let subtype = subtypePtr.map { String(cString: $0) } ?? "?"
            let baseFont = baseFontPtr.map { String(cString: $0) } ?? "?"
            print("[PDFExtractor] Font '\(fontName)' (no ToUnicode): Subtype=\(subtype), BaseFont=\(baseFont)")
            #endif

            var encodingObj: CGPDFObjectRef?
            guard CGPDFDictionaryGetObject(fd, "Encoding", &encodingObj),
                  let encObj = encodingObj else {
                #if DEBUG
                print("[PDFExtractor] Font '\(fontName)': no Encoding either — marking as special (OCR fallback)")
                #endif
                fontCMaps[fontName] = FontCMap(mapping: [:], isTwoByte: false, isSpecial: true)
                return
            }

            var encDict: CGPDFDictionaryRef?
            if CGPDFObjectGetValue(encObj, .dictionary, &encDict), let ed = encDict {
                var differencesArray: CGPDFArrayRef?
                if CGPDFDictionaryGetArray(ed, "Differences", &differencesArray),
                   let diffs = differencesArray {
                    let mapping = TextScanContext.parseDifferences(diffs)
                    if !mapping.isEmpty {
                        fontCMaps[fontName] = FontCMap(
                            mapping: mapping, isTwoByte: false, isSpecial: true
                        )
                        #if DEBUG
                        print("[PDFExtractor] Special font '\(fontName)': \(mapping.count) chars via Differences")
                        let chars = mapping.values.sorted().joined()
                        print("[PDFExtractor]   chars: \(chars)")
                        #endif
                    }
                }
            }
        }

        func decodeAndRecord(string: CGPDFStringRef) {
            guard let fontName = currentFontName,
                  let cmap = fontCMaps[fontName],
                  cmap.isSpecial else { return }

            guard let bytes = CGPDFStringGetBytePtr(string) else { return }
            let length = CGPDFStringGetLength(string)
            guard length > 0 else { return }

            let combined = textMatrix.concatenating(ctm)
            let position = CGPoint(x: combined.tx, y: combined.ty)

            if cmap.isTwoByte {
                var i = 0
                while i + 1 < length {
                    let code = UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
                    if let unicode = cmap.mapping[code] {
                        results.append(CMapChar(char: unicode, position: position, fontSize: currentFontSize))
                    }
                    i += 2
                }
            } else {
                for i in 0..<length {
                    let code = UInt16(bytes[i])
                    if let unicode = cmap.mapping[code] {
                        results.append(CMapChar(char: unicode, position: position, fontSize: currentFontSize))
                    }
                }
            }
        }

        // MARK: - Encoding/Differences parsing

        static func parseDifferences(_ array: CGPDFArrayRef) -> [UInt16: String] {
            var mapping: [UInt16: String] = [:]
            var currentCode: UInt16 = 0
            let count = CGPDFArrayGetCount(array)

            for i in 0..<count {
                var intValue: CGPDFInteger = 0
                if CGPDFArrayGetInteger(array, i, &intValue) {
                    currentCode = UInt16(intValue)
                    continue
                }

                var namePtr: UnsafePointer<CChar>?
                if CGPDFArrayGetName(array, i, &namePtr), let name = namePtr {
                    let glyphName = String(cString: name)
                    if let unicode = resolveGlyphName(glyphName) {
                        mapping[currentCode] = unicode
                    }
                    currentCode += 1
                }
            }
            return mapping
        }

        static func resolveGlyphName(_ name: String) -> String? {
            // uniXXXX format (e.g., "uni041F" → П)
            if name.hasPrefix("uni"), name.count == 7 {
                let hex = String(name.dropFirst(3))
                if let cp = UInt32(hex, radix: 16), let s = Unicode.Scalar(cp) {
                    return String(s)
                }
            }
            return glyphNameMap[name]
        }

        static let glyphNameMap: [String: String] = {
            var m: [String: String] = [:]
            let cyrUpperCodes: [(String, UInt32)] = [
                ("afii10017", 0x0410), ("afii10018", 0x0411), ("afii10019", 0x0412),
                ("afii10020", 0x0413), ("afii10021", 0x0414), ("afii10022", 0x0415),
                ("afii10023", 0x0401),
                ("afii10024", 0x0416), ("afii10025", 0x0417),
                ("afii10026", 0x0418), ("afii10027", 0x0419), ("afii10028", 0x041A),
                ("afii10029", 0x041B), ("afii10030", 0x041C), ("afii10031", 0x041D),
                ("afii10032", 0x041E), ("afii10033", 0x041F), ("afii10034", 0x0420),
                ("afii10035", 0x0421), ("afii10036", 0x0422), ("afii10037", 0x0423),
                ("afii10038", 0x0424), ("afii10039", 0x0425), ("afii10040", 0x0426),
                ("afii10041", 0x0427), ("afii10042", 0x0428), ("afii10043", 0x0429),
                ("afii10044", 0x042A), ("afii10045", 0x042B), ("afii10046", 0x042C),
                ("afii10047", 0x042D), ("afii10048", 0x042E), ("afii10049", 0x042F),
            ]
            let cyrLowerCodes: [(String, UInt32)] = [
                ("afii10065", 0x0430), ("afii10066", 0x0431), ("afii10067", 0x0432),
                ("afii10068", 0x0433), ("afii10069", 0x0434), ("afii10070", 0x0435),
                ("afii10071", 0x0451),
                ("afii10072", 0x0436), ("afii10073", 0x0437),
                ("afii10074", 0x0438), ("afii10075", 0x0439), ("afii10076", 0x043A),
                ("afii10077", 0x043B), ("afii10078", 0x043C), ("afii10079", 0x043D),
                ("afii10080", 0x043E), ("afii10081", 0x043F), ("afii10082", 0x0440),
                ("afii10083", 0x0441), ("afii10084", 0x0442), ("afii10085", 0x0443),
                ("afii10086", 0x0444), ("afii10087", 0x0445), ("afii10088", 0x0446),
                ("afii10089", 0x0447), ("afii10090", 0x0448), ("afii10091", 0x0449),
                ("afii10092", 0x044A), ("afii10093", 0x044B), ("afii10094", 0x044C),
                ("afii10095", 0x044D), ("afii10096", 0x044E), ("afii10097", 0x044F),
            ]
            for (name, code) in cyrUpperCodes + cyrLowerCodes {
                if let s = Unicode.Scalar(code) { m[name] = String(s) }
            }
            for code: UInt32 in 0x0041...0x005A {
                if let s = Unicode.Scalar(code) { m[String(Character(s))] = String(s) }
            }
            for code: UInt32 in 0x0061...0x007A {
                if let s = Unicode.Scalar(code) { m[String(Character(s))] = String(s) }
            }
            let digitNames = ["zero","one","two","three","four","five","six","seven","eight","nine"]
            for (i, name) in digitNames.enumerated() { m[name] = String(i) }
            m["space"] = " "; m["period"] = "."; m["comma"] = ","; m["colon"] = ":"
            m["semicolon"] = ";"; m["hyphen"] = "-"; m["endash"] = "–"; m["emdash"] = "—"
            m["quoteleft"] = "\u{2018}"; m["quoteright"] = "\u{2019}"
            m["quotedblleft"] = "\u{201C}"; m["quotedblright"] = "\u{201D}"
            m["guillemotleft"] = "«"; m["guillemotright"] = "»"
            m["exclam"] = "!"; m["question"] = "?"; m["parenleft"] = "("; m["parenright"] = ")"
            m["numbersign"] = "#"; m["numero"] = "№"
            return m
        }()

        // MARK: - CMap parsing

        static func parseCMap(_ data: Data) -> FontCMap {
            guard let cmapString = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .ascii) else {
                return FontCMap(mapping: [:], isTwoByte: false, isSpecial: false)
            }

            var mapping: [UInt16: String] = [:]
            var isTwoByte = false

            if let range = cmapString.range(of: "begincodespacerange") {
                let after = cmapString[range.upperBound...]
                if let hexStart = after.range(of: "<") {
                    let hexContent = after[hexStart.upperBound...]
                    if let hexEnd = hexContent.firstIndex(of: ">") {
                        isTwoByte = hexContent.distance(from: hexContent.startIndex, to: hexEnd) >= 4
                    }
                }
            }

            TextScanContext.parseSections(cmapString, begin: "beginbfchar", end: "endbfchar") { section in
                let lines = section.components(separatedBy: .newlines)
                for line in lines {
                    let hexValues = TextScanContext.extractHex(from: line)
                    guard hexValues.count >= 2,
                          let srcCode = UInt16(hexValues[0], radix: 16),
                          let unicode = TextScanContext.decodeHex(hexValues[1]) else { continue }
                    mapping[srcCode] = unicode
                }
            }

            TextScanContext.parseSections(cmapString, begin: "beginbfrange", end: "endbfrange") { section in
                let lines = section.components(separatedBy: .newlines)
                for line in lines {
                    let hexValues = TextScanContext.extractHex(from: line)
                    guard hexValues.count >= 3,
                          let lo = UInt16(hexValues[0], radix: 16),
                          let hi = UInt16(hexValues[1], radix: 16),
                          let startUnicode = UInt32(hexValues[2], radix: 16),
                          lo <= hi else { continue }
                    for code in lo...hi {
                        let unicode = startUnicode + UInt32(code - lo)
                        if let scalar = Unicode.Scalar(unicode) {
                            mapping[code] = String(scalar)
                        }
                    }
                }
            }

            return FontCMap(mapping: mapping, isTwoByte: isTwoByte, isSpecial: false)
        }

        static func parseSections(_ cmap: String, begin: String, end: String, handler: (String) -> Void) {
            var searchStart = cmap.startIndex
            while let beginRange = cmap.range(of: begin, range: searchStart..<cmap.endIndex) {
                guard let endRange = cmap.range(of: end, range: beginRange.upperBound..<cmap.endIndex) else { break }
                handler(String(cmap[beginRange.upperBound..<endRange.lowerBound]))
                searchStart = endRange.upperBound
            }
        }

        static func extractHex(from line: String) -> [String] {
            var values: [String] = []
            var i = line.startIndex
            while i < line.endIndex {
                if line[i] == "<" {
                    let start = line.index(after: i)
                    if let end = line[start...].firstIndex(of: ">") {
                        values.append(String(line[start..<end]))
                        i = line.index(after: end)
                    } else { break }
                } else {
                    i = line.index(after: i)
                }
            }
            return values
        }

        static func decodeHex(_ hex: String) -> String? {
            let normalised = hex.count == 2 ? "00" + hex : hex
            guard normalised.count >= 4, normalised.count % 4 == 0 else { return nil }
            var result = ""
            var i = normalised.startIndex
            while i < normalised.endIndex {
                guard let end = normalised.index(i, offsetBy: 4, limitedBy: normalised.endIndex) else { break }
                guard let codePoint = UInt32(normalised[i..<end], radix: 16),
                      let scalar = Unicode.Scalar(codePoint) else { return nil }
                result.append(Character(scalar))
                i = end
            }
            return result.isEmpty ? nil : result
        }
    }

    /// Scan a PDF page for text rendered with fonts that have ToUnicode CMaps.
    private static func extractCMapCharacters(from cgPage: CGPDFPage) -> [CMapChar] {
        let context = TextScanContext()
        guard let operatorTable = CGPDFOperatorTableCreate() else { return [] }

        CGPDFOperatorTableSetCallback(operatorTable, "q") { _, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            ctx.stateStack.append((ctx.ctm, ctx.currentFontName, ctx.currentFontSize))
        }

        CGPDFOperatorTableSetCallback(operatorTable, "Q") { _, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            if let saved = ctx.stateStack.popLast() {
                ctx.ctm = saved.ctm
                ctx.currentFontName = saved.fontName
                ctx.currentFontSize = saved.fontSize
            }
        }

        CGPDFOperatorTableSetCallback(operatorTable, "cm") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            var a: CGPDFReal = 0, b: CGPDFReal = 0, c: CGPDFReal = 0
            var d: CGPDFReal = 0, tx: CGPDFReal = 0, ty: CGPDFReal = 0
            CGPDFScannerPopNumber(scanner, &ty)
            CGPDFScannerPopNumber(scanner, &tx)
            CGPDFScannerPopNumber(scanner, &d)
            CGPDFScannerPopNumber(scanner, &c)
            CGPDFScannerPopNumber(scanner, &b)
            CGPDFScannerPopNumber(scanner, &a)
            let matrix = CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
            ctx.ctm = matrix.concatenating(ctx.ctm)
        }

        CGPDFOperatorTableSetCallback(operatorTable, "BT") { _, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            ctx.textMatrix = .identity
            ctx.lineMatrix = .identity
        }

        CGPDFOperatorTableSetCallback(operatorTable, "Tf") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            var fontSize: CGPDFReal = 0
            var fontNamePtr: UnsafePointer<CChar>?
            CGPDFScannerPopNumber(scanner, &fontSize)
            CGPDFScannerPopName(scanner, &fontNamePtr)
            guard let namePtr = fontNamePtr else { return }
            ctx.currentFontName = String(cString: namePtr)
            ctx.currentFontSize = CGFloat(abs(fontSize))
            ctx.loadCMapIfNeeded(scanner: scanner, fontNamePtr: namePtr)
        }

        CGPDFOperatorTableSetCallback(operatorTable, "Tm") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            var a: CGPDFReal = 0, b: CGPDFReal = 0, c: CGPDFReal = 0
            var d: CGPDFReal = 0, tx: CGPDFReal = 0, ty: CGPDFReal = 0
            CGPDFScannerPopNumber(scanner, &ty)
            CGPDFScannerPopNumber(scanner, &tx)
            CGPDFScannerPopNumber(scanner, &d)
            CGPDFScannerPopNumber(scanner, &c)
            CGPDFScannerPopNumber(scanner, &b)
            CGPDFScannerPopNumber(scanner, &a)
            let matrix = CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
            ctx.textMatrix = matrix
            ctx.lineMatrix = matrix
        }

        CGPDFOperatorTableSetCallback(operatorTable, "Td") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            var tx: CGPDFReal = 0, ty: CGPDFReal = 0
            CGPDFScannerPopNumber(scanner, &ty)
            CGPDFScannerPopNumber(scanner, &tx)
            let translate = CGAffineTransform(translationX: CGFloat(tx), y: CGFloat(ty))
            ctx.lineMatrix = translate.concatenating(ctx.lineMatrix)
            ctx.textMatrix = ctx.lineMatrix
        }

        CGPDFOperatorTableSetCallback(operatorTable, "TD") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            var tx: CGPDFReal = 0, ty: CGPDFReal = 0
            CGPDFScannerPopNumber(scanner, &ty)
            CGPDFScannerPopNumber(scanner, &tx)
            let translate = CGAffineTransform(translationX: CGFloat(tx), y: CGFloat(ty))
            ctx.lineMatrix = translate.concatenating(ctx.lineMatrix)
            ctx.textMatrix = ctx.lineMatrix
        }

        CGPDFOperatorTableSetCallback(operatorTable, "Tj") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            var pdfString: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &pdfString), let str = pdfString else { return }
            ctx.decodeAndRecord(string: str)
        }

        CGPDFOperatorTableSetCallback(operatorTable, "TJ") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array), let arr = array else { return }
            let count = CGPDFArrayGetCount(arr)
            for i in 0..<count {
                var pdfString: CGPDFStringRef?
                if CGPDFArrayGetString(arr, i, &pdfString), let str = pdfString {
                    ctx.decodeAndRecord(string: str)
                }
            }
        }

        CGPDFOperatorTableSetCallback(operatorTable, "'") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            var pdfString: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &pdfString), let str = pdfString else { return }
            ctx.decodeAndRecord(string: str)
        }

        let contentStream = CGPDFContentStreamCreateWithPage(cgPage)
        let opaqueCtx = Unmanaged.passUnretained(context).toOpaque()
        let pdfScanner = CGPDFScannerCreate(contentStream, operatorTable, opaqueCtx)

        _ = withExtendedLifetime(context) {
            CGPDFScannerScan(pdfScanner)
        }
        CGPDFScannerRelease(pdfScanner)
        CGPDFContentStreamRelease(contentStream)
        CGPDFOperatorTableRelease(operatorTable)

        return context.results
    }

    // MARK: - Diagnostics

    /// Large set of common Russian words that legitimately start lowercase after punctuation
    private static let diagnosticCommonLower: Set<String> = [
        "и", "а", "в", "с", "к", "о", "у", "на", "не", "но", "по", "из", "за", "до", "от", "же", "ни",
        "ещё", "еще", "его", "их", "её", "ее", "то", "что", "как", "так", "это", "все", "всё",
        "для", "при", "без", "или", "где", "чем", "вот", "вы", "мы", "он", "она", "они", "оно",
        "ему", "ей", "им", "нас", "вас", "да", "нет", "уже", "ведь", "тут", "там", "тем", "тот",
        "эта", "эти", "той", "том", "если", "чтобы", "когда", "пока", "потому", "поэтому",
        "также", "может", "можно", "нужно", "надо", "просто", "очень", "даже", "только",
        "более", "менее", "около", "после", "перед", "между", "через", "будет", "было", "были",
        "быть", "есть", "этот", "этой", "этих", "этому", "этим",
        "значит", "стоит", "важно", "например", "однако", "поскольку", "причём", "причем",
        "хотя", "либо", "ибо", "затем", "потом", "сначала", "сперва", "впрочем",
        "следовательно", "соответственно", "разумеется", "конечно", "безусловно",
        "обязательно", "необходимо", "достаточно", "возможно", "вероятно", "наверное",
        "кажется", "видимо", "скорее", "скоро", "точно", "действительно", "обычно",
        "наконец", "иначе", "иногда", "всегда", "никогда", "нигде", "везде", "здесь",
        "отсюда", "оттуда", "откуда", "куда", "зачем", "почему", "сколько",
        "кто", "кого", "кому", "кем", "чья", "чьё", "чей", "чьи",
        "каждый", "каждая", "каждое", "каждого", "любой", "любая", "любое",
        "другой", "другая", "другое", "других", "другим", "другие",
        "такой", "такая", "такое", "таких", "таким", "такие", "такого",
        "самый", "самая", "самое", "самого", "самых", "самым",
        "новый", "новая", "новое", "новых", "новые", "нового",
        "первый", "первая", "первое", "первых", "второй", "третий",
        "большой", "большая", "большое", "большие", "больших", "большего",
        "маленький", "малый", "малая", "малое", "малых",
        "хороший", "хорошая", "хорошее", "хорошо", "хороших",
        "плохой", "плохая", "плохое", "плохо",
        "главный", "главная", "главное", "главных", "главным",
        "основной", "основная", "основное", "основных", "основным",
        "общий", "общая", "общее", "общих", "общие",
        "полный", "полная", "полное", "полных", "полностью",
        "целый", "целая", "целое", "целых",
        "весь", "вся", "всего", "всех", "всем", "всеми", "всему",
        "свой", "своя", "своё", "своих", "своим", "своей", "своего",
        "сам", "сама", "само", "сами", "самих",
        "один", "одна", "одно", "одних", "одним", "одного", "одной",
        "два", "две", "двух", "трёх", "трех", "четырёх",
        "много", "мало", "несколько", "немного", "немало",
        "часто", "редко", "быстро", "медленно", "долго", "давно", "недавно",
        "далеко", "близко", "высоко", "низко", "глубоко", "широко",
        "слишком", "довольно", "весьма", "крайне", "чрезвычайно",
        "вместе", "отдельно", "вместо", "кроме", "помимо",
        "снова", "опять", "вновь", "снаружи", "внутри",
        "вверх", "вниз", "вперёд", "назад", "вправо", "влево",
        "сейчас", "теперь", "тогда", "прежде", "раньше", "позже",
        "сегодня", "вчера", "завтра", "утром", "вечером", "ночью", "днём",
        "специалист", "специалисты", "специалистам", "специалистов",
        "компания", "компании", "компаний", "компанию",
        "проект", "проекты", "проекта", "проектов", "проектом",
        "клиент", "клиенты", "клиента", "клиентов", "клиентом",
        "результат", "результаты", "результата", "результатов",
        "процесс", "процессы", "процесса", "процессов",
        "система", "системы", "систему", "системой",
        "задача", "задачи", "задач", "задачу", "задачей",
        "работа", "работы", "работу", "работой",
        "время", "времени", "временем",
        "деньги", "денег", "деньгами",
        "люди", "людей", "людям", "людьми",
        "человек", "человека", "человеку",
        "место", "места", "мест", "местом",
        "дело", "дела", "дел", "делом",
        "вопрос", "вопросы", "вопроса", "вопросов",
        "ответ", "ответы", "ответа", "ответов",
        "способ", "способы", "способа", "способов",
        "случай", "случае", "случая", "случаев",
        "часть", "части", "частью",
        "стороны", "стороне", "сторону", "стороной",
        "качество", "качества", "качеству",
        "количество", "количества", "количеству",
        "уровень", "уровня", "уровню", "уровнем",
        "помощь", "помощью", "помощи",
        "обучение", "обучения", "обучению",
        "развитие", "развития", "развитию",
        "управление", "управления", "управлению",
        "решение", "решения", "решению", "решений",
        "изменение", "изменения", "изменению", "изменений",
        "исследование", "исследования", "исследований",
        "технология", "технологии", "технологий",
        "информация", "информации", "информацию",
        "ситуация", "ситуации", "ситуацию",
        "проблема", "проблемы", "проблему", "проблем",
        "возможность", "возможности", "возможностей",
        "необходимость", "необходимости",
        "особенность", "особенности", "особенностей",
        "область", "области", "областей",
        "рынок", "рынка", "рынке", "рынку",
        "бизнес", "бизнеса", "бизнесе", "бизнесу",
        "продукт", "продукты", "продукта", "продуктов",
        "услуга", "услуги", "услуг", "услугу",
        "делать", "делает", "делают", "делая",
        "знать", "знает", "знают", "зная",
        "думать", "думает", "думают", "думая",
        "говорить", "говорит", "говорят",
        "работать", "работает", "работают", "работая",
        "начинать", "начинает", "начинают",
        "получать", "получает", "получают",
        "использовать", "использует", "используют", "используя",
        "создавать", "создаёт", "создают", "создавая",
        "развивать", "развивает", "развивают",
        "определять", "определяет", "определяют",
        "показывать", "показывает", "показывают",
        "помогать", "помогает", "помогают",
        "позволять", "позволяет", "позволяют",
        "требовать", "требует", "требуют",
        "приходить", "приходит", "приходят",
        "становиться", "становится", "становятся",
        "оставаться", "остаётся", "остаются",
        "являться", "является", "являются",
        "обучаться", "обучается", "обучаются",
        "существовать", "существует", "существуют",
        "представлять", "представляет", "представляют",
        "включать", "включает", "включают",
        "состоять", "состоит", "состоят",
        "зависеть", "зависит", "зависят",
        "следовать", "следует", "следуют",
        "который", "которая", "которое", "которых", "которым", "которые", "которого", "которой",
        "именно", "особенно", "постепенно", "постоянно", "ежедневно",
        "дальше", "больше", "меньше", "лучше", "хуже", "раньше",
        "наиболее", "наименее",
    ]

    /// Run drop cap diagnostics on all pages. Returns a report string.
    static func diagnoseDropCaps(document: PDFDocument) -> String {
        var report = "=== Drop Cap Diagnostic Report ===\n"
        report += "Pages: \(document.pageCount)\n\n"
        var totalIssues = 0
        var totalFixed = 0

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageBounds = page.bounds(for: .mediaBox)

            guard let pageString = page.string,
                  !pageString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            let strippedPageString = stripLeadingPageNumber(from: pageString)
            let textLines = extractTextLines(from: page, pageBounds: pageBounds)

            let recovered = recoverDropCaps(pageString: strippedPageString, textLines: textLines, page: page, pageBounds: pageBounds)

            let pageFixes = countDifferences(original: strippedPageString, recovered: recovered)
            totalFixed += pageFixes

            var pageIssues: [(word: String, context: String, confidence: String)] = []

            let patterns: [(String, String)] = [
                ("(?<=[.!?»])\\s+([а-яa-z]\\S{2,})", "after-punct"),
                ("(?:^|\\n)\\s*(\\d+\\)\\s*[а-яa-z]\\S{2,})", "numbered"),
            ]
            for (pattern, _) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                let nsText = recovered as NSString
                let matches = regex.matches(in: recovered, range: NSRange(location: 0, length: nsText.length))
                for match in matches {
                    let fullRange = match.range(at: 0)
                    let fullStr = nsText.substring(with: fullRange).trimmingCharacters(in: .whitespaces)

                    guard let firstLetterIdx = fullStr.firstIndex(where: { $0.isLetter }),
                          fullStr[firstLetterIdx].isLowercase else { continue }
                    let word = String(fullStr[firstLetterIdx...].prefix(while: { $0.isLetter }))

                    if word.count < 3 { continue }
                    if diagnosticCommonLower.contains(word.lowercased()) { continue }

                    guard isFragment(word) else { continue }
                    let confidence = "HIGH"

                    let loc = fullRange.location
                    let contextStart = max(0, loc - 15)
                    let contextEnd = min(nsText.length, loc + fullRange.length + 15)
                    let context = nsText.substring(with: NSRange(location: contextStart, length: contextEnd - contextStart))
                        .replacingOccurrences(of: "\n", with: "↵")

                    pageIssues.append((word: word, context: context, confidence: confidence))
                }
            }

            let resultLines = recovered.components(separatedBy: "\n")
            for (i, rLine) in resultLines.enumerated() {
                let trimmed = rLine.trimmingCharacters(in: .whitespaces)
                guard trimmed.count >= 3,
                      let firstLetterIdx = trimmed.firstIndex(where: { $0.isLetter }),
                      trimmed[firstLetterIdx].isLowercase else { continue }
                let isParagraphStart = i == 0 || resultLines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty
                guard isParagraphStart else { continue }

                let word = String(trimmed[firstLetterIdx...].prefix(while: { $0.isLetter }))
                if word.count < 3 { continue }
                if diagnosticCommonLower.contains(word.lowercased()) { continue }

                guard isFragment(word) else { continue }
                let confidence = "HIGH"

                let context = String(trimmed.prefix(40))
                pageIssues.append((word: word, context: context, confidence: confidence))
            }

            if !pageIssues.isEmpty {
                var seen = Set<String>()
                let unique = pageIssues.filter { seen.insert($0.word + $0.context).inserted }

                let sorted = unique.sorted { ($0.confidence == "HIGH" ? 0 : 1) < ($1.confidence == "HIGH" ? 0 : 1) }

                report += "Page \(pageIndex + 1):"
                if pageFixes > 0 { report += " (\(pageFixes) fixed)" }
                report += " \(sorted.count) remaining\n"
                for issue in sorted {
                    let marker = issue.confidence == "HIGH" ? "🔴" : "🟡"
                    report += "  \(marker) '\(issue.word)' ...\(issue.context)...\n"
                    totalIssues += 1
                }
                report += "\n"
            } else if pageFixes > 0 {
                report += "Page \(pageIndex + 1): ✅ \(pageFixes) fixed, 0 remaining\n"
            }
        }

        report += "\n=== Summary ===\n"
        report += "Fixed: \(totalFixed) insertions\n"
        report += "Remaining: \(totalIssues) potential issues (🔴 HIGH = likely real, 🟡 LOW = may be false positive)\n"
        report += "Pages: \(document.pageCount)\n"
        return report
    }

    /// Count character insertions between original and recovered text
    private static func countDifferences(original: String, recovered: String) -> Int {
        let diff = recovered.count - original.count
        return max(0, diff)
    }
}
