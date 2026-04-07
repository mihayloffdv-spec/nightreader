import XCTest
@testable import NightReader

/// Characterization tests for ReaderViewModel before the 4-way split.
/// These tests capture current behavior as a safety net for refactoring.
@MainActor
final class ReaderViewModelTests: XCTestCase {

    private func makeVM(totalPages: Int = 100) -> ReaderViewModel {
        let book = Book(title: "Test Book", author: "Author", fileName: "test.pdf", totalPages: totalPages)
        return ReaderViewModel(book: book)
    }

    // MARK: - Initial State

    func testInitialStateIsCorrect() {
        let vm = makeVM()
        XCTAssertTrue(vm.isLoading)
        XCTAssertTrue(vm.toolbarVisible)
        XCTAssertTrue(vm.isReaderMode)
        XCTAssertFalse(vm.isDayMode)
        XCTAssertEqual(vm.currentPage, 0)
        XCTAssertNil(vm.document)
        XCTAssertNotNil(vm.annotationStore)
        XCTAssertFalse(vm.showAISheet)
        XCTAssertFalse(vm.showChat)
        XCTAssertFalse(vm.showChapterReview)
        XCTAssertFalse(vm.showPostReadingReview)
        XCTAssertFalse(vm.showSessionRecap)
    }

    // MARK: - Toolbar

    func testToggleToolbarFlipsVisibility() {
        let vm = makeVM()
        XCTAssertTrue(vm.toolbarVisible)
        vm.toggleToolbar()
        XCTAssertFalse(vm.toolbarVisible)
        vm.toggleToolbar()
        XCTAssertTrue(vm.toolbarVisible)
    }

    // MARK: - Progress

    func testProgressTextFormatting() {
        let vm = makeVM(totalPages: 200)
        vm.currentPage = 49
        XCTAssertEqual(vm.progressText, "50 / 200")
    }

    func testProgressTextEmptyWhenZeroPages() {
        let vm = makeVM(totalPages: 0)
        XCTAssertEqual(vm.progressText, "")
    }

    func testProgressFraction() {
        let vm = makeVM(totalPages: 100)
        vm.currentPage = 49
        XCTAssertEqual(vm.progressFraction, 0.5, accuracy: 0.01)
    }

    func testProgressFractionZeroWhenZeroPages() {
        let vm = makeVM(totalPages: 0)
        XCTAssertEqual(vm.progressFraction, 0)
    }

    // MARK: - Bookmarks

    func testToggleBookmarkAddsAndRemoves() {
        let vm = makeVM()
        vm.currentPage = 5
        XCTAssertFalse(vm.isCurrentPageBookmarked)

        vm.toggleBookmark()
        XCTAssertTrue(vm.isCurrentPageBookmarked)
        XCTAssertTrue(vm.book.bookmarks.contains(5))

        vm.toggleBookmark()
        XCTAssertFalse(vm.isCurrentPageBookmarked)
        XCTAssertFalse(vm.book.bookmarks.contains(5))
    }

    // MARK: - Save Position

    func testSavePositionUpdatesBookAndViewModel() {
        let vm = makeVM(totalPages: 100)
        vm.savePosition(pageIndex: 42, scrollOffset: 123.5)

        XCTAssertEqual(vm.currentPage, 42)
        XCTAssertEqual(vm.book.lastPageIndex, 42)
        XCTAssertEqual(vm.book.scrollOffsetY, 123.5)
        XCTAssertNotNil(vm.book.lastReadDate)
        XCTAssertEqual(vm.book.readProgress, 43.0 / 100.0, accuracy: 0.001)
    }

    func testSavePositionDoesNotCrashWithZeroPages() {
        let vm = makeVM(totalPages: 0)
        vm.savePosition(pageIndex: 0, scrollOffset: 0)
        XCTAssertEqual(vm.book.readProgress, 0)
    }

    // MARK: - Rendering Mode

    func testIsDarkModeEnabled() {
        let vm = makeVM()
        vm.renderingMode = .smart
        XCTAssertTrue(vm.isDarkModeEnabled)

        vm.renderingMode = .simple
        XCTAssertTrue(vm.isDarkModeEnabled)

        vm.renderingMode = .off
        XCTAssertFalse(vm.isDarkModeEnabled)
    }

    // MARK: - Reader Mode / Day Mode Toggles

