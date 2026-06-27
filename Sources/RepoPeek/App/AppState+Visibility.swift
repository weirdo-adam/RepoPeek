import Foundation
import RepoPeekCore

extension AppState {
    func localMatchRepoNamesForLocalProjects(repos: [Repository], includePinned: Bool) -> Set<String> {
        var names = Set(repos.map(\.name))
        guard includePinned else { return names }

        let pinned = self.session.settings.repoList.allPinnedRepositories
        for fullName in pinned {
            if let last = fullName.split(separator: "/").last {
                names.insert(String(last))
            }
        }
        return names
    }

    func applyVisibilityFilters(to repos: [Repository]) -> [Repository] {
        let options = AppState.VisibleSelectionOptions(
            pinned: self.session.settings.repoList.pinnedRepositories,
            hidden: Set(self.session.settings.repoList.hiddenRepositories),
            hiddenGroups: self.session.settings.repoList.hiddenGroups,
            accountScopedRepositoryLists: self.session.settings.repoList.accountScopedRepositoryLists,
            includeForks: self.session.settings.repoList.showForks,
            includeArchived: self.session.settings.repoList.showArchived,
            limit: Int.max,
            ownerFilter: self.session.settings.repoList.ownerFilter
        )
        return AppState.selectVisible(all: repos, options: options)
    }

    func selectMenuTargets(from repos: [Repository]) -> [Repository] {
        RepositoryPipeline.apply(repos, query: self.menuQuery())
    }

    private func menuQuery() -> RepositoryQuery {
        let selection = self.session.menuRepoSelection
        let settings = self.session.settings
        let scope: RepositoryScope = selection.isPinnedScope ? .pinned : .all
        let ageCutoff = RepositoryQueryDefaults.ageCutoff(
            scope: scope,
            ageDays: RepositoryQueryDefaults.defaultAgeDays
        )
        return RepositoryQuery(
            scope: scope,
            onlyWith: selection.onlyWith,
            includeForks: settings.repoList.showForks,
            includeArchived: settings.repoList.showArchived,
            sortKey: settings.repoList.menuSortKey,
            limit: settings.repoList.displayLimit,
            ageCutoff: ageCutoff,
            pinned: settings.repoList.pinnedRepositories,
            hidden: Set(settings.repoList.hiddenRepositories),
            hiddenGroups: settings.repoList.hiddenGroups,
            accountScopedRepositoryLists: settings.repoList.accountScopedRepositoryLists,
            pinPriority: true,
            ownerFilter: settings.repoList.ownerFilter
        )
    }

    func applyPinnedOrder(to repos: [Repository]) -> [Repository] {
        let repoList = self.session.settings.repoList
        return repos.map { repo in
            let pinned = repoList.pinnedRepositories(forAccountID: repo.identity?.accountID)
            if let idx = self.index(of: repo.fullName, in: pinned) {
                return repo.withOrder(idx)
            }
            return repo
        }
    }

