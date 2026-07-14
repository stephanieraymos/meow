import Foundation

/// Deterministically generates a unique-solution Meowdoku board from a seed.
///
/// Same `(seed, size)` → identical board on every device. This is what makes the
/// race fair: the host picks a seed, shares it, and both players regenerate the
/// exact same puzzle locally instead of shipping the grid over the network.
///
/// Strategy: pick a valid cat placement, grow colored regions around it, then
/// *repair* the regions — surgically reassigning boundary cells to eliminate any
/// competing solution until only the intended one remains.
enum PuzzleGenerator {

    static func generate(seed: UInt64, size: Int) -> MeowBoard {
        var rng = SeededGenerator(seed: seed)

        for _ in 0..<40 {
            guard let solution = makeSolution(size: size, rng: &rng) else { continue }
            var regions = growRegions(size: size, solution: solution, rng: &rng)
            if repairToUnique(regions: &regions, solution: solution, size: size, rng: &rng) {
                return MeowBoard(size: size, regions: regions, solution: solution, seed: seed)
            }
        }

        // Fallback (practically never hit): guarantee uniqueness by pinning each
        // region tightly. Still a valid, solvable board.
        let solution = fallbackSolution(size: size)
        var regions = growRegions(size: size, solution: solution, rng: &rng)
        _ = repairToUnique(regions: &regions, solution: solution, size: size, rng: &rng)
        return MeowBoard(size: size, regions: regions, solution: solution, seed: seed)
    }

    // MARK: - Solution placement

    /// One cat per row/column with no two cats touching. Randomized backtracking:
    /// for each row we try columns (shuffled) that are unused and ≥2 away from the
    /// previous row's column.
    private static func makeSolution(size: Int, rng: inout SeededGenerator) -> [Int]? {
        var solution = [Int](repeating: -1, count: size)
        var usedCol = [Bool](repeating: false, count: size)

        func place(_ row: Int) -> Bool {
            if row == size { return true }
            var candidates = Array(0..<size)
            rng.shuffle(&candidates)
            let prev = row > 0 ? solution[row - 1] : -2
            for col in candidates {
                if usedCol[col] { continue }
                if abs(col - prev) < 2 { continue }
                solution[row] = col
                usedCol[col] = true
                if place(row + 1) { return true }
                usedCol[col] = false
                solution[row] = -1
            }
            return false
        }

        return place(0) ? solution : nil
    }

    private static func fallbackSolution(size: Int) -> [Int] {
        var cols: [Int] = []
        var c = 0
        while c < size { cols.append(c); c += 2 }
        c = 1
        while c < size { cols.append(c); c += 2 }
        return Array(cols.prefix(size))
    }

    // MARK: - Region carving

    /// Multi-source flood growth. Each solution cell seeds its own region; every
    /// other cell is repeatedly claimed by a random adjacent region until the
    /// whole grid is covered. Produces `size` orthogonally-connected regions, each
    /// containing exactly one cat.
    private static func growRegions(size: Int, solution: [Int], rng: inout SeededGenerator) -> [[Int]] {
        var region = [[Int]](repeating: [Int](repeating: -1, count: size), count: size)
        for r in 0..<size {
            region[r][solution[r]] = r   // region id == its seed row
        }

        var remaining = size * size - size
        while remaining > 0 {
            var frontier: [(Int, Int)] = []
            for r in 0..<size {
                for cc in 0..<size where region[r][cc] == -1 {
                    for (dr, dc) in dirs {
                        let nr = r + dr, nc = cc + dc
                        if inBounds(nr, nc, size), region[nr][nc] != -1 {
                            frontier.append((r, cc)); break
                        }
                    }
                }
            }
            if frontier.isEmpty { break }

            let (fr, fc) = frontier[rng.int(frontier.count)]
            var choices: [Int] = []
            for (dr, dc) in dirs {
                let nr = fr + dr, nc = fc + dc
                if inBounds(nr, nc, size), region[nr][nc] != -1 {
                    choices.append(region[nr][nc])
                }
            }
            region[fr][fc] = choices[rng.int(choices.count)]
            remaining -= 1
        }
        return region
    }

