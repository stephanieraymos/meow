import SwiftUI

/// The syncable slice of progress (device settings like theme/palette stay local).
struct ProgressSnapshot: Codable {
    var levelStars: [Int: Int]
    var levelBestTimes: [Int: Double]
    var dailyStreak: Int
    var dailyBestStreak: Int
    var lastDailyKey: String?
    var dailySolved: [String: Bool]
    var timeAttackBest: [Int: Double]
    var totalWins: Int
    var totalGames: Int
    var totalScore: Int
}

/// Local, persisted player state: campaign progress, daily streak, stats, and
/// settings. Saved to UserDefaults as JSON, and (if a player identity is chosen)
/// mirrored to Supabase so progress survives reinstalls and syncs across devices.
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
        var totalScore: Int = 0
        var catStyleID: String = "classic"
        var hapticsOn: Bool = true
        var soundOn: Bool = true
        var autoMarkOn: Bool = true
        var tutorialSeen: Bool = false
        var remindersOn: Bool = false
        var appearance: String = "dark"
        var paletteID: String = "classic"

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
            totalScore = v(.totalScore, 0)
            catStyleID = v(.catStyleID, "classic")
            hapticsOn = v(.hapticsOn, true)
            soundOn = v(.soundOn, true)
            autoMarkOn = v(.autoMarkOn, true)
            tutorialSeen = v(.tutorialSeen, false)
            remindersOn = v(.remindersOn, false)
            appearance = v(.appearance, "dark")
            paletteID = v(.paletteID, "classic")
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
    var totalScore: Int { data.totalScore }

    func recordGame(won: Bool) {
        data.totalGames += 1
        if won { data.totalWins += 1 }
    }

    /// Points for a solo win: bigger boards, cleaner runs, and faster solves all
    /// score higher. Returns the points earned (also added to the total).
    @discardableResult
    func awardScore(size: Int, stars: Int, seconds: Double, heartsLeft: Int) -> Int {
        let base = size * 20                    // 120 / 160 / 200
        let star = stars * 60                   // up to 180
        let hearts = heartsLeft * 40            // up to 120
        let speed = max(0, 200 - Int(seconds))  // faster = more, up to 200
        let earned = base + star + hearts + speed
        data.totalScore += earned
        return earned
    }

    // MARK: - Settings

    var catStyleID: String {
        get { data.catStyleID }
        set { data.catStyleID = newValue }
    }
    var catStyle: CatStyle { CatStyles.style(data.catStyleID) }

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
    var remindersOn: Bool {
        get { data.remindersOn }
        set { data.remindersOn = newValue }
    }
    var appearance: Appearance {
        get { Appearance(rawValue: data.appearance) ?? .dark }
        set { data.appearance = newValue.rawValue }
    }
    var palette: MeowPalette {
        get { MeowPalettes.palette(data.paletteID) }
        set { data.paletteID = newValue.id }
    }
    var paletteID: String {
        get { data.paletteID }
        set { data.paletteID = newValue }
    }

    // MARK: - Identity & cloud sync

    /// The player this device is signed in as (chosen in Settings / the race
    /// lobby). Device-local, shared with the race picker via these UserDefaults
    /// keys. When set, progress mirrors to Supabase.
    var playerID: String? {
        let s = UserDefaults.standard.string(forKey: "meow_player_id")
        return (s?.isEmpty ?? true) ? nil : s
    }
    var playerName: String {
        UserDefaults.standard.string(forKey: "meow_player_name") ?? ""
    }

    func snapshot() -> ProgressSnapshot {
        ProgressSnapshot(
            levelStars: data.levelStars, levelBestTimes: data.levelBestTimes,
            dailyStreak: data.dailyStreak, dailyBestStreak: data.dailyBestStreak,
            lastDailyKey: data.lastDailyKey, dailySolved: data.dailySolved,
            timeAttackBest: data.timeAttackBest, totalWins: data.totalWins,
            totalGames: data.totalGames, totalScore: data.totalScore)
    }

    /// Merge cloud progress in, keeping the best of each field (never regresses).
    func merge(_ r: ProgressSnapshot) {
        var d = data
        for (lvl, s) in r.levelStars { d.levelStars[lvl] = max(d.levelStars[lvl] ?? 0, s) }
        for (lvl, t) in r.levelBestTimes { d.levelBestTimes[lvl] = min(d.levelBestTimes[lvl] ?? .greatestFiniteMagnitude, t) }
        for (sz, t) in r.timeAttackBest { d.timeAttackBest[sz] = min(d.timeAttackBest[sz] ?? .greatestFiniteMagnitude, t) }
        for (k, solved) in r.dailySolved { d.dailySolved[k] = (d.dailySolved[k] ?? false) || solved }
        d.dailyStreak = max(d.dailyStreak, r.dailyStreak)
        d.dailyBestStreak = max(d.dailyBestStreak, r.dailyBestStreak)
        if let rk = r.lastDailyKey, rk > (d.lastDailyKey ?? "") { d.lastDailyKey = rk }
        d.totalWins = max(d.totalWins, r.totalWins)
        d.totalGames = max(d.totalGames, r.totalGames)
        d.totalScore = max(d.totalScore, r.totalScore)
        data = d
    }

    /// Pull cloud progress, merge, then push the merged result. No-op without an
    /// identity. Safe to call often.
    func sync() async {
        guard let pid = playerID else { return }
        if let remote = try? await MeowAPI.fetchProgress(playerId: pid) { merge(remote) }
        try? await MeowAPI.pushProgress(playerId: pid, snapshot: snapshot())
    }

    func setIdentity(id: String, name: String) {
        UserDefaults.standard.set(id, forKey: "meow_player_id")
        UserDefaults.standard.set(name, forKey: "meow_player_name")
        objectWillChange.send()
        Task { await sync() }
    }
}
