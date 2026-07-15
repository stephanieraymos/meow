import GameKit
import SwiftUI

/// Game Center integration: authentication, fastest-time leaderboards, and
/// achievements. Submissions no-op gracefully until the matching leaderboards /
/// achievements are created in App Store Connect, so this is safe to ship now.
@MainActor
final class GameCenter: ObservableObject {
    static let shared = GameCenter()

    @Published var authenticated = false

    enum Leaderboard {
        static func time(size: Int) -> String { "meow.time.\(size)" }
        static let daily = "meow.daily.time"
    }
    enum Achievement {
        static let firstWin = "meow.win.first"
        static let streak7 = "meow.streak.7"
        static let level50 = "meow.level.50"
        static let flawless = "meow.flawless"
    }

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            if let viewController { Self.present(viewController) }
            self?.authenticated = GKLocalPlayer.local.isAuthenticated
        }
    }

    /// Submit a solve time (stored as centiseconds so faster = lower score).
    func submitTime(_ seconds: Double, leaderboardID: String) {
        guard authenticated else { return }
        let score = max(0, Int(seconds * 100))
        Task {
            try? await GKLeaderboard.submitScore(
                score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [leaderboardID])
        }
    }

    func report(_ achievementID: String, percent: Double = 100) {
        guard authenticated else { return }
        let achievement = GKAchievement(identifier: achievementID)
        achievement.percentComplete = percent
        achievement.showsCompletionBanner = true
        GKAchievement.report([achievement])
    }

    static func present(_ vc: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(vc, animated: true)
    }
}

/// The native Game Center dashboard (leaderboards + achievements).
struct GameCenterDashboard: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> GKGameCenterViewController {
        let vc = GKGameCenterViewController(state: .dashboard)
        vc.gameCenterDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: GKGameCenterViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, GKGameCenterControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func gameCenterViewControllerDidFinish(_ gc: GKGameCenterViewController) { dismiss() }
    }
}
