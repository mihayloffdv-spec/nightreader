import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument?
    let darkModeStyle: DarkModeStyle

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemBackground
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Remove any existing layer filters first
        DarkModeFilters.removeSimpleDarkMode(from: pdfView)

        switch darkModeStyle {
        case .off:
            // Show original document
            if pdfView.document !== document {
                pdfView.document = document
            } else {
                // If switching from smart mode, need to reload original
                reloadOriginalDocument(pdfView)
            }

        case .simple:
            // Show original document + CIColorMatrix on layer
            reloadOriginalDocument(pdfView)
            DarkModeFilters.applySimpleDarkMode(to: pdfView)

        case .smart:
            // Wrap pages with DarkModePDFPage subclass
            applySmartDarkMode(to: pdfView)
        }
    }

    private func reloadOriginalDocument(_ pdfView: PDFView) {
        if let document = document {
            // Always reload to clear any smart-mode wrapped pages
            pdfView.document = document
        }
    }

    private func applySmartDarkMode(to pdfView: PDFView) {
        guard let originalDoc = document else { return }

        let darkDocument = PDFDocument()
        for i in 0..<originalDoc.pageCount {
            guard let originalPage = originalDoc.page(at: i) else { continue }
            let darkPage = DarkModePDFPage(wrapping: originalPage, pageIndex: i)
            darkDocument.insert(darkPage, at: i)
        }
        pdfView.document = darkDocument
    }
}
