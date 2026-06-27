# Repository Guidelines

## Project Overview

- RepoPeek is a macOS menubar app (SwiftUI + AppKit NSMenu) for GitLab repo status, activity, and local project state.
- Build system: SwiftPM wrapped by `pnpm` scripts; app bundling/signing via `Scripts/*.sh`.
- Testing: Swift Testing (`swift test`) via `pnpm test`/`pnpm check`.
- Product direction: GitLab-only, PAT-only. Do not add provider compatibility branches or browser sign-in paths.

## Project Structure & Module Organization

- `Sources/RepoPeek/` holds app code: `App` (entry), `StatusBar` (menus/windows), `Auth` (PAT + TokenStore), `API` clients through RepoPeekCore, `Models`, `Views`, `Settings`, and `Support`.
- `Sources/RepoPeekCore/` holds GitLab REST clients, models, cache/archive readers, settings, and local Git services.
- `Tests/RepoPeekTests/` contains Swift Testing suites; keep new coverage close to the code under test.
- `Resources/` includes app assets/entitlements; `Scripts/` wraps build/lint/run/package/release steps; `docs/` has specs and operational notes.

## Build, Test, And Development Commands

- Use pnpm scripts from repo root (pnpm v10+, Swift 6.2, Xcode 26): `pnpm install` once for script deps.
- `pnpm check` -> swiftformat + swiftlint + swift test (use before change review).
- `pnpm check:coverage` -> coverage run (isolated build dir under `.build/coverage`).
- `pnpm test` -> `Scripts/test.sh` (SwiftPM `--cache-path ~/Library/Caches/RepoPeek/swiftpm`); add `--filter` for focused runs.
- `pnpm build` -> `swift build` (debug).
- `pnpm start` / `pnpm restart` -> `Scripts/compile_and_run.sh` rebuilds + packages/codesigns + relaunches the menubar app (no tests); quit via `pnpm stop` or the menu.
- Updating the local app means overwrite-installing this checkout's packaged bundle to `/Applications/RepoPeek.app`; do not treat launching only the `.build` bundle as a local app update.
- Guardrail: always launch via `pnpm start`/`pnpm restart` from this checkout. If behavior/UI does not match code, verify the running binary path: `pgrep -af "RepoPeek.app/Contents/MacOS/RepoPeek"`.

## Coding Style & Naming Conventions

- Enforce formatting with `swiftformat` (4-space indent, inline commas, wrap args/collections before first element, no semicolons) and lint with `swiftlint`.
- Swift 6.2, prefer strict typing and small files (<500 LOC as a guardrail); keep MenuBarExtra/UI code in SwiftUI with extracted helpers.
- SwiftUI: use modern `@Observable` (not `ObservableObject`).
- Naming: types UpperCamelCase; methods/properties lowerCamelCase; tests mirror subject names.
- User-facing platform terms should say GitLab, merge request/MR, pipeline, and PAT.

## Testing Guidelines

- Framework: Swift Testing via `swift test`. Name suites `<Thing>Tests` and functions `test_<behavior>()`.
- Cover new logic with deterministic fixtures/mocks for GitLab data.
- Run `pnpm check` before pushing; prefer adding tests alongside bug fixes.

## Commit And Review Guidelines

- Commit messages follow the existing short, imperative style; optional scoped prefixes (`menu:`, `settings:`, `tests:`, `fix:`). Keep them concise; present tense; no trailing period.
- Change requests: include a brief summary, linked issue/ticket if any, screenshots or clips for UI changes (menubar window, settings), and note the exact commands run (`pnpm check`/`pnpm test`).

## Security & Configuration Tips

- Keep tokens out of the repo; PATs live in Keychain for release builds.
- Self-managed GitLab instances must use HTTPS.
- Do not log tokens or traffic stats responses; prefer redacted diagnostics.
- Avoid editing `Info.plist` flags that enforce LSUIElement/single-instance unless coordinated.

## Agent-Specific Notes

- Always use the provided scripts instead of raw `swift build/test` when possible.
- If you change shared scripts, keep the package scripts and release docs in sync. Clean up any tmux sessions you start for long-running tasks.
- Prefer models directly in views; view models only when they add real derived value.
- When modifying menus, update the Display Settings menu builder too.
- Ignore files you do not recognize (just list them); multiple agents often work here.
