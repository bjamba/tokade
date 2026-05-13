#!/usr/bin/env bash
# Build Tokade.app and install it into /Applications.
# Subsequent runs reinstall cleanly (quit running instance, replace bundle).

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Tokade"
SRC="${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

./build.sh

echo "→ Stopping any running ${APP_NAME}…"
pkill -f "MacOS/${APP_NAME}" 2>/dev/null || true

echo "→ Installing to ${DEST}"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "→ Refreshing Launch Services so Spotlight/Launchpad pick it up"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DEST" >/dev/null 2>&1 || true

echo "→ Launching $DEST"
open "$DEST"

echo "✓ Installed."
echo "  Add to Login Items: System Settings → General → Login Items & Extensions → + → $DEST"
