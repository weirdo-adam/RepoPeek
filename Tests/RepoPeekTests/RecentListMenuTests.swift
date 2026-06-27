import AppKit
@testable import RepoPeek
import RepoPeekCore
import Testing

struct RecentListMenuTests {
    @MainActor
    @Test
    func `recent list cache evicts least recently used entry`() {
        let cache = RecentListCache<Int>(maxEntries: 2)
        let now = Date(timeIntervalSinceReferenceDate: 1000)

        cache.store([1], for: "one", fetchedAt: now)
        cache.store([2], for: "two", fetchedAt: now)
        #expect(cache.stale(for: "one") == [1])
        cache.store([3], for: "three", fetchedAt: now)

        #expect(cache.count() == 2)
        #expect(cache.stale(for: "one") == [1])
        #expect(cache.stale(for: "two") == nil)
        #expect(cache.stale(for: "three") == [3])
    }

    @MainActor
    @Test
    func `recent list menus survive main menu open`() {
        let appState = AppState()
        let manager = StatusBarMenuManager(appState: appState)
        let mainMenu = NSMenu()
        let submenu = NSMenu()

        manager.setMainMenuForTesting(mainMenu)
        manager.registerRecentListMenu(
            submenu,
            context: RepoRecentMenuContext(fullName: "owner/repo", kind: .issues)
        )

        manager.menuWillOpen(mainMenu)

        #expect(manager.isRecentListMenu(submenu))
    }

    @MainActor
    @Test
    func `recent list menus survive filter rebuild`() async throws {
        let appState = AppState()
        let manager = StatusBarMenuManager(appState: appState)
        let mainMenu = NSMenu()
        let submenu = NSMenu()

        manager.setMainMenuForTesting(mainMenu)
        manager.registerRecentListMenu(
            submenu,
            context: RepoRecentMenuContext(fullName: "owner/repo", kind: .issues)
        )

        manager.menuFiltersChanged()
        try await Task.sleep(for: .milliseconds(50))

        #expect(manager.isRecentListMenu(submenu))
    }

    @MainActor
    @Test
    func `recent list failures show user facing reason`() {
        let error = GitLabAPIError.badStatus(code: 403, message: "Requires repository issues access.")

        #expect(
            RecentListMenuCoordinator.failureMessage(for: error) ==
                "Failed: Requires repository issues access."
        )
    }

    @MainActor
    @Test
    func `recent list timeouts include configured seconds`() {
        #expect(RecentListMenuCoordinator.timeoutMessage(timeout: 12) == "Timed out after 12s")
    }

    @MainActor
    @Test
    func `recent list rate limit message is not derived from GitLab errors`() {
        let error = GitLabAPIError.badStatus(code: 429, message: "GitLab rate limit hit.")

        #expect(RecentListMenuCoordinator.rateLimitMessage(for: error) == nil)
        #expect(RecentListMenuCoordinator.rateLimitMessage(for: URLError(.timedOut)) == nil)
    }

    @MainActor
    @Test
    func `multi reference menu offers issue navigator action at end`() throws {
        let appState = AppState()
        let manager = StatusBarMenuManager(appState: appState)
        let menu = NSMenu()
        let matches = try [
            Self.makeReference(number: 1),
            Self.makeReference(number: 2)
        ]

        manager.populateGitLabReferenceMenuForTesting(menu, matches: matches)

        let titles = menu.items.map(\.title)
        #expect(Array(titles.suffix(2)) == ["", "Open 2 refs in Issue Navigator…"])
        #expect(menu.items.last?.target === manager)
        #expect(menu.items.last?.action == #selector(StatusBarMenuManager.openGitLabReferenceMatchesInIssueNavigator))
    }

    @MainActor
    @Test
    func `multi reference status item uses click action instead of attached menu`() throws {
        let appState = AppState()
        let manager = StatusBarMenuManager(appState: appState)
        let matches = try [
            Self.makeReference(number: 1),
            Self.makeReference(number: 2)
        ]

        appState.session.gitLabReferenceMatches = matches
        appState.session.gitLabReferenceMatch = matches.first
        manager.syncGitLabReferenceStatusItemForTesting()

        let item = try #require(manager.gitLabReferenceStatusItemForTesting())
        let button = try #require(item.button)
        #expect(item.menu == nil)
        #expect(button.target === manager)
        #expect(button.action == #selector(StatusBarMenuManager.gitLabReferenceStatusItemClicked(_:)))
    }

    private static func makeReference(number: Int) throws -> GitLabReferenceMatch {
        let url = try #require(URL(string: "https://gitlab.com/owner/repo/-/issues/\(number)"))
        return GitLabReferenceMatch(
            query: .repositoryIssueNumber(repositoryFullName: "owner/repo", number: number),
            title: "Issue \(number)",
            url: url,
            repositoryFullName: "owner/repo",
            kind: .issue,
            state: .open,
            createdAt: Date(timeIntervalSinceReferenceDate: TimeInterval(number)),
            updatedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(number))
        )
    }
}
