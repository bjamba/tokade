# Tokade tab — design doc

> **Last reviewed**: 2026-05-13
> **Owner**: @bjamba
> **Status**: design draft (not implemented)
> **Companion ADR**: [0005-tokade-tab-data-architecture.md](../adr/0005-tokade-tab-data-architecture.md)

## Vision

A fourth top-level tab that hosts a small library of light "games" coupled
to your real Claude Code telemetry. The games don't simulate Claude
usage — they *consume* it. Empty install = empty tab. The point is to
make patterns visible, make milestones feel earned, and (eventually)
turn a number on a chart into something with personality.

v1 ships with two features:

- **Achievements** — auto-detected badges for usage patterns. Passive,
  observational, immediate-reward.
- **Tokegotchi** — a single pet that lives in a card. Mood and vitals
  driven by your current rate-limit state and recent activity. Active in
  the sense that it changes over time, but no input gameplay yet.

The tab is built so that adding a third or tenth game is the same shape
as adding the second. See the
[companion ADR](../adr/0005-tokade-tab-data-architecture.md) for the
architecture.

## Out of scope for v1

- Any game requiring keyboard input (Snake, Tetris, etc. — explicitly
  deferred to v2)
- Multiplayer / leaderboards / social
- Network calls of any kind — the no-network promise stands
- Custom art assets — start with SF Symbols and unicode
- User-naming the Tokegotchi (lock the name in v1; revisit)

## Tab layout

