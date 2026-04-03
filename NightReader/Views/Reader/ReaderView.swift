import SwiftUI
import SwiftData

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
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
                            fontFamily: viewModel.readerFontFamily,
                            currentPageIndex: viewModel.currentPage,
                            savedBlockID: Int(viewModel.book.scrollOffsetY),
                            goToPageIndex: $viewModel.goToPageIndex,
                            onPageChange: { page, blockID in
                                viewModel.savePosition(pageIndex: page, scrollOffset: Double(blockID))
                            },
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    viewModel.toggleToolbar()
                                }
                            },
                            onAIAction: { action, text in
                                if action == .explain {
                                    viewModel.requestExplain(text: text)
                                } else {
                                    viewModel.requestTranslate(text: text)
                                }
                            }
                        )
                        .ignoresSafeArea()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    } else {
                        // PDF content
                        PDFKitView(
                            document: viewModel.document,
                            renderingMode: viewModel.renderingMode,
                            theme: viewModel.selectedTheme,
                            initialPageIndex: viewModel.book.lastPageIndex,
                            highlightColor: viewModel.highlightColor,
                            cropMargin: viewModel.cropMargin,
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
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.isReaderMode)

                // Dimmer overlay
                if viewModel.dimmerOpacity > 0 {
                    DimmerOverlay(opacity: viewModel.dimmerOpacity)
                        .allowsHitTesting(false)
                }

                // Search bar (top, below status bar)
                if viewModel.showSearch {
                    VStack {
                        SearchBarView(
                            isPresented: $viewModel.showSearch,
                            document: viewModel.isReaderMode ? viewModel.originalDoc : viewModel.document,
                            onGoToSelection: { sel in
                                if viewModel.isReaderMode {
                                    // In Reader Mode, navigate to the page containing the selection
                                    if let page = sel.pages.first,
                                       let doc = viewModel.originalDoc {
                                        let idx = doc.index(for: page)
                                        viewModel.goToPage(idx)
                                    }
                                } else {
                                    viewModel.goToSelection(sel)
                                }
                            }
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
                }
            }
        }
        .background(Color.black)
        .animation(.easeInOut(duration: 0.3), value: viewModel.selectedTheme.id)
        .navigationBarHidden(true)
        .statusBarHidden(!viewModel.toolbarVisible)
        .task {
            await viewModel.loadDocument()
        }
        .onAppear {
            viewModel.scheduleHideToolbar()
            viewModel.startReadingSession()
            // Auto-switch theme based on settings
            let resolved = AppSettings.shared.resolvedTheme(isDarkAppearance: colorScheme == .dark)
            if AppSettings.shared.autoSwitchMode != .manual && resolved.id != viewModel.selectedTheme.id {
                viewModel.setTheme(resolved)
            }
        }
        .onChange(of: colorScheme) { _, newScheme in
            if AppSettings.shared.autoSwitchMode == .device {
                let resolved = AppSettings.shared.resolvedTheme(isDarkAppearance: newScheme == .dark)
                viewModel.setTheme(resolved)
            }
        }
        .onDisappear {
            viewModel.cancelHideToolbar()
            viewModel.stopReadingSession()
        }
        .sheet(isPresented: $viewModel.showAnnotationList) {
            AnnotationListView(
                document: viewModel.originalDoc ?? viewModel.document,
                onSelectAnnotation: { viewModel.goToPage($0) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showTOC) {
            TOCView(
                chapters: viewModel.chapters,
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
        .sheet(isPresented: $viewModel.showAISheet) {
            AIActionSheet(
                actionType: viewModel.aiActionType,
                selectedText: viewModel.aiSelectedText,
                state: viewModel.aiResponseState,
                theme: viewModel.selectedTheme,
                onDismiss: { viewModel.dismissAISheet() },
                onRetry: { viewModel.retryAIAction() },
                onOpenSettings: {
                    viewModel.dismissAISheet()
                    viewModel.showAPIKeySettings = true
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showAPIKeySettings) {
            APIKeySettingsView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
