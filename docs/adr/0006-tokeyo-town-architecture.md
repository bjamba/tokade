# ADR 0006 — Tokeyo Town architecture

- **Status**: Accepted (design — implementation in progress on `feature/tokeyo-town`)
- **Date**: 2026-05-20
- **Deciders**: @bjamba
- **Tracking issue**: [#26](https://github.com/bjamba/tokade/issues/26)

## Terminology

- **Tokade** — the macOS menu bar app.
- **Arcade tab** — the Games tab that hosts our games (already exists, currently has Token Gaiden).
- **Tokeyo Town** — the v2 game inside the Arcade tab. The subject of this ADR.
- **Town** — a single persistent save tied to one user-selected local repo.
- **Biome** — visual theme of a town (plain, desert, tundra, forest, beach), derived from the repo's primary language.

## Context

Tokeyo Town is the second game in the Arcade tab. Cozy isometric sandbox
city-builder: pick a local repo, get a procedurally-themed town, place
buildings, watch townsfolk wander. Resources flow from Claude Code usage;
terrain and unlocks come from local codebase analysis. No win condition,
no urgency.

This ADR captures the architectural decisions that need to be locked
before code lands. The rest is mechanical.

## Decisions

### 1. The Tokegotchi separation is total

Tokeyo Town shares **zero** runtime state with Token Gaiden. They sit in
separate folders (`Sources/Tokade/TokeyoTown/`), have separate stores
(`TokeyoTownStore` sibling of `TokenGaidenStore`), separate save files
(`~/.tokade/games/tokeyotown/` vs `~/.tokade/games/tokegotchi.json`), and
separate tick processors.

Reasoning: Token Gaiden is an RPG with combat, death, and inheritance.
Tokeyo Town is a sandbox with no failure state. Cross-pollination would
force one to compromise for the other. The shared surface is the Arcade
tab's `GamesTab` launcher and the `UsageStore` event feed (read-only).

### 2. One town per repo, one repo per town, one town total in MVP

The user picks a single local folder. The folder's resolved path is hashed
(SHA-256, first 16 hex chars) to derive a stable `townId`. The save lives
at `~/.tokade/games/tokeyotown/<townId>.json`. An `index.json` maps
townIds → (display name, repo path, last opened).

MVP allows only **one active town at a time**. Starting a new town
replaces the existing one (with explicit confirmation — the old save is
not silently deleted; it's moved to `~/.tokade/games/tokeyotown/archive/`
in case the user changes their mind).

Multi-town comes later. The schema (per-town files + index) is forward-
compatible with the multi-town world; we just don't expose multiple in
the UI for MVP.

### 3. Repo scanning is 100% local and read-only

The `RepoScanner` only ever:
- Reads file extensions in the chosen folder (recursively, bounded depth)
- Reads `.git/` metadata via `git log` / `git shortlog --summary` shelled
  out, never any plumbing that could mutate state
- Counts LOC by line-counting files matching known source extensions
- Never reads file *contents* beyond LOC counting

It **never** makes network calls and **never** invokes Claude. This is
the architectural contract that lets us claim "no extra credits" for
scanning, and it's enforced by the existing "no network code"
`scripts/check.sh` rule that already grep-blocks `URLSession` et al.

### 4. Biome derived from primary language; era from repo age

```
Primary language (by LOC):     →  Biome
  Swift / Kotlin / Dart            beach
  Rust / C / C++ / Zig             tundra
  Python / Ruby / R                forest
  JS / TS / HTML / CSS             plain
  Go / Java / C# / PHP             desert
  (mixed / unrecognized)           plain
```

```
Repo age (days since first commit):  →  Era visual
  < 90                                  modern/futuristic
  90 – 730                              contemporary
  > 730                                 classical/aged
```

Biome determines tile palette, available buildings (each biome has 8),
and townsfolk theming. Era is a visual overlay (building variants — e.g.
ancient vs. modern shop sprite).

### 5. Resource model — two streams

**Flow resources** (regenerate from Claude usage, consumed when placing buildings):

| Resource | Source | Conversion |
|---|---|---|
| 💰 Coin | Tokens spent | 1 coin / 1,000 tokens |
| 📜 Knowledge | `Read` tool uses | 1 knowledge / 5 reads |
| 🔨 Lumber | `Edit` / `Write` tool uses | 1 lumber / 3 edits |
| ⚙️ Industry | `Bash` tool uses | 1 industry / 5 bashes |
| 🛡️ Stability | Test runs (bash containing `swift test`, `npm test`, `pytest`, `go test`) | 1 stability / 1 test run |
| ✨ Inspiration | Slash commands | 1 inspiration / 1 slash command |
| 🌱 Growth | Sessions ended | 1 growth / 1 session |

**Terrain resources** (one-time at town creation, recomputed only on full rescan):

- `mapSize` — `min(64, max(16, sqrt(LOC/100)))` tiles square
- `npcSeedCount` — number of contributors from `git shortlog -sn`, capped at 12
- `lushness` — recent commit cadence (commits in last 30 days), 0..1
- `availableBuildings` — `BiomeCatalog.buildings(for: biome)`

### 6. Active-session bonus

When the Claude Code statusline JSON reports a current session whose `cwd`
matches the town's repo root (or any subdirectory), the town gets a 2× resource
multiplier on incoming events for that session's duration. Implementation:
`ResourceAccrual.multiplier(forSession:against:)` returns 2.0 if
`session.cwd.starts(with: town.repoPath)`, else 1.0.

### 7. Tick rate is two-mode

- **Foreground tick** (Arcade tab visible, Tokeyo Town selected):
  60 Hz animation loop via `TimelineView(.animation)`. Townsfolk
  positions interpolated each frame.
- **Background tick** (tab not visible): integrated with the existing
  `UsageStore` refresh tick (~once per minute). Resources accrue;
  townsfolk teleport to their next path waypoint instead of animating.

Save writes are debounced — at most once per 5 seconds, always on tab
exit, always on explicit user action (place building, start new town).

### 8. Persistence file format (v1)

```json
{
  "schemaVersion": 1,
  "townId": "a1b2c3d4...",
  "createdAt": "2026-05-20T04:51:21Z",
  "lastTickAt": "2026-05-20T05:12:00Z",
  "repo": {
    "path": "/Users/bjamba/code/github/bjamba/tokade",
    "displayName": "tokade",
    "scannedAt": "2026-05-20T04:51:21Z",
    "primaryLanguage": "swift",
    "biome": "beach",
    "era": "contemporary",
    "ageInDays": 7,
    "loc": 12480,
    "mapSize": 32,
    "contributorCount": 1,
    "lushness": 0.83
  },
  "resources": {
    "coin": 142,
    "knowledge": 31,
    "lumber": 87,
    "industry": 12,
    "stability": 5,
    "inspiration": 2,
    "growth": 18
  },
  "accountedEvents": {
    "lastEventId": "abc123",
    "lastTimestamp": "2026-05-20T05:11:55Z"
  },
  "buildings": [
    { "id": "uuid", "kind": "cottage", "tile": [4, 7], "placedAt": "..." }
  ],
  "townsfolk": [
    { "id": "uuid", "name": "Akira", "tile": [4, 7], "goalTile": [10, 11], "createdAt": "..." }
  ]
}
```

Writes are atomic (tmp + replace) with `0o600` perms, matching the
TokegotchiSave pattern. A new CLAUDE.md guardrail rule + `scripts/check.sh`
grep will enforce the perm.

### 9. Sprites: procedural placeholders for MVP, Kenney.nl swap later

MVP ships with procedural tile rendering (SwiftUI `Canvas` drawing
solid-color isometric diamonds with biome-specific palettes). Buildings
render as colored truncated pyramids with a name label. Townsfolk render
as moving 4-px circles.

This lets the entire engine + UX + data flow land without blocking on
art. The renderer abstraction (`IsoTileRenderer`) accepts a `Sprite`
protocol; the procedural impl is one conformer, a future Kenney-backed
impl is another.

Asset packs slated for swap (later milestones):
- [Kenney Isometric City](https://kenney.nl/assets/isometric-city) — CC0
- [Kenney Isometric Tiles](https://kenney.nl/assets/isometric-tiles) — CC0
- [Kenney City Builder](https://kenney.nl/assets/city-builder) — CC0

`docs/THIRD_PARTY.md` will credit Kenney once we ship art. CC0 doesn't
require attribution, but we're being polite.

## Out of scope for MVP

Tracked in issue #26 sub-tasks slated for later versions:

- Events (festivals, parades, fireworks)
- Seasons / weather variants beyond static lushness
- Townsfolk needs surfacing suggestion prompts
- Multi-town
- Custom pixel art replacing Kenney/procedural placeholders
- Roads / rivers as first-class objects
- Quests tied to GitHub issues/PRs

## Threading to CLAUDE.md

This ADR introduces one new rule and reuses three existing ones:

- **NEW**: `~/.tokade/games/tokeyotown/*.json` must be written with `0o600`.
  Enforced by `scripts/check.sh` grep for `0o600` in
  `Sources/Tokade/TokeyoTown/TokeyoTownSave.swift`.
- **REUSE**: No network code (existing rule). Repo scanning is local-only.
- **REUSE**: No LLM-attribution noise (existing rule).
- **REUSE**: Never call `Bundle.module` (existing rule). Asset loading
  goes through `appBundledResource`.
