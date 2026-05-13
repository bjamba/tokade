<!-- Thanks for sending a PR. A few things to check before merge: -->

## What this changes
<!-- One paragraph. Link the issue if there is one. -->

## Why
<!-- The problem this solves, not the implementation. -->

## How I tested it
<!-- `swift test` + manual smoke test (open the app, look at the relevant tab). -->

## Checklist

- [ ] `swift build -c release` passes locally
- [ ] `swift test` passes locally
- [ ] `./scripts/check.sh` passes (guardrail grep checks)
- [ ] Added or updated tests for any new logic in `Models.swift`, `ClaudeCodeReader.swift`, or `SharedComponents.swift`
- [ ] Updated `CHANGELOG.md` under `## [Unreleased]` if user-visible
- [ ] No new direct calls to `Bundle.module` (use `appBundledResource` in `SharedComponents.swift`)
- [ ] No new `URLSession` / `URLRequest` / network code — Tokade is offline by design
- [ ] If a chart was touched: explicit `chartYScale(domain:)`, `chartForegroundStyleScale(domain:range:)`, and pre-sorted rows are still in place (see `CLAUDE.md`)

## Screenshots (if UI changed)
<!-- Drag and drop here. -->
