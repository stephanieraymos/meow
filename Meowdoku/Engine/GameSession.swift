import SwiftUI

/// What a player has done to a cell.
enum CellMark: Equatable {
    case empty
    case cat      // a placed cat
    case blocked  // an "X" note: player has ruled this cell out
}

/// A guided hint. Hints never place a cat — they only ever lead the player to an
/// "X", and explain the deduction so the move teaches something:
///  - `.exclude` rules out (X's) a *group* of `targets` and explains why.
///  - `.testExclude` rules out a *single* candidate `targets[0]` by contradiction:
///     a cat there would wipe out every open square of some row/column/color, so
///     that line could never get its cat — meaning a cat can't go there. Shown as
///     a "?"-cat on the tested square with the doomed line highlighted.
///  - `.focus` just spotlights a nearly-solved color without acting.
/// Every hint's `reason` states the concrete consequence.
struct Hint: Equatable {
    enum Kind {
        case exclude      // X out the group `targets`; "Apply" marks them
        case testExclude  // "?"-cat: a cat at `targets[0]` is impossible; "Apply" X's it
        case focus        // just highlight `targets` (a color/row that's nearly solved)
    }
    let kind: Kind
    let highlight: [GameSession.Cell]  // the "cause" cells the reasoning points at (the doomed line for testExclude)
    let targets: [GameSession.Cell]    // exclude: empties to X · testExclude: the one impossible cell · focus: cells to highlight
    let reason: String
    var canApply: Bool { kind != .focus }
}

extension String {
    /// Uppercases only the first character (leaves the rest untouched), so
    /// "the olive cat" → "The olive cat" without lower-casing the rest.
    var capitalizedFirst: String {
        guard let f = first else { return self }
        return f.uppercased() + dropFirst()
    }
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
    /// Plain-English name per region id (e.g. "olive", "teal"), so hints can say
    /// which color they're reasoning about. Empty → hints fall back to "this color".
    var colorNames: [String] = []
    let startedAt = Date()
    private(set) var finishedAt: Date?

    struct Cell: Equatable { let row: Int; let col: Int }
    private struct Move { let row: Int; let col: Int; let before: CellMark }
    /// Each user action pushes one group, so undo reverts a placement together
    /// with any auto-marks it triggered.
    private var undoStack: [[Move]] = []
    private var faultToken = 0

    init(board: MeowBoard, allowedMistakes: Int = 1, autoMark: Bool = false, colorNames: [String] = []) {
        self.board = board
        self.allowedMistakes = allowedMistakes
        self.autoMark = autoMark
        self.colorNames = colorNames
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
        Haptics.selection()
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
        // Candidate = an empty square that could still hold a cat given the cats
        // already placed (ignores the player's own X notes).
        var possible = [[Bool]](repeating: [Bool](repeating: false, count: size), count: size)
        for r in 0..<size { for c in 0..<size { possible[r][c] = marks[r][c] == .empty && canHoldCat(r, c) } }

        // Simplest (most teachable) exclusions first, then the contradiction test,
        // then the more abstract locked/naked deductions.
        return basicElimination()
            ?? contradictionExclusion(possible)
            ?? lockedInLine(possible)
            ?? nakedSubset(possible, byColumn: true)
            ?? nakedSubset(possible, byColumn: false)
            ?? focusFallback(possible)
    }

    /// A readable name for a region's color; falls back to a neutral phrase.
    private func colorName(_ region: Int) -> String {
        region >= 0 && region < colorNames.count ? colorNames[region] : "this color"
    }

    /// "the olive cat" / "this color's cat" — subject phrase for a color's cat.
    private func catPhrase(_ region: Int) -> String {
        region >= 0 && region < colorNames.count ? "the \(colorNames[region]) cat" : "this color's cat"
    }

