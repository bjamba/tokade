# Tokade tab — design

> **Last reviewed**: 2026-05-13
> **Owner**: @bjamba
> **Status**: design (no implementation yet)
> **Companion ADR**: [0005-tokade-tab-rpg-system.md](../adr/0005-tokade-tab-rpg-system.md)

## Vision

The Tokade tab is a small RPG that lives inside the Tokade menu bar app and is fueled by your real Claude Code telemetry. You raise a creature called a **Tokegotchi**, walking it through *regions* (your projects), fighting monsters, completing quests, and aging it through tokens you spend with Claude. The longer it lives, the better.

It is not a Tamagotchi (passive observation). It is not Stardew Valley (active sim). It sits in between: telemetry generates events; the player makes light tactical choices at occasional encounters.

The aesthetic target is **SNES-era pixel-art JRPG** — Final Fantasy VI, Chrono Trigger. Tokegotchis are ~32×54 pixel sprites, animated by transforms on named body parts.

---

## Player experience

### First launch

A character creator screen lets the player pick:

| Trait | Options | Notes |
|---|---|---|
| Skin color | 6 swatches (lavender, peach, sage, sand, slate, coral) | Body color |
| Iris color | 6 swatches | Saturated, distinguishable at 32×54 |
| Hair style | 11 styles | horns, spiky, cat-ears, pigtails, mohawk, antennae, long, bald, flame, tentacles, mushroom |
| Hair color | 6 swatches | Independent of style |
| Name | free text (12 char cap) | Default "Boba" |

This gives **6 × 6 × 11 × 6 = 2,376 visible base appearances** — plenty of identity without a customization rabbit-hole.

### The game loop

1. **Work in Claude Code.** Telemetry events fire: messages, tool calls, slash commands.
2. **Items drop, HP drains.** Specific kinds of work generate specific kinds of items (see "Tick economy" below). Token consumption drains HP.
3. **Open the Tokade tab to check on the pet.** Stats, current region, recent drops, active quests, idle animation.
4. **Take light actions** — feed the pet, accept a quest, equip a cosmetic, travel to a previously-visited region's town center.
5. **Encounter events fire as you accumulate "steps"** (LoC + tool calls + token output). Monsters drop EXP/gold; NPCs offer quests/skills/items; shops sell cosmetics and equipment.
6. **The pet ages with every token consumed.** When age points exhaust the lifespan, the pet dies a peaceful, celebrated death. A new generation hatches with partial inheritance.

The player's long-term score is **how many days each Tokegotchi lived**, recorded in a Hall of Fame.

---

## Tab layout

```
┌────────────────────────────────────────────┐
│ Tokade tab                                 │
├────────────────────────────────────────────┤
│  ┌──────────────────────────────────────┐  │
│  │  Region: tokade  (Iron Fortress)     │  │
│  │  Day 12 · Reputation: 47             │  │
│  │                                      │  │
│  │     [animated sprite, idle/walk]     │  │
│  │            "Boba"                    │  │
│  │                                      │  │
│  │  HP ████████░░ 82/95                 │  │
│  │  SP ██████░░░░ 60/80                 │  │
│  │  Age 312K / 500K  · Gen 3            │  │
│  │  STR 18  DEX 22  INT 31  AGI 14  CHA 26 │
│  └──────────────────────────────────────┘  │
│                                             │
│  ┌──────────┬──────────┬──────────┐         │
│  │Inventory │ Quests   │ Events   │         │
│  ├──────────┴──────────┴──────────┤         │
│  │ 🍖 Hearty meat × 3              │         │
│  │ 🧪 Sonnet potion × 2            │         │
│  │ 🏋 Dumbbell (STR +1) × 1       │         │
│  │ 🗡 Iron Sword [equipped]       │         │
│  └────────────────────────────────┘         │
│                                              │
│  ▸ A wild Compile Beetle appeared! (tap)    │
└─────────────────────────────────────────────┘
```

Sub-sheets that open over the main panel:

- **Character sheet** — full stats, skills learned, gear equipped, ancestry
- **Region map** — visited regions with discovered nodes, current location, fast-travel (only within current region)
- **Battle modal** — passive (auto-resolve) or active (4-button menu) depending on user toggle
- **Quest dialog** — NPC text + quest description + accept/decline
- **Shop** — list of items with gold prices
- **Hall of Fame** — past generations, peak stats, days lived

