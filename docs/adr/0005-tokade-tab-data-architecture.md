# ADR 0005 — Tokade tab data architecture

- **Status**: Accepted (design draft)
- **Date**: 2026-05-13
- **Deciders**: @bjamba
- **Companion**: [docs/02-design/TOKADE_TAB.md](../02-design/TOKADE_TAB.md)

## Context

The new Tokade tab will host a growing library of "games" (Tokegotchi and
Achievements in v1; Snake, Year-in-Claude, etc. queued for v2+). Each
game needs to consume Claude usage telemetry, persist some small amount
of state to disk, and be added/removed without disturbing other games or
the rest of the codebase.

We could let each game reach into `UsageStore` directly and store its
own data wherever it likes. That works for two games but rots fast:

- Five games each computing `current_5h_pct` from `rateLimits` slightly
  differently produces five subtly different numbers
- Each new game touches `MenuView.swift` to register its tab content
- Persistence formats diverge — game A uses JSON, game B uses
  `UserDefaults`, game C uses a `.plist`
- No place to enforce "games can't write outside `~/.tokade/games/`"

This ADR locks down the contract before the first game ships, so the
boundary is the same shape for game #1 and game #10.

## Decision

### 1. `TelemetrySnapshot` is the read interface

A single value type computed once per `UsageStore.refresh()`, passed
into every game and every achievement predicate. Games and predicates do
**not** read `UsageStore` directly — only `TelemetrySnapshot`.

```swift
struct TelemetrySnapshot {
    let now: Date

    // Raw — same arrays UsageStore holds.
    let events: [UsageEvent]
    let snapshots: [UsageSnapshot]
    let rateLimits: RateLimitSnapshot?

    // Derived (computed lazily; cached on first access).
    var currentFiveHourPct: Double? { /* … */ }
    var currentSevenDayPct: Double? { /* … */ }
    var totalLifetimeTokens: Int { /* … */ }
    var lastEventAt: Date? { /* … */ }
    var hoursSinceLastEvent: Double? { /* … */ }
    var dailyActiveStreak: Int { /* … */ }
    var modelsUsedToday: Set<ModelTier> { /* … */ }
    var distinctSlashCommandsLifetime: Set<String> { /* … */ }
    var distinctCwdsToday: Set<String> { /* … */ }
}
```

`TelemetrySnapshot` lives at `Sources/Tokade/Tokade/TelemetrySnapshot.swift`.
Tests in `Tests/TokadeTests/TelemetrySnapshotTests.swift` lock the derived
fields against fixture event arrays.

**Why a value type, not an actor or class:** snapshots are immutable; a
new one is built per refresh; games hold a reference to the latest one
via SwiftUI's @Observable propagation. No threading concerns.

### 2. `Game` protocol

```swift
@MainActor
protocol Game: Identifiable {
    var id: String { get }                  // "tokegotchi", "achievements"
    var title: String { get }               // "Tokegotchi"
    var icon: String { get }                // SF Symbol name
    func view(telemetry: TelemetrySnapshot) -> AnyView
}
```

A game is a value type that:
- Knows its name + icon
- Renders its UI given a snapshot
- May read/write its own state via `GameStateStore` (below)

Games are registered once in `TokadeTab.allGames` (a static array). The
tab body iterates `allGames`, asks each for its view, and renders them
in a vertical stack of `Card`s.

To add a new game: create one Swift file conforming to `Game`, append it
to `allGames`. No other file changes. **This is the success criterion
of the architecture.**

### 3. `GameStateStore` is the write interface

Every game persists its state through a single store:

```swift
actor GameStateStore {
    func read<T: Codable>(_ type: T.Type, for gameId: String) async -> T?
    func write<T: Codable>(_ value: T, for gameId: String) async
    func erase(gameId: String) async
}
```

Implementation: writes JSON to `~/.tokade/games/<gameId>.json` with mode
`0600` (same promise as other archives). Atomic via `tmp + mv`.

The "Erase history…" action in the panel footer calls
`GameStateStore.eraseAll()` and resets all game state. Tokegotchi
re-hatches from the first archived event; Achievements re-evaluate from
zero.

### 4. File layout

