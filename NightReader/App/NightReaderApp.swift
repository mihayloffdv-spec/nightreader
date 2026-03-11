import SwiftUI
import SwiftData

@main
struct NightReaderApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                LibraryView()
                    .preferredColorScheme(.dark)

                if showSplash {
                    SplashScreenView {
                        showSplash = false
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSplash)
        }
        .modelContainer(for: Book.self)
    }
}