---

## Layer 1: Tick economy

Every Claude Code event generates a game effect. **This is the central mechanic.**

### Token consumption → HP drain

| Model | HP drain |
|---|---|
| Haiku | 1 HP per 10K tokens |
| Sonnet | 1 HP per 5K tokens |
| Opus | 1 HP per 2K tokens |

HP persists between sessions — no auto-regen. A heavy Opus day leaves the pet wounded next morning.

### Token consumption → age

Aging is the long-term version of HP drain. **Aging is irreversible** (except via Youth Elixir).

| Model | Age multiplier |
|---|---|
| Haiku | ×0.5 per token |
| Sonnet | ×1.0 per token |
| Opus | ×2.0 per token |

Default `lifespan = 500K` age points (~1 week of moderate mixed-model use). Aging only happens when CC actively emits tokens; vacations don't age the pet.

### Tool calls → stat-boost item drops

Each tool that has high user-controllability drops a themed stat item:

| Stat | Source tool(s) | Drop |
|---|---|---|
| STR | `Bash` | dumbbell, axe, anvil |
| DEX | `Edit`, `Write` | chisel, scalpel, brush |
| INT | `WebFetch`, `WebSearch` | scroll, lens, tome |
| AGI | switching cwd + `Task` | boots, signal flag, map |
| CHA | sustained messages in single project | banner, signet ring, lyre |

Low-user-control tools (`Read`, `Grep`, `Glob`, `TodoWrite`) drop **generic scrap**, sold at shops for a few gold each.

Drop weights are not uniform — Bash drops 60% STR items, 10% each of other stats. Weighted random rewards diversification but doesn't deterministically punish specialization.

### Skills (slash commands) → potion drops

Using a Claude Code skill (slash command) drops a **potion** that refills SP. Different skills produce different rarity potions:

| Skill complexity | Drop |
|---|---|
| Common skills (`/review`, `/clear`) | small SP potion (+10 SP) |
| Heavier skills (`/security-review`) | medium SP potion (+30 SP) |
| Custom user-defined skills | rare SP potion (+60 SP) |

### File edits → food drops

`Edit` / `Write` / `NotebookEdit` calls drop **food items** that recover HP.

| Edit size | Drop |
|---|---|
| ≤10 LoC | bread (+5 HP) |
| 10–100 LoC | hearty meat (+25 HP) |
| 100+ LoC | feast (+75 HP) |

The bigger the change you write, the better the food.

---

## Layer 2: State model

Lives in `~/.tokade/games/tokegotchi.json` (file mode 0600).

```jsonc
{
  "identity": {
    "name":       "Boba",
    "generation": 3,
    "bornAt":     "2026-05-13T15:42:08Z",
    "ageTokens":  312000,        // accumulated weighted token count
    "appearance": {
      "skin":      "lavender",
      "iris":      "blue",
      "hairStyle": "horns",
      "hairColor": "coral"
    }
  },
  "vitals": {
    "hp":     82,
    "hpMax":  95,                // derived: 80 + (STR + DEX) * 2
    "sp":     60,
    "spMax":  80,                // derived: 40 + (INT + CHA) * 2
    "stats":  { "STR": 18, "DEX": 22, "INT": 31, "AGI": 14, "CHA": 26 }
  },
  "progress": {
    "exp":      450,
    "gold":     1284
  },
  "world": {
    "currentRegion": "code/tokade",
    "reputation":    { "code/tokade": 47, "code/old-project": 12 }
  },
  "inventory": {
    "items":         { "bread": 4, "hearty-meat": 3, "sonnet-potion": 2, "dumbbell": 1, "revive-stone": 1 },
    "equippedCosmetic": { "hair": "horns", "shirt": "tunic", "pants": "long-pants", "hat": null, "eyewear": "shades" },
    "equippedGear":  { "weapon": "iron-sword", "amulet": null, "ring": null, "armor": null },
    "skillsLearned": ["strike", "mend", "athletics", "persuasion"],
    "activeQuests":  ["compile-beetle-cull", "find-the-librarian"]
  },
  "bloodline": {
    "ancestors": [
      { "name": "Mochi", "generation": 1, "peakStats": { /* ... */ }, "daysLived": 8, "causeOfDeath": "natural" },
      { "name": "Yuki",  "generation": 2, "peakStats": { /* ... */ }, "daysLived": 4, "causeOfDeath": "hp-zero" }
    ]
  }
}
```

