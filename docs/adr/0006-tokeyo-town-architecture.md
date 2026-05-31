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

> **Superseded.** The ratios above are the original v1 design. The
> shipped economy is documented in "Revision: economy v3.x" at the end of
> this ADR — coin still mints at 1 / 1,000 tokens (in-repo only), but tool
> credits are now 1-per-call and `stability` / `inspiration` are retired.

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

## v2 Addendum (2026-05-20)

After playing the v1 MVP, several decisions were revisited. This addendum
supersedes the corresponding sections above; the original text is
preserved for historical context.

### A1. Save schema bumped to v2

`schemaVersion: 2`. Adds:
- `terrain: TerrainGrid` — per-tile landscape state.
- `PlacedBuilding.width` / `height` — explicit footprint per placed instance (defaults to 1 when decoding v1 saves).
- `Townsfolk.homeBuildingId`, `pauseRemaining`, `activity` — needed by the new AI.

Decoder falls back gracefully on v1 saves: terrain is regenerated from the townId seed (deterministic, same townId → same terrain).

### A2. Procedural terrain layer

The map is now generated from value noise seeded by `townId`. Per-tile classification varies by biome:

| Biome  | Water     | Sand       | Grass    | Rock      | Tree     | Flower    |
|--------|-----------|------------|----------|-----------|----------|-----------|
| Beach  | low elev  | shoreline  | upland   | —         | sparse   | scattered |
| Desert | rare      | dominant   | —        | high elev | oasis    | rare      |
| Tundra | frozen    | —          | most     | high elev | sparse   | —         |
| Forest | rare      | —          | clearings| high elev | dominant | edges     |
| Plain  | rare      | —          | dominant | high elev | sparse   | scattered |

Buildings may only sit on `grass` (always) and `sand` (beach/desert only). Trees, rocks, and water block placement until terraformed (see A4).

### A3. Building shapes are procedural recipes

`BuildingShape` is a composable stack of iso-prism primitives:
- `Story` — base prism with width, depth, height, inset, wall + trim color
- `Roof` — `flat` / `gable(axis, height, color)` / `hip(height, color)` / `dome(height, color)`
- `Ornament` — optional chimney, spire, or annex
- `accent` — optional door rectangle on the front face

`BuildingCatalog` ships one recipe per building. The renderer draws the recipe directly — no glyph on the world, no sprite assets. Footprints are 1×1 (most) or 2×1 / 2×2 (landmarks: library, pyramid, aquarium, pier, bridge, school, etc.).

### A4. Roads and terraforming

New tools on the store, exposed in the sidebar:

| Tool         | Effect                                  | Cost          | Refund    |
|--------------|------------------------------------------|---------------|-----------|
| Road         | grass/sand/flower → road                | 4 coin/tile   | —         |
| Plant Tree   | grass → tree                            | 6 lumber      | —         |
| Clear Tree   | tree → grass                            | 8 coin        | 4 lumber  |
| Level Rock   | rock → grass                            | 10 industry   | —         |
| Plant Flower | grass → flower                          | 3 growth      | —         |
| Lantern      | grass → decor (lantern)                 | 12 coin       | —         |
| Hand         | demolish building / clear flower-or-decor | —           | —         |

Roads are tile decorations (not buildings) and contribute to townsfolk pathing — see A6.

### A5. Variable footprints + placement validation

`canPlaceBuilding(_, at:)`:
1. Footprint must be inside the map.
2. Every tile in the footprint must be on an allowed terrain kind for the biome (grass + sand for beach/desert; grass for others).
3. No overlap with any other placed building's footprint.
4. Player must be able to afford the building's `cost`.

The renderer draws a translucent preview at the hovered tile with a red overlay when the placement is invalid.

### A6. Townsfolk AI with home + errands + road preference

Each tick:
1. If paused, decrement `pauseRemaining`.
2. Else if `atGoal`, pick a new errand:
   - Homeless → wander to a random walkable tile.
   - At home → head to a random non-home building.
   - Elsewhere → head home.
   With `pauseChance` (85% default), pause for 3–10 in-game seconds before picking the next goal.
