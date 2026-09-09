# Meow — Meowdoku puzzle game (iOS)

**Read this first; it is loaded automatically because it lives in the repo.** The
long-form docs live in iCloud and are NOT auto-loaded — open them when the task is
architectural rather than a small change:

- `Cowork OS/Projects/Meow/CLAUDE.md` — architecture, features, design rules
- `Cowork OS/Projects/Meow/MEMORY.md` — current status, decisions, backlog

`Cowork OS` = `~/Library/Mobile Documents/com~apple~CloudDocs/Cowork OS`.

## Facts

- **Bundle id is `com.stephanieraymos.meowdoku`**, not `.meow`. The repo, the folder
  and the product name disagree on purpose; the bundle id is the one that matters for
  signing and App Store Connect.
- **Xcode project is `Meowdoku.xcodeproj`, scheme `Meowdoku`** — not "Meow".
- **Backend:** family Supabase `ihvljgwfslxorxsorzpi`, `meow_` prefixed tables.

## Commands

```
make gen
make build     # xcodebuild against Meowdoku.xcodeproj
make profile
make ship      # NEVER without explicit per-session approval
```

**The ship script does NOT self-verify** — confirm against the ASC API before saying
a build shipped.

## Notes

A game rather than a data app: most of the logic is local, so the Supabase surface is
small. Treat puzzle generation and solving as the core, not the sync.
