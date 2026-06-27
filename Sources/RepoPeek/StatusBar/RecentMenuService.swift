import Foundation
import RepoPeekCore

@MainActor
final class RecentMenuService {
    let listLimit: Int
    let previewLimit: Int
    let cacheTTL: TimeInterval
    let loadTimeout: TimeInterval

    private let clientProvider: @MainActor (String?) async -> GitLabClient
    private let recentIssuesCache = RecentListCache<RepoIssueSummary>()
    private let recentPullRequestsCache = RecentListCache<RepoPullRequestSummary>()
    private let recentReleasesCache = RecentListCache<RepoReleaseSummary>()
    private let recentWorkflowRunsCache = RecentListCache<RepoWorkflowRunSummary>()
    private let recentCommitsCache = RecentListCache<RepoCommitSummary>()
    private let recentTagsCache = RecentListCache<RepoTagSummary>()
    private let recentBranchesCache = RecentListCache<RepoBranchSummary>()
    private let recentContributorsCache = RecentListCache<RepoContributorSummary>()
    private var recentCommitCounts: [String: Int] = [:]

    init(
        gitlab: GitLabClient,
        listLimit: Int = AppLimits.RecentLists.limit,
        previewLimit: Int = AppLimits.RecentLists.previewLimit,
        cacheTTL: TimeInterval = AppLimits.RecentLists.cacheTTL,
        loadTimeout: TimeInterval = AppLimits.RecentLists.loadTimeout
    ) {
        self.clientProvider = { _ in gitlab }
        self.listLimit = listLimit
        self.previewLimit = previewLimit
        self.cacheTTL = cacheTTL
        self.loadTimeout = loadTimeout
    }

    init(
        clientProvider: @escaping @MainActor (String?) async -> GitLabClient,
        listLimit: Int = AppLimits.RecentLists.limit,
        previewLimit: Int = AppLimits.RecentLists.previewLimit,
        cacheTTL: TimeInterval = AppLimits.RecentLists.cacheTTL,
        loadTimeout: TimeInterval = AppLimits.RecentLists.loadTimeout
    ) {
        self.clientProvider = clientProvider
        self.listLimit = listLimit
        self.previewLimit = previewLimit
        self.cacheTTL = cacheTTL
        self.loadTimeout = loadTimeout
    }

    func descriptor(for kind: RepoRecentMenuKind) -> RecentMenuDescriptor? {
        self.descriptors()[kind]
    }

