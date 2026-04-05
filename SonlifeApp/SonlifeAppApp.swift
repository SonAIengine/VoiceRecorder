import SwiftUI

@main
struct SonlifeAppApp: App {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppTheme(rawValue: selectedTheme)?.colorScheme)
        }
    }
}
