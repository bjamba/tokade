#!/usr/bin/env bash
# render.sh — compose SVG (palette + fragments) → rasterize at 32x48 → outline + upscale + CRT → bake matrix.
# usage:    ./render.sh [<name>]
# env:      HAIR_STYLE (default: horns), HAT (default: none), plus palette overrides.
set -euo pipefail
cd "$(dirname "$0")"

NAME="${1:-tokegotchi-base-v3}"
SVG_IN="$NAME.svg"
SVG_RESOLVED="$NAME-resolved.svg"
SMALL="$NAME-32x48.png"
PIXEL="$NAME-pixel.png"
CRT="$NAME-crt.png"
MATRIX="$NAME.matrix"

if [[ ! -f "$SVG_IN" ]]; then echo "missing: $SVG_IN" >&2; exit 1; fi

# Compose the SVG: substitute hair-style + hat fragments + all color placeholders.
python3 compose.py "$SVG_IN" "$SVG_RESOLVED"

# Rasterize to source res. viewBox is 100×168, so 32 wide → ~54 tall.
rsvg-convert -w 32 -h 54 "$SVG_RESOLVED" -o "$SMALL"

# Outline + 16x upscale (no CRT).
swift pixelate.swift "$SMALL" "$PIXEL" 16 outline

# Outline + 16x upscale + CRT.
swift pixelate.swift "$SMALL" "$CRT" 16 outline crt

# Bake matrix. Pass palette so bake's quantization matches render colors.
SKIN="${SKIN:-#C7A5D9}" SKIN_LIGHT="${SKIN_LIGHT:-#DBC1E8}" SKIN_DARK="${SKIN_DARK:-#A07AB8}" \
  HAIR="${HAIR:-#E8DCC4}" HAIR_DARK="${HAIR_DARK:-#A89473}" IRIS="${IRIS:-#4A7BC5}" \
  SHIRT="${SHIRT:-#5A7F3F}" SHIRT_LIGHT="${SHIRT_LIGHT:-#7DA055}" SHIRT_DARK="${SHIRT_DARK:-#3F5A2A}" \
  PANTS="${PANTS:-#5C4033}" PANTS_LIGHT="${PANTS_LIGHT:-#7C5C45}" PANTS_DARK="${PANTS_DARK:-#3D2920}" \
  BELT="${BELT:-#8B6F47}" DARK="${DARK:-#1A1A2E}" WHITE="${WHITE:-#FFFFFF}" \
  swift bake.swift "$SMALL" "$MATRIX"

echo "rendered: $PIXEL $CRT $MATRIX  (HAIR_STYLE=${HAIR_STYLE:-horns} HAT=${HAT:-none})"
