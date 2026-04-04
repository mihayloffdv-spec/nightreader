import PDFKit
import UIKit
import CoreGraphics

// MARK: - Text Extractor
//
// Извлечение и обработка текста из PDF-страниц:
// - Извлечение строк через PDFSelection API
// - Разбиение на абзацы и дегифенация
// - Удаление номеров страниц
//
// ┌──────────────────────────────────────────────────────┐
// │                  TextExtractor                        │
// │                                                      │
// │  extractTextLines(page) → [(bounds, text)]           │
// │  splitIntoParagraphs(text) → [String]                │
// │  stripLeadingPageNumber(text) → String               │
// │  joinLines(lines) → String                           │
// │  isFragment(word) → Bool                             │
// └──────────────────────────────────────────────────────┘
//
// Восстановление drop cap вынесено в DropCapRecovery.swift

enum TextExtractor {

    // MARK: - Shared constants

    /// Consonant clusters that can start a valid Russian word.
    /// Used by fragment detection (diagnostics + live recovery) to identify truncated words.
    static let validRussianConsonantStarts: Set<String> = [
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
    static let fragmentVowelStarts: Set<String> = ["ей", "ой", "ый", "ий", "ёт", "ют", "ят", "ут", "еб", "ер", "оэ", "ок", "он"]

    /// Russian vowels.
    static let russianVowels: Set<Character> = ["а", "е", "ё", "и", "о", "у", "ы", "э", "ю", "я"]

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

            // Break paragraph when:
            // - Short line ending with punctuation (typical paragraph end)
            // - Sentence ending + next line starts uppercase (even mid-line)
            // - Current paragraph already has 2+ lines and sentence ends with capital next
            let shouldBreak = (isShortLine && endsWithSentence) ||
                              (endsWithSentence && nextStartsUpper)

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

                // Check if previous line ends with a single uppercase letter
                // that is the START of a word broken across PDF lines.
                // "П" + "ри этом" → "При этом"
                // But NOT: "Безусловно, О" + "стандартные" — "О" after comma is punctuation context
                //
                // Heuristic: join if trailing single uppercase is NOT preceded by
                // sentence-ending punctuation (. ! ? , ; :)
                let trailingLetters = String(result.reversed().prefix(while: { $0.isLetter }).reversed())
                let charBeforeTrailing: Character? = {
                    let before = result.dropLast(trailingLetters.count)
                    // Skip whitespace to find the actual preceding char
                    return before.last(where: { !$0.isWhitespace })
                }()
                let afterPunctuation = charBeforeTrailing != nil && ".!?,;:»\"'()".contains(charBeforeTrailing!)
                let isBrokenWord = trailingLetters.count == 1
                    && trailingLetters.first?.isUppercase == true
                    && startsLowercase
                    && !afterPunctuation

                if endsWithHyphen && startsLowercase {
                    result.removeLast() // remove hyphen/soft-hyphen, join word
                } else if isBrokenWord {
                    // Broken word: "П" + "ри этом" → "При этом" (no space)
                } else {
                    result += " "
                }
            }
            result += line
        }
        return result
    }
}