    /// Join names into readable English: "olive", "olive and teal", "a, b and c".
    private func englishList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }

    /// Technique — contradiction ("what-if"). If putting a cat in a candidate
    /// square would rule out *every* remaining open square of some row, column or
    /// color, then that line could never get its own cat. Since every line needs
    /// one, a cat can't go in that candidate — so it must be an "X". This is the
    /// "?"-cat hint: the tested square with the doomed line highlighted.
    private func contradictionExclusion(_ possible: [[Bool]]) -> Hint? {
        for r in 0..<size { for c in 0..<size where possible[r][c] {
            let hereRegion = board.regionID(row: r, col: c)

            for tr in 0..<size where tr != r && rowCat(tr) == nil {
                let cands = (0..<size).filter { possible[tr][$0] }.map { Cell(row: tr, col: $0) }
                if !cands.isEmpty, cands.allSatisfy({ wouldEliminate(catAt: (r, c), cell: $0) }) {
                    return set(.init(kind: .testExclude, highlight: cands, targets: [Cell(row: r, col: c)],
                        reason: "A cat here would rule out every open square in row \(tr + 1) — but every row needs a cat, so this square must be X."))
                }
            }
            for tc in 0..<size where tc != c && colCat(tc) == nil {
                let cands = (0..<size).filter { possible[$0][tc] }.map { Cell(row: $0, col: tc) }
                if !cands.isEmpty, cands.allSatisfy({ wouldEliminate(catAt: (r, c), cell: $0) }) {
                    return set(.init(kind: .testExclude, highlight: cands, targets: [Cell(row: r, col: c)],
                        reason: "A cat here would rule out every open square in column \(tc + 1) — but every column needs a cat, so this square must be X."))
                }
            }
            for reg in 0..<size where reg != hereRegion && regionCat(reg) == nil {
                let cands = regionCells(reg).filter { possible[$0.row][$0.col] }
                if !cands.isEmpty, cands.allSatisfy({ wouldEliminate(catAt: (r, c), cell: $0) }) {
                    return set(.init(kind: .testExclude, highlight: cands, targets: [Cell(row: r, col: c)],
                        reason: "A cat here would rule out every open square of \(colorName(reg)) — but each color needs a cat, so this square must be X."))
                }
            }
        } }
        return nil
    }

    /// Would a cat at `catAt` rule `cell` out? True if they share a row, column or
    /// color, or touch (orthogonally or diagonally).
    private func wouldEliminate(catAt: (r: Int, c: Int), cell: Cell) -> Bool {
        if cell.row == catAt.r || cell.col == catAt.c { return true }
        if board.regionID(row: cell.row, col: cell.col) == board.regionID(row: catAt.r, col: catAt.c) { return true }
        return abs(cell.row - catAt.r) <= 1 && abs(cell.col - catAt.c) <= 1
    }

    /// A square can still hold a cat only if no placed cat shares its row, column
    /// or color, or touches it.
    private func canHoldCat(_ r: Int, _ c: Int) -> Bool {
        if marks[r][c] == .cat { return false }
        for i in 0..<size where marks[r][i] == .cat { return false }
        for i in 0..<size where marks[i][c] == .cat { return false }
        let region = board.regionID(row: r, col: c)
        for rr in 0..<size { for cc in 0..<size where marks[rr][cc] == .cat && board.regionID(row: rr, col: cc) == region { return false } }
        for dr in -1...1 { for dc in -1...1 {
            let nr = r + dr, nc = c + dc
            if nr >= 0, nr < size, nc >= 0, nc < size, marks[nr][nc] == .cat { return false }
        } }
        return true
    }

    /// Technique 1 — a row / column / color that already holds a cat rules out its
    /// remaining empty squares (and squares touching a cat are out).
    private func basicElimination() -> Hint? {
        var best: (targets: [Cell], highlight: [Cell], reason: String)?
        func consider(_ targets: [Cell], _ highlight: [Cell], _ reason: String) {
            guard !targets.isEmpty else { return }
            if best == nil || targets.count > best!.targets.count { best = (targets, highlight, reason) }
        }
        for r in 0..<size where rowCat(r) != nil {
            consider((0..<size).filter { marks[r][$0] == .empty }.map { Cell(row: r, col: $0) },
                     [rowCat(r)!], "A cat can't go in these — row \(r + 1) already has a cat.")
        }
        for c in 0..<size where colCat(c) != nil {
            consider((0..<size).filter { marks[$0][c] == .empty }.map { Cell(row: $0, col: c) },
                     [colCat(c)!], "A cat can't go in these — column \(c + 1) already has a cat.")
        }
        for region in 0..<size where regionCat(region) != nil {
            var empties: [Cell] = []
            for r in 0..<size { for c in 0..<size where board.regionID(row: r, col: c) == region && marks[r][c] == .empty { empties.append(Cell(row: r, col: c)) } }
            consider(empties, [regionCat(region)!], "A cat can't go in these — \(catPhrase(region)) is already placed.")
        }
        for r in 0..<size { for c in 0..<size where marks[r][c] == .cat {
            var neighbours: [Cell] = []
            for dr in -1...1 { for dc in -1...1 where !(dr == 0 && dc == 0) {
                let nr = r + dr, nc = c + dc
                if nr >= 0, nr < size, nc >= 0, nc < size, marks[nr][nc] == .empty { neighbours.append(Cell(row: nr, col: nc)) }
            } }
            consider(neighbours, [Cell(row: r, col: c)], "A cat can't go here — it would touch the cat beside it.")
        } }
        guard let b = best else { return nil }
        return set(.init(kind: .exclude, highlight: b.highlight, targets: b.targets, reason: b.reason))
    }

    /// Technique 2 — locked candidates. If a color's only remaining squares sit in
    /// one row (or column), that line belongs to it, so no other cat can take it.
    private func lockedInLine(_ possible: [[Bool]]) -> Hint? {
        for region in 0..<size where regionCat(region) == nil {
            var cells: [Cell] = []
            for r in 0..<size { for c in 0..<size where possible[r][c] && board.regionID(row: r, col: c) == region { cells.append(Cell(row: r, col: c)) } }
            guard let first = cells.first else { continue }
            if cells.allSatisfy({ $0.row == first.row }) {
                let r = first.row
                let targets = (0..<size).compactMap { c in possible[r][c] && board.regionID(row: r, col: c) != region ? Cell(row: r, col: c) : nil }
                if !targets.isEmpty {
                    return set(.init(kind: .exclude, highlight: cells, targets: targets,
                                     reason: "\(catPhrase(region).capitalizedFirst) can only go in row \(r + 1), so no other cat can take that row."))
                }
            }
            if cells.allSatisfy({ $0.col == first.col }) {
                let c = first.col
                let targets = (0..<size).compactMap { r in possible[r][c] && board.regionID(row: r, col: c) != region ? Cell(row: r, col: c) : nil }
                if !targets.isEmpty {
                    return set(.init(kind: .exclude, highlight: cells, targets: targets,
                                     reason: "\(catPhrase(region).capitalizedFirst) can only go in column \(c + 1), so no other cat can take that column."))
                }
            }
        }
        return nil
    }

    /// Technique 3 — naked subsets. If K colors' remaining squares fit within
    /// exactly K columns (or rows), those lines are claimed, so no other cat can
    /// go in them. (This is the "N colors share N cols" deduction.)
    private func nakedSubset(_ possible: [[Bool]], byColumn: Bool) -> Hint? {
        var linesByColor: [Int: Set<Int>] = [:]
        var cellsByColor: [Int: [Cell]] = [:]
        for region in 0..<size where regionCat(region) == nil {
            var ls = Set<Int>(); var cs: [Cell] = []
            for r in 0..<size { for c in 0..<size where possible[r][c] && board.regionID(row: r, col: c) == region {
                ls.insert(byColumn ? c : r); cs.append(Cell(row: r, col: c))
            } }
            if !ls.isEmpty { linesByColor[region] = ls; cellsByColor[region] = cs }
        }
        let colors = linesByColor.keys.sorted()
        for k in 2...3 where k <= colors.count {
            for combo in combinations(colors, k) {
                var union = Set<Int>()
                for color in combo { union.formUnion(linesByColor[color]!) }
                guard union.count == k else { continue }
                let comboSet = Set(combo)
                var targets: [Cell] = []
                for r in 0..<size { for c in 0..<size where possible[r][c] {
                    if union.contains(byColumn ? c : r), !comboSet.contains(board.regionID(row: r, col: c)) { targets.append(Cell(row: r, col: c)) }
                } }
                if !targets.isEmpty {
                    let names = englishList(combo.map { colorName($0) })
                    let lines = englishList(union.sorted().map { "\(byColumn ? "column" : "row") \($0 + 1)" })
                    return set(.init(kind: .exclude, highlight: combo.flatMap { cellsByColor[$0]! }, targets: targets,
                                     reason: "The \(names) cats can only fit in \(lines), so no other cat can go there."))
                }
            }
        }
        return nil
    }

    /// Nothing left to rule out — point at the most-constrained color so the
    /// player knows where to reason next.
    private func focusFallback(_ possible: [[Bool]]) -> Hint? {
        var smallest: (open: Int, region: Int, cells: [Cell])?
        for region in 0..<size where regionCat(region) == nil {
            let cells = regionCells(region)
            let open = cells.filter { possible[$0.row][$0.col] }.count
            if open > 0, smallest == nil || open < smallest!.open { smallest = (open, region, cells) }
        }
        if let s = smallest {
            return set(.init(kind: .focus, highlight: s.cells, targets: s.cells,
                             reason: "\(catPhrase(s.region).capitalizedFirst) has the fewest squares left — reason about it next."))
        }
        return nil
    }

    private func rowCat(_ r: Int) -> Cell? { for c in 0..<size where marks[r][c] == .cat { return Cell(row: r, col: c) }; return nil }
    private func colCat(_ c: Int) -> Cell? { for r in 0..<size where marks[r][c] == .cat { return Cell(row: r, col: c) }; return nil }
    private func regionCat(_ region: Int) -> Cell? {
        for r in 0..<size { for c in 0..<size where marks[r][c] == .cat && board.regionID(row: r, col: c) == region { return Cell(row: r, col: c) } }
        return nil
    }
    private func regionCells(_ region: Int) -> [Cell] {
        var cells: [Cell] = []
        for r in 0..<size { for c in 0..<size where board.regionID(row: r, col: c) == region { cells.append(Cell(row: r, col: c)) } }
        return cells
    }
    private func combinations(_ arr: [Int], _ k: Int) -> [[Int]] {
        guard k > 0, arr.count >= k else { return k == 0 ? [[]] : [] }
        var result: [[Int]] = []
        func go(_ start: Int, _ current: [Int]) {
            if current.count == k { result.append(current); return }
            for i in start..<arr.count { go(i + 1, current + [arr[i]]) }
        }
        go(0, [])
        return result
    }

    private func set(_ hint: Hint) -> Hint {
        hintsUsed += 1
        activeHint = hint
        return hint
    }

    /// Apply the active hint's action, then dismiss it. Both `.exclude` and
    /// `.testExclude` only ever place "X"s — never a cat — so the player still
    /// makes every placement themselves. `.focus` just dismisses.
    func applyHint() {
        guard let h = activeHint else { return }
        activeHint = nil
        switch h.kind {
        case .exclude, .testExclude:
            var group: [Move] = []
            for t in h.targets where marks[t.row][t.col] == .empty {
                group.append(move(t.row, t.col))
                marks[t.row][t.col] = .blocked
            }
            commit(group)
            Haptics.light()
            SoundPlayer.shared.play(.tick)
        case .focus:
            break
        }
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
