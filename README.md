# Meowdoku 🐱

A cat-themed **Queens-style logic puzzle** for iOS (SwiftUI), with a live
head-to-head race mode built for two players.

## The puzzle
On an N×N grid divided into N colored regions, place cats so that:

- exactly **one cat per row**,
- exactly **one cat per column**,
- exactly **one cat per colored region**, and
- **no two cats touch** — orthogonally *or* diagonally.

Every puzzle has a single solution reachable by pure deduction — **no guessing**.

## Modes
- **Play solo** — practice at Easy (6×6), Normal (8×8), or Hard (10×10).
- **Race Audie** — a real-time head-to-head. Both players get the *identical*
  puzzle, play on their own boards, and the **first to place every cat wins**.
  It's high stakes: **one wrong cat ends your run instantly. No hints.**

## How the race stays fair
Both devices regenerate the exact same board from a shared 64-bit seed — the
puzzle is never sent over the wire. Generation is fully deterministic (custom
SplitMix64 RNG, no `Set`/`Dictionary` iteration, no stdlib randomness), so the
same `(seed, size)` yields a byte-for-byte identical board anywhere. The winner
is resolved atomically on the server (first writer to claim `winner` wins), so
there are never ties or double-wins.

## Architecture
| Layer | Files |
|-------|-------|
| Puzzle engine | `Engine/SeededGenerator.swift`, `MeowBoard.swift`, `MeowSolver.swift`, `PuzzleGenerator.swift` |
| Game state | `Engine/GameSession.swift` |
| Networking (Supabase PostgREST + polling) | `Network/MeowConfig.swift`, `Match.swift`, `MeowAPI.swift`, `RaceStore.swift` |
| UI | `Views/*`, `Theme/MeowTheme.swift` |

The generator carves regions with multi-source flood growth, then *repairs* them
— surgically reassigning boundary cells to eliminate any competing solution —
until the board is provably unique.

## Build
Requires Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open Meowdoku.xcodeproj
```

The `.xcodeproj` is generated (git-ignored); `project.yml` is the source of truth.
Supabase URL and the publishable anon key are injected via `project.yml` into
Info.plist — no credentials in Swift source.

## Backend
Supabase table `meow_matches` (project `ihvljgwfslxorxsorzpi`). Row-level
security allows anonymous access for this two-player game; the row only tracks
progress and the winner — never the puzzle itself.
