import Foundation
import RepoPeekCore

private struct MenuHydrationReleaseResult {
    let release: Release?
}

extension AppState {
    func requestRefresh(cancelInFlight: Bool = false) {
        if cancelInFlight {
            self.refreshTask?.cancel()
        }
        guard cancelInFlight || self.refreshTask == nil else { return }

        let token = UUID()
        self.refreshTaskToken = token
        self.refreshTask = Task { [weak self] in
            await self?.refresh()
            await MainActor.run {
                guard let self, self.refreshTaskToken == token else { return }

                self.refreshTask = nil
            }
        }
    }

    func refresh() async {
        self.refreshLocalProjects(cancelInFlight: false)
        self.beginRepositoryRefresh()
        var isRepositoryRefreshActive = true
        defer {
            if isRepositoryRefreshActive {
                self.endRepositoryRefresh()
            }
        }

        do {
            if Task.isCancelled { return }
            let now = Date()
            self.updateHeatmapRange(now: now)
            let hasUsableToken = self.hasAnyStoredPAT()
            if hasUsableToken == false {
                await self.applyLoggedOutState(lastError: nil)
                return
            }
            // If we have tokens but no user in session, fetch identity once per launch.
            if case .loggedOut = self.session.account {
                for account in self.enabledGitLabAccountsWithTokens() {
                    let client = await self.gitLabClient(for: account)
                    if let user = try? await client.currentUser() {
                        await MainActor.run {
                            self.session.accountUsers[account.accountID] = user
                            if self.session.account.isLoggedIn == false {
                                self.session.account = .loggedIn(user)
                            }
                        }
                    }
                }
            }
            let repos = try await self.fetchActivityRepos()
            try Task.checkCancellation()
            await self.updateAccessibleRepositories(repos)
            let visible = self.applyVisibilityFilters(to: repos)
            let ordered = self.applyPinnedOrder(to: visible)
            let needsPreselectionHydration = self.needsHydrationBeforeMenuSelection()
            let selectionSource = needsPreselectionHydration
                ? await self.hydrateMenuTargets(ordered)
                : ordered
            let targets = self.selectMenuTargets(from: selectionSource)
            let hydrated = needsPreselectionHydration
                ? selectionSource
                : await self.hydrateMenuTargets(targets)
            try Task.checkCancellation()
            await self.updateAccessibleRepositories(self.mergeHydrated(hydrated, into: repos))
            let merged = self.mergeHydrated(hydrated, into: ordered)
            let final = self.applyPinnedOrder(to: merged)
            let activityUsername: String? = {
                guard case let .loggedIn(user) = self.session.account,
                      user.username.isEmpty == false else { return nil }

                return user.username
            }()
            let globalActivityTask = Task { [weak self] in
                guard let self, let activityUsername else {
                    return GlobalActivityResult(events: [], commits: [], error: nil, commitError: nil)
                }

                return await self.fetchGlobalActivityEvents(
                    username: activityUsername,
                    scope: self.session.settings.appearance.activityScope,
                    repos: final
                )
            }
            await self.updateSession(with: final, now: now)
            self.endRepositoryRefresh()
            isRepositoryRefreshActive = false
            let globalActivity = await globalActivityTask.value
            await MainActor.run {
                self.session.globalActivityEvents = globalActivity.events
                self.session.globalActivityError = globalActivity.error
                self.session.globalCommitEvents = globalActivity.commits
                self.session.globalCommitError = globalActivity.commitError
                NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
            }
            await self.updateMenuDisplayIndex(now: now)
            await self.refreshRateLimitDisplayState()
            await MainActor.run {
                self.session.lastError = nil
                NotificationCenter.default.post(name: .menuDiagnosticsDidChange, object: nil)
            }
        } catch is CancellationError {
            await MainActor.run {
                NotificationCenter.default.post(name: .menuDiagnosticsDidChange, object: nil)
            }
        } catch {
            if error.isAuthenticationFailure {
                await self.handleAuthenticationFailure(error)
                return
            }
            let diagnostics = await self.gitlab.diagnostics()
            await MainActor.run {
                self.session.rateLimitReset = nil
                self.session.rateLimitDiagnostics = diagnostics
                self.session.rateLimitCacheSummary = nil
                self.session.lastError = error.userFacingMessage
                NotificationCenter.default.post(name: .menuDiagnosticsDidChange, object: nil)
            }
        }
    }

    @discardableResult
    func refreshLocalProjects(cancelInFlight: Bool = true, forceRescan: Bool = false) -> Task<Void, Never>? {
        if cancelInFlight {
            self.localProjectsTask?.cancel()
            self.localProjectsTask = nil
            self.localProjectsTaskToken = UUID()
        } else if let task = self.localProjectsTask {
            return task
        }

        let settings = self.session.settings.localProjects
        guard let rootPath = settings.rootPath,
              rootPath.isEmpty == false
        else {
            self.session.localRepoIndex = .empty
            self.session.localDiscoveredRepoCount = 0
            self.session.localProjectsAccessDenied = false
            self.session.localProjectsScanInProgress = false
            self.localProjectsTask = nil
            return nil
        }

        let token = UUID()
        self.localProjectsTaskToken = token
        self.session.localProjectsScanInProgress = true
        let task = Task { [weak self] in
            guard let self else { return }

            let localSnapshot = await self.snapshotLocalProjects(settings: settings, forceRescan: forceRescan)
            await MainActor.run {
                guard self.localProjectsTaskToken == token else { return }

                self.applyLocalProjectsSnapshot(localSnapshot)
                self.localProjectsTask = nil
            }
        }
        self.localProjectsTask = task
        return task
    }

