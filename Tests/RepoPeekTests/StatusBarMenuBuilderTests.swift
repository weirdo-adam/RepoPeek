import AppKit
import Foundation
@testable import RepoPeek
import RepoPeekCore
import Testing

struct StatusBarMenuBuilderTests {
    @Test
    func `work filter label uses compact wording`() {
        #expect(MenuRepoSelection.work.label == "Work")
    }

    @Test
    func `repository filters expose menu sort control`() {
        #expect(MenuRepoSelection.local.showsSortControl)
        #expect(MenuRepoSelection.all.showsSortControl)
        #expect(MenuRepoSelection.pinned.showsSortControl)
        #expect(MenuRepoSelection.work.showsSortControl)
    }

    @Test
    func `repository search input is offered whenever repositories are present`() {
        #expect(MenuRepoFiltersView.offersSearch(
            repositoryCandidateCount: 0,
            hasSearchQuery: false
        ) == false)
        #expect(MenuRepoFiltersView.offersSearch(
            repositoryCandidateCount: 1,
            hasSearchQuery: false
        ))
        #expect(MenuRepoFiltersView.offersSearch(repositoryCandidateCount: 0, hasSearchQuery: true))
    }

    @Test
    func `repository search field is fixed in the filter bar`() {
        #expect(MenuRepoFiltersView.showsSearchField(
            repositoryCandidateCount: 1,
            hasSearchQuery: false,
            isExpanded: false
        ))
        #expect(MenuRepoFiltersView.showsSearchField(
            repositoryCandidateCount: 1,
            hasSearchQuery: false,
            isExpanded: true
        ))
        #expect(MenuRepoFiltersView.showsSearchField(
            repositoryCandidateCount: 1,
            hasSearchQuery: true,
            isExpanded: false
        ))
    }

    @MainActor
    @Test
    func `main menu search lets focused text inputs handle key events`() {
        #expect(StatusBarMenuManager.isTextInputResponderType(NSTextView.self))
        #expect(StatusBarMenuManager.isTextInputResponderType(NSSearchField.self))
        #expect(!StatusBarMenuManager.isTextInputResponderType(NSButton.self))
    }

    @MainActor
    @Test
    func `logged out local menu shows local repositories without sign in chrome`() {
        let appState = AppState()
        appState.session.account = .loggedOut
        appState.session.menuRepoSelection = .all
        appState.session.settings.localProjects.rootPath = "/tmp/projects"
        appState.session.settings.repoList.menuSortKey = .name
        appState.session.localRepoIndex = LocalRepoIndex(statuses: [
            Self.makeLocalStatus(name: "beta", fullName: "example/beta"),
            Self.makeLocalStatus(name: "alpha", fullName: "example/alpha")
        ])

        let manager = StatusBarMenuManager(appState: appState)
        let plan = manager.mainMenuPlanForTesting()
        let menu = NSMenu()
        manager.populateMainMenuForTesting(menu, repos: plan.repos)

        #expect(plan.repos.map(\.title) == ["example/alpha", "example/beta"])
        #expect(Self.visibleRepresentedTitles(in: menu) == ["example/alpha", "example/beta"])
        #expect(menu.items.first?.view != nil)
        #expect(menu.items.first?.representedObject == nil)
        #expect(!menu.items.contains { $0.title == "Sign in to GitLab" })
    }

    @MainActor
    @Test
    func `issue navigator menu item uses configured shortcut`() throws {
        let host = try #require(URL(string: "https://gitlab.com"))
        let appState = AppState()
        appState.session.account = .loggedIn(UserIdentity(
            username: "alice",
            host: host
        ))
        appState.session.hasLoadedRepositories = true
        appState.session.settings.keyboardShortcuts.issueNavigator = .commandShiftF

        let manager = StatusBarMenuManager(appState: appState)
        let plan = manager.mainMenuPlanForTesting()
        let menu = NSMenu()
        manager.populateMainMenuForTesting(menu, repos: plan.repos)

        let item = try #require(menu.items.first { $0.title == "Issue Navigator…" })
        #expect(item.keyEquivalent == "f")
        #expect(item.keyEquivalentModifierMask.contains(.command))
        #expect(item.keyEquivalentModifierMask.contains(.shift))
        #expect(!item.keyEquivalentModifierMask.contains(.option))
    }

    @MainActor
    @Test
    func `refresh now menu item uses configured shortcut`() throws {
        let host = try #require(URL(string: "https://gitlab.com"))
        let appState = AppState()
        appState.session.account = .loggedIn(UserIdentity(
            username: "alice",
            host: host
        ))
        appState.session.hasLoadedRepositories = true
        appState.session.settings.keyboardShortcuts.refreshNow = MenuKeyboardShortcut(
            key: "u",
            modifiers: [.command, .option]
        )

        let manager = StatusBarMenuManager(appState: appState)
        let plan = manager.mainMenuPlanForTesting()
        let menu = NSMenu()
        manager.populateMainMenuForTesting(menu, repos: plan.repos)

        let item = try #require(menu.items.first { $0.title == "Refresh Now" })
        #expect(item.keyEquivalent == "u")
        #expect(item.keyEquivalentModifierMask.contains(.command))
        #expect(item.keyEquivalentModifierMask.contains(.option))
        #expect(!item.keyEquivalentModifierMask.contains(.shift))
    }

    @MainActor
    @Test
    func `footer action menu items have icons`() throws {
        let host = try #require(URL(string: "https://gitlab.com"))
        let appState = AppState()
        appState.session.account = .loggedIn(UserIdentity(
            username: "alice",
            host: host
        ))
        appState.session.hasLoadedRepositories = true

        let manager = StatusBarMenuManager(appState: appState)
        let plan = manager.mainMenuPlanForTesting()
        let menu = NSMenu()
        manager.populateMainMenuForTesting(menu, repos: plan.repos)

        for title in [
            "Refresh Now",
            "Issue Navigator…",
            "Preferences…",
            "About RepoPeek",
            "Quit RepoPeek"
        ] {
            let item = try #require(menu.items.first { $0.title == title })
            #expect(item.image != nil)
            #expect(item.image?.isTemplate == true)
        }
    }

    @MainActor
    @Test
    func `all repository tab keeps menu visibility within configured display limit`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let host = try #require(URL(string: "https://gitlab.com"))
        let appState = AppState()
        appState.session.account = .loggedIn(UserIdentity(
            username: "alice",
            host: host
        ))
        appState.session.hasLoadedRepositories = true
        appState.session.settings.repoList.displayLimit = 2
        appState.session.settings.repoList.menuSortKey = .activity
        appState.session.menuRepoSelection = .all
        appState.session.repositories = (0 ..< 5).map { index in
            Self.makeRepository(
                id: "\(index)",
                owner: "example",
                name: "repo-\(index)",
                pushedAt: now.addingTimeInterval(TimeInterval(index))
            )
        }

        let manager = StatusBarMenuManager(appState: appState)
        let plan = manager.mainMenuPlanForTesting(now: now)
        let menu = NSMenu()
        manager.populateMainMenuForTesting(menu, repos: plan.repos)

        #expect(Self.visibleRepositoryTitles(in: menu) == ["example/repo-4", "example/repo-3"])
    }

    @MainActor
    @Test
    func `repository menu search filters visible rows`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let host = try #require(URL(string: "https://gitlab.com"))
        let appState = AppState()
        appState.session.account = .loggedIn(UserIdentity(
            username: "alice",
            host: host
        ))
        appState.session.hasLoadedRepositories = true
        appState.session.settings.repoList.displayLimit = 2
        appState.session.settings.repoList.menuSortKey = .activity
        appState.session.menuRepoSelection = .all
        appState.session.menuRepoSearchQuery = "repo-1"
        appState.session.repositories = (0 ..< 5).map { index in
            Self.makeRepository(
                id: "\(index)",
                owner: "example",
                name: "repo-\(index)",
                pushedAt: now.addingTimeInterval(TimeInterval(index))
            )
        }

        let manager = StatusBarMenuManager(appState: appState)
        let plan = manager.mainMenuPlanForTesting(now: now)
        let menu = NSMenu()
        manager.populateMainMenuForTesting(menu, repos: plan.repos)

        #expect(Self.visibleRepositoryTitles(in: menu) == ["example/repo-1"])
    }

    @MainActor
    @Test
    func `repository menu search can match beyond first eighty repositories`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let host = try #require(URL(string: "https://gitlab.com"))
        let appState = AppState()
        appState.session.account = .loggedIn(UserIdentity(
            username: "alice",
            host: host
        ))
        appState.session.hasLoadedRepositories = true
        appState.session.settings.repoList.displayLimit = 2
        appState.session.settings.repoList.menuSortKey = .activity
        appState.session.menuRepoSelection = .all
        appState.session.menuRepoSearchQuery = "repo-001"
        appState.session.repositories = (0 ..< 120).map { index in
            Self.makeRepository(
                id: "\(index)",
                owner: "example",
                name: "repo-\(String(format: "%03d", index))",
                pushedAt: now.addingTimeInterval(TimeInterval(index))
            )
        }

        let manager = StatusBarMenuManager(appState: appState)
        let plan = manager.mainMenuPlanForTesting(now: now)
        let menu = NSMenu()
        manager.populateMainMenuForTesting(menu, repos: plan.repos)

        #expect(Self.visibleRepositoryTitles(in: menu) == ["example/repo-001"])
    }

    @MainActor
    @Test
    func `repository list uses cached snapshot while first refresh is pending`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let host = try #require(URL(string: "https://gitlab.com"))
        let appState = AppState()
        appState.session.account = .loggedIn(UserIdentity(
            username: "alice",
            host: host
        ))
        appState.session.hasLoadedRepositories = false
        appState.session.settings.repoList.displayLimit = 2
        appState.session.menuRepoSelection = .all
        appState.session.menuSnapshot = MenuSnapshot(
            repositories: [
                Self.makeRepository(
                    id: "cached-1",
                    owner: "example",
                    name: "repo-cached",
                    pushedAt: now
                )
            ],
            capturedAt: now.addingTimeInterval(-300)
        )

        let manager = StatusBarMenuManager(appState: appState)
        let plan = manager.mainMenuPlanForTesting(now: now)
        let menu = NSMenu()
        manager.populateMainMenuForTesting(menu, repos: plan.repos)

        #expect(Self.visibleRepositoryTitles(in: menu) == ["example/repo-cached"])
    }

    @MainActor
    @Test
    func `first remote load failure falls back to configured local repositories`() throws {
        let host = try #require(URL(string: "https://gitlab.example.com"))
        let appState = AppState()
        appState.session.account = .loggedIn(UserIdentity(
            username: "alice",
            host: host
        ))
        appState.session.hasLoadedRepositories = false
        appState.session.lastError = "Request timed out."
        appState.session.menuRepoSelection = .all
        appState.session.settings.appearance.showContributionHeader = false
        appState.session.settings.localProjects.rootPath = "/tmp/projects"
        appState.session.settings.repoList.menuSortKey = .name
        appState.session.settings.repoList.pinnedRepositories = ["example/beta"]
        appState.session.localRepoIndex = LocalRepoIndex(statuses: [
            Self.makeLocalStatus(name: "beta", fullName: "example/beta"),
            Self.makeLocalStatus(name: "alpha", fullName: "example/alpha", syncState: .dirty)
        ])

        let manager = StatusBarMenuManager(appState: appState)
        let menu = NSMenu()

        let plan = manager.mainMenuPlanForTesting()
        manager.populateMainMenuForTesting(menu, repos: plan.repos)

        #expect(plan.repos.map(\.title) == ["example/alpha", "example/beta"])
        #expect(Self.visibleRepresentedTitles(in: menu) == ["example/alpha", "example/beta"])
        #expect(Self.visibleUnrepresentedViewItemCount(in: menu) == 4)

        appState.session.menuRepoSelection = .pinned
        let pinnedPlan = manager.mainMenuPlanForTesting()
        manager.populateMainMenuForTesting(menu, repos: pinnedPlan.repos)
        #expect(pinnedPlan.repos.map(\.title) == ["example/beta"])
        #expect(Self.visibleRepresentedTitles(in: menu) == ["example/beta"])

        appState.session.menuRepoSelection = .work
        let workPlan = manager.mainMenuPlanForTesting()
        manager.populateMainMenuForTesting(menu, repos: workPlan.repos)
        #expect(workPlan.repos.map(\.title) == ["example/alpha"])
        #expect(Self.visibleRepresentedTitles(in: menu) == ["example/alpha"])
    }

    @MainActor
    @Test
    func `background refresh keeps cached repository cards quiet`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let host = try #require(URL(string: "https://gitlab.com"))
        let appState = AppState()
        appState.session.account = .loggedIn(UserIdentity(
            username: "alice",
            host: host
        ))
        appState.session.hasLoadedRepositories = true
        appState.session.isRefreshingRepositories = true
        appState.session.settings.appearance.showContributionHeader = false
        appState.session.repositories = [
            Self.makeRepository(
                id: "refreshing-1",
                owner: "example",
                name: "repo-refreshing",
                pushedAt: now
            )
        ]

        let manager = StatusBarMenuManager(appState: appState)
        let plan = manager.mainMenuPlanForTesting(now: now)
        let menu = NSMenu()
        manager.populateMainMenuForTesting(menu, repos: plan.repos)

        #expect(Self.itemIndex(in: menu, identifier: "RepoPeekRepoRefreshingItem") == nil)
        #expect(Self.repositoryItemIndex(in: menu, title: "example/repo-refreshing") != nil)
    }

    @MainActor
    @Test
    func `healthy GitLab API status is omitted from main menu`() throws {
        let host = try #require(URL(string: "https://gitlab.com"))
        let appState = AppState()
        appState.session.account = .loggedIn(UserIdentity(
            username: "alice",
            host: host
        ))
        appState.session.hasLoadedRepositories = true
        appState.session.settings.appearance.showContributionHeader = false

        let manager = StatusBarMenuManager(appState: appState)
        let plan = manager.mainMenuPlanForTesting()
        let menu = NSMenu()
        manager.populateMainMenuForTesting(menu, repos: plan.repos)

        #expect(Self.hasMenuItemSubmenu(in: menu) == false)
    }

    @MainActor
    @Test
    func `blocked GitLab API status remains visible in main menu`() throws {
        let host = try #require(URL(string: "https://gitlab.com"))
        let appState = AppState()
        appState.session.account = .loggedIn(UserIdentity(
            username: "alice",
            host: host
        ))
        appState.session.hasLoadedRepositories = true
        appState.session.settings.appearance.showContributionHeader = false
        let apiHost = try #require(URL(string: "https://gitlab.com/api/v4"))
        appState.session.rateLimitDiagnostics = DiagnosticsSummary(
            apiHost: apiHost,
            rateLimitReset: Date().addingTimeInterval(600),
            lastRateLimitError: "GitLab rate limit hit; resets in 10 min.",
            etagEntries: 0,
            backoffEntries: 0,
            restRateLimit: nil
        )

        let manager = StatusBarMenuManager(appState: appState)
        let plan = manager.mainMenuPlanForTesting()
        let menu = NSMenu()
        manager.populateMainMenuForTesting(menu, repos: plan.repos)

        #expect(Self.hasMenuItemSubmenu(in: menu))
    }

    private static func visibleRepositoryTitles(in menu: NSMenu) -> [String] {
        menu.items
            .filter { !$0.isHidden }
            .compactMap(self.representedTitle)
            .filter { $0.contains("repo-") }
    }

    private static func visibleRepresentedTitles(in menu: NSMenu) -> [String] {
        menu.items
            .filter { !$0.isHidden }
            .compactMap(self.representedTitle)
    }

    private static func representedTitle(for item: NSMenuItem) -> String? {
        if let context = item.representedObject as? RepoMenuActionContext {
            return context.fullName
        }

        return item.representedObject as? String
    }

    private static func visibleUnrepresentedViewItemCount(in menu: NSMenu) -> Int {
        menu.items.count { item in
            !item.isHidden && item.view != nil && item.representedObject == nil
        }
    }

    private static func hasMenuItemSubmenu(in menu: NSMenu) -> Bool {
        menu.items.contains { $0.submenu != nil }
    }

    private static func itemIndex(in menu: NSMenu, identifier: String) -> Int? {
        menu.items.firstIndex {
            $0.identifier == NSUserInterfaceItemIdentifier(identifier)
        }
    }

    private static func repositoryItemIndex(in menu: NSMenu, title: String) -> Int? {
        menu.items.firstIndex {
            self.representedTitle(for: $0) == title
        }
    }

    private static func makeRepository(id: String, owner: String, name: String, pushedAt: Date) -> Repository {
        Repository(
            id: id,
            name: name,
            owner: owner,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 0,
            pushedAt: pushedAt,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
    }

    private static func makeLocalStatus(
        name: String,
        fullName: String,
        syncState: LocalSyncState = .synced
    ) -> LocalRepoStatus {
        LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/projects/\(name)"),
            name: name,
            fullName: fullName,
            branch: "release",
            isClean: syncState != .dirty,
            aheadCount: 0,
            behindCount: 0,
            syncState: syncState
        )
    }
}
