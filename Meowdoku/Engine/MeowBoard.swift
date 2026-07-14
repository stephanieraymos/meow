import Foundation

/// An immutable Meowdoku puzzle.
///
/// Rules (Queens-family):
///  - Exactly one cat per row.
///  - Exactly one cat per column.
///  - Exactly one cat per colored region.
///  - No two cats touch — orthogonally *or* diagonally.
///
/// A well-formed board has a single unique solution reachable by pure deduction.
struct MeowBoard: Equatable {
    let size: Int
    /// `regions[row][col]` → region id in `0..<size`. Each region is orthogonally
    /// connected and contains exactly one solution cat.
    let regions: [[Int]]
    /// `solution[row]` = column of the cat in that row. A permutation of `0..<size`.
    let solution: [Int]
    let seed: UInt64

    func regionID(row: Int, col: Int) -> Int { regions[row][col] }

    /// True iff `(row, col)` holds a cat in the unique solution.
    func isSolutionCell(row: Int, col: Int) -> Bool { solution[row] == col }
}
