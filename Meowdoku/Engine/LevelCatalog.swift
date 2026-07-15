import Foundation

/// The solo campaign: a long, deterministic ladder of puzzles that ramps in size.
/// Each level maps to a fixed `(size, seed)`, so a given level is always the same
/// board and progress is meaningful.
enum LevelCatalog {
    static let totalLevels = 240

    /// Size bands: eased in (6×6), the bulk at 8×8, a hard tail at 10×10.
    static func size(for level: Int) -> Int {
        switch level {
        case ..<60:  return 6
        case ..<160: return 8
        default:     return 10
        }
    }

    static func difficulty(for level: Int) -> Difficulty {
        switch size(for: level) {
        case 6:  return .easy
        case 8:  return .normal
        default: return .hard
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
