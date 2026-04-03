import SwiftUI
import SwiftData

@main
struct NightReaderApp: App {
    @State private var showSplash = true

    init() {
        let theme = AppSettings.shared.currentTheme

        // Navigation bar
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: theme.accentUIColor,
            .font: theme.headlineUIFont(size: 34)
        ]
        navAppearance.titleTextAttributes = [
            .foregroundColor: theme.accentUIColor
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance

        // Tab bar
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundColor = theme.backgroundUIColor.withAlphaComponent(0.95)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()
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
