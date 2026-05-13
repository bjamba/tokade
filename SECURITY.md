# Security policy

## Reporting a vulnerability

Please **do not** open a public issue for security vulnerabilities. Use
GitHub's private vulnerability reporting:

1. Go to https://github.com/bjamba/tokade/security
2. Click "Report a vulnerability"
3. Fill in the form

I'll respond within a few days. There's no bug-bounty program; this is a
volunteer-maintained project.

## Threat model in brief

Tokade is a local-only macOS desktop app:

- **No network**. The code contains no `URLSession`, `URLRequest`, or HTTP
  calls. A grep guard in CI (`scripts/check.sh`) enforces this.
- **Reads** Claude Code's session JSONL (`~/.claude/projects/`) and a
  statusline JSON written by `statusline-shim.sh` (`~/.tokade/last-status.json`).
- **Writes** to `~/.tokade/history/` (append-only archives).
- **Does not** read prompt content, response content, or auth material from
  Claude Code.

## Out of scope

These don't qualify as security vulnerabilities for Tokade:

- Issues in Claude Code itself or the macOS sandbox
- Issues that require local root access on the user's machine
- Crashes that don't have a security implication (file a regular bug)
- Theoretical issues with ad-hoc codesigning (Tokade ships without Apple
  notarization; users opt into the Gatekeeper warning by building from source
  or running a downloaded `.app`)
