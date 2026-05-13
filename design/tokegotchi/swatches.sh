#!/usr/bin/env bash
# swatches.sh — render the v3 base sprite under each of the 6 skin presets.
# Demonstrates that the parameterized palette swap works end-to-end.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p swatches

declare -A PRESETS=(
  [lavender]="#C7A5D9 #DBC1E8 #A07AB8"
  [peach]="#E5A88E #F0C0A8 #B8826A"
  [sage]="#A5D9B5 #C5E8CC #7AB590"
  [sand]="#DDC893 #ECDDB5 #B89E5C"
  [slate]="#A8B5C7 #C5CFDB #7E8AA0"
  [coral]="#E89C9C #F2B8B8 #B86E6E"
)

for name in "${!PRESETS[@]}"; do
  read -r SKIN SKIN_LIGHT SKIN_DARK <<< "${PRESETS[$name]}"
  echo "→ $name  ($SKIN / $SKIN_LIGHT / $SKIN_DARK)"
  SKIN="$SKIN" SKIN_LIGHT="$SKIN_LIGHT" SKIN_DARK="$SKIN_DARK" \
    ./render.sh tokegotchi-base-v3 > /dev/null
  cp tokegotchi-base-v3-pixel.png   "swatches/skin-$name.png"
  cp tokegotchi-base-v3.matrix      "swatches/skin-$name.matrix"
done

echo
echo "wrote swatches/skin-{lavender,peach,sage,sand,slate,coral}.{png,matrix}"
