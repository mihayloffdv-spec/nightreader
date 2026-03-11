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
            if viewModel.isLoading {
                ProgressView("Opening…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if let error = viewModel.loadError {
                ContentUnavailableView {
                    Label("Cannot Open", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Go Back") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Group {
                    if viewModel.isReaderMode {
                        // Reader Mode — reflowable text
                        ReaderModeView(
                            document: viewModel.originalDoc,
                            theme: viewModel.selectedTheme,
                            fontSize: viewModel.readerFontSize,
                            currentPageIndex: viewModel.currentPage,
                            onPageChange: { page in
                                viewModel.savePosition(pageIndex: page, scrollOffset: 0)
                            },
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    viewModel.toggleToolbar()
                                }
                            }
                        )
                        .ignoresSafeArea()
                        .transition(.opacity)
                    } else {
                        // PDF content
                        PDFKitView(
                            document: viewModel.document,
                            renderingMode: viewModel.renderingMode,
                            theme: viewModel.selectedTheme,
                            initialPageIndex: viewModel.book.lastPageIndex,
                            highlightColor: viewModel.highlightColor,
                            goToPageIndex: viewModel.goToPageIndex,
                            goToSelection: viewModel.goToSelectionValue,
                            onPageChange: { page, offset in
                                viewModel.savePosition(pageIndex: page, scrollOffset: offset)
                                viewModel.goToPageIndex = nil
                                viewModel.goToSelectionValue = nil
                            },
                            onHighlight: { _ in },
                            onTapEmpty: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    viewModel.toggleToolbar()
                                }
                            }
                        )
                        .ignoresSafeArea()
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.isReaderMode)

                // Dimmer overlay — exclude toolbar areas
                if viewModel.dimmerOpacity > 0 {
                    DimmerOverlay(opacity: viewModel.dimmerOpacity)
                        .padding(.top, viewModel.toolbarVisible ? 52 : 0)
                        .padding(.bottom, viewModel.toolbarVisible ? 120 : 0)
                }

                // Search bar (top, below status bar)
                if viewModel.showSearch {
                    VStack {
                        SearchBarView(
                            isPresented: $viewModel.showSearch,
                            document: viewModel.document,
                            onGoToSelection: { viewModel.goToSelection($0) }
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
        }
        .background(Color.black)
        .navigationBarHidden(true)
        .statusBarHidden(!viewModel.toolbarVisible)
        .task {
            await viewModel.loadDocument()
        }
        .onAppear {
            viewModel.scheduleHideToolbar()
        }
        .onDisappear {
            viewModel.cancelHideToolbar()
        }
        .sheet(isPresented: $viewModel.showAnnotationList) {
            AnnotationListView(
                document: viewModel.document,
                onSelectAnnotation: { viewModel.goToPage($0) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showTOC) {
            TOCView(
                document: viewModel.document,
                onSelectPage: { viewModel.goToPage($0) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
