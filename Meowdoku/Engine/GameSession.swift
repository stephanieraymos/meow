import SwiftUI

/// What a player has done to a cell.
enum CellMark: Equatable {
    case empty
    case cat      // a placed cat
    case blocked  // an "X" note: player has ruled this cell out
}

/// The live, mutable state of one player's board.
///
/// Solo modes give the player a small number of hearts: a wrong cat flashes red,
/// costs a heart, and is removed — the game ends only when hearts run out. The
/// race uses `allowedMistakes == 1`, so the first wrong cat ends it instantly and
/// stays on the board.
@MainActor
final class GameSession: ObservableObject {
    let board: MeowBoard

    @Published private(set) var marks: [[CellMark]]
    @Published private(set) var correctCats: Int = 0
    @Published private(set) var mistakes: Int = 0
    @Published private(set) var isWon = false
    @Published private(set) var isLost = false
    @Published private(set) var faultCell: Cell? = nil
    @Published private(set) var hintCell: Cell? = nil
    @Published private(set) var hintsUsed = 0
    /// Bumps whenever a cat is *correctly* placed, so views can trigger a pop.
    @Published private(set) var lastPlaced: Cell? = nil

    let allowedMistakes: Int
    /// When true, placing a correct cat auto-marks the cells it rules out.
    let autoMark: Bool
    let startedAt = Date()
    private(set) var finishedAt: Date?

    struct Cell: Equatable { let row: Int; let col: Int }
    private struct Move { let row: Int; let col: Int; let before: CellMark }
    /// Each user action pushes one group, so undo reverts a placement together
    /// with any auto-marks it triggered.
    private var undoStack: [[Move]] = []
    private var faultToken = 0

    init(board: MeowBoard, allowedMistakes: Int = 1, autoMark: Bool = false) {
        self.board = board
        self.allowedMistakes = allowedMistakes
        self.autoMark = autoMark
        self.marks = Array(
            repeating: Array(repeating: .empty, count: board.size),
            count: board.size
        )
    }

    var size: Int { board.size }
    var isOver: Bool { isWon || isLost }
    var progress: Int { correctCats }
    var heartsRemaining: Int { max(0, allowedMistakes - mistakes) }
    var canUndo: Bool { !isOver && !undoStack.isEmpty }
    var elapsed: TimeInterval { (finishedAt ?? Date()).timeIntervalSince(startedAt) }

    func mark(row: Int, col: Int) -> CellMark { marks[row][col] }

    // MARK: - Interactions

    enum PlaceResult { case placedCorrect, removed, mistake, ignored }

    /// Place or remove a cat (double-tap).
    @discardableResult
    func placeCat(row: Int, col: Int) -> PlaceResult {
        guard !isOver else { return .ignored }

        if marks[row][col] == .cat {
            commit([move(row, col)])
            marks[row][col] = .empty
            if board.isSolutionCell(row: row, col: col) { correctCats -= 1 }
            Haptics.light()
            return .removed
        }

        if board.isSolutionCell(row: row, col: col) {
            var group = [move(row, col)]
            marks[row][col] = .cat
            correctCats += 1
            lastPlaced = Cell(row: row, col: col)
            clearHint()
            if autoMark { group += applyAutoMarks(row: row, col: col) }
            commit(group)
            Haptics.place()
            if correctCats == board.size { win() }
            return .placedCorrect
        }

        // Wrong placement — a mistake.
        mistakes += 1
        marks[row][col] = .cat
        faultCell = Cell(row: row, col: col)
        Haptics.error()
        if mistakes >= allowedMistakes {
            lose()                // leave the offending cat on the board, flashed red
        } else {
            scheduleFaultClear(row: row, col: col)
        }
        return .mistake
    }

