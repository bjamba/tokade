# Tokeyo Town — Per-repo districts (design)

> *Design proposal for issue #80 (the geographic half deferred from #43).*
>
> **Last reviewed**: 2026-05-31
> **Owner**: @bjamba
> **Status**: design (no implementation yet — needs sign-off before building)

## Problem

Today a Tokeyo Town = one adopted repo. Terrain is seeded once from
repo-level signals (primary language → biome, LOC → map size, age → era,
recent commits → lushness), and ongoing Claude usage anywhere in that repo
feeds one shared resource pool. But in a real monorepo you work in distinct
**sub-packages** — `packages/api`, `packages/web`, `services/worker` — and
the town has no way to reflect *where* in the repo you actually spend time.
The promise of #80: a monorepo's sub-packages grow into distinct
**districts** (neighborhoods) within the town, so the map mirrors your work.

## Approach

Three layers, each shippable on its own (phasing below).

### 1. Sub-package detection (scan-time, local-only)

`RepoScanner` already walks the tree. Extend it to identify sub-packages —
immediate-to-shallow subdirectories that are meaningful units:

- **Manifest-anchored** (preferred): a subdir containing its own
  `Package.swift` / `package.json` / `pyproject.toml` / `go.mod` /
  `Cargo.toml` / `build.gradle`, etc.
- **Fallback** (no manifests): top-level source directories (`src/`, `app/`,
  `services/*`, `packages/*`) by LOC.

Cap at **N districts** (proposed 3–8) — take the top sub-packages by LOC,
fold the remainder into a "downtown"/core district. A single-package repo
yields exactly one district == the whole town (graceful degradation to
today's behavior). Stays 100 % local — no network, no Claude calls (preserves
the ADR-0006 §3 contract).

### 2. cwd → district mapping (accrual-time)

Events already carry `cwd`. At accrual, map each in-repo event to its owning
district by **longest-prefix match** against the detected sub-package paths
(fall back to the core district). Track per-district activity (events,
tokens, last-active) over time. This is the data spine and is cheap.

### 3. Geography & growth (render-time)

Partition the town map into contiguous district zones (seeded
deterministically by `townId`, e.g. a coarse Voronoi or grid split), sized by
each sub-package's LOC. A district's lushness/population/growth then tracks
**your ongoing activity in that sub-package**: a hot package's district
booms; a neglected one stays sparse. `InitialTownPlanner` seeds starter
buildings per district instead of one global cluster.

## Data model (additive, save-compatible)

```
TokeyoTownState {
  ...
  districts: [District]?          // optional → old saves decode as nil (one implicit district)
}

District {
  id: String                      // stable, derived from sub-package path
  name: String                    // display name (sub-package dir)
  rootSubpath: String             // relative path under repoPath
  originLOC: Int                  // size at scan time → zone area
  bounds: TileRegion              // assigned map zone
  activityTokens: Int             // ongoing, from cwd→district mapping
  lastActiveAt: Date?
}
```

Resource attribution stays **global** for v1 (don't fragment the economy);
per-district resource pools are a possible later refinement.

## Phasing

- **Phase 1 — data only.** Detect sub-packages + cwd→district mapping +
  per-district activity counters. No visible map change yet. Low risk;
  unlocks a "districts" readout and validates the mapping.
- **Phase 2 — geography.** Spatial partition + per-district seeding/growth
  (the visible neighborhoods). The bulk of the work (partitioning +
  rendering + save migration).
- **Phase 3 — rescan.** Wire the currently-missing rescan path (ADR-0006
  notes terrain is frozen at creation) so new sub-packages appear as new
  districts over a repo's life.

## Open questions (need a decision before Phase 2)

1. **District cap** — 3–8? And how to present the "everything else" core.
2. **Sub-package definition for manifest-less repos** — top-level source dirs
   only, or a heuristic on directory size/file count?
3. **Partition method** — grid (simple, blocky) vs Voronoi (organic) vs
   growth-from-seed (prettiest, most code).
4. **Save migration** — lazily synthesize a single default district for
   existing towns, or require a rescan to populate districts?
5. **Resource attribution** — keep global (proposed), or per-district pools?

## Risks

- Spatial partitioning + rendering complexity (Phase 2 is the real cost).
- Save-schema migration for existing towns.
- Balance: districts must add texture without fragmenting the economy or
  the player's attention.

## Relationship to shipped work

- Builds directly on #43 (model-mix resources) and #31 (repo-gated accrual) —
  the cwd→repo gating is already in `ResourceAccrual`; districts extend it to
  cwd→sub-package.
- Phase 3 (rescan) overlaps the long-noted "terrain frozen at creation" gap
  in ADR-0006 — worth doing together.
