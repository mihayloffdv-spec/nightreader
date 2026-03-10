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
                isDarkModeEnabled: viewModel.isDarkModeEnabled,
                initialPageIndex: viewModel.book.lastPageIndex,
                onPageChange: { page, offset in
                    viewModel.savePosition(pageIndex: page, scrollOffset: offset)
                }
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
    }
}
