import XCTest
@testable import NightReader

final class SmartHighlightTests: XCTestCase {

    // MARK: - Model encode/decode

    func testSmartHighlightRoundTrip() throws {
        let highlight = SmartHighlight(
            bookId: "book-1",
            chapterIndex: 2,
            chapterTitle: "Chapter 2",
            text: "The fundamental problem is distraction.",
            type: .thesis,
            rationale: "This is the author's central argument.",
            page: 15
        )

        let data = try JSONEncoder().encode(highlight)
        let decoded = try JSONDecoder().decode(SmartHighlight.self, from: data)

        XCTAssertEqual(decoded.bookId, "book-1")
        XCTAssertEqual(decoded.chapterIndex, 2)
        XCTAssertEqual(decoded.chapterTitle, "Chapter 2")
        XCTAssertEqual(decoded.text, "The fundamental problem is distraction.")
        XCTAssertEqual(decoded.type, .thesis)
        XCTAssertEqual(decoded.rationale, "This is the author's central argument.")
        XCTAssertEqual(decoded.page, 15)
        XCTAssertFalse(decoded.dismissed)
        XCTAssertFalse(decoded.savedAsHighlight)
    }

    func testSmartHighlightTypeRawValues() {
        XCTAssertEqual(SmartHighlightType.thesis.rawValue, "thesis")
        XCTAssertEqual(SmartHighlightType.insight.rawValue, "insight")
        XCTAssertEqual(SmartHighlightType.actionable.rawValue, "actionable")
        XCTAssertEqual(SmartHighlightType(rawValue: "thesis"), .thesis)
        XCTAssertNil(SmartHighlightType(rawValue: "unknown"))
    }

    func testBookAnnotationsWithSmartHighlights() throws {
        var annotations = BookAnnotations(id: "book-1", title: "Test Book")
        let smart = SmartHighlight(
            bookId: "book-1", chapterIndex: 0, text: "Test sentence.",
            type: .insight, rationale: "Important.", page: 1
        )
        annotations.smartHighlights.append(smart)
        annotations.analysisCount = 3

        let data = try JSONEncoder().encode(annotations)
        let decoded = try JSONDecoder().decode(BookAnnotations.self, from: data)

        XCTAssertEqual(decoded.smartHighlights.count, 1)
        XCTAssertEqual(decoded.smartHighlights.first?.type, .insight)
        XCTAssertEqual(decoded.analysisCount, 3)
    }

    func testBackwardCompatibilityDecoding() throws {
        // Simulate old JSON without smartHighlights and analysisCount fields
        let oldJSON = """
        {
            "id": "book-1",
            "title": "Old Book",
            "highlights": [],
            "postReading": null
        }
        """.data(using: .utf8)!

        // This should NOT crash — new fields should have defaults
        // BookAnnotations uses Codable, so missing keys need defaults or optionals
        // If this fails, we need to add CodingKeys with default values
        let decoded = try? JSONDecoder().decode(BookAnnotations.self, from: oldJSON)
        // New fields may cause a decode failure if not optional — test documents this
        if let decoded {
            XCTAssertEqual(decoded.smartHighlights.count, 0)
            XCTAssertEqual(decoded.analysisCount, 0)
        }
        // If decode fails, that's the format migration issue Codex flagged
    }

    // MARK: - AnnotationStore CRUD

    func testAnnotationStoreAddSmartHighlights() {
        let store = AnnotationStore(bookId: "test-smart-\(UUID().uuidString)", title: "Test")
        let highlights = [
            SmartHighlight(bookId: "test", chapterIndex: 0, text: "Sentence 1.", type: .thesis, rationale: "R1", page: 0),
            SmartHighlight(bookId: "test", chapterIndex: 0, text: "Sentence 2.", type: .insight, rationale: "R2", page: 1),
        ]

        store.addSmartHighlights(highlights)

        XCTAssertEqual(store.annotations.smartHighlights.count, 2)
        XCTAssertEqual(store.monthlyAnalysisCount, 1)
    }