```
┌─────────────────────────────────────────────────────────┐
│ Tokade tab                                              │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Tokegotchi                                       │  │
│  │  ─────────────                                    │  │
│  │     ╭───╮       Boba                              │  │
│  │     │ ◕‿◕ │      Status: content                  │  │
│  │     ╰───╯       Born: 2026-04-22  (Day 21)        │  │
│  │                                                   │  │
│  │   Energy   ████████░░  82%                        │  │
│  │   Hunger   ██████░░░░  62%                        │  │
│  │   Mood     ███████░░░  73%                        │  │
│  │                                                   │  │
│  │   "I'm cozy. Send me an Opus message later 🌟"   │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Achievements          12 / 24 earned             │  │
│  │  ─────────────                                    │  │
│  │   🏅 First message            Apr 22              │  │
│  │   🏅 Lifetime: 1M tokens      Apr 28              │  │
│  │   🏅 First Opus message       Apr 22              │  │
│  │   🏅 3-day streak             Apr 24              │  │
│  │   🏅 7-day streak             Apr 29              │  │
│  │   🏅 …                                            │  │
│  │   🔒 Lifetime: 100M tokens                        │  │
│  │   🔒 30-day streak                                │  │
│  │   …  (Show all)                                   │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Tokegotchi specification

### Identity

- Lives in a single card at the top of the Tokade tab
- Has a fixed name `Boba` in v1 (we'll let users rename in a later milestone)
- Has a "birthday" = the timestamp of the user's first archived event
- Has an "age" in days computed from birthday

### Vitals

Three meters, each a percentage 0–100. Computed from telemetry on every
30-second poll. Updates live.

| Vital | Source | Mapping |
|-------|--------|---------|
| **Energy** | `100 - current_5h_pct` | High = window fresh; low = window almost spent |
| **Hunger** | Time since last event in `events` | 100% if last event ≤ 12h ago; linearly drops to 0% at 7 days |
| **Mood** | `(Energy + Hunger) / 2`, optionally biased by `Tokegotchi.streak` (3+ consecutive active days nudges Mood up by 10) | Composite |

Display as three short horizontal bars colored by the existing palette
(blue family). When any vital drops below 25%, that bar turns amber.

### Mood states + speech

Mood determines a single sprite + speech line shown in the card. The
sprite is a unicode-art expression rendered in a monospace font.

| Mood band | Sprite (illustrative) | Sample lines |
|-----------|----------------------|--------------|
| 80–100 | `╭───╮` / `│ ◕‿◕ │` / `╰───╯` | "I'm cozy. 🌟" · "Plenty of budget left. Keep cooking." |
| 60–79  | `╭───╮` / `│ ·_· │` / `╰───╯` | "Good pace today." · "Steady. Boba approves." |
| 40–59  | `╭───╮` / `│ -_- │` / `╰───╯` | "You're using me a lot. Pace yourself." |
| 20–39  | `╭───╮` / `│ >_< │` / `╰───╯` | "Burning hot. Window won't last." · "Maybe a Sonnet for the next one?" |
| 0–19   | `╭───╮` / `│ x_x │` / `╰───╯` | "You hit the cap. Boba needs a nap." (locked emoji 😴) |

Three speech lines per band, rotated daily by hash(date + line index) so
the same line doesn't appear two days running. Lines live in a single
file (`Sources/Tokade/Arcade/Tokegotchi/Lines.swift`) so they're easy to
edit and contribute to.

Special override: when `isFiveHourDataStale(rateLimits)` is true, mood
flips to "asleep" with sprite `( - . - ) zzz`. The pet sleeps through
windows you're not using.

### Life cycle / age

Boba doesn't reset, evolve, or die in v1. There's a single Tokegotchi
that grows older over time. Age in days is shown next to the name.

Future (v1.1): an "evolutions" system where Boba changes appearance at
milestones (Day 7, Day 30, Day 100). v1 does **not** ship this — the
sprite is fixed across the age dimension. We just track + display age.

### Persistence

A single JSON file at `~/.tokade/history/tokegotchi.json`:

```json
{
  "name": "Boba",
  "bornAt": "2026-04-22T18:12:04Z",
  "lastSeenMoodBand": 60,
  "todaysLineIndex": 1
}
```

Created on first launch from the user's earliest archived event. Updated
on each poll. File permissions: 0600 (same as other archive files).

If the file is missing or corrupt, recreate from `events.jsonl`'s
earliest event. If `events.jsonl` is also empty, Boba enters an "egg"
state until the first event lands.

## Achievements specification

### Definition shape

Each achievement is a value type with:

- `id: String` — stable identifier (e.g. `"lifetime-1m-tokens"`)
- `title: String` — display name
- `description: String` — one sentence
- `icon: String` — SF Symbol or emoji
- `predicate: (TelemetrySnapshot) -> Bool` — pure function over the
  current state. Called on every poll; once true, sticky.

Stickiness: once earned, the achievement records its `earnedAt: Date`
and never re-evaluates. We persist the entire earned set; predicates run
only for unearned items.

### Initial v1 badge set (24)

**Volume**

| id | title | predicate |
|----|-------|-----------|
| `lifetime-1m` | First million | total tokens ≥ 1M |
| `lifetime-100m` | Heavy hitter | total tokens ≥ 100M |
| `lifetime-1b` | One billion | total tokens ≥ 1B |
| `lifetime-10b` | Token whale | total tokens ≥ 10B |

**Model coverage**

| id | title | predicate |
|----|-------|-----------|
| `first-haiku` | Hello, Haiku | any event with model containing "haiku" |
| `first-sonnet` | Hello, Sonnet | … "sonnet" |
| `first-opus` | Hello, Opus | … "opus" |
| `polyglot-day` | Three-model day | all three tiers used same calendar day |

**Tools and skills**

| id | title | predicate |
|----|-------|-----------|
| `tool-set-bero` | Bash · Edit · Read · Other | all of {Bash, Edit, Read, Write} in one session |
| `skill-sampler` | Skill sampler | 5 distinct slash commands used lifetime |
| `skill-explorer` | New tool | invoked a slash command never used before |

**Rhythm**

| id | title | predicate |
|----|-------|-----------|
| `streak-3` | 3-day streak | activity 3 consecutive calendar days |
| `streak-7` | 7-day streak | activity 7 consecutive days |
| `streak-30` | 30-day streak | activity 30 consecutive days |
| `early-bird` | Early bird | 3 sessions before 7am |
| `night-owl` | Night owl | 3 sessions between midnight and 4am |

**Budget**

| id | title | predicate |
|----|-------|-----------|
| `window-survivor` | Window survivor | finished a 5h window between 90–99% utilization |
| `near-miss` | Walked the line | finished a 7d window between 95–99% |
| `capped` | Maxed out | hit 100% on any window (badge of honor or shame, ymmv) |
| `cache-pro` | Cache pro | `cache_read / total_input ≥ 70%` for a 7-day stretch |

**Project flavor**

| id | title | predicate |
|----|-------|-----------|
| `multi-project` | Multitasker | events from 3+ distinct cwds in one day |
| `deep-dive` | Deep dive | a single session ≥ 1M tokens |
| `marathon` | Marathon | a single session ≥ 4 hours wall-clock |

**Tokegotchi-linked**

| id | title | predicate |
|----|-------|-----------|
| `boba-first-week` | Boba's first week | Tokegotchi age ≥ 7 days |
| `boba-survived-cap` | Boba survived the cap | hit 100% window without going idle for 24h after |

That's 24 badges. Reasonable for a v1 gallery: ~half achievable in the
first month of use, ~quarter in the first day, ~quarter as long-term goals.

### UI shape

Achievements card body:

- Header: `Achievements   N / 24 earned`
- List view, sorted: earned first (newest first), then locked (in catalog order)
- Each row: icon + title + (earned: date) | (locked: lock emoji)
- "Show all" expands the locked section if >5 hidden
- Tooltip on hover: full description + predicate explanation

Tap a badge: opens a sheet with the badge's description + a small chart
or stat showing your progress toward it (e.g., for `lifetime-1b`, a
horizontal progress bar with current total vs. 1B). Sheet is read-only.

### Persistence

A single JSON file at `~/.tokade/history/achievements.json`:

```json
{
  "earned": {
    "lifetime-1m":    "2026-04-28T12:33:01Z",
    "first-opus":     "2026-04-22T18:13:11Z",
    "streak-3":       "2026-04-24T09:00:00Z"
  }
}
```

On startup, load earned set. On each poll, evaluate unearned predicates
against the current `TelemetrySnapshot`. If any flip to true, record
`earnedAt: now`, persist, fire a one-shot notification banner
("🏅 First million tokens — earned").

File permissions: 0600.

### Notification banner

A minimal toast in the panel for newly-earned badges, dismissable. No
macOS-level notification — we don't have `NSUserNotification` permissions
and the bar for Tier 2 OSS doesn't include them.

## Telemetry contract

The Tokegotchi card and the Achievement predicates both consume a
shared **`TelemetrySnapshot`** value type computed once per poll:

```swift
struct TelemetrySnapshot {
    let now: Date
    let events: [UsageEvent]
    let snapshots: [UsageSnapshot]
    let rateLimits: RateLimitSnapshot?

