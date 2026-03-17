import PDFKit
import UIKit
import CoreGraphics
import Vision

// MARK: - Content block types

enum ContentBlock {
    case text(String)
    case heading(String)   // Detected heading (larger font size in PDF)
    case image(UIImage)    // Extracted raster image from PDF
    case snapshot(UIImage)  // Rendered region snapshot (tables, diagrams, etc.)
}

// MARK: - Extracted image with position

private struct ExtractedImage {
    let cgImage: CGImage
    let rect: CGRect  // Position in PDF page coordinates
}

// MARK: - Block cache

final class BlockCache {
    static let shared = BlockCache()

    private let cache = NSCache<NSString, CachedBlocks>()

    private init() {
        cache.countLimit = 30  // ~30 pages
        cache.totalCostLimit = 60 * 1024 * 1024  // ~60MB

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    func blocks(forPage pageIndex: Int, width: CGFloat) -> [ContentBlock]? {
        let key = "\(pageIndex)_\(Int(width.rounded()))" as NSString
        return cache.object(forKey: key)?.blocks
    }

    func clearAll() {
        cache.removeAllObjects()
    }

    func store(_ blocks: [ContentBlock], forPage pageIndex: Int, width: CGFloat) {
        let key = "\(pageIndex)_\(Int(width.rounded()))" as NSString
        let cost = blocks.reduce(0) { sum, block in
            switch block {
            case .text, .heading: return sum + 256
            case .image(let img), .snapshot(let img):
                let bytes = Int(img.size.width * img.scale * img.size.height * img.scale * 4)
                return sum + bytes
            }
        }
        cache.setObject(CachedBlocks(blocks: blocks), forKey: key, cost: cost)
    }

    func invalidate() {
        cache.removeAllObjects()
    }
}

private class CachedBlocks: NSObject {
    let blocks: [ContentBlock]
    init(blocks: [ContentBlock]) { self.blocks = blocks }
}

// MARK: - PDF Content Extractor

final class PDFContentExtractor {

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
    /// Returns true if the word starts with a consonant cluster or vowel bigram
    /// that cannot begin a valid Russian word.
    private static func isFragment(_ word: String) -> Bool {
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

    // MARK: - Shared helpers

    /// Strip leading page number from page text (e.g., "6\nГлобальная..." → "Глобальная...")
    private static func stripLeadingPageNumber(from pageString: String) -> String {
        guard let firstNewline = pageString.firstIndex(of: "\n") else { return pageString }
        let firstLine = pageString[pageString.startIndex..<firstNewline]
            .trimmingCharacters(in: .whitespaces)
        if firstLine.count <= 4 && firstLine.allSatisfy({ $0.isNumber || $0.isWhitespace }) {
            return String(pageString[pageString.index(after: firstNewline)...])
        }
        return pageString
    }

    /// Extract sorted text lines from a PDF page using selectionsByLine().
    private static func extractTextLines(from page: PDFPage, pageBounds: CGRect) -> [(bounds: CGRect, text: String)] {
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

    /// Extract content blocks from a single PDF page.
    /// Returns an ordered array of text, image, and snapshot blocks (top to bottom).
    static func extractBlocks(from page: PDFPage, pageWidth: CGFloat) -> [ContentBlock] {
        let pageBounds = page.bounds(for: .mediaBox)

        // Assess text quality — if poor, render entire page as snapshot
        let quality = assessTextQuality(page: page, pageBounds: pageBounds)
        if quality == .poor {
            if let image = renderFullPage(page, fitWidth: pageWidth) {
                return [.snapshot(image)]
            }
            return []
        }

        // Scan page content: images, rectangles, lines, fonts
        let scanResult: ScannerContext
        if let cgPage = page.pageRef {
            scanResult = Self.scanPageContent(from: cgPage)
        } else {
            scanResult = ScannerContext()
        }

        // Get line selections for layout analysis (multi-column, complex regions)
        let textLines = extractTextLines(from: page, pageBounds: pageBounds)

        // Detect multi-column layout → full page snapshot (text reflow won't work)
        let isMultiColumn = !textLines.isEmpty && detectMultiColumnLayout(textLines: textLines, pageBounds: pageBounds)
        if isMultiColumn {
            if let image = renderFullPage(page, fitWidth: pageWidth) {
                return [.snapshot(image)]
            }
            return []
        }

        // Primary text source: page.string (clean, no garbage from styled text).
        // textLines is used ONLY to recover dropped first characters (drop caps)
        // and for heading detection / layout analysis.
        guard let pageString = page.string,
              !pageString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let image = renderFullPage(page, fitWidth: pageWidth) {
                return [.snapshot(image)]
            }
            return []
        }
        let strippedPageString = stripLeadingPageNumber(from: pageString)
        let fullText = recoverDropCaps(pageString: strippedPageString, textLines: textLines, page: page, pageBounds: pageBounds)

        // Detect heading lines based on font size (line height)
        let headingTexts = detectHeadings(textLines: textLines)

        // Detect visual content in large gaps between text lines (vector charts, diagrams)
        let gapSnapshots = detectGapContent(textLines: textLines, page: page, pageBounds: pageBounds, pageWidth: pageWidth)

        // Merge detected gap regions into imageRects, but skip gaps that overlap existing XObjects
        var allImageRects = scanResult.imageRects
        let allImages = scanResult.images
        for gap in gapSnapshots {
            let overlapsExisting = scanResult.imageRects.contains { existing in
                existing.intersects(gap.rect)
            }
            if !overlapsExisting {
                allImageRects.append(gap.rect)
            }
        }

        #if DEBUG
        let pageIndex = page.document?.index(for: page) ?? -1
        print("[PDFExtractor] Page \(pageIndex): textLines=\(textLines.count), xobjectRects=\(scanResult.imageRects.count), gapRegions=\(gapSnapshots.count), headings=\(headingTexts.count)")
        if !headingTexts.isEmpty {
            print("[PDFExtractor]   headings: \(headingTexts)")
        }
        let preview = String(fullText.prefix(100)).replacingOccurrences(of: "\n", with: "↵")
        print("[PDFExtractor]   text preview: \(preview)...")
        #endif

        // If no images/forms/gaps on the page, just split text into paragraphs
        if allImageRects.isEmpty {
            let blocks = classifyParagraphs(splitIntoParagraphs(fullText), headingTexts: headingTexts)
            #if DEBUG
            print("[PDFExtractor]   → \(blocks.count) blocks (text-only)")
            #endif
            return blocks
        }

        // With images: interleave text paragraphs and images by Y position
        let blocks = interleaveTextAndImages(
            fullText: fullText,
            textLines: textLines,
            extractedImages: allImages,
            imageRects: allImageRects,
            page: page,
            pageBounds: pageBounds,
            pageWidth: pageWidth,
            headingTexts: headingTexts
        )
        #if DEBUG
        let blockTypes = blocks.map { b -> String in
            switch b {
            case .text(let t): return "text(\(t.prefix(30)))"
            case .heading(let t): return "heading(\(t.prefix(30)))"
            case .image: return "image"
            case .snapshot: return "snapshot"
            }
        }
        print("[PDFExtractor]   → \(blocks.count) blocks: \(blockTypes)")
        #endif
        return blocks
    }

    // MARK: - Diagnostics

    /// Run drop cap diagnostics on all pages. Returns a report string.
    /// Call from a debug UI button or test.
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

            // Run recovery and compare
            let recovered = recoverDropCaps(pageString: strippedPageString, textLines: textLines, page: page, pageBounds: pageBounds)

            // Count fixes on this page
            let pageFixes = countDifferences(original: strippedPageString, recovered: recovered)
            totalFixed += pageFixes

            // Scan recovered text for REMAINING suspicious fragments
            var pageIssues: [(word: String, context: String, confidence: String)] = []

            // Only two patterns — skip line-start lowercase (too many false positives)
            let patterns: [(String, String)] = [
                ("(?<=[.!?»])\\s+([а-яa-z]\\S{2,})", "after-punct"),       // after sentence-end punctuation
                ("(?:^|\\n)\\s*(\\d+\\)\\s*[а-яa-z]\\S{2,})", "numbered"),  // numbered list "3) оздаём"
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

                    // Skip short words and common words
                    if word.count < 3 { continue }
                    if diagnosticCommonLower.contains(word.lowercased()) { continue }

                    // Heuristic: does this word look like a truncated fragment?
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

            // Also check paragraph-start lines (first line or after empty line) — these are higher signal
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

                // Sort by confidence — HIGH first
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

    /// Large set of common Russian words that legitimately start lowercase after punctuation
    private static let diagnosticCommonLower: Set<String> = [
        // Pronouns, particles, prepositions, conjunctions
        "и", "а", "в", "с", "к", "о", "у", "на", "не", "но", "по", "из", "за", "до", "от", "же", "ни",
        "ещё", "еще", "его", "их", "её", "ее", "то", "что", "как", "так", "это", "все", "всё",
        "для", "при", "без", "или", "где", "чем", "вот", "вы", "мы", "он", "она", "они", "оно",
        "ему", "ей", "им", "нас", "вас", "да", "нет", "уже", "ведь", "тут", "там", "тем", "тот",
        "эта", "эти", "той", "том", "если", "чтобы", "когда", "пока", "потому", "поэтому",
        "также", "может", "можно", "нужно", "надо", "просто", "очень", "даже", "только",
        "более", "менее", "около", "после", "перед", "между", "через", "будет", "было", "были",
        "быть", "есть", "этот", "этой", "этих", "этому", "этим",
        // Common verbs and verb forms
        "значит", "стоит", "важно", "например", "однако", "поскольку", "причём", "причем",
        "хотя", "либо", "ибо", "затем", "потом", "сначала", "сперва", "впрочем",
        "следовательно", "соответственно", "разумеется", "конечно", "безусловно",
        "обязательно", "необходимо", "достаточно", "возможно", "вероятно", "наверное",
        "кажется", "видимо", "скорее", "скоро", "точно", "действительно", "обычно",
        "наконец", "иначе", "иногда", "всегда", "никогда", "нигде", "везде", "здесь",
        "отсюда", "оттуда", "откуда", "куда", "зачем", "почему", "сколько",
        "кто", "кого", "кому", "кем", "чья", "чьё", "чей", "чьи",
        // Common nouns, adjectives, adverbs that often follow punctuation
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
        // Common business/tech words from the user's PDF
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
        // Common verbs
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
        // Participles and gerunds (common after punctuation)
        "который", "которая", "которое", "которых", "которым", "которые", "которого", "которой",
        "именно", "особенно", "постепенно", "постоянно", "ежедневно",
        "дальше", "больше", "меньше", "лучше", "хуже", "раньше",
        "наиболее", "наименее",
    ]


    /// Guess the missing prefix for a word fragment using common Russian word patterns.
    /// Returns the string to prepend (1-2 chars), or nil if ambiguous/unknown.
    private static func guessMissingPrefix(fragment: String) -> String? {
        let lower = fragment.lowercased()

        // Table: fragment prefix → missing character(s)
        // Ordered longest-first within each group for correct matching
        let prefixRules: [(prefix: String, insert: String)] = [
            // "от-" derivatives (Отсюда, Открыть, Отдавать, Откуда, Отпугивать, etc.)
            ("тсюда", "О"),     // Отсюда
            ("ткуда", "О"),     // Откуда
            ("ткры", "О"),      // Открыть, Открытый
            ("тдав", "О"),      // Отдавать
            ("тдать", "О"),     // Отдать
            ("тдел", "О"),      // Отдел, Отделение
            ("тказ", "О"),      // Отказ
            ("тклик", "О"),     // Отклик
            ("тклон", "О"),     // Отклонение
            ("тлич", "О"),      // Отличие, Отличный
            ("тнош", "О"),      // Отношение
            ("тправ", "О"),     // Отправить
            ("трасл", "О"),     // Отрасль
            ("тсут", "О"),      // Отсутствие
            ("тчёт", "О"),      // Отчёт
            ("тчет", "О"),      // Отчет
            ("тзыв", "О"),      // Отзыв
            ("тобр", "О"),      // Отобрать
            ("тсеч", "О"),      // Отсечь
            ("тсек", "О"),      // Отсекать
            ("тслеж", "О"),     // Отслеживать
            ("тток", "О"),      // Отток
            ("ттал", "О"),      // Оттолкнуть, Отталкивать
            ("тпугив", "О"),    // Отпугивать
            ("тпуг", "О"),      // Отпугнуть
            // "об-" derivatives (Общее, Обман, etc.)
            ("бщ", "О"),        // Общее, Общий, Общая
            ("бъяв", "О"),      // Объявление
            ("бъект", "О"),     // Объект
            ("бъём", "О"),      // Объём
            ("бъем", "О"),      // Объем
            ("бязат", "О"),     // Обязательно
            ("бласт", "О"),     // Область
            ("бслуж", "О"),     // Обслуживание
            ("бсужд", "О"),     // Обсуждение
            ("бучен", "О"),     // Обучение
            ("бнаруж", "О"),    // Обнаружить
            ("бновл", "О"),     // Обновление
            ("бработ", "О"),    // Обработка
            ("бразо", "О"),     // Образование, Образ
            ("братн", "О"),     // Обратный
            ("бращ", "О"),      // Обращение
            ("бзор", "О"),      // Обзор
            ("бход", "О"),      // Обход
            ("бсто", "О"),      // Обстоятельство
            ("бман", "О"),      // Обман
            // "он-/оф-" derivatives (Онлайн, Оффер, etc.)
            ("нлайн", "О"),     // Онлайн
            ("ффер", "О"),      // Оффер
            ("ффлайн", "О"),    // Оффлайн
            ("ффици", "О"),     // Официальный
            // "К-" words
            ("ейсы", "К"),      // Кейсы
            ("ейс", "К"),       // Кейс
            ("ейтер", "К"),     // Кейтеринг
            // "Н-" words
            ("ейронк", "Н"),    // Нейронка
            ("ейросет", "Н"),   // Нейросеть
            ("ейрон", "Н"),     // Нейрон
            // "П-" words
            ("ятый", "П"),      // Пятый
            ("ятая", "П"),      // Пятая
            ("ятое", "П"),      // Пятое
            ("ять", "П"),       // Пять
            ("яток", "П"),      // Пяток
            // "Ни-" words (2-char prefix)
            ("зкая", "Ни"),     // Низкая
            ("зкий", "Ни"),     // Низкий
            ("зкое", "Ни"),     // Низкое
            ("зких", "Ни"),     // Низких
            ("зком", "Ни"),     // Низком
            ("зко", "Ни"),      // Низко
        ]

        for rule in prefixRules {
            if lower.hasPrefix(rule.prefix) {
                return rule.insert
            }
        }

        return nil
    }

    /// Count character insertions between original and recovered text
    private static func countDifferences(original: String, recovered: String) -> Int {
        // Simple heuristic: count characters that were added
        let diff = recovered.count - original.count
        return max(0, diff)
    }

    // MARK: - Build text from positioned lines

    /// Recover dropped first characters (drop caps) by parsing font ToUnicode CMaps.
    ///
    /// page.string is the cleanest text source but drops styled/decorated first letters
    /// because PDFKit can't decode the special fonts used for drop caps.
    /// This method directly parses the font's ToUnicode CMap table to find the correct
    /// Unicode characters, then inserts them at the right positions.
    private static func recoverDropCaps(
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
        // Catches ". отому что" (should be ". Потому что"), ". ейсы" (should be ". Кейсы")
        if let midLineRegex = try? NSRegularExpression(pattern: "[.!?»]\\s+([а-яa-z]\\S{2,})", options: []) {
            let nsText = text as NSString
            let matches = midLineRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let wordRange = match.range(at: 1)
                let wordStr = nsText.substring(with: wordRange)

                // Extract the word (letters only)
                guard let firstIdx = wordStr.firstIndex(where: { $0.isLetter }),
                      wordStr[firstIdx].isLowercase else { continue }
                let word = String(wordStr[firstIdx...].prefix(while: { $0.isLetter }))
                if commonLower.contains(word) { continue }

                // Use ~15 chars from the lowercase word as searchPrefix
                let fromWord = String(wordStr[firstIdx...])
                let searchPrefix = String(fromWord.prefix(min(15, fromWord.count)))

                // Already covered by Pass 1?
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
                // Lazy render
                if renderedPage == nil {
                    renderedPage = renderPageForOCR(page)
                }
                guard let rendered = renderedPage else { continue }

                // Extend bounds left to capture potential missing first character
                // Use 2.5x line height — drop caps can be wider than regular chars
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

                    // Strategy A: OCR starts with searchPrefix → no missing char (continuation line)
                    // BUT: if the word is clearly a fragment, don't trust this — the crop
                    // might not have captured the missing character
                    let shortPrefix = String(searchPrefix.prefix(min(6, searchPrefix.count))).lowercased()
                    if ocrTrimmed.lowercased().hasPrefix(shortPrefix) {
                        if isLikelyFragment {
                            #if DEBUG
                            print("[PDFExtractor] OCR shows same broken text for fragment '\(searchPrefix.prefix(15))' — crop may be too small, retrying wider")
                            #endif
                            // Try wider crop (full page width from left margin)
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
                            continue  // Not a missing capital, skip
                        }
                    } else {
                        // Strategy B: Search for searchPrefix INSIDE the OCR text.
                        // The crop may include previous line text, so the missing capital
                        // is the character just before where searchPrefix appears in OCR text.
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

            // Strategy 3 (Pass 3): Dictionary-based fragment repair
            // If OCR failed and the word is clearly a fragment, try known prefix patterns
            if insertStr == nil && isLikelyFragment {
                insertStr = guessMissingPrefix(fragment: searchPrefix)
                #if DEBUG
                if let s = insertStr {
                    print("[PDFExtractor] Fragment repair: '\(searchPrefix.prefix(15))' → '\(s)' (dictionary)")
                }
                #endif
            }

            if let s = insertStr {
                // Loop to fix ALL occurrences of this fragment on the page
                while tryInsertStr(s, beforeTextMatching: searchPrefix, in: &text) {
                    insertions += 1
                }
            }
        }

        // Fix doubled uppercase characters (e.g., "ГГлобальная" → "Глобальная")
        fixDoubledCharacters(&text)

        #if DEBUG
        // Validation: only warn about lines that start a new paragraph but still have lowercase
        let resultLines = text.components(separatedBy: .newlines)
        var warnings = 0
        for (i, rLine) in resultLines.enumerated() {
            let trimmed = rLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 3,
                  let f = trimmed.first,
                  f.isLowercase && f.isLetter else { continue }
            // Only warn if this line starts a paragraph (prev line is empty or this is first line)
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

    /// Try to insert a string (1+ chars) before text matching the given continuation string.
    private static func tryInsertStr(_ prefix: String, beforeTextMatching continuation: String, in text: inout String) -> Bool {
        let searchLengths = [20, 12, 8, 5, 3]
        for searchLen in searchLengths {
            guard continuation.count >= searchLen else { continue }
            let searchStr = String(continuation.prefix(searchLen))

            // Search ALL occurrences — earlier ones may already be fixed
            var searchStart = text.startIndex
            while let range = text.range(of: searchStr, range: searchStart..<text.endIndex) {
                let pos = range.lowerBound

                let isAtBoundary = pos == text.startIndex || {
                    let prev = text[text.index(before: pos)]
                    return prev.isWhitespace || prev.isNewline || prev.isPunctuation
                }()

                if isAtBoundary {
                    // Don't double-insert: check if prefix is already there
                    if text[pos...].hasPrefix(prefix + searchStr) {
                        searchStart = range.upperBound
                        continue
                    }
                    // Also check if prefix chars are immediately before pos
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
    /// Example: "ГГлобальная" → "Глобальная"
    private static func fixDoubledCharacters(_ text: inout String) {
        // Match two identical uppercase letters followed by a lowercase letter
        guard let regex = try? NSRegularExpression(
            pattern: "([А-ЯA-ZЁ])\\1([а-яa-zё])", options: []
        ) else { return }

        // Process in reverse to maintain valid indices
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches.reversed() {
            let fullRange = match.range(at: 0)
            let charRange = match.range(at: 1)
            let lowerRange = match.range(at: 2)

            // Check boundary: must be at word start (preceded by whitespace, newline, or start)
            if fullRange.location > 0 {
                let prevCharRange = NSRange(location: fullRange.location - 1, length: 1)
                let prevChar = nsText.substring(with: prevCharRange)
                if let p = prevChar.first, p.isLetter { continue } // Not at word start
            }

            let replacement = nsText.substring(with: charRange) + nsText.substring(with: lowerRange)
            text = (text as NSString).replacingCharacters(in: fullRange, with: replacement)
            #if DEBUG
            print("[PDFExtractor] Fixed doubled char: '\(nsText.substring(with: fullRange))' → '\(replacement)'")
            #endif
        }
    }

    // MARK: - OCR fallback for unresolvable fonts

    /// Render the full PDF page and return the image + scale factor.
    /// Uses getDrawingTransform (same as renderFullPage) for correct coordinates.
    private static func renderPageForOCR(_ page: PDFPage) -> (image: CGImage, scale: CGFloat, outputSize: CGSize)? {
        guard let cgPage = page.pageRef else { return nil }
        let mediaBox = page.bounds(for: .mediaBox)
        let fitWidth: CGFloat = 800  // Sufficient resolution for OCR
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
    /// Uses getDrawingTransform to correctly map PDF coordinates to image pixels,
    /// handling page rotation, cropBox offset, and aspect ratio.
    private static func ocrFromRenderedPage(
        _ fullImage: CGImage,
        pdfBounds: CGRect,
        page: PDFPage,
        imageSize: CGSize,
        imageScale: CGFloat
    ) -> String? {
        guard let cgPage = page.pageRef else { return nil }

        // Get the SAME transform used to render the page
        let drawTransform = cgPage.getDrawingTransform(
            .mediaBox,
            rect: CGRect(origin: .zero, size: imageSize),
            rotate: 0,
            preserveAspectRatio: true
        )

        // Transform PDF bounds through the drawing transform
        let transformed = pdfBounds.applying(drawTransform)

        // Scale to pixel coordinates and flip Y
        // (CGContext has origin at bottom-left, CGImage at top-left)
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
    private struct CMapChar {
        let char: String       // The Unicode character(s)
        let position: CGPoint  // Position in PDF page coordinates
        let fontSize: CGFloat  // Font size used to render this character
    }

    /// Parsed font encoding.
    private struct FontCMap {
        var mapping: [UInt16: String]  // Character code → Unicode string
        var isTwoByte: Bool            // Whether character codes are 2 bytes
        var isSpecial: Bool            // true = font without ToUnicode (drop cap candidate)
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
        var checkedFonts: Set<String> = []  // Fonts we already tried to parse
        var results: [CMapChar] = []

        /// Load font encoding. Tries ToUnicode CMap first, then Encoding/Differences.
        /// Only marks fonts WITHOUT ToUnicode as "special" (drop cap candidates).
        func loadCMapIfNeeded(scanner: OpaquePointer?, fontNamePtr: UnsafePointer<CChar>) {
            guard let fontName = currentFontName else { return }
            if fontCMaps[fontName] != nil || checkedFonts.contains(fontName) { return }
            checkedFonts.insert(fontName)
            guard let scanner else { return }

            let contentStream = CGPDFScannerGetContentStream(scanner)
            guard let fontObj = CGPDFContentStreamGetResource(contentStream, "Font", fontNamePtr) else { return }
            var fontDict: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(fontObj, .dictionary, &fontDict), let fd = fontDict else { return }

            // Try 1: ToUnicode CMap — PDFKit handles these fonts, mark as NOT special
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

            // Try 2: Encoding/Differences — font without ToUnicode, mark as SPECIAL
            #if DEBUG
            // Log font details for debugging unresolvable fonts
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
                // Mark as special with empty mapping so OCR fallback can handle it
                fontCMaps[fontName] = FontCMap(mapping: [:], isTwoByte: false, isSpecial: true)
                return
            }

            // Encoding can be a dictionary (with Differences) or a name
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

        /// Only record text from "special" fonts (without ToUnicode = drop cap candidates).
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

        /// Parse a PDF Differences array: [code1 /glyphName1 /glyphName2 code2 /glyphName3 ...]
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

        /// Resolve a PostScript glyph name to Unicode.
        static func resolveGlyphName(_ name: String) -> String? {
            // uniXXXX format (e.g., "uni041F" → П)
            if name.hasPrefix("uni"), name.count == 7 {
                let hex = String(name.dropFirst(3))
                if let cp = UInt32(hex, radix: 16), let s = Unicode.Scalar(cp) {
                    return String(s)
                }
            }
            // Direct lookup in glyph name table
            return glyphNameMap[name]
        }

        /// Adobe Glyph List subset: common Cyrillic + Latin + punctuation
        static let glyphNameMap: [String: String] = {
            var m: [String: String] = [:]
            // Cyrillic uppercase (afii10017=А ... afii10049=Я)
            let cyrUpperCodes: [(String, UInt32)] = [
                ("afii10017", 0x0410), ("afii10018", 0x0411), ("afii10019", 0x0412),
                ("afii10020", 0x0413), ("afii10021", 0x0414), ("afii10022", 0x0415),
                ("afii10023", 0x0401), // Ё
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
            // Cyrillic lowercase (afii10065=а ... afii10097=я)
            let cyrLowerCodes: [(String, UInt32)] = [
                ("afii10065", 0x0430), ("afii10066", 0x0431), ("afii10067", 0x0432),
                ("afii10068", 0x0433), ("afii10069", 0x0434), ("afii10070", 0x0435),
                ("afii10071", 0x0451), // ё
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
            // Latin A-Z, a-z (single-char glyph names)
            for code: UInt32 in 0x0041...0x005A {
                if let s = Unicode.Scalar(code) { m[String(Character(s))] = String(s) }
            }
            for code: UInt32 in 0x0061...0x007A {
                if let s = Unicode.Scalar(code) { m[String(Character(s))] = String(s) }
            }
            // Digits
            let digitNames = ["zero","one","two","three","four","five","six","seven","eight","nine"]
            for (i, name) in digitNames.enumerated() { m[name] = String(i) }
            // Common punctuation
            m["space"] = " "; m["period"] = "."; m["comma"] = ","; m["colon"] = ":"
            m["semicolon"] = ";"; m["hyphen"] = "-"; m["endash"] = "–"; m["emdash"] = "—"
            m["quoteleft"] = "\u{2018}"; m["quoteright"] = "\u{2019}"
            m["quotedblleft"] = "\u{201C}"; m["quotedblright"] = "\u{201D}"
            m["guillemotleft"] = "«"; m["guillemotright"] = "»"
            m["exclam"] = "!"; m["question"] = "?"; m["parenleft"] = "("; m["parenright"] = ")"
            m["numbersign"] = "#"; m["numero"] = "№"
            return m
        }()

        // MARK: - CMap parsing (static to avoid capturing context)

        static func parseCMap(_ data: Data) -> FontCMap {
            guard let cmapString = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .ascii) else {
                return FontCMap(mapping: [:], isTwoByte: false, isSpecial: false)
            }

            var mapping: [UInt16: String] = [:]
            var isTwoByte = false

            // Determine byte width from codespacerange
            if let range = cmapString.range(of: "begincodespacerange") {
                let after = cmapString[range.upperBound...]
                if let hexStart = after.range(of: "<") {
                    let hexContent = after[hexStart.upperBound...]
                    if let hexEnd = hexContent.firstIndex(of: ">") {
                        isTwoByte = hexContent.distance(from: hexContent.startIndex, to: hexEnd) >= 4
                    }
                }
            }

            // Parse beginbfchar sections: <srcCode> <dstUnicode>
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

            // Parse beginbfrange sections: <lo> <hi> <startUnicode>
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
            // Support 2-digit (single byte ASCII) or 4n-digit (BMP Unicode) hex strings
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
    /// Returns positioned characters that PDFKit's page.string may have missed.
    private static func extractCMapCharacters(from cgPage: CGPDFPage) -> [CMapChar] {
        let context = TextScanContext()
        guard let operatorTable = CGPDFOperatorTableCreate() else { return [] }

        // q — save graphics state
        CGPDFOperatorTableSetCallback(operatorTable, "q") { _, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            ctx.stateStack.append((ctx.ctm, ctx.currentFontName, ctx.currentFontSize))
        }

        // Q — restore graphics state
        CGPDFOperatorTableSetCallback(operatorTable, "Q") { _, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            if let saved = ctx.stateStack.popLast() {
                ctx.ctm = saved.ctm
                ctx.currentFontName = saved.fontName
                ctx.currentFontSize = saved.fontSize
            }
        }

        // cm — concatenate matrix
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

        // BT — begin text object
        CGPDFOperatorTableSetCallback(operatorTable, "BT") { _, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            ctx.textMatrix = .identity
            ctx.lineMatrix = .identity
        }

        // Tf — set font and size
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

        // Tm — set text matrix
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

        // Td — move text position
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

        // TD — move text position (same as Td, also sets leading)
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

        // Tj — show text string
        CGPDFOperatorTableSetCallback(operatorTable, "Tj") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            var pdfString: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &pdfString), let str = pdfString else { return }
            ctx.decodeAndRecord(string: str)
        }

        // TJ — show text array (strings interspersed with kerning adjustments)
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

        // ' — move to next line and show text
        CGPDFOperatorTableSetCallback(operatorTable, "'") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<TextScanContext>.fromOpaque(info).takeUnretainedValue()
            var pdfString: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &pdfString), let str = pdfString else { return }
            ctx.decodeAndRecord(string: str)
        }

        // IMPORTANT: CGPDFScannerScan is synchronous. passUnretained is safe here
        // because withExtendedLifetime keeps `context` alive until the scan completes.
        // Do NOT make this async without switching to passRetained/takeRetainedValue.
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

    // MARK: - Text paragraph splitting

    /// Split full page text into paragraphs using multiple heuristics:
    /// 1. Blank lines → always break
    /// 2. Short lines → likely heading or paragraph end
    /// 3. Sentence-ending punctuation + next line starts with capital → paragraph break
    private static func splitIntoParagraphs(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        let nonEmptyLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
                                 .filter { !$0.isEmpty }
        guard !nonEmptyLines.isEmpty else { return [] }

        // Find typical line length to detect short (paragraph-ending) lines
        let lengths = nonEmptyLines.map { $0.count }
        let sortedLengths = lengths.sorted()
        let typicalLength = sortedLengths[min(sortedLengths.count * 3 / 4, sortedLengths.count - 1)]
        let shortThreshold = max(typicalLength * 2 / 3, 15)

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

            let shouldBreak = isShortLine ||
                              (endsWithSentence && nextStartsUpper && currentLines.count >= 2)

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
    private static func joinLines(_ lines: [String]) -> String {
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

    // MARK: - Heading detection

    /// Detect heading lines by comparing line heights to the median.
    /// Lines significantly taller than typical body text are likely headings.
    private static func detectHeadings(textLines: [(bounds: CGRect, text: String)]) -> Set<String> {
        guard textLines.count >= 3 else { return [] }

        let heights = textLines.map { $0.bounds.height }.sorted()
        let medianHeight = heights[heights.count / 2]
        guard medianHeight > 0 else { return [] }

        let bulletPrefixes: [Character] = ["•", "·", "‣", "▪", "▸", "-", "–", "—"]
        var headingTexts = Set<String>()
        for line in textLines {
            let heightRatio = line.bounds.height / medianHeight
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Heading: significantly larger font AND reasonably short text
            // Exclude:
            //  - bullet/list lines (symbols inflate line height)
            //  - multi-line entries (contain \n — these are tall selections, not headings)
            //  - entries starting with punctuation (garbage from styled text)
            //  - very short entries (< 5 chars — likely garbage)
            if heightRatio > 1.25 && text.count >= 5 && text.count < 120 {
                let startsWithBullet = text.first.map { bulletPrefixes.contains($0) || $0.isNumber } ?? false
                let containsNewline = text.contains("\n")
                let startsWithPunctuation = text.first?.isPunctuation == true || text.first?.isSymbol == true
                if !startsWithBullet && !containsNewline && !startsWithPunctuation {
                    headingTexts.insert(text)
                }
            }
        }
        return headingTexts
    }

    /// Classify paragraphs as headings or body text based on detected heading lines.
    private static func classifyParagraphs(_ paragraphs: [String], headingTexts: Set<String>) -> [ContentBlock] {
        paragraphs.compactMap { para in
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            // Skip garbage: very short strings that are just punctuation/symbols/single chars
            if trimmed.count <= 3 && trimmed.allSatisfy({ !$0.isLetter || $0.isWhitespace }) {
                return nil
            }

            // Check if this paragraph matches a heading line
            // Both must be similar length — a heading shouldn't match a full paragraph
            if trimmed.count >= 5 && trimmed.count < 120 && headingTexts.contains(where: { heading in
                heading.count >= 5 && (trimmed.hasPrefix(heading) || heading.hasPrefix(trimmed)) &&
                Double(min(trimmed.count, heading.count)) / Double(max(trimmed.count, heading.count)) > 0.5
            }) {
                return .heading(trimmed)
            }
            return .text(trimmed)
        }
    }

    // MARK: - Gap content detection (vector charts, diagrams)

    private struct GapRegion {
        let rect: CGRect
    }

    /// Detect large vertical gaps between text lines that likely contain visual content
    /// (vector-drawn charts, diagrams, tables) not captured by XObject scanning.
    private static func detectGapContent(
        textLines: [(bounds: CGRect, text: String)],
        page: PDFPage,
        pageBounds: CGRect,
        pageWidth: CGFloat
    ) -> [GapRegion] {
        guard textLines.count >= 2 else { return [] }

        // textLines are sorted by maxY descending (top-to-bottom in PDF coords)
        // Calculate typical line spacing
        var lineSpacings: [CGFloat] = []
        for i in 1..<textLines.count {
            let gap = textLines[i - 1].bounds.minY - textLines[i].bounds.maxY
            if gap > 0 {
                lineSpacings.append(gap)
            }
        }
        guard !lineSpacings.isEmpty else { return [] }

        let sortedSpacings = lineSpacings.sorted()
        let medianSpacing = sortedSpacings[sortedSpacings.count / 2]
        // A gap must be at least 3x median spacing and at least 40pt to be visual content
        let gapThreshold = max(medianSpacing * 3, 40)

        var gaps: [GapRegion] = []
        for i in 1..<textLines.count {
            let topLineBottom = textLines[i - 1].bounds.minY
            let bottomLineTop = textLines[i].bounds.maxY
            let gapHeight = topLineBottom - bottomLineTop

            if gapHeight > gapThreshold && gapHeight.isFinite && gapHeight < pageBounds.height {
                // Build a rect covering this gap region (full page width)
                let gapRect = CGRect(
                    x: pageBounds.minX,
                    y: bottomLineTop,
                    width: pageBounds.width,
                    height: gapHeight
                )
                gaps.append(GapRegion(rect: gapRect))
            }
        }

        // Also check gap between page top and first text line
        let firstLineTop = textLines.first!.bounds.maxY
        let topGap = pageBounds.maxY - firstLineTop
        if topGap > gapThreshold && topGap.isFinite && topGap < pageBounds.height {
            gaps.append(GapRegion(rect: CGRect(
                x: pageBounds.minX,
                y: firstLineTop,
                width: pageBounds.width,
                height: topGap
            )))
        }

        return gaps
    }

    // MARK: - Text + image interleaving

    /// Interleave text paragraphs with images based on Y positions.
    /// Uses extracted CGImages when available, falls back to rendering snapshots.
    private static func interleaveTextAndImages(
        fullText: String,
        textLines: [(bounds: CGRect, text: String)],
        extractedImages: [ExtractedImage],
        imageRects: [CGRect],
        page: PDFPage,
        pageBounds: CGRect,
        pageWidth: CGFloat,
        headingTexts: Set<String> = []
    ) -> [ContentBlock] {
        let paragraphs = splitIntoParagraphs(fullText)
        let pageHeight = pageBounds.height

        // Build image blocks: use CGImage if available, snapshot otherwise
        struct PositionedImage {
            let block: ContentBlock
            let fraction: CGFloat  // 0 = top of page, 1 = bottom
        }

        var positionedImages: [PositionedImage] = []
        for rect in imageRects {
            let fraction = 1.0 - (rect.midY - pageBounds.minY) / pageHeight
            let clampedFraction = min(max(fraction, 0), 1)

            // Check if we have a matching extracted CGImage for this rect
            if let extracted = extractedImages.first(where: { $0.rect.intersects(rect) }) {
                // Scale the raw CGImage to pageWidth — PDF images may have arbitrary
                // native pixel dimensions unrelated to screen size
                let uiImage = scaleImageToWidth(extracted.cgImage, targetWidth: pageWidth)
                positionedImages.append(PositionedImage(block: .image(uiImage), fraction: clampedFraction))
            } else {
                // Render the region as a snapshot
                if let img = renderRegion(of: page, region: rect, fitWidth: pageWidth) {
                    positionedImages.append(PositionedImage(block: .snapshot(img), fraction: clampedFraction))
                }
            }
        }

        // Sort images top-to-bottom (ascending fraction)
        positionedImages.sort { $0.fraction < $1.fraction }

        guard !paragraphs.isEmpty else {
            return positionedImages.map { $0.block }
        }

        // Build interleaved blocks
        var blocks: [ContentBlock] = []
        var nextImageIdx = 0

        for (paraIdx, para) in paragraphs.enumerated() {
            let paraFraction = CGFloat(paraIdx) / CGFloat(max(paragraphs.count - 1, 1))

            // Insert images that should appear before this paragraph
            while nextImageIdx < positionedImages.count,
                  positionedImages[nextImageIdx].fraction <= paraFraction + 0.05 {
                blocks.append(positionedImages[nextImageIdx].block)
                nextImageIdx += 1
            }

            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Skip garbage: very short non-letter strings
            if trimmed.count <= 3 && trimmed.allSatisfy({ !$0.isLetter || $0.isWhitespace }) {
                continue
            }
            if trimmed.count >= 5 && trimmed.count < 120 && headingTexts.contains(where: { heading in
                heading.count >= 5 && (trimmed.hasPrefix(heading) || heading.hasPrefix(trimmed)) &&
                Double(min(trimmed.count, heading.count)) / Double(max(trimmed.count, heading.count)) > 0.5
            }) {
                blocks.append(.heading(trimmed))
            } else {
                blocks.append(.text(trimmed))
            }
        }

        // Append remaining images at the end
        while nextImageIdx < positionedImages.count {
            blocks.append(positionedImages[nextImageIdx].block)
            nextImageIdx += 1
        }

        return blocks
    }

    // MARK: - CGPDFScanner content extraction

    /// Scan a PDF page for images, rectangles, lines, and font usage.
    private static func scanPageContent(from cgPage: CGPDFPage) -> ScannerContext {
        let context = ScannerContext()
        context.pageBounds = cgPage.getBoxRect(.mediaBox)

        guard let operatorTable = CGPDFOperatorTableCreate() else { return context }

        // q — save graphics state
        CGPDFOperatorTableSetCallback(operatorTable, "q") { _, info in
            guard let info else { return }
            let ctx = Unmanaged<ScannerContext>.fromOpaque(info).takeUnretainedValue()
            ctx.stateStack.append(ctx.ctm)
        }

        // Q — restore graphics state
        CGPDFOperatorTableSetCallback(operatorTable, "Q") { _, info in
            guard let info else { return }
            let ctx = Unmanaged<ScannerContext>.fromOpaque(info).takeUnretainedValue()
            if let saved = ctx.stateStack.popLast() {
                ctx.ctm = saved
            }
        }

        // cm — concatenate matrix
        CGPDFOperatorTableSetCallback(operatorTable, "cm") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<ScannerContext>.fromOpaque(info).takeUnretainedValue()
            var a: CGPDFReal = 0, b: CGPDFReal = 0, c: CGPDFReal = 0
            var d: CGPDFReal = 0, tx: CGPDFReal = 0, ty: CGPDFReal = 0
            CGPDFScannerPopNumber(scanner, &ty)
            CGPDFScannerPopNumber(scanner, &tx)
            CGPDFScannerPopNumber(scanner, &d)
            CGPDFScannerPopNumber(scanner, &c)
            CGPDFScannerPopNumber(scanner, &b)
            CGPDFScannerPopNumber(scanner, &a)
            let matrix = CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
            // PDF spec: CTM' = M × CTM (new matrix applied first, then existing CTM)
            ctx.ctm = matrix.concatenating(ctx.ctm)
        }

        // Do — invoke XObject (images and form XObjects are drawn here)
        CGPDFOperatorTableSetCallback(operatorTable, "Do") { scanner, info in
            guard let info else { return }
            let ctx = Unmanaged<ScannerContext>.fromOpaque(info).takeUnretainedValue()

            var namePtr: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &namePtr), let name = namePtr else { return }

            let contentStream = CGPDFScannerGetContentStream(scanner)
            guard let xobject = CGPDFContentStreamGetResource(contentStream, "XObject", name)
            else { return }

            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(xobject, .stream, &stream), let pdfStream = stream else { return }
            guard let dict = CGPDFStreamGetDictionary(pdfStream) else { return }

            var subtypePtr: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dict, "Subtype", &subtypePtr),
                  let subtype = subtypePtr else { return }

            let subtypeStr = String(cString: subtype)

            // XObject is drawn in a 1×1 unit square, CTM transforms it
            let xobjRect = CGRect(x: 0, y: 0, width: 1, height: 1).applying(ctx.ctm)
            // Skip tiny rendered objects (< 30pt on page)
            guard abs(xobjRect.width) > 30 && abs(xobjRect.height) > 30 else { return }
            let normalizedRect = xobjRect.standardized

            if subtypeStr == "Image" {
                // Always record the rect so we can render as snapshot if CGImage fails
                ctx.imageRects.append(normalizedRect)

                // Try to extract CGImage (may fail for complex color spaces)
                var width: CGPDFInteger = 0, height: CGPDFInteger = 0
                CGPDFDictionaryGetInteger(dict, "Width", &width)
                CGPDFDictionaryGetInteger(dict, "Height", &height)
                if width > 20 && height > 20,
                   let cgImage = extractCGImageFromStream(pdfStream, dict: dict) {
                    ctx.images.append(ExtractedImage(cgImage: cgImage, rect: normalizedRect))
                }
            } else if subtypeStr == "Form" {
                // Form XObjects may contain images, diagrams, or complex compositions.
                // Skip only truly full-page forms (backgrounds, watermarks, templates)
                // by checking if the form covers ~the entire page dimensions
                let isFullPage = normalizedRect.width > ctx.pageBounds.width * 0.9 &&
                                 normalizedRect.height > ctx.pageBounds.height * 0.9
                if !isFullPage {
                    ctx.imageRects.append(normalizedRect)
                }
            }
        }

        // IMPORTANT: CGPDFScannerScan is synchronous. passUnretained is safe here
        // because withExtendedLifetime keeps `context` alive until the scan completes.
        // Do NOT make this async without switching to passRetained/takeRetainedValue.
        let contentStream = CGPDFContentStreamCreateWithPage(cgPage)
        let opaqueCtx = Unmanaged.passUnretained(context).toOpaque()
        let scanner = CGPDFScannerCreate(contentStream, operatorTable, opaqueCtx)

        _ = withExtendedLifetime(context) {
            CGPDFScannerScan(scanner)
        }
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(contentStream)
        CGPDFOperatorTableRelease(operatorTable)

        return context
    }

    /// Extract CGImage from a PDF image stream.
    fileprivate static func extractCGImage(from stream: CGPDFStreamRef, dict: CGPDFDictionaryRef) -> CGImage? {
        var format: CGPDFDataFormat = .raw
        guard let data = CGPDFStreamCopyData(stream, &format) else { return nil }

        // JPEG — create directly
        if format == .JPEG2000 || format == .jpegEncoded {
            guard let provider = CGDataProvider(data: data) else { return nil }
            return CGImage(
                jpegDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        }

        // Raw pixel data — reconstruct CGImage
        var width: CGPDFInteger = 0, height: CGPDFInteger = 0, bpc: CGPDFInteger = 0
        CGPDFDictionaryGetInteger(dict, "Width", &width)
        CGPDFDictionaryGetInteger(dict, "Height", &height)
        CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bpc)
        guard width > 0, height > 0, bpc > 0 else { return nil }

        // Determine color space
        let colorSpace: CGColorSpace
        var csNamePtr: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(dict, "ColorSpace", &csNamePtr), let csName = csNamePtr {
            switch String(cString: csName) {
            case "DeviceGray": colorSpace = CGColorSpaceCreateDeviceGray()
            case "DeviceCMYK": colorSpace = CGColorSpace(name: CGColorSpace.genericCMYK) ?? CGColorSpaceCreateDeviceRGB()
            default: colorSpace = CGColorSpaceCreateDeviceRGB()
            }
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB()
        }

        let components = colorSpace.numberOfComponents
        let bitsPerPixel = Int(bpc) * components
        let bytesPerRow = (Int(width) * bitsPerPixel + 7) / 8

        guard let provider = CGDataProvider(data: data) else { return nil }

        return CGImage(
            width: Int(width),
            height: Int(height),
            bitsPerComponent: Int(bpc),
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    // MARK: - Scanner context (tracks CTM, paths, fonts for detection)

    private class ScannerContext {
        var ctm: CGAffineTransform = .identity
        var stateStack: [CGAffineTransform] = []
        var images: [ExtractedImage] = []       // Successfully extracted CGImages
        var imageRects: [CGRect] = []           // ALL image/form XObject positions (for snapshot fallback)
        var pageBounds: CGRect = .zero          // Page bounds for relative size filtering
    }

    /// Detect multi-column layout by clustering text line left margins.
    private static func detectMultiColumnLayout(textLines: [(bounds: CGRect, text: String)], pageBounds: CGRect) -> Bool {
        guard textLines.count >= 6 else { return false }

        // Cluster left margins (X positions)
        let leftMargins = textLines.map { $0.bounds.minX }
        let sorted = leftMargins.sorted()

        // Find distinct margin clusters (gap > 30% of page width between clusters)
        let clusterGap = pageBounds.width * 0.15
        var clusters: [[CGFloat]] = [[sorted[0]]]

        for i in 1..<sorted.count {
            if sorted[i] - sorted[i - 1] > clusterGap {
                clusters.append([sorted[i]])
            } else {
                clusters[clusters.count - 1].append(sorted[i])
            }
        }

        // Filter clusters with enough lines (at least 3 each)
        let significantClusters = clusters.filter { $0.count >= 3 }

        // Multi-column if 2+ distinct margin clusters with sufficient horizontal separation
        // AND vertical overlap (lines at the same Y in both clusters = side-by-side columns)
        if significantClusters.count >= 2 {
            let firstClusterAvg = significantClusters[0].reduce(0, +) / CGFloat(significantClusters[0].count)
            let secondClusterAvg = significantClusters[1].reduce(0, +) / CGFloat(significantClusters[1].count)
            guard abs(secondClusterAvg - firstClusterAvg) > pageBounds.width * 0.25 else { return false }

            // Verify vertical overlap: true columns have lines at overlapping Y positions
            let halfGap = clusterGap / 2
            let col1Lines = textLines.filter { abs($0.bounds.minX - firstClusterAvg) < halfGap }
            let col2Lines = textLines.filter { abs($0.bounds.minX - secondClusterAvg) < halfGap }
            let col2MidYs = col2Lines.map { $0.bounds.midY }.sorted()
            let hasVerticalOverlap = col1Lines.contains { line1 in
                let target = line1.bounds.midY
                // Binary search for nearest midY in col2
                var lo = 0, hi = col2MidYs.count - 1
                while lo <= hi {
                    let mid = (lo + hi) / 2
                    if abs(col2MidYs[mid] - target) < 20 { return true }
                    if col2MidYs[mid] < target { lo = mid + 1 } else { hi = mid - 1 }
                }
                return false
            }
            return hasVerticalOverlap
        }

        return false
    }

    // MARK: - Text quality assessment

    enum TextQuality {
        case good, poor
    }

    static func assessTextQuality(page: PDFPage, pageBounds: CGRect) -> TextQuality {
        let text = page.string ?? ""
        let charCount = text.count

        if charCount < 30 {
            return .poor
        }

        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        if words.isEmpty { return .poor }

        let reasonableWords = words.filter { $0.count >= 2 && $0.count <= 25 }
        let ratio = Double(reasonableWords.count) / Double(words.count)
        if ratio < 0.3 { return .poor }

        return .good
    }

    // MARK: - Rendering

    /// Scale a CGImage to a target width (points), preserving aspect ratio.
    /// Produces a @2x UIImage for Retina displays.
    private static func scaleImageToWidth(_ cgImage: CGImage, targetWidth: CGFloat) -> UIImage {
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let scale: CGFloat = 2.0 // Retina
        let aspectRatio = srcH / max(srcW, 1)
        let targetH = targetWidth * aspectRatio

        let pixelW = Int(targetWidth * scale)
        let pixelH = Int(targetH * scale)

        // If the source is already close to target size, skip re-rendering
        if abs(srcW - CGFloat(pixelW)) < 4 && abs(srcH - CGFloat(pixelH)) < 4 {
            return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetWidth, height: targetH))
        return renderer.image { ctx in
            let drawRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetH)
            UIImage(cgImage: cgImage).draw(in: drawRect)
        }
    }

    /// Render a specific region of a PDF page to a UIImage.
    static func renderRegion(of page: PDFPage, region: CGRect, fitWidth: CGFloat) -> UIImage? {
        guard let cgPage = page.pageRef,
              region.width > 0 && region.height > 0,
              region.width.isFinite && region.height.isFinite else { return nil }

        // Scale so the REGION fills fitWidth (not the whole page)
        let scaleFactor = fitWidth / region.width
        let outputSize = CGSize(
            width: fitWidth,
            height: region.height * scaleFactor
        )
        // Use 2x scale, but reduce if the resulting bitmap would be too large
        var scale: CGFloat = 2.0
        while scale > 0.5 {
            let pw = Int(ceil(outputSize.width * scale))
            let ph = Int(ceil(outputSize.height * scale))
            if pw > 0 && ph > 0 && pw <= 8192 && ph <= 8192 { break }
            scale *= 0.5
        }

        let pixelW = Int(ceil(outputSize.width * scale))
        let pixelH = Int(ceil(outputSize.height * scale))
        guard pixelW > 0, pixelH > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        // Clear with transparent background (avoids white blocks in dark themes)
        ctx.clear(CGRect(origin: .zero, size: outputSize))

        ctx.scaleBy(x: scaleFactor, y: scaleFactor)
        // Translate FIRST so region.origin maps to (0,0), THEN draw.
        // No clip needed — the context is already sized to the region.
        ctx.translateBy(x: -region.origin.x, y: -region.origin.y)
        ctx.drawPDFPage(cgPage)

        guard let cgImage = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    /// Render a full PDF page fitted to a given width.
    static func renderFullPage(_ page: PDFPage, fitWidth: CGFloat) -> UIImage? {
        guard let cgPage = page.pageRef else { return nil }
        let mediaBox = page.bounds(for: .mediaBox)
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
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}

// Free function accessible from C callbacks (can't capture Self in C closures)
private func extractCGImageFromStream(_ stream: CGPDFStreamRef, dict: CGPDFDictionaryRef) -> CGImage? {
    PDFContentExtractor.extractCGImage(from: stream, dict: dict)
}
