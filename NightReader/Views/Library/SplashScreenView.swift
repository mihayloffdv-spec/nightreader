import SwiftUI

// MARK: - Splash Screen (exact Deep Forest mockup replica)
//
// Minimalist: open book icon with sprout, app name, subtitle, bottom quote.
// All elements terracotta on deep green background.

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

                // Book + sprout icon
                bookWithSproutIcon
                    .opacity(logoOpacity)
                    .padding(.bottom, 20)

                // App name — medium weight, not bold
                Text("NightReader")
                    .font(.custom(theme.labelFontName, size: 26))
                    .foregroundStyle(theme.accent)
                    .opacity(textOpacity)
                    .padding(.bottom, 6)

                // Subtitle — uppercase, kerning, muted
                Text("THE SUBTERRANEAN CONSERVATORY")
                    .font(theme.captionFont(size: 9))
                    .foregroundStyle(theme.textSecondary.opacity(0.5))
                    .kerning(3)
                    .opacity(textOpacity)

                Spacer()

                // Bottom: dot + quote
                VStack(spacing: 8) {
                    Circle()
                        .fill(theme.textSecondary.opacity(0.25))
                        .frame(width: 3, height: 3)

                    Text("Cultivating wisdom in the quiet hours.")
                        .font(theme.bodyFont(size: 12))
                        .italic()
                        .foregroundStyle(theme.textSecondary.opacity(0.4))
                }
                .opacity(quoteOpacity)
                .padding(.bottom, 50)
            }
        }
        .task {
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
            try? await Task.sleep(for: .seconds(Self.displayDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: Self.fadeOutDuration)) {
                isFinished = true
            }
            try? await Task.sleep(for: .seconds(Self.fadeOutDuration))
            guard !Task.isCancelled else { return }
            onFinished()
        }
        .opacity(isFinished ? 0 : 1)
    }

    // MARK: - Custom book + sprout icon (matches mockup exactly)
    // Open book: two pages spreading left and right, spine in center
    // Small leaf/sprout growing from the top of the spine

    private var bookWithSproutIcon: some View {
        Canvas { context, size in
            let color = UIColor(theme.accent)
            let cx = size.width / 2
            let cy = size.height / 2

            // Book pages (two curves spreading outward)
            let bookPath = Path { p in
                // Left page
                p.move(to: CGPoint(x: cx, y: cy + 8))
                p.addQuadCurve(
                    to: CGPoint(x: cx - 22, y: cy - 12),
                    control: CGPoint(x: cx - 4, y: cy - 6)
                )
                p.addLine(to: CGPoint(x: cx - 22, y: cy + 14))
                p.addQuadCurve(
                    to: CGPoint(x: cx, y: cy + 22),
                    control: CGPoint(x: cx - 4, y: cy + 18)
                )

                // Right page
                p.move(to: CGPoint(x: cx, y: cy + 8))
                p.addQuadCurve(
                    to: CGPoint(x: cx + 22, y: cy - 12),
                    control: CGPoint(x: cx + 4, y: cy - 6)
                )
                p.addLine(to: CGPoint(x: cx + 22, y: cy + 14))
                p.addQuadCurve(
                    to: CGPoint(x: cx, y: cy + 22),
                    control: CGPoint(x: cx + 4, y: cy + 18)
                )
            }
            context.stroke(bookPath, with: .color(Color(uiColor: color)), lineWidth: 1.8)

            // Sprout/leaf from spine top
            let sproutPath = Path { p in
                // Stem
                p.move(to: CGPoint(x: cx, y: cy + 4))
                p.addLine(to: CGPoint(x: cx, y: cy - 12))

                // Left leaf
                p.move(to: CGPoint(x: cx, y: cy - 8))
                p.addQuadCurve(
                    to: CGPoint(x: cx - 8, y: cy - 18),
                    control: CGPoint(x: cx - 10, y: cy - 10)
                )

                // Right leaf
                p.move(to: CGPoint(x: cx, y: cy - 10))
                p.addQuadCurve(
                    to: CGPoint(x: cx + 7, y: cy - 20),
                    control: CGPoint(x: cx + 9, y: cy - 12)
                )
            }
            context.stroke(sproutPath, with: .color(Color(uiColor: color)), lineWidth: 1.5)
        }
        .frame(width: 60, height: 60)
    }
}

#Preview {
    SplashScreenView { }
}
