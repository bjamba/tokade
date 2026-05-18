#!/usr/bin/env bash
# bake-monsters.sh — rasterize each monster SVG at 32×32 and bake to a
# palette-indexed matrix. Each monster SVG uses palette placeholders that
# map to the same role glyphs as the Tokegotchi pipeline, so they can be
# rendered with a per-monster palette at runtime.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$REPO/Sources/Tokade/Resources/sprites/monsters"
BAKE_SWIFT="$SCRIPT_DIR/../tokegotchi/bake.swift"
mkdir -p "$OUT_DIR"

# Defaults — match the Tokegotchi palette so monsters use the same role
# glyph map at bake time. Per-monster palettes are applied at runtime via
# Palette.from(...) so the bake stays palette-neutral.
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

bake_monster() {
    local file="$1"
    local name="$(basename "$file" .svg)"
    local tmp_svg="$(mktemp /tmp/monster-bake-XXXXXX).svg"
    local tmp_png="$(mktemp /tmp/monster-bake-XXXXXX).png"
    trap "rm -f '$tmp_svg' '$tmp_png'" RETURN

    sed -e "s|{{SKIN}}|$SKIN|g" \
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
        "$file" > "$tmp_svg"

    rsvg-convert -w 32 -h 32 "$tmp_svg" -o "$tmp_png"
    SKIN="$SKIN" SKIN_LIGHT="$SKIN_LIGHT" SKIN_DARK="$SKIN_DARK" \
        HAIR="$HAIR" HAIR_DARK="$HAIR_DARK" IRIS="$IRIS" \
        SHIRT="$SHIRT" SHIRT_LIGHT="$SHIRT_LIGHT" SHIRT_DARK="$SHIRT_DARK" \
        PANTS="$PANTS" PANTS_LIGHT="$PANTS_LIGHT" PANTS_DARK="$PANTS_DARK" \
        BELT="$BELT" DARK="$DARK" WHITE="$WHITE" \
        swift "$BAKE_SWIFT" "$tmp_png" "$OUT_DIR/monster-$name.matrix"
    echo "  monster-$name ✓"
}

for svg in "$SCRIPT_DIR"/*.svg; do
    bake_monster "$svg"
done

echo "wrote $OUT_DIR"
