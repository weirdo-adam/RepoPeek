import Foundation
import RepoPeekCore
import Testing

struct UserSettingsCoverageTests {
    @Test
    func `labels and seconds cover enum switches`() {
        #expect(LocalProjectsRefreshInterval.oneMinute.seconds == 60)
        #expect(LocalProjectsRefreshInterval.fifteenMinutes.seconds == 900)
        #expect(LocalProjectsRefreshInterval.oneHour.seconds == 3600)
        #expect(LocalProjectsRefreshInterval.twoMinutes.label == "2 minutes")
        #expect(LocalProjectsSettings().maxDepth == LocalProjectsConstants.defaultMaxDepth)

        #expect(GhosttyOpenMode.newWindow.label == "New Window")
        #expect(GhosttyOpenMode.tab.label == "Tab")

        #expect(RefreshInterval.thirtyMinutes.seconds == 1800)
        #expect(RefreshInterval.oneHour.seconds == 3600)
        #expect(RefreshInterval.sixHours.seconds == 21600)
        #expect(RefreshInterval.twelveHours.seconds == 43200)
        #expect(RefreshInterval.oneDay.seconds == 86400)
        #expect(RefreshInterval.oneDay.label == "1 day")

        #expect(HeatmapDisplay.inline.label == "Inline")
        #expect(HeatmapDisplay.submenu.label == "Submenu")

        #expect(CardDensity.comfortable.label == "Comfortable")
        #expect(CardDensity.compact.label == "Compact")

        #expect(AccentTone.system.label == "System accent")
        #expect(AccentTone.gitlabGreen.label == "Contribution greens")
        #expect(AppearanceSettings().showRateLimitMeterInMenuBar)
        #expect(GitLabReferenceMonitorSettings().enabled == false)
        #expect(GitLabPullRequestNotificationSettings().enabled == false)
        #expect(GitLabPullRequestNotificationSettings().newPullRequests)
        #expect(GitLabPullRequestNotificationSettings().pullRequestUpdates)
        #expect(GitLabPullRequestNotificationSettings().reviewRequests == false)
        #expect(GitLabPullRequestNotificationSettings().comments == false)
        #expect(GitLabPullRequestNotificationSettings().clickAction == .openInBrowser)
        #expect(GitLabPullRequestNotificationClickAction.openInBrowser.label == "Default browser")
        #expect(GitLabPullRequestNotificationClickAction.openIssueNavigator.label == "Issue Navigator")

        #expect(GlobalActivityScope.allActivity.label == "All activity")
        #expect(GlobalActivityScope.myActivity.label == "My activity")

        #expect(GitLabArchiveSettings().preferArchiveWhenRateLimited)
        #expect(GitLabArchiveFormat.discrawlSnapshot.label == "Discrawl snapshot")
        #expect(KeyboardShortcutSettings().issueNavigator == .commandF)
        #expect(KeyboardShortcutSettings().refreshNow == .commandR)
        #expect(MenuKeyboardShortcut.commandF.label == "⌘F")
        #expect(MenuKeyboardShortcut.commandShiftF.label == "⌘⇧F")
        #expect(MenuKeyboardShortcut.commandOptionF.label == "⌘⌥F")
        #expect(MenuKeyboardShortcut.controlF.label == "⌃F")
        #expect(MenuKeyboardShortcut.none.label == "None")

        #expect(AppLanguage.system.localeIdentifier == nil)
        #expect(AppLanguage.english.localeIdentifier == "en")
        #expect(AppLanguage.simplifiedChinese.localeIdentifier == "zh-Hans")
    }

