#!/usr/bin/env bash
# bake-cosmetic.sh — turn a single cosmetic SVG fragment into a standalone
# matrix file (a "just the cosmetic" sprite). Layered at runtime by
# SpriteComposer.swift.
#
# Usage: ./bake-cosmetic.sh <fragment.svg> <out.matrix>
#
# Substitutes the same color placeholders render.sh uses so the matrix
# bakes to palette roles (1=outline, 5=hair, 9=shirt, etc.) rather than
# arbitrary RGB.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BAKE_SWIFT="$SCRIPT_DIR/bake.swift"

FRAGMENT="$1"
OUT="$2"
# Resolve paths so cwd doesn't matter to the caller.
if [[ ! -f "$FRAGMENT" ]]; then
    echo "missing fragment: $FRAGMENT" >&2
    exit 1
fi
TMP_SVG="$(mktemp /tmp/tokade-bake.XXXXXX).svg"
TMP_PNG="$(mktemp /tmp/tokade-bake.XXXXXX).png"
trap 'rm -f "$TMP_SVG" "$TMP_PNG"' EXIT

# Defaults match the Boba preset in Palette.swift.
: "${SKIN:=#C7A5D9}"
: "${SKIN_LIGHT:=#DBC1E8}"
: "${SKIN_DARK:=#A07AB8}"
: "${HAIR:=#E8DCC4}"
: "${HAIR_DARK:=#A89473}"
: "${IRIS:=#4A7BC5}"
: "${SHIRT:=#5A7F3F}"
: "${SHIRT_LIGHT:=#7DA055}"
: "${SHIRT_DARK:=#3F5A2A}"
: "${PANTS:=#5C4033}"
: "${PANTS_LIGHT:=#7C5C45}"
: "${PANTS_DARK:=#3D2920}"
: "${BELT:=#8B6F47}"
: "${DARK:=#1A1A2E}"
: "${WHITE:=#FFFFFF}"

# Inline the fragment into a standalone SVG with the same viewBox and
# clip-path defs as the base sprite, so cosmetic geometry that references
# those clip-paths still resolves.
fragment_resolved="$(sed \
    -e "s|{{SKIN}}|$SKIN|g" \
    -e "s|{{SKIN_LIGHT}}|$SKIN_LIGHT|g" \
    -e "s|{{SKIN_DARK}}|$SKIN_DARK|g" \
    -e "s|{{HAIR}}|$HAIR|g" \
    -e "s|{{HAIR_DARK}}|$HAIR_DARK|g" \
    -e "s|{{IRIS}}|$IRIS|g" \
    -e "s|{{SHIRT}}|$SHIRT|g" \
    -e "s|{{SHIRT_LIGHT}}|$SHIRT_LIGHT|g" \
    -e "s|{{SHIRT_DARK}}|$SHIRT_DARK|g" \
    -e "s|{{PANTS}}|$PANTS|g" \
    -e "s|{{PANTS_LIGHT}}|$PANTS_LIGHT|g" \
    -e "s|{{PANTS_DARK}}|$PANTS_DARK|g" \
    -e "s|{{BELT}}|$BELT|g" \
    -e "s|{{DARK}}|$DARK|g" \
    -e "s|{{WHITE}}|$WHITE|g" \
    "$FRAGMENT")"

cat > "$TMP_SVG" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 -18 100 168" width="32" height="54" shape-rendering="geometricPrecision">
  <defs>
    <clipPath id="head-clip"><circle cx="50" cy="38" r="23"/></clipPath>
    <clipPath id="shirt-clip"><rect x="32" y="64" width="36" height="42" rx="6"/></clipPath>
    <clipPath id="pants-clip-r"><rect x="36" y="106" width="11" height="32" rx="3"/></clipPath>
    <clipPath id="pants-clip-l"><rect x="53" y="106" width="11" height="32" rx="3"/></clipPath>
    <clipPath id="arm-clip-r"><rect x="25" y="65" width="9" height="40" rx="4"/></clipPath>
    <clipPath id="arm-clip-l"><rect x="66" y="65" width="9" height="40" rx="4"/></clipPath>
  </defs>
  $fragment_resolved
</svg>
EOF

rsvg-convert -w 32 -h 54 "$TMP_SVG" -o "$TMP_PNG"

# Bake — palette env is passed to bake.swift so quantization matches.
SKIN="$SKIN" SKIN_LIGHT="$SKIN_LIGHT" SKIN_DARK="$SKIN_DARK" \
    HAIR="$HAIR" HAIR_DARK="$HAIR_DARK" IRIS="$IRIS" \
    SHIRT="$SHIRT" SHIRT_LIGHT="$SHIRT_LIGHT" SHIRT_DARK="$SHIRT_DARK" \
    PANTS="$PANTS" PANTS_LIGHT="$PANTS_LIGHT" PANTS_DARK="$PANTS_DARK" \
    BELT="$BELT" DARK="$DARK" WHITE="$WHITE" \
    swift "$BAKE_SWIFT" "$TMP_PNG" "$OUT"
