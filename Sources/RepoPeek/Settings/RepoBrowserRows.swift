import Foundation
import RepoPeekCore

enum RepoBrowserRuleKind: String, Hashable {
    case repository
    case group
}

struct RepoBrowserRow: Identifiable, Hashable {
    let id: String
    let accountID: String?
    let fullName: String
    let rulePath: String
    let ruleKind: RepoBrowserRuleKind
    let hiddenByGroup: String?
    let owner: String
    let name: String
    let visibility: RepoVisibility
    let isFork: Bool
    let isArchived: Bool
    let isManual: Bool
    let openIssues: Int?
    let openPulls: Int?
    let stars: Int?
    let pushedAt: Date?
    let updatedLabel: String

    var issueLabel: String {
        self.openIssues.map(String.init) ?? "-"
    }

    var pullRequestLabel: String {
        self.openPulls.map(String.init) ?? "-"
    }

    var starLabel: String {
        self.stars.map(String.init) ?? "-"
    }

    func matches(_ query: String) -> Bool {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).lowercased() }
        guard !terms.isEmpty else { return true }

        let haystack = [
            self.fullName,
            self.owner,
            self.name,
            self.visibility.label,
            self.ruleKind == .group ? "group rule" : "",
            self.hiddenByGroup.map { "hidden group \($0)" } ?? "",
            self.accountID.map { "account \($0)" } ?? "",
            self.isFork ? "fork" : "",
            self.isArchived ? "archived" : "",
            self.isManual ? "manual" : ""
        ]
        .joined(separator: " ")
        .lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }
}

enum RepoBrowserRows {
    static func make(
        repositories: [Repository],
        pinnedRepositories: [String],
        hiddenRepositories: [String],
        hiddenGroups: [String],
        accountScopedRepositoryLists: AccountScopedRepositoryLists = AccountScopedRepositoryLists(),
        now: Date
    ) -> [RepoBrowserRow] {
        let uniqueRepos = RepositoryUniquing.byFullName(repositories)

        var rows = uniqueRepos.map { repo in
            let accountID = repo.identity?.accountID
            let key = Self.normalized(repo.fullName)
            let pinnedSet = Set(
                (accountScopedRepositoryLists.pinnedRepositories(forAccountID: accountID) ?? pinnedRepositories)
                    .map(Self.normalized)
            )
            let hiddenSet = Set(
                (accountScopedRepositoryLists.hiddenRepositories(forAccountID: accountID) ?? hiddenRepositories)
                    .map(Self.normalized)
            )
            let normalizedHiddenGroups = RepositoryVisibilityRules.normalizedGroupPaths(
                accountScopedRepositoryLists.hiddenGroups(forAccountID: accountID) ?? hiddenGroups
            )
            let hiddenByGroup = RepositoryVisibilityRules.hiddenGroup(
                for: repo.fullName,
                hiddenGroups: normalizedHiddenGroups
            )
            let visibility: RepoVisibility = if hiddenByGroup != nil {
                .hidden
            } else if pinnedSet.contains(key) {
                .pinned
            } else if hiddenSet.contains(key) {
                .hidden
            } else {
                .visible
            }
            return RepoBrowserRow(
                id: Self.ruleID(kind: .repository, path: repo.fullName, accountID: accountID),
                accountID: accountID,
                fullName: repo.fullName,
                rulePath: repo.fullName,
                ruleKind: .repository,
                hiddenByGroup: hiddenByGroup,
                owner: repo.owner,
                name: repo.name,
                visibility: visibility,
                isFork: repo.isFork,
                isArchived: repo.isArchived,
                isManual: false,
                openIssues: repo.stats.openIssues,
                openPulls: repo.stats.openPulls,
                stars: repo.stats.stars,
                pushedAt: repo.stats.pushedAt,
                updatedLabel: repo.stats.pushedAt.map { RelativeFormatter.string(from: $0, relativeTo: now) } ?? "-"
            )
        }

        var seenRuleKeys = Set(rows.filter { $0.ruleKind == .repository }.map {
            Self.ruleKey(path: $0.rulePath, accountID: $0.accountID)
        })
        for name in pinnedRepositories {
            guard seenRuleKeys.insert(Self.ruleKey(path: name, accountID: nil)).inserted else { continue }

            rows.append(Self.manualRow(fullName: name, visibility: .pinned, accountID: nil))
        }
        for name in hiddenRepositories {
            guard seenRuleKeys.insert(Self.ruleKey(path: name, accountID: nil)).inserted else { continue }

            rows.append(Self.manualRow(fullName: name, visibility: .hidden, accountID: nil))
        }
        for group in RepositoryVisibilityRules.normalizedGroupPaths(hiddenGroups) {
            rows.append(Self.groupRow(groupPath: group, accountID: nil))
        }
        for accountID in accountScopedRepositoryLists.pinnedRepositoriesByAccount.keys.sorted() {
            for name in accountScopedRepositoryLists.pinnedRepositoriesByAccount[accountID] ?? [] {
                guard seenRuleKeys.insert(Self.ruleKey(path: name, accountID: accountID)).inserted else { continue }

                rows.append(Self.manualRow(fullName: name, visibility: .pinned, accountID: accountID))
            }
        }
        for accountID in accountScopedRepositoryLists.hiddenRepositoriesByAccount.keys.sorted() {
            for name in accountScopedRepositoryLists.hiddenRepositoriesByAccount[accountID] ?? [] {
                guard seenRuleKeys.insert(Self.ruleKey(path: name, accountID: accountID)).inserted else { continue }

                rows.append(Self.manualRow(fullName: name, visibility: .hidden, accountID: accountID))
            }
        }
        for accountID in accountScopedRepositoryLists.hiddenGroupsByAccount.keys.sorted() {
            for group in accountScopedRepositoryLists.hiddenGroupsByAccount[accountID] ?? [] {
                rows.append(Self.groupRow(groupPath: group, accountID: accountID))
            }
        }

        return rows.sorted { lhs, rhs in
            if lhs.visibility.sortPriority != rhs.visibility.sortPriority {
                return lhs.visibility.sortPriority < rhs.visibility.sortPriority
            }
            if lhs.ruleKind != rhs.ruleKind {
                return lhs.ruleKind.sortPriority < rhs.ruleKind.sortPriority
            }
            return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
        }
    }

