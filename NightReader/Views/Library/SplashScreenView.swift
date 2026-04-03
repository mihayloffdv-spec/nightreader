import SwiftUI

// MARK: - Splash Screen (Deep Forest design)
//
// Minimalist splash: book+sprout logo, app name, tagline.
// Matches the "Splash Screen & Logo (Deep Forest)" mockup.

struct SplashScreenView: View {
    private static let displayDuration: Double = 3.5
    private static let fadeOutDuration: Double = 0.4

    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var quoteOpacity: Double = 0
    @State private var isFinished = false

    var onFinished: () -> Void

    private var theme: Theme { AppSettings.shared.currentTheme }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo: open book with sprout
                bookLogo
                    .opacity(logoOpacity)
                    .padding(.bottom, 24)

                // App name
                Text("NightReader")
                    .font(theme.headlineFont(size: 28))
                    .foregroundStyle(theme.accent)
                    .opacity(textOpacity)
                    .padding(.bottom, 8)

                // Subtitle
                Text("THE SUBTERRANEAN CONSERVATORY")
                    .font(theme.captionFont(size: 10))
                    .foregroundStyle(theme.textSecondary.opacity(0.6))
                    .kerning(3)
                    .opacity(textOpacity)

                Spacer()

                // Bottom quote
                VStack(spacing: 8) {
                    Circle()
                        .fill(theme.textSecondary.opacity(0.3))
                        .frame(width: 4, height: 4)

                    Text("Cultivating wisdom in the quiet hours.")
                        .font(theme.bodyFont(size: 13))
                        .italic()
                        .foregroundStyle(theme.textSecondary.opacity(0.5))
                }
                .opacity(quoteOpacity)
                .padding(.bottom, 60)
            }
        }
        .task {
            // Staggered fade-in
            withAnimation(.easeIn(duration: 0.6)) {
                logoOpacity = 1
            }
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeIn(duration: 0.5)) {
                textOpacity = 1
            }
            try? await Task.sleep(for: .seconds(0.4))
            withAnimation(.easeIn(duration: 0.6)) {
                quoteOpacity = 1
            }

            // Hold
            try? await Task.sleep(for: .seconds(Self.displayDuration))
            guard !Task.isCancelled else { return }

            // Fade out
            withAnimation(.easeOut(duration: Self.fadeOutDuration)) {
                isFinished = true
            }
            try? await Task.sleep(for: .seconds(Self.fadeOutDuration))
            guard !Task.isCancelled else { return }
            onFinished()
        }
        .opacity(isFinished ? 0 : 1)
    }

    // MARK: - Book Logo (SF Symbol based)

    private var bookLogo: some View {
        ZStack {
            // Open book
            Image(systemName: "book.pages")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(theme.accent)

            // Sprout on top
            Image(systemName: "leaf")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(theme.accent)
                .offset(y: -20)
        }
    }
}

#Preview {
    SplashScreenView { }
}
