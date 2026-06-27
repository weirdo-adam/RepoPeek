<div align="center">
  <img src="Resources/AppIcon.png" alt="RepoPeek app icon" width="80">
  <h1>RepoPeek</h1>
  <p><strong>GitLab repository status, local checkout state, and API limits in the macOS menu bar.</strong></p>
</div>

RepoPeek is a native macOS menu bar app for people who move between many GitLab projects and need fast answers without living in a browser. It keeps repository health, open issues and merge requests, pipelines, releases, recent activity, local checkout state, and API rate-limit status in a compact menu.

> **Forked from [steipete/RepoBar](https://github.com/steipete/RepoBar)** — original concept and architecture by [Peter Steinberger](https://github.com/steipete). RepoPeek is the GitLab-focused downstream fork, adapted for Personal Access Token authentication, GitLab REST APIs, self-managed GitLab hosts, and the menu conventions of GitLab-native workflow.

## Highlights

- See repository cards with issues, merge requests, pipeline state, stars, forks, activity, and optional heatmaps.
- Open rich GitLab submenus for issues, merge requests, releases, pipelines, tags, branches, contributors, commits, and activity.
- Match local checkouts to GitLab projects and surface branch, ahead/behind, dirty files, worktrees, and sync status.
- Browse and manage visible, pinned, hidden, local, and work-focused repository views.
- Track GitLab API rate limits, cached responses, archive fallback data, and typed reference matches.
- Authenticate with GitLab Personal Access Tokens only; self-managed HTTPS GitLab hosts are supported.

## Install

Release packaging is owned by this project. Current release assets are published through the RepoPeek GitHub release flow and Sparkle appcast.

For local development:

```bash
pnpm install
pnpm build
pnpm start
```

## What It Shows

RepoPeek's main menu is a repository dashboard:

- Repository cards with issue count, merge request count, stars, forks, latest activity, and optional heatmaps.
- A contribution header for the signed-in GitLab user.
- Filters for all repositories, pinned repositories, local repositories, and work-focused views.
- A profile submenu with recent GitLab activity.
- A GitLab API status submenu showing current blockers, REST state, and persisted REST resource headers.
- Quick access to Preferences, About, and Quit.

Each repository has a rich submenu:

- Open the repository in GitLab.
- Open or checkout the local repo when configured.
- View local branch, ahead/behind, dirty files, and worktrees.
- Browse recent issues, merge requests, releases, pipelines, tags, branches, contributors, commits, and activity.
- Preview changelog entries from a local `CHANGELOG.md` when available.
- Pin, unpin, or hide the repository.

## Repository Browser

Preferences > Repositories searches projects the configured GitLab token can access and lets you choose what appears in the menu:

- `Visible` keeps the repo available through normal sorting and filtering.
- `Pinned` keeps the repo near the top.
- `Hidden` removes it from the menu.
- Manual rules remain visible even if a token no longer returns the repo, which makes access problems easier to diagnose.

RepoPeek can see public projects, user projects, collaborator projects, and group projects that the configured token can access.

## Authentication

RepoPeek supports GitLab Personal Access Token authentication only.

Use a GitLab PAT with read access to projects, issues, merge requests, pipelines, releases, branches, tags, and repository contents. Self-managed GitLab instances are configured by host URL, for example `https://gitlab.example.com`.

Release builds store tokens in the macOS Keychain. Debug builds and SwiftPM test runs default to file-backed auth storage so local development does not trigger Keychain prompts. See [docs/auth-storage.md](docs/auth-storage.md).

## Local Projects

RepoPeek can scan a local projects folder such as `~/Projects` and match local checkouts to GitLab projects, including `group/subgroup/project` paths.

Local state appears directly in the menu:

- current branch
- upstream branch
- ahead/behind counts
- dirty file summary
- worktree state
- fast-forward sync status

Optional auto-sync fetches and fast-forwards clean repositories on a configurable cadence. It does not force-push, hard-reset, or discard local changes. See [docs/reposync.md](docs/reposync.md).

## Caching, Archives, And Rate Limits

RepoPeek opens from local data first and spends GitLab requests carefully.

It stores REST ETags, response bodies, recent lists, repository detail data, and rate-limit state in RepoPeek-owned storage. First-open menu rows can be seeded from the persistent cache, then refreshed in the background.

The optional typed GitLab reference monitor is cache-first too: when enabled in Advanced settings, RepoPeek watches issue-number patterns and commit-like hashes, looks for matching cached issues, merge requests, or commits in accessible repositories, and falls back to live GitLab lookups on cache misses. The best match appears as a separate menu bar item that opens in your default browser. Global monitoring requires granting RepoPeek Accessibility permission in System Settings.

RepoPeek can import compatible Git-backed archive snapshots into its own SQLite cache. Archive databases are read-only on the menu path and are used as fallback data when live GitLab is limited, offline, or temporarily unavailable.

The current cache and archive behavior is documented in [docs/cache.md](docs/cache.md).

## Development

RepoPeek is a SwiftPM-based macOS app wrapped by `pnpm` scripts.

Requirements:

- macOS
- Xcode 26 / Swift 6.2
- pnpm 10+

Install script dependencies once:

```bash
pnpm install
```

Common commands:

```bash
pnpm check     # swiftformat + swiftlint + swift test
pnpm test      # Swift Testing suite
pnpm build     # debug Swift build
pnpm start     # build, package, sign, and launch a debug app from this checkout
pnpm restart   # relaunch the debug app from this checkout
Scripts/install_local_app.sh # package a release app, ad-hoc sign if needed, install to /Applications, and clean artifacts
pnpm stop      # quit RepoPeek
```

Always launch local builds through `pnpm start` or `pnpm restart`. If the menu does not match the code you just edited, verify the running binary:

```bash
pgrep -af "RepoPeek.app/Contents/MacOS/RepoPeek"
```

## Project Layout

- `Sources/RepoPeek/` - macOS app, menu, settings, auth coordination, local project UI.
- `Sources/RepoPeekCore/` - GitLab client, cache/archive readers, models, settings, local Git services.
- `Tests/RepoPeekTests/` - Swift Testing coverage.
- `docs/` - design notes and operational docs.
- `Scripts/` - build, package, signing, testing, and launch wrappers.

Useful docs:

- [docs/spec.md](docs/spec.md) - product and technical spec.
- [docs/cache.md](docs/cache.md) - persistent cache and archive design.
- [docs/auth-storage.md](docs/auth-storage.md) - Keychain vs debug file-backed token storage.
- [docs/reposync.md](docs/reposync.md) - local project scanning and sync behavior.
- [docs/release.md](docs/release.md) - release checklist.

## Status

This project is independently maintained as GitLab-only and PAT-only. It is not affiliated with GitLab Inc.; GitLab is a trademark of GitLab Inc. Legacy provider clients, browser sign-in helpers, token refresh helpers, generated schema tooling, and schema-query cache paths are not part of the supported product surface.

## License

MIT. See [LICENSE](LICENSE).