    static func filter(_ rows: [RepoBrowserRow], query: String) -> [RepoBrowserRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }

        return rows.filter { $0.matches(trimmed) }
    }

    static func statusLine(
        allRows: [RepoBrowserRow],
        filteredRows: [RepoBrowserRow],
        language: AppLanguage = .english
    ) -> String {
        let total = allRows.count
        let visible = filteredRows.count
        let loaded = allRows.count(where: { !$0.isManual })
        let pinned = allRows.count(where: { $0.visibility == .pinned })
        let hidden = allRows.count(where: { $0.visibility == .hidden })
        if visible == total {
            return L10n.format(
                "%d repositories, %d loaded, %d pinned, %d hidden",
                language: language,
                total,
                loaded,
                pinned,
                hidden
            )
        }
        return L10n.format(
            "%d of %d repositories, %d pinned, %d hidden",
            language: language,
            visible,
            total,
            pinned,
            hidden
        )
    }

    private static func manualRow(fullName: String, visibility: RepoVisibility, accountID: String?) -> RepoBrowserRow {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/").map(String.init)
        let owner = parts.count > 1 ? parts.dropLast().joined(separator: "/") : ""
        let name = parts.last ?? trimmed
        return RepoBrowserRow(
            id: Self.ruleID(kind: .repository, path: trimmed, accountID: accountID),
            accountID: accountID,
            fullName: trimmed,
            rulePath: trimmed,
            ruleKind: .repository,
            hiddenByGroup: nil,
            owner: owner,
            name: name,
            visibility: visibility,
            isFork: false,
            isArchived: false,
            isManual: true,
            openIssues: nil,
            openPulls: nil,
            stars: nil,
            pushedAt: nil,
            updatedLabel: "-"
        )
    }

    private static func groupRow(groupPath: String, accountID: String?) -> RepoBrowserRow {
        let normalized = RepositoryVisibilityRules.normalizeGroupPath(groupPath)
        let parts = normalized.split(separator: "/").map(String.init)
        let name = parts.last ?? normalized
        let owner = parts.dropLast().joined(separator: "/")
        return RepoBrowserRow(
            id: Self.ruleID(kind: .group, path: normalized, accountID: accountID),
            accountID: accountID,
            fullName: normalized,
            rulePath: normalized,
            ruleKind: .group,
            hiddenByGroup: nil,
            owner: owner,
            name: name,
            visibility: .hidden,
            isFork: false,
            isArchived: false,
            isManual: true,
            openIssues: nil,
            openPulls: nil,
            stars: nil,
            pushedAt: nil,
            updatedLabel: "-"
        )
    }

    private static func normalized(_ fullName: String) -> String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func ruleID(kind: RepoBrowserRuleKind, path: String, accountID: String?) -> String {
        "\(kind.rawValue):\(self.ruleKey(path: path, accountID: accountID))"
    }

    private static func ruleKey(path: String, accountID: String?) -> String {
        let scope = AccountScopedRepositoryLists.normalizedAccountID(accountID) ?? "global"
        return "\(scope):\(Self.normalized(path))"
    }
}

private extension RepoVisibility {
    var sortPriority: Int {
        switch self {
        case .pinned: 0
        case .visible: 1
        case .hidden: 2
        }
    }
}

private extension RepoBrowserRuleKind {
    var sortPriority: Int {
        switch self {
        case .repository: 0
        case .group: 1
        }
    }
}
