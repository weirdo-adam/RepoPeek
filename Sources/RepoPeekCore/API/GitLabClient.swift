import Foundation

public actor GitLabClient {
    private static let activityFetchConcurrencyLimit = 6

    public private(set) var webHost: URL = .init(string: "https://gitlab.com")!
    public private(set) var apiHost: URL = .init(string: "https://gitlab.com/api/v4")!
    private var tokenProvider: (@Sendable () async throws -> String?)?
    private let session: URLSession
    private let eTagCache: ETagCache
    private let backoffTracker: BackoffTracker
    private var lastRateLimitError: String?
    private var restRateLimit: RateLimitSnapshot?
    private var prefetchedRepos: [Repository] = []
    private var prefetchedReposExpiry: Date?
    private lazy var restAPI = GitLabRestAPI(
        apiHost: { [weak self] in
            await self?.apiHost ?? URL(string: "https://gitlab.com/api/v4")!
        },
        webHost: { [weak self] in
            await self?.webHost ?? URL(string: "https://gitlab.com")!
        },
        tokenProvider: { [weak self] in
            guard let self else { throw URLError(.userAuthenticationRequired) }

            return try await self.validAccessToken()
        },
        session: session,
        eTagCache: eTagCache,
        backoffTracker: backoffTracker,
        responseRecorder: { [weak self] response, now in
            await self?.recordResponse(response, now: now)
        },
        rateLimitErrorRecorder: { [weak self] _, message in
            await self?.recordRateLimitError(message)
        }
    )

    public init(session: URLSession = .shared, cacheAccountID: String? = nil) {
        self.init(
            session: session,
            eTagCache: ETagCache.persistent(accountID: cacheAccountID),
            backoffTracker: BackoffTracker()
        )
    }

    init(
        session: URLSession,
        eTagCache: ETagCache,
        backoffTracker: BackoffTracker
    ) {
        self.session = session
        self.eTagCache = eTagCache
        self.backoffTracker = backoffTracker
    }

    public func setWebHost(_ host: URL) throws {
        let normalized = try Self.normalizedWebHost(for: host)
        self.webHost = normalized
        self.apiHost = normalized.appending(path: "api/v4")
        self.prefetchedRepos = []
        self.prefetchedReposExpiry = nil
    }

    public func setTokenProvider(_ provider: @Sendable @escaping () async throws -> String?) {
        self.tokenProvider = provider
    }

    public func currentUser() async throws -> UserIdentity {
        let user = try await self.restAPI.fetchCurrentUser()
        return UserIdentity(username: user.username, host: self.webHostURL())
    }

    public func repositoryList(limit: Int?) async throws -> [Repository] {
        let webHost = self.webHostURL()
        let projects = try await self.restAPI.membershipProjects(limit: limit)
        return projects.map { $0.repository(webHost: webHost) }
    }

    public func fullRepository(owner: String, name: String) async throws -> Repository {
        try await self.restAPI.project(owner: owner, name: name).repository(webHost: self.webHostURL())
    }

    public func activityRepositories(limit: Int?) async throws -> [Repository] {
        let webHost = self.webHostURL()
        let projects = try await self.restAPI.membershipProjects(limit: limit)
        let eventsByPath = await self.fetchActivityEvents(for: projects)
        return projects.map { project in
            var repo = project.repository(webHost: webHost)
            let events = eventsByPath[project.pathWithNamespace] ?? repo.activityEvents
            repo.activityEvents = events
            repo.latestActivity = events.first ?? repo.latestActivity
            return repo
        }
    }

    public func recentRepositories(limit: Int = 8) async throws -> [Repository] {
        try await self.repositoryList(limit: limit)
    }

    public func searchRepositories(matching query: String) async throws -> [Repository] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return try await self.recentRepositories(limit: AppLimitsFallback.searchRecentLimit)
        }

        let webHost = self.webHostURL()
        let projects = try await self.restAPI.searchProjects(
            matching: trimmed,
            limit: AppLimitsFallback.searchLimit
        )
        return projects.map { $0.repository(webHost: webHost) }
    }

    public func prefetchedRepositories(max: Int = RepoCacheConstants.maxRepositoriesToPrefetch) async throws -> [Repository] {
        let now = Date()
        if let expires = self.prefetchedReposExpiry, expires > now, self.prefetchedRepos.isEmpty == false {
            return Array(self.prefetchedRepos.prefix(max))
        }

        let repos = try await self.repositoryList(limit: max)
        self.prefetchedRepos = repos
        self.prefetchedReposExpiry = now.addingTimeInterval(RepoCacheConstants.cacheTTL)
        return repos
    }

    public func cachedRepositoryList(limit: Int?) async throws -> [Repository] {
        try await self.repositoryList(limit: limit)
    }

    public func recentIssues(owner: String, name: String, limit: Int = 20) async throws -> [RepoIssueSummary] {
        try await self.restAPI.recentIssues(owner: owner, name: name, limit: limit)
    }

    public func searchIssues(owner: String, name: String, query: String, limit: Int = 20) async throws -> [RepoIssueSummary] {
        try await self.restAPI.searchIssues(owner: owner, name: name, query: query, limit: limit)
    }

    public func issue(owner: String, name: String, iid: Int) async throws -> RepoIssueSummary? {
        try await self.restAPI.issue(owner: owner, name: name, iid: iid)
    }

    public func recentMergeRequests(owner: String, name: String, limit: Int = 20) async throws -> [RepoPullRequestSummary] {
        try await self.restAPI.recentMergeRequests(owner: owner, name: name, limit: limit)
    }

    public func recentPullRequests(owner: String, name: String, limit: Int = 20) async throws -> [RepoPullRequestSummary] {
        try await self.recentMergeRequests(owner: owner, name: name, limit: limit)
    }

    public func openMergeRequestCount(owner: String, name: String) async throws -> Int {
        try await self.restAPI.openMergeRequestCount(owner: owner, name: name)
    }

    public func searchMergeRequests(owner: String, name: String, query: String, limit: Int = 20) async throws -> [RepoPullRequestSummary] {
        try await self.restAPI.searchMergeRequests(owner: owner, name: name, query: query, limit: limit)
    }

    public func mergeRequest(owner: String, name: String, iid: Int) async throws -> RepoPullRequestSummary? {
        try await self.restAPI.mergeRequest(owner: owner, name: name, iid: iid)
    }

    public func recentReleases(owner: String, name: String, limit: Int = 20) async throws -> [RepoReleaseSummary] {
        try await self.restAPI.recentReleases(owner: owner, name: name, limit: limit)
    }

    public func latestRelease(owner: String, name: String) async throws -> Release? {
        try await self.recentReleases(owner: owner, name: name, limit: 1).first.map {
            Release(name: $0.name, tag: $0.tag, publishedAt: $0.publishedAt, url: $0.url)
        }
    }

    public func recentPipelines(owner: String, name: String, limit: Int = 20) async throws -> [RepoWorkflowRunSummary] {
        try await self.restAPI.recentPipelines(owner: owner, name: name, limit: limit)
    }

    public func recentWorkflowRuns(owner: String, name: String, limit: Int = 20) async throws -> [RepoWorkflowRunSummary] {
        try await self.recentPipelines(owner: owner, name: name, limit: limit)
    }

    public func recentCommits(owner: String, name: String, limit: Int = 20) async throws -> RepoCommitList {
        try await self.restAPI.recentCommits(owner: owner, name: name, limit: limit)
    }

    public func commit(owner: String, name: String, sha: String) async throws -> RepoCommitSummary? {
        try await self.restAPI.commit(owner: owner, name: name, sha: sha)
    }

    public func userCommitEvents(username _: String, scope _: GlobalActivityScope, limit _: Int) async throws -> [RepoCommitSummary] {
        []
    }

    public func userActivityEvents(
        username _: String,
        scope: GlobalActivityScope,
        after: Date? = nil,
        before: Date? = nil,
        limit: Int
    ) async throws -> [ActivityEvent] {
        try await self.restAPI.userEvents(
            scope: scope,
            after: after,
            before: before,
            limit: limit
        )
    }

    public func repositoryActivityEvents(owner: String, name: String, limit: Int = 20) async throws -> [ActivityEvent] {
        try await self.restAPI.projectEvents(
            projectPath: GitLabRestAPI.projectPath(owner: owner, name: name),
            limit: limit
        )
    }

    public func recentTags(owner: String, name: String, limit: Int = 20) async throws -> [RepoTagSummary] {
        try await self.restAPI.recentTags(owner: owner, name: name, limit: limit)
    }

    public func recentBranches(owner: String, name: String, limit: Int = 20) async throws -> [RepoBranchSummary] {
        try await self.restAPI.recentBranches(owner: owner, name: name, limit: limit)
    }

    public func topContributors(owner: String, name: String, limit: Int = 20) async throws -> [RepoContributorSummary] {
        try await self.restAPI.topContributors(owner: owner, name: name, limit: limit)
    }

    public func repoContents(owner: String, name: String, path: String? = nil) async throws -> [RepoContentItem] {
        try await self.restAPI.repoContents(owner: owner, name: name, path: path)
    }

    public func repoFileContents(owner: String, name: String, path: String) async throws -> Data {
        try await self.restAPI.repoFileContents(owner: owner, name: name, path: path)
    }

    public func diagnostics() async -> DiagnosticsSummary {
        let now = Date()
        let rateLimitReset = await self.eTagCache.rateLimitUntil(now: now)
        let cooldowns = await self.backoffTracker.activeCooldowns(now: now)
        let endpointCooldowns = Self.endpointCooldowns(from: cooldowns)
        let etagEntries = await self.eTagCache.count()
        return DiagnosticsSummary(
            apiHost: self.apiHost,
            rateLimitReset: rateLimitReset,
            lastRateLimitError: rateLimitReset == nil ? nil : self.lastRateLimitError,
            etagEntries: etagEntries,
            backoffEntries: endpointCooldowns.count,
            endpointCooldowns: endpointCooldowns,
            restRateLimit: self.restRateLimit
        )
    }

    public static func apiHost(for webHost: URL) throws -> URL {
        try self.normalizedWebHost(for: webHost).appending(path: "api/v4")
    }

    public static func normalizedWebHost(for webHost: URL) throws -> URL {
        guard webHost.scheme?.lowercased() == "https", webHost.host != nil else {
            throw GitLabAPIError.invalidHost
        }

        var components = URLComponents(url: webHost, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        if components?.path == "/" {
            components?.path = ""
        } else if let path = components?.path, path.hasSuffix("/") {
            components?.path = String(path.dropLast())
        }
        guard let normalized = components?.url else { throw GitLabAPIError.invalidHost }

        return normalized
    }

    private func validAccessToken() async throws -> String {
        if let provider = self.tokenProvider {
            let providerToken = try await provider()
            if let providerToken, providerToken.isEmpty == false {
                return providerToken
            }
        }

        let storedToken = try TokenStore.shared.loadPAT()
        if let storedToken, storedToken.isEmpty == false {
            return storedToken
        }

        throw URLError(.userAuthenticationRequired)
    }

    private func webHostURL() -> URL {
        self.webHost
    }

    private func recordResponse(_ response: HTTPURLResponse, now: Date) {
        if let snapshot = RateLimitSnapshot.from(response: response, now: now) {
            self.restRateLimit = snapshot
        }
        if (200 ..< 400).contains(response.statusCode) {
            self.lastRateLimitError = nil
        }
    }

    private func recordRateLimitError(_ message: String?) {
        self.lastRateLimitError = message
    }

    private static func endpointCooldowns(from cooldowns: [String: Date]) -> [EndpointCooldownSummary] {
        cooldowns.compactMap { rawURL, retryAfter in
            guard let url = URL(string: rawURL) else { return nil }

            return self.endpointCooldown(url: url, retryAfter: retryAfter)
        }
        .sorted {
            if $0.retryAfter != $1.retryAfter { return $0.retryAfter < $1.retryAfter }
            return $0.url < $1.url
        }
    }

    private static func endpointCooldown(url: URL, retryAfter: Date) -> EndpointCooldownSummary {
        let components = Self.pathComponents(for: url)
        let projectIndex = components.firstIndex(of: "projects")
        let repository = projectIndex.flatMap { index in
            components.indices.contains(index + 1) ? components[index + 1] : nil
        }
        let endpointComponents = projectIndex.map { index in
            repository == nil
                ? Array(components.dropFirst(index))
                : Array(components.dropFirst(index + 2))
        } ?? components
        return EndpointCooldownSummary(
            endpoint: self.endpointLabel(from: endpointComponents),
            repository: repository,
            url: url.absoluteString,
            retryAfter: retryAfter
        )
    }

    private static func pathComponents(for url: URL) -> [String] {
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
        return path
            .split(separator: "/")
            .map(String.init)
            .map { $0.removingPercentEncoding ?? $0 }
    }

    private static func endpointLabel(from components: [String]) -> String {
        let normalized = components.filter { $0.isEmpty == false }
        guard normalized.isEmpty == false else { return "project" }

        if normalized.first == "repository", normalized.count > 1 {
            return self.humanizeEndpoint(normalized[1])
        }
        if normalized.first == "events" {
            return "activity"
        }
        return self.humanizeEndpoint(normalized[0])
    }

    private static func humanizeEndpoint(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
    }

    private func fetchActivityEvents(for projects: [GitLabProject]) async -> [String: [ActivityEvent]] {
        var out: [String: [ActivityEvent]] = [:]
        for batch in projects.repoPeekBatches(of: Self.activityFetchConcurrencyLimit) {
            let batchResults = await withTaskGroup(of: (String, [ActivityEvent]).self) { group in
                for project in batch {
                    group.addTask { [self] in
                        let events = await (try? self.restAPI.projectEvents(
                            projectPath: project.pathWithNamespace,
                            limit: 25
                        )) ?? []
                        return (project.pathWithNamespace, events)
                    }
                }
                var batchOut: [String: [ActivityEvent]] = [:]
                for await (path, events) in group {
                    batchOut[path] = events
                }
                return batchOut
            }
            out.merge(batchResults) { _, new in new }
        }
        return out
    }
}

private enum AppLimitsFallback {
    static let searchRecentLimit = 8
    static let searchLimit = 30
}
