import XCTest
@testable import NightReader

final class AnnotationStoreTests: XCTestCase {

    private var testBookId: String!
    private var testDirectory: URL!

    override func setUp() {
        super.setUp()
        testBookId = "test-\(UUID().uuidString)"
    }

    override func tearDown() {
        // Clean up test annotation files
        AnnotationStore.deleteAnnotations(forBookId: testBookId)
        super.tearDown()
    }

    // MARK: - CRUD: Highlights

    func testAddHighlightReturnsHighlightWithCorrectFields() {
        let store = AnnotationStore(bookId: testBookId, title: "Test Book")

        let highlight = store.addHighlight(
            text: "Important sentence",
            page: 3,
            bounds: [[10, 20, 200, 15]],
            chapter: "Chapter 1",
            color: "green"
        )

        XCTAssertEqual(highlight.text, "Important sentence")
        XCTAssertEqual(highlight.page, 3)
        XCTAssertEqual(highlight.bounds, [[10, 20, 200, 15]])
        XCTAssertEqual(highlight.chapter, "Chapter 1")
        XCTAssertEqual(highlight.color, "green")
        XCTAssertEqual(store.highlightCount, 1)
    }

    func testUpdateHighlightSetsReactionAndAction() {
        let store = AnnotationStore(bookId: testBookId, title: "Test Book")
        let highlight = store.addHighlight(text: "Quote", page: 0, bounds: [])

        store.updateHighlight(id: highlight.id, reaction: "Wow", action: "Share with team")

        let updated = store.allHighlights.first!
        XCTAssertEqual(updated.reaction, "Wow")
        XCTAssertEqual(updated.action, "Share with team")
        XCTAssertGreaterThanOrEqual(updated.updatedAt, updated.createdAt)
    }

    func testDeleteHighlightRemovesIt() {
        let store = AnnotationStore(bookId: testBookId, title: "Test Book")
        let h1 = store.addHighlight(text: "First", page: 0, bounds: [])
        let _ = store.addHighlight(text: "Second", page: 1, bounds: [])
        XCTAssertEqual(store.highlightCount, 2)

        store.deleteHighlight(id: h1.id)

        XCTAssertEqual(store.highlightCount, 1)
        XCTAssertEqual(store.allHighlights.first?.text, "Second")
    }

    func testHighlightsForPageFiltersCorrectly() {
        let store = AnnotationStore(bookId: testBookId, title: "Test Book")
        let _ = store.addHighlight(text: "Page 0", page: 0, bounds: [])
        let _ = store.addHighlight(text: "Page 2a", page: 2, bounds: [])
        let _ = store.addHighlight(text: "Page 2b", page: 2, bounds: [])

        XCTAssertEqual(store.highlightsForPage(0).count, 1)
        XCTAssertEqual(store.highlightsForPage(2).count, 2)
        XCTAssertEqual(store.highlightsForPage(99).count, 0)
    }

    func testSetCommittedUpdatesFlag() {
        let store = AnnotationStore(bookId: testBookId, title: "Test Book")
        let h = store.addHighlight(text: "Action item", page: 0, bounds: [])
        XCTAssertFalse(h.committed)

        store.setCommitted(id: h.id, committed: true)

        XCTAssertTrue(store.allHighlights.first!.committed)
    }

    // MARK: - CRUD: Smart Highlights

    func testAddSmartHighlightsIncrementsAnalysisCount() {
        let store = AnnotationStore(bookId: testBookId, title: "Test Book")
        XCTAssertEqual(store.monthlyAnalysisCount, 0)

        let smarts = [
            SmartHighlight(bookId: testBookId, chapterIndex: 0, text: "Thesis", type: .thesis, rationale: "Core", page: 1),
            SmartHighlight(bookId: testBookId, chapterIndex: 0, text: "Insight", type: .insight, rationale: "Surprising", page: 2)
        ]
        store.addSmartHighlights(smarts)

        XCTAssertEqual(store.monthlyAnalysisCount, 1)
        XCTAssertEqual(store.smartHighlightsForChapter(0).count, 2)
    }

