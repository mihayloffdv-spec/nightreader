import SwiftUI

struct ReaderToolbar: View {
    @Bindable var viewModel: ReaderViewModel
    let onDismiss: () -> Void

    @State private var brightness: Double = Double(UIScreen.main.brightness)
    @State private var showHighlightColors = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 0) {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.title2.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")

                Text(viewModel.book.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                // Action buttons — 44pt tap targets
                toolbarButton("magnifyingglass", label: "Search") {
                    withAnimation { viewModel.showSearch = true }
                }
                toolbarButton("list.bullet", label: "Contents") {
                    viewModel.showTOC = true
                }
                toolbarButton(viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark", label: "Bookmark") {
                    viewModel.toggleBookmark()
                }
                toolbarButton("highlighter", label: "Highlights") {
                    viewModel.showAnnotationList = true
                }

                // Highlight color button
                Button {
                    withAnimation { showHighlightColors.toggle() }
                    viewModel.scheduleHideToolbar()
                } label: {
                    Circle()
                        .fill(Color(viewModel.highlightColor.displayColor))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Highlight color")

                toolbarButton(viewModel.isReaderMode ? "book.fill" : "book", label: "Reader Mode") {
                    withAnimation { viewModel.toggleReaderMode() }
                }

                toolbarButton("paintpalette", label: "Theme") {
                    withAnimation { viewModel.showThemePicker.toggle() }
                    viewModel.scheduleHideToolbar()
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)

            // Expandable panels
            if showHighlightColors {
                highlightColorPicker
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if viewModel.showThemePicker {
                themePicker
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            // Bottom bar
            VStack(spacing: 12) {
                // Progress
                HStack {
                    Text(viewModel.progressText)
                        .font(.footnote)
                        .monospacedDigit()
                    Spacer()
                    Text("\(Int(viewModel.progressFraction * 100))%")
                        .font(.footnote)
                        .monospacedDigit()
                }

                ProgressView(value: viewModel.progressFraction)
                    .tint(.white.opacity(0.6))
                    .scaleEffect(y: 1.5)

                // Mode picker + settings gear
                HStack(spacing: 12) {
                    if !viewModel.isReaderMode {
                        Picker("Mode", selection: Binding(
                            get: { viewModel.renderingMode },
                            set: { viewModel.setRenderingMode($0) }
                        )) {
                            ForEach(RenderingMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.regular)
                    }

                    Button {
                        withAnimation { showSettings.toggle() }
                        viewModel.scheduleHideToolbar()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                }

                // Settings panel
                if showSettings {
                    settingsPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
        }
        .foregroundStyle(.white)
    }

    // MARK: - Toolbar button helper (44pt tap target)

    private func toolbarButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }

    // MARK: - Settings panel

    private var settingsPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "sun.min").font(.callout)
                    .frame(width: 24)
                Slider(value: $brightness, in: 0...1) { _ in
                    UIScreen.main.brightness = CGFloat(brightness)
                    viewModel.scheduleHideToolbar()
                }
                Image(systemName: "sun.max").font(.callout)
                    .frame(width: 24)
            }
            .frame(height: 36)
            .onAppear {
                brightness = Double(UIScreen.main.brightness)
            }

            HStack(spacing: 14) {
                Image(systemName: "circle.lefthalf.filled").font(.callout)
                    .frame(width: 24)
                Slider(value: $viewModel.dimmerOpacity, in: 0...0.9)
                    .onChange(of: viewModel.dimmerOpacity) {
                        viewModel.scheduleHideToolbar()
                    }
                Text("Dimmer").font(.footnote)
            }
            .frame(height: 36)

            if viewModel.isReaderMode {
                HStack(spacing: 14) {
                    Image(systemName: "textformat.size.smaller").font(.callout)
                        .frame(width: 24)
                    Slider(value: Binding(
                        get: { viewModel.readerFontSize },
                        set: { viewModel.setReaderFontSize($0) }
                    ), in: 12...32, step: 1)
                        .onChange(of: viewModel.readerFontSize) {
                            viewModel.scheduleHideToolbar()
                        }
                    Image(systemName: "textformat.size.larger").font(.callout)
                        .frame(width: 24)
                }
                .frame(height: 36)

                // Font family picker
                HStack(spacing: 0) {
                    ForEach(ReaderFont.allCases) { font in
                        Button {
                            viewModel.setReaderFontFamily(font)
                            viewModel.scheduleHideToolbar()
                        } label: {
                            Text("Aa")
                                .font(.system(size: 15, weight: viewModel.readerFontFamily == font ? .bold : .regular, design: font.design))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(viewModel.readerFontFamily == font ? .white.opacity(0.2) : .clear)
                                )
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.08))
                )
                .frame(height: 36)
            }

            #if DEBUG
            // Diagnostic button for testing drop cap recovery
            Button {
                viewModel.runDropCapDiagnostics()
            } label: {
                HStack {
                    if viewModel.isRunningDiagnostics {
                        ProgressView().tint(.white)
                        Text("Running diagnostics...").font(.footnote)
                    } else {
                        Image(systemName: "stethoscope")
                        Text("Drop Cap Diagnostics").font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12)))
            }
            .disabled(viewModel.isRunningDiagnostics)

            if let report = viewModel.diagnosticReport {
                ScrollView {
                    Text(report)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.5)))
            }
            #endif
        }
        .padding(.top, 4)
    }

    // MARK: - Highlight color picker

    private var highlightColorPicker: some View {
        HStack(spacing: 16) {
            ForEach(HighlightColor.allCases) { color in
                Button {
                    viewModel.highlightColor = color
                    viewModel.scheduleHideToolbar()
                } label: {
                    Circle()
                        .fill(Color(color.displayColor))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle()
                                .strokeBorder(.white, lineWidth: viewModel.highlightColor == color ? 2.5 : 0)
                        )
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("\(color.id) highlight")
            }
            Spacer()
            Button { viewModel.exportAnnotations() } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Export highlights")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    // MARK: - Theme picker

    private var themePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Theme.allBuiltIn) { theme in
                    Button {
                        viewModel.setTheme(theme)
                    } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(theme.bgColor)
                                .overlay(
                                    Circle()
                                        .fill(theme.tintColor)
                                        .frame(width: 24, height: 24)
                                )
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.white, lineWidth: viewModel.selectedTheme.id == theme.id ? 2.5 : 0)
                                )
                            Text(theme.name)
                                .font(.caption)
                        }
                    }
                    .accessibilityLabel("\(theme.name) theme")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }
}
