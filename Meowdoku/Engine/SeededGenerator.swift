import Foundation

/// A fully deterministic pseudo-random generator (SplitMix64).
///
/// Determinism is critical: in a race, both players must generate the *identical*
/// puzzle from a shared seed. We deliberately avoid `Set`/`Dictionary` iteration
/// (whose order is randomized per process) and Swift stdlib `random(in:using:)`
/// (whose mapping could vary across stdlib versions). Every random draw goes
/// through the helpers below so results are byte-for-byte reproducible on any
/// device running any Swift/iOS version.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid a zero state producing a degenerate stream.
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    /// Raw 64-bit draw.
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform-ish integer in `0..<bound`. Modulo bias is negligible for the
    /// small bounds used in puzzle generation.
    mutating func int(_ bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        return Int(next() % UInt64(bound))
    }

    /// Deterministic in-place Fisher–Yates shuffle.
    mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        var i = array.count - 1
        while i > 0 {
            let j = int(i + 1)
            array.swapAt(i, j)
            i -= 1
        }
    }
}
