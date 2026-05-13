# ADR 0004 — Ship ad-hoc codesigned only; no notarization

- **Status**: Accepted
- **Date**: 2026-05-13
- **Deciders**: @bjamba

## Context

`build.sh` codesigns `Tokade.app` with the `-` identity (ad-hoc):

```bash
codesign --force --sign - "$APP_DIR/Contents/MacOS/Tokade"
codesign --force --sign - "$APP_DIR"
```

Ad-hoc signing is the simplest level — the binary's pages are hashed
and a self-attached signature is produced, but there's no Apple
Developer certificate involved.

The next two rungs up are:

- **Developer ID codesigning** — requires a paid Apple Developer
  account ($99/yr), uses an Apple-issued certificate, lets Gatekeeper
  identify the developer.
- **Notarization** — additionally uploads the binary to Apple, who
  scans it and issues a "stapled" notarization ticket. Required for
  Gatekeeper to launch a downloaded app without a warning on macOS 10.15+.

Tokade is a free, single-maintainer OSS project. Paying $99/yr and
managing a Developer ID isn't proportionate.

## Decision

Ship ad-hoc signed only. Document the consequence — Gatekeeper will
warn on first launch — in the README and in the Release page text
(once the release workflow lands per issue #9).

Users who download `Tokade.app` from a Release get the standard
"unidentified developer" message. The workaround is documented:
right-click → Open → confirm. This is the same flow as any of the
many other free macOS OSS apps.

Users who build from source via `./install.sh` skip the warning
entirely because they're running a binary they just compiled.

## Consequences

**Positive**

- Zero ongoing cost
- No Apple Developer-program lock-in
- Release pipeline doesn't need to manage credentials or notarization
  upload time

**Negative**

- First-launch friction for downloaders. Some non-technical users will
  bounce. Documented; acceptable for the tier 2 OSS audience.
- If Apple tightens Gatekeeper further (e.g., disallows right-click →
  Open by default in some future macOS), we'd have to revisit.

## Revisit when

Revisit this decision if any of:

- Tokade starts having non-technical user demand visible enough that
  the right-click-Open flow becomes a real friction
- A sponsor offers to cover the $99/yr Developer Program fee
- Tokade ever needs to ship via the Mac App Store

Until then, ad-hoc stays.

## Alternatives considered

- **Full Developer ID + notarization** — $99/yr + ~5 min per release
  for upload/wait/staple. Rejected on cost/proportion grounds.
- **No signing at all** — even ad-hoc is preferable; macOS treats
  unsigned binaries more harshly than ad-hoc signed.
- **Ship source-only** — feasible (build is one command) but a "no
  binaries" stance is contributor-friendly only, not user-friendly.
  Rejected.
