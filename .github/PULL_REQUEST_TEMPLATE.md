<!--
Write this PR so a reasonably competent engineer who has NEVER seen this
codebase can understand it and navigate to the relevant code from the
description alone. Every problem statement should name the user-visible
symptom AND point at the file/function to open. Delete the guidance comments
before submitting.
-->

## TL;DR
<!-- 1–2 sentences: what this PR does and its kind (bugfix / feature / refactor / chore). -->

## Orientation
<!-- For readers new to this area: name the subsystem(s) this touches and where
they live (directory/file paths), in one or two lines each. Skip only for a
truly trivial one-file change. -->

## What changed and why
<!-- One block per logical change. Use this shape so the description doubles as
a map of the diff:

### <short title> (#issue)
**Problem.** Plain language, no internal jargon — what's wrong and how it shows up.
**Why it matters.** The user-visible impact / which promise or contract it touches.
**Fix & where to look.** The specific files + functions to open, and tests covering it.
-->

## How I tested it
<!-- `swift test` results + any manual smoke test (open the app, look at the
relevant tab). Paste the verification numbers. -->

## Reviewer notes (optional)
<!-- Suggested reading order, gotchas, anything that needs a second opinion. -->

## Checklist

- [ ] `swift build -c release` passes locally
- [ ] `swift test` passes locally
- [ ] `./scripts/check.sh` passes (guardrail grep checks)
- [ ] Added or updated tests for any new logic in `Models.swift`, `ClaudeCodeReader.swift`, or `SharedComponents.swift`
- [ ] Updated `CHANGELOG.md` under `## [Unreleased]` if user-visible
- [ ] No new direct calls to `Bundle.module` (use `appBundledResource` in `SharedComponents.swift`)
- [ ] No new `URLSession` / `URLRequest` / network code — Tokade is offline by design
- [ ] If a chart was touched: explicit `chartYScale(domain:)`, `chartForegroundStyleScale(domain:range:)`, and pre-sorted rows are still in place (see `CLAUDE.md`)
- [ ] Linked to its issue(s) and milestone; added to the Tokade Roadmap project

## Screenshots (if UI changed)
<!-- Drag and drop here. -->
