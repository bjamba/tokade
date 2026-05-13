# ADR 0001 — Server `%` is ground truth; raw tokens are a separate dimension

- **Status**: Accepted
- **Date**: 2026-05-10
- **Deciders**: @bjamba

## Context

Tokade reads two unrelated kinds of numbers from Claude:

1. **Per-message token counts** from `~/.claude/projects/*.jsonl` —
   precise integers, easy to sum, but model-mix-dependent.
2. **`5h%` and `7d%` utilization** from the statusline JSON Claude Code
   pipes us — a single number per snapshot, server-authoritative, already
   incorporates Anthropic's per-model weighting.

Early attempts to display both as "your budget" caused user confusion:
"Why does my Opus session show 500K tokens but the 5h bar say 60%?"
Because Anthropic applies undisclosed per-model weights (Opus burns more
budget per token than Sonnet, which burns more than Haiku), raw tokens
don't translate to `%` of budget without those weights.

We don't have the weights. We can't infer them reliably either: they
change, they may differ by plan, and a per-snapshot inference would be
noisy.

## Decision

Treat the two numbers as **different dimensions**, never combined:

- **Budget tab** answers "how much of my limit am I using?" Always in
  `%`, always sourced from the server snapshot. Raw tokens never appear
  on a Budget chart.
- **Models tab** answers "where are my tokens going?" Always in raw
  tokens. Budget `%` never appears on a Models chart.
- **Trends tab** is raw tokens because the long-tail trend (heatmap,
  YTD) is more useful in absolute numbers than `%` (which would just
  be the rate-limit ceiling repeated).

The README and the audit explicitly call this out as a limitation.

## Consequences

**Positive**

- Users can't mix the two interpretations and reach a wrong conclusion
- "Why does the math not add up?" → because the two charts answer
  different questions, by design
- We never need to know Anthropic's weighting to be honest about
  utilization — the server tells us directly

**Negative**

- Two tabs that look similar at a glance but mean different things
- Users who *want* "tokens consumed against my plan" can't get an
  exact answer from us; we can only approximate by inverting
  `local_tokens / server_pct * 100` per snapshot (the Past 5h Windows
  chart does this for historical bars)
- The header copy on each chart matters more than usual; if the
  difference isn't clear, users will conflate them

## Alternatives considered

- **Compute weights ourselves** from observed `5h%` deltas vs local
  token deltas. Fragile — weights vary by plan, may change. Rejected.
- **Display tokens scaled into "budget units" using a constant**.
  Pretends to a precision we don't have. Rejected.
- **Hide the raw-tokens charts entirely**. Too much loss of insight —
  power users want to see which projects burn tokens, which is
  inherently a raw-tokens question. Rejected.
