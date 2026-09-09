# Meow — Meowdoku puzzle game (iOS)

**Read this first; it is loaded automatically because it lives in the repo. It is a
pointer, not the documentation.**

## Read these before you start, and write back to them as you finish

The real project documentation lives in iCloud and is NOT auto-loaded. Open both
before anything beyond a trivial change:

| Document | Path |
| :-- | :-- |
| Workstation brief — architecture, features, design rules | `Cowork OS/Projects/Meow/CLAUDE.md` |
| Living status — current state, decisions, backlog | `Cowork OS/Projects/Meow/MEMORY.md` |
| Plan — phases and rationale, where one exists | `Cowork OS/Projects/Meow/plan.md` |

**Update MEMORY.md as each piece of work finishes, not at the end of the session.**
A session that is interrupted or runs out of context takes undocumented work with
it, and the next one starts from a status line that is already wrong. Write an entry
the moment a feature lands, a decision is made, or something here turns out to be
stale: what changed, and why it was done that way. Keep the `*Last updated:*` line at
the top of MEMORY.md current, and correct the workstation CLAUDE.md whenever the code
and the doc disagree — the code is the truth, the doc is what the next session reads.

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
