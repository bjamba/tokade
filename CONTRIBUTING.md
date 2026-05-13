# Contributing to Tokade

Thanks for the interest. Tokade is a small, single-maintainer OSS project.
Issues and PRs are welcome — please read this first so your work merges
smoothly.

## Filing issues

- Use the **Bug report** template for things that are broken
- Use the **Feature request** template for new capabilities
- For "should we…?" or "how do I…?" questions, open a
  [Discussion](https://github.com/bjamba/tokade/discussions) instead

## Local setup

```
# macOS 14+ and Xcode Command Line Tools required
xcode-select --install

git clone https://github.com/bjamba/tokade
cd tokade

# Build the .app into the project dir
./build.sh

# Run from project dir
open Tokade.app

# Or install to /Applications
./install.sh
```

The statusline shim is optional but recommended — it's how Tokade gets
fresh server-truth `%` data:

```
./install-statusline.sh
```

This patches `~/.claude/settings.json` so Claude Code invokes
`statusline-shim.sh` on every response.

## Tests

```
swift test
```

30+ tests live in `Tests/TokadeTests/`. They cover the math that drives every
chart: parser, sequence extensions, model palette logic, 5h-window
projection. Run them before opening a PR.

## Guardrails

Before committing, run:

```
./scripts/check.sh
```

This enforces the rules in [`CLAUDE.md`](CLAUDE.md):

- No direct `Bundle.module` calls outside `SharedComponents.swift`
- No network primitives in `Sources/` (`URLSession`, `URLRequest`, etc.)
- Chart-stability modifiers must stay in `StatsView.swift`
- Every chart-driving function in `Models.swift` must have a test
- No LLM-attribution noise in source/docs

CI runs the same script on every PR.

To run guardrails on every local commit:

```
brew install pre-commit
pre-commit install
```

## Pull requests

1. Branch from `main`
2. Make the change. Add or update tests when you touch math in `Models.swift`,
   `ClaudeCodeReader.swift`, or `SharedComponents.swift`
3. Run `swift test` and `./scripts/check.sh`
4. Update the `## [Unreleased]` section of [`CHANGELOG.md`](CHANGELOG.md) if
   the change is user-visible
5. Open a PR using the template. Fill in the checklist.

The PR template asks you to confirm: build passes, tests pass, guardrails
pass, no new `Bundle.module` calls, no new network code, chart-stability
modifiers intact. CI verifies the first three for you.

## Code style

There's no `swiftformat` config yet (see issue tracker for the M2 item).
Match surrounding style:

- 4-space indent
- Trailing commas in multi-line collection literals
- Open braces on the same line
- Documentation comments only where the *why* is non-obvious

## Architecture

See [`docs/02-design/ARCHITECTURE.md`](docs/02-design/ARCHITECTURE.md) for
the data flow + file map. See [`docs/adr/`](docs/adr/) for non-obvious
design decisions.

## Reporting security issues

See [`SECURITY.md`](SECURITY.md). Don't open public issues for
vulnerabilities.

## License

By contributing, you agree your contributions are licensed under the MIT
License, the same as the rest of the project.
