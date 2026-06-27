import Foundation
import RepoPeekCore
import Testing

struct SettingsStoreCoverageTests {
    @Test
    func `load returns defaults when missing`() throws {
        let suiteName = "SettingsStoreCoverageTests.missing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)
        let settings = store.load()
        #expect(settings == UserSettings())
    }

    @Test
    func `save and load round trips`() throws {
        let suiteName = "SettingsStoreCoverageTests.roundtrip.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)

        var settings = UserSettings()
        settings.repoList.displayLimit = 9
        settings.gitLabReferenceMonitor.enabled = true
        settings.gitLabPullRequestNotifications.enabled = true
        settings.gitLabPullRequestNotifications.reviewRequests = true
        settings.gitLabPullRequestNotifications.clickAction = .openIssueNavigator
        settings.aiSummaries.enabled = true
        settings.aiSummaries.provider = .claudeCode
        settings.aiSummaries.model = "opus"
        settings.aiSummaries.requestURL = URL(string: "https://ai.example.com/v1/responses")
        settings.gitlabHost = try #require(URL(string: "https://gitlab.example.com"))
        settings.gitlabArchives.sources = [
            GitLabArchiveSource(
                name: "example",
                localRepositoryPath: "~/Backups/example",
                remoteURL: "https://gitlab.com/example/example-backup.git",
                importedDatabasePath: "/tmp/example.sqlite"
            )
        ]
        store.save(settings)

        let loaded = store.load()
        #expect(loaded.repoList.displayLimit == 9)
        #expect(loaded.gitLabReferenceMonitor.enabled)
        #expect(loaded.gitLabPullRequestNotifications.enabled)
        #expect(loaded.gitLabPullRequestNotifications.reviewRequests)
        #expect(loaded.gitLabPullRequestNotifications.clickAction == .openIssueNavigator)
        #expect(loaded.aiSummaries.enabled)
        #expect(loaded.aiSummaries.provider == .claudeCode)
        #expect(loaded.aiSummaries.model == "opus")
        #expect(loaded.aiSummaries.requestURL == URL(string: "https://ai.example.com/v1/responses"))
        #expect(loaded.gitlabHost == URL(string: "https://gitlab.example.com")!)
        #expect(loaded.gitlabArchives.sources.first?.name == "example")
        #expect(loaded.gitlabArchives.sources.first?.format == .discrawlSnapshot)
    }

    @Test
    func `load migrates older envelope and persists current version`() throws {
        let suiteName = "SettingsStoreCoverageTests.migrate.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        struct TestEnvelope: Codable {
            let version: Int
            let settings: UserSettings
        }

        var original = UserSettings()
        original.repoList.showForks = true
        original.refreshInterval = .thirtyMinutes
        let data = try JSONEncoder().encode(TestEnvelope(version: 1, settings: original))
        defaults.set(data, forKey: "com.weirdoadam.repopeek.settings")

        let store = SettingsStore(defaults: defaults)
        let loaded = store.load()
        #expect(loaded.repoList.showForks == true)
        #expect(loaded.refreshInterval == .sixHours)

        let stored = defaults.data(forKey: "com.weirdoadam.repopeek.settings")
        let decoded = try JSONDecoder().decode(TestEnvelope.self, from: #require(stored))
        #expect(decoded.version == 4)
    }

    @Test
    func `load invalid data falls back to defaults`() throws {
        let suiteName = "SettingsStoreCoverageTests.invalid.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: "com.weirdoadam.repopeek.settings")
        let store = SettingsStore(defaults: defaults)
        #expect(store.load() == UserSettings())
    }

    @Test
    func `load older settings missing archive config`() throws {
        var original = UserSettings()
        original.repoList.displayLimit = 4
        let data = try JSONEncoder().encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "gitlabArchives")
        object.removeValue(forKey: "gitLabReferenceMonitor")
        object.removeValue(forKey: "gitLabPullRequestNotifications")
        object.removeValue(forKey: "aiSummaries")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(UserSettings.self, from: legacyData)
        #expect(loaded.repoList.displayLimit == 4)
        #expect(loaded.gitLabReferenceMonitor == GitLabReferenceMonitorSettings())
        #expect(loaded.gitLabPullRequestNotifications == GitLabPullRequestNotificationSettings())
        #expect(loaded.aiSummaries == AISummarySettings())
        #expect(loaded.gitlabArchives == GitLabArchiveSettings())
    }

    @Test
    func `load older menu customization ignores removed main menu items`() throws {
        let data = try JSONEncoder().encode(UserSettings())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var customization = try #require(object["menuCustomization"] as? [String: Any])
        customization["hiddenMainMenuItems"] = ["actionsLimits"]
        customization["mainMenuOrder"] = ["loggedOutPrompt", "actionsLimits", "repoList", "quit"]
        object["menuCustomization"] = customization
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(UserSettings.self, from: legacyData)

        #expect(loaded.menuCustomization.hiddenMainMenuItems.isEmpty)
        #expect(!loaded.menuCustomization.mainMenuOrder.map(\.rawValue).contains("actionsLimits"))
    }

    @Test
    func `load older issue number monitor setting as gitlab reference monitor`() throws {
        let data = try JSONEncoder().encode(UserSettings())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "gitLabReferenceMonitor")
        object["issueNumberMonitor"] = ["enabled": true]
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(UserSettings.self, from: legacyData)

        #expect(loaded.gitLabReferenceMonitor.enabled)
    }

    @Test
    func `load older merge request notification settings defaults click action`() throws {
        let data = try JSONEncoder().encode(UserSettings())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var notifications = try #require(object["gitLabPullRequestNotifications"] as? [String: Any])
        notifications["enabled"] = true
        notifications["reviewRequests"] = true
        notifications.removeValue(forKey: "clickAction")
        object["gitLabPullRequestNotifications"] = notifications
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(UserSettings.self, from: legacyData)

        #expect(loaded.gitLabPullRequestNotifications.enabled)
        #expect(loaded.gitLabPullRequestNotifications.reviewRequests)
        #expect(loaded.gitLabPullRequestNotifications.clickAction == .openInBrowser)
    }

    @Test
    func `load older appearance settings enables rate-limit meter`() throws {
        let data = try JSONEncoder().encode(UserSettings())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var appearance = try #require(object["appearance"] as? [String: Any])
        appearance.removeValue(forKey: "showRateLimitMeterInMenuBar")
        object["appearance"] = appearance
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(UserSettings.self, from: legacyData)

        #expect(loaded.appearance.showRateLimitMeterInMenuBar)
    }
}