    /// Toggle an "X" note (single tap). On a cat, clears it.
    func toggleBlock(row: Int, col: Int) {
        guard !isOver else { return }
        switch marks[row][col] {
        case .empty:
            commit([move(row, col)]); marks[row][col] = .blocked; Haptics.light()
        case .blocked:
            commit([move(row, col)]); marks[row][col] = .empty; Haptics.light()
        case .cat:
            commit([move(row, col)])
            marks[row][col] = .empty
            if board.isSolutionCell(row: row, col: col) { correctCats -= 1 }
            Haptics.light()
        }
    }

    /// Paint an "X" while dragging — only marks empty cells (never toggles off,
    /// never disturbs cats), so a swipe reliably eliminates a run of cells.
    func paintBlock(row: Int, col: Int) {
        guard !isOver, marks[row][col] == .empty else { return }
        commit([move(row, col)])
        marks[row][col] = .blocked
    }

    func undo() {
        guard canUndo, let group = undoStack.popLast() else { return }
        for m in group.reversed() { marks[m.row][m.col] = m.before }
        recomputeCorrect()
        Haptics.light()
    }

    /// Reveal the most-constrained correct cat as a hint. Caps the star rating.
    @discardableResult
    func hint() -> Cell? {
        guard !isOver else { return nil }
        var best: (cell: Cell, freedom: Int)? = nil
        for r in 0..<size where marks[r][board.solution[r]] != .cat {
            let region = board.regionID(row: r, col: board.solution[r])
            var freedom = 0
            for rr in 0..<size {
                for cc in 0..<size where board.regionID(row: rr, col: cc) == region {
                    if marks[rr][cc] == .empty { freedom += 1 }
                }
            }
            if best == nil || freedom < best!.freedom {
                best = (Cell(row: r, col: board.solution[r]), freedom)
            }
        }
        guard let pick = best?.cell else { return nil }
        hintsUsed += 1
        hintCell = pick
        clearHintSoon(pick)
        return pick
    }

    /// Force a loss (opponent solved first / forfeit / time up).
    func forceLose() {
        guard !isOver else { return }
        lose()
    }

    // MARK: - Internals

    private func win() {
        finishedAt = Date()
        isWon = true
        Haptics.success()
    }

    private func lose() {
        finishedAt = Date()
        isLost = true
        Haptics.error()
    }

    /// Snapshot a cell's current mark for the undo group (call *before* mutating).
    private func move(_ row: Int, _ col: Int) -> Move {
        Move(row: row, col: col, before: marks[row][col])
    }

    private func commit(_ group: [Move]) {
        if !group.isEmpty { undoStack.append(group) }
    }

    /// Mark every empty cell a correct cat rules out: its row, column, region,
    /// and the 8 touching cells. Returns the moves so they join the undo group.
    private func applyAutoMarks(row: Int, col: Int) -> [Move] {
        var moves: [Move] = []
        func block(_ r: Int, _ c: Int) {
            guard r >= 0, r < size, c >= 0, c < size, marks[r][c] == .empty else { return }
            moves.append(move(r, c))
            marks[r][c] = .blocked
        }
        let region = board.regionID(row: row, col: col)
        for i in 0..<size {
            block(row, i)   // row
            block(i, col)   // column
        }
        for r in 0..<size {
            for c in 0..<size where board.regionID(row: r, col: c) == region { block(r, c) }
        }
        for dr in -1...1 { for dc in -1...1 { block(row + dr, col + dc) } }
        return moves
    }

    private func recomputeCorrect() {
        var n = 0
        for r in 0..<size where marks[r][board.solution[r]] == .cat { n += 1 }
        correctCats = n
    }

    private func scheduleFaultClear(row: Int, col: Int) {
        faultToken += 1
        let token = faultToken
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard let self, self.faultToken == token, !self.isOver else { return }
            if self.marks[row][col] == .cat { self.marks[row][col] = .empty }
            self.faultCell = nil
        }
    }

    private func clearHint() { hintCell = nil }

    private func clearHintSoon(_ cell: Cell) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard let self else { return }
            if self.hintCell == cell { self.hintCell = nil }
        }
    }
}
