import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument?
    let renderingMode: RenderingMode
    let theme: Theme
    let initialPageIndex: Int
    let highlightColor: HighlightColor
    let goToPageIndex: Int?
    let cropMargin: Double
    let onPageChange: (Int, Double) -> Void
    let onHighlight: (PDFSelection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChange: onPageChange, onHighlight: onHighlight)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(white: 0.05, alpha: 1)
        pdfView.document = document

        // Restore reading position
        if let doc = document, initialPageIndex > 0, initialPageIndex < doc.pageCount,
           let page = doc.page(at: initialPageIndex) {
            pdfView.go(to: page)
        }

        // Add highlight menu item
        let highlightItem = UIMenuItem(title: "Highlight", action: #selector(Coordinator.highlightSelection))
        UIMenuController.shared.menuItems = [highlightItem]

        context.coordinator.pdfView = pdfView
        context.coordinator.startObserving()

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Update document if it changed (e.g. switching to/from Smart mode)
        if pdfView.document !== document {
            let currentPageIndex = context.coordinator.lastPageIndex
            pdfView.document = document
            if let doc = document, currentPageIndex < doc.pageCount,
               let page = doc.page(at: currentPageIndex) {
                pdfView.go(to: page)
            }
        }

        context.coordinator.highlightColor = highlightColor

        // Navigate to page if requested
        if let pageIndex = goToPageIndex,
           let doc = pdfView.document, pageIndex < doc.pageCount,
           let page = doc.page(at: pageIndex) {
            pdfView.go(to: page)
        }

        // Apply crop margin
        if cropMargin > 0 {
            pdfView.displaysPageBreaks = true
            let inset = CGFloat(cropMargin)
            pdfView.pageBreakMargins = UIEdgeInsets(top: -inset, left: -inset, bottom: -inset, right: -inset)
        } else {
            pdfView.pageBreakMargins = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        }

        // Simple mode uses compositing filter overlays
        if renderingMode == .simple {
            DarkModeRenderer.applyDarkMode(to: pdfView, theme: theme)
        } else {
            DarkModeRenderer.removeDarkMode(from: pdfView)
        }
    }

    class Coordinator: NSObject {
        weak var pdfView: PDFView?
        let onPageChange: (Int, Double) -> Void
        let onHighlight: (PDFSelection) -> Void
        var lastPageIndex: Int = 0
        var highlightColor: HighlightColor = .yellow

        init(onPageChange: @escaping (Int, Double) -> Void, onHighlight: @escaping (PDFSelection) -> Void) {
            self.onPageChange = onPageChange
            self.onHighlight = onHighlight
        }

        func startObserving() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged),
                name: .PDFViewPageChanged,
                object: pdfView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(selectionChanged),
                name: .PDFViewSelectionChanged,
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

        @objc func selectionChanged() {
            // Selection changed — menu will show automatically from PDFView
        }

        @objc func highlightSelection() {
            guard let pdfView, let selection = pdfView.currentSelection,
                  let document = pdfView.document else { return }
            _ = AnnotationService.addHighlight(to: selection, in: document, color: highlightColor)
            AnnotationService.saveAnnotations(in: document)
            pdfView.clearSelection()
            onHighlight(selection)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
