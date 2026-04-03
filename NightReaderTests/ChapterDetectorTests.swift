import XCTest
@testable import NightReader

// MARK: - Тесты для ChapterDetector

final class ChapterDetectorTests: XCTestCase {

    // MARK: - Тестовые данные

    /// Создаём массив глав для тестов
    private var testChapters: [Chapter] {
        [
            Chapter(id: 0, title: "Введение", pageIndex: 0, level: 0, source: .pdfOutline),
            Chapter(id: 1, title: "Глава 1", pageIndex: 5, level: 0, source: .pdfOutline),
            Chapter(id: 2, title: "Глава 2", pageIndex: 15, level: 0, source: .pdfOutline),
            Chapter(id: 3, title: "Глава 3", pageIndex: 30, level: 0, source: .pdfOutline),
        ]
    }

    // MARK: - currentChapter

    /// Пустой массив глав — возвращает nil
    func testCurrentChapter_emptyChapters() {
        let result = ChapterDetector.currentChapter(forPage: 5, in: [])
        XCTAssertNil(result)
    }

    /// Страница в пределах первой главы
    func testCurrentChapter_firstChapter() {
        let result = ChapterDetector.currentChapter(forPage: 3, in: testChapters)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "Введение")
    }

    /// Страница на границе — ровно начало главы
    func testCurrentChapter_exactBoundary() {
        let result = ChapterDetector.currentChapter(forPage: 15, in: testChapters)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "Глава 2")
    }

    /// Страница в середине главы
    func testCurrentChapter_middleOfChapter() {
        let result = ChapterDetector.currentChapter(forPage: 20, in: testChapters)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "Глава 2")
    }

    /// Последняя глава — страница после начала последней главы
    func testCurrentChapter_lastChapter() {
        let result = ChapterDetector.currentChapter(forPage: 35, in: testChapters)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "Глава 3")
    }

    // MARK: - chapterProgress

    /// Начало главы — прогресс 0
    func testChapterProgress_startOfChapter() {
        let progress = ChapterDetector.chapterProgress(forPage: 5, in: testChapters, totalPages: 50)
        XCTAssertEqual(progress, 0.0, accuracy: 0.001)
    }

    /// Середина главы — прогресс 0.5
    func testChapterProgress_middleOfChapter() {
        // Глава 2: страницы 15-29 (длина 15), середина = страница 22 или 23
        // pageIndex 15, next pageIndex 30, chapterLength = 15
        // progress = (22 - 15) / 15 ≈ 0.467
        // Для ровно 0.5: страница 22.5 — невозможно, берём ближайшую
        // Используем Глава 1: страницы 5-14, длина 10, середина = страница 10
        let progress = ChapterDetector.chapterProgress(forPage: 10, in: testChapters, totalPages: 50)
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
    }

    /// Последняя глава — прогресс считается до totalPages
    func testChapterProgress_lastChapter() {
        // Глава 3: pageIndex 30, totalPages 50, chapterLength = 20
        // Страница 40: progress = (40 - 30) / 20 = 0.5
        let progress = ChapterDetector.chapterProgress(forPage: 40, in: testChapters, totalPages: 50)
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
    }

    /// Пустой массив глав — прогресс 0
    func testChapterProgress_emptyChapters() {
        let progress = ChapterDetector.chapterProgress(forPage: 10, in: [], totalPages: 50)
        XCTAssertEqual(progress, 0.0, accuracy: 0.001)
    }

    /// Граница между главами — ровно на начале следующей главы
    func testChapterProgress_atChapterBoundary() {
        // Страница 15 — начало Главы 2, прогресс = 0
        let progress = ChapterDetector.chapterProgress(forPage: 15, in: testChapters, totalPages: 50)
        XCTAssertEqual(progress, 0.0, accuracy: 0.001)
    }
}
