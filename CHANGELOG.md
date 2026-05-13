# Changelog

All notable changes to Tokade are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows [semver](https://semver.org/).

## [Unreleased]

### Added

- `.swiftformat` config (conservative ruleset) + CI lint step
- README screenshots for each tab (Budget / Models / Trends)
- README Roadmap section linking to the public Projects v2 board
- README Questions section pointing to GitHub Discussions
- `.github/CODEOWNERS` (single-line, `* @bjamba`)
- Xcode 15.4 pin on both CI and Release workflows so an Apple update can't
  silently change Swift semantics
- CONTRIBUTING.md Roadmap subsection documenting board column semantics
- Discussions enabled at the repo level
- Public Projects v2 board "Tokade Roadmap" with all open issues attached

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

[Unreleased]: https://github.com/bjamba/tokade/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/bjamba/tokade/releases/tag/v0.2.0
[0.1.0]: https://github.com/bjamba/tokade/releases/tag/v0.1.0
