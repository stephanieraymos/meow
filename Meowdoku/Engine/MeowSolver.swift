import Foundation

/// Backtracking solver for the Meowdoku constraint set. Used at generation time
/// to guarantee a puzzle has exactly one solution (no guessing required).
///
/// We place one cat per row, top to bottom. Because there is exactly one cat per
/// column, the only way two cats can *touch* is diagonally across two adjacent
/// rows — cats two or more rows apart can never be adjacent. So the no-touch rule
/// reduces to: for adjacent rows, the chosen columns differ by at least 2.
enum MeowSolver {

    /// Counts solutions up to `limit` (early-exits once `limit` is reached, so
    /// pass `2` when you only care whether the solution is unique).
    static func countSolutions(regions: [[Int]], size: Int, limit: Int = 2) -> Int {
        var usedCol = [Bool](repeating: false, count: size)
        var usedRegion = [Bool](repeating: false, count: size)
        var count = 0

        func place(row: Int, prevCol: Int) {
            if count >= limit { return }
            if row == size { count += 1; return }
            for col in 0..<size {
                if usedCol[col] { continue }
                // No-touch with the cat directly above (adjacent row).
                if prevCol >= 0 && abs(col - prevCol) < 2 { continue }
                let region = regions[row][col]
                if usedRegion[region] { continue }

                usedCol[col] = true
                usedRegion[region] = true
                place(row: row + 1, prevCol: col)
                usedCol[col] = false
                usedRegion[region] = false
                if count >= limit { return }
            }
        }

        place(row: 0, prevCol: -2)
        return count
    }

    /// True iff the (regions) layout yields exactly one solution.
    static func isUnique(regions: [[Int]], size: Int) -> Bool {
        countSolutions(regions: regions, size: size, limit: 2) == 1
    }

    /// Returns the first valid arrangement that differs from `solution`, or `nil`
    /// if `solution` is the only one (i.e. the puzzle is unique). Used by the
    /// generator to find — and then eliminate — competing solutions.
    static func findAlternate(regions: [[Int]], size: Int, avoiding solution: [Int]) -> [Int]? {
        var usedCol = [Bool](repeating: false, count: size)
        var usedRegion = [Bool](repeating: false, count: size)
        var current = [Int](repeating: -1, count: size)
        var found: [Int]? = nil

        func place(row: Int, prevCol: Int) {
            if found != nil { return }
            if row == size {
                if current != solution { found = current }
                return
            }
            for col in 0..<size {
                if usedCol[col] { continue }
                if prevCol >= 0 && abs(col - prevCol) < 2 { continue }
                let region = regions[row][col]
                if usedRegion[region] { continue }

                current[row] = col
                usedCol[col] = true
                usedRegion[region] = true
                place(row: row + 1, prevCol: col)
                usedCol[col] = false
                usedRegion[region] = false
                if found != nil { return }
            }
        }

        place(row: 0, prevCol: -2)
        return found
    }

    // MARK: - Difficulty grading