There is no explicit "level" — age in days lived is the score.

---

## Layer 3: Regions and world

Each project (cwd) maps to a **region**. Regions are matched by **cwd prefix**, so `~/code/foo` and `~/code/foo/subdir` are the same region.

### Region content (seeded + grown)

When a new cwd is first observed, the system analyzes the project to **seed** the region's flavor (language, dependency manager, file count, etc.):

| Project signature | Region flavor |
|---|---|
| Swift / Xcode project | Stonework Town (stoic architecture, granite golems) |
| Python / poetry | Garden Village (lush flora, plant-themed monsters) |
| Rust / cargo | Iron Fortress (industrial, mechanical foes, blacksmith shop) |
| JS/TS / npm | Bazaar (busy market, trickster NPCs, deal-making) |
| Go / mod | Open Steppe (wide plains, fast couriers, wolves) |
| (no project file) | Wilderness (unstructured, more monsters than NPCs) |

The flavor seeds **what's possible** in the region — monster types, NPC archetypes, dungeon theme — but everything is hidden.

### Discovery via LoC steps

The player explores a region through **steps**. The step formula:

```
steps = (lines_edited * 1.0) + (tool_calls * 0.5) + (output_tokens / 200)
```

This means even chat-heavy days advance discovery; refactor-heavy days advance much faster.

| Step threshold | Unlocked |
|---|---|
| 0     | Open road (just walking) |
| 200   | First village (1 NPC, shop opens) |
| 1500  | More NPCs, side paths visible |
| 5000  | Dungeon discovered (boss monster, rare drop) |
| 15000 | Hidden zone (mythic NPC, late-game quest) |

After the first NPC is discovered, **fast-travel** between nodes within the same region becomes available. Travel between *regions* still requires switching cwd in CC.

### Reputation

Reputation per region grows with **sustained messaging in that project's cwd**. Specifically: every 50 messages in a region grants +1 reputation. Reputation caps at 100. High reputation unlocks:

- Shop discounts (≥30)
- Special quests from NPCs (≥50)
- A region-flavored cosmetic gift (≥75)
- A late-game item (≥100, mythic)

---

## Layer 4: Encounters

### Monster combat

User-toggleable between two modes:

- **Passive**: auto-resolve based on stats vs monster stats. Result appears as a brief banner. Used by default; respect "I'm coding, don't interrupt me."
- **Active**: turn-based menu RPG modal. `Attack` / `Use Skill` / `Use Item` / `Run`. 2–6 turns until one side drops.

A subset of monsters (bosses, rare encounters) trigger active mode regardless of toggle — these are the meaningful fights.

Combat math:
- Damage dealt = `(attacker_STR or weapon_atk) - target_DEF` with stat-scaling from skills
- Skill damage = `base + relevant_stat × multiplier` (e.g., Fireball = `10 + INT × 2.5`)
- Dodge chance = `target_AGI - attacker_AGI` percent (capped 5–60%)

### NPCs

NPCs appear in regions at discovery thresholds. Each NPC has a role:

| Role | What they do |
|---|---|
| **Merchant** | Sells items, cosmetics, gear |
| **Trainer** | Teaches in-game skills (spend EXP) |
| **Quest-giver** | Offers explicit prompt-style quests |
| **Lore-keeper** | Background flavor + sometimes hints |

NPCs sometimes block paths and trigger **D&D-style skill checks** (see Layer 6).

### Quests

Two distinct flavors:

- **NPC quests** are explicit, prescriptive: *"Use `/review` three times today and report back."* They appear in the Quest log, you complete them by doing the thing in Claude Code, you return to the NPC for the gold/EXP/item reward. These intentionally try to **change your CC behavior**.
- **System achievements** are implicit milestones: *"Hello, Opus" (first Opus message), "Three-model day", "7-day streak"*. They fire silently when triggered and reward small items + a Hall-of-Fame entry. They reward **what you naturally do**.

### Encounter frequency

Default scaling:

| Session intensity | Monsters | NPC interactions | Achievement triggers |
|---|---|---|---|
| Light (10K LoC, 1hr) | 1–2 | 0–1 | 0–2 |
| Medium (50K LoC, 4hr) | 5–8 | 2–4 | 3–6 |
| Heavy (200K LoC, 8hr+) | 15–25 | 6–10 | 8–15 |