    @Test
    func `keyboard shortcuts decode defaults legacy issue navigator and custom refresh shortcut`() throws {
        let legacyData = Data("{}".utf8)
        let legacySettings = try JSONDecoder().decode(UserSettings.self, from: legacyData)
        #expect(legacySettings.keyboardShortcuts.issueNavigator == .commandF)
        #expect(legacySettings.keyboardShortcuts.refreshNow == .commandR)

        let customData = Data("""
        {
          "keyboardShortcuts": {
            "issueNavigator": "commandShiftF",
            "refreshNow": {
              "key": "u",
              "modifiers": ["command", "option"]
            }
          }
        }
        """.utf8)
        let customSettings = try JSONDecoder().decode(UserSettings.self, from: customData)
        #expect(customSettings.keyboardShortcuts.issueNavigator == .commandShiftF)
        #expect(customSettings.keyboardShortcuts.refreshNow == MenuKeyboardShortcut(
            key: "u",
            modifiers: [.command, .option]
        ))
    }

    @Test
    func `legacy gitlab host migrates to account settings`() throws {
        let data = Data("""
        {
          "gitlabHost": "https://code.company.com/gitlab/"
        }
        """.utf8)

        let settings = try JSONDecoder().decode(UserSettings.self, from: data)

        let account = try #require(settings.gitlabAccounts.first)
        #expect(settings.gitlabAccounts.count == 1)
        #expect(account.host.absoluteString == "https://code.company.com/gitlab")
        #expect(account.hostKey == "code.company.com/gitlab")
        #expect(settings.gitlabHost == account.host)
    }

    @Test
    func `gitlab accounts normalize and dedupe by host key`() throws {
        let data = Data("""
        {
          "gitlabAccounts": [
            {"id": "one", "name": "One", "host": "https://code.company.com/gitlab/", "enabled": true},
            {"id": "two", "name": "Two", "host": "https://code.company.com/gitlab", "enabled": true},
            {"id": "three", "name": "Three", "host": "https://gitlab.com", "enabled": false}
          ]
        }
        """.utf8)

        let settings = try JSONDecoder().decode(UserSettings.self, from: data)

        #expect(settings.gitlabAccounts.map(\.hostKey) == ["code.company.com/gitlab", "gitlab.com"])
        #expect(settings.gitlabAccounts.first?.id == "one")
    }

    @Test
    func `gitlab accounts allow same host when usernames differ`() throws {
        let data = Data("""
        {
          "gitlabAccounts": [
            {"id": "alice", "name": "Alice", "host": "https://code.company.com/gitlab/", "username": "Alice", "enabled": true},
            {"id": "bob", "name": "Bob", "host": "https://code.company.com/gitlab", "username": "bob", "enabled": true},
            {"id": "alice-copy", "name": "Alice Copy", "host": "https://code.company.com/gitlab", "username": "alice", "enabled": true}
          ]
        }
        """.utf8)

        let settings = try JSONDecoder().decode(UserSettings.self, from: data)

        #expect(settings.gitlabAccounts.map(\.accountID) == [
            "code.company.com/gitlab#alice",
            "code.company.com/gitlab#bob"
        ])
        #expect(settings.gitlabAccounts.map(\.hostKey) == [
            "code.company.com/gitlab",
            "code.company.com/gitlab"
        ])
    }

    @Test
    func `explicit empty gitlab accounts remain empty`() throws {
        let data = Data("""
        {
          "gitlabHost": "https://gitlab.com",
          "gitlabAccounts": []
        }
        """.utf8)

        let settings = try JSONDecoder().decode(UserSettings.self, from: data)

        #expect(settings.gitlabAccounts.isEmpty)
        #expect(settings.gitlabHost.absoluteString == "https://gitlab.com")
    }

    @Test
    func `repo list account scoped rules override global rules per account`() {
        var repoList = RepoListSettings()
        repoList.pinnedRepositories = ["global/repo"]
        repoList.hiddenGroups = ["global/private"]
        repoList.setPinnedRepositories(["team/alice"], forAccountID: "gitlab.example.com#alice")
        repoList.setPinnedRepositories([], forAccountID: "gitlab.example.com#bob")
        repoList.setHiddenGroups(["team/private"], forAccountID: "gitlab.example.com#alice")

        #expect(repoList.pinnedRepositories(forAccountID: nil) == ["global/repo"])
        #expect(repoList.pinnedRepositories(forAccountID: "gitlab.example.com#carol") == ["global/repo"])
        #expect(repoList.pinnedRepositories(forAccountID: "gitlab.example.com#alice") == ["team/alice"])
        #expect(repoList.pinnedRepositories(forAccountID: "gitlab.example.com#bob").isEmpty)
        #expect(repoList.hiddenGroups(forAccountID: "gitlab.example.com#alice") == ["team/private"])
        #expect(repoList.hiddenGroups(forAccountID: "gitlab.example.com#bob") == ["global/private"])
        #expect(repoList.allPinnedRepositories == ["global/repo", "team/alice"])
    }

    @Test
    func `menu normalization keeps rate limits above filters`() throws {
        var customization = MenuCustomization()
        customization.mainMenuOrder = [
            .loggedOutPrompt,
            .signInAction,
            .contributionHeader,
            .statusBanner,
            .filters,
            .repoList,
            .issueNavigator,
            .preferences,
            .about,
            .restartToUpdate,
            .quit
        ]

        customization.normalize()

        let statusIndex = try #require(customization.mainMenuOrder.firstIndex(of: .statusBanner))
        let rateIndex = try #require(customization.mainMenuOrder.firstIndex(of: .rateLimits))
        let filterIndex = try #require(customization.mainMenuOrder.firstIndex(of: .filters))
        let repoListIndex = try #require(customization.mainMenuOrder.firstIndex(of: .repoList))
        let refreshIndex = try #require(customization.mainMenuOrder.firstIndex(of: .refreshNow))
        #expect(statusIndex < rateIndex)
        #expect(rateIndex < filterIndex)
        #expect(repoListIndex < refreshIndex)
    }

    @Test
    func `default repo submenu order has no duplicates`() {
        var seen = Set<RepoSubmenuItemID>()

        for item in MenuCustomization.defaultRepoSubmenuOrder {
            #expect(seen.insert(item).inserted)
        }
    }

    @Test
    func `archive source derives internal fields from repo`() throws {
        let shorthand = try #require(GitLabArchiveStore.source(repository: "example/archive"))
        #expect(shorthand.name == "example/archive")
        #expect(shorthand.remoteURL == "https://gitlab.com/example/archive.git")
        #expect(shorthand.localRepositoryPath == nil)
        #expect(shorthand.importedDatabasePath.contains("/RepoPeek/Archives/example-archive-"))
        #expect(shorthand.importedDatabasePath.hasSuffix(".sqlite"))

        let ssh = try #require(GitLabArchiveStore.source(repository: "git@gitlab.com:example/RepoPeek.git"))
        #expect(ssh.name == "example/RepoPeek")
        #expect(ssh.remoteURL == "git@gitlab.com:example/RepoPeek.git")

        let local = try #require(GitLabArchiveStore.source(repository: "/tmp/RepoPeekArchive.git/"))
        #expect(local.name == "RepoPeekArchive")
        #expect(local.remoteURL == nil)
        #expect(local.localRepositoryPath == "/tmp/RepoPeekArchive.git")

        let colliding = try #require(GitLabArchiveStore.source(repository: "/tmp/example-archive"))
        #expect(colliding.name == "example-archive")
        #expect(colliding.importedDatabasePath != shorthand.importedDatabasePath)
    }

    @Test
    func `archive location matching ignores nil optionals`() throws {
        let firstRemote = try #require(GitLabArchiveStore.source(repository: "example/archive"))
        let secondRemote = try #require(GitLabArchiveStore.source(repository: "example/RepoPeek"))
        let firstLocal = try #require(GitLabArchiveStore.source(repository: "/tmp/archive-one"))
        let secondLocal = try #require(GitLabArchiveStore.source(repository: "/tmp/archive-two"))
        let sameLeafLocal = try #require(GitLabArchiveStore.source(repository: "/Volumes/backup/archive-one"))

        #expect(GitLabArchiveStore.sameArchiveLocation(firstRemote, firstRemote))
        #expect(GitLabArchiveStore.sameArchiveLocation(firstRemote, secondRemote) == false)
        #expect(GitLabArchiveStore.sameArchiveLocation(firstLocal, secondLocal) == false)
        #expect(GitLabArchiveStore.sameArchiveLocation(firstLocal, sameLeafLocal) == false)
    }
}