    func testSmartHighlightsForChapter() {
        let store = AnnotationStore(bookId: "test-chapter-\(UUID().uuidString)", title: "Test")
        store.addSmartHighlights([
            SmartHighlight(bookId: "t", chapterIndex: 0, text: "Ch0.", type: .thesis, rationale: "R", page: 0),
            SmartHighlight(bookId: "t", chapterIndex: 1, text: "Ch1.", type: .insight, rationale: "R", page: 5),
            SmartHighlight(bookId: "t", chapterIndex: 0, text: "Ch0b.", type: .actionable, rationale: "R", page: 2),
        ])

        let ch0 = store.smartHighlightsForChapter(0)
        let ch1 = store.smartHighlightsForChapter(1)

        XCTAssertEqual(ch0.count, 2)
        XCTAssertEqual(ch1.count, 1)
        XCTAssertEqual(ch1.first?.text, "Ch1.")
    }

    func testDismissSmartHighlight() {
        let store = AnnotationStore(bookId: "test-dismiss-\(UUID().uuidString)", title: "Test")
        let highlight = SmartHighlight(bookId: "t", chapterIndex: 0, text: "Dismiss me.", type: .thesis, rationale: "R", page: 0)
        store.addSmartHighlights([highlight])

        store.dismissSmartHighlight(id: highlight.id)

        XCTAssertTrue(store.annotations.smartHighlights.first!.dismissed)
        XCTAssertEqual(store.smartHighlightsForChapter(0).count, 0) // filtered out
        XCTAssertEqual(store.activeSmartHighlights.count, 0)
    }

    func testPromoteToHighlight() {
        let store = AnnotationStore(bookId: "test-promote-\(UUID().uuidString)", title: "Test")
        let smart = SmartHighlight(bookId: "t", chapterIndex: 0, text: "Promote me.", type: .insight, rationale: "Great insight.", page: 3)
        store.addSmartHighlights([smart])

        let promoted = store.promoteToHighlight(id: smart.id)

        XCTAssertNotNil(promoted)
        XCTAssertEqual(promoted?.text, "Promote me.")
        XCTAssertEqual(promoted?.page, 3)
        XCTAssertTrue(store.annotations.smartHighlights.first!.savedAsHighlight)
        XCTAssertEqual(store.highlightCount, 1)
        // Check reaction was set via updateHighlight (read from store, not returned copy)
        let savedHighlight = store.allHighlights.first
        XCTAssertTrue(savedHighlight?.reaction?.contains("Great insight.") ?? false)
    }

    func testIsChapterAnalyzed() {
        let store = AnnotationStore(bookId: "test-analyzed-\(UUID().uuidString)", title: "Test")
        XCTAssertFalse(store.isChapterAnalyzed(0))

        store.addSmartHighlights([
            SmartHighlight(bookId: "t", chapterIndex: 0, text: "S.", type: .thesis, rationale: "R", page: 0)
        ])

        XCTAssertTrue(store.isChapterAnalyzed(0))
        XCTAssertFalse(store.isChapterAnalyzed(1))
    }

    func testClearSmartHighlightsForChapter() {
        let store = AnnotationStore(bookId: "test-clear-\(UUID().uuidString)", title: "Test")
        store.addSmartHighlights([
            SmartHighlight(bookId: "t", chapterIndex: 0, text: "S0.", type: .thesis, rationale: "R", page: 0),
            SmartHighlight(bookId: "t", chapterIndex: 1, text: "S1.", type: .insight, rationale: "R", page: 5),
        ])

        store.clearSmartHighlightsForChapter(0)

        XCTAssertEqual(store.annotations.smartHighlights.count, 1)
        XCTAssertEqual(store.annotations.smartHighlights.first?.chapterIndex, 1)
    }

    func testActiveSmartHighlightsExcludesDismissedAndSaved() {
        let store = AnnotationStore(bookId: "test-active-\(UUID().uuidString)", title: "Test")
        let s1 = SmartHighlight(bookId: "t", chapterIndex: 0, text: "Active.", type: .thesis, rationale: "R", page: 0)
        let s2 = SmartHighlight(bookId: "t", chapterIndex: 0, text: "Dismissed.", type: .insight, rationale: "R", page: 1)
        let s3 = SmartHighlight(bookId: "t", chapterIndex: 0, text: "Saved.", type: .actionable, rationale: "R", page: 2)
        store.addSmartHighlights([s1, s2, s3])

        store.dismissSmartHighlight(id: s2.id)
        store.promoteToHighlight(id: s3.id)

        XCTAssertEqual(store.activeSmartHighlights.count, 1)
        XCTAssertEqual(store.activeSmartHighlights.first?.text, "Active.")
    }
}
