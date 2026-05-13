# ADR 0005 — Token Gaiden RPG system architecture

- **Status**: Accepted (design — implementation TBD)
- **Date**: 2026-05-13
- **Deciders**: @bjamba
- **Companion**: [docs/02-design/TOKADE_TAB.md](../02-design/TOKADE_TAB.md)

## Terminology

- **Tokade** — the macOS menu bar app (existing brand).
- **Tokade tab** — the new tab in the app (the container; may host other games in the future).
- **Token Gaiden** — the v1 game inside the Tokade tab. The subject of this ADR.
- **Tokegotchi** — the creature the player raises in Token Gaiden. One per active save; ancestors live in the Hall of Fame.

## Context

Token Gaiden is a small RPG inside the Tokade tab — a Tokegotchi creature with stats, regions, encounters, and a death/inheritance loop, fed by real Claude Code telemetry. This ADR captures the architectural decisions made during the design discussion that produced the v1 spec.

The challenge is that Token Gaiden combines several distinct subsystems that all have to work together:
- An RPG state machine driven by externally-observed events
- A pixel-art rendering pipeline with per-character customization
- An animation system that has to compose with cosmetics
- A persistent save state that handles death + inheritance
- A composable cosmetic system that can grow to many items

The decisions below are the load-bearing ones — getting them right early means the rest of the implementation is mechanical.

## Decisions

### 1. Matrix is the runtime asset format; SVG is the design-time format

Sprites at runtime are **text matrix files** — 32×54 grids of palette-role indices. The base sprite, each hair style, each cosmetic item, and each animation frame is one such file (~1.5KB).

SVG is the **design intermediary**. Iteration happens in SVG, where a designer (human or LLM) edits geometry, runs `bake.swift`, and gets a matrix. SVG is not loaded at runtime.

Reasoning: SVG editing is fast and forgiving for iteration but heavy at runtime (requires a rasterizer). Matrix is cheap to load (just text), trivially diff-able in git, and supports the palette-swap trick (decision 2) without re-bakes.

**Pipeline:**

```
design/tokegotchi/<part>.svg     ← author edits this
  ↓ compose.py + rsvg-convert
design/tokegotchi/<part>-32x54.png  ← rasterized 32×54
  ↓ bake.swift
design/tokegotchi/<part>.matrix  ← runtime asset
```

### 2. Palette roles are parameterized; specific RGB is applied at render time

The matrix encodes **role indices** (1 = outline, 2 = skin, 3 = skin-light, 4 = skin-dark, …) — not literal RGB.