    func updateHeatmapRange(now: Date = Date()) {
        self.session.heatmapRange = HeatmapFilter.range(
            span: self.session.settings.heatmap.span,
            now: now,
            calendar: HeatmapFilter.gitLabCalendar(),
            alignToWeek: true
        )
    }

    func handleAuthenticationFailure(_ error: Error) async {
        for account in self.session.settings.gitlabAccounts {
            await self.patAuth.logout(account: account, clearHostFallback: true)
        }
        await self.applyLoggedOutState(lastError: error.userFacingMessage)
    }

    private func needsHydrationBeforeMenuSelection() -> Bool {
        let selection = self.session.menuRepoSelection
        return selection.onlyWith.requireMRs || self.session.settings.repoList.menuSortKey == .pulls
    }

    private func hydrateMenuTargets(_ repos: [Repository]) async -> [Repository] {
        guard repos.isEmpty == false else { return [] }

        var hydrated: [Repository] = []
        for batch in repos.chunked(into: self.hydrateConcurrencyLimit) {
            if Task.isCancelled { break }

            let batchRepos = Array(batch)
            let batchHydrated = await withTaskGroup(of: Repository.self) { group in
                for repo in batchRepos {
                    let client = await self.gitLabClient(for: repo)
                    group.addTask {
                        await Self.hydrateMenuTarget(repo, client: client)
                    }
                }

                var results: [Repository] = []
                for await repo in group {
                    results.append(repo)
                }
                return results
            }
            let byKey = Dictionary(batchHydrated.map { ($0.lookupKey, $0) }, uniquingKeysWith: { first, _ in first })
            hydrated.append(contentsOf: batchRepos.map { byKey[$0.lookupKey] ?? $0 })
        }
        return hydrated
    }

    private nonisolated static func hydrateMenuTarget(_ repo: Repository, client: GitLabClient) async -> Repository {
        guard let parts = repositoryParts(from: repo.fullName) else { return repo }

        var hydrated = repo
        var detailState = hydrated.detailCacheState ?? .missing

        if let openMergeRequestCount = try? await client.openMergeRequestCount(owner: parts.owner, name: parts.name) {
            hydrated.openPulls = openMergeRequestCount
            detailState.openPulls = .fresh
        }

        if let pipelines = try? await client.recentPipelines(owner: parts.owner, name: parts.name, limit: 1) {
            hydrated.ciStatus = pipelines.first?.status ?? .unknown
            detailState.ci = .fresh
        }

        if let releaseResult = await Self.latestRelease(owner: parts.owner, name: parts.name, client: client) {
            hydrated.latestRelease = releaseResult.release
            detailState.release = .fresh
        }

        if let events = try? await client.repositoryActivityEvents(
            owner: parts.owner,
            name: parts.name,
            limit: AppLimits.RepoActivity.heatmapFetchLimit
        ) {
            hydrated.activityEvents = events
            hydrated.latestActivity = events.first ?? hydrated.latestActivity
            hydrated.heatmap = RepositoryHydration.heatmap(from: events)
            detailState.activity = .fresh
            detailState.heatmap = .fresh
        }

        hydrated.detailCacheState = detailState
        return hydrated
    }

    private nonisolated static func repositoryParts(from fullName: String) -> (owner: String, name: String)? {
        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].isEmpty == false, parts[1].isEmpty == false else { return nil }

