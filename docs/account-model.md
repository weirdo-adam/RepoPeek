---
summary: "Planned RepoPeek account model upgrade for same-host multi-user PAT support."
read_when:
  - Adding same-host multi-user GitLab accounts
  - Changing PAT storage keys or account settings
  - Scoping pinned/hidden repositories by account
  - Partitioning REST caches by account
---

# Account Model Upgrade Design

RepoPeek currently treats a GitLab account as one GitLab host. That works for
GitLab.com plus self-managed instances, but it cannot safely represent two PAT
owners on the same host. The next account model should identify an account by
both host and username while keeping the product GitLab-only and PAT-only.

## Current Model

Current account state is host-scoped:

- `UserSettings.gitlabAccounts` stores `GitLabAccountSettings` records keyed by
  normalized host.
- `TokenStore.savePAT(_:forHost:)` stores PATs under `pat:<hostKey>`.
- `GitLabClientRegistry` owns one `GitLabClient` per host key.
- Repository visibility rules stay in the global `repoList` settings.
- REST cache data lives in one `~/Library/Application Support/RepoPeek/Cache.sqlite`.

This means separate users on `https://gitlab.example.com` would collide in
settings, PAT storage, pinned/hidden rules, and cache state.

## Target Model

Add a stable account identity that is derived after token verification:

```swift
public struct GitLabAccount: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var host: URL
    public var username: String
    public var displayName: String
    public var enabled: Bool
    public var addedAt: Date
}
```

Account ID formula:

```swift
"\(hostKey)#\(username.lowercased())"
```

Examples:

- `gitlab.com#alice`
- `gitlab.example.com#bob`
- `gitlab.example.com:8443/group#alice` when the configured GitLab base URL has a path.

Keep PAT-only authentication. Do not add OAuth, browser sign-in, provider
abstractions, or GitHub compatibility branches.

## Settings

Extend `UserSettings` additively:

```swift
public var accounts: [GitLabAccount] = []
public var activeAccountID: String?
public var accountSelection: GitLabAccountSelection = .all
public var accountScopedRepositoryLists = AccountScopedRepositoryLists()
```

Keep `gitlabAccounts` as a compatibility shim for one migration cycle. New UI
should render `accounts`; old settings should migrate into `accounts` after the
first successful token verification.

`GitLabAccountSelection` should be `.all` or `.only(Set<String>)` so users can
temporarily hide an account from menus without deleting credentials.

## PAT Storage

Add account-scoped TokenStore methods while preserving host-scoped wrappers:

```swift
func savePAT(_ token: String, accountID: String) throws
func loadPAT(accountID: String) throws -> String?
func clearPAT(accountID: String)
func indexedAccountIDs() throws -> [String]
```

Keychain and file-backed storage should use stable account keys:

- `pat:<accountID>` for the PAT.
- `index:accounts` for the account ID list, if the backend cannot enumerate
  keys cheaply.

Migration:

1. Load each existing host-scoped PAT.
2. Call `/user` with that PAT to get the GitLab username.
3. Create `GitLabAccount(id: "\(hostKey)#\(username.lowercased())", ...)`.
4. Copy the PAT to `pat:<accountID>`.
5. Keep the host-scoped PAT for one release so downgrade remains possible.
6. Prefer account-scoped reads when both entries exist.

## Client Registry

`GitLabClientRegistry` should be keyed by `accountID`, not only host key. Each
client still points at the account host, but its token provider reads
`loadPAT(accountID:)`.

Repository identity should carry both:

- `hostKey` for URL routing.
- `accountID` for auth, cache, and visibility rules.

If a repository is visible through two accounts, UI identity should include
`accountID` so SwiftUI lists and menu caches do not collapse rows incorrectly.

## Repository Visibility

Move pinned and hidden lists from global repository names to account-scoped
names:

```swift
public struct AccountScopedRepositoryLists: Equatable, Codable, Sendable {
    public var pinnedByAccount: [String: [String]]
    public var hiddenByAccount: [String: [String]]
}
```

Migration rule:

- If there is exactly one account, attach all legacy pinned/hidden entries to
  that account.
- If there are multiple accounts, keep legacy entries visible as fallback until
  the user saves settings, then write explicit account-scoped lists.

## Cache Partitioning

Keep the legacy path for current installs:

```text
~/Library/Application Support/RepoPeek/Cache.sqlite
```

Add account-scoped paths:

```text
~/Library/Application Support/RepoPeek/Cache/<safe-account-id>.sqlite
```

Use a deterministic safe filename such as `v2-<hex-encoded-account-id>` so
characters like `/`, `:`, and `#` never leak into path segments.

Migration:

1. For one migrated account, copy or move `Cache.sqlite` into that account's
   scoped cache.
2. For multiple accounts, leave the legacy cache readable only as a cold-start
   fallback for the active account.
3. Write all new ETag, response body, and rate-limit state to account-scoped
   databases.
4. Diagnostics should show the active account cache path and whether the legacy
   cache is still present.

## Rollout Order

1. Add `GitLabAccount`, account selection, account-scoped repository lists, and
   TokenStore account methods with tests.
2. Add one-shot migration from host-scoped settings and PATs after `/user`
   verification.
3. Change `GitLabClientRegistry` and refresh paths to use `accountID`.
4. Partition the REST cache and update diagnostics.
5. Update settings UI to show `username @ host`, active account, visibility,
   verify, and remove actions.
6. Remove legacy host-scoped writes after one compatible release.

## Test Plan

- Host-scoped settings decode into one account after token verification.
- Two users on one host store different PATs and do not load each other's token.
- Same repository from two accounts keeps separate menu/cache identity.
- Pinned and hidden rules migrate to the only account and remain stable.
- Account-scoped cache filenames are deterministic and path-safe.
- Legacy `Cache.sqlite` remains readable during migration but is not used for
  new writes once account scope is available.
