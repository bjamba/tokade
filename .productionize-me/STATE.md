# productionize-me state

- **Tier**: 2 — small public OSS
- **Path**: B (in-place modernization)
- **Phase**: M0 + M1 + M2 complete. v0.2.0 and v0.3.0 both shipped.
- **Last action**:
  - PR #19 (M2 swiftformat) merged
  - PR #20 (M2 wave B: incremental parsing + a11y) merged
  - Tag `v0.3.0` pushed; release workflow built and published Tokade-v0.3.0-macos.zip
  - v0.3.0 milestone closed (8/8 issues)
- **Releases**:
  - v0.1.0: initial public release
  - v0.2.0: productionize-me M0+M1 (tests, CI, guardrails, ADRs, release pipeline, privacy/reliability)
  - v0.3.0: M2 (swiftformat, incremental parsing, shape glyphs, VoiceOver, GitHub surface)
- **Tests**: 40 XCTest cases, green on CI
- **No open milestones**.
- **Open issues**: zero from the audit. The remaining backlog is the "Coming soon" items in the README:
  - Arcade tab (next major direction — needs design phase)
  - Cost estimation (small, future)
  - Multi-account support (medium, future)
- **CLAUDE.md and `.productionize-me/` artifacts** are durable; future
  contributors land in a repo with full enforcement + audit trail.
