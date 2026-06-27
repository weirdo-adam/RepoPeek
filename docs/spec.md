---
summary: "RepoPeek product and technical spec."
read_when:
  - Changing core app behavior or data-fetching behavior
  - Adding new menu surfaces or settings
  - Adjusting auth, cache, local repo sync, or release behavior
---

# RepoPeek Spec

## Product Scope

RepoPeek is a macOS menubar-only app for GitLab repositories. It shows selected projects with pipeline state, issue/MR counts, latest release, recent activity, local Git state, and rate-limit health.

The app is GitLab-only and PAT-only. It does not contain browser sign-in, token exchange helpers, generated API schemas, or multi-provider compatibility branches.

## Supported GitLab Targets

- GitLab.com.
- Self-managed GitLab over HTTPS.
- Group and subgroup project paths such as `group/subgroup/project`.

## Auth

- The user signs in with a GitLab Personal Access Token.
- Release builds store the PAT in the macOS Keychain.
- Debug builds can use file-backed storage via `RepoPeekTokenStore=file` or `REPOPEEK_TOKEN_STORE=file`.
- The token must have enough read access for projects, issues, merge requests, pipelines, releases, branches, tags, repository contents, and events.

## Core Data

All live network fetching lives in `RepoPeekCore` through `GitLabClient` and `GitLabRestAPI`.

Primary REST surfaces:

- Repository list and search.
- Repository detail and counts.
- Issues and merge requests.
- Releases, tags, branches, commits, contributors.
- Pipelines.
- Project events for activity.
- Repository contents and file previews.
- Rate-limit headers and endpoint backoff state.

## Menu Behavior

Main menu:

- Account/profile row.
- Optional contribution heatmap header.
- GitLab API Status row.
- Repository filter and sort controls.
- Repository cards.
- Preferences, About, refresh, and quit actions.

Repository submenu:

- Open in GitLab.
- Open local checkout when available.
- Checkout project into Local Projects root.
- Local branch/worktree state.
- Recent issues, merge requests, releases, pipelines, tags, branches, contributors, commits, and activity.
- Pin/hide controls.

## Local Projects

Local project scanning preserves full GitLab path identity and remote web host. A local remote such as:

```text
git@gitlab.example.com:platform/core/service.git
```

maps to:

```text
host: gitlab.example.com
fullName: platform/core/service
```

Browser routes for local projects use that host, not a hard-coded public instance.

## Cache And Archives

- REST ETag response bodies and rate-limit state are persisted in `Cache.sqlite`.
- Menu open reads local snapshots/cache only; scheduled and manual refreshes own GitLab traffic.
- Background refresh defaults to a six-hour interval and hydrates only the selected visible repositories.
- Archive sources are configured by the user and imported into RepoPeek-owned SQLite databases.
- Archive databases are fallback input only; menu open must not mutate archive sources.

## Settings

Settings are stored through `UserSettings` and `SettingsStore`.

Important user settings:

- GitLab host.
- PAT auth state.
- repository visibility rules.
- menu sort and filters.
- local project root and sync behavior.
- archive sources.
- diagnostics and logging.

## Release And Maintenance

The app has an independent bundle identifier, Keychain service, local storage namespace, signing configuration, Sparkle appcast, and release flow. Release builds must not share service IDs, cache/archive locations, signing identities, or update feeds with any other app.

## Validation

Before shipping a change:

- `pnpm build`
- `pnpm test` when the local Swift Testing toolchain is available
- `git diff --check`
- Manual smoke through `pnpm restart` for menu/UI changes
