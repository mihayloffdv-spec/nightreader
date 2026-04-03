import SwiftUI

// MARK: - Splash Screen (pixel-perfect from HTML mockup)
//
// Translated from Stitch HTML source. Every color, size, and position
// matches the original CSS/SVG exactly.

struct SplashScreenView: View {
    private static let displayDuration: Double = 3.5
    private static let fadeOutDuration: Double = 0.4

    @State private var contentOpacity: Double = 0
    @State private var isFinished = false

    var onFinished: () -> Void

    // Exact colors from the HTML mockup
    private let bgColor = Color(hex: "#0B120B")
    private let accentColor = Color(hex: "#CC704B")
    private let subtitleColor = Color(hex: "#78716C") // stone-500
    private let quoteColor = Color(hex: "#C5C7C1")    // on-surface-variant
    private let mistGreen = Color(hex: "#061404")      // tertiary-container
    private let mistRed = Color(hex: "#250700")        // primary-container

    var body: some View {
        ZStack {
            // Background
            bgColor.ignoresSafeArea()

            // Floating decorative blurs (atmospheric mist)
            Circle()
                .fill(mistGreen.opacity(0.2))
                .frame(width: 384, height: 384)
                .blur(radius: 100)
                .offset(x: -120, y: 300)

            Circle()
                .fill(mistRed.opacity(0.1))
                .frame(width: 320, height: 320)
                .blur(radius: 100)
                .offset(x: 120, y: -300)

            // Vignette gradient (bottom darkening)
            LinearGradient(
                colors: [.clear, .clear, Color(hex: "#091009").opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Central content
            VStack(spacing: 0) {
                Spacer()

                // Logo + branding cluster
                VStack(spacing: 32) {
                    // Logo with ambient glow
                    ZStack {
                        // Ambient glow behind logo
                        Circle()
                            .fill(accentColor)
                            .frame(width: 192, height: 192) // scale-150 of 128
                            .blur(radius: 48) // blur-3xl
                            .opacity(0.1)

                        // SVG logo: open book with sprout
                        bookLogo
                            .frame(width: 128, height: 128)
                    }

                    // Text cluster
                    VStack(spacing: 8) {
                        // App name: Plus Jakarta Sans bold, text-4xl (36px), tracking-tighter
                        Text("NightReader")
                            .font(.custom("Onest", size: 36).bold())
                            .tracking(-0.8) // tracking-tighter
                            .foregroundStyle(accentColor)

                        // Subtitle: uppercase, tracking 0.3em, 10px, stone-500, opacity 80%
                        Text("The Subterranean Conservatory")
                            .font(.custom("Onest", size: 10))
                            .textCase(.uppercase)
                            .tracking(3) // 0.3em at 10px
                            .foregroundStyle(subtitleColor.opacity(0.8))
                    }
                }

                Spacer()

                // Bottom footer
                VStack(spacing: 16) {
                    // Dot: 4x4 accent, opacity 40%
                    Circle()
                        .fill(accentColor.opacity(0.4))
                        .frame(width: 4, height: 4)

                    // Quote: Noto Serif italic, 14px, on-surface-variant at 40%
                    Text("Cultivating wisdom in the quiet hours.")
                        .font(.custom("Noto Serif", size: 14))
                        .italic()
                        .foregroundStyle(quoteColor.opacity(0.4))
                }
                .padding(.bottom, 64) // bottom-16 = 4rem = 64px
            }
            .opacity(contentOpacity)
        }
        .task {
            withAnimation(.easeIn(duration: 0.8)) {
                contentOpacity = 1
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

    // MARK: - Book Logo (exact SVG path translation)
    //
    // Original SVG viewBox="0 0 100 100", rendered at 128x128
    // stroke="#CC704B" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill="none"

    private var bookLogo: some View {
        Canvas { context, size in
            let scale = size.width / 100.0 // viewBox 100x100 → actual size

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * scale, y: y * scale)
            }

            let strokeColor = Color(hex: "#CC704B")

            // Book left wing: M50,85 C40,85 20,80 20,60 V30 C20,30 40,35 50,35
            var leftWing = Path()
            leftWing.move(to: p(50, 85))
            leftWing.addCurve(to: p(20, 60), control1: p(40, 85), control2: p(20, 80))
            leftWing.addLine(to: p(20, 30))
            leftWing.addCurve(to: p(50, 35), control1: p(20, 30), control2: p(40, 35))
            context.stroke(leftWing, with: .color(strokeColor),
                          style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round, lineJoin: .round))

            // Book right wing: M50,85 C60,85 80,80 80,60 V30 C80,30 60,35 50,35
            var rightWing = Path()
            rightWing.move(to: p(50, 85))
            rightWing.addCurve(to: p(80, 60), control1: p(60, 85), control2: p(80, 80))
            rightWing.addLine(to: p(80, 30))
            rightWing.addCurve(to: p(50, 35), control1: p(80, 30), control2: p(60, 35))
            context.stroke(rightWing, with: .color(strokeColor),
                          style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round, lineJoin: .round))

            // Spine: M50,35 V85 (opacity 0.5, stroke-width 1)
            var spine = Path()
            spine.move(to: p(50, 35))
            spine.addLine(to: p(50, 85))
            context.stroke(spine, with: .color(strokeColor.opacity(0.5)),
                          style: StrokeStyle(lineWidth: 1.0 * scale, lineCap: .round))

            // Sprout left: M50,35 C50,28 45,23 40,20 (stroke-width 2)
            var sproutLeft = Path()
            sproutLeft.move(to: p(50, 35))
            sproutLeft.addCurve(to: p(40, 20), control1: p(50, 28), control2: p(45, 23))
            context.stroke(sproutLeft, with: .color(strokeColor),
                          style: StrokeStyle(lineWidth: 2.0 * scale, lineCap: .round, lineJoin: .round))

            // Sprout right: M50,35 C50,25 55,20 60,15 (stroke-width 2)
            var sproutRight = Path()
            sproutRight.move(to: p(50, 35))
            sproutRight.addCurve(to: p(60, 15), control1: p(50, 25), control2: p(55, 20))
            context.stroke(sproutRight, with: .color(strokeColor),
                          style: StrokeStyle(lineWidth: 2.0 * scale, lineCap: .round, lineJoin: .round))

            // Sprout tip dot: circle at (60,15) r=1.5, filled
            let dotRect = CGRect(
                x: (60 - 1.5) * scale, y: (15 - 1.5) * scale,
                width: 3 * scale, height: 3 * scale
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(strokeColor))
        }
    }
}

#Preview {
    SplashScreenView { }
}