    func testDismissSmartHighlightHidesFromQuery() {
        let store = AnnotationStore(bookId: testBookId, title: "Test Book")
        let smart = SmartHighlight(bookId: testBookId, chapterIndex: 1, text: "Dismiss me", type: .actionable, rationale: "R", page: 5)
        store.addSmartHighlights([smart])
        XCTAssertEqual(store.smartHighlightsForChapter(1).count, 1)

        store.dismissSmartHighlight(id: smart.id)

        XCTAssertEqual(store.smartHighlightsForChapter(1).count, 0)
        // Still in storage, just dismissed
        XCTAssertTrue(store.annotations.smartHighlights.first!.dismissed)
    }

    func testPromoteToHighlightCreatesBookHighlight() {
        let store = AnnotationStore(bookId: testBookId, title: "Test Book")
        let smart = SmartHighlight(bookId: testBookId, chapterIndex: 0, chapterTitle: "Ch1", text: "Promote this", type: .thesis, rationale: "Central argument", page: 3)
        store.addSmartHighlights([smart])

        let promoted = store.promoteToHighlight(id: smart.id)

        XCTAssertNotNil(promoted)
        XCTAssertEqual(promoted?.text, "Promote this")
        XCTAssertEqual(promoted?.page, 3)
        XCTAssertEqual(store.highlightCount, 1)
        XCTAssertTrue(store.annotations.smartHighlights.first!.savedAsHighlight)
    }

    func testIsChapterAnalyzed() {
        let store = AnnotationStore(bookId: testBookId, title: "Test Book")
        XCTAssertFalse(store.isChapterAnalyzed(0))

        store.addSmartHighlights([
            SmartHighlight(bookId: testBookId, chapterIndex: 0, text: "T", type: .thesis, rationale: "R", page: 0)
        ])

        XCTAssertTrue(store.isChapterAnalyzed(0))
        XCTAssertFalse(store.isChapterAnalyzed(1))
    }

    // MARK: - Chapter Reviews

    func testChapterReviewCRUD() {
        let store = AnnotationStore(bookId: testBookId, title: "Test Book")
        let review = ChapterReview(chapterIndex: 2, chapterTitle: "Ch2", questions: ["Q1", "Q2"])

        store.addChapterReview(review)
        XCTAssertNotNil(store.chapterReview(forChapter: 2))
        XCTAssertNil(store.chapterReview(forChapter: 99))

        store.updateChapterReview(id: review.id, answerIndex: 0, answer: "My answer")
        XCTAssertEqual(store.chapterReview(forChapter: 2)?.answers[0], "My answer")

        store.addAIFeedback(reviewId: review.id, feedback: ["Good", "Great"], summary: "Nice work")
        let updated = store.chapterReview(forChapter: 2)!
        XCTAssertEqual(updated.aiFeedback, ["Good", "Great"])
        XCTAssertEqual(updated.summary, "Nice work")
    }

    // MARK: - Post-Reading Review

    func testSetPostReading() {
        let store = AnnotationStore(bookId: testBookId, title: "Test Book")
        XCTAssertNil(store.annotations.postReading)

        store.setPostReading(coreIdea: "The core idea", whyRead: nil, mainShift: "Changed my view")

        XCTAssertEqual(store.annotations.postReading?.coreIdea, "The core idea")
        XCTAssertNil(store.annotations.postReading?.whyRead)
        XCTAssertEqual(store.annotations.postReading?.mainShift, "Changed my view")
        XCTAssertNotNil(store.annotations.postReading?.completedAt)
    }

    // MARK: - Persistence (round-trip)

