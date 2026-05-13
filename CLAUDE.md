# Tokade — agent guardrails

These are the rules an LLM agent (or any contributor) must follow when
working in this repo. Each rule is paired with the mechanism that enforces
it. Rules without enforcement are wishes; we don't keep wishes here.

> If you propose a change that would violate a rule, state the rule, the
> reason it exists, and ask the user before working around it. Don't
> silently disable an enforcement mechanism.

---

## Repo overview

Tokade is a macOS menu bar app written in Swift / SwiftUI. It reads Claude
Code's local session JSONL + a statusline JSON file, and surfaces budget
utilization, model-by-model token counts, and trend charts. No network
calls; all data stays on the user's machine.

Top-level layout:

- `Sources/Tokade/` — all production Swift
- `Tests/TokadeTests/` — XCTest target
- `scripts/check.sh` — guardrail grep checks (CI + pre-commit)
- `.github/workflows/ci.yml` — build + test + guardrails on every PR
- `docs/` — architecture, ADRs, runbooks
- `.productionize-me/` — audit/plan artifacts (don't ship to users; informational)

---

## Rules

### Bundle lookups: never call `Bundle.module` directly

**Rule**: production code must not reference `Bundle.module`. Use
`appBundledResource(named:ext:)` in `SharedComponents.swift`.

**Why**: SPM's auto-generated `Bundle.module` accessor for executable
targets bakes the build-time path into the binary. The accessor checks
`Bundle.main.bundleURL/<Target>_<Module>.bundle` (wrong location — bundles
live in `Contents/Resources/`) and then a hard-coded path that's invalid if
the project dir was renamed or the `.app` is run from `/Applications`.
Hitting `Bundle.module` at runtime when neither path resolves crashes with
a `fatalError`.

**Enforcement**: `scripts/check.sh` greps for `Bundle.module` outside of
`SharedComponents.swift`. Fails CI and pre-commit. See finding in
`.productionize-me/AUDIT.md § 1`.

### No network code

**Rule**: production code must not import or call `URLSession`,
`URLRequest`, `URLDownload`, or any HTTP primitive.

**Why**: Tokade promises in the README and SECURITY.md that nothing leaves
the user's machine. Adding any network code, even commented out, breaks
that promise and degrades the supply-chain argument (the user can verify
the claim with one grep today).

**Enforcement**: `scripts/check.sh` greps for `URLSession|URLRequest|
URLDownload|NSURLSession|NSURLRequest` in `Sources/`. Fails CI.

### Chart stability hacks must stay

**Rule**: `Sources/Tokade/StatsView.swift` must contain literal calls to
`chartForegroundStyleScale`, `chartYScale(domain:`, and `sortedModels(`.
Don't remove these as "cleanup."

**Why**: SwiftUI Charts auto-derives color domains and stack-segment order
from data iteration order. Without explicit `chartYScale(domain:)`, pinned
`chartForegroundStyleScale(domain:range:)`, and pre-sorted rows, stacked
bars in the Models tab reshuffle colors and segment order on hover. This
was diagnosed and fixed; the fix looks decorative and is easy to delete.

**Enforcement**: `scripts/check.sh` greps for each of the three markers.
Fails CI if any are missing.

### Critical-math test coverage

**Rule**: every `func` in `Sources/Tokade/Models.swift` that powers a
chart must have at least one corresponding test in `Tests/TokadeTests/`
named `func test...<FunctionName>...`.

**Why**: silent arithmetic bugs in window aggregation, group-by, projection,
or cap inference produce plausible-but-wrong numbers in every chart — the
worst kind of failure because nobody can eyeball-spot it.

**Enforcement**: `scripts/check.sh` greps for `func <fn>` in `Models.swift`
and verifies `Tests/` contains `func test...<fn>`. Fails CI if any
chart-driving function lacks a test.

**Functions currently enforced**: `groupedByModel`, `groupedByProject`,
`toolCallCounts`, `groupedBySlashCommand`, `stackedByProjectAndModel`.
Add any new chart-driving function to the list in `scripts/check.sh`.

### Data archive promises

**Rule**: `EventArchive` and `SnapshotArchive` must keep the
append-only-with-high-water-mark contract. Don't truncate, rewrite, or
out-of-order-write the JSONL files. Don't change the field names in
`ArchivedEvent` or `UsageSnapshot` without an ADR.

**Why**: `~/.tokade/history/events.jsonl` is a durable user contract. A
user who shares Tokade between machines or whose Claude Code JSONL gets
pruned still has their archive as the source of truth.

**Enforcement**: manual review. Document any schema change in
`docs/adr/`. There's no automated check; that's an honest gap.

### Archive file permissions

**Rule**: every file `EventArchive` or `SnapshotArchive` writes must have
mode `0600` (owner-only read/write).

**Why**: archive files contain `cwd` paths from your sessions. The
README's Privacy section promises 0600. A multi-user macOS could otherwise
let another local account read your archive.

**Enforcement**:
- Source-side: `scripts/check.sh` greps `0o600` in
  `Sources/Tokade/EventArchive.swift` and `SnapshotArchive.swift`.
- Behavior-side: `Tests/TokadeTests/EventArchivePermissionsTests.swift`
  writes a real file and asserts the mode.

### No LLM-attribution noise

**Rule**: don't commit comments or docs that contain strings like
"generated by Claude," "Claude wrote this," "generated by an AI," etc.
Co-authored-by trailers in git commits are fine and encouraged.

**Why**: comments rot. A "generated by Claude" comment from six months ago
gives a future reader no information except a vague signal not to trust
the surrounding code.

**Enforcement**: `scripts/check.sh` greps `Sources/` and `README.md` for
the pattern. Fails CI on match.

---

## Audit threading

Every P0 finding in `.productionize-me/AUDIT.md` should map to a rule
here. If you change a rule, update the corresponding section of
`AUDIT.md`. If you add an audit finding that requires regression
protection, add the corresponding rule + enforcement here.

Current threading:

| AUDIT finding | CLAUDE.md rule | Enforcement |
|---|---|---|
| Bundle.module workaround (§1) | "Never call Bundle.module" | `scripts/check.sh` grep |
| No network promise (§3) | "No network code" | `scripts/check.sh` grep |
| Chart stability hacks (§1) | "Chart stability hacks must stay" | `scripts/check.sh` grep × 3 |
| Zero tests on critical math (§2) | "Critical-math test coverage" | `scripts/check.sh` test-name grep |
| Archive append-only contract (cross-cut) | "Data archive promises" | Manual review (honest gap) |

---

## Things that are not rules

These are recommendations, not enforced:

- Use `os_log` for new error paths instead of `try?`-and-swallow. Not yet
  enforced because the codebase has legacy `try?` calls that will be
  migrated over time.
- Prefer extracting a per-card file (like `PastWindowsBudgetCard.swift`)
  over growing `StatsView.swift`. Soft style.
- Run `swift test` before opening a PR. The CI will catch you, but local
  is faster.
- Keep `README.md` and `docs/` updated when behavior changes. PR template
  asks for this.
