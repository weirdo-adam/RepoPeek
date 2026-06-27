import Foundation

public enum RepositoryScope: String, CaseIterable, Codable, Sendable {
    case all
    case pinned
    case hidden
}

public struct RepositoryQuery: Equatable, Sendable {
    public var scope: RepositoryScope
    public var onlyWith: RepositoryOnlyWith
    public var includeForks: Bool
    public var includeArchived: Bool
    public var sortKey: RepositorySortKey
    public var limit: Int?
    public var ageCutoff: Date?
    public var pinned: [String]
    public var hidden: Set<String>
    public var hiddenGroups: [String]
    public var accountScopedRepositoryLists: AccountScopedRepositoryLists
    public var pinPriority: Bool
    public var ownerFilter: [String]

    public init(
        scope: RepositoryScope = .all,
        onlyWith: RepositoryOnlyWith = .none,
        includeForks: Bool = false,
        includeArchived: Bool = false,
        sortKey: RepositorySortKey = .activity,
        limit: Int? = nil,
        ageCutoff: Date? = nil,
        pinned: [String] = [],
        hidden: Set<String> = [],
        hiddenGroups: [String] = [],
        accountScopedRepositoryLists: AccountScopedRepositoryLists = AccountScopedRepositoryLists(),
        pinPriority: Bool = false,
        ownerFilter: [String] = []
    ) {
        self.scope = scope
        self.onlyWith = onlyWith
        self.includeForks = includeForks
        self.includeArchived = includeArchived
        self.sortKey = sortKey
        self.limit = limit
        self.ageCutoff = ageCutoff
        self.pinned = pinned
        self.hidden = hidden
        self.hiddenGroups = RepositoryVisibilityRules.normalizedGroupPaths(hiddenGroups)
        self.accountScopedRepositoryLists = accountScopedRepositoryLists
        self.pinPriority = pinPriority
        self.ownerFilter = OwnerFilter.normalize(ownerFilter)
    }
}

public enum RepositoryQueryDefaults {
    public static let defaultAgeDays = 365

    public static func ageCutoff(
        now: Date = Date(),
        scope: RepositoryScope,
        ageDays: Int = defaultAgeDays
    ) -> Date? {
        guard scope == .all, ageDays > 0 else { return nil }

        return Calendar.current.date(byAdding: .day, value: -ageDays, to: now)
    }
}

public enum RepositoryPipeline {
    public static func apply(_ repos: [Repository], query: RepositoryQuery) -> [Repository] {
        var filtered = RepositoryUniquing.byFullName(repos)
        let defaultPinnedSet = Set(query.pinned.map { RepositoryVisibilityRules.normalizeRepositoryPath($0) })
        let defaultHidden = query.hidden.map { RepositoryVisibilityRules.normalizeRepositoryPath($0) }

        func accountID(for repo: Repository) -> String? {
            repo.identity?.accountID
        }

        func pinnedRepositories(for repo: Repository) -> [String] {
            query.accountScopedRepositoryLists.pinnedRepositories(forAccountID: accountID(for: repo)) ?? query.pinned
        }

        func pinnedSet(for repo: Repository) -> Set<String> {
            guard query.accountScopedRepositoryLists.pinnedRepositories(forAccountID: accountID(for: repo)) != nil else {
                return defaultPinnedSet
            }

            return Set(pinnedRepositories(for: repo).map { RepositoryVisibilityRules.normalizeRepositoryPath($0) })
        }

        func hiddenRepositories(for repo: Repository) -> Set<String> {
            guard let repositories = query.accountScopedRepositoryLists.hiddenRepositories(forAccountID: accountID(for: repo)) else {
                return Set(defaultHidden)
            }

            return Set(repositories.map { RepositoryVisibilityRules.normalizeRepositoryPath($0) })
        }

        func hiddenGroups(for repo: Repository) -> [String] {
            query.accountScopedRepositoryLists.hiddenGroups(forAccountID: accountID(for: repo)) ?? query.hiddenGroups
        }

        func isPinned(_ repo: Repository) -> Bool {
            pinnedSet(for: repo).contains(RepositoryVisibilityRules.normalizeRepositoryPath(repo.fullName))
        }

        func isHiddenByRepositoryRule(_ repo: Repository) -> Bool {
            hiddenRepositories(for: repo).contains(RepositoryVisibilityRules.normalizeRepositoryPath(repo.fullName))
        }

        func isHiddenByGroupRule(_ repo: Repository) -> Bool {
            RepositoryVisibilityRules.hiddenGroup(for: repo.fullName, hiddenGroups: hiddenGroups(for: repo)) != nil
        }

        func isEffectivelyHidden(_ repo: Repository) -> Bool {
            isHiddenByGroupRule(repo) || (isHiddenByRepositoryRule(repo) && !isPinned(repo))
        }

        switch query.scope {
        case .hidden:
            filtered = filtered.filter { isEffectivelyHidden($0) }
        case .all, .pinned:
            filtered = filtered.filter { !isEffectivelyHidden($0) }
        }

        filtered = RepositoryFilter.apply(
            filtered,
            includeForks: query.includeForks,
            includeArchived: query.includeArchived,
            pinned: defaultPinnedSet,
            ownerFilter: query.ownerFilter,
            isPinned: isPinned
        )

        if let cutoff = query.ageCutoff {
            filtered = filtered.filter { ($0.activityDate ?? .distantPast) >= cutoff }
        }

        if query.scope == .pinned {
            filtered = filtered.filter { isPinned($0) }
        }

        if query.onlyWith.isActive {
            filtered = filtered.filter { query.onlyWith.matches($0) }
        }

        let sorted: [Repository] = if query.pinPriority, !query.pinned.isEmpty || query.accountScopedRepositoryLists.hasPinnedRepositories {
            filtered.sorted { lhs, rhs in
                let leftIndex = Self.pinnedIndex(for: lhs, pinnedRepositories: pinnedRepositories(for: lhs))
                let rightIndex = Self.pinnedIndex(for: rhs, pinnedRepositories: pinnedRepositories(for: rhs))
                switch (leftIndex, rightIndex) {
                case let (left?, right?):
                    if left != right { return left < right }
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    break
                }
                return RepositorySort.isOrderedBefore(lhs, rhs, sortKey: query.sortKey)
            }
        } else {
            RepositorySort.sorted(filtered, sortKey: query.sortKey)
        }

        if let limit = query.limit {
            return Array(sorted.prefix(max(limit, 0)))
        }
        return sorted
    }

    private static func pinnedIndex(for repo: Repository, pinnedRepositories: [String]) -> Int? {
        let normalized = RepositoryVisibilityRules.normalizeRepositoryPath(repo.fullName)
        return pinnedRepositories.firstIndex {
            RepositoryVisibilityRules.normalizeRepositoryPath($0) == normalized
        }
    }
}
