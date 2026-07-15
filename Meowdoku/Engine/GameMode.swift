import Foundation

/// Configuration for a single solo game. Race mode uses `RaceStore` instead.
struct GameMode: Equatable {
    enum Kind: Equatable {
        case daily(String)      // date key
        case level(Int)         // campaign level index
        case timeAttack(Int)    // grid size
        case freeplay(Int)      // grid size
    }

    var kind: Kind
    var size: Int
    var seed: UInt64
    var allowedMistakes: Int
    var hintsAllowed: Bool
    var showsTimer: Bool
    var title: String
    var subtitle: String

    // MARK: - Builders

    static func daily(key: String) -> GameMode {
        GameMode(kind: .daily(key), size: DailyPuzzle.size, seed: DailyPuzzle.seed(for: key),
                 allowedMistakes: 3, hintsAllowed: true, showsTimer: true,
                 title: "Daily Puzzle", subtitle: key)
    }

    static func level(_ index: Int) -> GameMode {
        let size = LevelCatalog.size(for: index)
        return GameMode(kind: .level(index), size: size, seed: LevelCatalog.seed(for: index),
                        allowedMistakes: 3, hintsAllowed: true, showsTimer: true,
                        title: "Level \(index)", subtitle: "\(size)×\(size)")
    }

    static func timeAttack(size: Int, seed: UInt64) -> GameMode {
        GameMode(kind: .timeAttack(size), size: size, seed: seed,
                 allowedMistakes: 3, hintsAllowed: false, showsTimer: true,
                 title: "Time Attack", subtitle: "\(size)×\(size) · beat the clock")
    }

    static func freeplay(difficulty: Difficulty, seed: UInt64) -> GameMode {
        GameMode(kind: .freeplay(difficulty.size), size: difficulty.size, seed: seed,
                 allowedMistakes: 3, hintsAllowed: true, showsTimer: false,
                 title: difficulty.title, subtitle: "Practice · \(difficulty.subtitle)")
    }
}