A `encounter_frequency_multiplier` setting (default 1.0, range 0.25–4.0) lets the player tune.

---

## Layer 5: Aging, death, inheritance

### Aging

Aging is purely token-driven; see Layer 1 for the per-model multiplier. Pet ages only when CC is actively consuming tokens.

When `age > 0.7 × lifespan`, the pet enters **Elder state**: hair tinged gray, idle pose tired, occasional "I'm not as quick as I once was" dialog. Visible to the player.

### Two-track death

- **Natural death** (age reaches lifespan): peaceful eulogy line, sprite fades, Hall-of-Fame entry written. **No revive possible** — death by old age is final. The achievement is the days lived.
- **HP=0 death**: pet enters **Critical state** for 24 real-time hours. Player can:
  - Use a Revive Stone (consumable) → restore HP to max, abort death
  - Refill HP via food items → exit critical state naturally
  - Do nothing → tragic eulogy + next generation

### Lifespan-extension items

| Item | Effect | Source |
|---|---|---|
| **Revive Stone** | Auto-consumed on HP=0 to restore HP. No effect on natural death. | Rare boss drop, 5000 gold |
| **Youth Elixir** | Pauses aging for next 24 real-time hours | Quest chain, 2000 gold |
| **Phoenix Feather** | Pauses aging for 7 real-time days | Single hand-placed in a late-game dungeon |
| **Ancient Tonic** | Halves age-cost of next 100K tokens | Crafted (recipe is a quest reward) |

### Inheritance on death

| Trait | Carryover |
|---|---|
| Each stat (STR/DEX/INT/AGI/CHA) | 30% of peak value |
| Learned skills | Carry at 50% effectiveness; re-train by spending half original EXP |
| Town reputation per region | 100% — "your ancestor was the great Boba" |
| Gold | 10% |
| Inventory items | All carry |
| Equipped cosmetics | All carry |
| Equipped gear | Carry only one piece (player picks); rest goes to Hall |
| Appearance | 70% chance each color (skin/iris) inherits; hair style re-rolls |

### Hall of Fame

- Last 20 generations stored in full detail (name, peak stats, days lived, cause of death, ancestry quotes)
- Older entries roll up to summary (just name + days lived) — infinite history at low storage cost
- Browsable in a sheet within the Tokade tab

---

## Layer 6: Skills

Two distinct categories. Both bought with **EXP** from Trainer NPCs.

### Combat skills (20 total)

Used during battle, cost SP per use. Damage/effect scales with the relevant stat.

| Category | Skills | Stat scaling |
|---|---|---|
| **Damage** (4) | Strike, Pierce, Fireball, Inspire-Attack | STR / DEX / INT / CHA |
| **Heal** (4) | Mend, Greater Heal, Group Heal, Resurrection | CHA / CHA / CHA / INT |
| **Buff** (4) | Power-Up (+STR), Quickness (+AGI), Focus (+INT), Rally (+all) | self-targeted, multi-turn |
| **Debuff** (4) | Weaken, Slow, Confuse, Demoralize | inflicted on monster |
| **Utility** (4) | Block, Escape, Steal, Analyze | combat tools, no damage |

Example: Fireball cost = 12 SP. Damage = `10 + INT × 2.5`. So at INT=20, Fireball deals 60 damage.

### RPG skills (10 total)

D&D-style narrative skills triggered by **skill checks** in dialog. Possessing the skill + meeting a stat threshold unlocks alternative branches.

| Skill | Stat | What it unlocks |
|---|---|---|
| Athletics | STR | force doors, climb walls, push obstacles |
| Lockpicking | DEX | open chests + gates without keys (consumes lockpicks) |
| Stealth | DEX | sneak past monsters, find hidden NPCs |
| Investigation | INT | clues in environments, identify item rarity |
| Arcana | INT | decode runes, identify magical items |
| Persuasion | CHA | extra quest dialog options, shop discounts |
| Intimidation | CHA | force NPC info, scare low-tier monsters |
| Insight | CHA | detect lying NPCs |
| Survival | DEX or INT | track monsters, find wilderness shortcuts |
| Performance | CHA | entertainer NPCs, festival quests |

Example branching scene:

