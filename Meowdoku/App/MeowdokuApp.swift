import SwiftUI

@main
struct MeowdokuApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var profile = PlayerProfile.shared

    init() {
        GameCenter.shared.authenticate()
        SoundPlayer.shared.preload()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(profile.appearance.colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Reminders.refresh()
                Task { await PlayerProfile.shared.sync() }
            }
        }
    }
}
