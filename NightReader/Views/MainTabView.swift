import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    private var theme: Theme { AppSettings.shared.currentTheme }

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem {
                    Image(systemName: "books.vertical")
                    Text("Library")
                }
                .tag(0)

            // Notebook placeholder — will be replaced with full NotebookView
            NotebookPlaceholderView()
                .tabItem {
                    Image(systemName: "bookmark.fill")
                    Text("Notebook")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .tag(2)
        }
        .tint(theme.accent)
        .onAppear {
            let tabAppearance = UITabBarAppearance()
            tabAppearance.configureWithTransparentBackground()
            tabAppearance.backgroundColor = UIColor(theme.background).withAlphaComponent(0.95)
            UITabBar.appearance().standardAppearance = tabAppearance
            UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        }
    }
}

// MARK: - Notebook Placeholder

struct NotebookPlaceholderView: View {
    private var theme: Theme { AppSettings.shared.currentTheme }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "bookmark")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundStyle(theme.surface)

                Text("Notebook")
                    .font(theme.headlineFont(size: 22))
                    .foregroundStyle(theme.textPrimary)

                Text("Your highlights and annotations will appear here")
                    .font(theme.captionFont(size: 15))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
        }
    }
}
