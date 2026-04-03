import SwiftUI
import SwiftData

@main
struct NightReaderApp: App {
    @State private var showSplash = true

    init() {
        let theme = AppSettings.shared.currentTheme
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.largeTitleTextAttributes = [
            .foregroundColor: theme.accentUIColor,
            .font: theme.headlineUIFont(size: 34)
        ]
        appearance.titleTextAttributes = [
            .foregroundColor: theme.accentUIColor
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

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
