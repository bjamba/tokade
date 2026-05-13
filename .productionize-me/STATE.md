# productionize-me state

- **Tier**: 2 — small public OSS
- **Path**: B (in-place modernization)
- **Phase**: 4 in progress. **M0 + M1 merged to main and v0.2.0 tagged.**
- **Last action**:
  - PR #11 (M0) merged as `9c95f71`
  - PR #12 (M1) merged as `f2fdf8e`
  - Tag `v0.2.0` pushed; release workflow triggered (publishes `Tokade-v0.2.0-macos.zip` to GitHub Releases)
- **GitHub side-effects**:
  - 16 curated labels
  - Milestone `v0.2.0` (#1) with all 10 audit-derived issues closed by PR #12
  - Release `v0.2.0` published (or publishing — depending on when you read this) with notes pulled from CHANGELOG
- **Tests**: 32 XCTest cases, all passing on CI
- **Next (M2)**: out-of-scope-for-launch items still tracked as open issues —
  - #4 incremental JSONL parsing (perf)
  - #5 colorblind-safe pattern overlays (a11y)
  - #6 chart VoiceOver labels (a11y)
  - plus other M2 candidates: SwiftLint, swiftformat lint, Discussions, public Projects v2 roadmap, CODEOWNERS, Arcade tab brainstorm (Phase 5 / new milestone)
