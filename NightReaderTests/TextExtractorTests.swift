import XCTest
@testable import NightReader

// MARK: - Тесты для TextExtractor

final class TextExtractorTests: XCTestCase {

    // MARK: - splitIntoParagraphs

    /// Пустой ввод должен вернуть пустой массив
    func testSplitIntoParagraphs_emptyInput() {
        let result = TextExtractor.splitIntoParagraphs("")
        XCTAssertEqual(result, [])
    }

    /// Одна строка — один абзац
    func testSplitIntoParagraphs_singleLine() {
        let result = TextExtractor.splitIntoParagraphs("Привет мир")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first, "Привет мир")
    }

    /// Несколько абзацев, разделённых пустой строкой
    func testSplitIntoParagraphs_multipleWithBlankLines() {
        let input = """
        Первый абзац текста здесь.

        Второй абзац текста здесь.

        Третий абзац текста здесь.
        """
        let result = TextExtractor.splitIntoParagraphs(input)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result[0].contains("Первый"))
        XCTAssertTrue(result[1].contains("Второй"))
        XCTAssertTrue(result[2].contains("Третий"))
    }

    /// Короткие строки, заканчивающиеся точкой — разрыв абзаца
    func testSplitIntoParagraphs_shortLinesEndingSentence() {
        let input = "Заголовок."
        let result = TextExtractor.splitIntoParagraphs(input)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result[0].contains("Заголовок"))
    }

    /// Перенос через дефис между строками должен склеиваться в joinLines
    func testSplitIntoParagraphs_hyphenation() {
        // Строки с переносом внутри одного абзаца
        let input = "Это технол-\nогия будущего"
        let result = TextExtractor.splitIntoParagraphs(input)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].contains("технология"))
    }

    // MARK: - joinLines

    /// Одна строка возвращается без изменений
    func testJoinLines_singleLine() {
        let result = TextExtractor.joinLines(["Привет мир"])
        XCTAssertEqual(result, "Привет мир")
    }

    /// Дегифенация: "технол-" + "огия" → "технология"
    func testJoinLines_dehyphenation() {
        let result = TextExtractor.joinLines(["технол-", "огия"])
        XCTAssertEqual(result, "технология")
    }

    /// Составные слова сохраняются: "из-за" не склеивается, если следующая строка с заглавной
    func testJoinLines_preserveCompoundWords() {
        let result = TextExtractor.joinLines(["из-за", "Этого"])
        // "из-за" + заглавная "Э" → пробел, а не склейка
        XCTAssertEqual(result, "из-за Этого")
    }

    /// Обычное соединение строк через пробел
    func testJoinLines_regularJoinWithSpace() {
        let result = TextExtractor.joinLines(["первая строка", "вторая строка"])
        XCTAssertEqual(result, "первая строка вторая строка")
    }

    /// Пустой массив — пустая строка
    func testJoinLines_emptyArray() {
        let result = TextExtractor.joinLines([])
        XCTAssertEqual(result, "")
    }

    // MARK: - isFragment

    /// "ейсы" (от "Кейсы") — фрагмент
    func testIsFragment_ейсы() {
        XCTAssertTrue(TextExtractor.isFragment("ейсы"))
    }

    /// "тсюда" — содержит невалидный кластер "тс" в начале
    func testIsFragment_тсюда() {
        XCTAssertTrue(TextExtractor.isFragment("тсюда"))
    }

    /// "привет" — обычное слово, не фрагмент
    func testIsFragment_привет() {
        XCTAssertFalse(TextExtractor.isFragment("привет"))
    }

    /// "система" — обычное слово, не фрагмент
    func testIsFragment_система() {
        XCTAssertFalse(TextExtractor.isFragment("система"))
    }

    /// Одна буква — не фрагмент (кластер из одного согласного всегда валиден)
    func testIsFragment_singleLetter() {
        XCTAssertFalse(TextExtractor.isFragment("к"))
    }

    // MARK: - stripLeadingPageNumber

    /// Номер на отдельной строке сверху удаляется
    func testStripPageNumber_numberOnOwnLineAtTop() {
        let input = "6\nГлобальная экономика"
        let result = TextExtractor.stripLeadingPageNumber(from: input)
        XCTAssertEqual(result, "Глобальная экономика")
    }

    /// Инлайн-номер, совпадающий с индексом страницы, удаляется
    func testStripPageNumber_inlineMatchingPageIndex() {
        let input = "42 Глобальная экономика"
        let result = TextExtractor.stripLeadingPageNumber(from: input, pageIndex: 42)
        XCTAssertEqual(result, "Глобальная экономика")
    }

    /// Номер на отдельной строке снизу удаляется
    func testStripPageNumber_numberAtBottom() {
        let input = "Текст страницы\n15"
        let result = TextExtractor.stripLeadingPageNumber(from: input)
        XCTAssertEqual(result, "Текст страницы")
    }

    /// Нет номера для удаления — текст не меняется
    func testStripPageNumber_noNumberToStrip() {
        let input = "Обычный текст без номеров"
        let result = TextExtractor.stripLeadingPageNumber(from: input, pageIndex: 99)
        XCTAssertEqual(result, "Обычный текст без номеров")
    }

    // MARK: - joinLines broken word fix

    /// Single uppercase letter at end of line + lowercase start → join without space
    func testJoinLines_brokenWordSingleUppercase() {
        XCTAssertEqual(TextExtractor.joinLines(["О", "пыта"]), "Опыта")
        XCTAssertEqual(TextExtractor.joinLines(["П", "ри этом"]), "При этом")
        XCTAssertEqual(TextExtractor.joinLines(["К", "ейсы из"]), "Кейсы из")
        XCTAssertEqual(TextExtractor.joinLines(["Н", "а них"]), "На них")
    }

    /// Normal lines (not broken words) should still get spaces
    func testJoinLines_normalLines() {
        XCTAssertEqual(TextExtractor.joinLines(["Первая строка.", "Вторая строка."]), "Первая строка. Вторая строка.")
    }

    /// Lowercase prepositions should keep space
    func testJoinLines_lowercasePreposition() {
        XCTAssertEqual(TextExtractor.joinLines(["о", "важном"]), "о важном")
    }

    /// Hyphenated word join
    func testJoinLines_hyphenatedWord() {
        XCTAssertEqual(TextExtractor.joinLines(["технол-", "огия"]), "технология")
    }
}
