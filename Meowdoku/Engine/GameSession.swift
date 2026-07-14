import SwiftUI

/// What a player has done to a cell.
enum CellMark: Equatable {
    case empty
    case cat      // a placed cat
    case blocked  // an "X" note: player has ruled this cell out
}

/// The live, mutable state of one player's board. Drives both Solo and Race.
///
/// High-stakes rule: placing a cat on any cell that is not part of the unique
/// solution is a mistake. With `allowedMistakes == 1` (the default), the first
/// mistake ends the game immediately — no hints, no second chances.
@MainActor
final class GameSession: ObservableObject {
    let board: MeowBoard

    @Published private(set) var marks: [[CellMark]]
    @Published private(set) var correctCats: Int = 0
    @Published private(set) var mistakes: Int = 0
    @Published private(set) var isWon = false
    @Published private(set) var isLost = false
    /// The cell that triggered the loss, for a red flash on the board.
    @Published private(set) var faultCell: Cell? = nil

    let allowedMistakes: Int

    struct Cell: Equatable { let row: Int; let col: Int }

    init(board: MeowBoard, allowedMistakes: Int = 1) {
        self.board = board
        self.allowedMistakes = allowedMistakes
        self.marks = Array(
            repeating: Array(repeating: .empty, count: board.size),
            count: board.size
        )
    }

    var size: Int { board.size }
    var isOver: Bool { isWon || isLost }
    var progress: Int { correctCats }

    func mark(row: Int, col: Int) -> CellMark { marks[row][col] }

    // MARK: - Interactions

    /// Place or remove a cat. Returns the outcome so callers (e.g. the race layer)
    /// can react — report progress, declare a loss, etc.
    enum PlaceResult { case placedCorrect, removed, mistake, ignored }

    @discardableResult
    func placeCat(row: Int, col: Int) -> PlaceResult {
        guard !isOver else { return .ignored }

        switch marks[row][col] {
        case .cat:
            // Remove — always allowed, no penalty.
            marks[row][col] = .empty
            if board.isSolutionCell(row: row, col: col) { correctCats -= 1 }
            return .removed

        case .empty, .blocked:
            if board.isSolutionCell(row: row, col: col) {
                marks[row][col] = .cat
                correctCats += 1
                if correctCats == board.size { isWon = true }
                return .placedCorrect
            } else {
                // Wrong placement — a mistake.
                marks[row][col] = .cat
                mistakes += 1
                faultCell = Cell(row: row, col: col)
                if mistakes >= allowedMistakes { isLost = true }
                return .mistake
            }
        }
    }

    /// Toggle an "X" note. Purely a personal aid — never affects win/loss.
    func toggleBlock(row: Int, col: Int) {
        guard !isOver else { return }
        switch marks[row][col] {
        case .empty:   marks[row][col] = .blocked
        case .blocked: marks[row][col] = .empty
        case .cat:
            marks[row][col] = .empty
            if board.isSolutionCell(row: row, col: col) { correctCats -= 1 }
        }
    }

    /// Force a loss (opponent solved first / forfeit).
    func forceLose() {
        guard !isOver else { return }
        isLost = true
    }
}
