# Tokade — Production Audit (Tier 2: small public OSS)

Scoring legend: 🔴 missing · 🟡 partial · 🟢 production-ready for chosen tier.
Tier-2 target is "a stranger can clone, build, contribute, and trust the math."
Not "Apple-shipping-quality production." Items marked N/A do not apply at this
tier and are not gaps.

| # | Dimension | Current | Target | Headline |
|---|-----------|---------|--------|----------|
| 1 | Code quality & structure | 🟢 | 🟢 | clean, small, well-separated |
| 2 | Testing & verification | 🔴 | 🟢 | **biggest gap** — zero tests on math that drives every chart |
| 3 | Security & secrets | 🟡 | 🟢 | no code issues; minor file-permission + signing items |
| 4 | Dependencies & supply chain | 🟢 | 🟢 | zero runtime deps; SPM toolchain pinned |
| 5 | Observability | 🟡 | 🟡 | partial; errors silently swallowed but no remote telemetry expected |
| 6 | CI/CD & deployment | 🔴 | 🟢 | **second biggest gap** — no CI, no release process |
| 7 | Documentation | 🟢 | 🟢 | recently expanded; CONTRIBUTING + ADRs would polish |
| 8 | Configuration & environments | 🟢 | 🟢 | single-user app, no envs to manage |
| 9 | Data handling & privacy | 🟡 | 🟢 | local-only is great; missing clear-archive + perms |
| 10 | Performance & scalability | 🟡 | 🟡 | full re-parse every 30s; OK now, will hurt long-term users |
| 11 | Reliability & error handling | 🟡 | 🟢 | `try?` everywhere; need stderr logging for diagnostics |
| 12 | Operational readiness | N/A | N/A | desktop app — user's machine is the ops env |
| 13 | Accessibility | 🟡 | 🟡 | colorblind-unsafe palette; pattern + label additions wanted |
| 14 | Licensing & compliance | 🟢 | 🟢 | MIT, attributed, README links |

---

## 1. Code quality & structure — 🟢 Production

**What's good**
- 15 source files, ~2,150 LOC. Right-sized for the scope.
- `UsageStore` is the only shared state. Views are presentations. Easy to reason about.
- Each reader has one responsibility (`ClaudeCodeReader`, `StatusFileReader`,
  `EventArchive`, `SnapshotArchive`).
- Hover/sort/animation hacks are explicitly commented as defensive (e.g.
  `StatsView.swift:200-230` pre-sorting rows + pinning color domain).

**Gaps**
- No formatter configured. A `swiftformat` config and pre-commit hook would
  lock in consistent style for outside contributors.
- `StatsView.swift` is 460+ lines. Not dangerous but on the long side; could
  split per-card files like `PastWindowsBudgetCard.swift` already does. Minor.

**Specifics**
- `Sources/Tokade/SharedComponents.swift:appBundledResource` — the
  Bundle.module workaround. Worth an inline comment block describing *why*
  someone can't just use `Bundle.module` directly.

---

## 2. Testing & verification — 🔴 Missing (highest-risk gap)

**What's missing**
- Zero unit tests, zero integration tests, no `Tests/` directory in
  `Package.swift`, no XCTest target.
- The failure mode this enables is exactly the most expensive: silent math
  bugs producing plausible-but-wrong numbers in every chart.

**Critical paths that need tests at Tier 2**
- **`ClaudeCodeReader.parseFile`** — given JSONL fixtures, returns the
  correct events. Edge cases: malformed lines (must skip, not crash), missing
  `usage` block, `<synthetic>` model, missing `cwd`, slash-command lines
  (`type: "last-prompt"`).
- **`UsageEvent.grandTotal`** and the `Sequence` extensions in `Models.swift`:
  `within(_:)`, `groupedByModel`, `groupedByProject`, `toolCallCounts`,
  `groupedBySlashCommand`, `stackedByProjectAndModel`,
  `stackedBySlashCommandAndModel`, `stackedByToolAndModel`.
- **`effectiveFiveHourResetsAt`** / **`isFiveHourDataStale`** (SharedComponents) —
  edge cases: server time in past by >1 cycle, server time in future, missing
  rate limits.
- **`PastWindowsBudgetCard` cap inference** — the "max across all
  snapshot-truthed windows" logic. Given known snapshots, returns expected
  cap.
- **`YTDCumulativeCard` wedge math** — given known YTD points + last-30-day
  rate, returns expected (low, high) at year-end.
- **`SnapshotArchive` dedup** — appending the same snapshot twice doesn't
  duplicate.
- **`EventArchive` high-water mark** — only events newer than `events.last`
  get archived.

**Tier-2 bar**: each of the above gets at least one happy-path test plus one
edge case. CI must run them on every PR. Coverage threshold not required for
Tier 2; "all critical-math files have at least one test" is the bar.

**Effort estimate**: 1–2 weekend days to bootstrap. Most of these are pure
functions over fixture JSONL strings.

---

## 3. Security & secrets — 🟡 Partial

