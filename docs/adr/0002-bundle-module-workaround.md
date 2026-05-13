# ADR 0002 — Bypass SPM's `Bundle.module` for executable resource lookups

- **Status**: Accepted
- **Date**: 2026-05-11
- **Deciders**: @bjamba

## Context

Tokade ships one resource — the menu bar template glyph PNG — bundled via
SPM's `resources: [.process("Resources")]` declaration. SwiftPM auto-
generates a `Bundle.module` accessor that looks up the resource bundle
at runtime.

For library targets, the accessor searches multiple sensible locations
including `Bundle.main.resourceURL`. For **executable targets**, the
generated accessor checks only two paths:

1. `Bundle.main.bundleURL/<Target>_<Module>.bundle` — the **top** of the
   `.app` bundle. Not where macOS expects resources to live.
2. A hard-coded build-time path like
   `/Users/bjamba/.../tokade/.build/arm64-apple-macosx/release/...` —
   baked into the binary at compile time.

The first path doesn't match Apple's `.app` structure (resources go in
`Contents/Resources/`). The second path is invalid the moment the project
directory is renamed or the `.app` is moved (or run from `/Applications/`).
When neither resolves, `Bundle.module`'s initializer calls `fatalError`
and the app crashes on launch with no menu bar icon to show for it.

We hit this concretely when renaming the project dir from `token-meter` to
`tokade`. The installed `.app` in `/Applications/` worked yesterday and
crashed today, because the hard-coded path no longer existed.

## Decision

Production code must not reference `Bundle.module`. Use
`appBundledResource(named:ext:)` in `SharedComponents.swift` instead,
which searches the locations our build script actually places the
resource:

1. `Bundle.main.resourceURL/Tokade_Tokade.bundle/<name>.<ext>` (where
   `build.sh` puts it — Apple-canonical)
2. `Bundle.main.bundleURL/Tokade_Tokade.bundle/<name>.<ext>` (SPM's
   default expectation; fallback)
3. `Bundle.main.resourceURL/<name>.<ext>` (loose resource, no inner
   bundle)

`Bundle.module`'s generated extension still exists in the build output;
we just don't call it, so its initializer never runs and the
`fatalError` is unreachable.

This rule is enforced by `scripts/check.sh`, which fails CI on any
`Bundle.module` reference outside `SharedComponents.swift`.

## Consequences

**Positive**

- The app launches reliably from any location (`/Applications/`, project
  dir, anywhere else)
- Renaming the project directory doesn't break installed binaries
- No mystery crash on first install for users who download from Releases

**Negative**

- Future contributors will naturally reach for `Bundle.module` because
  it's idiomatic SwiftPM. They'll be caught by CI but the surprise costs
  a few minutes.
- The workaround adds 25 lines to `SharedComponents.swift`
- If we ever migrate Tokade to an Xcode project (using a real asset
  catalog), this whole concern goes away — at the cost of dropping pure
  SPM tooling

## Alternatives considered

- **Move to an Xcode project with an asset catalog**. The "correct"
  long-term answer, but trades one form of complexity for another and
  drops the ability to build the app with just `swift build`.
- **Put the resource bundle at `Tokade.app/Tokade_Tokade.bundle`
  (top of the .app)** so SPM's first lookup path resolves. Wrong
  Apple layout; trips up codesigning with `--deep`.
- **Hand-edit the generated `resource_bundle_accessor.swift`**.
  Survives one build, gets overwritten on next clean. Rejected.
