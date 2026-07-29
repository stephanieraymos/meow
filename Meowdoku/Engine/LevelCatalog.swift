import Foundation

/// The solo campaign: a long, deterministic ladder of puzzles that ramps in size.
/// Each level maps to a fixed `(size, seed)`, so a given level is always the same
/// board and progress is meaningful.
enum LevelCatalog {
    static let totalLevels = 240

    /// A small deterministic hash, used to vary size without correlating to level.
    private static func hash(_ x: UInt64) -> UInt64 {
        var s = x &+ 0x9E3779B97F4A7C15
        s = (s ^ (s >> 30)) &* 0xBF58476D1CE4E5B9
        s = (s ^ (s >> 27)) &* 0x94D049BB133111EB
        return s ^ (s >> 31)
    }

    /// Grid size for a level. **Deliberately decorrelated from difficulty** — the
    /// original Meowdoku mixes big and small boards throughout, and size alone
    /// doesn't make a puzzle harder. Consecutive levels vary a lot (5×5 → 10×10),
    /// with the first few eased in so a new player isn't dropped onto a 10×10.
    static func size(for level: Int) -> Int {
        if level <= 3 { return 5 }
        if level <= 6 { return 6 }
        let h = hash(UInt64(level) &* 2_654_435_761)
        // Onboarding (≤18): small but varied, so the first hour stays gentle while
        // still changing box count. After that: full variation, decorrelated from
        // difficulty (a big board can be easy, a small one brutal — the generator's
        // difficulty match decides hardness, not the size).
        if level <= 18 {
            let pool = [5, 6, 6, 7, 7]
            return pool[Int(h % UInt64(pool.count))]
        }
        let pool = [5, 6, 6, 7, 7, 8, 8, 8, 9, 9, 10, 10]
        return pool[Int(h % UInt64(pool.count))]
    }

    /// Target *logical* difficulty (0…1) for a level, fed to the generator's
    /// difficulty-matching. Rises monotonically with level — independent of grid
    /// size — so the campaign genuinely gets harder as it goes, whether the board
    /// is big or small. Eased so early levels stay gentle and the top plateaus hard.
    static func difficultyTarget(for level: Int) -> Double {
        let span = 170.0
        let t = min(1.0, max(0.0, Double(level - 1) / span))
        let eased = t * t * (3 - 2 * t)          // smoothstep
        return 0.12 + 0.83 * eased               // 0.12 (gentle) → 0.95 (expert)
    }

    /// Human-readable difficulty tier for a level, derived from the target (for
    /// level-select badges). Not tied to grid size.
    static func difficultyLabel(for level: Int) -> String {
        switch difficultyTarget(for: level) {
        case ..<0.30: return "Easy"
        case ..<0.55: return "Medium"
        case ..<0.78: return "Hard"
        default:      return "Expert"
        }
    }

    /// Deterministic, well-spread seed for a level.
    static func seed(for level: Int) -> UInt64 {
        var s = UInt64(bitPattern: Int64(level)) &+ 1
        s = (s &* 0x9E3779B97F4A7C15) ^ 0xD1B54A32D192ED03
        s ^= s >> 31
        return s | 1
    }

    /// Stars for a completed level: 3 = flawless, 2 = one slip, 1 = squeaked by.
    /// Using a hint caps you at 2 stars.
    static func stars(mistakes: Int, hintsUsed: Int) -> Int {
        if mistakes == 0 && hintsUsed == 0 { return 3 }
        if mistakes <= 1 { return 2 }
        return 1
    }
}

/// The daily puzzle: one shared board per calendar day, derived from the date.
enum DailyPuzzle {
    static let size = 8

    static func dateKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Seed derived from the yyyy-MM-dd string so everyone gets the same daily.
    static func seed(for key: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603 // FNV-1a offset
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash | 1
    }
}