3. Else step toward the goal: pick the 4-neighbor with the lowest `Manhattan distance + 0.04 × tile.pathCost`. Roads cost 1, grass 3, trees 6 — so townsfolk prefer roads when scores are close, without being forced to use them.

When a "home" building (cottage, adobe home, log cabin, tree house, mushroom hut, pastel cottage) is placed, the spawner assigns it to the first homeless townsfolk and 50% of the time spawns a newcomer who immediately moves into it.

### A7. Resource rebalance

After v1 playtesting showed coin dominating every other resource:

| Resource    | v1 ratio          | v2 ratio              |
|-------------|-------------------|-----------------------|
| Coin        | 1 / 1,000 tokens  | **1 / 4,000 tokens**  |
| Knowledge   | 1 / 5 reads       | **1 / 10 reads**      |
| Lumber      | 1 / 3 edits       | unchanged             |
| Industry    | 1 / 5 bashes      | **1 / 8 bashes**      |
| Stability   | 1 / 25 bashes     | **1 / 40 bashes**     |
| Inspiration | 1 / slash command | unchanged             |
| Growth      | 1 / session       | unchanged             |

Building costs were bumped roughly 2-3×. Major (2×2) buildings now require *multiple* scarce resources, not just lots of coin — enforced by the `testMajorBuildingsHaveMultiResourceCosts` test.

### A8. Camera + tile size

Tile half-width scales with map size: bigger tiles for small towns (12-tile maps get 34px tiles), smaller tiles for huge maps. The map-size formula now floors at 12 (was 16) and caps at 48 (was 64), so the canvas is full at every scale.

## v3 Addendum (2026-05-20 — second iteration)

After v2 playtesting, another set of decisions was revisited:

### B1. Townsfolk move strictly cardinally on screen

Townsfolk state now tracks `(tileX, tileY)` *and* `nextStepX/Y`. The AI commits to a single 4-cardinal neighbor per tick; the renderer interpolates only between `(tileX, tileY)` and `nextStep`. The ultimate `goalX/Y` is never used as a renderer target, eliminating diagonal motion across the board.

The AI also rejects steps with elevation deltas > 1 — townsfolk can climb a cliff one tier high but not jump up a mountain.

### B2. Undo / redo

`TokeyoTownStore` keeps two `[TokeyoTownState]` stacks capped at 50 entries each. Every player action (build, demolish, road, terraform, raise, lower) calls `snapshot()` *before* mutating, pushes the prior state onto the undo stack, and clears redo. `undo()` / `redo()` swap states through the stacks. Header has ↶ / ↷ buttons that disable when their stack is empty.

### B3. Building badge

Each building draws a small white-filled circle with a colored ring at the building's base, with the catalog glyph inside it — the silhouette stays clean (so cottages look like cottages) but the meaning is recoverable at a glance. Badge color comes from the biome's accent.

### B4. Per-tile sub-detail

Grass tiles get 3 small green strokes; sand tiles get 2 short ripple arcs. Both seeded by `townId ⊕ tile coords` so the variation is stable per town and lifelike, not noisy.

### B5. Zoom + pan

`IsoMath.ViewTransform { zoom, panX, panY }` plumbed through all projection. Three discrete zoom levels (0.75 / 1.0 / 1.5). Header has − / + / recenter buttons. A 🖐 toggle puts the canvas in pan mode — drags then move the camera instead of placing tiles. Tap-then-release with movement < 4px still applies the tool.

### B6. Road autotiling with sidewalks

Roads are no longer the whole tile. Each road tile draws two thin diamonds (NS strip + EW strip), each with a slightly-wider sidewalk underlay. Strip endpoints extend to the tile edge in directions that connect, otherwise stop short — naturally producing straights, curves, Ts, crosses, and dead-ends without enumerating sprite variants. Adjacent buildings count as connections, so roads visibly meet building edges. Straight tiles get a center dash.

### B7. More home variants per biome

