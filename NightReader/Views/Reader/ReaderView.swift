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
                    if viewModel.isDayMode {
                        // Day Mode — light reading view
                        DayModeReadingView(
                            document: viewModel.originalDoc,
                            theme: viewModel.selectedTheme,
                            book: viewModel.book,
                            fontSize: viewModel.readerFontSize,
                            currentPageIndex: viewModel.currentPage,
                            savedBlockID: Int(viewModel.book.scrollOffsetY),
                            goToPageIndex: $viewModel.goToPageIndex,
                            chapters: viewModel.chapters,
                            currentChapter: viewModel.currentChapter,
                            onPageChange: { page, blockID in
                                viewModel.savePosition(pageIndex: page, scrollOffset: Double(blockID))
                            },
                            onTap: {
                                withAnimation(.softMenu) {
                                    viewModel.toggleToolbar()
                                }
                            },
                            onAIAction: { action, text in
                                if action == .explain {
                                    viewModel.requestExplain(text: text)
                                } else {
                                    viewModel.requestTranslate(text: text)
                                }
                            },
                            onOpenSettings: {
                                viewModel.toolbarVisible = true
                            }
                        )
                        .ignoresSafeArea()
                        .transition(.opacity)
                    } else if viewModel.isReaderMode || !viewModel.isPDF {
                        // Reader Mode — reflowable text (night)
                        // EPUB/FB2 always use this path (no PDF view fallback)
                        ReaderModeView(
                            document: viewModel.originalDoc,
                            provider: viewModel.provider,
                            theme: viewModel.selectedTheme,
                            fontSize: viewModel.readerFontSize,
                            fontFamily: viewModel.readerFontFamily,
                            customFontOverride: viewModel.readerCustomFontName,
                            currentPageIndex: viewModel.currentPage,
                            savedBlockID: Int(viewModel.book.scrollOffsetY),
                            goToPageIndex: $viewModel.goToPageIndex,
                            onPageChange: { page, blockID in
                                viewModel.savePosition(pageIndex: page, scrollOffset: Double(blockID))
                            },
                            onTap: {
                                withAnimation(.softMenu) {
                                    viewModel.toggleToolbar()
                                }
                            },
                            onAIAction: { action, text in
                                if action == .explain {
                                    viewModel.requestExplain(text: text)
                                } else {
                                    viewModel.requestTranslate(text: text)
                                }
                            },
                            onHighlight: { text in
                                viewModel.createHighlight(text: text)
                            },
                            smartHighlightTexts: viewModel.annotationStore?.activeSmartHighlights.map(\.text) ?? []
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
                            cropMargin: viewModel.cropMargin,
                            goToPageIndex: viewModel.goToPageIndex,
                            goToSelection: viewModel.goToSelectionValue,
                            hasUserToggledRenderingMode: viewModel.hasUserToggledRenderingMode,
                            onPageChange: { page, offset in
                                viewModel.savePosition(pageIndex: page, scrollOffset: offset)
                                viewModel.goToPageIndex = nil
                                viewModel.goToSelectionValue = nil
                            },
                            onHighlight: { _ in },
                            onTapEmpty: {
                                withAnimation(.softMenu) {
                                    viewModel.toggleToolbar()
                                }
                            }
                        )
                        .ignoresSafeArea()
                        .transition(.opacity)
                    }
                }
                .animation(.softFade, value: viewModel.isReaderMode)

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
                    .transition(.softTop)
                }

                // Toolbar
                if viewModel.toolbarVisible && !viewModel.showSearch {
                    ReaderToolbar(viewModel: viewModel) {
                        dismiss()
                    }
                }
            }
        }
        .background(viewModel.selectedTheme.background)
        .animation(.softFade, value: viewModel.selectedTheme.id)
        .animation(.softMenu, value: viewModel.toolbarVisible)
        .animation(.softMenu, value: viewModel.showSearch)
        .navigationBarHidden(true)
        .statusBarHidden(!viewModel.toolbarVisible)
        .toolbar(.hidden, for: .tabBar)
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
            NotebookView(
                document: viewModel.originalDoc ?? viewModel.document,
                bookTitle: viewModel.book.title,
                bookAuthor: viewModel.book.author,
                readProgress: viewModel.progressFraction,
                theme: viewModel.selectedTheme,
                annotationStore: viewModel.annotationStore,
                onSelectAnnotation: { viewModel.goToPage($0) }
            )
            .presentationDetents([.large])
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
        .sheet(isPresented: $viewModel.showAnnotationSheet) {
            AnnotationSheetView(
                highlightText: viewModel.pendingHighlightText,
                theme: viewModel.selectedTheme,
                reaction: $viewModel.pendingReaction,
                action: $viewModel.pendingAction,
                onSave: { viewModel.saveHighlight() },
                onDismiss: { viewModel.dismissAnnotationSheet() }
            )
            .presentationDetents([.fraction(0.5), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showChat) {
            ChatView(viewModel: viewModel, theme: viewModel.selectedTheme)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showChapterReview) {
            if let review = viewModel.currentChapterReview {
                ChapterReviewView(
                    chapterName: review.chapterTitle ?? "Chapter",
                    chapterNumber: review.chapterIndex + 1,
                    theme: viewModel.selectedTheme,
                    review: review,
                    onDismiss: { viewModel.showChapterReview = false }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $viewModel.showPostReadingReview) {
            PostReadingReviewView(viewModel: viewModel, theme: viewModel.selectedTheme)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showSessionRecap) {
            SessionRecapCard(
                duration: viewModel.sessionDuration,
                highlightCount: viewModel.sessionHighlightCount,
                theme: viewModel.selectedTheme,
                onDismiss: { viewModel.showSessionRecap = false }
            )
            .presentationDetents([.fraction(0.4)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $viewModel.showArgumentMap) {
            if let map = viewModel.currentArgumentMap {
                ArgumentMapView(
                    argumentMap: map,
                    theme: viewModel.selectedTheme,
                    onDismiss: { viewModel.showArgumentMap = false }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
