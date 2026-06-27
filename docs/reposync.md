---
summary: "Local Projects: scan a project folder, map repos to GitLab cards, show branch + optional auto-sync."
read_when:
  - Adding/changing Local Projects scanning or matching
  - Debugging "no repositories found" in sandboxed builds
  - Adjusting auto-sync behavior or notifications
---

# Local Projects

Goal: map a local project folder such as `~/Projects` to GitLab repositories shown in RepoPeek, then surface local branch and sync state, with optional fast-forward auto-sync.

## User-Facing Behavior

### Settings

- **Project folder**: pick a folder; if unset, Local Projects UI stays hidden everywhere.
- **Found count**: show how many git repos are discovered under the folder, even if no GitLab match exists yet.
- **Rescan**: icon button (`arrow.clockwise`); triggers a forced rescan and status refresh.
- **Auto-sync clean repos**: when enabled, attempts `git pull --ff-only` on eligible repos.
- **Show dirty files in menu**: shows up to 3 dirty files inline in the main menu.
- **Fetch interval**: controls how often RepoPeek runs `git fetch --prune`; the default is one hour.
- **Scan depth**: how many folder levels to traverse under the root.
- **Worktree folder**: default subfolder used for new worktrees.
- **Preferred Terminal**: choose terminal app for "Open in Terminal" actions.

### Repo cards and details

- Repo card: show current local branch and a small status icon when a matching local repo exists.
- Details/menu: show branch, sync state, plus actions:
  - Open in Finder
  - Open in Terminal

### Notifications

- Fire a local notification on successful sync.
- No notification on failure.

## Scanning And Matching

### Discovery

- Scan the selected folder up to the configured depth.
- A directory counts as a git repo if it contains `.git` as a file or folder.
- Skip hidden directories and symlinks.

### Mapping to GitLab repos

- Primary match: parse `origin` remote and preserve the full `group/subgroup/project` path.
- Fallback match: folder name equals GitLab project name when the remote is absent.
- Preserve the remote web host so self-managed GitLab URLs open on the correct instance.
- Only compute git status for visible, pinned, or locally matched repos.

## Auto-Sync Rules

Only attempt sync when:

- repo is clean,
- not detached HEAD,
- behind remote,
- pull is fast-forward only (`git pull --ff-only`).

"Synced" means pull succeeded and `rev-parse HEAD` changed.

## Refresh And Caching

Triggers:

- App refresh tick.
- Settings Local Projects section appears.
- Manual Rescan button.

Caching:

- Discovery cache TTL: 10 minutes.
- Status cache TTL: 2 minutes.
- Auto-sync is off by default so choosing a large project folder does not immediately start many `git pull` operations.
- Forced rescan bypasses both caches.

## Sandbox Notes

RepoPeek runs sandboxed; project folder access requires:

- Persisted security-scoped bookmark for the chosen folder.
- Entitlement: `com.apple.security.files.user-selected.read-write`.

If bookmark is missing or stale, show `0 repos` until the user re-chooses the folder.
