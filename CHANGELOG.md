# Changelog

All notable changes to Tokade are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows [semver](https://semver.org/).

## [Unreleased]

## [0.5.0] — 2026-05-22

### Added

- **Tokeyo Town** — the second Arcade game. Cozy isometric sandbox
  city-builder themed after a real local repo. Players pick a folder;
  the scanner derives biome from the primary language
  (Swift/Kotlin/Dart → beach, Rust/C/C++/Zig → tundra,
  Python/Ruby/R → forest, JS/TS → plain, Go/Java/C# → desert), era
  from repo age, map size from LOC, lushness from recent commit
  cadence, and a starter cluster of buildings + roads + townsfolk
  from repo signals (tests/, docs/, README, CI files). Subsequent
  resources accrue from live Claude Code usage (tokens → coin, reads
  → knowledge, edits → lumber, bashes → industry, sessions →
  growth). 100% local — no Claude calls, no network requests for
  scanning (enforced by `scripts/check.sh`).

  Headline features:
  - 5 biomes × 9 buildings (45 catalog) with composable shape recipes
    (stories + roof type + ornament + detail) and footprints 1×1
    through 3×3.
  - Procedural terrain: water, sand, grass, rock, trees, flowers,
    elevation tiers (-1 underwater through +4 mountain), seeded by
    townId so the same repo always grows the same landscape.
  - Townsfolk with full appearance variation (hat / skin / hair /
    age / pattern), walk animation, and proper A\* pathing between
    buildings (preferring roads via tile pathCost weighting).
  - Real-time **day / night cycle** tied to wall clock — lanterns
    glow at night, stars appear, ground darkens uniformly. Toggle for
    forced day / forced night.
  - Tools sidebar: Remove (universal, with refunds), Pan, Road,
    Tree, Flower, Lantern, Pond, Raise, Lower.
  - 50-action Undo / Redo stack.
  - 5 discrete zoom levels (0.5×–2.0×), drag-pan, click-to-cycle
    label modes (icon / name / none) and CRT effect (5 modes).
  - Population grows with buildings (cap = `buildings + 2`); each
    townsfolk costs 1 coin/tick upkeep. If you can't pay, townsfolk
    leave town.
  - Resource trading: spend coin to buy +1 of any other resource at
    published rates.
  - Building-to-building tap-to-place with hover highlight; pier must
    straddle land and water; no road on peaks; raise/lower locked out
    of road tiles.
- **Both Arcade banners redesigned** with procedural SwiftUI:
  - Token Gaiden RPG: Conan-style fantasy — jagged mountains,
    crossed swords, heavy serif title.
  - Tokeyo Town: night-sunset cityscape silhouette with lit
    skyscrapers and clean sans-serif title.
  - Both topped with a thin CRT scanline + vignette overlay.
- **Token Gaiden** got a small `← Arcade` back button at the top of
  every screen, matching Tokeyo Town's idiom.

### Changed

- `CFBundleShortVersionString` → 0.5.0, `CFBundleVersion` → 7.

## [Tokeyo Town iteration log — pre-merge work referenced from v0.5.0]

Documented for posterity; the work above was iterated across ~25
commits on `feature/tokeyo-town-v2` (squash-merged via #28). The
following sections describe the design path.

### Changed (Tokeyo Town v3 — second iteration on the v1 MVP)

- **Cardinal-only townsfolk movement**. The renderer used to interpolate npc position toward the *ultimate goal*, producing visible diagonal motion. AI now commits to a single cardinal `nextStep`; renderer interpolates only between current and next, so motion is strictly N/E/S/W.
- **Undo + redo** (cap 50). Every player action (build, demolish, road, terraform, raise, lower) snapshots state first. Buttons in the header.
- **Building badges**. Small white-and-color circle with the catalog glyph drawn beside each building — silhouette stays clean, meaning stays readable.
- **Per-tile sub-detail**. Grass tiles get 3 tiny green strokes; sand tiles get 2 short ripple arcs. Seeded by `townId ⊕ tile coords` so variation is stable per town.
- **Zoom + pan**. Discrete zoom (0.75 / 1.0 / 1.5). Pan toggle in the header — when on, drags move the camera; off, drags hover/place.
- **Roads look like roads now**. Narrow asphalt strip with a sidewalk underlay; neighbor-aware so straights, curves, Ts, crosses, and dead-ends emerge automatically. Roads extend into adjacent building edges. Straight tiles get a center dash.
- **More home variants** — each biome now has 9 buildings (was 8): added Row House (plain), Yurt (desert), Stone Lodge (tundra), Forest Cabin (forest), Bungalow (beach). `Building.isHome` flag replaces hardcoded id lists.
- **Pier must touch water** — `canPlaceBuilding` rejects `beach-pier` unless a footprint tile is orthogonally adjacent to water.
- **Terrain elevation** in tiers (-1 / 0 / 1 / 2). Renderer lifts tiles + draws cliff side-faces. `canBuild` requires flat footprints. New tools: ⛰ Raise / 🕳 Lower (industry 6 each).
- **Universal removal tool** — Hand is now Remove and also clears road / flower / decor (not just buildings).

### Changed (Tokeyo Town v2 — major overhaul of the v1 MVP)

- **Save schema → v2**. Adds `terrain`, footprint fields on placed buildings, and AI fields on townsfolk. v1 saves decode cleanly — terrain regenerates from the (deterministic) townId seed.
- **Procedural terrain**. Every town now has water, sand, grass, rock, trees, and flowers generated from value noise seeded by townId. Per-biome thresholds; same repo → same landscape every time. Buildings can only sit on grass (and sand, for beach/desert).
- **Building shapes are drawn, not stickered**. Replaced the glyph-on-a-brick rendering with a composable shape system: stacked iso prisms + roof types (flat/gable/hip/dome) + optional ornaments (chimneys, spires, annexes). Cottages look like cottages, lighthouses look like lighthouses.
- **Variable footprints (1×1, 2×1, 2×2)**. Landmarks (library, pyramid, aquarium, pier, bridge, school, …) now take more tiles and demand multiple scarce resources, not just coin.
- **Roads + terraforming** as a tool sidebar: road / plant tree / clear tree / level rock / plant flower / lantern. Roads cost 4 coin/tile, clearing a tree returns lumber, leveling a rock costs industry, etc.
- **Townsfolk actually do things now**. Each gets a home building, errands (random non-home destinations), pauses 3-10s at each destination, then heads home. Pathing biases toward road tiles so streets feel used.
- **Resource rebalance** based on v1 playtesting:
  - Coin: 1 / 1,000 tokens → **1 / 4,000 tokens** (tokens were dominating)
  - Knowledge: 1 / 5 reads → **1 / 10 reads**
  - Industry: 1 / 5 bashes → **1 / 8 bashes**
  - Stability: 1 / 25 → **1 / 40 bashes**
  - Building costs bumped 2-3×; major buildings require ≥2 distinct scarce resources.
- **Zoom + camera**. Tile sizes scale with map size so small towns fill the canvas. Map-size formula floors at 12 (was 16) and caps at 48 (was 64).
- **ADR-0006 addendum** captures every architectural decision above.

### Added (v1 — landed in the previous commit)

- **Tokeyo Town** — a second game in the Arcade tab. Cozy isometric
  sandbox city-builder where each town is themed after a real local
  repo on your machine. Pick a folder; the scanner derives biome
  (Swift/Kotlin/Dart → beach, Rust/C → tundra, Python/Ruby → forest,
  JS/TS → plain, Go/Java/C# → desert), era from repo age, and map size
  from LOC. Place buildings from a per-biome catalog (8 buildings per
  biome × 5 biomes = 40 total) that cost resources accrued from your
  Claude Code usage:
  - 💰 coin from tokens (1 / 1,000)
  - 📜 knowledge from `Read` calls (1 / 5)
  - 🔨 lumber from `Edit`/`Write` (1 / 3)
  - ⚙️ industry from `Bash` (1 / 5)
  - 🛡 stability from heavy bashing (1 / 25)
  - ✨ inspiration from slash commands (1 / 1)
  - 🌱 growth from sessions (1 / 1)
- **Active-session bonus** — when the most recent Claude Code session
  is working inside the town's repo, that town earns at 2× while the
  session is active. ADR-0006 §6.
- **Townsfolk** wander autonomously across the iso grid, with names
  drawn from a per-biome pool. New townsfolk chance-spawn when you
  place new buildings.
- **One-town MVP**. Starting a new town archives the previous save to
  `~/.tokade/games/tokeyotown/archive/` rather than deleting it.
- **100% local repo scanning**. No Claude calls, no network requests —
  enforced by `scripts/check.sh` grep over `Sources/Tokade/TokeyoTown/`.
- Procedural placeholder sprites for MVP (colored isometric diamonds +
  glyph labels). Kenney.nl CC0 packs are the planned upgrade — the
  renderer is structured so swapping in real sprites doesn't touch the
  game logic.
- ADR-0006: Tokeyo Town architecture (`docs/adr/0006-tokeyo-town-architecture.md`).
- 18 new tests in `TokeyoTownTests` covering biome mapping, resource
  accrual, idempotent ticking, iso-math round trip, and building
  catalog drift guards.

## [0.4.2] — 2026-05-18

### Fixed

- **Wardrobe was missing four hair styles** (bald / flame / mushroom /
  tentacles). They were selectable at hatch in the character creator and
  the sprite matrices were baked + bundled, but `CosmeticCatalog`'s hair
  slot only listed seven of the eleven styles, so the wardrobe carousel
  silently dropped them. All eleven styles now appear and are starter
  cosmetics (matching the existing pattern — hair is chosen at hatch).
- New `CosmeticCatalogTests` guard against future drift in both
  directions (hatch ⇄ catalog hair-style parity).
- `CFBundleShortVersionString` → 0.4.2, `CFBundleVersion` → 6.

## [0.4.1] — 2026-05-18

Small patch release moving the Reset Tokegotchi action into the game's
own Settings panel so all per-game options live in one place.

### Changed

- **Reset Tokegotchi** moved from the Tokade app's hamburger menu into
  Token Gaiden's in-game Settings. The Tokade hamburger menu still hosts
  app-wide controls (Usage alerts, Erase Tokade budget history). The
  reset uses an in-place two-click confirmation (`Reset…` reveals
  `Cancel` / `Reset`) so it can't be triggered by accident.
- `CFBundleShortVersionString` → 0.4.1, `CFBundleVersion` → 5.

## [0.4.0] — 2026-05-18

The **Token Gaiden RPG** release. A pixel-art roguelike inside the Tokade
menu bar, fed by your Claude Code telemetry. New `Games` tab, full
gameplay loop, plan-normalized aging, app-level usage alerts.

### Added

- **Games tab + Token Gaiden RPG launcher.** New top-level tab in the
  Tokade panel listing playable games as pixel-art cartridges. Selecting
  a game enters its emulator-screen view; exit lives in the in-game
  Settings panel.
- **Token Gaiden v1: full gameplay loop.** The RPG now plays start to
  finish — character creation, persistent Tokegotchi with stats and
  inventory, age-and-die lifecycle, multi-generation inheritance, and a
  bloodline Hall of Fame. Fed by real Claude Code usage:
  - **Regions** seeded by project type (Swift → Stonework Town,
    Rust → Iron Fortress, Python → Garden Village, JS/TS → Bazaar,
    Go → Open Steppe, unknown → Wilderness). Project-root detection
    walks up from each `cwd` to find a `.git` / `Package.swift` /
    `package.json` / etc. marker, so sub-folders of the same project
    collapse into one region. Map caps to the 10 most-recently-active
    regions (current + pinned always pinned).
  - **Encounters + active combat.** Every 10–20 events in a region
    triggers a passive or active fight against one of 5 flavor-specific
    monsters (30 total). Active mode opens a turn-based panel with
    Attack / Skill / Item / Run. Real-time encounter cooldown (90s)
    prevents heavy-plan users from being drowned in fights.
  - **NPCs, shops, trainers, quests.** Each region has a merchant
    (food / SP potions / gear) with CHA-driven haggling, a trainer
    (stat boosts + skill grants in exchange for EXP), and a curated
    quest line. Quest rewards include gold, EXP, items, and unlockable
    cosmetics.
  - **Gear system.** 12-piece gear catalog across 4 slots (weapon /
    armor / accessory / boots) with ATK/DEF/stat bonuses; drops from
    encounter victories, sold at merchants, equip in the Equip panel.
  - **Skills + SP.** 9 combat skills cost SP to use mid-fight, scale
    with stats, learnable from trainers. Inspire / Power Strike / Mend
    / Fireball / Block / Pierce / Weaken / Escape / Bash.
  - **Death + inheritance.** Critical-HP grace period and
    probabilistic elder-death past 60% lifespan. On death, a new pet
    inherits a fraction of peak stats, all items, equipped cosmetics,
    town reputation, 10% of gold, and the full cosmetic collection.
- **Cosmetic unlock system.** 45-entry catalog across 8 slots (hair /
  hat / eyewear / cape / shirt / pants / belt / held). Unlocks come
  from a balanced mix of achievement grants, quest rewards, and
  weighted random encounter drops. Locked cosmetics render in the
  Wardrobe as dark silhouettes; an unlock-hints panel below the
  carousel explains how to earn each one.
- **Auto-play mode.** Optional autopilot that plays the pet on the
  user's behalf: feeds + heals when HP dips, claims and accepts quests,
  upgrades gear, trains with banked EXP, buys SP potions and gear from
  merchants, attacks / casts skills / flees in combat, wanders for
  EXP, enters dungeons when overpowered, fast-travels between regions
  when quest content is exhausted.
- **Plan-normalized aging + HP drain.** Aging and HP drain are now
  keyed off **Δ% of the 5-hour rate-limit budget**, not raw tokens —
  so a Pro user and a Max-5× user see similar wall-clock lifespans.
  Background-tick loop in `TokadeApp` keeps the pet ticking with the
  menu bar panel closed.
- **Usage alerts (app-level).** Tokade now surfaces Claude API budget
  milestones independent of the game: rate-limit threshold crossings
  (50% / 75% / 90%) and 5-minute token bursts (>500K). Toggle lives in
  the app's hamburger menu next to Reset / Quit, not inside the game.
- **CRT post-effect.** Scanlines / phosphor / soft / dot-matrix / edge-
  fade overlays applied to the whole game screen (every sprite, every
  text element, the launcher banner, the map). Chosen in game settings.
- **Pixel-art UI primitives.** `PixelButton`, `PixelArrowButton`,
  `PixelBar`, `PixelPanel`, `PixelTextFrame`, `GameScreen` bezel, and
  a monospaced `gameFont` modifier. Every interactive element inside
  the game uses these, not native macOS controls.
- **Sprite system extensions.** Per-slot animated cosmetics (idle /
  walk-a / walk-b) with held items wrapped in arm transforms and capes
  wrapped in the head transform so they animate with body movement.
  Baked 49 cosmetics × 3 frames = ~147 sprite matrices. Tokegotchi base
  SVG, 30 monster SVGs, 6 biome tile SVGs, world overworld matrix.
- **77 new XCTest cases** covering Tokegotchi state derivation, tick
  idempotence, encounter math, quest engine, NPC shop / trainer
  interactions, gear / item / skill resolution, death + inheritance,
  and the budget-wear pathway. Total test count: 99.

### Changed

- `appBundledResource(_:ext:)` is module-internal (was private) so
  Token Gaiden code can use the same `Bundle.module` workaround pattern.
- `.swiftformat` excludes `design/` — the design folder's helper Swift
  scripts (`pixelate.swift`, `bake.swift`, `render_matrix.swift`,
  `diff-matrices.swift`) are authoring tools, not app code.
- `CFBundleShortVersionString` → 0.4.0, `CFBundleVersion` → 4.

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

[Unreleased]: https://github.com/bjamba/tokade/compare/v0.4.2...HEAD
[0.4.2]: https://github.com/bjamba/tokade/releases/tag/v0.4.2
[0.4.1]: https://github.com/bjamba/tokade/releases/tag/v0.4.1
[0.4.0]: https://github.com/bjamba/tokade/releases/tag/v0.4.0
[0.3.0]: https://github.com/bjamba/tokade/releases/tag/v0.3.0
[0.2.0]: https://github.com/bjamba/tokade/releases/tag/v0.2.0
[0.1.0]: https://github.com/bjamba/tokade/releases/tag/v0.1.0