    // Derived; cached.
    let currentFiveHourPct: Double?
    let currentSevenDayPct: Double?
    let totalTokens: Int
    let lastEventAt: Date?
    let dailyActiveStreak: Int
}
```

The exact shape and computation rules live in
[ADR-0005](../adr/0005-tokade-tab-data-architecture.md).

## Open questions

These need an answer before we ship v1 but don't block design review:

1. **Naming the pet.** v1 hardcodes "Boba." Should we ship a "rename"
   action and persist user choice? Adds a settings sheet. (Lean: defer.)
2. **Notification banner styling.** Toast-in-panel vs. a small badge that
   dot-appears next to the Tokade tab label like "GitHub notifications
   count" on the segmented control? (Lean: dot indicator.)
3. **What happens if `~/.claude/projects/` is empty?** Achievements
   gallery still shows the locked list. Tokegotchi enters an "egg" state
   with no animation. (Lean: yes.)

## Future (v2+)

- Snake / Breakout as the first playable game
- Tokegotchi evolutions at age milestones (Day 7, 30, 100)
- Tokegotchi customization (rename, color tint from model mix)
- A "year-in-Claude" Polaroid view as a third game-card
- Daily oracle: fortune-cookie line from yesterday's usage
- Plant-a-tree garden (token volume = growth rate)
- Idle factory (in-game tokens earned from real tokens 1:1000)
- Achievement leaderboards (anonymized, opt-in, would break no-network)
