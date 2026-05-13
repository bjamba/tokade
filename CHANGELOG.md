# Changelog

All notable changes to Tokade are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows [semver](https://semver.org/).

## [Unreleased]

### Added

- Productionize-me M0: tests, CI, guardrails, templates, `CLAUDE.md`,
  `.productionize-me/` artifacts (see PR #11)
- Productionize-me M1: documentation foundation — `CONTRIBUTING.md`,
  ADRs for non-obvious decisions, `docs/02-design/ARCHITECTURE.md`,
  expanded Privacy section in README, README badges
- 0600 permissions on `~/.tokade/history/*.jsonl`
- "Erase history…" action in the menu bar panel footer
- `os_log` warnings at file I/O boundaries (silent `try?` paths replaced)
- Friendly banner when `~/.claude/projects/` is missing
- Release workflow: pushing a `v*` tag builds `Tokade.app` and attaches
  it to a GitHub Release

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

[Unreleased]: https://github.com/bjamba/tokade/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/bjamba/tokade/releases/tag/v0.1.0