        return (parts[0], parts[1])
    }

    private nonisolated static func latestRelease(
        owner: String,
        name: String,
        client: GitLabClient
    ) async -> MenuHydrationReleaseResult? {
        do {
            let release = try await client.latestRelease(owner: owner, name: name)
            return MenuHydrationReleaseResult(release: release)
        } catch {
            return nil
        }
    }

    private func snapshotLocalProjects(
        settings: LocalProjectsSettings,
        forceRescan: Bool
    ) async -> LocalRepoManager.SnapshotResult {
        let matchSource = self.localProjectMatchSourceRepositories()
        let matchNames = self.localMatchRepoNamesForLocalProjects(
            repos: matchSource,
            includePinned: matchSource.isEmpty == false
        )
        return await self.localRepoManager.snapshot(
            rootPath: settings.rootPath,
            rootBookmarkData: settings.rootBookmarkData,
            options: LocalRepoManager.SnapshotOptions(
                autoSyncEnabled: settings.autoSyncEnabled,
                fetchInterval: settings.fetchInterval.seconds,
                preferredPathsByFullName: settings.preferredLocalPathsByFullName,
                matchRepoNames: matchNames,
                forceRescan: forceRescan,
                maxDepth: settings.maxDepth
            )
        )
    }

    private func localProjectMatchSourceRepositories() -> [Repository] {
        self.session.repositories.isEmpty
            ? (self.session.menuSnapshot?.repositories ?? [])
            : self.session.repositories
    }

    private func applyLocalProjectsSnapshot(_ localSnapshot: LocalRepoManager.SnapshotResult) {
        self.session.localRepoIndex = localSnapshot.repoIndex
        self.session.localDiscoveredRepoCount = localSnapshot.discoveredCount
        self.session.localProjectsAccessDenied = localSnapshot.accessDenied
        self.session.localProjectsScanInProgress = false
        self.session.menuDisplayIndex = self.menuDisplayIndex(for: self.session.repositories, now: Date())
        NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
    }

    private func applyLoggedOutState(lastError: String?) async {
        await MainActor.run {
            self.menuSnapshotStore.clear()
            self.session.account = .loggedOut
            self.session.hasStoredTokens = false
            self.session.accessibleRepositories = []
            self.session.repositories = []
            self.session.menuSnapshot = nil
            self.session.menuDisplayIndex = [:]
            self.session.hasLoadedRepositories = false
            self.session.lastError = lastError
            self.session.globalActivityEvents = []
            self.session.globalActivityError = nil
            self.session.globalCommitEvents = []
            self.session.globalCommitError = nil
            // Auto-select local filter when logged out.
            if self.session.menuRepoSelection != .local {
                self.session.menuRepoSelection = .local
            }
        }
    }

    private func mergeHydrated(_ detailed: [Repository], into repos: [Repository]) -> [Repository] {
        RepositoryHydration.merge(detailed, into: repos)
    }

    private func updateSession(with repos: [Repository], now: Date) async {
        let index = self.menuDisplayIndex(for: repos, now: now)
        await MainActor.run {
            let snapshot = MenuSnapshot(repositories: repos, capturedAt: now)
            self.session.repositories = repos
            self.session.menuSnapshot = snapshot
            self.session.menuDisplayIndex = index
            self.session.hasLoadedRepositories = true
            self.session.rateLimitReset = nil
            self.session.lastError = nil
            self.menuSnapshotStore.save(snapshot)
            NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
        }
    }

    private func updateAccessibleRepositories(_ repos: [Repository]) async {
        let uniqueRepos = RepositoryUniquing.byFullName(repos)
        await MainActor.run {
            self.session.accessibleRepositories = uniqueRepos
        }
    }

    private func updateMenuDisplayIndex(now: Date) async {
        let repos = self.session.repositories
        let index = self.menuDisplayIndex(for: repos, now: now)
        await MainActor.run {
            self.session.menuDisplayIndex = index
            NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
        }
    }

    private func menuDisplayIndex(for repos: [Repository], now: Date) -> [String: RepositoryDisplayModel] {
        let localIndex = self.session.localRepoIndex
        let models = repos.map { repo in
            RepositoryDisplayModel(repo: repo, localStatus: localIndex.status(for: repo), now: now)
        }
        var index: [String: RepositoryDisplayModel] = [:]
        for model in models {
            index[model.id.lowercased()] = model
            index[model.source.lookupKey] = model
            if index[model.title.lowercased()] == nil {
                index[model.title.lowercased()] = model
            }
        }
        return index
    }

    func restorePersistedMenuSnapshot(now: Date = Date()) {
        guard let snapshot = self.menuSnapshotStore.load() else { return }

        self.session.repositories = snapshot.repositories
        self.session.menuSnapshot = snapshot
        self.session.accessibleRepositories = snapshot.repositories
        self.session.menuDisplayIndex = self.menuDisplayIndex(for: snapshot.repositories, now: now)
        self.session.hasLoadedRepositories = true
        NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
    }

    func restoreCachedAccountStateIfPossible() {
        guard self.session.account.isLoggedIn == false,
              let account = self.primaryGitLabAccount(),
              let username = account.username?.trimmingCharacters(in: .whitespacesAndNewlines),
              username.isEmpty == false,
              self.patAuth.loadPAT(account: account) != nil
        else { return }

        let user = UserIdentity(username: username, host: account.host)
        self.session.account = .loggedIn(user)
        self.session.accountUsers[account.accountID] = user
    }

    private func beginRepositoryRefresh() {
        self.activeRepositoryRefreshCount += 1
        self.updateRepositoryRefreshInProgress()
    }

    private func endRepositoryRefresh() {
        self.activeRepositoryRefreshCount = max(0, self.activeRepositoryRefreshCount - 1)
        self.updateRepositoryRefreshInProgress()
    }

    private func updateRepositoryRefreshInProgress() {
        let isInProgress = self.activeRepositoryRefreshCount > 0
        guard self.session.isRefreshingRepositories != isInProgress else { return }

        self.session.isRefreshingRepositories = isInProgress
        NotificationCenter.default.post(name: .menuDiagnosticsDidChange, object: nil)
    }
}
