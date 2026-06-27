import Foundation

public enum MainMenuItemGroup: String, Hashable, Sendable {
    case auth
    case header
    case status
    case filters
    case repos
    case footer
}

public enum MainMenuItemID: String, CaseIterable, Codable, Hashable, Sendable {
    case loggedOutPrompt
    case signInAction
    case contributionHeader
    case statusBanner
    case rateLimits
    case filters
    case repoList
    case refreshNow
    case issueNavigator
    case preferences
    case about
    case restartToUpdate
    case quit

    public var title: String {
        switch self {
        case .loggedOutPrompt: "Account Status"
        case .signInAction: "Sign In"
        case .contributionHeader: "Contribution Header"
        case .statusBanner: "Status Banner"
        case .rateLimits: "GitLab API Status"
        case .filters: "Menu Filters"
        case .repoList: "Repository List"
        case .refreshNow: "Refresh Now"
        case .issueNavigator: "Issue Navigator"
        case .preferences: "Preferences"
        case .about: "About RepoPeek"
        case .restartToUpdate: "Restart to Update"
        case .quit: "Quit RepoPeek"
        }
    }

    public var subtitle: String? {
        switch self {
        case .loggedOutPrompt: "Login state banner"
        case .signInAction: "GitLab sign-in action"
        case .contributionHeader: "Heatmap header + submenu"
        case .statusBanner: "Rate-limit or error banner"
        case .rateLimits: "Shown only when GitLab API is blocked"
        case .filters: "Search, filters, sort, and refresh"
        case .repoList: "Repository rows + inline heatmap"
        case .refreshNow: "Manual GitLab and local project refresh"
        case .issueNavigator: "Fast issue and merge request search"
        case .preferences: nil
        case .about: nil
        case .restartToUpdate: "Shown when an update is ready"
        case .quit: nil
        }
    }

    public var systemImage: String? {
        switch self {
        case .refreshNow: "arrow.clockwise"
        case .issueNavigator: "rectangle.and.text.magnifyingglass"
        case .preferences: "gearshape"
        case .about: "info.circle"
        case .restartToUpdate: "arrow.triangle.2.circlepath"
        case .quit: "power"
        default: nil
        }
    }

    public var group: MainMenuItemGroup {
        switch self {
        case .loggedOutPrompt, .signInAction: .auth
        case .contributionHeader: .header
        case .statusBanner, .rateLimits: .status
        case .filters: .filters
        case .repoList: .repos
        case .refreshNow, .issueNavigator, .preferences, .about, .restartToUpdate, .quit: .footer
        }
    }
}

public enum RepoSubmenuItemGroup: String, Hashable, Sendable {
    case open
    case local
    case lists
    case heatmap
    case commits
    case activity
    case manage
}

public enum RepoSubmenuItemID: String, CaseIterable, Codable, Hashable, Sendable {
    case openOnGitLab
    case openInFinder
    case openInTerminal
    case checkoutRepo
    case localState
    case worktrees
    case issues
    case pulls
    case releases
    case changelog
    case ciRuns
    case tags
    case branches
    case contributors
    case heatmap
    case commits
    case activity
    case pinToggle
    case hideRepo
    case moveUp
    case moveDown

    public var title: String {
        switch self {
        case .openOnGitLab: "Open on GitLab"
        case .openInFinder: "Open in Finder"
        case .openInTerminal: "Open in Terminal"
        case .checkoutRepo: "Checkout Repo"
        case .localState: "Local Repo Status"
        case .worktrees: "Worktrees"
        case .issues: "Issues"
        case .pulls: "Merge Requests"
        case .releases: "Releases"
        case .changelog: "Changelog"
        case .ciRuns: "Pipelines"
        case .tags: "Tags"
        case .branches: "Branches"
        case .contributors: "Contributors"
        case .heatmap: "Heatmap"
        case .commits: "Commits"
        case .activity: "Activity"
        case .pinToggle: "Pin/Unpin"
        case .hideRepo: "Hide Repo"
        case .moveUp: "Move Up"
        case .moveDown: "Move Down"
        }
    }

    public var subtitle: String? {
        switch self {
        case .openOnGitLab: "Open repository in browser"
        case .openInFinder: "Local checkout"
        case .openInTerminal: "Local checkout"
        case .checkoutRepo: "Clone or checkout"
        case .localState: "Sync + dirty state"
        case .worktrees: "Switch or create worktrees"
        case .issues: "Recent issues list"
        case .pulls: "Recent merge requests"
        case .releases: "Recent releases list"
        case .changelog: "Inline markdown preview"
        case .ciRuns: "Recent pipelines"
        case .tags: "Recent tags"
        case .branches: "Branch menu"
        case .contributors: "Recent contributors"
        case .heatmap: "Repo heatmap submenu"
        case .commits: "Commit list preview"
        case .activity: "Activity feed preview"
        case .pinToggle: nil
        case .hideRepo: nil
        case .moveUp: nil
        case .moveDown: nil
        }
    }

    public var group: RepoSubmenuItemGroup {
        switch self {
        case .openOnGitLab: .open
        case .openInFinder, .openInTerminal, .checkoutRepo, .localState, .worktrees: .local
        case .changelog: .open
        case .issues, .pulls, .releases, .ciRuns, .tags, .branches, .contributors: .lists
        case .heatmap: .heatmap
        case .commits: .commits
        case .activity: .activity
        case .pinToggle, .hideRepo, .moveUp, .moveDown: .manage
        }
    }
}

