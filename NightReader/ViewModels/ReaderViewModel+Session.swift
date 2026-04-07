import Foundation

// MARK: - Reading Session Tracking & Recap

extension ReaderViewModel {

    func startReadingSession() {
        sessionStartTime = Date()
    }

    func stopReadingSession() {
        guard let start = sessionStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        // Only count sessions longer than 5 seconds (ignore accidental opens)
        if elapsed > 5 {
            book.totalReadingTime += elapsed
        }
        // Session recap: show if session > 30 seconds
        if elapsed > 30 {
            sessionDuration = elapsed
            sessionHighlightCount = annotationStore?.highlightsCreatedAfter(start).count ?? 0
            showSessionRecap = true
        }
        sessionStartTime = nil
    }
}
