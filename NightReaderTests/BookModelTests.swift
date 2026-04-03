import XCTest
@testable import NightReader

// MARK: - Тесты для модели Book

final class BookModelTests: XCTestCase {

    // MARK: - formattedReadingTime

    /// Меньше 60 секунд — возвращает nil
    func testFormattedReadingTime_lessThan60seconds() {
        let book = Book(title: "Тест", fileName: "test.pdf")
        book.totalReadingTime = 30
        XCTAssertNil(book.formattedReadingTime)
    }

    /// Ровно 60 секунд — "1m"
    func testFormattedReadingTime_exactly60seconds() {
        let book = Book(title: "Тест", fileName: "test.pdf")
        book.totalReadingTime = 60
        XCTAssertEqual(book.formattedReadingTime, "1m")
    }

    /// 2700 секунд (45 минут) — "45m"
    func testFormattedReadingTime_45minutes() {
        let book = Book(title: "Тест", fileName: "test.pdf")
        book.totalReadingTime = 2700
        XCTAssertEqual(book.formattedReadingTime, "45m")
    }

    /// 8100 секунд (2 часа 15 минут) — "2h 15m"
    func testFormattedReadingTime_2hours15minutes() {
        let book = Book(title: "Тест", fileName: "test.pdf")
        book.totalReadingTime = 8100
        XCTAssertEqual(book.formattedReadingTime, "2h 15m")
    }

    /// 3600 секунд (ровно 1 час) — "1h"
    func testFormattedReadingTime_exactly1hour() {
        let book = Book(title: "Тест", fileName: "test.pdf")
        book.totalReadingTime = 3600
        XCTAssertEqual(book.formattedReadingTime, "1h")
    }

    // MARK: - renderingMode

    /// Чтение и запись renderingMode через computed property
    func testRenderingMode_simpleRoundtrip() {
        let book = Book(title: "Тест", fileName: "test.pdf")
        // По умолчанию .simple
        XCTAssertEqual(book.renderingMode, .simple)

        book.renderingMode = .smart
        XCTAssertEqual(book.renderingMode, .smart)
        XCTAssertEqual(book.renderingModeRaw, "smart")

        book.renderingMode = .off
        XCTAssertEqual(book.renderingMode, .off)
        XCTAssertEqual(book.renderingModeRaw, "off")
    }

    // MARK: - bookmarks

    /// Добавление закладок и проверка сохранения через bookmarksData
    func testBookmarks_encodeAndDecode() {
        let book = Book(title: "Тест", fileName: "test.pdf")

        // Изначально пусто
        XCTAssertTrue(book.bookmarks.isEmpty)

        // Добавляем закладки
        book.bookmarks = [1, 5, 10, 25]
        XCTAssertEqual(book.bookmarks.count, 4)
        XCTAssertTrue(book.bookmarks.contains(5))
        XCTAssertTrue(book.bookmarks.contains(25))

        // Проверяем что данные записались в bookmarksData
        XCTAssertNotNil(book.bookmarksData)

        // Декодируем данные напрямую для проверки
        if let data = book.bookmarksData,
           let decoded = try? JSONDecoder().decode(Set<Int>.self, from: data) {
            XCTAssertEqual(decoded, [1, 5, 10, 25])
        } else {
            XCTFail("Не удалось декодировать bookmarksData")
        }
    }

    /// Пустой набор закладок — возвращается пустой массив
    func testBookmarks_emptySetReturnsEmpty() {
        let book = Book(title: "Тест", fileName: "test.pdf")
        book.bookmarksData = nil
        XCTAssertEqual(book.bookmarks, [])
    }

    // MARK: - documentsDirectory

    /// documentsDirectory возвращает не-nil URL
    func testDocumentsDirectory_returnsNonNilURL() {
        let url = Book.documentsDirectory
        XCTAssertNotNil(url)
        XCTAssertTrue(url.path.contains("Documents") || url.path.count > 0)
    }
}
