# Architecture

> **Last reviewed**: 2026-05-13
> **Owner**: @bjamba
> **Status**: stable for v0.x

Tokade is a single-process macOS menu bar app. It polls two local sources
every 3 seconds, appends to two local archives, and renders three tabs of
charts off a single observable store. No network calls; no IPC beyond the
statusline shim's file-write.

## Data flow

```mermaid
flowchart LR
  CC[Claude Code] -->|writes JSONL| JL["~/.claude/projects/*.jsonl"]
  CC -->|invokes on each<br/>statusline render| SH[statusline-shim.sh]
  SH -->|writes JSON| ST["~/.tokade/last-status.json"]
  JL -->|reads every 3s| US[UsageStore]
  ST -->|reads every 3s| US
  US -->|appends new events| EA["~/.tokade/history/events.jsonl"]
  US -->|appends new pct snapshots| SA["~/.tokade/history/snapshots.jsonl"]
  US -->|@Observable @MainActor| UI[SwiftUI MenuBarExtra]

  subgraph "Budget tab"
    UI --> BT[Subscription limits + Current 5h budget + Past 5h windows]
  end
  subgraph "Models tab"
    UI --> MT[Tokens by model + Top 5 slash/projects/tools]
  end
  subgraph "Trends tab"
    UI --> TT[Heatmap + YTD cumulative]
  end
```

## File map

### Entry

- `Sources/Tokade/TokadeApp.swift` — `@main`, creates `UsageStore`, starts
  the 30 s polling task, declares `MenuBarExtra` scene with custom menu bar
  template glyph

### State

- `Sources/Tokade/UsageStore.swift` — `@MainActor @Observable` singleton-ish.
  Owns: `events`, `rateLimits`, `snapshots`, `lastUpdated`, `isLoading`.
  All readers are unidirectional from views; no view writes to the store
  except via `refresh()`.

### I/O

- `Sources/Tokade/ClaudeCodeReader.swift` — actor. Enumerates
  `~/.claude/projects/**/*.jsonl`, parses each line, returns deduped
  `[UsageEvent]`. Maintains a per-file session-id → cwd / slash-command
  map within `parseFile()`.
- `Sources/Tokade/StatusFileReader.swift` — actor. Reads
  `~/.tokade/last-status.json` and decodes it into a `RateLimitSnapshot`.
- `Sources/Tokade/EventArchive.swift` — actor. Append-only JSONL writer
  for every parsed event. High-water mark in `events.last` prevents
  re-archiving.
- `Sources/Tokade/SnapshotArchive.swift` — actor. Same shape as
  EventArchive but for the rolling `%` snapshots.

### Models

- `Sources/Tokade/Models.swift` — `UsageEvent` struct, `formatCount`,
  and the `Sequence` extensions that drive every chart:
  `groupedByModel`, `groupedByProject`, `toolCallCounts`,
  `groupedBySlashCommand`, `stackedByProjectAndModel`,
  `stackedBySlashCommandAndModel`, `stackedByToolAndModel`,
  `within(_:)`. Any new chart-driving function added here must be
  added to `scripts/check.sh`'s required-test list.

### Shared

- `Sources/Tokade/SharedComponents.swift` — `Card` view,
  `MiniTooltip`, `modelRank`, `sortedModels`, `modelColor`,
  `appBundledResource`, `effectiveFiveHourResetsAt`,
  `isFiveHourDataStale`, `tokadeIcon`. Centralizes the
  decision-makers used across the three tabs.

### Tabs and cards

- `Sources/Tokade/MenuView.swift` — root panel; tab picker;
  `BudgetTab`, `TrendsTab`. Note all three are annotated
  `@MainActor` so they can read `UsageStore`'s actor-isolated
  properties.
- `Sources/Tokade/StatsView.swift` — `ModelsTab` and its four
  horizontal bar charts.
- `Sources/Tokade/CurrentSessionCard.swift` — Budget tab's
  current-5h-window curve.
- `Sources/Tokade/PastWindowsBudgetCard.swift` — Budget tab's
  per-window utilization bars (mix of server-truth and JSONL-derived
  approximations).
- `Sources/Tokade/HeatmapCard.swift` — Trends tab's all-time
  weekday × hour grid.
- `Sources/Tokade/YTDCumulativeCard.swift` — Trends tab's cumulative
  line with linear-rate projection wedge.
- `Sources/Tokade/WindowSkillsCard.swift` — currently unused in the
  app body. Retained for the Models tab v2 iteration.

### Build

- `Package.swift` — SPM manifest. `executableTarget Tokade` +
  `testTarget TokadeTests`. Resources processed from
  `Sources/Tokade/Resources/`.
- `build.sh` — wraps `swift build -c release` into a macOS `.app`
  bundle with `Info.plist`, app icon, resource bundle, and ad-hoc
  codesigning.
- `install.sh` — `build.sh` + copy to `/Applications/` + `lsregister`.
- `install-statusline.sh` — patches `~/.claude/settings.json` to
  invoke our statusline shim on every Claude Code response.

### Tests

- `Tests/TokadeTests/` — XCTest target. Categorized:
  - `SmokeTests.swift` — `formatCount`
  - `ModelRankTests.swift` — tier + version classification, sort order
  - `ModelsExtensionsTests.swift` — all the `Sequence` aggregations
  - `RateLimitHelpersTests.swift` — projection of stale `resetsAt`
  - `ClaudeCodeReaderTests.swift` — JSONL parsing against fixture files

## Concurrency model

- `UsageStore` is `@MainActor`. Every observer (View struct) is also
  `@MainActor` so they can read store properties without extra hops.
- I/O happens on `actor` types (`ClaudeCodeReader`, `StatusFileReader`,
  `EventArchive`, `SnapshotArchive`). `refresh()` `await`s them in
  parallel where independent.
- The polling task is launched from `TokadeApp.init` with
  `Task { @MainActor in s.startPolling(every: 30) }`. It runs forever
  until process exit.

## Data contract

The two archive JSONLs at `~/.tokade/history/` are a durable user contract:

- `events.jsonl` — one `ArchivedEvent` per line. Compact field names
  (`t`, `m`, `i`, `cc`, `cr`, `o`, `s`, `id`, `cwd`, `tools`, `cmd`) to
  keep file size manageable.
- `snapshots.jsonl` — one `UsageSnapshot` per line. Records the server's
  reported `%` over time so the Past 5h Windows chart can plot real
  history once accumulated.

Schema changes to either file require an ADR (`docs/adr/`).

## Cross-references

- [`CLAUDE.md`](../../CLAUDE.md) — enforceable rules + their hooks
- [`docs/adr/`](../adr/) — ADRs for non-obvious decisions
- [`.productionize-me/AUDIT.md`](../../.productionize-me/AUDIT.md) — current
  state vs Tier 2 target
- [`.productionize-me/PLAN.md`](../../.productionize-me/PLAN.md) —
  prioritized roadmap