    func testSaveAndReload() {
        // Create store, add data, force save
        let store = AnnotationStore(bookId: testBookId, title: "Persistence Test", author: "Author")
        let _ = store.addHighlight(text: "Persisted highlight", page: 7, bounds: [[1, 2, 3, 4]], chapter: "Ch3", color: "blue")
        store.addSmartHighlights([
            SmartHighlight(bookId: testBookId, chapterIndex: 0, text: "AI sentence", type: .insight, rationale: "R", page: 1)
        ])
        store.saveNow()

        // Reload from disk
        let reloaded = AnnotationStore(bookId: testBookId, title: "Persistence Test")

        XCTAssertEqual(reloaded.highlightCount, 1)
        XCTAssertEqual(reloaded.allHighlights.first?.text, "Persisted highlight")
        XCTAssertEqual(reloaded.allHighlights.first?.bounds, [[1, 2, 3, 4]])
        XCTAssertEqual(reloaded.smartHighlightsForChapter(0).count, 1)
        XCTAssertEqual(reloaded.annotations.schemaVersion, BookAnnotations.currentSchemaVersion)
    }

    func testCorruptedFileBacksUpAndStartsFresh() {
        // Write garbage to the annotation file
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("annotations")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(testBookId!).json")
        try? "NOT VALID JSON {{{".data(using: .utf8)?.write(to: fileURL)

        // Loading should not crash — should backup and start fresh
        let store = AnnotationStore(bookId: testBookId, title: "Recovered")

        XCTAssertEqual(store.highlightCount, 0)
        XCTAssertEqual(store.annotations.title, "Recovered")
        // Backup file should exist
        let backupURL = fileURL.appendingPathExtension("backup")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))

        // Clean up backup
        try? FileManager.default.removeItem(at: backupURL)
    }

    // MARK: - Schema Migration

    func testSchemaVersionDefaultsTo1ForOldFiles() throws {
        // Old JSON without schemaVersion field
        let oldJSON = """
        {
            "id": "\(testBookId!)",
            "title": "Old Book",
            "highlights": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(BookAnnotations.self, from: oldJSON)
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func testSchemaVersionMigratesOnLoad() {
        // Write a v1 file (no schemaVersion field)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("annotations")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(testBookId!).json")

        let v1JSON = """
        {
            "id": "\(testBookId!)",
            "title": "V1 Book",
            "highlights": [{"id":"11111111-1111-1111-1111-111111111111","bookId":"\(testBookId!)","text":"Old","page":0,"bounds":[],"color":"yellow","committed":false,"createdAt":0,"updatedAt":0}]
        }
        """.data(using: .utf8)!
        try? v1JSON.write(to: fileURL)

        // Load — should migrate to current version
        let store = AnnotationStore(bookId: testBookId, title: "V1 Book")

        XCTAssertEqual(store.annotations.schemaVersion, BookAnnotations.currentSchemaVersion)
        XCTAssertEqual(store.highlightCount, 1)
        XCTAssertEqual(store.allHighlights.first?.text, "Old")
    }

    // MARK: - Session Tracking Queries

    func testHighlightsCreatedAfterDate() {
        let store = AnnotationStore(bookId: testBookId, title: "Test Book")
        let beforeDate = Date()

        // Small delay to ensure createdAt > beforeDate
        let _ = store.addHighlight(text: "After", page: 0, bounds: [])

        XCTAssertEqual(store.highlightsCreatedAfter(beforeDate).count, 1)
        XCTAssertEqual(store.highlightsCreatedAfter(Date()).count, 0)
    }

    func testActionAndReactionCounts() {
        let store = AnnotationStore(bookId: testBookId, title: "Test Book")
        let h1 = store.addHighlight(text: "With action", page: 0, bounds: [])
        let h2 = store.addHighlight(text: "With reaction", page: 1, bounds: [])
        let _ = store.addHighlight(text: "Plain", page: 2, bounds: [])

        store.updateHighlight(id: h1.id, reaction: nil, action: "Do this")
        store.updateHighlight(id: h2.id, reaction: "Felt this", action: nil)

        XCTAssertEqual(store.actionCount, 1)
        XCTAssertEqual(store.highlightsWithActions.count, 1)
        XCTAssertEqual(store.highlightsWithReactions.count, 1)
    }
}
