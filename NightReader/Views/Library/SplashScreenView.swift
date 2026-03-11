import SwiftUI

struct SplashScreenView: View {
    @State private var moonOpacity: Double = 0
    @State private var moonScale: Double = 0.8
    @State private var starOpacity: Double = 0
    @State private var starOffset: CGFloat = 8
    @State private var titleOpacity: Double = 0
    @State private var isFinished = false

    var onFinished: () -> Void

    var body: some View {
        ZStack {
            NightTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Moon + Star icon
                ZStack {
                    // Moon crescent
                    MoonShape()
                        .fill(NightTheme.moonGray)
                        .frame(width: 72, height: 72)

                    // Small star above the moon
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(NightTheme.starColor)
                        .offset(x: 12, y: -42)
                        .opacity(starOpacity)
                        .offset(y: starOffset)
                }
                .opacity(moonOpacity)
                .scaleEffect(moonScale)

                Spacer().frame(height: 24)

                // App name
                Text("NightReader")
                    .font(.system(size: 26, weight: .light, design: .serif))
                    .foregroundStyle(NightTheme.primaryText)
                    .opacity(titleOpacity)

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                moonOpacity = 1
                moonScale = 1
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                starOpacity = 1
                starOffset = 0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                titleOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeIn(duration: 0.3)) {
                    isFinished = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onFinished()
                }
            }
        }
        .opacity(isFinished ? 0 : 1)
    }
}

// MARK: - Crescent moon shape matching the Canva design

struct MoonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        // Full circle
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)

        // Cut out a circle offset to the right to create crescent
        let cutoutCenter = CGPoint(x: center.x + radius * 0.45, y: center.y - radius * 0.1)
        let cutoutRadius = radius * 0.75

        // Use even-odd fill to subtract
        path.addArc(center: cutoutCenter, radius: cutoutRadius,
                    startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)

        return path
    }
}

// Use even-odd rule for the crescent cutout
extension MoonShape {
    // SwiftUI Shape uses even-odd by default with addArc subpaths
}

#Preview {
    SplashScreenView { }
}
