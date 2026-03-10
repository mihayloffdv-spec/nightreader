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
                onPageChange: { page, offset in
                    viewModel.savePosition(pageIndex: page, scrollOffset: offset)
                },
                onHighlight: { _ in }
            )
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.toggleToolbar()
                }
            }

            // Dimmer overlay (above PDF, below toolbar)
            if viewModel.dimmerOpacity > 0 {
                DimmerOverlay(opacity: viewModel.dimmerOpacity)
            }

            // Toolbar
            if viewModel.toolbarVisible {
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
                onSelectAnnotation: { pageIndex in
                    viewModel.currentPage = pageIndex
                },
                onDeleteAnnotation: { _, _ in }
            )
        }
    }
}
