import AppKit
import OSLog
import RepoPeekCore
import SwiftUI

@MainActor
final class StatusBarMenuBuilder {
    private static let menuFixedWidth: CGFloat = 360
    private static let repoMenuItemIdentifier = NSUserInterfaceItemIdentifier("RepoPeekRepoMenuItem")
    private static let repoSeparatorItemIdentifier = NSUserInterfaceItemIdentifier("RepoPeekRepoSeparatorItem")
    private static let repoEmptySearchItemIdentifier = NSUserInterfaceItemIdentifier("RepoPeekRepoEmptySearchItem")

    let appState: AppState
    unowned let target: StatusBarMenuManager
    let signposter = OSSignposter(subsystem: "com.weirdoadam.repopeek", category: "menu")
    var repoMenuItemCache: [String: NSMenuItem] = [:]
    var repoSubmenuCache: [String: RepoSubmenuCacheEntry] = [:]
    var systemImageCache: [String: NSImage] = [:]
    let menuItemFactory = MenuItemViewFactory()

    init(appState: AppState, target: StatusBarMenuManager) {
        self.appState = appState
        self.target = target
    }

    func makeMainMenu() -> NSMenu {
        let menu = MainMenuSearchMenu()
        menu.autoenablesItems = false
        menu.delegate = self.target
        menu.onKeyEquivalent = { [weak target = self.target] event in
            target?.handleMainMenuKeyEquivalent(event) ?? false
        }
        menu.appearance = nil
        return menu
    }

    func mainMenuPlan(now: Date = Date()) -> MainMenuPlan {
        let session = self.appState.session
        let settings = session.settings
        let repos = self.orderedViewModels(now: now)
        let signature = MenuBuildSignature(
            account: AccountSignature(session.account),
            settings: MenuSettingsSignature(settings: settings, selection: session.menuRepoSelection),
            hasLoadedRepositories: session.hasLoadedRepositories,
            rateLimitReset: session.rateLimitReset,
            rateLimits: RateLimitMenuSignature(session.rateLimitDisplayState),
            lastError: session.lastError,
            contribution: ContributionSignature(
                user: session.contributionUser,
                error: session.contributionError,
                heatmapCount: session.contributionHeatmap.count
            ),
            globalActivity: ActivitySignature(
                events: session.globalActivityEvents,
                error: session.globalActivityError
            ),
            globalCommits: CommitSignature(
                commits: session.globalCommitEvents,
                error: session.globalCommitError
            ),
            heatmapRangeStart: session.heatmapRange.start.timeIntervalSinceReferenceDate,
            heatmapRangeEnd: session.heatmapRange.end.timeIntervalSinceReferenceDate,
            repoSearchQuery: session.menuRepoSearchQuery,
            repoSearchExpanded: session.menuRepoSearchExpanded,
            reposDigest: RepoSignature.digest(for: repos),
            timeBucket: Int(now.timeIntervalSinceReferenceDate / 60)
        )
        return MainMenuPlan(repos: repos, signature: signature)
    }

    func populateMainMenu(_ menu: NSMenu, repos: [RepositoryDisplayModel]) {
        let signpost = self.signposter.beginInterval("populateMainMenu")
        defer { self.signposter.endInterval("populateMainMenu", signpost) }
        menu.removeAllItems()
        let session = self.appState.session
        let settings = session.settings
        let customization = settings.menuCustomization.normalized()
        let blocks = self.mainMenuBlocks(repos: repos, settings: settings, customization: customization)
        self.flattenMainMenuBlocks(blocks).forEach { menu.addItem($0) }
    }

    private struct MainMenuBlock {
        let group: MainMenuItemGroup
        let items: [NSMenuItem]
    }

    private func mainMenuBlocks(
        repos: [RepositoryDisplayModel],
        settings: UserSettings,
        customization: MenuCustomization
    ) -> [MainMenuBlock] {
        let session = self.appState.session
        var blocks: [MainMenuBlock] = []
        for itemID in customization.mainMenuOrder {
            if customization.hiddenMainMenuItems.contains(itemID), !itemID.isRequired { continue }
            let items = self.mainMenuItems(for: itemID, repos: repos, settings: settings, session: session)
            if items.isEmpty { continue }
            blocks.append(MainMenuBlock(group: itemID.group, items: items))
        }
        return blocks
    }

