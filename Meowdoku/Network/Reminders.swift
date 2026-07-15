import UserNotifications

/// Local daily-puzzle reminders — no server or push certificates needed.
///
/// Schedules a single one-shot notification for the next 7pm, and reschedules it
/// (on app foreground and after the daily is solved) so it never nags a player
/// who already played today, and always nudges to protect a streak.
@MainActor
enum Reminders {
    private static let id = "meow.daily.reminder"
    private static let hour = 19   // 7pm local

    /// Ask permission and turn reminders on. Returns whether it was granted.
    @discardableResult
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        PlayerProfile.shared.remindersOn = granted
        if granted { schedule() }
        return granted
    }

    static func disable() {
        PlayerProfile.shared.remindersOn = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Reschedule the next reminder if reminders are on. Safe to call often.
    static func refresh() {
        guard PlayerProfile.shared.remindersOn else { return }
        schedule()
    }

    private static func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let now = Date()
        let cal = Calendar.current
        var target = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        // If 7pm already passed today, or today's puzzle is done, aim for tomorrow.
        if target <= now || PlayerProfile.shared.todaySolved {
            target = cal.date(byAdding: .day, value: 1, to: target) ?? target
        }

        let content = UNMutableNotificationContent()
        content.title = "Meowdoku 🐱"
        let streak = PlayerProfile.shared.dailyStreak
        content.body = streak > 0
            ? "Keep your \(streak)-day streak alive — today's puzzle is ready!"
            : "Today's Meowdoku puzzle is ready. Can you solve it?"
        content.sound = .default

        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: target)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