Each biome now has 9 buildings (was 8): the original set plus one new home variant. Plain gets a row house, desert a yurt, tundra a stone lodge, forest a forest cabin, beach a bungalow. `BuildingCatalog.Building` now carries an `isHome: Bool` flag — the store no longer hardcodes which ids are homes, and `testEveryBiomeHasMultipleHomeVariants` ensures at least 2 per biome going forward.

### B8. Pier must touch water

`canPlaceBuilding` now rejects `beach-pier` unless at least one tile in the footprint is orthogonally adjacent to a `.water` tile. Other water-adjacent buildings can be added to `waterAdjacentBuildings` in the store.

### B9. Terrain elevation tiers + raise/lower tools

Per-tile `elevation: Int8` in `[-1, 2]`:
- -1 = underwater (sits below the 0-plane; tile rendered as water)
-  0 = ground
-  1 = hill
-  2 = mountain peak (auto-converts to a `rock` tile)

The renderer lifts each tile diamond by `elev × stepHeight × zoom` and draws side cliff faces between this tile and its south/east neighbors when elevation drops. `canBuild` requires every tile in a footprint share elevation (buildings need flat ground).

New tools `raise` (industry 6) and `lower` (industry 6) bump elevation one tier per click. Tier transitions auto-flip terrain kind: lower to -1 becomes water; raise to 2 becomes rock.

All elevation changes go through the same undo/redo stack, so #B2 covers #9 reversibility for free.

## Revision: economy v3.x (2026-05-31)

This revision is **canonical** for the flow-resource economy and
supersedes §5 and the v2 addendum's §A7 ratio table. It documents what
the code in `ResourceAccrual.swift` actually ships, after several
playtest iterations (v3.6–v3.8) drifted away from the earlier spec. No
balance is changed by this revision; it only reconciles the docs and the
in-file comments with the shipped behavior (issue #40).

**Shipped flow economy:**

| Resource | Source | Conversion |
|---|---|---|
| 💰 Coin | Tokens spent on **in-repo** events | 1 coin / 1,000 tokens |
| 📜 Knowledge | `Read` tool calls | 1 knowledge / read |
| 🔨 Lumber | `Edit` / `Write` tool calls | 1 lumber / edit |
| ⚙️ Industry | `Bash` tool calls | 1 industry / bash |
| 🌱 Growth | Distinct sessions seen | 1 growth / session |
| 🛡️ Stability | — | **RETIRED** (always 0) |
| ✨ Inspiration | — | **RETIRED** (always 0) |

Notes:

- **In-repo gating (issue #31).** Only events whose `cwd` is the town's
  repo (or nested inside it) fund the town. Out-of-repo usage still
  advances the high-water mark so it isn't reprocessed, but grants
  nothing.
- **Tool credits are 1-per-call.** `normalize` no longer divides; the old
  divisor ratios (1/10 reads, 1/3 edits, 1/8 bashes, etc.) are gone. Tool
  calls occur far less often than tokens accumulate, so a 1:1 ratio keeps
  the tool-resource pool from being a perpetual bottleneck while coin
  keeps pace via tokens.
- **`stability` and `inspiration` are retired.** They earned too rarely to
  matter and added UI noise; their building costs were folded into
  industry/knowledge. `ResourceAccrual.normalize` force-zeros both, and
  neither is displayed. The fields **remain** on
  `TokeyoTownState.Resources` (and in the save schema) so existing saves
  decode unchanged — they are simply always zero going forward. The test
  `testAccrualDoesNotAccrueRetiredResources` locks this in.
- **Active-session bonus (§6) still applies** as a 2× multiplier on tool
  credits when the active session's `cwd` is in the town's repo.

## Threading to CLAUDE.md

This ADR introduces one new rule and reuses three existing ones:

- **NEW**: `~/.tokade/games/tokeyotown/*.json` must be written with `0o600`.
  Enforced by `scripts/check.sh` grep for `0o600` in
  `Sources/Tokade/TokeyoTown/TokeyoTownSave.swift`.
- **REUSE**: No network code (existing rule). Repo scanning is local-only.
- **REUSE**: No LLM-attribution noise (existing rule).
- **REUSE**: Never call `Bundle.module` (existing rule). Asset loading
  goes through `appBundledResource`.