    private func mainMenuItems(
        for itemID: MainMenuItemID,
        repos: [RepositoryDisplayModel],
        settings: UserSettings,
        session: Session
    ) -> [NSMenuItem] {
        switch itemID {
        case .loggedOutPrompt:
            guard !self.shouldUseLocalMenuWithoutAccount(session) else { return [] }

            switch session.account {
            case .loggedOut, .loggingIn:
                let loggedOut = MenuLoggedOutView(
                    title: self.t("Sign in to see your repositories"),
                    subtitle: self.t("Connect your GitLab account to load pins and activity.")
                )
                .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
                .padding(.vertical, MenuStyle.sectionVerticalPadding)
                return [self.viewItem(for: loggedOut, enabled: false)]
            case .loggedIn:
                return []
            }
        case .signInAction:
            guard !self.shouldUseLocalMenuWithoutAccount(session) else { return [] }

            switch session.account {
            case .loggedOut:
                return [self.centeredActionItem(
                    title: self.t("Sign in to GitLab"),
                    action: #selector(self.target.signIn),
                    enabled: true
                )]
            case .loggingIn:
                return [self.centeredActionItem(
                    title: self.t("Signing in…"),
                    action: #selector(self.target.signIn),
                    enabled: false
                )]
            case .loggedIn:
                return []
            }
        case .contributionHeader:
            guard case .loggedIn = session.account else { return [] }

            let hasContributionHeatmap = session.contributionHeatmap.isEmpty == false
            let shouldShowContributionHeader = settings.appearance.showContributionHeader
                && (hasContributionHeatmap || session.contributionError == nil)
            let username = self.currentUsername()
            let displayName = self.currentDisplayName()
            guard shouldShowContributionHeader, let username, let displayName else { return [] }

            let header = ContributionHeaderView(
                username: username,
                displayName: displayName,
                session: session,
                appState: self.appState
            )
            .padding(.horizontal, MenuStyle.headerHorizontalPadding)
            .padding(.top, MenuStyle.headerTopPadding)
            .padding(.bottom, MenuStyle.headerBottomPadding)
            let submenu = self.contributionSubmenu(username: username, displayName: displayName)
            return [self.viewItem(for: header, enabled: true, submenu: submenu)]
        case .statusBanner:
            guard case .loggedIn = session.account else { return [] }

            if let reset = session.rateLimitReset {
                let resetText = RelativeFormatter.string(from: reset, relativeTo: Date())
                let banner = RateLimitBanner(
                    reset: reset,
                    text: self.format("Rate limit resets %@", resetText),
                    accessibilityLabel: self.format("Rate limit reset: %@", resetText)
                )
                .padding(.horizontal, MenuStyle.bannerHorizontalPadding)
                .padding(.vertical, MenuStyle.bannerVerticalPadding)
                return [self.viewItem(for: banner, enabled: false)]
            }
            if let error = session.lastError {
                let banner = ErrorBanner(message: error, accessibilityLabel: self.format("Error: %@", error))
                    .padding(.horizontal, MenuStyle.bannerHorizontalPadding)
                    .padding(.vertical, MenuStyle.bannerVerticalPadding)
                return [self.viewItem(for: banner, enabled: false)]
            }
            return []
        case .rateLimits:
            guard case .loggedIn = session.account else { return [] }
            guard let item = self.rateLimitsStatusMenuItemIfNeeded() else { return [] }

            return [item]
        case .filters:
            let isLoggedIn = session.account.isLoggedIn
            let canShowLocalMenu = self.shouldUseLocalMenuWithoutAccount(session)
            let useLocalRepositoryFallback = self.shouldUseLocalRepositoryFallback(session)
            guard isLoggedIn ? (session.hasLoadedRepositories || useLocalRepositoryFallback) : canShowLocalMenu else { return [] }

            let filters = MenuRepoFiltersView(
                session: session,
                repositoryCandidateCount: self.uniqueDisplayModels(repos).count,
                onSearchChange: { [weak target = self.target] query in
                    target?.applyMainMenuRepoSearch(query)
                },
                onRefresh: { [weak target = self.target] in
                    target?.refreshNow()
                }
            )
            .padding(.horizontal, 0)
            .padding(.vertical, 0)
            return [self.viewItem(for: filters, enabled: true)]
        case .repoList:
            let isLoggedIn = session.account.isLoggedIn
            let isLocalScope = session.menuRepoSelection.isLocalScope
            let uniqueRepos = self.uniqueDisplayModels(repos)
            let canShowLocalMenu = self.shouldUseLocalMenuWithoutAccount(session)
            let useLocalRepositoryFallback = self.shouldUseLocalRepositoryFallback(session)
            guard isLoggedIn || isLocalScope || canShowLocalMenu else { return [] }

            if isLoggedIn,
               !session.hasLoadedRepositories,
               uniqueRepos.isEmpty,
               !useLocalRepositoryFallback || session.localProjectsScanInProgress
            {
                let loading = MenuLoadingRowView(text: self.t("Loading repositories…"))
                    .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
                    .padding(.vertical, MenuStyle.sectionVerticalPadding)
                return [self.viewItem(for: loading, enabled: false)]
            }
            if uniqueRepos.isEmpty {
                let (title, subtitle) = self.emptyStateMessage(for: session)
                let emptyState = MenuEmptyStateView(title: title, subtitle: subtitle)
                    .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
                    .padding(.vertical, MenuStyle.sectionVerticalPadding)
                return [self.viewItem(for: emptyState, enabled: false)]
            }
            var items: [NSMenuItem] = []
            var usedRepoKeys: Set<String> = []
            for (index, repo) in uniqueRepos.enumerated() {
                let isPinned = settings.repoList.isPinned(
                    fullName: repo.title,
                    accountID: repo.source.identity?.accountID
                )
                let item = self.repoMenuItem(for: repo, isPinned: isPinned)
                item.identifier = Self.repoMenuItemIdentifier
                item.representedObject = repo.menuActionContext
                items.append(item)
                if index < uniqueRepos.count - 1 {
                    let separator = self.repoCardSeparator()
                    separator.identifier = Self.repoSeparatorItemIdentifier
                    items.append(separator)
                }
                usedRepoKeys.insert(repo.id)
            }
            let emptySearchState = MenuEmptyStateView(
                title: self.t("No repositories match this filter"),
                subtitle: self.t("Try All or a different filter.")
            )
            .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
            .padding(.vertical, MenuStyle.sectionVerticalPadding)
            let emptySearchItem = self.viewItem(for: emptySearchState, enabled: false)
            emptySearchItem.identifier = Self.repoEmptySearchItemIdentifier
            items.append(emptySearchItem)
            self.applyRepoListVisibility(
                in: items,
                query: session.menuRepoSearchQuery,
                displayLimit: settings.repoList.displayLimit
            )
            self.repoMenuItemCache = self.repoMenuItemCache.filter { usedRepoKeys.contains($0.key) }
            self.repoSubmenuCache = self.repoSubmenuCache.filter { usedRepoKeys.contains($0.key) }
            return items
        case .refreshNow:
            let shortcut = settings.keyboardShortcuts.refreshNow

            return [self.actionItem(
                title: self.t("Refresh Now"),
                action: #selector(self.target.refreshNow),
                keyEquivalent: shortcut.menuKeyEquivalent,
                keyEquivalentModifierMask: shortcut.menuKeyEquivalentModifierMask,
                systemImage: itemID.systemImage
            )]
        case .issueNavigator:
            guard case .loggedIn = session.account else { return [] }

            let shortcut = settings.keyboardShortcuts.issueNavigator

            return [self.actionItem(
                title: self.t("Issue Navigator…"),
                action: #selector(self.target.openIssueNavigator),
                keyEquivalent: shortcut.menuKeyEquivalent,
                keyEquivalentModifierMask: shortcut.menuKeyEquivalentModifierMask,
                systemImage: itemID.systemImage
            )]
        case .preferences:
            return [self.actionItem(
                title: self.t("Preferences…"),
                action: #selector(self.target.openPreferences),
                keyEquivalent: ",",
                systemImage: itemID.systemImage
            )]
        case .about:
            return [self.actionItem(
                title: self.t("About RepoPeek"),
                action: #selector(self.target.openAbout),
                systemImage: itemID.systemImage
            )]
        case .restartToUpdate:
            guard case .loggedIn = session.account else { return [] }
            guard SparkleController.shared.updateStatus.isUpdateReady else { return [] }

            return [self.actionItem(
                title: self.t("Restart to update"),
                action: #selector(self.target.checkForUpdates),
                systemImage: itemID.systemImage
            )]
        case .quit:
            return [self.actionItem(
                title: self.t("Quit RepoPeek"),
                action: #selector(self.target.quitApp),
                keyEquivalent: "q",
                systemImage: itemID.systemImage
            )]
        }
    }

