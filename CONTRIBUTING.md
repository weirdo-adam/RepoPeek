# Contributing to RepoPeek

Thanks for your interest in contributing! This document outlines how to set up your environment, make changes, and submit them.

## Getting Started

### Prerequisites

- macOS
- Xcode 26 / Swift 6.2
- pnpm 10+

### Setup

```bash
git clone https://github.com/weirdo-adam/RepoPeek.git
cd RepoPeek
pnpm install
pnpm build
pnpm start
```

## Development Workflow

### Before Making Changes

1. Check existing [issues](https://github.com/weirdo-adam/RepoPeek/issues) to see if your idea is already being discussed.
2. For significant changes, open an issue first to discuss the approach.

### Making Changes

1. Create a branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following the project's coding style:
   - 4-space indentation, Swift 6.2
   - `@Observable` for SwiftUI state (not `ObservableObject`)
   - Types UpperCamelCase, methods/properties lowerCamelCase
   - Files under 500 LOC

3. Run the full check before committing:
   ```bash
   pnpm check     # swiftformat + swiftlint + swift test
   ```

4. For UI changes, test with:
   ```bash
   pnpm start     # build, package, sign, and launch from this checkout
   ```

### Commit Messages

Follow the existing style: short, imperative, present tense. Optional scoped prefixes are welcome:

- `menu:` — menu bar and status bar changes
- `settings:` — preferences and settings
- `tests:` — test additions or fixes
- `fix:` — bug fixes
- `docs:` — documentation updates

Example: `menu: add pipeline status indicator to repo submenu`

### Pull Requests

1. Push your branch and open a PR against `main`.
2. Fill in the PR template — include a summary, motivation, and checklist.
3. Attach screenshots or screen recordings for UI changes.
4. Ensure CI passes (`pnpm check` is verified in GitHub Actions).

## Project Structure

- `Sources/RepoPeek/` — macOS app, menu, settings, auth coordination, local project UI
- `Sources/RepoPeekCore/` — GitLab client, cache/archive readers, models, settings, local Git services
- `Tests/RepoPeekTests/` — Swift Testing coverage
- `docs/` — design notes and operational docs
- `Scripts/` — build, package, signing, testing, and launch wrappers

## Testing

- Framework: Swift Testing (`swift test`)
- Name suites `<Thing>Tests` and functions `test_<behavior>()`
- Cover new logic with deterministic fixtures/mocks for GitLab data
- Run `pnpm test` for the full suite or `swift test --filter <TestSuite>` for focused runs

## Documentation

- Inline comments for non-obvious logic
- Update relevant docs in `docs/` when changing behavior
- Update `CHANGELOG.md` with user-facing changes

## Questions?

Open an issue or start a discussion — we're happy to help.