    func addPinned(_ fullName: String, accountID: String? = nil) async {
        guard self.session.settings.repoList.pinRepository(fullName, forAccountID: accountID) else { return }

        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    func removePinned(_ fullName: String, accountID: String? = nil) async {
        let normalized = self.normalizedFullName(fullName)
        var pinned = self.session.settings.repoList.pinnedRepositories(forAccountID: accountID)
        pinned.removeAll { self.normalizedFullName($0) == normalized }
        self.session.settings.repoList.setPinnedRepositories(pinned, forAccountID: accountID)
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    func hide(_ fullName: String, accountID: String? = nil) async {
        let normalized = self.normalizedFullName(fullName)
        var hidden = self.session.settings.repoList.hiddenRepositories(forAccountID: accountID)
        guard !hidden.contains(where: { self.normalizedFullName($0) == normalized }) else { return }

        hidden.append(fullName)
        self.session.settings.repoList.setHiddenRepositories(hidden, forAccountID: accountID)
        // If hidden, also unpin to avoid stale pin list.
        var pinned = self.session.settings.repoList.pinnedRepositories(forAccountID: accountID)
        pinned.removeAll { self.normalizedFullName($0) == normalized }
        self.session.settings.repoList.setPinnedRepositories(pinned, forAccountID: accountID)
        self.settingsStore.save(self.session.settings)
        self.session.repositories.removeAll {
            self.repo($0, matchesFullName: normalized, accountID: accountID)
        }
        await self.refresh()
    }

    func hideGroup(_ groupPath: String, accountID: String? = nil) async {
        let normalized = RepositoryVisibilityRules.normalizeGroupPath(groupPath)
        guard !normalized.isEmpty else { return }

        var hiddenGroups = self.session.settings.repoList.hiddenGroups(forAccountID: accountID)
        hiddenGroups.removeAll {
            RepositoryVisibilityRules.normalizeGroupPath($0) == normalized
        }
        hiddenGroups.append(normalized)
        self.session.settings.repoList.setHiddenGroups(hiddenGroups, forAccountID: accountID)

        var pinned = self.session.settings.repoList.pinnedRepositories(forAccountID: accountID)
        pinned.removeAll {
            RepositoryVisibilityRules.hiddenGroup(for: $0, hiddenGroups: [normalized]) != nil
        }
        self.session.settings.repoList.setPinnedRepositories(pinned, forAccountID: accountID)

        var hidden = self.session.settings.repoList.hiddenRepositories(forAccountID: accountID)
        hidden.removeAll {
            RepositoryVisibilityRules.hiddenGroup(for: $0, hiddenGroups: [normalized]) != nil
        }
        self.session.settings.repoList.setHiddenRepositories(hidden, forAccountID: accountID)
        self.settingsStore.save(self.session.settings)
        self.session.repositories.removeAll {
            RepositoryVisibilityRules.hiddenGroup(for: $0.fullName, hiddenGroups: [normalized]) != nil
                && self.repo($0, matchesAccountID: accountID)
        }
        await self.refresh()
    }

    func removeHiddenGroup(_ groupPath: String, accountID: String? = nil) async {
        let normalized = RepositoryVisibilityRules.normalizeGroupPath(groupPath)
        guard !normalized.isEmpty else { return }

        var hiddenGroups = self.session.settings.repoList.hiddenGroups(forAccountID: accountID)
        hiddenGroups.removeAll {
            RepositoryVisibilityRules.normalizeGroupPath($0) == normalized
        }
        self.session.settings.repoList.setHiddenGroups(hiddenGroups, forAccountID: accountID)
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    func unhide(_ fullName: String, accountID: String? = nil) async {
        let normalized = self.normalizedFullName(fullName)
        var hidden = self.session.settings.repoList.hiddenRepositories(forAccountID: accountID)
        hidden.removeAll { self.normalizedFullName($0) == normalized }
        self.session.settings.repoList.setHiddenRepositories(hidden, forAccountID: accountID)
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    /// Sets a repository's visibility in one place, keeping pinned/hidden arrays consistent.
    func setVisibility(for fullName: String, to visibility: RepoVisibility, accountID: String? = nil) async {
        // Always trim first to avoid storing whitespace variants.
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = self.normalizedFullName(trimmed)

        // Remove from both buckets before re-adding.
        var pinned = self.session.settings.repoList.pinnedRepositories(forAccountID: accountID)
        pinned.removeAll { self.normalizedFullName($0) == normalized }
        var hidden = self.session.settings.repoList.hiddenRepositories(forAccountID: accountID)
        hidden.removeAll { self.normalizedFullName($0) == normalized }

        switch visibility {
        case .pinned:
            pinned.append(trimmed)
        case .hidden:
            hidden.append(trimmed)
        case .visible:
            break
        }

        self.session.settings.repoList.setPinnedRepositories(pinned, forAccountID: accountID)
        self.session.settings.repoList.setHiddenRepositories(hidden, forAccountID: accountID)
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    struct VisibleSelectionOptions {
        let pinned: [String]
        let hidden: Set<String>
        let hiddenGroups: [String]
        let accountScopedRepositoryLists: AccountScopedRepositoryLists
        let includeForks: Bool
        let includeArchived: Bool
        let limit: Int
        let ownerFilter: [String]

        init(
            pinned: [String],
            hidden: Set<String>,
            hiddenGroups: [String],
            accountScopedRepositoryLists: AccountScopedRepositoryLists = AccountScopedRepositoryLists(),
            includeForks: Bool,
            includeArchived: Bool,
            limit: Int,
            ownerFilter: [String]
        ) {
            self.pinned = pinned
            self.hidden = hidden
            self.hiddenGroups = hiddenGroups
            self.accountScopedRepositoryLists = accountScopedRepositoryLists
            self.includeForks = includeForks
            self.includeArchived = includeArchived
            self.limit = limit
            self.ownerFilter = ownerFilter
        }
    }

    nonisolated static func selectVisible(all repos: [Repository], options: VisibleSelectionOptions) -> [Repository] {
        let uniqueRepos = RepositoryUniquing.byFullName(repos)
        let defaultPinnedSet = Set(options.pinned.map { RepositoryVisibilityRules.normalizeRepositoryPath($0) })
        let defaultHidden = options.hidden.map { RepositoryVisibilityRules.normalizeRepositoryPath($0) }

        func accountID(for repo: Repository) -> String? {
            repo.identity?.accountID
        }

        func pinnedRepositories(for repo: Repository) -> [String] {
            options.accountScopedRepositoryLists.pinnedRepositories(forAccountID: accountID(for: repo)) ?? options.pinned
        }

        func isPinned(_ repo: Repository) -> Bool {
            let pinned = pinnedRepositories(for: repo)
            let normalized = RepositoryVisibilityRules.normalizeRepositoryPath(repo.fullName)
            return pinned.contains {
                RepositoryVisibilityRules.normalizeRepositoryPath($0) == normalized
            }
        }

        func isHiddenByRepositoryRule(_ repo: Repository) -> Bool {
            let hiddenRepositories = options.accountScopedRepositoryLists
                .hiddenRepositories(forAccountID: accountID(for: repo))
                ?? defaultHidden
            let normalized = RepositoryVisibilityRules.normalizeRepositoryPath(repo.fullName)
            let hiddenSet = Set(hiddenRepositories.map { RepositoryVisibilityRules.normalizeRepositoryPath($0) })
            return hiddenSet.contains(normalized)
        }

        func isHiddenByGroupRule(_ repo: Repository) -> Bool {
            let hiddenGroups = options.accountScopedRepositoryLists
                .hiddenGroups(forAccountID: accountID(for: repo))
                ?? options.hiddenGroups

            return RepositoryVisibilityRules.hiddenGroup(for: repo.fullName, hiddenGroups: hiddenGroups) != nil
        }

        func isEffectivelyHidden(_ repo: Repository) -> Bool {
            isHiddenByGroupRule(repo) || (isHiddenByRepositoryRule(repo) && !isPinned(repo))
        }

        let filtered = uniqueRepos.filter { !isEffectivelyHidden($0) }
        let visible = RepositoryFilter.apply(
            filtered,
            includeForks: options.includeForks,
            includeArchived: options.includeArchived,
            pinned: defaultPinnedSet,
            ownerFilter: options.ownerFilter,
            isPinned: isPinned
        )
        let limited = Array(visible.prefix(max(options.limit, 0)))
        return limited.sorted { lhs, rhs in
            let lhsIndex = Self.index(of: lhs.fullName, in: pinnedRepositories(for: lhs))
            let rhsIndex = Self.index(of: rhs.fullName, in: pinnedRepositories(for: rhs))
            switch (lhsIndex, rhsIndex) {
            case let (l?, r?):
                return l < r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return false
            }
        }
    }

    private func normalizedFullName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private nonisolated static func index(of fullName: String, in repositories: [String]) -> Int? {
        let normalized = RepositoryVisibilityRules.normalizeRepositoryPath(fullName)
        return repositories.firstIndex {
            RepositoryVisibilityRules.normalizeRepositoryPath($0) == normalized
        }
    }

    private func index(of fullName: String, in repositories: [String]) -> Int? {
        Self.index(of: fullName, in: repositories)
    }

    private func repo(_ repo: Repository, matchesFullName normalizedFullName: String, accountID: String?) -> Bool {
        self.normalizedFullName(repo.fullName) == normalizedFullName && self.repo(repo, matchesAccountID: accountID)
    }

    private func repo(_ repo: Repository, matchesAccountID accountID: String?) -> Bool {
        guard let normalizedAccountID = AccountScopedRepositoryLists.normalizedAccountID(accountID) else {
            return true
        }

        return AccountScopedRepositoryLists.normalizedAccountID(repo.identity?.accountID) == normalizedAccountID
    }
}
