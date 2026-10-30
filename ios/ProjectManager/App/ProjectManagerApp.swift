import SwiftUI

@main
struct ProjectManagerApp: App {
    @StateObject private var theme = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            BentoDashboardView()
                .preferredColorScheme(theme.preferredColorScheme)
        }
    }
}
