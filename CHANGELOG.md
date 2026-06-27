# Changelog

## 2026.06.04

- Add copyable update diagnostics to the About settings screen so support details can be shared directly from the app.
- Improve GitLab reference parsing for owner/repo merge request and issue references without leaking matches across same-number repositories.
- Support same-host GitLab accounts with separate PAT storage, account-scoped repository identity, and account-scoped REST cache files.
- Scope pinned repositories, hidden repositories, and hidden groups by GitLab account so users on the same host do not share visibility rules.
- Add a local install path that packages a release app, ad-hoc signs when needed, and cleans packaging artifacts after updating `/Applications/RepoPeek.app`.

## 2026.05.30

- Refine the main menu into a quieter GitLab work dashboard with persistent repository search, clearer status controls, foreground-only refresh progress, and better preview fallback handling.
- Add menu and display settings for activity sections, keyboard shortcuts, search focus behavior, issue navigator access, and repository visibility controls.
- Improve GitLab data refresh behavior with REST GET cache cooldowns, endpoint backoff persistence, global activity caching, repository hydration, and quieter background refreshes.
- Improve repository and heatmap presentation, including selected-window heatmap sizing, clearer sort icons, compact submenu rows, and better empty/loading menu states.
- Tighten settings layouts across account, repository, keyboard shortcut, archive, display, and About screens, including a simpler repository rule composer with direct Pin/Hide actions.
- Update the app icon and align bundle, appcast, docs, scripts, and generated metadata with the RepoPeek product identity.
- Expand test coverage for GitLab REST caching, global activity cache, heatmap sizing, menu signatures, repository hydration, settings persistence, and status bar menu behavior.

## 2026.05.29

- Bump version metadata to 2026.05.29 / 2026052901.

## 0.5.0-gitlab
- Convert RepoPeek to a GitLab-only, PAT-only app.
- Add GitLab REST clients for project lists, project search, details, issues, merge requests, releases, pipelines, tags, branches, commits, contributors, repository contents, and events.
- Preserve full `group/subgroup/project` paths for local project matching and self-managed GitLab web routes.
- Replace browser sign-in with Personal Access Token sign-in.
- Update macOS user-facing text to GitLab, merge requests, pipelines, and PAT.
- Switch Add Repo and repository settings autocomplete to GitLab.
- Switch activity loading to GitLab project events.
- Move packaging, bundle identifiers, Sparkle appcast metadata, and release scripts to RepoPeek.
- Move debug auth, cache, archive, log, update, and release defaults into RepoPeek-owned namespaces.
- Remove runtime schema-query cache/rate-limit surfaces and generated schema tooling.
- Remove provider compatibility branches and auxiliary tooling.