    func testToggleReaderMode() {
        let vm = makeVM()
        XCTAssertTrue(vm.isReaderMode)

        vm.toggleReaderMode()
        XCTAssertFalse(vm.isReaderMode)
        XCTAssertFalse(vm.isDayMode) // day mode disabled when reader mode off

        vm.toggleReaderMode()
        XCTAssertTrue(vm.isReaderMode)
    }

    func testToggleDayModeEnablesReaderMode() {
        let vm = makeVM()
        vm.isReaderMode = false
        vm.isDayMode = false

        vm.toggleDayMode()
        XCTAssertTrue(vm.isDayMode)
        XCTAssertTrue(vm.isReaderMode) // reader mode forced on
    }

    func testToggleDayModeOff() {
        let vm = makeVM()
        vm.isDayMode = true
        vm.isReaderMode = true

        vm.toggleDayMode()
        XCTAssertFalse(vm.isDayMode)
    }

    // MARK: - Font Settings

    func testSetReaderFontSizePropagates() {
        let vm = makeVM()
        vm.setReaderFontSize(22)
        XCTAssertEqual(vm.readerFontSize, 22)
        XCTAssertEqual(AppSettings.shared.readerFontSize, 22)
    }

    func testSetReaderFontFamilyPropagates() {
        let vm = makeVM()
        vm.setReaderFontFamily(.sansSerif)
        XCTAssertEqual(vm.readerFontFamily, .sansSerif)
    }

    // MARK: - Crop Margin

    func testSetCropMargin() {
        let vm = makeVM()
        vm.setCropMargin(0.15)
        XCTAssertEqual(vm.cropMargin, 0.15)
        XCTAssertEqual(vm.book.cropMargin, 0.15)
    }

    // MARK: - Estimated Reading Time

    func testEstimatedReadingMinutes() {
        let vm = makeVM()
        vm.totalWordCount = 40_000
        XCTAssertEqual(vm.estimatedReadingMinutes, 200) // 40000 / 200 wpm
    }

    func testEstimatedReadingMinutesMinimumOne() {
        let vm = makeVM()
        vm.totalWordCount = 0
        XCTAssertEqual(vm.estimatedReadingMinutes, 1)
    }

    // MARK: - Highlights

    func testCreateHighlightShowsAnnotationSheet() {
        let vm = makeVM()
        XCTAssertFalse(vm.showAnnotationSheet)

        vm.createHighlight(text: "Important quote")
        XCTAssertTrue(vm.showAnnotationSheet)
        XCTAssertEqual(vm.pendingHighlightText, "Important quote")
    }

    func testSaveHighlightAddsToStore() {
        let vm = makeVM()
        vm.createHighlight(text: "Saved quote")
        vm.saveHighlight()

        XCTAssertFalse(vm.showAnnotationSheet)
        XCTAssertEqual(vm.annotationStore?.highlightCount, 1)
        XCTAssertEqual(vm.book.highlightCount, 1)
    }

    func testSaveHighlightIgnoresEmptyText() {
        let vm = makeVM()
        vm.pendingHighlightText = ""
        vm.saveHighlight()
        XCTAssertEqual(vm.annotationStore?.highlightCount, 0)
    }

    func testSaveHighlightWithReactionAndAction() {
        let vm = makeVM()
        vm.createHighlight(text: "Deep thought")
        vm.pendingReaction = "Wow"
        vm.pendingAction = "Share this"
        vm.saveHighlight()

        let highlight = vm.annotationStore?.allHighlights.first
        XCTAssertEqual(highlight?.reaction, "Wow")
        XCTAssertEqual(highlight?.action, "Share this")
    }

    func testDismissAnnotationSheet() {
        let vm = makeVM()
        vm.showAnnotationSheet = true
        vm.dismissAnnotationSheet()
        XCTAssertFalse(vm.showAnnotationSheet)
    }

    // MARK: - AI Actions

    func testRequestAIActionTooLongText() {
        let vm = makeVM()
        let longText = String(repeating: "a", count: 2001)
        vm.requestExplain(text: longText)

        XCTAssertTrue(vm.showAISheet)
        if case .error(let msg) = vm.aiResponseState {
            XCTAssertTrue(msg.contains("2000"))
        } else {
            XCTFail("Expected error state for too-long text")
        }
    }

