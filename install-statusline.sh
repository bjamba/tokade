#!/usr/bin/env bash
# Adds Tokade's statusline to ~/.claude/settings.json (non-destructively).
# Run from a regular Terminal window, NOT from inside a Claude Code `!` prompt
# (the agent's sandbox blocks writes to its own settings).

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
SHIM="$(cd "$(dirname "$0")" && pwd)/statusline-shim.sh"

if [ ! -f "$SETTINGS" ]; then
  echo "No $SETTINGS — creating a minimal one."
  mkdir -p "$(dirname "$SETTINGS")"
  echo '{}' > "$SETTINGS"
fi

if [ ! -x "$SHIM" ]; then
  echo "Shim not executable: $SHIM" >&2
  exit 1
fi

cp "$SETTINGS" "$SETTINGS.backup.$(date +%Y%m%d-%H%M%S)"

python3 - "$SETTINGS" "$SHIM" <<'PY'
import json, sys
path, shim = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)
cfg["statusLine"] = {"type": "command", "command": shim}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY

echo "OK — statusLine added to $SETTINGS"
echo "Backup: $SETTINGS.backup.*"
echo
echo "Next: send any Claude Code message; Tokade will pick up real numbers."