> *A locked iron gate bars the path.*
> [Athletics 25] kick it down (costs 15 HP)
> [Lockpicking 15] pick the lock (consumes lockpick)
> [Persuasion 20] convince the guard (requires reputation ≥ 30)
> [back away]

Each option requires the skill **and** the stat threshold. Player builds determine which paths open.

---

## Sprite + animation system

> See [docs/adr/0005-tokade-tab-rpg-system.md](../adr/0005-tokade-tab-rpg-system.md) for the architecture rationale.

- **Source resolution**: 32×54 pixels (viewBox `0 -18 100 168`)
- **Proportions**: FFVI-ish humanoid — head ~33% of height, torso ~30%, legs ~37%
- **Color**: 16-color palette per sprite, parameterized by ROLE (skin/skin-light/skin-dark/hair/hair-dark/iris/etc.); the runtime swaps actual RGB values to produce 6 skin × 6 iris × 6 hair-color variants of every shape from a single matrix
- **Animation**: per-part transforms (`HEAD_TRANSFORM`, `R_ARM_TRANSFORM`, `L_ARM_TRANSFORM`, `R_LEG_TRANSFORM`, `L_LEG_TRANSFORM`). At least 3 frames per Tokegotchi: idle, walk-A, walk-B
- **Stylization**: every other source pixel row darkened 12% for a pixel-grid scanline feel (toggleable)
- **Outline**: 1-pixel dark border applied at source resolution to every silhouette
- **In-app render**: matrix → nearest-neighbor upscale → blit to SwiftUI Canvas. No PNG files at runtime.

### Cosmetic slots and inventory

| Slot | v1 items |
|---|---|
| Hair (style chosen at creation) | 11: horns, spiky, cat-ears, pigtails, mohawk, antennae, long, bald, flame, tentacles, mushroom |
| Hat | 7: beanie, wizard-hat, cap, crown, jester, octopus, halo |
| Eyewear | 5: shades, round-glasses, eye-patch, monocle, heart-glasses |
| Shirt | 6: tunic, striped, vest, red-robe, lab-coat, jester-motley |
| Pants | 6: long-pants, shorts, blue-trousers, kilt, bell-bottoms, striped-leggings |
| Belt | 2: leather, gold |
| Cape | 4: red-cape, blue-cape, rainbow, bat-wings |
| Held items (R + L) | 8: sword, shield, staff, mug, rubber-duck, crystal-ball, fish, magic-wand |

Total: **49 cosmetic items across 9 slots** at v1. Each is one ~5-line SVG; new items take minutes to author.

### Animation rig

The base sprite has named part groups: `head`, `r-arm`, `l-arm`, `r-leg`, `l-leg`. Each accepts a full SVG transform expression as an env-var-driven placeholder.

Locked canonical animation frames:

| Frame | Transforms |
|---|---|
| **idle** | all noop |
| **walk-A** | head `translate(0,1.5)`, r-leg `translate(0,-3.125)`, both arms `rotate(8 ...)` (body twists right) |
| **walk-B** | head `translate(0,1.5)`, l-leg `translate(0,-3.125)`, both arms `rotate(-8 ...)` (body twists left) |

Both arms tilt the **same direction** in each frame — front-view walking shows up as body sway, not counter-swing. Cycle at ~6fps to read as walking.

Future animations using the same rig: `eat`, `sleep`, `wave`, `attack`, `cast`, `death`.

---

## Open questions (not blocking v1)

1. **Per-region soundtrack?** Could tie to project language. Big scope addition; defer.
2. **Cross-Tokegotchi memory?** Should ancestors leave physical objects in regions (graves, journals)? Atmospheric but expensive.
3. **Custom NPC dialog from project metadata?** Hooking into `package.json` or `README.md` for region flavor text. Risky for privacy; defer.
4. **Cosmetic mutations on inheritance** — should the new generation occasionally inherit a *new* color (e.g., the ancestor's blue eyes mutate to teal)? Adds variety; complicates UI.
5. **Active animations** — beyond walk + idle, when does the pet visibly do something? On feed, on level up, on quest accept?

---

## Future (v2+)

- Multiplayer Tokegotchi exchange — gift cosmetics between users
- A second game in the tab — pure card game or puzzle, share the Tokegotchi state
- "Year-in-Claude" Polaroid review at year-end, generated from Hall of Fame data
- Tokegotchi customization (rename mid-life, color-shift via potion)
- Cosmetic crafting system — combine items at a workbench NPC