    private func uniqueDisplayModels(_ repos: [RepositoryDisplayModel]) -> [RepositoryDisplayModel] {
        var seen: Set<String> = []
        return repos.filter { repo in
            seen.insert(repo.id.lowercased()).inserted
        }
    }

    func applyRepoListVisibility(in menu: NSMenu, query: String) {
        self.applyRepoListVisibility(
            in: menu.items,
            query: query,
            displayLimit: self.appState.session.settings.repoList.displayLimit
        )
    }

    private func applyRepoListVisibility(
        in items: [NSMenuItem],
        query rawQuery: String,
        displayLimit rawDisplayLimit: Int
    ) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = query.lowercased()
        let displayLimit = min(
            max(rawDisplayLimit, AppLimits.MainMenu.minimumRepositoryDisplayLimit),
            AppLimits.MainMenu.maximumRepositoryDisplayLimit
        )
        var visibleRepoItems: [NSMenuItem] = []

        for item in items where item.identifier == Self.repoMenuItemIdentifier {
            let title = self.repoFullName(from: item.representedObject) ?? ""
            let matches = normalizedQuery.isEmpty || title.lowercased().contains(normalizedQuery)
            let shouldShow = matches && visibleRepoItems.count < displayLimit
            item.isHidden = !shouldShow
            if shouldShow {
                visibleRepoItems.append(item)
            }
        }

