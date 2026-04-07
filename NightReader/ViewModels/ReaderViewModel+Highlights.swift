import Foundation

// MARK: - Highlights & Annotations

extension ReaderViewModel {

    func createHighlight(text: String) {
        pendingHighlightText = text
        pendingReaction = ""
        pendingAction = ""
        showAnnotationSheet = true
    }

    func saveHighlight() {
        guard !pendingHighlightText.isEmpty else { return }
        let highlight = annotationStore?.addHighlight(
            text: pendingHighlightText,
            page: currentPage,
            bounds: [],
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
