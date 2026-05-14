# Changelog

All notable changes to Tokade are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows [semver](https://semver.org/).

## [Unreleased]

### Added

- **Token Gaiden tab (M0 foundation).** New tab in the Tokade panel that
  houses a small RPG fed by Claude Code telemetry. v1 foundation lands the
  character creator (6 skin × 6 iris × 6 hair-color × 11 hair-style), the
  matrix-runtime sprite system (32×54 source res, role-parameterized
  palette), the `TickProcessor` (token → HP drain, token → age advance,
  tool → themed item drop, slash command → SP potion), persistent save at
  `~/.tokade/games/tokegotchi.json` (0600), and the live sprite view with
  idle-walk-A-walk-B animation cycle. Encounters, regions, quests, combat,
  and the death/inheritance loop land in subsequent PRs. See
  `docs/02-design/TOKADE_TAB.md`.
- **Cosmetic composition.** Bundled 14 cosmetic matrices (7 hair styles, 1
  shirt, 2 pants, 1 belt, 3 hats) layered over a "naked" base sprite at
  runtime via `SpriteComposer`. The hair style chosen at character
  creation is applied to the rendered sprite. A Wardrobe sheet lets the
  player swap cosmetic slots live; choices persist.
- **Region tracking (Layer 3 foundation).** Each Claude Code `cwd` maps
  to a stable region identifier (home-relative path) seeded with a flavor
  on first visit by sniffing project marker files (Swift → Stonework
  Town, Rust → Iron Fortress, Python → Garden Village, JS/TS → Bazaar,
  Go → Open Steppe, unknown → Wilderness). Per-region event counter
  drives reputation (+1 per 50 events, cap 100). Current region + flavor
  + reputation surface in the Token Gaiden tab. Region-discovery
  thresholds, NPCs, shops, and fast-travel land in subsequent PRs.
- 22 XCTest cases covering matrix parsing, palette role resolution,
  Tokegotchi state derivation, TickProcessor model/tool mapping, and
  TokenGaidenStore tick idempotence.

### Changed

- `appBundledResource(_:ext:)` is now module-internal (was private) so the
  Token Gaiden code can use the same Bundle.module workaround pattern.
- `.swiftformat` excludes `design/` — the design folder's helper Swift
  scripts (`pixelate.swift`, `bake.swift`, `render_matrix.swift`) are
  authoring tools, not app code.

## [0.3.0] — 2026-05-13

The M2 release. Perf + accessibility + repo-surface upgrades. No
user-visible feature changes beyond the colorblind-friendly shape glyphs.

### Added

- **Incremental JSONL parsing.** Per-file mtime cache; steady-state polls
  re-parse zero files instead of all of them. Big perf win for users with
  many historical session JSONLs.
- **Shape glyphs per model tier** (Haiku ●, Sonnet ■, Opus ▲, other ◆) in
  legends and tooltips. Second visual channel for colorblind users since
  the palette is blue-family.
- **VoiceOver labels** on every `BarMark` / `RectangleMark` across Models
  tab, Past 5h windows, and Window skills. Line/area marks deliberately
  not labeled — they're continuous; chart-level summaries are M3 work.
- **`.swiftformat` config** (conservative ruleset) + CI lint step
- **README screenshots** of each tab (Budget / Models / Trends)
- **README Roadmap section** linking the public Projects v2 board
- **README Questions section** pointing to GitHub Discussions
- **`.github/CODEOWNERS`** (`* @bjamba`)
- **Xcode 15.4 pin** on CI + Release workflows
- **CONTRIBUTING.md** Roadmap + code-style sections
- **GitHub Discussions** enabled
- **Public Projects v2 board** "Tokade Roadmap" with all open issues attached

## [0.2.0] — 2026-05-13

The "productionize-me" release. No user-facing feature changes beyond the
Erase-history button and the Claude-Code-not-detected banner; the rest of
the work is infrastructure that makes the project safe to contribute to
and easier to maintain.

### Added

- **Tests**: 32 XCTest cases covering the math that drives every chart —
  JSONL parsing, sequence aggregations, model-tier palette, 5h-window
  projection, and archive file permissions
- **CI**: GitHub Actions workflow runs `swift build -c release`,
  `swift test`, and `scripts/check.sh` on every PR and on `main`
- **Release pipeline**: pushing a `v*` tag builds `Tokade.app`, zips it,
  and attaches the zip + sha256 to a GitHub Release with auto-generated
  notes
- **Guardrails** (`scripts/check.sh` + `.pre-commit-config.yaml`): no
  `Bundle.module` outside `SharedComponents.swift`, no network primitives
  in `Sources/`, chart-stability modifiers stay in `StatsView.swift`,
  every chart-driving `Models.swift` function has a test, archive sources
  set `0o600`, no LLM-attribution noise in source/docs
- **Documentation**: `CONTRIBUTING.md`, `docs/02-design/ARCHITECTURE.md`,
  four ADRs covering server-`%`-as-truth, `Bundle.module` workaround,
  fixed bar thickness, ad-hoc codesigning
- **Issue/PR templates**: structured Issue Forms (bug + feature),
  PR template with guardrail checklist, `SECURITY.md` with private
  vulnerability reporting
- **Privacy hardening**: `0600` permissions on `~/.tokade/history/*`,
  "Erase history…" menu action with confirmation dialog, expanded
  Privacy section in README
- **Reliability**: `os_log` warnings at I/O boundaries (silent `try?`
  paths replaced); friendly banner when `~/.claude/projects/` is missing
- **`CLAUDE.md`**: enforceable rules paired 1:1 with their hooks/CI/script
  enforcement and threaded back to `.productionize-me/AUDIT.md` findings
- **README badges** for CI, latest Release, and license

## [0.1.0] — 2026-05-11

Initial public release. Path: `github.com/bjamba/tokade`.

### Added

- macOS menu bar app reading Claude Code's local session logs and
  statusline JSON
- Budget tab — current 5h window utilization, on-pace reference line,
  projection wedge, past 5h windows history
- Models tab — tokens by model, top 5 slash commands / projects /
  tool calls, all broken down by model
- Trends tab — all-time weekday × hour heatmap, YTD cumulative with
  linear projection
- Persistent local archive at `~/.tokade/history/{events,snapshots}.jsonl`
- Statusline shim + installer
- MIT license, README, AppIcon + menu bar template glyph

[Unreleased]: https://github.com/bjamba/tokade/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/bjamba/tokade/releases/tag/v0.3.0
[0.2.0]: https://github.com/bjamba/tokade/releases/tag/v0.2.0
[0.1.0]: https://github.com/bjamba/tokade/releases/tag/v0.1.0
