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
}
