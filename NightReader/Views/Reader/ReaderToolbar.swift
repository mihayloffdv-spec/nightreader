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
                Button(action: viewModel.toggleDarkMode) {
                    Image(systemName: viewModel.isDarkModeEnabled ? "moon.fill" : "moon")
                        .font(.title3)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

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
}