**What's good**
- No credentials in code, no API keys, no auth material.
- Zero network calls. `URLSession`/`URLRequest` not imported.
- Only reads from `$HOME` paths owned by the user.
- `install-statusline.sh` uses a python heredoc to mutate JSON safely;
  variables quoted in all shell scripts.
- Statusline shim writes atomically (`tmp.$$` + `mv -f`).
- README's "no network" claim is verifiable from one grep.

**Gaps for Tier 2**
- **Ad-hoc codesigning**. `Tokade.app` is signed with the `-` identity. Anyone
  who downloads a pre-built artifact will hit a Gatekeeper "unidentified
  developer" wall and have to right-click → Open. For a public OSS project
  this is fine to leave (it's the user's choice to opt into building from
  source), but the README should call it out.
- **`~/.tokade/` file permissions**. Files are created with default umask
  (typically 644). For a local-only data store this is fine, but tightening to
  0600 on the events/snapshot archives matches the "your data, your machine"
  promise.
- **Statusline shim is invoked by Claude Code on every response**, with full
  user privileges. It's a 30-line shell script the user audits, but the
  *concept* of "an installer adds an external command into a CC config" is
  worth documenting prominently in the README so users know what they're
  consenting to.

**Specifics**
- `EventArchive.swift:60-72` — file creation; consider `chmod 0600` after creation.
- `SnapshotArchive.swift:53-62` — same.

---

## 4. Dependencies & supply chain — 🟢 Production

**What's good**
- `Package.swift` has empty `dependencies: []`. Zero runtime third-party code.
- Swift toolchain version pinned (`swift-tools-version: 5.9`).
- macOS platform pinned (`platforms: [.macOS(.v14)]`).
- `librsvg` is a build-time-only tool, only needed for icon regeneration,
  and the pre-built `.icns` is committed.

**Gaps**
- README should state the minimum Xcode / CLT version required to build
  (currently implicit via Swift 5.9). Not a security issue, a contributor
  friction one.

---

## 5. Observability — 🟡 Partial (tier-acceptable)

**What's good**
- macOS crash reports land in `~/Library/Logs/DiagnosticReports/` automatically.
- App is single-process, simple enough that the developer can attach a
  debugger or `Console.app` to diagnose.

**Gaps**
- Every file-read and decode uses `try?`, swallowing the error. If a user's
  `~/.claude/projects/*.jsonl` files are corrupted, Tokade silently shows
  fewer events with no surfacing of "I skipped 47 malformed lines."
- No `os.Logger` or `os_log` calls anywhere. Adding them at the I/O boundaries
  (parser, archive, statusline reader) gives users + maintainers a way to
  trace issues via `log show --predicate 'process == "Tokade"'`.

**Tier-2 bar**: log warnings/errors at the boundary, not in the hot path.
No remote telemetry. No sentry.

---

## 6. CI/CD & deployment — 🔴 Missing

**What's missing**
- No `.github/workflows/` directory.
- No PR build verification. A contributor opening a PR has no automated
  signal that their change compiles, let alone passes tests.
- No release process. Zero tags. No `.app` artifact attached to any release.
- No SwiftLint / format check on PRs.

**Tier-2 bar**
- **CI**: a GitHub Actions workflow on `macos-latest` that runs
  `swift build -c release` and `swift test` on every PR and on push to main.
- **Release**: a manually-triggered workflow that takes a tag, builds the
  `.app`, zips it, and attaches to a GitHub Release. Notarization is **not**
  required at this tier (Gatekeeper warning is OK; users opt in).
- **Lint**: `swiftformat --lint` step (no auto-fix; just fail PRs that
  reformat the codebase). Skip SwiftLint unless someone wants it — it adds
  rule-bikeshedding without much value at this size.

**Effort estimate**: 2–3 hours to wire up the workflow + release script.

---

## 7. Documentation — 🟢 Production

**What's good**
- README covers install, build, usage, data location, how it works, why no
  API integration, limitations/assumptions, and roadmap. Recently expanded.
- LICENSE present and linked.
- Footnotes inside charts explain biases (e.g., approximate-bar caveats).

**Gaps**
- No `CONTRIBUTING.md`. Tier-2 OSS norm: tell strangers how to file issues,
  what PRs you'll accept, code style, branch workflow.
- No ADRs documenting the *non-obvious* design choices: server-`%` as ground
  truth, raw tokens as a separate dimension, `Bundle.module` workaround,
  bypassing `--deep` codesign, fixed-bar-thickness rationale, model palette
  philosophy.
- No `CHANGELOG.md`. At 2 commits this is fine; after the first tagged
  release it becomes useful.
- No code-of-conduct file. Optional at this size.

---

## 8. Configuration & environments — 🟢 Production

