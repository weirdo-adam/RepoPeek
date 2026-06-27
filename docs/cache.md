---
summary: "RepoPeek caching and archive source design."
read_when:
  - Adding or changing persistent GitLab caching
  - Adding SQLite or GRDB-backed storage
  - Integrating Git-backed issue/MR archives
  - Debugging rate-limit behavior or stale cached data
---

# Cache And Archive Design

RepoPeek owns its cache and archive configuration. It does not infer settings from external crawler config files.

## Goals

- Open menus from local data first.
- Spend GitLab requests only when data is stale and the rate budget is healthy.
- Survive app restarts with persistent ETags, REST response bodies, recent lists, and rate-limit state.
- Allow one or more GitLab archive snapshots to be configured directly in RepoPeek.
- Treat archive snapshots as read-only input unless the user explicitly runs an import/update command.

## RepoPeek-Owned Configuration

RepoPeek stores archive sources in `UserSettings.gitlabArchives`.

```swift
public struct GitLabArchiveSettings: Equatable, Codable {
    public var sources: [GitLabArchiveSource] = []
    public var preferArchiveWhenRateLimited = true
    public var staleAfterSeconds: TimeInterval = 15 * 60
}

public struct GitLabArchiveSource: Identifiable, Equatable, Codable {
    public var id: String
    public var name: String
    public var enabled: Bool = true
    public var localRepositoryPath: String?
    public var remoteURL: String?
    public var branch: String = "main"
    public var importedDatabasePath: String
    public var format: GitLabArchiveFormat = .snapshot
}
```

Archive sources are managed from Advanced settings. An explicit update pulls the configured Git snapshot repo when a remote is set, reads `manifest.json`, imports `tables/<table>/*.jsonl` and `tables/<table>/*.jsonl.gz` into the configured SQLite database, and records import metadata.

## RepoPeek SQLite Cache

RepoPeek persists REST ETag response bodies and rate-limit reset times in `~/Library/Application Support/RepoPeek/Cache.sqlite` using GRDB.

Future same-host multi-user support should partition this cache by account ID.
See [Account Model Upgrade Design](account-model.md) for the planned
`Cache/<safe-account-id>.sqlite` layout and migration path.

Current tables:

- `api_responses`: request key, URL, ETag, status, headers JSON, body, fetch time, and rate-limit metadata.
- `rate_limits`: resource name, remaining budget, reset time, and last error.

Current behavior:

- The SQLite schema and cache helpers can store REST ETags, response bodies, and rate-limit reset state.
- Live REST requests still need to be wired through the cache helpers before conditional `304 Not Modified` responses are available end-to-end.
- Menu opens read local state only; they do not start GitLab refreshes or fan out recent-list prefetches.
- Background refreshes hydrate only the selected visible repositories. Additional repository details load when the user opens that repository's submenu.
- The main menu includes a GitLab API Status submenu that shows the current blocker first, then combines live REST state with the latest persisted REST resource headers.

## Snapshot Shape

Use a simple Git-backed snapshot shape:

- `manifest.json` at the snapshot root.
- Table data in `tables/<table>/NNNNNN.jsonl.gz`.
- Manifest table entries with `name`, `files`, `columns`, and `rows`.
- Optional `files` checksums.
- Imported data stored in SQLite.
- Freshness stored in `sync_state`.

Suggested tables:

- `repositories`: group path, visibility, archived/fork flags, stars, forks, open issue/MR counts, pushed/updated timestamps.
- `threads`: issues and merge requests with number, kind, state, title, author, labels, timestamps, draft/merged fields, URL, and raw JSON.
- `comments`: issue/MR comments and review comments.
- `timeline_events`: renamed/closed/reopened/labeled/merged events.
- `pipelines`: recent pipeline runs keyed by repository.
- `releases`: release/tag metadata.
- `sync_state`: source freshness, last import, and per-repo cursors.
- `documents_fts`: optional FTS table for issue/MR/comment search.

## Read Policy

RepoPeek issue and merge request list policy:

- Use live GitLab while the request budget is healthy so fresh data wins.
- Use ETags for REST requests so repeated calls spend minimal budget.
- If GitLab is rate-limited, offline, or temporarily unavailable, read enabled archive databases and return the first non-empty archive result.

Menu opens should not run `git pull`, import snapshots, or fan out live GitLab requests. Snapshot updates belong to explicit commands, explicit settings buttons, or a background task with a long throttle and visible status.

## Write Policy

RepoPeek writes only its own cache database. Archive databases are read-only from the menu path.

Allowed writes:

- A Settings button triggers the same explicit update path and persists the resolved local checkout path for remote-only sources.

Disallowed writes:

- Do not edit external crawler config.
- Do not write into external archive databases.
- Do not auto-discover archive paths from other tools.
- Do not update Git snapshot repos during menu open.

## Rate-Limit Behavior

Persist:

- API response ETags and bodies.
- `X-RateLimit-Resource`, limit, remaining count, reset time, and last error.
- Per-request backoff for limited or temporarily unavailable endpoints.

When budget is low:

- Skip background prefetch.
- Prefer archive reads for issue/MR lists.
- Keep interactive requests limited to the opened repo/submenu.
- Surface the reset time in the menu instead of showing an endless loading row.