public struct MenuCustomization: Equatable, Codable, Hashable, Sendable {
    public var hiddenMainMenuItems: Set<MainMenuItemID> = []
    public var mainMenuOrder: [MainMenuItemID] = Self.defaultMainMenuOrder
    public var hiddenRepoSubmenuItems: Set<RepoSubmenuItemID> = []
    public var repoSubmenuOrder: [RepoSubmenuItemID] = Self.defaultRepoSubmenuOrder

    public init() {}

    enum CodingKeys: String, CodingKey {
        case hiddenMainMenuItems
        case mainMenuOrder
        case hiddenRepoSubmenuItems
        case repoSubmenuOrder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hiddenMainMenuItems = try Set(Self.decodeIDs(MainMenuItemID.self, forKey: .hiddenMainMenuItems, from: container))
        self.mainMenuOrder = try Self.decodeIDs(MainMenuItemID.self, forKey: .mainMenuOrder, from: container)
        self.hiddenRepoSubmenuItems = try Set(Self.decodeIDs(RepoSubmenuItemID.self, forKey: .hiddenRepoSubmenuItems, from: container))
        self.repoSubmenuOrder = try Self.decodeIDs(RepoSubmenuItemID.self, forKey: .repoSubmenuOrder, from: container)
        self.normalize()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.hiddenMainMenuItems.map(\.rawValue).sorted(), forKey: .hiddenMainMenuItems)
        try container.encode(self.mainMenuOrder.map(\.rawValue), forKey: .mainMenuOrder)
        try container.encode(self.hiddenRepoSubmenuItems.map(\.rawValue).sorted(), forKey: .hiddenRepoSubmenuItems)
        try container.encode(self.repoSubmenuOrder.map(\.rawValue), forKey: .repoSubmenuOrder)
    }

    public mutating func normalize() {
        let originalMainOrder = self.mainMenuOrder
        let originalRepoOrder = self.repoSubmenuOrder
        self.mainMenuOrder = Self.normalizedOrder(self.mainMenuOrder, defaults: Self.defaultMainMenuOrder)
        Self.moveMainMenuItem(.rateLimits, after: .statusBanner, in: &self.mainMenuOrder)
        if originalMainOrder.contains(.refreshNow) == false {
            Self.moveMainMenuItem(.refreshNow, after: .repoList, in: &self.mainMenuOrder)
        }
        self.repoSubmenuOrder = Self.normalizedOrder(self.repoSubmenuOrder, defaults: Self.defaultRepoSubmenuOrder)
        if originalRepoOrder.contains(.changelog) == false {
            self.repoSubmenuOrder.removeAll { $0 == .changelog }
            if let openIndex = self.repoSubmenuOrder.firstIndex(of: .openOnGitLab) {
                self.repoSubmenuOrder.insert(.changelog, at: openIndex + 1)
            } else {
                self.repoSubmenuOrder.insert(.changelog, at: 0)
            }
        }
    }

    public func normalized() -> MenuCustomization {
        var copy = self
        copy.normalize()
        return copy
    }

    public static let requiredMainMenuItems: Set<MainMenuItemID> = [
        .preferences,
        .about,
        .quit
    ]

    public static let defaultMainMenuOrder: [MainMenuItemID] = [
        .loggedOutPrompt,
        .signInAction,
        .contributionHeader,
        .statusBanner,
        .rateLimits,
        .filters,
        .repoList,
        .refreshNow,
        .issueNavigator,
        .preferences,
        .about,
        .restartToUpdate,
        .quit
    ]

    public static let defaultRepoSubmenuOrder: [RepoSubmenuItemID] = [
        .openOnGitLab,
        .changelog,
        .openInFinder,
        .openInTerminal,
        .checkoutRepo,
        .localState,
        .worktrees,
        .issues,
        .pulls,
        .releases,
        .ciRuns,
        .tags,
        .branches,
        .contributors,
        .heatmap,
        .commits,
        .activity,
        .pinToggle,
        .hideRepo
    ]

    private static func normalizedOrder<T: Hashable>(_ order: [T], defaults: [T]) -> [T] {
        var seen = Set<T>()
        var result: [T] = []
        let allowed = Set(defaults)
        for item in order where allowed.contains(item) && seen.insert(item).inserted {
            result.append(item)
        }
        for item in defaults where seen.insert(item).inserted {
            result.append(item)
        }
        return result
    }

    private static func decodeIDs<T: RawRepresentable>(
        _ type: T.Type,
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [T] where T.RawValue == String {
        let rawValues = try container.decodeIfPresent([String].self, forKey: key) ?? []
        return rawValues.compactMap(type.init(rawValue:))
    }

    private static func moveMainMenuItem(
        _ item: MainMenuItemID,
        after anchor: MainMenuItemID,
        in order: inout [MainMenuItemID]
    ) {
        guard let itemIndex = order.firstIndex(of: item),
              let anchorIndex = order.firstIndex(of: anchor) else { return }

        order.remove(at: itemIndex)
        let adjustedAnchorIndex = itemIndex < anchorIndex ? anchorIndex - 1 : anchorIndex
        order.insert(item, at: min(adjustedAnchorIndex + 1, order.count))
    }
}

public extension MainMenuItemID {
    var isRequired: Bool {
        MenuCustomization.requiredMainMenuItems.contains(self)
    }
}
