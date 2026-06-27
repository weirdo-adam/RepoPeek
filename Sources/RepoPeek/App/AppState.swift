import Algorithms
import Foundation
import Observation
import RepoPeekCore

// MARK: - AppState container

@MainActor
@Observable
final class AppState {
    var session = Session()
    let patAuth = PATAuthenticator()
    let gitlab: GitLabClient
    let gitLabClientRegistry: GitLabClientRegistry
    let refreshScheduler = RefreshScheduler()
    let settingsStore = SettingsStore()
    let menuSnapshotStore = MenuSnapshotStore()
    let globalActivityCacheStore = GlobalActivityCacheStore()
    let localRepoManager = LocalRepoManager()
    var refreshTask: Task<Void, Never>?
    var localProjectsTask: Task<Void, Never>?
    var localProjectsTaskToken = UUID()
    private var gitLabReferenceMonitor: GitLabReferenceMonitor?
    private var gitLabReferenceResolutionID = UUID()
    var refreshTaskToken = UUID()
    let hydrateConcurrencyLimit = 4
    var activeRepositoryRefreshCount = 0

    init() {
        let primaryGitLab = GitLabClient()
        self.gitlab = primaryGitLab
        self.gitLabClientRegistry = GitLabClientRegistry(primaryClient: primaryGitLab)
        self.session.settings = self.settingsStore.load()
        if self.session.settings.gitlabHost.host?.lowercased() == "gitlab.com" {
            self.session.settings.gitlabHost = RepoPeekAuthDefaults.gitlabHost
            self.session.settings.enterpriseHost = nil
            self.session.settings.authMethod = .pat
            self.settingsStore.save(self.session.settings)
        }
        if self.session.settings.authMethod != .pat {
            self.session.settings.authMethod = .pat
            self.settingsStore.save(self.session.settings)
        }
        self.reloadRateLimitCacheSummary()
        RepoPeekLogging.bootstrapIfNeeded()
        RepoPeekLogging.configure(
            verbosity: self.session.settings.loggingVerbosity,
            fileLoggingEnabled: self.session.settings.fileLoggingEnabled
        )
        let storedPAT = self.hasAnyStoredPAT()
        self.session.hasStoredTokens = storedPAT
        if storedPAT {
            self.restoreCachedAccountStateIfPossible()
            self.restorePersistedMenuSnapshot()
        } else {
            self.menuSnapshotStore.clear()
        }
        Task { [weak self] in
            guard let self else { return }

            for account in await MainActor.run(body: { self.enabledGitLabAccounts() }) {
                _ = await self.gitLabClient(for: account)
            }
        }
        let shouldRefreshOnStart = self.shouldRefreshOnStart(hasStoredPAT: storedPAT)
        self.refreshScheduler.configure(
            interval: self.session.settings.refreshInterval.seconds,
            fireImmediately: shouldRefreshOnStart
        ) { [weak self] in
            self?.requestRefresh()
        }
        if shouldRefreshOnStart == false {
            self.refreshLocalProjectsOnStartIfNeeded()
        }
        Task { await DiagnosticsLogger.shared.setEnabled(self.session.settings.diagnosticsEnabled) }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await self?.refreshRateLimitDisplayState()
        }
        self.updateGitLabReferenceMonitor()
    }

    struct GlobalActivityResult {
        let events: [ActivityEvent]
        let commits: [RepoCommitSummary]
        let error: String?
        let commitError: String?
    }

    func diagnostics() async -> DiagnosticsSummary {
        await self.refreshRateLimitDisplayState()
        return self.session.rateLimitDiagnostics
    }

    func refreshRateLimitDisplayState() async {
        let diagnostics = await self.gitlab.diagnostics()
        self.session.rateLimitReset = nil
        self.session.rateLimitDiagnostics = diagnostics
        self.session.rateLimitCacheSummary = nil
        NotificationCenter.default.post(name: .menuDiagnosticsDidChange, object: nil)
    }

    func reloadRateLimitCacheSummary(limit: Int = 100) {
        self.session.rateLimitCacheSummary = try? RepoPeekPersistentCache.summary(limit: limit)
    }

    func clearCaches() async {
        ContributionCacheStore.clear()
        self.globalActivityCacheStore.clear()
        self.menuSnapshotStore.clear()
    }

    func persistSettings() {
        self.settingsStore.save(self.session.settings)
    }

    private func shouldRefreshOnStart(hasStoredPAT: Bool, now: Date = Date()) -> Bool {
        if hasStoredPAT == false {
            return self.session.settings.localProjects.rootPath?.isEmpty == false
        }
        return self.session.menuSnapshot.map {
            $0.isStale(now: now, interval: self.session.settings.refreshInterval.seconds)
        } ?? true
    }

    private func refreshLocalProjectsOnStartIfNeeded() {
        guard self.session.settings.localProjects.rootPath?.isEmpty == false else { return }

        self.refreshLocalProjects(cancelInFlight: false)
    }

    func updateGitLabReferenceMonitor() {
        guard self.session.settings.gitLabReferenceMonitor.enabled else {
            Task { await DiagnosticsLogger.shared.message("GitLab reference monitor disabled") }
            self.gitLabReferenceMonitor?.stop()
            self.gitLabReferenceMonitor = nil
            self.setGitLabReferenceMatch(nil)
            return
        }

        if self.gitLabReferenceMonitor == nil {
            Task { await DiagnosticsLogger.shared.message("GitLab reference monitor created") }
            self.gitLabReferenceMonitor = GitLabReferenceMonitor(
                onPasteboardWithoutReference: { [weak self] in
                    await self?.clearGitLabReference()
                },
                onReferences: { [weak self] queries, text in
                    await self?.resolveGitLabReferences(queries, sourceText: text)
                }
            )
        }
        Task { await DiagnosticsLogger.shared.message("GitLab reference monitor started mode=clipboard-only") }
        self.gitLabReferenceMonitor?.start()
    }

    private func clearGitLabReference() async {
        guard self.session.settings.gitLabReferenceMonitor.enabled else { return }

        self.gitLabReferenceResolutionID = UUID()
        self.setGitLabReferenceMatches([])
    }

    private func resolveGitLabReferences(_ queries: [GitLabReferenceQuery], sourceText: String) async {
        guard self.session.settings.gitLabReferenceMonitor.enabled else { return }

        let resolutionID = UUID()
        self.gitLabReferenceResolutionID = resolutionID
        let scopedQueries = await self.queries(queries, applyingLocalRepositoryContextFrom: sourceText)
        guard self.gitLabReferenceResolutionID == resolutionID else { return }

        let matches = await self.referenceMatches(for: scopedQueries, resolutionID: resolutionID) { matches in
            self.setGitLabReferenceMatches(matches)
        }
        guard self.gitLabReferenceResolutionID == resolutionID else { return }

        self.setGitLabReferenceMatches(matches)
    }

    func resolveGitLabReferenceQueries(_ queries: [GitLabReferenceQuery], sourceText: String) async -> [GitLabReferenceMatch] {
        let scopedQueries = await self.queries(queries, applyingLocalRepositoryContextFrom: sourceText)
        return await self.referenceMatches(for: scopedQueries, resolutionID: nil)
    }

    func searchIssueReferences(
        matching text: String,
        repositoryFullName: String?,
        includeIssues: Bool,
        includePullRequests: Bool,
        limit: Int = AppLimits.IssueNavigator.searchLimit
    ) async throws -> [GitLabReferenceMatch] {
        if let repositoryFullName {
            let client = await self.gitLabClient(forRepositoryFullName: repositoryFullName)
            return try await Self.gitLabSearchIssueReferences(
                gitlab: client,
                text: text,
                repositoryFullName: repositoryFullName,
                options: GitLabReferenceLookupOptions(
                    includeIssues: includeIssues,
                    includePullRequests: includePullRequests,
                    limit: limit
                )
            )
        }

        let repositories = Self.issueNavigatorSearchRepositories(from: self.gitlabReferenceCandidateRepositories())
        guard repositories.isEmpty == false else {
            if self.session.hasLoadedRepositories {
                return []
            }

            throw IssueNavigatorSearchError.repositoryInventoryLoading
        }

        let searchOptions = GitLabReferenceLookupOptions(
            includeIssues: includeIssues,
            includePullRequests: includePullRequests,
            limit: AppLimits.IssueNavigator.perRepositorySearchLimit
        )
        var matches: [GitLabReferenceMatch] = []
        var firstError: Error?
        var failedSearches = 0

        for chunk in repositories.chunks(ofCount: AppLimits.IssueNavigator.repositorySearchConcurrencyLimit) {
            await withTaskGroup(of: Result<[GitLabReferenceMatch], Error>.self) { group in
                for repo in chunk {
                    let client = await self.gitLabClient(for: repo)
                    group.addTask {
                        do {
                            let matches = try await Self.gitLabSearchIssueReferences(
                                gitlab: client,
                                text: text,
                                repositoryFullName: repo.fullName,
                                options: searchOptions
                            )
                            return .success(matches)
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                for await result in group {
                    switch result {
                    case let .success(found):
                        matches.append(contentsOf: found)
                    case let .failure(error):
                        failedSearches += 1
                        firstError = firstError ?? error
                    }
                }
            }
        }

        if Self.shouldSurfaceIssueSearchFailure(
            searchedRepositories: repositories.count,
            failedSearches: failedSearches,
            matchCount: matches.count
        ), let firstError {
            throw firstError
        }

        return Array(Self.dedupedGitLabReferenceMatches(matches).prefix(limit))
    }

    static func shouldSurfaceIssueSearchFailure(
        searchedRepositories: Int,
        failedSearches: Int,
        matchCount: Int
    ) -> Bool {
        matchCount == 0 && searchedRepositories > 0 && failedSearches >= searchedRepositories
    }

    static func issueNavigatorSearchRepositories(from repositories: [Repository]) -> [Repository] {
        let sorted = repositories
            .filter { $0.viewerCanRead && !$0.isArchived }
            .sorted {
                let lhsDate = $0.latestActivity?.date ?? $0.pushedAt ?? .distantPast
                let rhsDate = $1.latestActivity?.date ?? $1.pushedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }

        return Array(sorted.prefix(AppLimits.IssueNavigator.maxRepositorySearchFanout))
    }

    func recentIssueReferences(
        repositoryFullName: String?,
        includeIssues: Bool,
        includePullRequests: Bool,
        limit: Int = AppLimits.IssueNavigator.searchLimit
    ) async throws -> [GitLabReferenceMatch] {
        if let repositoryFullName {
            let matches = try await self.recentRepositoryIssueReferences(
                repositoryFullName: repositoryFullName,
                includeIssues: includeIssues,
                includePullRequests: includePullRequests,
                limit: limit
            )
            return Array(Self.dedupedGitLabReferenceMatches(matches).prefix(limit))
        }

        let matches = await self.recentAccessibleRepositoryIssueReferences(
            includeIssues: includeIssues,
            includePullRequests: includePullRequests
        )
        return Array(Self.dedupedGitLabReferenceMatches(matches).prefix(limit))
    }

    func gitLabReferenceRepositories() -> [Repository] {
        self.gitlabReferenceCandidateRepositories()
    }

    func openAIAPIKeySource() -> OpenAIAPIKeySource {
        OpenAIAPIKeyStore().resolve().source
    }

    func saveOpenAIAPIKey(_ key: String) throws {
        try TokenStore.shared.saveOpenAIAPIKey(key)
    }

    func clearOpenAIAPIKey() {
        TokenStore.shared.clearOpenAIAPIKey()
    }

    func summarizeIssueNavigatorMatches(_ matches: [GitLabReferenceMatch]) async throws -> [GitLabReferenceMatch] {
        try await PullRequestAISummarizer().summarizeMergeRequests(
            in: matches,
            settings: self.session.settings.aiSummaries
        )
    }

    nonisolated static func dedupedGitLabReferenceMatches(_ matches: [GitLabReferenceMatch]) -> [GitLabReferenceMatch] {
        var seen: Set<URL> = []
        return matches
            .filter { seen.insert($0.url).inserted }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
    }

    static func issueNavigatorRecentRepositories(
        from repositories: [Repository],
        includeIssues: Bool,
        includePullRequests: Bool
    ) -> [Repository] {
        let sorted = repositories
            .filter { repo in
                guard repo.viewerCanRead, !repo.isArchived else { return false }

                return (includeIssues && repo.openIssues > 0) || (includePullRequests && repo.openPulls > 0)
            }
            .sorted {
                let lhs = $0.latestActivity?.date ?? $0.pushedAt ?? .distantPast
                let rhs = $1.latestActivity?.date ?? $1.pushedAt ?? .distantPast
                if lhs != rhs { return lhs > rhs }
                return $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }

        return Array(sorted.prefix(AppLimits.IssueNavigator.recentRepositoryLimit))
    }

    private func recentAccessibleRepositoryIssueReferences(
        includeIssues: Bool,
        includePullRequests: Bool
    ) async -> [GitLabReferenceMatch] {
        let repositories = Self.issueNavigatorRecentRepositories(
            from: self.gitlabReferenceCandidateRepositories(),
            includeIssues: includeIssues,
            includePullRequests: includePullRequests
        )

        var matches: [GitLabReferenceMatch] = []
        let recentOptions = GitLabReferenceLookupOptions(
            includeIssues: includeIssues,
            includePullRequests: includePullRequests,
            limit: AppLimits.IssueNavigator.perRepositoryRecentLimit
        )

        for chunk in repositories.chunks(ofCount: AppLimits.IssueNavigator.repositorySearchConcurrencyLimit) {
            await withTaskGroup(of: [GitLabReferenceMatch].self) { group in
                for repo in chunk {
                    let client = await self.gitLabClient(for: repo)
                    group.addTask {
                        do {
                            return try await Self.recentGitLabRepositoryIssueReferences(
                                gitlab: client,
                                repositoryFullName: repo.fullName,
                                options: recentOptions
                            )
                        } catch {
                            return []
                        }
                    }
                }

                for await found in group {
                    matches.append(contentsOf: found)
                }
            }
        }

        return matches
    }

    private func recentRepositoryIssueReferences(
        repositoryFullName: String,
        includeIssues: Bool,
        includePullRequests: Bool,
        limit: Int
    ) async throws -> [GitLabReferenceMatch] {
        let client = await self.gitLabClient(forRepositoryFullName: repositoryFullName)
        return try await Self.recentGitLabRepositoryIssueReferences(
            gitlab: client,
            repositoryFullName: repositoryFullName,
            options: GitLabReferenceLookupOptions(
                includeIssues: includeIssues,
                includePullRequests: includePullRequests,
                limit: limit
            )
        )
    }

    private nonisolated static func recentGitLabRepositoryIssueReferences(
        gitlab: GitLabClient,
        repositoryFullName: String,
        options: GitLabReferenceLookupOptions
    ) async throws -> [GitLabReferenceMatch] {
        guard let parts = repositoryParts(from: repositoryFullName) else { return [] }

        async let issuesItems: [RepoIssueSummary] = options.includeIssues
            ? gitlab.recentIssues(owner: parts.owner, name: parts.name, limit: options.limit)
            : []
        async let pullsItems: [RepoPullRequestSummary] = options.includePullRequests
            ? gitlab.recentMergeRequests(owner: parts.owner, name: parts.name, limit: options.limit)
            : []

        let (issues, pulls) = try await (issuesItems, pullsItems)
        return Self.gitLabReferenceMatches(
            repositoryFullName: repositoryFullName,
            issues: issues,
            mergeRequests: pulls
        )
    }

    private nonisolated static func gitLabSearchIssueReferences(
        gitlab: GitLabClient,
        text: String,
        repositoryFullName: String,
        options: GitLabReferenceLookupOptions
    ) async throws -> [GitLabReferenceMatch] {
        guard let parts = repositoryParts(from: repositoryFullName) else { return [] }

        async let issuesItems: [RepoIssueSummary] = options.includeIssues
            ? gitlab.searchIssues(owner: parts.owner, name: parts.name, query: text, limit: options.limit)
            : []
        async let pullsItems: [RepoPullRequestSummary] = options.includePullRequests
            ? gitlab.searchMergeRequests(owner: parts.owner, name: parts.name, query: text, limit: options.limit)
            : []

        let (issues, pulls) = try await (issuesItems, pullsItems)
        return Self.gitLabReferenceMatches(
            repositoryFullName: repositoryFullName,
            issues: issues,
            mergeRequests: pulls
        )
    }

    private nonisolated static func gitLabReferenceMatches(
        repositoryFullName: String,
        issues: [RepoIssueSummary],
        mergeRequests: [RepoPullRequestSummary]
    ) -> [GitLabReferenceMatch] {
        var matches: [GitLabReferenceMatch] = []
        matches.append(contentsOf: issues.map {
            GitLabReferenceMatch(
                query: .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: $0.number),
                title: $0.title,
                url: $0.url,
                repositoryFullName: repositoryFullName,
                kind: .issue,
                state: .open,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                authorLogin: $0.authorLogin
            )
        })
        matches.append(contentsOf: mergeRequests.map {
            GitLabReferenceMatch(
                query: .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: $0.number),
                title: $0.title,
                url: $0.url,
                repositoryFullName: repositoryFullName,
                kind: .pullRequest,
                state: .open,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                authorLogin: $0.authorLogin
            )
        })
        return Self.dedupedGitLabReferenceMatches(matches)
    }

    private nonisolated static func repositoryParts(from fullName: String) -> (owner: String, name: String)? {
        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].isEmpty == false, parts[1].isEmpty == false else { return nil }

        return (parts[0], parts[1])
    }

    private func referenceMatches(
        for queries: [GitLabReferenceQuery],
        resolutionID: UUID?,
        onProgress: (([GitLabReferenceMatch]) -> Void)? = nil
    ) async -> [GitLabReferenceMatch] {
        let limitedQueries = Array(queries.prefix(AppLimits.GitLabReferenceMonitor.queryLimit))
        let candidates = await self.gitlabReferenceCandidates()
        var matchesByIndex: [Int: GitLabReferenceMatch] = [:]
        var seen: Set<URL> = []

        let indexedQueries = Array(limitedQueries.enumerated())
        for chunk in indexedQueries.chunks(ofCount: AppLimits.GitLabReferenceMonitor.resolutionConcurrencyLimit) {
            await withTaskGroup(of: (Int, GitLabReferenceMatch?).self) { group in
                for (index, query) in chunk {
                    group.addTask {
                        let match = await Self.resolveGitLabReferenceMatch(
                            query: query,
                            candidates: candidates
                        )
                        return (index, match)
                    }
                }

                for await (index, match) in group {
                    if let resolutionID, self.gitLabReferenceResolutionID != resolutionID {
                        group.cancelAll()
                        return
                    }
                    guard let match, seen.insert(match.url).inserted else { continue }

                    matchesByIndex[index] = match
                    let orderedMatches = matchesByIndex.keys.sorted().compactMap { matchesByIndex[$0] }
                    onProgress?(orderedMatches)
                }
            }

            if let resolutionID, self.gitLabReferenceResolutionID != resolutionID {
                return []
            }
        }

        return matchesByIndex.keys.sorted().compactMap { matchesByIndex[$0] }
    }

    private func queries(
        _ queries: [GitLabReferenceQuery],
        applyingLocalRepositoryContextFrom text: String
    ) async -> [GitLabReferenceQuery] {
        guard queries.contains(where: { $0.repositoryFullName == nil }) else { return queries }

        let repositoryFullName = await GitLabReferenceLocalContext.repositoryFullName(
            in: text,
            localRepoIndex: self.session.localRepoIndex
        )
        guard let repositoryFullName else {
            return await GitLabReferenceLocalContext.queries(
                queries,
                applyingLocalRepositoryContextFrom: self.session.localRepoIndex
            )
        }

        return GitLabReferenceTranslator.queries(
            from: text,
            minimumBareDigits: AppLimits.GitLabReferenceMonitor.minimumBareDigits,
            repositoryContextOverride: repositoryFullName
        )
    }

    private nonisolated static func resolveGitLabReferenceMatch(
        query: GitLabReferenceQuery,
        candidates: [GitLabReferenceCandidate]
    ) async -> GitLabReferenceMatch? {
        let matchingCandidates = if let repositoryFullName = query.repositoryFullName {
            candidates.filter { $0.repository.fullName.caseInsensitiveCompare(repositoryFullName) == .orderedSame }
        } else if let repositoryName = query.repositoryName {
            candidates.filter { $0.repository.name.caseInsensitiveCompare(repositoryName) == .orderedSame }
        } else {
            candidates
        }
        guard matchingCandidates.isEmpty == false else { return nil }

        for candidate in matchingCandidates.prefix(AppLimits.GitLabReferenceMonitor.liveLookupLimit) {
            let repo = candidate.repository
            let gitlab = candidate.gitlab
            guard let parts = repositoryParts(from: repo.fullName) else { continue }

            switch query {
            case let .issueNumber(number),
                 let .repositoryNameIssueNumber(_, number),
                 let .repositoryIssueNumber(_, number):
                async let issue = gitlab.issue(owner: parts.owner, name: parts.name, iid: number)
                async let mergeRequest = gitlab.mergeRequest(owner: parts.owner, name: parts.name, iid: number)
                if let found = try? await issue {
                    return Self.gitLabReferenceMatch(repositoryFullName: repo.fullName, issue: found)
                }
                if let found = try? await mergeRequest {
                    return Self.gitLabReferenceMatch(repositoryFullName: repo.fullName, mergeRequest: found)
                }
            case let .commitHash(hash),
                 let .repositoryCommitHash(_, hash):
                if let commit = try? await gitlab.commit(owner: parts.owner, name: parts.name, sha: hash) {
                    return GitLabReferenceMatch(
                        query: .repositoryCommitHash(repositoryFullName: repo.fullName, hash: commit.sha),
                        title: commit.message,
                        url: commit.url,
                        repositoryFullName: repo.fullName,
                        kind: .commit,
                        state: nil,
                        createdAt: commit.authoredAt,
                        updatedAt: commit.authoredAt,
                        authorLogin: commit.authorLogin ?? commit.authorName
                    )
                }
            case .repositoryWorkflowRun:
                continue
            }
        }

        return nil
    }

    private func gitlabReferenceCandidates() async -> [GitLabReferenceCandidate] {
        let repositories = self.gitlabReferenceCandidateRepositories()
        var candidates: [GitLabReferenceCandidate] = []
        for repository in repositories {
            let client = await self.gitLabClient(for: repository)
            candidates.append(GitLabReferenceCandidate(repository: repository, gitlab: client))
        }
        return candidates
    }

    private nonisolated static func gitLabReferenceMatch(
        repositoryFullName: String,
        issue: RepoIssueSummary
    ) -> GitLabReferenceMatch {
        GitLabReferenceMatch(
            query: .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: issue.number),
            title: issue.title,
            url: issue.url,
            repositoryFullName: repositoryFullName,
            kind: .issue,
            state: .open,
            createdAt: issue.createdAt,
            updatedAt: issue.updatedAt,
            authorLogin: issue.authorLogin
        )
    }

    private nonisolated static func gitLabReferenceMatch(
        repositoryFullName: String,
        mergeRequest: RepoPullRequestSummary
    ) -> GitLabReferenceMatch {
        let state: GitLabReferenceState = if mergeRequest.mergedAt != nil {
            .merged
        } else if mergeRequest.state == .closed {
            .closed
        } else {
            .open
        }
        return GitLabReferenceMatch(
            query: .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: mergeRequest.number),
            title: mergeRequest.title,
            url: mergeRequest.url,
            repositoryFullName: repositoryFullName,
            kind: .pullRequest,
            state: state,
            createdAt: mergeRequest.createdAt,
            updatedAt: mergeRequest.updatedAt,
            authorLogin: mergeRequest.authorLogin
        )
    }

    private func gitlabReferenceCandidateRepositories() -> [Repository] {
        let sources = [
            self.session.accessibleRepositories,
            self.session.repositories,
            self.session.menuSnapshot?.repositories ?? []
        ]
        let repositories = sources.first(where: { $0.isEmpty == false }) ?? []
        var seen: Set<String> = []
        return repositories.filter { repo in
            guard repo.viewerCanRead else { return false }

            return seen.insert(repo.lookupKey).inserted
        }
    }

    private func setGitLabReferenceMatch(_ match: GitLabReferenceMatch?) {
        self.setGitLabReferenceMatches(match.map { [$0] } ?? [])
    }

    private func setGitLabReferenceMatches(_ matches: [GitLabReferenceMatch]) {
        let primaryMatch = GitLabReferenceMatch.newestCreated(in: matches)
        guard self.session.gitLabReferenceMatches != matches || self.session.gitLabReferenceMatch != primaryMatch else { return }

        self.session.gitLabReferenceMatches = matches
        self.session.gitLabReferenceMatch = primaryMatch
        NotificationCenter.default.post(name: .gitLabReferenceMatchDidChange, object: nil)
    }
}

private struct GitLabReferenceLookupOptions {
    let includeIssues: Bool
    let includePullRequests: Bool
    let limit: Int
}

private struct GitLabReferenceCandidate {
    let repository: Repository
    let gitlab: GitLabClient
}

private enum IssueNavigatorSearchError: LocalizedError {
    case repositoryInventoryLoading

    var errorDescription: String? {
        switch self {
        case .repositoryInventoryLoading:
            "Repository list is still loading. Try again in a moment."
        }
    }
}
