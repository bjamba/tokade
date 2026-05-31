# Tokade — Summary

## What it does
Tokade is a macOS menu bar app that surfaces a Claude Code user's current rate-limit
utilization (5-hour and 7-day windows), token-by-model breakdown, and longer-term
usage trends. It does this without any API key by reading two local sources: Claude
Code's session JSONL files in `~/.claude/projects/` and a statusline JSON file
written by a companion shell script (`statusline-shim.sh`) that Claude Code is
configured to invoke. No network calls; all data stays on the machine.

## Stack
- **Language**: Swift 5.9
- **UI**: SwiftUI (MenuBarExtra) + Swift Charts
- **Build**: Swift Package Manager (executable target), no Xcode project
- **Bundling**: bespoke `build.sh` that wraps the SPM-built executable into a
  macOS `.app` with `Info.plist` and ad-hoc codesigning
- **Resource conversion**: `librsvg` (`brew install librsvg`) used at icon-gen
  time to produce `AppIcon.icns` and PNG menu-bar templates from SVG sources

## Architecture
Single-process menu bar app with `LSUIElement=true` (no Dock icon). The SwiftUI
`MenuBarExtra` scene drives a panel with three tabs (Budget, Models, Trends) on
top of a single `UsageStore` observable. The store polls every 3 seconds (the
game tick reads the same events at that cadence; an mtime cache keeps re-polls
cheap): reads
all `.jsonl` files under `~/.claude/projects/`, reads the most recent statusline
snapshot from `~/.tokade/last-status.json`, and appends both raw events and
server-snapshot deltas to JSONL archives in `~/.tokade/history/`. All view
state derives from the single store; no other shared state.

```mermaid
flowchart LR
  CC[Claude Code] -->|writes JSONL| JL[~/.claude/projects/*.jsonl]
  CC -->|invokes on each<br/>statusline render| SH[statusline-shim.sh]
  SH -->|writes JSON| ST[~/.tokade/last-status.json]
  JL -->|reads every 3s| US[UsageStore]
  ST -->|reads every 3s| US
  US -->|appends new events| EA[~/.tokade/history/events.jsonl]
  US -->|appends new pct snapshots| SA[~/.tokade/history/snapshots.jsonl]
  US -->|@Observable| UI[SwiftUI MenuBarExtra]
```

## Entry points
- `Sources/Tokade/TokadeApp.swift:4` — `@main struct TokadeApp` creates the
  `UsageStore`, starts the 3-second polling task, and declares the
  `MenuBarExtra` scene
- `Sources/Tokade/MenuView.swift:4` — `MenuView` is the panel root; switches
  between `BudgetTab`, `ModelsTab`, `TrendsTab`
- `Sources/Tokade/UsageStore.swift` — `refresh()` is the central poll function
- `statusline-shim.sh` — the script Claude Code invokes on every statusline
  render; writes the JSON it receives on stdin to `~/.tokade/last-status.json`

## Data
- **Reads**: `~/.claude/projects/**/*.jsonl` (Claude Code's session logs),
  `~/.tokade/last-status.json` (current statusline snapshot)
- **Writes**: `~/.tokade/history/events.jsonl` (append-only event archive,
  ~3MB after a few months of heavy use), `~/.tokade/history/snapshots.jsonl`
  (append-only `%`-utilization snapshots)
- **Sensitive data**: low risk. Tokade reads token counts, model names,
  session IDs, cwds, tool names, and slash commands from JSONL — no prompt
  content, no responses, no auth material. Filesystem paths in `cwd` reveal
  which projects the user works on. All data stays local.

## External dependencies
- **None at runtime.** No Swift Package dependencies declared (target is
  empty `dependencies: []`).
- **At build time**: Swift toolchain (Xcode CLT), `librsvg` (only needed if
  regenerating the icon from SVG; pre-built `AppIcon.icns` is committed).
- **At install time**: `python3` (only used by `install-statusline.sh` to
  patch `~/.claude/settings.json`; macOS ships with python3).
- **External services**: none. Tokade makes zero network calls.

## Current state
- **Tests**: none. No `Tests/` directory, no `Package.swift` test target.
  Smoke testing has been the build-and-launch loop during development.
- **CI/CD**: none. No `.github/workflows/`, no pre-commit hooks. Builds and
  installs are manual via `./build.sh` and `./install.sh`.
- **Deployment**: ad-hoc-signed `.app` bundle installed via `./install.sh`
  to `/Applications/Tokade.app`. No notarization, no distribution channel.
- **Git**: 2 commits on `main`, public at `github.com/bjamba/tokade`. No
  tags. No branches. No PRs.
- **Linting/formatting**: none configured.

## Notable observations
- **Clean separation of concerns.** `UsageStore` owns all I/O; views are
  pure presentations of its state. `ClaudeCodeReader`, `StatusFileReader`,
  `EventArchive`, `SnapshotArchive` each have one job. The split between
  Budget (utilization `%`, server-truth) and Models (raw tokens) deliberately
  prevents users from confusing two unrelated units.
- **One real footgun**: SPM's auto-generated `Bundle.module` accessor bakes
  the build-time path into the binary. We worked around this in
  `SharedComponents.swift:appBundledResource(named:ext:)` by searching the
  real paths ourselves. A new developer adding a second bundled resource
  would hit this trap if they used `Bundle.module` directly. (Worth a
  CLAUDE.md rule.)
- **Build script is opinionated**: `build.sh` skips `--deep` codesigning
  because the SPM resource bundle has no `Info.plist` and breaks deep-sign
  recursion. This is deliberate and noted in a comment, but fragile to
  anyone modifying the bundle layout.
- **No version pin on the Swift toolchain.** `Package.swift` declares
  `swift-tools-version: 5.9` and `platforms: [.macOS(.v14)]`, which is fine,
  but the README doesn't tell a contributor which Xcode/CLT version they need.
- **Charts are well-typed but visually fragile.** SwiftUI Charts has multiple
  past bugs where stack ordering / colors shifted on hover; `StatsView.swift`
  has explicit `chartYScale(domain:)`, pre-sorted rows, and
  `chartForegroundStyleScale(domain:range:)` calls that exist solely to
  stabilize rendering. Future contributors who "simplify" them will reintroduce
  the bugs.
- **No tests on the math that drives every chart**: token aggregation,
  group-by-model, sliding 5h windows, `%` projection wedge, plan-cap
  derivation. Silent bugs in any of these would produce plausible-but-wrong
  numbers — exactly the failure mode hardest to catch by eyeball.
- **`finalize-rename.sh` is dead code now** (the dir rename happened). It's
  gitignored, but it lives in the repo root. Worth deleting.
- **PII-adjacent**: `~/.tokade/history/events.jsonl` captures filesystem
  paths under `cwd`. If a user shares their archive, they leak their project
  list. Documented but worth flagging at the top of the privacy section in
  the README.