    /// Grades a puzzle's *logical* difficulty on a 0…1 scale that is **independent
    /// of grid size** — a small board can score hard and a large board easy.
    ///
    /// It simulates a human solver that only ever makes forced deductions:
    ///   • tier 0 ("single") — a region, row, or column with exactly one remaining
    ///     candidate cell forces a cat there.
    ///   • tier 1 ("pointing") — a region confined to one row/column (or a line
    ///     confined to one region) prunes candidates elsewhere, unlocking a single.
    /// A board solved with only tier-0 singles is easy; one that needs tier-1
    /// pruning is medium; one where forced logic stalls (a human must look ahead /
    /// guess-and-check) is hard-to-expert. The score is a per-placement average, so
    /// it does not inflate with size.
    static func gradeDifficulty(regions: [[Int]], size n: Int) -> Double {
        var alive = [[Bool]](repeating: [Bool](repeating: true, count: n), count: n)
        var rowDone = [Bool](repeating: false, count: n)
        var colDone = [Bool](repeating: false, count: n)
        var regionDone = [Bool](repeating: false, count: n)
        var placed = 0
        var tier1Steps = 0
        var usedTier1 = false

        func kill(_ r: Int, _ c: Int) { if r >= 0, r < n, c >= 0, c < n { alive[r][c] = false } }
        func place(_ r: Int, _ c: Int) {
            let g = regions[r][c]
            rowDone[r] = true; colDone[c] = true; regionDone[g] = true
            for k in 0..<n { kill(r, k); kill(k, c) }
            for rr in 0..<n { for cc in 0..<n where regions[rr][cc] == g { kill(rr, cc) } }
            for dr in -1...1 { for dc in -1...1 { kill(r + dr, c + dc) } }
            placed += 1
        }

        while placed < n {
            var progressed = false

            // tier 0 — region with a single candidate
            for g in 0..<n where !regionDone[g] {
                var only: (Int, Int)? = nil, count = 0
                for r in 0..<n { for c in 0..<n where alive[r][c] && regions[r][c] == g { only = (r, c); count += 1 } }
                if count == 1, let (r, c) = only { place(r, c); progressed = true }
            }
            if progressed { continue }
            // tier 0 — row with a single candidate
            for r in 0..<n where !rowDone[r] {
                var only = -1, count = 0
                for c in 0..<n where alive[r][c] { only = c; count += 1 }
                if count == 1 { place(r, only); progressed = true }
            }
            if progressed { continue }
            // tier 0 — column with a single candidate
            for c in 0..<n where !colDone[c] {
                var only = -1, count = 0
                for r in 0..<n where alive[r][c] { only = r; count += 1 }
                if count == 1 { place(only, c); progressed = true }
            }
            if progressed { continue }

            // tier 1 — pointing / line-region confinement
            var pruned = false
            // A region confined to one row/column can't be anywhere else on that line.
            for g in 0..<n where !regionDone[g] {
                var rows = Set<Int>(), cols = Set<Int>()
                for r in 0..<n { for c in 0..<n where alive[r][c] && regions[r][c] == g { rows.insert(r); cols.insert(c) } }
                if rows.count == 1, let rr = rows.first {
                    for c in 0..<n where alive[rr][c] && regions[rr][c] != g { alive[rr][c] = false; pruned = true }
                }
                if cols.count == 1, let cc = cols.first {
                    for r in 0..<n where alive[r][cc] && regions[r][cc] != g { alive[r][cc] = false; pruned = true }
                }
            }
            // A line whose candidates all fall in one region claims that region.
            for r in 0..<n where !rowDone[r] {
                var regs = Set<Int>()
                for c in 0..<n where alive[r][c] { regs.insert(regions[r][c]) }
                if regs.count == 1, let g = regs.first {
                    for rr in 0..<n where rr != r { for c in 0..<n where alive[rr][c] && regions[rr][c] == g { alive[rr][c] = false; pruned = true } }
                }
            }
            for c in 0..<n where !colDone[c] {
                var regs = Set<Int>()
                for r in 0..<n where alive[r][c] { regs.insert(regions[r][c]) }
                if regs.count == 1, let g = regs.first {
                    for cc in 0..<n where cc != c { for r in 0..<n where alive[r][cc] && regions[r][cc] == g { alive[r][cc] = false; pruned = true } }
                }
            }
            if pruned { usedTier1 = true; tier1Steps += 1; progressed = true; continue }

            break   // forced logic stalled — needs look-ahead
        }

        if placed < n {
            // Human must guess-and-check: hard → expert, scaled by how stuck it got.
            let frac = Double(n - placed) / Double(n)
            return min(1.0, 0.72 + 0.28 * frac)
        }
        if !usedTier1 { return 0.15 }                       // pure singles → easy
        let ratio = min(1.0, Double(tier1Steps) / Double(n))
        return 0.40 + 0.30 * ratio                          // pointing needed → medium
    }
}
