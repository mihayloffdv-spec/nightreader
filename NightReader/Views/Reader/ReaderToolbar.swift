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

                Text(viewModel.book.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                // Action buttons — 44pt tap targets
                toolbarButton("magnifyingglass") {
                    withAnimation { viewModel.showSearch = true }
                }
                toolbarButton("list.bullet") {
                    viewModel.showTOC = true
                }
                toolbarButton(viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark") {
                    viewModel.toggleBookmark()
                }
                toolbarButton("highlighter") {
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

                toolbarButton("paintpalette") {
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

                    Button {
                        withAnimation { showSettings.toggle() }
                        viewModel.scheduleHideToolbar()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
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

    private func toolbarButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 44, height: 44)
        }
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

            HStack(spacing: 14) {
                Image(systemName: "crop").font(.callout)
                    .frame(width: 24)
                Slider(value: Binding(
                    get: { viewModel.book.cropMargin },
                    set: { viewModel.setCropMargin($0) }
                ), in: 0...100)
                Text("Crop").font(.footnote)
            }
            .frame(height: 36)
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
            }
            Spacer()
            Button { viewModel.exportAnnotations() } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
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
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }
}
