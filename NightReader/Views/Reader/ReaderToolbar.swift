import SwiftUI

struct ReaderToolbar: View {
    @Bindable var viewModel: ReaderViewModel
    let onDismiss: () -> Void

    @State private var brightness: Double = Double(UIScreen.main.brightness)

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                Text(viewModel.book.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Button {
                    viewModel.showAnnotationList = true
                } label: {
                    Image(systemName: "highlighter")
                        .font(.title3)
                }
                Button {
                    withAnimation { viewModel.showThemePicker.toggle() }
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.title3)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            // Theme picker panel
            if viewModel.showThemePicker {
                themePicker
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            // Bottom controls
            VStack(spacing: 16) {
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

                // Highlight color
                HStack(spacing: 12) {
                    Image(systemName: "highlighter")
                        .font(.caption)
                    ForEach(HighlightColor.allCases) { color in
                        Button {
                            viewModel.highlightColor = color
                        } label: {
                            Circle()
                                .fill(Color(color.displayColor))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.white, lineWidth: viewModel.highlightColor == color ? 2 : 0)
                                )
                        }
                    }
                    Spacer()
                }

                // Brightness
                HStack(spacing: 12) {
                    Image(systemName: "sun.min")
                        .font(.caption)
                    Slider(value: $brightness, in: 0...1) { _ in
                        UIScreen.main.brightness = CGFloat(brightness)
                    }
                    Image(systemName: "sun.max")
                        .font(.caption)
                }

                // Dimmer
                HStack(spacing: 12) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.caption)
                    Slider(value: $viewModel.dimmerOpacity, in: 0...0.9)
                    Text("Dimmer")
                        .font(.caption)
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
