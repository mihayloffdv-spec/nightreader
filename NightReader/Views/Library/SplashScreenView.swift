import SwiftUI

struct SplashScreenView: View {
    @State private var opacity: Double = 0
    @State private var isFinished = false

    var onFinished: () -> Void

    var body: some View {
        ZStack {
            NightTheme.background
                .ignoresSafeArea()

            // Van Gogh "Starry Night" splash image
            Image("SplashArt")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.6)) {
                opacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeOut(duration: 0.4)) {
                    isFinished = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onFinished()
                }
            }
        }
        .opacity(isFinished ? 0 : 1)
    }
}

#Preview {
    SplashScreenView { }
}
