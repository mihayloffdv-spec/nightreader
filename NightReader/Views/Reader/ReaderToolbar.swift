import SwiftUI

// MARK: - Reader Toolbar (Deep Forest design)
//
// Minimal toolbar: chapter name at top, thin progress bar + actions at bottom.
// Uses theme tokens for colors and fonts.
//
// ┌─────────────────────────────────────────┐
// │  ☰  Chapter 1: The Silent Sea      ⚑ ⋯ │  ← top bar
// │                                         │
// │           (reading content)              │
// │                                         │
// │  ═══════════════════════ 42%            │  ← progress
// │  p.42  │  📖  🔍  Aa  📓              │  ← bottom bar
// └─────────────────────────────────────────┘

struct ReaderToolbar: View {
    @Bindable var viewModel: ReaderViewModel
    let onDismiss: () -> Void

    @State private var showMenu = false
    @State private var showSettings = false
    @State private var showThemeEditor = false
    @State private var editingTheme: Theme?

    private var theme: Theme { viewModel.selectedTheme }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .background(theme.background.opacity(0.9))
                .background(.ultraThinMaterial)
                .transition(.move(edge: .top).combined(with: .opacity))

            Spacer()

            bottomBar
                .background(theme.background.opacity(0.9))
                .background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .foregroundStyle(theme.textPrimary)
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(viewModel: viewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showThemeEditor) {
            ThemeEditorView(editingTheme: editingTheme) { newTheme in
                saveCustomTheme(newTheme)
                viewModel.setTheme(newTheme)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func saveCustomTheme(_ newTheme: Theme) {
        var customs = Theme.loadCustomThemes()
        customs.removeAll { $0.id == newTheme.id }
        customs.append(newTheme)
        Theme.saveCustomThemes(customs)
    }

    private func deleteCurrentCustomTheme() {
        let themeId = viewModel.selectedTheme.id
        var customs = Theme.loadCustomThemes()
        customs.removeAll { $0.id == themeId }
        Theme.saveCustomThemes(customs)
        viewModel.setTheme(.deepForest)
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

            Spacer()

            // Chapter name (center)
            VStack(spacing: 2) {
                if let chapter = viewModel.currentChapter {
                    Text(chapter.title)
                        .font(theme.labelFont(size: 14))
                        .lineLimit(1)
                } else {
                    Text(viewModel.book.title)
                        .font(theme.labelFont(size: 14))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(theme.textPrimary.opacity(0.8))

            Spacer()

            // Bookmark
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    viewModel.toggleBookmark()
                }
            } label: {
                Image(systemName: viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.body.weight(.regular))
                    .foregroundStyle(viewModel.isCurrentPageBookmarked ? theme.accent : theme.textPrimary)
                    .frame(width: 44, height: 44)
            }

            // Menu
            toolbarMenu
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Bottom Bar

    @State private var isDraggingScrubber = false

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // Progress bar (thin, accent colored)
            HStack(spacing: 12) {
                Text(viewModel.progressText)
                    .font(theme.captionFont(size: 12).monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
                    .contentTransition(.numericText())

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(theme.surface.opacity(0.3))
                            .frame(height: isDraggingScrubber ? 5 : 2)

                        Capsule()
                            .fill(theme.accent)
                            .frame(
                                width: max(2, geo.size.width * viewModel.progressFraction),
                                height: isDraggingScrubber ? 5 : 2
                            )

                        if isDraggingScrubber {
                            Circle()
                                .fill(theme.accent)
                                .frame(width: 12, height: 12)
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                .offset(x: max(0, min(geo.size.width - 12, geo.size.width * viewModel.progressFraction - 6)))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                withAnimation(.easeOut(duration: 0.1)) { isDraggingScrubber = true }
                                let fraction = max(0, min(1, value.location.x / geo.size.width))
                                let page = Int(fraction * Double(max(1, viewModel.book.totalPages - 1)))
                                viewModel.goToPage(page)
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.2)) { isDraggingScrubber = false }
                                viewModel.scheduleHideToolbar()
                            }
                    )
                }
                .frame(height: 20)
                .animation(.easeInOut(duration: 0.15), value: isDraggingScrubber)

                Text("\(Int(viewModel.progressFraction * 100))%")
                    .font(theme.captionFont(size: 12).monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
                    .contentTransition(.numericText())
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.progressFraction)

            // Chapter info + action buttons
            HStack(spacing: 0) {
                // Chapter progress
                if let chapter = viewModel.currentChapter {
                    Text("\(chapter.title) — \(Int(viewModel.chapterProgress * 100))%")
                        .font(theme.captionFont(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Action buttons row
                HStack(spacing: 4) {
                    // Reader Mode toggle
                    Button {
                        withAnimation { viewModel.toggleReaderMode() }
                    } label: {
                        Image(systemName: viewModel.isReaderMode ? "doc.richtext" : "book")
                            .frame(width: 40, height: 40)
                    }

                    // Day Mode toggle
                    Button {
                        withAnimation { viewModel.toggleDayMode() }
                    } label: {
                        Image(systemName: viewModel.isDayMode ? "moon.fill" : "sun.max")
                            .foregroundStyle(viewModel.isDayMode ? theme.accent : theme.textPrimary.opacity(0.7))
                            .frame(width: 40, height: 40)
                    }

                    // Search
                    Button {
                        withAnimation { viewModel.showSearch = true }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .frame(width: 40, height: 40)
                    }

                    // Font size (Reader Mode)
                    if viewModel.isReaderMode {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "textformat.size")
                                .frame(width: 40, height: 40)
                        }
                    }

                    // Highlights
                    Button {
                        viewModel.showAnnotationList = true
                    } label: {
                        Image(systemName: "highlighter")
                            .frame(width: 40, height: 40)
                    }
                }
                .font(.system(size: 15))
                .foregroundStyle(theme.textPrimary.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Menu

    private var toolbarMenu: some View {
        Menu {
            // Reader Mode toggle
            Button {
                withAnimation { viewModel.toggleReaderMode() }
            } label: {
                Label(
                    viewModel.isReaderMode ? "PDF View" : "Reader Mode",
                    systemImage: viewModel.isReaderMode ? "doc.richtext" : "book"
                )
            }

            // Day Mode toggle (only in Reader Mode)
            if viewModel.isReaderMode {
                Button {
                    withAnimation { viewModel.toggleDayMode() }
                } label: {
                    Label(
                        viewModel.isDayMode ? "Night Mode" : "Day Mode",
                        systemImage: viewModel.isDayMode ? "moon.fill" : "sun.max"
                    )
                }
            }

            Divider()

            // Table of Contents
            Button {
                viewModel.showTOC = true
            } label: {
                Label("Contents", systemImage: "list.bullet")
            }

            // Rendering mode (PDF mode only)
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

            // Theme submenu
            Menu {
                ForEach(Theme.allThemes) { t in
                    Button {
                        viewModel.setTheme(t)
                    } label: {
                        HStack {
                            Text(t.name)
                            if viewModel.selectedTheme.id == t.id {
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

            // Export
            Button {
                viewModel.exportAnnotations()
            } label: {
                Label("Export Highlights", systemImage: "square.and.arrow.up")
            }

            Divider()

            // Display settings
            Button {
                showSettings = true
            } label: {
                Label("Display Settings", systemImage: "textformat.size")
            }

            // AI Settings
            Button {
                viewModel.showAPIKeySettings = true
            } label: {
                Label("AI Settings", systemImage: "key")
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
    }
}
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
                        Text("Manual").tag(AutoSwitchMode.manual)
                        Text("Schedule").tag(AutoSwitchMode.schedule)
                        Text("Match Device").tag(AutoSwitchMode.device)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)

                    if AppSettings.shared.autoSwitchMode == .schedule {
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
