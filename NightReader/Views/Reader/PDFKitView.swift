import SwiftUI
import PDFKit

// MARK: - Custom PDFView with Highlight in context menu

class HighlightablePDFView: PDFView {
    var highlightColor: HighlightColor = .yellow
    var onHighlight: ((PDFSelection) -> Void)?
    var onTapEmpty: (() -> Void)?

    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)

        guard currentSelection != nil else { return }

        let highlightAction = UIAction(
            title: "Highlight",
            image: UIImage(systemName: "highlighter")
        ) { [weak self] _ in
            self?.performHighlight()
        }

        let noteAction = UIAction(
            title: "Highlight + Note",
            image: UIImage(systemName: "note.text")
        ) { [weak self] _ in
            self?.performHighlightWithNote()
        }

        let menu = UIMenu(title: "", options: .displayInline, children: [highlightAction, noteAction])
        builder.insertChild(menu, atStartOfMenu: .standardEdit)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(performHighlight) || action == #selector(performHighlightWithNote) {
            return currentSelection != nil
        }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc private func performHighlight() {
        guard let selection = currentSelection, let document else { return }
        _ = AnnotationService.addHighlight(to: selection, in: document, color: highlightColor)
        AnnotationService.saveAnnotations(in: document)
        let sel = selection
        clearSelection()
        onHighlight?(sel)
    }

    @objc private func performHighlightWithNote() {
        guard let selection = currentSelection, let document else { return }
        let annotations = AnnotationService.addHighlight(to: selection, in: document, color: highlightColor)
        AnnotationService.saveAnnotations(in: document)
        let sel = selection
        clearSelection()
        onHighlight?(sel)

        // Show note input via nearest view controller
        if let annotation = annotations.first,
           let vc = findViewController() {
            let alert = UIAlertController(title: "Add Note", message: nil, preferredStyle: .alert)
            alert.addTextField { $0.placeholder = "Your note..." }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
                let note = alert.textFields?.first?.text ?? ""
                if !note.isEmpty {
                    AnnotationService.updateNote(for: annotation, note: note)
                    if let doc = self?.document {
                        AnnotationService.saveAnnotations(in: doc)
                    }
                }
            })
            vc.present(alert, animated: true)
        }
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }
}

// MARK: - SwiftUI wrapper

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument?
    let renderingMode: RenderingMode
    let theme: Theme
    let initialPageIndex: Int
    let highlightColor: HighlightColor
    let goToPageIndex: Int?
    let goToSelection: PDFSelection?
    let onPageChange: (Int, Double) -> Void
    let onHighlight: (PDFSelection) -> Void
    let onTapEmpty: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChange: onPageChange)
    }

    func makeUIView(context: Context) -> HighlightablePDFView {
        let pdfView = HighlightablePDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(theme.bgColor)
        pdfView.document = document
        pdfView.highlightColor = highlightColor
        pdfView.onHighlight = onHighlight
        pdfView.onTapEmpty = onTapEmpty

        // Single tap on empty area — toggle toolbar
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.delegate = context.coordinator

        // Double-tap to toggle zoom
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2

        singleTap.require(toFail: doubleTap)
        pdfView.addGestureRecognizer(singleTap)
        pdfView.addGestureRecognizer(doubleTap)

        // Restore reading position
        if let doc = document, initialPageIndex > 0, initialPageIndex < doc.pageCount,
           let page = doc.page(at: initialPageIndex) {
            pdfView.go(to: page)
        }

        context.coordinator.pdfView = pdfView
        context.coordinator.startObserving()

        return pdfView
    }

    func updateUIView(_ pdfView: HighlightablePDFView, context: Context) {
        // Update document if changed (e.g. switching to/from Smart mode)
        if pdfView.document !== document {
            let currentPageIndex = context.coordinator.lastPageIndex
            pdfView.document = document
            if let doc = document, currentPageIndex < doc.pageCount,
               let page = doc.page(at: currentPageIndex) {
                pdfView.go(to: page)
            }
        }

        pdfView.highlightColor = highlightColor
        pdfView.onHighlight = onHighlight
        pdfView.onTapEmpty = onTapEmpty

        // Update background color from theme
        pdfView.backgroundColor = UIColor(theme.bgColor)

        // Update zoom limits (scaleFactorForSizeToFit is only valid after layout)
        let fitScale = pdfView.scaleFactorForSizeToFit
        if fitScale > 0 {
            pdfView.minScaleFactor = fitScale
            pdfView.maxScaleFactor = fitScale * 4
        }

        // Navigate to page if requested
        if let pageIndex = goToPageIndex,
           let doc = pdfView.document, pageIndex < doc.pageCount,
           let page = doc.page(at: pageIndex) {
            pdfView.go(to: page)
        }

        // Navigate to search selection and highlight it
        if let selection = goToSelection {
            pdfView.go(to: selection)
            pdfView.setCurrentSelection(selection, animate: true)
            // Auto-clear highlight after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                pdfView.clearSelection()
            }
        }

        // Simple mode uses compositing filter overlays
        if renderingMode == .simple {
            DarkModeRenderer.applyDarkMode(to: pdfView, theme: theme)
        } else {
            DarkModeRenderer.removeDarkMode(from: pdfView)
        }
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var pdfView: HighlightablePDFView?
        let onPageChange: (Int, Double) -> Void
        var lastPageIndex: Int = 0

        init(onPageChange: @escaping (Int, Double) -> Void) {
            self.onPageChange = onPageChange
        }

        func startObserving() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged),
                name: .PDFViewPageChanged,
                object: pdfView
            )
        }

        @objc func pageChanged() {
            guard let pdfView, let currentPage = pdfView.currentPage,
                  let document = pdfView.document,
                  let pageIndex = document.index(for: currentPage) as Int? else { return }
            let scrollOffset = pdfView.documentView?.bounds.origin.y ?? 0
            lastPageIndex = pageIndex
            onPageChange(pageIndex, scrollOffset)
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard let pdfView else { return }
            // Don't toggle toolbar if there's an active text selection
            if pdfView.currentSelection != nil {
                pdfView.clearSelection()
                return
            }
            pdfView.onTapEmpty?()
        }

        @objc func handleDoubleTap() {
            guard let pdfView else { return }
            let fitScale = pdfView.scaleFactorForSizeToFit
            if pdfView.scaleFactor > fitScale * 1.1 {
                pdfView.scaleFactor = fitScale
            } else {
                pdfView.scaleFactor = fitScale * 2
            }
        }

        // Allow simultaneous recognition so we don't block PDFView's built-in gestures
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