**What's good**
- No environment variables to manage.
- One deployment environment (the user's machine).
- Paths are `$HOME`-relative.
- `@AppStorage` used for the few user preferences (range pickers).

**Gaps**
- None at Tier 2.

---

## 9. Data handling & privacy — 🟡 Partial

**What's good**
- Strictly local. No network. No telemetry.
- README's privacy claim is concrete and verifiable.
- Data archive (`events.jsonl`) intentionally excludes prompt/response bodies.

**Gaps**
- **No "clear my archive" affordance.** Users can `rm -rf ~/.tokade/` from
  the terminal, but a Tokade-side action ("Erase history…" with confirmation)
  is expected at Tier 2.
- **No retention policy.** `events.jsonl` grows forever. At a few hundred
  bytes per event, this is a slow problem — but a heavy user past a year
  will see noticeable startup latency.
- **`cwd` in archived events is mild PII** (project directory names). The
  README should call this out in the privacy section so users know what's
  in their archive before they share it.
- **Tightening file permissions** (covered under §3) also belongs here.

---

## 10. Performance & scalability — 🟡 Partial

**What's good**
- Single-process, single-threaded poll loop.
- Snapshot archive write is incremental (high-water mark).
- Event archive write is incremental (`lastArchived` cutoff).
- 30-second cadence — not a hot path.

**Gaps**
- **Full re-parse every poll.** `ClaudeCodeReader.readAllEvents()` enumerates
  every `.jsonl` under `~/.claude/projects/` and re-reads every line on every
  30-second tick. For a heavy Claude Code user with months of sessions this
  is hundreds of files / hundreds of MB. The footprint hit earlier (~360MB
  RSS) traces here.
- **Fix**: track file mtimes + sizes; only re-parse files whose mtime changed
  since the last poll. Or, use the persisted `events.jsonl` archive as the
  primary source on startup and only consult fresh `~/.claude/projects/`
  files for incremental updates.
- **Charts re-render on every `lastUpdated` change.** This is correct
  (observables drive UI), but with many charts in view this hits 30-fps
  budget once data sets get larger. Profile before optimizing — probably
  fine today.

---

## 11. Reliability & error handling — 🟡 Partial

**What's good**
- File-not-found is handled (returns empty arrays, doesn't crash).
- Malformed JSONL lines are skipped (`guard let ... else { continue }`).
- Statusline shim degrades when `jq` is missing.
- 5h-window auto-reset projection handles stale server data.

**Gaps**
- **`try?` everywhere** silently swallows errors at write paths too. If
  `~/.tokade/history/` is read-only (or full), Tokade silently fails to
  archive events. The UI shows no indication.
- **No graceful "Claude Code not installed" UI.** If `~/.claude/projects/`
  doesn't exist, the parser returns 0 events and every chart says "no data."
  Better: a banner explaining the dependency.
- **Polling task is never cancelled cleanly** on app termination. Mostly OK
  since the process exits, but a flushed write of the high-water mark on
  termination would prevent rare double-archiving on next launch.

---

## 12. Operational readiness — N/A at Tier 2 desktop app

Not applicable. There's no service to operate. macOS handles process
lifecycle. The user *is* the operator.

---

## 13. Accessibility — 🟡 Partial

**What's good**
- Menu bar uses an `isTemplate = true` NSImage — automatically inverts for
  dark mode and respects increased contrast.
- SwiftUI defaults give baseline VoiceOver support on text and buttons.
- Tooltips expose categorical info textually.

**Gaps**
- **Colorblind safety.** All three model tiers use blue-family hues. A
  deuteranopia / protanopia / tritanopia user will struggle to distinguish
  Haiku from Sonnet in stacked bars. The model name in the legend mitigates
  this, but adding a pattern overlay (stripes / dots / hatches) per tier
  would help. Tier 2 nice-to-have.
- **Chart accessibility.** Swift Charts has `accessibilityLabel` /
  `accessibilityValue` modifiers we don't use. A VoiceOver user can't navigate
  individual bars.
- **No high-contrast palette mode.** Probably overkill for Tier 2 desktop.

---

## 14. Licensing & compliance — 🟢 Production

- MIT LICENSE in repo root, attributed to bjamba, year 2026. ✅
- README links it. ✅
- Zero deps → no transitive license conflicts. ✅
- No GDPR/CCPA implications (no data leaves the device).

---

## Cross-cutting concerns the audit surfaced

1. **The `~/.tokade/` data directory is a first-class user contract** that
   isn't documented anywhere as a contract. If we ever change its schema,
   we break upgrades. Worth an ADR.
2. **The chart-rendering hacks** in `StatsView.swift` are the kind of code
   that future contributors "clean up" without realizing they encode bug
   workarounds. Comment + ADR.
3. **The Bundle.module workaround** — same story. Document the trap.

---

## Findings → CLAUDE.md hooks (preview for Plan phase)

Audit findings that should become enforced rules in `CLAUDE.md`:

- "Never call `Bundle.module` directly — use `appBundledResource` instead"
  (enforce via pre-commit grep)
- "All new functions in `Models.swift` and `ClaudeCodeReader.swift` must have
  a corresponding test before merge" (enforce via CI check counting test
  files)
- "Never remove `chartYScale(domain:)`, `chartForegroundStyleScale(...)`, or
  pre-sorted rows from Models tab charts without a written reason" (enforce
  via CI grep)
- "Data file permissions in `EventArchive` / `SnapshotArchive` must be 0600"
  (enforce via test)
- "Do not introduce network code" (enforce via CI grep for `URLSession`,
  `URLRequest`, `https?://` outside README)

These graduate into the Plan as P0/P1 items + their enforcement mechanisms.
