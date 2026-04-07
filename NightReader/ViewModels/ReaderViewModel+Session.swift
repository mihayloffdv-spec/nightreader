import Foundation
import UIKit

// MARK: - Reading Session Tracking & Recap

extension ReaderViewModel {

    func startReadingSession() {
        sessionStartTime = Date()
        sessionBackgroundTime = 0
        backgroundEnteredAt = nil

        // Pause tracking when app goes to background
        sessionBackgroundObserver = NotificationCenter.default.addObserver(
            forName: .appWillBackground, object: nil, queue: .main
        ) { [weak self] _ in
            self?.backgroundEnteredAt = Date()
        }

        // Resume tracking when app returns to foreground
        sessionForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let entered = self.backgroundEnteredAt else { return }
            self.sessionBackgroundTime += Date().timeIntervalSince(entered)
            self.backgroundEnteredAt = nil
        }
    }

    func stopReadingSession() {
        // Clean up observers
        if let obs = sessionBackgroundObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = sessionForegroundObserver { NotificationCenter.default.removeObserver(obs) }
        sessionBackgroundObserver = nil
        sessionForegroundObserver = nil

        guard let start = sessionStartTime else { return }

        // If currently in background, count time up to background entry
        if let entered = backgroundEnteredAt {
            sessionBackgroundTime += Date().timeIntervalSince(entered)
            backgroundEnteredAt = nil
        }

        let totalElapsed = Date().timeIntervalSince(start)
        let activeTime = max(0, totalElapsed - sessionBackgroundTime)

        // Only count sessions longer than 5 seconds (ignore accidental opens)
        if activeTime > 5 {
            book.totalReadingTime += activeTime
        }
        // Session recap: show if active reading > 30 seconds
        if activeTime > 30 {
            sessionDuration = activeTime
            sessionHighlightCount = annotationStore?.highlightsCreatedAfter(start).count ?? 0
            showSessionRecap = true
        }
        sessionStartTime = nil
        sessionBackgroundTime = 0
    }
}
