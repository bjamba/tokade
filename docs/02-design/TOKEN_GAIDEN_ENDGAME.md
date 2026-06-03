# Token Gaiden — Endgame & anti-bloat (design)

> *Design for the endgame epic (#97) and its children #93–#96.*
>
> **Last reviewed**: 2026-06-03
> **Owner**: @bjamba
> **Status**: design — **defaults proposed, not open questions** (correct any of
> them post-hoc; this doubles as the build spec for #93).

## The problem (the plateau)

Heavy or spiky Claude Code usage pumps gold, items, gear, cosmetics, and stat
growth into the pet faster than the game can absorb. With nothing scarce and
nothing aspirational left, the run reaches an **"infinite-cash" end state** —
no decisions, no tension, no reason to keep playing.

## Where the bloat comes from (code map)

| Source | Where |
|---|---|
| Item / food drops | `TickProcessor.process` (`toolDropThreshold`, `foodDropThreshold`, slash drops) |
| Gold + gear on victory | `EncounterEngine.resolve` via the combat paths in `TokenGaidenStore` |
| Cosmetic drops | tick + achievement/quest unlocks |
| Stat growth | training / skills |
| Carry-over | bloodline inheritance on hatch (~30% peak stats + gold + cosmetics) |

The inflow is effectively unbounded in usage; the **sinks are flat and finite**.
That asymmetry is the whole bug.

## The system

Four interlocking mechanisms. **#93 is mechanisms 1–2 + 4 (the economy spine);
#94/#95/#96 are the content that mechanism 3 sinks into.**

### 1. Soft caps & diminishing returns (the immediate anti-bloat)
Past a threshold, additional inflow tapers instead of compounding:
- **Drops**: once you hold ≥ N of an item, its drop chance decays (you stop
  stockpiling 400 breads).
- **Stat training**: cost-per-point rises with the stat; gains taper toward the
  99 cap so power curves instead of spikes.
- **Gold**: no hard cap, but see wealth-scaling below — gold you can't spend
  stops mattering, which is the point.

### 2. Wealth/power-scaled costs
Prices and upgrade costs scale with the player's **net worth and effective
power**, so a rich, strong pet still feels cost. A flat 50g potion is free to a
veteran; a potion that costs `base × f(netWorth)` keeps its bite. Applies to
shop prices (`Shop.swift`), training, and haggling.

### 3. Escalating sinks (the content — children)
Wealth needs ever-deeper destinations:
- **Tiered/exotic shops (#94)** — the primary gold sink; rarer goods gated by
  progress, priced on the wealth curve.
- **Boss ladder (#95)** — challenge gated by *materials/keys* you buy or earn,
  consuming resources; drops feed the exotic shops.
- **Quest chains (#96)** — long arcs that consume items/gold as inputs, not just
  hand out rewards.

### 4. Ascension / prestige (the *exit* from a maxed run)
The key idea other facets orbit. When a bloodline is effectively maxed, the
player can **Ascend**: retire the current line for a permanent **Legacy** bonus
(a slow meta-currency / prestige tier) and start fresh with scarcity reset but
*meaning* carried forward. This converts the dead-end "infinite cash" into a
deliberate, rewarding loop — the same trick idle games use to stay alive. Builds
on the existing `bloodline` inheritance rather than replacing it.

## How the children interlock

```
boss ladder (#95) ──drops materials──▶ exotic shops (#94)
        ▲                                      │
   keys/materials                         primary sink
        │                                      ▼
 quest chains (#96) ◀──narrates──  scaled economy (#93: caps + wealth-pricing)
        │                                      │
        └──────────── Ascension/Legacy (#93) ──┘  (resets scarcity, keeps meaning)
```

## Phasing (build order)

- **Phase 1 — economy spine (#93):** soft caps + diminishing returns + wealth/
  power-scaled costs. Ships the anti-bloat immediately, low content cost. Pure,
  testable balance functions.
- **Phase 2 — Ascension/Legacy (#93):** the prestige loop on top of bloodline.
- **Phase 3 — content (#94 shops, #95 bosses, #96 quests):** the escalating
  sinks + narrative, each its own issue, all leaning on the Phase 1 curves.

## Recommended starting numbers (all tunable)

- Item drop decay: drop chance × `max(0.1, 1 − heldCount / softCap)`, `softCap`
  ≈ 10 per item.
- Training cost: `base × (1 + currentStat × 0.15)` per point; gains halve past
  stat 70.
- Wealth price multiplier: `1 + log10(max(1, netWorth / 500))` (a 5,000g pet
  pays ~2×, a 50,000g pet ~3×) — gentle, logarithmic, never punishing early.
- Ascension unlock: available once peak stats sum ≥ ~80% of the soft cap *or*
  net worth crosses a high threshold; Legacy grants a small permanent
  per-ascension bonus (e.g. +2% inherited stats, stacking).

## Risks

- **Over-nerfing** the early game — all curves must be near-flat for a young
  pet; they only bite at the plateau. Keep the math logarithmic/soft.
- **Auto-play** (`AutoPlay.swift`) must respect the new costs so the autopilot
  doesn't trivially out-grind the sinks.
- Balance is iterative — ship Phase 1 behind clear constants and tune.