```
Sources/Tokade/
├── Tokade/
│   ├── TokadeTab.swift                 # the new tab view + game registry
│   ├── TelemetrySnapshot.swift         # the read interface
│   ├── GameStateStore.swift            # the write interface
│   ├── Game.swift                      # the protocol
│   ├── Games/
│   │   ├── Tokegotchi/
│   │   │   ├── Tokegotchi.swift        # game conforming to Game
│   │   │   ├── TokegotchiCard.swift    # SwiftUI view
│   │   │   ├── TokegotchiState.swift   # Codable state struct
│   │   │   ├── Mood.swift              # mood band logic
│   │   │   └── Lines.swift             # speech lines (data)
│   │   └── Achievements/
│   │       ├── Achievements.swift      # game conforming to Game
│   │       ├── AchievementsCard.swift  # SwiftUI view (list + sheet)
│   │       ├── Achievement.swift       # value type
│   │       └── Catalog.swift           # the 24 v1 badges
```

The `Tokade/` subdirectory under `Sources/Tokade/` is deliberately
named — it's the *tab*, not the app namespace. (We considered `Arcade/`
to disambiguate; rejected because the user calls it the Tokade tab.)

### 5. Persistence rules

- All game state lives under `~/.tokade/games/`
- Each file is `<gameId>.json`, owned by that game
- Files are `0600`
- Schema changes to a game's state require a new ADR or schema-versioned
  Codable shape with `migrate()` logic
- Games **must not** write outside their own state file
- Games **must not** read other games' state files (use shared
  `TelemetrySnapshot` for cross-game signals)

### 6. Achievement-fire side effect

Achievements need to fire a one-shot toast when newly earned. This is
the only place games are allowed a UI side-effect on the rest of the
panel. The mechanism:

- `Achievements.tick(_ snapshot:)` returns a `[Achievement]` list of
  newly-earned items in this tick
- `TokadeTab` reads that list, prepends them to an internal
  `pendingToasts` array
- A `ToastOverlay` view in `MenuView` renders the queue with auto-dismiss

No other game gets to push toasts in v1.

### 7. CLAUDE.md rules added

Three new enforceable rules:

- **Games read telemetry only via `TelemetrySnapshot`.** No `UsageStore`
  references inside `Sources/Tokade/Tokade/Games/`. Enforced by
  `scripts/check.sh` grep.
- **Games persist only via `GameStateStore`.** No direct
  `FileManager.write` calls inside `Sources/Tokade/Tokade/Games/`.
  Enforced by `scripts/check.sh` grep.
- **Every game in `allGames` has a smoke test.** Just `view(snapshot:)`
  returns without crashing on empty-data and on full-data snapshots.
  Enforced by `scripts/check.sh` greppingfor `func test...<GameName>...`
  in `Tests/TokadeTests/`.

These get appended to `CLAUDE.md` when v1 ships.

## Consequences

**Positive**

- New games are a one-file addition + one registry-line edit
- All telemetry derivations live in one place; no drift
- All game state lives in one place with consistent perms
- The "Erase history…" action correctly nukes game state too
- Future audits can grep `Sources/Tokade/Tokade/Games/` for compliance

**Negative**

- More indirection for game-1 than strictly needed. We're paying
  architecture cost up front to enable games 2..N cheaply.
- `TelemetrySnapshot` has to keep growing as games request new derived
  fields. Risk: a kitchen-sink type. Mitigation: lazy computation +
  document each field's "who needs this" in the source comment.
- `GameStateStore` adds another actor; one more thing to manage Swift
  concurrency around.

## Alternatives considered

- **Direct `UsageStore` access from each game.** Rejected as discussed
  in Context. Doesn't scale past two games.
- **A single `GamesViewModel` that owns all game state.** Rejected;
  putting Tokegotchi and Achievements in the same file (eventually
  also Snake, Year-in-Claude, …) is exactly the monolith we're avoiding.
- **Use `UserDefaults` for game state.** Rejected; doesn't fit the
  "your data is in `~/.tokade/`" promise, hard to inspect, doesn't
  participate in "Erase history…" cleanly.
- **Make games SwiftUI views directly, no protocol.** Rejected; the
  protocol gives us a registration list + uniform testing surface.
  Without it, adding a game requires editing `TokadeTab` body in
  multiple places.
