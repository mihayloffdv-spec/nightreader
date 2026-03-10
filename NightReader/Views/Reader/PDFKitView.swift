import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument?
    let isDarkModeEnabled: Bool
    let initialPageIndex: Int
    let onPageChange: (Int, Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChange: onPageChange)
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

        context.coordinator.pdfView = pdfView
        context.coordinator.startObserving()

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if isDarkModeEnabled {
            DarkModeRenderer.applyDarkMode(to: pdfView)
        } else {
            DarkModeRenderer.removeDarkMode(from: pdfView)
        }
    }

    class Coordinator: NSObject {
        weak var pdfView: PDFView?
        let onPageChange: (Int, Double) -> Void

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
            onPageChange(pageIndex, scrollOffset)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