    func descriptors() -> [RepoRecentMenuKind: RecentMenuDescriptor] {
        let commitDescriptor = self.commitDescriptor()

        let descriptors: [RecentMenuDescriptor] = [
            commitDescriptor,
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .issues,
                headerTitle: "Open Issues",
                headerIcon: "exclamationmark.circle",
                emptyTitle: "No open issues",
                cache: self.recentIssuesCache,
                wrap: RecentMenuItems.issues,
                unwrap: { boxed in
                    if case let .issues(items) = boxed { return items }
                    return nil
                },
                fetch: { hostKey, owner, name, limit in
                    try await self.recentIssues(hostKey: hostKey, owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .pullRequests,
                headerTitle: "Open Merge Requests",
                headerIcon: "arrow.triangle.branch",
                emptyTitle: "No open merge requests",
                cache: self.recentPullRequestsCache,
                wrap: RecentMenuItems.pullRequests,
                unwrap: { boxed in
                    if case let .pullRequests(items) = boxed { return items }
                    return nil
                },
                fetch: { hostKey, owner, name, limit in
                    try await self.recentPullRequests(hostKey: hostKey, owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .releases,
                headerTitle: "Open Releases",
                headerIcon: "tag",
                emptyTitle: "No releases",
                cache: self.recentReleasesCache,
                wrap: RecentMenuItems.releases,
                unwrap: { boxed in
                    if case let .releases(items) = boxed { return items }
                    return nil
                },
                fetch: { hostKey, owner, name, limit in
                    try await self.recentReleases(hostKey: hostKey, owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .ciRuns,
                headerTitle: "Open Pipelines",
                headerIcon: "bolt",
                emptyTitle: "No pipelines",
                cache: self.recentWorkflowRunsCache,
                wrap: RecentMenuItems.workflowRuns,
                unwrap: { boxed in
                    if case let .workflowRuns(items) = boxed { return items }
                    return nil
                },
                fetch: { hostKey, owner, name, limit in
                    try await self.recentWorkflowRuns(hostKey: hostKey, owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .tags,
                headerTitle: "Open Tags",
                headerIcon: "tag",
                emptyTitle: "No tags",
                cache: self.recentTagsCache,
                wrap: RecentMenuItems.tags,
                unwrap: { boxed in
                    if case let .tags(items) = boxed { return items }
                    return nil
                },
                fetch: { hostKey, owner, name, limit in
                    try await self.recentTags(hostKey: hostKey, owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .branches,
                headerTitle: "Open Branches",
                headerIcon: "point.topleft.down.curvedto.point.bottomright.up",
                emptyTitle: "No branches",
                cache: self.recentBranchesCache,
                wrap: RecentMenuItems.branches,
                unwrap: { boxed in
                    if case let .branches(items) = boxed { return items }
                    return nil
                },
                fetch: { hostKey, owner, name, limit in
                    try await self.recentBranches(hostKey: hostKey, owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .contributors,
                headerTitle: "Open Contributors",
                headerIcon: "person.2",
                emptyTitle: "No contributors",
                cache: self.recentContributorsCache,
                wrap: RecentMenuItems.contributors,
                unwrap: { boxed in
                    if case let .contributors(items) = boxed { return items }
                    return nil
                },
                fetch: { hostKey, owner, name, limit in
                    try await self.topContributors(hostKey: hostKey, owner: owner, name: name, limit: limit)
                }
            ))
        ]

        return Dictionary(uniqueKeysWithValues: descriptors.map { ($0.kind, $0) })
    }

    func cachedRecentCommitCount(cacheKey: String) -> Int? {
        if let total = self.recentCommitCounts[cacheKey] { return total }
        return self.recentCommitsCache.stale(for: cacheKey)?.count
    }

    func cachedCommits(cacheKey: String, now: Date = Date()) -> [RepoCommitSummary]? {
        self.recentCommitsCache.cached(for: cacheKey, now: now, maxAge: self.cacheTTL)
            ?? self.recentCommitsCache.stale(for: cacheKey)
    }

    func cachedCommitDigest(cacheKey: String) -> Int? {
        let now = Date()
        guard let commits = self.cachedCommits(cacheKey: cacheKey, now: now), commits.isEmpty == false else { return nil }

        var hasher = Hasher()
        for commit in commits {
            hasher.combine(commit.sha)
            hasher.combine(commit.authoredAt.timeIntervalSinceReferenceDate)
        }
        return hasher.finalize()
    }

    private func commitDescriptor() -> RecentMenuDescriptor {
        RecentMenuDescriptor(
            kind: .commits,
            headerTitle: "Open Commits",
            headerIcon: "arrow.turn.down.right",
            emptyTitle: "No commits",
            cached: { key, now, ttl in
                self.recentCommitsCache.cached(for: key, now: now, maxAge: ttl).map(RecentMenuItems.commits)
            },
            stale: { key in
                self.recentCommitsCache.stale(for: key).map(RecentMenuItems.commits)
            },
            needsRefresh: { key, now, ttl in
                self.recentCommitsCache.needsRefresh(for: key, now: now, maxAge: ttl)
            },
            load: { key, hostKey, owner, name, limit in
                let task = self.recentCommitsCache.task(for: key) {
                    let list = try await self.recentCommits(hostKey: hostKey, owner: owner, name: name, limit: limit)
                    await MainActor.run {
                        self.recentCommitCounts[key] = list.totalCount ?? list.items.count
                    }
                    return list.items
                }
                defer { self.recentCommitsCache.clearInflight(for: key) }
                let items = try await AsyncTimeout.value(within: self.loadTimeout, task: task)
                let evictedKeys = self.recentCommitsCache.store(items, for: key, fetchedAt: Date())
                for evictedKey in evictedKeys {
                    self.recentCommitCounts[evictedKey] = nil
                }
                return RecentMenuItems.commits(items)
            }
        )
    }

    private func makeDescriptor(
        _ config: RecentMenuDescriptorConfig<some Sendable>
    ) -> RecentMenuDescriptor {
        let fetch = config.fetch

        return RecentMenuDescriptor(
            kind: config.kind,
            headerTitle: config.headerTitle,
            headerIcon: config.headerIcon,
            emptyTitle: config.emptyTitle,
            cached: { key, now, ttl in
                config.cache.cached(for: key, now: now, maxAge: ttl).map(config.wrap)
            },
            stale: { key in
                config.cache.stale(for: key).map(config.wrap)
            },
            needsRefresh: { key, now, ttl in
                config.cache.needsRefresh(for: key, now: now, maxAge: ttl)
            },
            load: { key, hostKey, owner, name, limit in
                let task = config.cache.task(for: key) {
                    try await fetch(hostKey, owner, name, limit)
                }
                defer { config.cache.clearInflight(for: key) }
                let items = try await AsyncTimeout.value(within: self.loadTimeout, task: task)
                _ = config.cache.store(items, for: key, fetchedAt: Date())
                return config.wrap(items)
            }
        )
    }

    private func recentIssues(hostKey: String?, owner: String, name: String, limit: Int) async throws -> [RepoIssueSummary] {
        let client = await self.client(hostKey: hostKey)
        return try await client.recentIssues(owner: owner, name: name, limit: limit)
    }

    private func recentPullRequests(hostKey: String?, owner: String, name: String, limit: Int) async throws -> [RepoPullRequestSummary] {
        let client = await self.client(hostKey: hostKey)
        return try await client.recentMergeRequests(owner: owner, name: name, limit: limit)
    }

    private func recentReleases(hostKey: String?, owner: String, name: String, limit: Int) async throws -> [RepoReleaseSummary] {
        let client = await self.client(hostKey: hostKey)
        return try await client.recentReleases(owner: owner, name: name, limit: limit)
    }

    private func recentWorkflowRuns(hostKey: String?, owner: String, name: String, limit: Int) async throws -> [RepoWorkflowRunSummary] {
        let client = await self.client(hostKey: hostKey)
        return try await client.recentPipelines(owner: owner, name: name, limit: limit)
    }

    private func recentCommits(hostKey: String?, owner: String, name: String, limit: Int) async throws -> RepoCommitList {
        let client = await self.client(hostKey: hostKey)
        return try await client.recentCommits(owner: owner, name: name, limit: limit)
    }

    private func recentTags(hostKey: String?, owner: String, name: String, limit: Int) async throws -> [RepoTagSummary] {
        let client = await self.client(hostKey: hostKey)
        return try await client.recentTags(owner: owner, name: name, limit: limit)
    }

    private func recentBranches(hostKey: String?, owner: String, name: String, limit: Int) async throws -> [RepoBranchSummary] {
        let client = await self.client(hostKey: hostKey)
        return try await client.recentBranches(owner: owner, name: name, limit: limit)
    }

    private func topContributors(hostKey: String?, owner: String, name: String, limit: Int) async throws -> [RepoContributorSummary] {
        let client = await self.client(hostKey: hostKey)
        return try await client.topContributors(owner: owner, name: name, limit: limit)
    }

    private func client(hostKey: String?) async -> GitLabClient {
        await self.clientProvider(hostKey)
    }
}

struct RecentMenuDescriptorConfig<Item: Sendable> {
    let kind: RepoRecentMenuKind
    let headerTitle: String
    let headerIcon: String?
    let emptyTitle: String
    let cache: RecentListCache<Item>
    let wrap: ([Item]) -> RecentMenuItems
    let unwrap: (RecentMenuItems) -> [Item]?
    let fetch: @Sendable (String?, String, String, Int) async throws -> [Item]
}

struct RecentMenuDescriptor {
    let kind: RepoRecentMenuKind
    let headerTitle: String
    let headerIcon: String?
    let emptyTitle: String
    let cached: (String, Date, TimeInterval) -> RecentMenuItems?
    let stale: (String) -> RecentMenuItems?
    let needsRefresh: (String, Date, TimeInterval) -> Bool
    let load: @MainActor (String, String?, String, String, Int) async throws -> RecentMenuItems
}

enum RecentMenuItems {
    case commits([RepoCommitSummary])
    case issues([RepoIssueSummary])
    case pullRequests([RepoPullRequestSummary])
    case releases([RepoReleaseSummary])
    case workflowRuns([RepoWorkflowRunSummary])
    case tags([RepoTagSummary])
    case branches([RepoBranchSummary])
    case contributors([RepoContributorSummary])

    var isEmpty: Bool {
        switch self {
        case let .commits(items): items.isEmpty
        case let .issues(items): items.isEmpty
        case let .pullRequests(items): items.isEmpty
        case let .releases(items): items.isEmpty
        case let .workflowRuns(items): items.isEmpty
        case let .tags(items): items.isEmpty
        case let .branches(items): items.isEmpty
        case let .contributors(items): items.isEmpty
        }
    }

    var count: Int {
        switch self {
        case let .commits(items): items.count
        case let .issues(items): items.count
        case let .pullRequests(items): items.count
        case let .releases(items): items.count
        case let .workflowRuns(items): items.count
        case let .tags(items): items.count
        case let .branches(items): items.count
        case let .contributors(items): items.count
        }
    }
}

final class RecentListCache<Item: Sendable> {
    struct Entry {
        var fetchedAt: Date
        var items: [Item]
    }

    private let maxEntries: Int
    private var entries: [String: Entry] = [:]
    private var entryOrder: [String] = []
    private var inflight: [String: Task<[Item], Error>] = [:]

    init(maxEntries: Int = AppLimits.RecentLists.cacheEntries) {
        self.maxEntries = max(0, maxEntries)
    }

    func cached(for key: String, now: Date, maxAge: TimeInterval) -> [Item]? {
        guard let entry = self.entries[key] else { return nil }
        guard now.timeIntervalSince(entry.fetchedAt) <= maxAge else { return nil }

        self.touch(key)
        return entry.items
    }

    func stale(for key: String) -> [Item]? {
        guard let entry = self.entries[key] else { return nil }

        self.touch(key)
        return entry.items
    }

    func needsRefresh(for key: String, now: Date, maxAge: TimeInterval) -> Bool {
        guard let entry = self.entries[key] else { return true }

        return now.timeIntervalSince(entry.fetchedAt) > maxAge
    }

    func task(for key: String, factory: @escaping @Sendable () async throws -> [Item]) -> Task<[Item], Error> {
        if let existing = self.inflight[key] { return existing }
        let task = Task { try await factory() }
        self.inflight[key] = task
        return task
    }

    func clearInflight(for key: String) {
        self.inflight[key] = nil
    }

    @discardableResult
    func store(_ items: [Item], for key: String, fetchedAt: Date) -> [String] {
        guard self.maxEntries > 0 else { return [] }

        self.entries[key] = Entry(fetchedAt: fetchedAt, items: items)
        self.touch(key)
        return self.evictIfNeeded()
    }

    func count() -> Int {
        self.entries.count
    }

    private func touch(_ key: String) {
        self.entryOrder.removeAll { $0 == key }
        self.entryOrder.append(key)
    }

    private func evictIfNeeded() -> [String] {
        var evicted: [String] = []
        while self.entries.count > self.maxEntries, let oldest = self.entryOrder.first {
            self.entryOrder.removeFirst()
            if self.entries.removeValue(forKey: oldest) != nil {
                evicted.append(oldest)
            }
        }
        return evicted
    }
}
