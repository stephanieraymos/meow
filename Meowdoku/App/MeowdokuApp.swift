import SwiftUI

@main
struct MeowdokuApp: App {
    init() {
        GameCenter.shared.authenticate()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
        }
    }
}
