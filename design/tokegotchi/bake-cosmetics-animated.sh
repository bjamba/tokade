#!/usr/bin/env bash
# bake-cosmetics-animated.sh — for each cosmetic in the design folder, bake
# three animation-frame variants (idle, walk-a, walk-b) so cosmetics animate
# with their underlying body parts.
#
# Algorithm per (cosmetic, frame):
#   1. Render naked Tokegotchi with the frame's transforms → naked-FRAME.matrix
#   2. Render Tokegotchi with just this cosmetic + same transforms → full-FRAME.matrix
#   3. Diff (full - naked) → just-cosmetic matrix
#
# Output goes to Sources/Tokade/Resources/sprites/.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$REPO/Sources/Tokade/Resources/sprites"
mkdir -p "$OUT_DIR"

cd "$SCRIPT_DIR"

# Frame definitions. Counter-swing arm motion (FFVI-style "walking" — opposite
# arms forward in alternating frames).
declare -A IDLE=(
    [HEAD_TRANSFORM]="translate(0,0)"
    [R_LEG_TRANSFORM]="translate(0,0)"
    [L_LEG_TRANSFORM]="translate(0,0)"
    [R_ARM_TRANSFORM]="rotate(0 32 65)"
    [L_ARM_TRANSFORM]="rotate(0 68 65)"
)
declare -A WALK_A=(
    [HEAD_TRANSFORM]="translate(0,1.5)"
    [R_LEG_TRANSFORM]="translate(0,-3.125)"
    [L_LEG_TRANSFORM]="translate(0,0)"
    # Both arms rotate SAME direction in each frame. From the front-view
    # sprite this reads as "right arm forward, left arm tucked back": the
    # right arm swings outward (away from body) and the left arm under the
    # same rotation swings inward (toward body).
    [R_ARM_TRANSFORM]="rotate(15 32 65)"
    [L_ARM_TRANSFORM]="rotate(15 68 65)"
)
declare -A WALK_B=(
    [HEAD_TRANSFORM]="translate(0,1.5)"
    [L_LEG_TRANSFORM]="translate(0,-3.125)"
    [R_LEG_TRANSFORM]="translate(0,0)"
    [R_ARM_TRANSFORM]="rotate(-15 32 65)"
    [L_ARM_TRANSFORM]="rotate(-15 68 65)"
)

bake_frame() {
    # $1 = frame label (idle / walk-a / walk-b)
    # $2-N = name=value transform pairs
    local label="$1"; shift
    local args=("$@")
    local naked="/tmp/tg-naked-$label.matrix"

    # Render naked base for this frame.
    env "${args[@]}" HAIR_STYLE=__none__ SHIRT_STYLE=__none__ \
        PANTS_STYLE=__none__ BELT_STYLE=__none__ \
        HAT= EYEWEAR= CAPE= HELD_R= HELD_L= \
        ./render.sh tokegotchi-base-v3 > /dev/null
    cp tokegotchi-base-v3.matrix "$naked"
    cp "$naked" "$OUT_DIR/$label.matrix"

    # For each cosmetic, render the full Tokegotchi with just that cosmetic
    # + same frame transforms, then diff against the naked base.
    # The four "body-region" slots (hair/shirt/pants/belt) have non-empty
    # default values in compose.py, so we have to explicitly pass __none__
    # for the others. The "addition" slots (hat/eyewear/cape/held_r) default
    # to empty so they only need to be re-blanked when iterating.
    bake_one_cosmetic() {
        local slot="$1" name="$2" var="$3"
        local full="/tmp/tg-full-$slot-$name-$label.matrix"
        env "${args[@]}" "$var=$name" \
            $(if [[ "$var" != "HAIR_STYLE" ]];   then echo "HAIR_STYLE=__none__"; fi) \
            $(if [[ "$var" != "SHIRT_STYLE" ]];  then echo "SHIRT_STYLE=__none__"; fi) \
            $(if [[ "$var" != "PANTS_STYLE" ]];  then echo "PANTS_STYLE=__none__"; fi) \
            $(if [[ "$var" != "BELT_STYLE" ]];   then echo "BELT_STYLE=__none__"; fi) \
            $(if [[ "$var" != "HAT" ]];          then echo "HAT="; fi) \
            $(if [[ "$var" != "EYEWEAR" ]];      then echo "EYEWEAR="; fi) \
            $(if [[ "$var" != "CAPE" ]];         then echo "CAPE="; fi) \
            $(if [[ "$var" != "HELD_R" ]];       then echo "HELD_R="; fi) \
            ./render.sh tokegotchi-base-v3 > /dev/null
        cp tokegotchi-base-v3.matrix "$full"
        local outname="tg-$slot-$name"
        if [[ "$label" != "idle" ]]; then outname="$outname-$label"; fi
        swift diff-matrices.swift "$naked" "$full" "$OUT_DIR/$outname.matrix"
        echo "  $outname ✓"
    }

    echo "→ $label"

    # Hair (11 — every catalog hair style)
    for hs in horns spiky cat-ears pigtails mohawk antennae long bald flame mushroom tentacles; do
        bake_one_cosmetic hair "$hs" HAIR_STYLE
    done
    # Shirts (6)
    for s in tunic vest striped lab-coat red-robe jester-motley; do
        bake_one_cosmetic shirt "$s" SHIRT_STYLE
    done
    # Pants (6)
    for p in long-pants shorts kilt bell-bottoms blue-trousers striped-leggings; do
        bake_one_cosmetic pants "$p" PANTS_STYLE
    done
    # Belts (2)
    for b in leather gold; do
        bake_one_cosmetic belt "$b" BELT_STYLE
    done
    # Hats (7)
    for h in beanie wizard-hat cap crown halo jester octopus; do
        bake_one_cosmetic hat "$h" HAT
    done
    # Eyewear (5)
    for e in round-glasses shades monocle heart-glasses eye-patch; do
        bake_one_cosmetic eyewear "$e" EYEWEAR
    done
    # Capes (4)
    for c in red-cape blue-cape rainbow bat-wings; do
        bake_one_cosmetic cape "$c" CAPE
    done
    # Held items (8) — currently right-handed only; the held-L slot is
    # reserved for future dual-wield gear.
    for h in sword staff shield magic-wand crystal-ball mug fish rubber-duck; do
        bake_one_cosmetic held "$h" HELD_R
    done
}

# Convert associative array to env-var args.
to_args() {
    declare -n a=$1
    local result=()
    for k in "${!a[@]}"; do
        result+=("$k=${a[$k]}")
    done
    printf '%s\0' "${result[@]}"
}

idle_args=()
while IFS= read -r -d '' v; do idle_args+=("$v"); done < <(to_args IDLE)
a_args=()
while IFS= read -r -d '' v; do a_args+=("$v"); done < <(to_args WALK_A)
b_args=()
while IFS= read -r -d '' v; do b_args+=("$v"); done < <(to_args WALK_B)

bake_frame idle    "${idle_args[@]}"
bake_frame walk-a  "${a_args[@]}"
bake_frame walk-b  "${b_args[@]}"

echo "Done. Wrote: $OUT_DIR"