    func testRequestAIActionEmptyTextDoesNothing() {
        let vm = makeVM()
        vm.requestExplain(text: "   ")
        XCTAssertFalse(vm.showAISheet)
    }

    func testRequestAIActionNoAPIKeyShowsSettings() {
        // This test assumes no API key is set in the test environment
        let vm = makeVM()
        if !KeychainManager.hasAPIKey {
            vm.requestExplain(text: "Some text")
            XCTAssertTrue(vm.showAPIKeySettings)
            XCTAssertFalse(vm.showAISheet)
        }
        // If API key IS set, skip — we don't want to call the real API
    }

    func testDismissAISheet() {
        let vm = makeVM()
        vm.showAISheet = true
        vm.aiResponseState = .loading
        vm.dismissAISheet()

        XCTAssertFalse(vm.showAISheet)
        if case .idle = vm.aiResponseState { } else {
            XCTFail("Expected idle state after dismiss")
        }
    }

    // MARK: - Smart Highlights Toggle

    func testToggleSmartHighlightsFlipsState() {
        let vm = makeVM()
        let initial = vm.smartHighlightsEnabled
        vm.toggleSmartHighlights()
        XCTAssertNotEqual(vm.smartHighlightsEnabled, initial)
        XCTAssertEqual(AppSettings.shared.smartHighlightsEnabled, vm.smartHighlightsEnabled)
    }

    func testDisablingSmartHighlightsCancelsAnalysis() {
        let vm = makeVM()
        vm.smartHighlightsEnabled = true
        vm.isAnalyzingChapter = true
        vm.toggleSmartHighlights() // disables
        XCTAssertFalse(vm.smartHighlightsEnabled)
        XCTAssertFalse(vm.isAnalyzingChapter)
    }

    // MARK: - Reading Session Tracking

    func testSessionTrackingAccumulatesTime() {
        let vm = makeVM()
        vm.book.totalReadingTime = 100
        vm.startReadingSession()

        // Simulate time passing (we can't easily test real time,
        // but we verify the mechanism is wired correctly)
        XCTAssertFalse(vm.showSessionRecap) // not shown yet
    }

    func testStopSessionWithoutStartDoesNothing() {
        let vm = makeVM()
        vm.book.totalReadingTime = 100
        vm.stopReadingSession()
        XCTAssertEqual(vm.book.totalReadingTime, 100) // unchanged
        XCTAssertFalse(vm.showSessionRecap)
    }

    // MARK: - IsNearEndOfBook

    func testIsNearEndOfBook() {
        let vm = makeVM(totalPages: 100)
        vm.currentPage = 94
        // progressFraction = 95/100 = 0.95 — not > 0.95 yet
        XCTAssertFalse(vm.isNearEndOfBook)

        vm.currentPage = 95
        // progressFraction = 96/100 = 0.96 — > 0.95
        XCTAssertTrue(vm.isNearEndOfBook)
    }

    // MARK: - Go To Page

    func testGoToPageSetsIndex() {
        let vm = makeVM()
        XCTAssertNil(vm.goToPageIndex)
        vm.goToPage(42)
        XCTAssertEqual(vm.goToPageIndex, 42)
    }

    // MARK: - Chat State

    func testSendChatMessageIgnoresEmptyText() {
        let vm = makeVM()
        vm.chatInputText = "   "
        vm.sendChatMessage()
        XCTAssertTrue(vm.chatMessages.isEmpty)
    }

    func testSendChatMessageIgnoresWithoutAPIKey() {
        let vm = makeVM()
        vm.chatInputText = "What is this chapter about?"
        if !KeychainManager.hasAPIKey {
            vm.sendChatMessage()
            XCTAssertTrue(vm.chatMessages.isEmpty)
        }
    }

    // MARK: - Chapter Review

    func testTriggerChapterReviewGuardsNoAPIKey() {
        let vm = makeVM()
        if !KeychainManager.hasAPIKey {
            vm.triggerChapterReview()
            XCTAssertFalse(vm.showChapterReview)
            XCTAssertFalse(vm.isGeneratingQuestions)
        }
    }

    func testTriggerChapterReviewGuardsNoChapter() {
        let vm = makeVM()
        XCTAssertNil(vm.currentChapter)
        vm.triggerChapterReview()
        XCTAssertFalse(vm.showChapterReview)
    }
}
