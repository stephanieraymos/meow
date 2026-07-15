import UIKit

/// Lightweight haptic feedback, gated by the player's setting. No-ops on devices
/// without a Taptic Engine (and in the Simulator).
enum Haptics {
    /// Kept in sync with `PlayerProfile.hapticsOn`.
    static var enabled = true

    static func light() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func place() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
