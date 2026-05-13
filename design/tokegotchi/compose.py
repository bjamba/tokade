#!/usr/bin/env python3
"""compose.py — substitute SVG fragment placeholders + color placeholders.

Reads the base SVG, replaces:
  {{HAIR_BODY}}  → contents of hair-styles/$HAIR_STYLE.svg  (default: horns)
  {{HAT_BODY}}   → contents of cosmetics/hat/$HAT.svg       (default: empty)
  {{COLOR}}      → env var value (SKIN, SKIN_LIGHT, etc.)

Output goes to stdout (or to argv[2] if given).
"""
import os, sys, pathlib

HERE = pathlib.Path(__file__).parent

def read(path):
    p = HERE / path
    return p.read_text() if p.exists() else ""

base = read(sys.argv[1] if len(sys.argv) > 1 else "tokegotchi-base-v3.svg")

# --- Fragment placeholders ---
hair    = os.environ.get("HAIR_STYLE",   "horns")
hat     = os.environ.get("HAT",          "")
eyewear = os.environ.get("EYEWEAR",      "")
shirt   = os.environ.get("SHIRT_STYLE",  "tunic")
pants   = os.environ.get("PANTS_STYLE",  "long-pants")
belt    = os.environ.get("BELT_STYLE",   "leather")
cape    = os.environ.get("CAPE",         "")
held_r  = os.environ.get("HELD_R",       "")
held_l  = os.environ.get("HELD_L",       "")
base = base.replace("{{HAIR_BODY}}",    read(f"hair-styles/{hair}.svg"))
base = base.replace("{{HAT_BODY}}",     read(f"cosmetics/hat/{hat}.svg")          if hat     else "")
base = base.replace("{{EYEWEAR_BODY}}", read(f"cosmetics/eyewear/{eyewear}.svg")  if eyewear else "")
base = base.replace("{{SHIRT_BODY}}",   read(f"shirt-styles/{shirt}.svg"))
base = base.replace("{{PANTS_BODY}}",   read(f"pants-styles/{pants}.svg"))
base = base.replace("{{BELT_BODY}}",    read(f"belt-styles/{belt}.svg"))
base = base.replace("{{CAPE_BODY}}",    read(f"cosmetics/cape/{cape}.svg")        if cape    else "")
base = base.replace("{{HELD_R_BODY}}",  read(f"cosmetics/held/{held_r}.svg")      if held_r  else "")
base = base.replace("{{HELD_L_BODY}}",  read(f"cosmetics/held/{held_l}.svg")      if held_l  else "")

# --- Color placeholders ---
DEFAULTS = {
    "SKIN":        "#C7A5D9",
    "SKIN_LIGHT":  "#DBC1E8",
    "SKIN_DARK":   "#A07AB8",
    "HAIR":        "#E8DCC4",
    "HAIR_DARK":   "#A89473",
    "IRIS":        "#4A7BC5",
    "SHIRT":       "#5A7F3F",
    "SHIRT_LIGHT": "#7DA055",
    "SHIRT_DARK":  "#3F5A2A",
    "PANTS":       "#5C4033",
    "PANTS_LIGHT": "#7C5C45",
    "PANTS_DARK":  "#3D2920",
    "BELT":        "#8B6F47",
    "DARK":        "#1A1A2E",
    "WHITE":       "#FFFFFF",
    # Animation transforms — full SVG transform expressions.
    # 1 source pixel = 3.125 SVG units (100 viewBox / 32 source res).
    "HEAD_TRANSFORM":  "translate(0,0)",
    "R_ARM_TRANSFORM": "rotate(0 32 65)",
    "L_ARM_TRANSFORM": "rotate(0 68 65)",
    "R_LEG_TRANSFORM": "translate(0,0)",
    "L_LEG_TRANSFORM": "translate(0,0)",
}
for key, default in DEFAULTS.items():
    base = base.replace("{{" + key + "}}", os.environ.get(key, default))

out = sys.argv[2] if len(sys.argv) > 2 else None
if out:
    pathlib.Path(out).write_text(base)
else:
    sys.stdout.write(base)
