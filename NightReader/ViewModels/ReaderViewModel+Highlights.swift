import Foundation

// MARK: - Highlights & Annotations

extension ReaderViewModel {

    /// Create highlight from text selection.
    /// In Reader Mode, bounds are empty (reflowed text has no stable PDF coords).
    /// In PDF Mode, pass PDFSelection bounds via the overload.
    func createHighlight(text: String) {
        pendingHighlightText = text
        pendingHighlightBounds = []
        pendingReaction = ""
        pendingAction = ""
        showAnnotationSheet = true
    }

    /// Create highlight with PDF bounds (for PDF Mode).
    func createHighlight(text: String, bounds: [[CGFloat]]) {
        pendingHighlightText = text
        pendingHighlightBounds = bounds
        pendingReaction = ""
        pendingAction = ""
        showAnnotationSheet = true
    }

    func saveHighlight() {
        guard !pendingHighlightText.isEmpty else { return }
        let highlight = annotationStore?.addHighlight(
            text: pendingHighlightText,
            page: currentPage,
            bounds: pendingHighlightBounds,
            chapter: currentChapter?.title
        )
        if !pendingReaction.isEmpty || !pendingAction.isEmpty, let h = highlight {
            annotationStore?.updateHighlight(
                id: h.id,
                reaction: pendingReaction.isEmpty ? nil : pendingReaction,
                action: pendingAction.isEmpty ? nil : pendingAction
            )
        }
        book.highlightCount = annotationStore?.highlightCount ?? 0
        book.actionCount = annotationStore?.actionCount ?? 0
        showAnnotationSheet = false
    }

    func dismissAnnotationSheet() {
        showAnnotationSheet = false
    }

    func exportAnnotations() {
        scheduleHideToolbar()
        guard let document else { return }
        if let url = ExportService.exportAnnotationsToFile(from: document, title: book.title) {
            exportURL = url
            showExportShare = true
        } else {
            loadError = "Failed to export annotations."
        }
    }
}
