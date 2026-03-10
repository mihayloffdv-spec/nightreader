import SwiftUI

struct ReaderToolbar: View {
    @Bindable var viewModel: ReaderViewModel
    let onDismiss: () -> Void

    @State private var brightness: Double = Double(UIScreen.main.brightness)

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 16) {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                }

                Text(viewModel.book.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                // Action buttons
                Button { withAnimation { viewModel.showSearch = true } } label: {
                    Image(systemName: "magnifyingglass").font(.body)
                }
                Button { viewModel.showTOC = true } label: {
                    Image(systemName: "list.bullet").font(.body)
                }
                Button { viewModel.toggleBookmark() } label: {
                    Image(systemName: viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.body)
                }
                Button { viewModel.showAnnotationList = true } label: {
                    Image(systemName: "highlighter").font(.body)
                }
                Button { withAnimation { viewModel.showThemePicker.toggle() } } label: {
                    Image(systemName: "paintpalette").font(.body)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            // Theme picker panel
            if viewModel.showThemePicker {
                themePicker
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            // Bottom controls
            VStack(spacing: 12) {
                // Progress
                HStack {
                    Text(viewModel.progressText)
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    Text("\(Int(viewModel.progressFraction * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                }

                ProgressView(value: viewModel.progressFraction)
                    .tint(.white.opacity(0.6))

                // Rendering mode picker
                Picker("Mode", selection: Binding(
                    get: { viewModel.renderingMode },
                    set: { viewModel.setRenderingMode($0) }
                )) {
                    ForEach(RenderingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                // Highlight colors + export
                HStack(spacing: 10) {
                    Image(systemName: "highlighter")
                        .font(.caption)
                    ForEach(HighlightColor.allCases) { color in
                        Button {
                            viewModel.highlightColor = color
                        } label: {
                            Circle()
                                .fill(Color(color.displayColor))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.white, lineWidth: viewModel.highlightColor == color ? 2 : 0)
                                )
                        }
                    }
                    Spacer()
                    Button { viewModel.exportAnnotations() } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                    }
                }

                // Brightness
                HStack(spacing: 12) {
                    Image(systemName: "sun.min").font(.caption)
                    Slider(value: $brightness, in: 0...1) { _ in
                        UIScreen.main.brightness = CGFloat(brightness)
                    }
                    Image(systemName: "sun.max").font(.caption)
                }

                // Dimmer
                HStack(spacing: 12) {
                    Image(systemName: "circle.lefthalf.filled").font(.caption)
                    Slider(value: $viewModel.dimmerOpacity, in: 0...0.9)
                    Text("Dimmer").font(.caption)
                }

                // Crop margin
                HStack(spacing: 12) {
                    Image(systemName: "crop").font(.caption)
                    Slider(value: Binding(
                        get: { viewModel.book.cropMargin },
                        set: { viewModel.setCropMargin($0) }
                    ), in: 0...100)
                    Text("Crop").font(.caption)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .foregroundStyle(.white)
    }

    private var themePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Theme.allBuiltIn) { theme in
                    Button {
                        viewModel.setTheme(theme)
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(theme.bgColor)
                                .overlay(
                                    Circle()
                                        .fill(theme.tintColor)
                                        .frame(width: 20, height: 20)
                                )
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.white, lineWidth: viewModel.selectedTheme.id == theme.id ? 2 : 0)
                                )
                            Text(theme.name)
                                .font(.caption2)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }
}