        for item in items where item.identifier == Self.repoSeparatorItemIdentifier {
            item.isHidden = true
        }

        for item in visibleRepoItems.dropLast() {
            guard let index = items.firstIndex(where: { $0 === item }),
                  items.indices.contains(index + 1),
                  items[index + 1].identifier == Self.repoSeparatorItemIdentifier
            else { continue }

            items[index + 1].isHidden = false
        }

        for item in items where item.identifier == Self.repoEmptySearchItemIdentifier {
            item.isHidden = query.isEmpty || visibleRepoItems.isEmpty == false
        }
    }

    private func repoFullName(from representedObject: Any?) -> String? {
        if let context = representedObject as? RepoMenuActionContext {
            return context.fullName
        }

        return representedObject as? String
    }

    private func flattenMainMenuBlocks(_ blocks: [MainMenuBlock]) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        var lastGroup: MainMenuItemGroup?
        for block in blocks {
            guard block.items.isEmpty == false else { continue }

            if let lastGroup, lastGroup != block.group, items.isEmpty == false {
                let separator: NSMenuItem = block.group == .footer ? self.paddedSeparator() : .separator()
                items.append(separator)
            }
            items.append(contentsOf: block.items)
            lastGroup = block.group
        }
        return items
    }

    func refreshMenuViewHeights(in menu: NSMenu) {
        let signpost = self.signposter.beginInterval("refreshMenuViewHeights")
        defer { self.signposter.endInterval("refreshMenuViewHeights", signpost) }
        self.refreshMenuViewHeights(in: menu, width: self.menuWidth(for: menu))
    }

    func refreshMenuViewHeights(in menu: NSMenu, width: CGFloat) {
        let signpost = self.signposter.beginInterval("refreshMenuViewHeightsWidth")
        defer { self.signposter.endInterval("refreshMenuViewHeightsWidth", signpost) }
        for item in menu.items {
            guard let view = item.view,
                  let measuring = view as? MenuItemMeasuring else { continue }

            let height = measuring.measuredHeight(width: width)
            if abs(view.frame.size.height - height) > 0.5 || view.frame.size.width != width {
                view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
            }
        }
    }

    func clearHighlights(in menu: NSMenu) {
        for item in menu.items {
            (item.view as? MenuItemHighlighting)?.setHighlighted(false)
        }
    }

    func menuWidth(for menu: NSMenu) -> CGFloat {
        let signpost = self.signposter.beginInterval("menuWidth")
        defer { self.signposter.endInterval("menuWidth", signpost) }
        if let view = menu.items.compactMap(\.view).first {
            if let contentWidth = view.window?.contentView?.bounds.width, contentWidth > 0 {
                return max(contentWidth, Self.menuFixedWidth)
            }
            if let windowWidth = view.window?.frame.width, windowWidth > 0 {
                return max(windowWidth, Self.menuFixedWidth)
            }
        }
        let menuWidth = menu.size.width
        if menuWidth > 0 { return max(menuWidth, Self.menuFixedWidth) }
        return Self.menuFixedWidth
    }

    private func orderedViewModels(now: Date) -> [RepositoryDisplayModel] {
        let session = self.appState.session
        let selection = session.menuRepoSelection
        let settings = session.settings

        if selection.isLocalScope
            || self.shouldUseLocalMenuWithoutAccount(session)
            || self.shouldUseLocalRepositoryFallback(session)
        {
            return self.localScopeViewModels(session: session, settings: settings, now: now)
        }

        let scope: RepositoryScope = selection.isPinnedScope ? .pinned : .all
        let query = RepositoryQuery(
            scope: scope,
            onlyWith: selection.onlyWith,
            includeForks: settings.repoList.showForks,
            includeArchived: settings.repoList.showArchived,
            sortKey: settings.repoList.menuSortKey,
            limit: nil,
            pinned: settings.repoList.pinnedRepositories,
            hidden: Set(settings.repoList.hiddenRepositories),
            hiddenGroups: settings.repoList.hiddenGroups,
            accountScopedRepositoryLists: settings.repoList.accountScopedRepositoryLists,
            pinPriority: true
        )
        let baseRepos = session.repositories.isEmpty
            ? (session.menuSnapshot?.repositories ?? [])
            : session.repositories
        let sorted = RepositoryPipeline.apply(baseRepos, query: query)
        let displayIndex = session.menuDisplayIndex
        return sorted.map { repo in
            displayIndex[repo.lookupKey]
                ?? RepositoryDisplayModel(
                    repo: repo,
                    localStatus: session.localRepoIndex.status(for: repo),
                    now: now
                )
        }
    }

    private func localScopeViewModels(
        session: Session,
        settings: UserSettings,
        now: Date
    ) -> [RepositoryDisplayModel] {
        // Filter out worktrees - they appear in parent repo's "Switch Worktree" submenu
        let selection = self.effectiveLocalRepoSelection(session)
        let localRepos = self.filteredLocalRepos(
            session.localRepoIndex.all.filter { $0.worktreeName == nil },
            selection: selection,
            settings: settings
        )
        let displayIndex = session.menuDisplayIndex

        var models: [RepositoryDisplayModel] = []
        for localStatus in localRepos {
            guard let fullName = localStatus.fullName?.lowercased(),
                  let existingModel = displayIndex[fullName]
            else {
                let model = RepositoryDisplayModel(localStatus: localStatus, now: now)
                models.append(model)
                continue
            }

            models.append(existingModel)
        }

        return models.sorted {
            if selection.isPinnedScope,
               let left = $0.localStatus,
               let right = $1.localStatus
            {
                let leftOrder = self.localPinnedOrder(left, settings: settings)
                let rightOrder = self.localPinnedOrder(right, settings: settings)
                switch (leftOrder, rightOrder) {
                case let (left?, right?) where left != right:
                    return left < right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    break
                }
            }
            return RepositorySort.isOrderedBefore($0.source, $1.source, sortKey: settings.repoList.menuSortKey)
        }
    }

    private func effectiveLocalRepoSelection(_ session: Session) -> MenuRepoSelection {
        session.account.isLoggedIn ? session.menuRepoSelection : .local
    }

    private func filteredLocalRepos(
        _ statuses: [LocalRepoStatus],
        selection: MenuRepoSelection,
        settings: UserSettings
    ) -> [LocalRepoStatus] {
        switch selection {
        case .all, .local:
            statuses
        case .pinned:
            statuses.filter { self.localPinnedOrder($0, settings: settings) != nil }
        case .work:
            statuses.filter { $0.syncState != .synced }
        }
    }

    private func localPinnedOrder(_ status: LocalRepoStatus, settings: UserSettings) -> Int? {
        let candidates = self.localPinnedCandidates(for: status)
        return settings.repoList.allPinnedRepositories.enumerated().compactMap { index, pinned in
            candidates.contains(self.normalizedRepoName(pinned)) ? index : nil
        }.min()
    }

    private func localPinnedCandidates(for status: LocalRepoStatus) -> Set<String> {
        var candidates = Set<String>()
        candidates.insert(self.normalizedRepoName(status.name))
        candidates.insert(self.normalizedRepoName(status.displayName))
        if let fullName = status.fullName {
            candidates.insert(self.normalizedRepoName(fullName))
        }
        return candidates
    }

    private func normalizedRepoName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func emptyStateMessage(for session: Session) -> (String, String) {
        let hasPinned = session.settings.repoList.hasPinnedRepositories
        let isPinnedScope = session.menuRepoSelection.isPinnedScope
        let isLocalScope = session.menuRepoSelection.isLocalScope
            || self.shouldUseLocalMenuWithoutAccount(session)
            || self.shouldUseLocalRepositoryFallback(session)
        let hasFilter = session.menuRepoSelection.onlyWith.isActive
        if isPinnedScope, !hasPinned {
            return (self.t("No pinned repositories"), self.t("Pin a repository to see activity here."))
        }
        if isPinnedScope || hasFilter {
            return (self.t("No repositories match this filter"), self.t("Try All or a different filter."))
        }
        if isLocalScope {
            return (
                self.t("No local repositories"),
                self.t("Clone a repository or set your projects folder in Settings.")
            )
        }
        return (self.t("No repositories yet"), self.t("Pin a repository to see activity here."))
    }

    private func shouldUseLocalMenuWithoutAccount(_ session: Session) -> Bool {
        !session.account.isLoggedIn && self.hasConfiguredLocalProjects(session)
    }

    private func shouldUseLocalRepositoryFallback(_ session: Session) -> Bool {
        let hasInitialRemoteFailure = session.account.isLoggedIn
            && !session.hasLoadedRepositories
            && !(session.lastError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        return hasInitialRemoteFailure && self.hasConfiguredLocalProjects(session)
    }

    private func hasConfiguredLocalProjects(_ session: Session) -> Bool {
        guard let rootPath = session.settings.localProjects.rootPath else { return false }

        return !rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func t(_ key: String) -> String {
        L10n.t(key, settings: self.appState.session.settings)
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, settings: self.appState.session.settings, arguments)
    }

    func format(_ key: String, _ arguments: [CVarArg]) -> String {
        L10n.format(key, settings: self.appState.session.settings, arguments)
    }

    private func currentUsername() -> String? {
        if case let .loggedIn(user) = self.appState.session.account { return user.username }
        return nil
    }

    private func currentDisplayName() -> String? {
        if case let .loggedIn(user) = self.appState.session.account { return user.username }
        return nil
    }

    var isLightAppearance: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }

        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }
}
