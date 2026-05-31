# Tokade

[![CI](https://github.com/bjamba/tokade/actions/workflows/ci.yml/badge.svg)](https://github.com/bjamba/tokade/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/bjamba/tokade?include_prereleases&sort=semver)](https://github.com/bjamba/tokade/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A macOS menu bar app that shows your Claude usage and budget at a glance. Reads
from Claude Code's local session logs and statusline output — no API key needed.

Ships with two **Arcade** games that grow alongside your real Claude
usage:

- **Token Gaiden RPG** — a pixel-art roguelike whose pet ages with your
  plan consumption, encounters monsters as you work, and unlocks
  cosmetics from achievements + quest rewards + rare drops.
- **Tokeyo Town** *(new in v0.5)* — a cozy isometric sandbox
  city-builder, themed after a real local repo. Resources flow from
  your Claude usage; you place buildings, sculpt terrain, paint roads,
  and watch townsfolk path between buildings under a real-time
  day/night cycle.

## What it shows

- **Menu bar**: current 5-hour rate-limit window utilization (server-truth %)
- **Budget tab**: current 5h window curve with projection, on-pace reference
  line, and a Past 5h windows history view (1d / 7d / 30d)
- **Models tab**: tokens grouped by model, top-5 slash commands / projects /
  tool calls, all broken down by model
- **Trends tab**: weekday × hour heatmap (all-time), YTD cumulative tokens
  with linear-rate projection wedge
- **Games tab** *(new in v0.4)*: Arcade launcher for Tokade's pixel-art
  games. Hosts **Token Gaiden RPG** (full RPG loop with regions, NPCs,
  quests, gear, skills, multi-generation inheritance) and **Tokeyo
  Town** *(new in v0.5)* — a cozy isometric sandbox city-builder.
- **Usage alerts** *(new in v0.4)*: notifications when your 5-hour budget
  crosses 50% / 75% / 90% or a 5-minute window burns >500K tokens.

### Screenshots

| Budget | Models | Trends |
|:------:|:------:|:------:|
| ![Budget tab](docs/screenshots/tokade-budget.png) | ![Models tab](docs/screenshots/tokade-models.png) | ![Trends tab](docs/screenshots/tokade-trends.png) |

### Token Gaiden RPG

A roguelike fed by your Claude Code usage. Project root = region, project
language = region flavor, tool calls = item drops, plan consumption =
pet aging. Plays itself on autopilot if you want — toggle Auto-play in the
in-game Settings and the pet will heal, fight, train, equip gear, and
travel between regions on its own.

![Token Gaiden RPG cover](docs/screenshots/tg-rpg-cover.png)

| Menu | Region | Map |
|:------:|:------:|:------:|
| ![Token Gaiden menu](docs/screenshots/tg-rpg-menu.png) | ![Token Gaiden region](docs/screenshots/tg-rpg-region.png) | ![Token Gaiden map](docs/screenshots/tg-rpg-map.png) |

### Tokeyo Town

A cozy isometric sandbox city-builder, themed after a *real local repo*
on your machine. Pick a folder; the scanner derives its biome
(Swift → beach, Rust → tundra, Python → forest, JS/TS → plain,
Go/Java → desert), era from repo age, and starting lushness from
recent commit cadence. Then build:

- Place buildings (40+ across 5 biomes, with footprints from 1×1
  cottages to 3×3 landmarks) — each costs resources accrued from your
  Claude usage (tokens → coin, reads → knowledge, edits → lumber,
  bashes → industry, sessions → growth).
- Sculpt terrain with raise / lower / pond / tree / flower / lantern /
  road tools. Townsfolk path between buildings using A\*, preferring
  the roads you build.
- Real-time **day/night cycle** tied to your wall clock: lanterns
  glow at night, stars appear above the town.
- Active-session 2× bonus when the current Claude session is working
  inside the town's repo.

100% local — no Claude calls, no network requests for scanning.
Buildings auto-populate the town with townsfolk as it densifies; coin
upkeep covers their existence.

![Tokeyo Town overview](docs/screenshots/tokeyo-town-overview.png)

| Day | Night |
|:------:|:------:|
| ![Tokeyo Town in daylight](docs/screenshots/tokeyo-town-day.png) | ![Tokeyo Town at night](docs/screenshots/tokeyo-town-night.png) |

## Requirements

- macOS 14 (Sonoma) or newer
- [Claude Code](https://docs.claude.com/claude-code) installed and signed in
- Xcode Command Line Tools (`xcode-select --install`) for the Swift toolchain

## Install

```bash
git clone https://github.com/bjamba/tokade.git
cd tokade
./install.sh
```

That builds `Tokade.app`, copies it to `/Applications/`, and launches it.

Optional but recommended — wire the statusline shim so Tokade gets fresh
rate-limit data each time Claude Code responds:

```bash
./install-statusline.sh
```

This adds a `statusLine` entry to `~/.claude/settings.json` pointing at
`statusline-shim.sh`. The shim writes Claude Code's statusline JSON to
`~/.tokade/last-status.json` for Tokade to read.

To launch on login: System Settings → General → Login Items & Extensions →
+ → `/Applications/Tokade.app`.

## Privacy

Tokade is local-first by design. There are no network calls anywhere in the
codebase — you can verify this with `grep -r URLSession Sources/` (and CI
enforces it on every PR).

Tokade reads:

- `~/.claude/projects/**/*.jsonl` — Claude Code's session logs. Tokade
  extracts only **metadata**: timestamps, model names, token counts, session
  IDs, current-working-directory paths, tool names, and slash commands.
  Tokade does **not** read prompt text, response text, or any auth material.
- `~/.tokade/last-status.json` — written by our statusline shim with the
  current `5h%` / `7d%` from Claude Code's view of Anthropic's rate limits.

Tokade writes to `~/.tokade/`:

- `last-status.json` — most recent statusline snapshot (overwritten each
  Claude Code response)
- `history/snapshots.jsonl` — append-only log of server-reported `%` over time
- `history/events.jsonl` — every parsed Claude Code event (model, tokens,
  session, **cwd**, tools, slash command). The `cwd` field reveals the
  directory names of projects you've worked on; review before sharing your
  archive.

All files in `~/.tokade/history/` are created with `0600` permissions
(owner-only read/write).

**To wipe your archive**: use the "Erase history…" action in the menu bar
panel footer, or `rm -rf ~/.tokade/` from the terminal. Neither touches
`~/.claude/projects/` (that's Claude Code's, not ours).

**Distribution model**: the `Tokade.app` released via GitHub Releases is
**ad-hoc codesigned** but not Apple-notarized. macOS will show an
"unidentified developer" warning on first launch — right-click → Open →
confirm. See [ADR-0004](docs/adr/0004-ad-hoc-codesigning-no-notarization.md)
for why.

## Data

Tokade keeps a local archive at `~/.tokade/`:

- `last-status.json` — most recent statusline snapshot
- `history/snapshots.jsonl` — append-only log of server-reported `%` over time
- `history/events.jsonl` — every parsed Claude Code event (model, tokens,
  session, cwd, tools, slash command)

Nothing is sent over the network. All data stays on your machine.

## Build from source

```bash
./build.sh         # produces ./Tokade.app
open Tokade.app    # run from project dir without installing
```

To regenerate the app icon from the SVG source (requires `librsvg`):

```bash
brew install librsvg
mkdir -p AppIcon.iconset
for size in 16 32 128 256 512; do
  rsvg-convert -w $size -h $size design/Tokade-AppIcon.svg -o "AppIcon.iconset/icon_${size}x${size}.png"
  rsvg-convert -w $((size*2)) -h $((size*2)) design/Tokade-AppIcon.svg -o "AppIcon.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
```

The menu bar template icon is regenerated similarly into
`Sources/Tokade/Resources/MenuBarIcon.png` (22 px) and `MenuBarIcon@2x.png` (44 px).

## How it works

Two data sources:

1. **Claude Code JSONL** at `~/.claude/projects/**/*.jsonl` — every assistant
   message includes its model and token usage. Tokade parses these on each
   3-second poll (the game tick reads the same events at that cadence; an
   mtime cache keeps re-polls cheap). This gives raw token counts but no
   plan-budget context.
2. **Statusline JSON** at `~/.tokade/last-status.json` — written by the shim
   each time Claude Code refreshes its statusline. Contains the server's
   current 5h and 7d utilization `%`, the next reset timestamps, the current
   session ID, and the active model. This is the source of truth for budget
   utilization because the `%` already incorporates whatever per-model weights
   Anthropic applies.

The Past 5h windows chart prefers the snapshot archive for server-truth bars
and falls back to a JSONL-derived approximation for windows that have no
snapshot yet. The approximation uses today's derived 5h cap; it can drift if
your model mix or claude.ai-vs-Code split has shifted historically.

## Why no Anthropic API integration?

Anthropic doesn't expose subscription plan, plan-tier, or historical
utilization data via any public API. The Admin API only covers API-key usage,
not Claude.ai Pro/Max subscriptions. The statusline JSON is the only
authoritative source Tokade can reach without scraping claude.ai cookies.

## Limitations and assumptions

These shape every chart and metric. None of them are bugs — they're the
boundaries of what's possible given what Anthropic exposes.

- **claude.ai web and desktop usage is invisible.** Tokade only sees Claude
  Code's local JSONL. If you also chat on claude.ai or the desktop app, your
  raw-token charts undercount real usage. The server-reported `%` still
  reflects the unified total (Code + web + desktop), so the Budget tab is
  accurate; only the Models / Trends token charts are Code-only.
- **Raw tokens are not budget-weighted.** Anthropic applies undisclosed
  per-model weights when computing rate-limit `%`. A 1M-token Opus session
  burns substantially more budget than a 1M-token Sonnet session. The Models
  tab shows raw counts, so high-token Haiku sessions can look bigger than
  low-token Opus sessions even though Opus consumed more of your cap.
- **Plan caps aren't published.** Anthropic doesn't publish tokens-per-week
  caps for Pro / Max 5× / Max 20×. Tokade derives an inferred 5h cap from
  your server `%` ÷ local 5h tokens, then uses that for approximate bars on
  the Past 5h Windows chart. The inference is biased downward by whatever
  share of usage was on claude.ai (since local tokens undercount).
- **Approximate bars assume a stable model mix and surface split.** If your
  model mix shifts over months (heavy Opus then heavy Sonnet, or vice versa),
  past approximate bars drift in the direction the mix shifted. The same is
  true if your claude.ai-vs-Code split changes.
- **Historical `%` only exists from when Tokade started.** Server-truth `%`
  comes from the statusline shim. Anything before the shim was wired is
  reconstructed from raw tokens with the caveats above.
- **5h-window auto-reset is projected, not observed.** When your server
  `resetsAt` is in the past and Claude Code hasn't messaged since, Tokade
  advances the window forward in 5h increments. The next Claude Code message
  confirms or corrects it.
- **YTD projection is linear.** The wedge edges are YTD-average rate and
  last-30-day rate. Tokade doesn't model seasonality, holidays, or
  intentional usage shifts; it only shows the range bounded by your damped
  and responsive paces.
- **No network. No telemetry.** Everything stays on your machine, archived
  under `~/.tokade/`.

## Roadmap

Work in progress lives on the public [Tokade Roadmap board](https://github.com/users/bjamba/projects/2).
File a [feature request](https://github.com/bjamba/tokade/issues/new/choose)
or open a [Discussion](https://github.com/bjamba/tokade/discussions) if
you'd like to weigh in.

Larger directions still in the brainstorm phase (no committed timeline):

- **More games in the Games tab.** Token Gaiden RPG is the first; more
  small games that couple to your Claude usage will land alongside it.
- **Cost estimation.** Optional dollar values per chart for API-key users.
- **Multi-account support.** Switch between work / personal / API-key views.

## Questions

Use [Discussions](https://github.com/bjamba/tokade/discussions) for "how do
I…?" or "should we…?" threads. Use [Issues](https://github.com/bjamba/tokade/issues/new/choose)
for bugs and concrete feature requests.

## License

MIT. See [LICENSE](LICENSE).
