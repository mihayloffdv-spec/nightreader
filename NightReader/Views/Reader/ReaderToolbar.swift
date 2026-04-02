import SwiftUI

struct ReaderToolbar: View {
    @Bindable var viewModel: ReaderViewModel
    let onDismiss: () -> Void

    @State private var showMenu = false
    @State private var showSettings = false
    @State private var showThemeEditor = false
    @State private var editingTheme: Theme?

    var body: some View {
        VStack(spacing: 0) {
            // ── Top bar: Back · Title · Bookmark · Menu ──
            topBar
                .background(.ultraThinMaterial)
                .transition(.move(edge: .top).combined(with: .opacity))

            Spacer()

            // ── Bottom bar: page slider + progress ──
            bottomBar
                .background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(viewModel: viewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showThemeEditor) {
            ThemeEditorView(editingTheme: editingTheme) { theme in
                saveCustomTheme(theme)
                viewModel.setTheme(theme)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func saveCustomTheme(_ theme: Theme) {
        var customs = Theme.loadCustomThemes()
        customs.removeAll { $0.id == theme.id }
        customs.append(theme)
        Theme.saveCustomThemes(customs)
    }

    private func deleteCurrentCustomTheme() {
        let themeId = viewModel.selectedTheme.id
        var customs = Theme.loadCustomThemes()
        customs.removeAll { $0.id == themeId }
        Theme.saveCustomThemes(customs)
        viewModel.setTheme(.midnight)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            // Back
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back")

            // Title
            Text(viewModel.book.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            // Font size quick buttons (Reader Mode only)
            if viewModel.isReaderMode {
                Button {
                    let newSize = max(12, viewModel.readerFontSize - 1)
                    viewModel.setReaderFontSize(newSize)
                } label: {
                    Text("A")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 34, height: 44)
                }
                .accessibilityLabel("Decrease font size")

                Button {
                    let newSize = min(32, viewModel.readerFontSize + 1)
                    viewModel.setReaderFontSize(newSize)
                } label: {
                    Text("A")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 34, height: 44)
                }
                .accessibilityLabel("Increase font size")
            }

            // Bookmark
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    viewModel.toggleBookmark()
                }
            } label: {
                Image(systemName: viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.body.weight(.regular))
                    .frame(width: 44, height: 44)
                    .scaleEffect(viewModel.isCurrentPageBookmarked ? 1.0 : 0.9)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: viewModel.isCurrentPageBookmarked)
            }
            .accessibilityLabel("Bookmark")

            // Menu (...)
            Menu {
                // Search
                Button {
                    withAnimation { viewModel.showSearch = true }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }

                // Table of Contents
                Button {
                    viewModel.showTOC = true
                } label: {
                    Label("Contents", systemImage: "list.bullet")
                }

                Divider()

                // Reader Mode toggle
                Button {
                    withAnimation { viewModel.toggleReaderMode() }
                } label: {
                    Label(
                        viewModel.isReaderMode ? "PDF View" : "Reader Mode",
                        systemImage: viewModel.isReaderMode ? "doc.richtext" : "book"
                    )
                }

                // Rendering mode (only in PDF mode)
                if !viewModel.isReaderMode {
                    Menu {
                        ForEach(RenderingMode.allCases) { mode in
                            Button {
                                viewModel.setRenderingMode(mode)
                            } label: {
                                HStack {
                                    Text(mode.displayName)
                                    if viewModel.renderingMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Dark Mode", systemImage: "moon.circle")
                    }
                }

                Divider()

                // Highlights & Annotations
                Button {
                    viewModel.showAnnotationList = true
                } label: {
                    Label("Highlights", systemImage: "highlighter")
                }

                // Highlight color submenu
                Menu {
                    ForEach(HighlightColor.allCases) { color in
                        Button {
                            viewModel.highlightColor = color
                        } label: {
                            HStack {
                                Text(color.id.capitalized)
                                if viewModel.highlightColor == color {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        viewModel.exportAnnotations()
                    } label: {
                        Label("Export Highlights", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Highlight Color", systemImage: "circle.fill")
                }

                Divider()

                // Settings (opens sheet)
                Button {
                    showSettings = true
                } label: {
                    Label("Display Settings", systemImage: "textformat.size")
                }

                // Theme submenu
                Menu {
                    ForEach(Theme.allThemes) { theme in
                        Button {
                            viewModel.setTheme(theme)
                        } label: {
                            HStack {
                                Text(theme.name)
                                if viewModel.selectedTheme.id == theme.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        editingTheme = nil
                        showThemeEditor = true
                    } label: {
                        Label("New Theme", systemImage: "plus")
                    }

                    // Edit current custom theme
                    if !viewModel.selectedTheme.isBuiltIn {
                        Button {
                            editingTheme = viewModel.selectedTheme
                            showThemeEditor = true
                        } label: {
                            Label("Edit Theme", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            deleteCurrentCustomTheme()
                        } label: {
                            Label("Delete Theme", systemImage: "trash")
                        }
                    }
                } label: {
                    Label("Theme", systemImage: "paintpalette")
                }

                Divider()

                // AI Settings
                Button {
                    viewModel.showAPIKeySettings = true
                } label: {
                    Label("AI Настройки", systemImage: "key")
                }

                #if DEBUG
                Divider()
                Button {
                    viewModel.runDropCapDiagnostics()
                } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
                #endif
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.regular))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Menu")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Bottom Bar

    @State private var isDraggingScrubber = false

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // Page scrubber — interactive
            HStack(spacing: 12) {
                Text(viewModel.progressText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .contentTransition(.numericText())

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        Capsule()
                            .fill(.white.opacity(0.15))
                            .frame(height: isDraggingScrubber ? 6 : 3)

                        // Fill
                        Capsule()
                            .fill(.white.opacity(isDraggingScrubber ? 0.7 : 0.5))
                            .frame(
                                width: max(3, geo.size.width * viewModel.progressFraction),
                                height: isDraggingScrubber ? 6 : 3
                            )

                        // Thumb (visible on drag)
                        if isDraggingScrubber {
                            Circle()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                .offset(x: max(0, min(geo.size.width - 14, geo.size.width * viewModel.progressFraction - 7)))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                withAnimation(.easeOut(duration: 0.1)) {
                                    isDraggingScrubber = true
                                }
                                let fraction = max(0, min(1, value.location.x / geo.size.width))
                                let page = Int(fraction * Double(max(1, viewModel.book.totalPages - 1)))
                                viewModel.goToPage(page)
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDraggingScrubber = false
                                }
                                viewModel.scheduleHideToolbar()
                            }
                    )
                }
                .frame(height: 24)
                .animation(.easeInOut(duration: 0.15), value: isDraggingScrubber)

                Text("\(Int(viewModel.progressFraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .contentTransition(.numericText())
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.progressFraction)

            // Chapter name + progress
            if let chapter = viewModel.currentChapter {
                HStack(spacing: 8) {
                    Text(chapter.title)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.5))

                    Text("— \(Int(viewModel.chapterProgress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                        .contentTransition(.numericText())
                }
            }

            // Reading time (Reader Mode only)
            if viewModel.isReaderMode && viewModel.totalWordCount > 0 {
                Text("\(viewModel.estimatedReadingMinutes) min read")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Settings Sheet

struct ReaderSettingsSheet: View {
    @Bindable var viewModel: ReaderViewModel
    @State private var brightness: Double = Double(UIScreen.main.brightness)

    var body: some View {
        NavigationStack {
            List {
                // ── Brightness ──
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "sun.min")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Slider(value: $brightness, in: 0...1) { _ in
                            UIScreen.main.brightness = CGFloat(brightness)
                        }
                        Image(systemName: "sun.max")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Brightness")
                }

                // ── Dimmer ──
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Slider(value: $viewModel.dimmerOpacity, in: 0...0.9)
                        Text("\(Int(viewModel.dimmerOpacity * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Dimmer")
                }

                // ── Crop Margins (PDF mode only) ──
                if !viewModel.isReaderMode {
                    Section {
                        HStack(spacing: 16) {
                            Image(systemName: "arrow.left.and.right.square")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { viewModel.cropMargin },
                                set: { viewModel.setCropMargin($0) }
                            ), in: 0...0.5)
                            Text("\(Int(viewModel.cropMargin * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Crop Margins")
                    }
                }

                // ── Font (Reader Mode only) ──
                if viewModel.isReaderMode {
                    Section {
                        // Font size
                        HStack(spacing: 16) {
                            Image(systemName: "textformat.size.smaller")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { viewModel.readerFontSize },
                                set: { viewModel.setReaderFontSize($0) }
                            ), in: 12...32, step: 1)
                            Image(systemName: "textformat.size.larger")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)

                        // Font family
                        HStack(spacing: 0) {
                            ForEach(ReaderFont.allCases) { font in
                                Button {
                                    viewModel.setReaderFontFamily(font)
                                } label: {
                                    Text("Aa")
                                        .font(.system(
                                            size: 16,
                                            weight: viewModel.readerFontFamily == font ? .semibold : .regular,
                                            design: font.design
                                        ))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(viewModel.readerFontFamily == font
                                                      ? .white.opacity(0.15)
                                                      : .clear)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white.opacity(0.06))
                        )
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Font")
                    }
                }
                // ── Auto Theme Switching ──
                Section {
                    Picker("Mode", selection: Binding(
                        get: { AppSettings.shared.autoSwitchMode },
                        set: { AppSettings.shared.autoSwitchMode = $0 }
                    )) {
                        Text("Manual").tag("manual")
                        Text("Schedule").tag("schedule")
                        Text("Match Device").tag("device")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)

                    if AppSettings.shared.autoSwitchMode == "schedule" {
                        HStack {
                            Text("Dark hours")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(AppSettings.shared.darkStartHour):00 – \(AppSettings.shared.darkEndHour):00")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Auto Theme")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Display")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                brightness = Double(UIScreen.main.brightness)
            }
        }
    }
}
