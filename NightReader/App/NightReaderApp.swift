import SwiftUI
import SwiftData

@main
struct NightReaderApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: Book.self)
    }
}
