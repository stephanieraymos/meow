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

## Shipping to TestFlight
The project is archive-ready: Team `FZ5HL2XU6U`, app icon, and
`ExportOptions.plist` (App Store Connect, automatic signing) are all configured.

One-time setup (App Store Connect, done in the web UI):
1. Register the bundle id `com.stephanieraymos.meowdoku` and create the app
   record at https://appstoreconnect.apple.com → Apps → +.

Each build:
```sh
xcodegen generate
xcodebuild -project Meowdoku.xcodeproj -scheme Meowdoku \
  -configuration Release -sdk iphoneos \
  -archivePath build/Meowdoku.xcarchive \
  -allowProvisioningUpdates archive

xcodebuild -exportArchive \
  -archivePath build/Meowdoku.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates
```
`-allowProvisioningUpdates` lets Xcode register the App ID and mint the
distribution profile automatically (needs an App Store Connect API key in Xcode's
accounts, or an interactive Xcode login). Then upload `build/export/Meowdoku.ipa`
to TestFlight with Transporter or `xcrun altool --upload-app`.

## Game Center setup (App Store Connect)

The app already submits scores/achievements using the IDs below; create them in
App Store Connect → your app → Features → Game Center to activate them.

Leaderboards (Single leaderboard · **Score format: Elapsed Time to the
hundredth of a second** · **Sort: Low to High**, faster is better):

| Leaderboard ID | Purpose |
|----------------|---------|
| `meow.time.6`  | Fastest 6×6 solve |
| `meow.time.8`  | Fastest 8×8 solve |
| `meow.time.10` | Fastest 10×10 solve |
| `meow.daily.time` | Fastest daily-puzzle solve |

Achievements:

| Achievement ID | When it fires |
|----------------|---------------|
| `meow.win.first` | First solo win |
| `meow.streak.7`  | 7-day daily streak |
| `meow.level.50`  | Complete level 50 |
| `meow.flawless`  | Solve with no mistakes and no hints |

The Game Center capability is already enabled in `Meowdoku.entitlements`.

## Notifications

The daily reminder uses **local** notifications only — no APNs certificate, push
key, or App Store Connect configuration required. iOS shows the permission prompt
when the player enables "Daily reminder" in Settings.