At runtime, each Tokegotchi has a **palette table** mapping each role to a specific RGB color (the user's chosen skin, iris, hair, etc.). Rendering = for each cell, look up `palette[role]` and paint.

This means **all 6×6×6×6 = 1,296 color combinations of any sprite share a single matrix**. Storage for the full character creator is ~10–20KB, not hundreds of MB.

Implication: stat-bearing equipment (rings, amulets) has its own palette entries too. New cosmetic categories add new roles, but the base palette is capped at 16 entries to keep glyph encoding to one hex character per cell.

### 3. Cosmetics use additive composition via z-ordered SVG fragments

Each cosmetic slot has a placeholder in the base SVG (`{{HAT_BODY}}`, `{{SHIRT_BODY}}`, `{{HELD_R_BODY}}`, etc.). Each cosmetic is a small SVG fragment substituted into the placeholder by `compose.py` at design time.

Slots and their z-order (back-to-front):

```
cape  →  legs  →  pants  →  arms  →  torso  →  shirt  →  belt
      →  [head group:  face → eyewear → hair → hat]  →  held-r / held-l
```

This means:
- Slot file structure is flat: `cosmetics/<slot>/<name>.svg`
- New cosmetics = one file + one folder entry. No base SVG changes needed.
- Z-order is fixed in the base SVG; cosmetics can't reorder themselves.

### 4. Animation is rig-based: per-part transforms, not per-frame matrices

Each animatable body part is wrapped in a `<g id="...">` group with a `{{X_TRANSFORM}}` placeholder. Animation frames are **tuples of transform strings**:

```swift
struct AnimationFrame {
  let headTransform: String
  let rArmTransform: String
  let lArmTransform: String
  let rLegTransform: String
  let lLegTransform: String
}
```

At equip time (when cosmetics change), the compositor pre-bakes each frame for the current outfit. Frames are then PNG/matrix files cycled at runtime.

Arm groups have clip-paths removed because clip-paths don't transform with their parent — rotation breaks them. Shading rects are sized to naturally stay within arm bounds, making the clip-path redundant.

### 5. State persistence is one JSON file per Tokegotchi, at `~/.tokade/games/tokegotchi.json`

File mode is `0600` (same promise as other Tokade archives). Atomic write via tmp + mv. Schema is versioned with a `schemaVersion` integer to support future migrations.

On death, the file is **not deleted** — the dead Tokegotchi rolls into the `bloodline.ancestors` array of the next generation's file. Hall of Fame is a derived view over that array.

If the file is missing or corrupt, the app shows a character creator to start a new lineage. No data is lost from the user's actual Claude Code logs — they're the source of truth and replayable.

### 6. Telemetry events are consumed via a `TickProcessor`; state is updated via pure functions

A `TickProcessor` watches the existing `UsageStore` (or its successor) and translates each new event into game effects:

```swift
protocol TickProcessor {
  func consume(_ event: UsageEvent, against state: inout TokegotchiState) -> [TickResult]
}

enum TickResult {
  case itemDropped(itemId: String, count: Int)
  case hpChanged(delta: Int)
  case spChanged(delta: Int)
  case ageAdvanced(byTokens: Int, multiplier: Double)
  case questUnlocked(questId: String)
  case encounterTriggered(kind: EncounterKind)
  case achievementEarned(id: String)
}
```

All state changes go through `consume(...)`. The UI subscribes to state changes; `TickResult` values surface as toasts, animations, or modals. This isolates game logic from UI logic.

### 7. Token Gaiden is the only game in the Tokade tab at v1; no game-registry abstraction

The earlier draft of this ADR proposed a `Game` protocol with multiple games registered via a static `allGames` array. **That is dropped.** The Tokade tab at v1 hosts Token Gaiden and nothing else. If a second game is ever added, this ADR will be amended to introduce the registry shape at that time.

This simplifies the code substantially — no protocol, no compositor for cross-game state, no game-state-store actor. State is just the Tokegotchi save file.

### 8. Region identity is cwd-prefix-matched and seeded by project analysis

A region is uniquely identified by its **cwd prefix** (top-level project root). Subdirectories share the parent's region.

When a new cwd is first observed, the system runs a **one-time region analysis**:

1. Walks the project root looking for marker files (`Package.swift`, `Cargo.toml`, `package.json`, `pyproject.toml`, `go.mod`)
2. Picks a region "flavor" from a small table
3. Writes the seed to `~/.tokade/games/regions/<encoded-cwd>.json`

Seed information stays hidden from the player until LoC steps reveal it (Layer 3 in TOKADE_TAB.md). This way the world has consistent structure on first visit but unfolds gradually.

### 9. Combat is mode-toggled, not fundamentally different code paths

The user toggles `combatMode = passive | active` in settings. The combat engine is the same in both modes — the difference is **whether the UI presents a turn-based modal**. Passive mode simply auto-clicks "Attack" each turn until resolution, and renders a brief result banner. Active mode renders the modal and waits for input.

A small set of "boss" monsters override `combatMode` to always-active. This is encoded per-monster, not at the global level.

## Consequences

**Positive**

- Adding a cosmetic = 1 SVG file. No code change.
- Adding a hair style = 1 SVG file. No code change.
- Changing a Tokegotchi's colors = updating their palette table. No re-bake.
- Saving the full game state = serializing one struct.
- The full sprite library fits in ~100KB at any size.
- All telemetry-to-game logic is in one place (`TickProcessor`), easy to test in isolation.

**Negative**

- The bake pipeline is a real piece of tooling (`compose.py`, `pixelate.swift`, `bake.swift`, `render_matrix.swift`). It must be kept working as new SVGs are authored.
- The 16-color palette cap will eventually be limiting — a cosmetic that wants three new fill colors uses up 3 slots fast. v2 will need to extend.
- Region seeding is one-time at first-visit; if the project changes language later, the region's flavor doesn't update. Acceptable; user can request a re-seed.
- Per-part transforms can't easily express *bone-chain* animation (e.g., wrist independently rotating from elbow). That's out of scope for v1's anatomy.

## Alternatives considered

- **PNG-baked-per-combo cosmetics.** Rejected — would require ~1,728 PNGs per cosmetic to cover every character creator combination. Matrix + palette swap is 1 file per cosmetic.
- **A general `Game` protocol** so multiple games can share the tab. Rejected — over-engineering for a single game. If a second game lands, this ADR is amended.
- **Realtime SVG rendering** (load SVG, rasterize on every frame). Rejected — slow on cold start, complex runtime dependency on libsvg or similar.
- **Per-frame matrix files for animation** (instead of rig transforms). Rejected — would mean each cosmetic combination × each frame = explosion in matrices. Rig-based wins by an order of magnitude.
- **Skeletal/bone animation** with named joints + IK. Rejected — overkill for 32×54 sprites. The 5 part-groups + transforms cover everything v1 needs.
- **UserDefaults / SQLite for state.** Rejected — JSON in `~/.tokade/` matches the existing privacy promise and is inspectable.
