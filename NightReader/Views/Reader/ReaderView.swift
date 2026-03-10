import SwiftUI
import SwiftData

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: ReaderViewModel

    init(book: Book) {
        _viewModel = State(initialValue: ReaderViewModel(book: book))
    }

    var body: some View {
        ZStack {
            // PDF content
            PDFKitView(
                document: viewModel.document,
                renderingMode: viewModel.renderingMode,
                theme: viewModel.selectedTheme,
                initialPageIndex: viewModel.book.lastPageIndex,
                highlightColor: viewModel.highlightColor,
                goToPageIndex: viewModel.goToPageIndex,
                cropMargin: viewModel.book.cropMargin,
                onPageChange: { page, offset in
                    viewModel.savePosition(pageIndex: page, scrollOffset: offset)
                    viewModel.goToPageIndex = nil
                },
                onHighlight: { _ in }
            )
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.toggleToolbar()
                }
            }

            // Dimmer overlay
            if viewModel.dimmerOpacity > 0 {
                DimmerOverlay(opacity: viewModel.dimmerOpacity)
            }

            // Search bar (top, below status bar)
            if viewModel.showSearch {
                VStack {
                    SearchBarView(
                        isPresented: $viewModel.showSearch,
                        document: viewModel.document,
                        onGoToPage: { viewModel.goToPage($0) }
                    )
                    Spacer()
                }
                .transition(.move(edge: .top))
            }

            // Toolbar
            if viewModel.toolbarVisible && !viewModel.showSearch {
                ReaderToolbar(viewModel: viewModel) {
                    dismiss()
                }
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(!viewModel.toolbarVisible)
        .onAppear {
            viewModel.scheduleHideToolbar()
        }
        .onDisappear {
            viewModel.cancelHideToolbar()
        }
        .sheet(isPresented: $viewModel.showAnnotationList) {
            AnnotationListView(
                document: viewModel.document,
                onSelectAnnotation: { viewModel.goToPage($0) },
                onDeleteAnnotation: { _, _ in }
            )
        }
        .sheet(isPresented: $viewModel.showTOC) {
            TOCView(
                document: viewModel.document,
                onSelectPage: { viewModel.goToPage($0) }
            )
        }
        .sheet(isPresented: $viewModel.showExportShare) {
            if let url = viewModel.exportURL {
                ShareSheet(items: [url])
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
