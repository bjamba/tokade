# ADR 0003 — Fixed bar thickness + explicit chart stability modifiers

- **Status**: Accepted
- **Date**: 2026-05-13
- **Deciders**: @bjamba

## Context

The Models tab has four horizontal stacked bar charts (Tokens by model,
Top 5 slash commands, Top 5 projects, Top 5 tool calls). Swift Charts
auto-derives several things from data iteration order:

- **Bar thickness** — divides available chart height by the number of
  categories. A chart with 2 categories gets fat bars; a chart with
  5 gets thin ones; bars resize when the user changes the time range.
- **Color domain** — assigns colors to the foreground-style key in
  whatever order the data is iterated. If the visible model set changes
  between renders (e.g., on hover), colors shuffle.
- **Stack segment order** — segments stack in data-array order. If
  the array reorders between renders, segments visibly reshuffle.

This produced two distinct ugly behaviors users reported:

1. **Bars getting fatter or thinner** depending on category count and
   time range, making the chart "breathe" visually as you flip through
   ranges
2. **Colors and segment order flickering on hover** — hovering one row
   would reorder colors across the whole chart, which is the worst kind
   of UI bug because it looks like a glitch but is fully deterministic
   in the SwiftUI Charts default behavior

## Decision

Three explicit modifiers, applied to every horizontal stacked bar chart
in the Models tab:

1. **`height: .fixed(12)`** on every `BarMark`. Bars are 12 pt thick
   regardless of category count or chart height.
2. **`chartYScale(domain: categoryOrder)`** — pins the categorical axis
   ordering to a pre-computed list sorted by total desc. Categories
   never reshuffle.
3. **`chartForegroundStyleScale(domain: modelDomain, range: modelRange)`**
   — pins each model name to a specific color from `modelColor()`. The
   `modelDomain` is pre-sorted by `sortedModels(...)` so the legend
   color sequence is deterministic.

Additionally, `stackedHorizontalChart(...)` pre-sorts the row array by
(category index, model index) before passing to `Chart {...}` so stack
segment order is deterministic.

`scripts/check.sh` greps for the three modifiers in `StatsView.swift`
and fails CI if any are missing.

## Consequences

**Positive**

- Charts read identically regardless of time range or hover state
- Eliminates a hard-to-diagnose visual jitter bug
- The 12 pt bar height also gives token-count annotations visual room

**Negative**

- The modifiers look decorative to a contributor reading the code; if
  they look like cleanup candidates they'll get deleted "to simplify"
  and the bugs return. Mitigated by CLAUDE.md + `scripts/check.sh`.
- 12 pt is a single magic number; if Tokade's panel ever resizes
  significantly we may need a different value. Acceptable for now.
- We trade Apple's adaptive layout for predictability. A user with a
  very tall panel sees more whitespace than they "should." Acceptable.

## Alternatives considered

- **Trust SwiftUI Charts defaults**. Was the original; produced the
  bugs above. Rejected.
- **Wrap chart in our own layout that calculates bar thickness from
  available height**. More math, same fragility. Rejected.
- **Use `BarMark`'s `width` parameter instead of `height`**. `width`
  is for vertical bars (x-categorical); irrelevant here.
