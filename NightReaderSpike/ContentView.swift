import SwiftUI
import PDFKit

struct ContentView: View {
    @State private var darkModeStyle: DarkModeStyle = .off
    @State private var selectedPDF: String = "Text Only"
    @State private var pdfDocuments: [String: PDFDocument] = [:]

    private let pdfNames = ["Text Only", "Text + Images", "Colored Diagrams"]

    var body: some View {
        VStack(spacing: 0) {
            // PDF Viewer
            PDFKitView(
                document: pdfDocuments[selectedPDF],
                darkModeStyle: darkModeStyle
            )
            .ignoresSafeArea(edges: .horizontal)

            // Controls
            VStack(spacing: 12) {
                // PDF file picker
                Picker("PDF", selection: $selectedPDF) {
                    ForEach(pdfNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.segmented)

                // Dark mode style picker
                Picker("Dark Mode", selection: $darkModeStyle) {
                    ForEach(DarkModeStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .onAppear {
            pdfDocuments = TestPDFGenerator.generateAllTestPDFs()
        }
    }
}

#Preview {
    ContentView()
}
