import SwiftUI

struct SplashScreenView: View {
    private static let displayDuration: Double = 4.2
    private static let fadeOutDuration: Double = 0.4

    @State private var opacity: Double = 0
    @State private var isFinished = false

    var onFinished: () -> Void

    var body: some View {
        GeometryReader { geo in
            Image("SplashArt")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .opacity(opacity)
        }
        .ignoresSafeArea()
        .background(Color(hex: "#01081E"))
        .task {
            withAnimation(.easeIn(duration: 0.6)) {
                opacity = 1
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
}

#Preview {
    SplashScreenView { }
}
