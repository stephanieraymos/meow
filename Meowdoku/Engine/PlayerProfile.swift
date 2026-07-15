import SwiftUI

/// Local, persisted player state: campaign progress, daily streak, stats, and
/// settings. Saved to UserDefaults as JSON.
@MainActor
final class PlayerProfile: ObservableObject {
    static let shared = PlayerProfile()

    private struct Data: Codable {
        var levelStars: [Int: Int] = [:]          // level → stars (0–3)
        var levelBestTimes: [Int: Double] = [:]   // level → seconds
        var dailyStreak: Int = 0
        var dailyBestStreak: Int = 0
        var lastDailyKey: String? = nil
        var dailySolved: [String: Bool] = [:]     // date key → solved
        var timeAttackBest: [Int: Double] = [:]   // size → best seconds
        var totalWins: Int = 0
        var totalGames: Int = 0
        var catStyleID: String = "classic"
        var hapticsOn: Bool = true
        var soundOn: Bool = true
        var autoMarkOn: Bool = true
        var tutorialSeen: Bool = false

        init() {}

        /// Resilient decode: every field falls back to its default when absent, so
        /// adding new fields in a future version never wipes existing progress.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
                (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil ?? fallback
            }
            levelStars = v(.levelStars, [:])
            levelBestTimes = v(.levelBestTimes, [:])
            dailyStreak = v(.dailyStreak, 0)
            dailyBestStreak = v(.dailyBestStreak, 0)
            lastDailyKey = (try? c.decodeIfPresent(String.self, forKey: .lastDailyKey)) ?? nil
            dailySolved = v(.dailySolved, [:])
            timeAttackBest = v(.timeAttackBest, [:])
            totalWins = v(.totalWins, 0)
            totalGames = v(.totalGames, 0)
            catStyleID = v(.catStyleID, "classic")
            hapticsOn = v(.hapticsOn, true)
            soundOn = v(.soundOn, true)
            autoMarkOn = v(.autoMarkOn, true)
            tutorialSeen = v(.tutorialSeen, false)
        }
    }

    @Published private var data: Data { didSet { persist(); Haptics.enabled = data.hapticsOn } }

    private let key = "meow_profile_v1"

    private init() {
        if let raw = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Data.self, from: raw) {
            data = decoded
        } else {
            data = Data()
        }
        Haptics.enabled = data.hapticsOn
    }

    private func persist() {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: key)
        }
    }

    // MARK: - Campaign

    func stars(forLevel level: Int) -> Int { data.levelStars[level] ?? 0 }
    func isCompleted(level: Int) -> Bool { data.levelStars[level] != nil }
    func bestTime(forLevel level: Int) -> Double? { data.levelBestTimes[level] }

    /// Highest unlocked level (level 1 always unlocked; each win unlocks the next).
    var highestUnlocked: Int {
        var n = 1
        while data.levelStars[n] != nil && n < LevelCatalog.totalLevels { n += 1 }
        return n
    }

    var levelsCompleted: Int { data.levelStars.count }
    var totalStars: Int { data.levelStars.values.reduce(0, +) }

    func completeLevel(_ level: Int, stars: Int, time: Double) {
        data.levelStars[level] = max(stars, data.levelStars[level] ?? 0)
        if let prev = data.levelBestTimes[level] { data.levelBestTimes[level] = min(prev, time) }
        else { data.levelBestTimes[level] = time }
    }

    // MARK: - Daily

    var dailyStreak: Int { data.dailyStreak }
    var dailyBestStreak: Int { data.dailyBestStreak }
    func daily(solvedFor key: String) -> Bool? { data.dailySolved[key] }
    var todaySolved: Bool { data.dailySolved[DailyPuzzle.dateKey()] == true }

    func recordDaily(key: String, solved: Bool) {
        let already = data.dailySolved[key]
        data.dailySolved[key] = (already == true) || solved
        guard solved, already != true else { return }

        // Extend the streak if yesterday's daily was solved; otherwise reset to 1.
        let yesterday = DailyPuzzle.dateKey(Date().addingTimeInterval(-86_400))
        if data.lastDailyKey == yesterday || data.lastDailyKey == key {
            data.dailyStreak += (data.lastDailyKey == key ? 0 : 1)
        } else {
            data.dailyStreak = 1
        }
        data.lastDailyKey = key
        data.dailyBestStreak = max(data.dailyBestStreak, data.dailyStreak)
    }

    // MARK: - Time attack & stats

    func timeAttackBest(size: Int) -> Double? { data.timeAttackBest[size] }
    func recordTimeAttack(size: Int, time: Double) {
        if let prev = data.timeAttackBest[size] { data.timeAttackBest[size] = min(prev, time) }
        else { data.timeAttackBest[size] = time }
    }

    var totalWins: Int { data.totalWins }
    var totalGames: Int { data.totalGames }
    func recordGame(won: Bool) {
        data.totalGames += 1
        if won { data.totalWins += 1 }
    }

    // MARK: - Settings

    var catStyleID: String {
        get { data.catStyleID }
        set { data.catStyleID = newValue }
    }
    var catGlyph: String { CatStyles.glyph(for: data.catStyleID) }

    var hapticsOn: Bool {
        get { data.hapticsOn }
        set { data.hapticsOn = newValue }
    }
    var soundOn: Bool {
        get { data.soundOn }
        set { data.soundOn = newValue }
    }
    var autoMarkOn: Bool {
        get { data.autoMarkOn }
        set { data.autoMarkOn = newValue }
    }
    var tutorialSeen: Bool {
        get { data.tutorialSeen }
        set { data.tutorialSeen = newValue }
    }
}
