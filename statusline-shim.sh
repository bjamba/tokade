#!/bin/bash
# Tokade statusline shim.
# Reads Claude Code's statusline JSON from stdin, persists it for the menu bar
# app, and echoes a compact status line back to Claude Code.

set -u
DEST_DIR="$HOME/.tokade"
DEST="$DEST_DIR/last-status.json"
TMP="$DEST.tmp.$$"

mkdir -p "$DEST_DIR"

# Slurp stdin once.
input="$(cat)"

# Persist atomically. Don't fail the statusline if disk write fails.
if [ -n "$input" ]; then
  printf '%s' "$input" > "$TMP" 2>/dev/null && mv -f "$TMP" "$DEST" 2>/dev/null
fi

# Echo a status line. Best-effort; degrade gracefully if jq is missing.
if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
  model=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // empty' 2>/dev/null)
  five=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
  week=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)

  out=""
  [ -n "$model" ] && out="$model"
  [ -n "$five" ] && out="${out:+$out · }5h:$(printf '%.0f%%' "$five")"
  [ -n "$week" ] && out="${out:+$out · }7d:$(printf '%.0f%%' "$week")"
  [ -n "$out" ] && echo "$out"
fi
