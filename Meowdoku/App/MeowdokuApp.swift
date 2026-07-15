import SwiftUI

@main
struct MeowdokuApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        GameCenter.shared.authenticate()
        SoundPlayer.shared.preload()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Reminders.refresh() }
        }
    }
}
