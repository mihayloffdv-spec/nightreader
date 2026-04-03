import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    private var theme: Theme { AppSettings.shared.currentTheme }

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem {
                    Image(systemName: "book.fill")
                    Text("Library")
                }
                .tag(0)

            NotebookPlaceholderView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Explore")
                }
                .tag(1)

            NotebookPlaceholderView()
                .tabItem {
                    Image(systemName: "square.and.pencil")
                    Text("Journal")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Image(systemName: "person")
                    Text("Profile")
                }
                .tag(3)
        }
        .tint(Color(hex: "#CC704B"))
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