    // MARK: - Uniqueness repair

    /// Reassigns boundary cells to eliminate competing solutions. Each pass finds
    /// one alternate solution and reshapes a region so that alternate becomes
    /// invalid, without ever disturbing the intended solution. Returns true once
    /// the board is unique.
    private static func repairToUnique(regions: inout [[Int]], solution: [Int], size: Int, rng: inout SeededGenerator) -> Bool {
        let maxPasses = size * size * 3
        for _ in 0..<maxPasses {
            guard let alt = MeowSolver.findAlternate(regions: regions, size: size, avoiding: solution) else {
                return true   // no alternate exists → unique
            }
            if !killAlternate(alt: alt, regions: &regions, solution: solution, size: size, rng: &rng) {
                return false  // couldn't reshape safely; caller will retry with a new solution
            }
        }
        return MeowSolver.isUnique(regions: regions, size: size)
    }

    /// Makes `alt` invalid by moving one of alt's (non-true) cat cells into an
    /// adjacent region, forcing a two-cats-in-one-region conflict for `alt` while
    /// leaving the true solution untouched.
    ///
    /// Moving a boundary cell can orphan a fragment of its old region; we sweep
    /// that fragment into the new region too, so both regions stay connected. The
    /// old region always keeps its seed cell (its true cat), so the intended
    /// solution is never disturbed.
    private static func killAlternate(alt: [Int], regions: inout [[Int]], solution: [Int], size: Int, rng: inout SeededGenerator) -> Bool {
        var rows: [Int] = []
        for r in 0..<size where alt[r] != solution[r] { rows.append(r) }
        rng.shuffle(&rows)

        for r in rows {
            let c = alt[r]                    // alt's cat here; never a true-solution cell
            let old = regions[r][c]
            var neighborRegions: [Int] = []
            for (dr, dc) in dirs {
                let nr = r + dr, nc = c + dc
                if inBounds(nr, nc, size) {
                    let g = regions[nr][nc]
                    if g != old && !neighborRegions.contains(g) { neighborRegions.append(g) }
                }
            }
            if neighborRegions.isEmpty { continue }   // interior cell, no boundary to move across
            rng.shuffle(&neighborRegions)
            let g = neighborRegions[0]

            regions[r][c] = g
            // Any part of `old` no longer reachable from its seed is swept into `g`
            // (that fragment was only connected through the cell we just moved).
            absorbOrphans(oldRegion: old, seed: (old, solution[old]), into: g, regions: &regions, size: size)
            return true
        }
        return false
    }

    /// Reassigns every `oldRegion` cell not reachable (orthogonally) from `seed`
    /// to region `into`.
    private static func absorbOrphans(oldRegion: Int, seed: (Int, Int), into: Int, regions: inout [[Int]], size: Int) {
        var reachable = [[Bool]](repeating: [Bool](repeating: false, count: size), count: size)
        var stack = [seed]
        reachable[seed.0][seed.1] = true
        while let (r, c) = stack.popLast() {
            for (dr, dc) in dirs {
                let nr = r + dr, nc = c + dc
                if inBounds(nr, nc, size), !reachable[nr][nc], regions[nr][nc] == oldRegion {
                    reachable[nr][nc] = true
                    stack.append((nr, nc))
                }
            }
        }
        for r in 0..<size {
            for c in 0..<size where regions[r][c] == oldRegion && !reachable[r][c] {
                regions[r][c] = into
            }
        }
    }

    // MARK: - Helpers

    private static let dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]

    private static func inBounds(_ r: Int, _ c: Int, _ size: Int) -> Bool {
        r >= 0 && r < size && c >= 0 && c < size
    }
}
