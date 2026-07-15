import SwiftUI

/// What a player has done to a cell.
enum CellMark: Equatable {
    case empty
    case cat      // a placed cat
    case blocked  // an "X" note: player has ruled this cell out
}

/// A guided hint. Hints never reveal where a cat goes — they show which squares
/// can be ruled out (X'd) and explain why, leading the player to deduce the cat.
struct Hint: Equatable {
    enum Kind {
        case exclude   // X out `targets`; "Apply" marks them
        case focus     // just highlight `targets` (a color/row that's nearly solved)
    }
    let kind: Kind
    let spotlight: GameSession.Cell?  // an existing cat being reasoned about
    let targets: [GameSession.Cell]   // exclude: empties to X · focus: cells to highlight
    let reason: String
    var canApply: Bool { kind == .exclude }
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
    @Published private(set) var activeHint: Hint? = nil
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
        clearHint()

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
            SoundPlayer.shared.play(.pop)
            if correctCats == board.size { win() }
            return .placedCorrect
        }

        // Wrong placement — a mistake.
        mistakes += 1
        marks[row][col] = .cat
        faultCell = Cell(row: row, col: col)
        Haptics.error()
        SoundPlayer.shared.play(.mistake)
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
        clearHint()
        switch marks[row][col] {
        case .empty:
            commit([move(row, col)]); marks[row][col] = .blocked; Haptics.light(); SoundPlayer.shared.play(.tick)
        case .blocked:
            commit([move(row, col)]); marks[row][col] = .empty; Haptics.light(); SoundPlayer.shared.play(.tick)
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
        SoundPlayer.shared.play(.tick)
    }

    func undo() {
        guard canUndo, let group = undoStack.popLast() else { return }
        for m in group.reversed() { marks[m.row][m.col] = m.before }
        recomputeCorrect()
        Haptics.light()
    }

    /// Build a guided hint that spotlights the reasoning and offers a one-tap
    /// action — teaching the deduction rather than just giving the answer.
    @discardableResult
    func hint() -> Hint? {
        guard !isOver else { return nil }

        // A cell can still hold a cat only if no placed cat shares its row,
        // column, region, or touches it. (Ignores the player's X notes.)
        func canHoldCat(_ r: Int, _ c: Int) -> Bool {
            if marks[r][c] == .cat { return false }
            for i in 0..<size where marks[r][i] == .cat { return false }
            for i in 0..<size where marks[i][c] == .cat { return false }
            let region = board.regionID(row: r, col: c)
            for rr in 0..<size {
                for cc in 0..<size where marks[rr][cc] == .cat && board.regionID(row: rr, col: cc) == region { return false }
            }
            for dr in -1...1 { for dc in -1...1 {
                let nr = r + dr, nc = c + dc
                if nr >= 0, nr < size, nc >= 0, nc < size, marks[nr][nc] == .cat { return false }
            } }
            return true
        }
        // 1) Exclusion around a placed cat (the reference hint): X the empty
        //    squares still open in its row, column or neighbours.
        var bestCat: Cell? = nil; var bestTargets: [Cell] = []
        for r in 0..<size { for c in 0..<size where marks[r][c] == .cat {
            var targets: [Cell] = []
            for i in 0..<size {
                if marks[r][i] == .empty { targets.append(Cell(row: r, col: i)) }
                if marks[i][c] == .empty { targets.append(Cell(row: i, col: c)) }
            }
            for dr in -1...1 { for dc in -1...1 {
                let nr = r + dr, nc = c + dc
                if nr >= 0, nr < size, nc >= 0, nc < size, marks[nr][nc] == .empty { targets.append(Cell(row: nr, col: nc)) }
            } }
            var seen = Set<Int>(); targets = targets.filter { seen.insert($0.row * size + $0.col).inserted }
            if targets.count > bestTargets.count { bestTargets = targets; bestCat = Cell(row: r, col: c) }
        } }
        if let cat = bestCat, !bestTargets.isEmpty {
            return set(.init(kind: .exclude, spotlight: cat, targets: bestTargets,
                             reason: "This cat's row, column and neighbours can't hold another cat — rule them out."))
        }

        // 2) Region narrowing: a color with empty squares no cat can reach.
        //    X them so the one remaining square stands out on its own.
        for region in 0..<size where !regionHasCat(region) {
            var blockable: [Cell] = []
            for r in 0..<size { for c in 0..<size
                where board.regionID(row: r, col: c) == region && marks[r][c] == .empty && !canHoldCat(r, c) {
                blockable.append(Cell(row: r, col: c))
            } }
            if !blockable.isEmpty {
                return set(.init(kind: .exclude, spotlight: nil, targets: blockable,
                                 reason: "No cat can reach these squares in this color — rule them out to narrow it down."))
            }
        }

        // 3) Focus: a color that's down to one open square — highlight it so the
        //    player spots the forced cat themselves (never placed for them).
        for region in 0..<size where !regionHasCat(region) {
            let cells = regionCells(region)
            let open = cells.filter { marks[$0.row][$0.col] == .empty }
            if open.count == 1 {
                return set(.init(kind: .focus, spotlight: nil, targets: cells,
                                 reason: "This color is down to one open square — can you see where its cat goes?"))
            }
        }
        // 4) Focus fallback: the most-constrained color.
        var smallest: (region: Int, open: Int, cells: [Cell])? = nil
        for region in 0..<size where !regionHasCat(region) {
            let cells = regionCells(region)
            let open = cells.filter { marks[$0.row][$0.col] == .empty }.count
            if open > 0, smallest == nil || open < smallest!.open { smallest = (region, open, cells) }
        }
        if let s = smallest {
            return set(.init(kind: .focus, spotlight: nil, targets: s.cells,
                             reason: "Fewest squares means fewest choices — reason about this color next."))
        }
        return nil
    }

    private func regionHasCat(_ region: Int) -> Bool {
        for r in 0..<size { for c in 0..<size
            where board.regionID(row: r, col: c) == region && marks[r][c] == .cat { return true } }
        return false
    }
    private func regionCells(_ region: Int) -> [Cell] {
        var cells: [Cell] = []
        for r in 0..<size { for c in 0..<size where board.regionID(row: r, col: c) == region { cells.append(Cell(row: r, col: c)) } }
        return cells
    }

    private func set(_ hint: Hint) -> Hint {
        hintsUsed += 1
        activeHint = hint
        return hint
    }

    /// Apply the active hint's X's (exclude only), then dismiss it.
    func applyHint() {
        guard let h = activeHint, h.kind == .exclude else { activeHint = nil; return }
        activeHint = nil
        var group: [Move] = []
        for t in h.targets where marks[t.row][t.col] == .empty {
            group.append(move(t.row, t.col))
            marks[t.row][t.col] = .blocked
        }
        commit(group)
        Haptics.light()
        SoundPlayer.shared.play(.tick)
    }

    func dismissHint() { activeHint = nil }

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
        SoundPlayer.shared.play(.win)
    }

    private func lose() {
        finishedAt = Date()
        isLost = true
        Haptics.error()
        SoundPlayer.shared.play(.lose)
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

    private func clearHint() { activeHint = nil }
}
