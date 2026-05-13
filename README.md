# Tokade

A macOS menu bar app that shows your Claude usage and budget at a glance. Reads
from Claude Code's local session logs and statusline output — no API key needed.

## What it shows

- **Menu bar**: current 5-hour rate-limit window utilization (server-truth %)
- **Budget tab**: current 5h window curve with projection, on-pace reference
  line, and a Past 5h windows history view (1d / 7d / 30d)
- **Models tab**: tokens grouped by model, top-5 slash commands / projects /
  tool calls, all broken down by model
- **Trends tab**: weekday × hour heatmap (all-time), YTD cumulative tokens
  with linear-rate projection wedge

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
   30-second poll. This gives raw token counts but no plan-budget context.
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

## License

MIT. See [LICENSE](LICENSE).
