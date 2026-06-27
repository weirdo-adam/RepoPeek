import Foundation

public struct UserSettings: Equatable, Codable {
    public var appearance = AppearanceSettings()
    public var heatmap = HeatmapSettings()
    public var repoList = RepoListSettings()
    public var localProjects = LocalProjectsSettings()
    public var gitLabReferenceMonitor = GitLabReferenceMonitorSettings()
    public var gitLabPullRequestNotifications = GitLabPullRequestNotificationSettings()
    public var aiSummaries = AISummarySettings()
    public var gitlabArchives = GitLabArchiveSettings()
    public var menuCustomization = MenuCustomization()
    public var keyboardShortcuts = KeyboardShortcutSettings()
    public var refreshInterval: RefreshInterval = .sixHours
    public var launchAtLogin = false
    public var debugPaneEnabled: Bool = false
    public var diagnosticsEnabled: Bool = false
    public var loggingVerbosity: LogVerbosity = .info
    public var fileLoggingEnabled: Bool = false
    public var gitlabHost: URL = .init(string: "https://gitlab.com")!
    public var enterpriseHost: URL?
    public var gitlabAccounts: [GitLabAccountSettings] = [.gitLabCom()]
    public var authMethod: AuthMethod = .pat
    public var language: AppLanguage = .system

    public init() {}

    enum CodingKeys: String, CodingKey {
        case appearance
        case heatmap
        case repoList
        case localProjects
        case gitLabReferenceMonitor
        case gitLabPullRequestNotifications
        case aiSummaries
        case legacyIssueNumberMonitor = "issueNumberMonitor"
        case gitlabArchives
        case menuCustomization
        case keyboardShortcuts
        case refreshInterval
        case launchAtLogin
        case debugPaneEnabled
        case diagnosticsEnabled
        case loggingVerbosity
        case fileLoggingEnabled
        case gitlabHost
        case enterpriseHost
        case gitlabAccounts
        case authMethod
        case language
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.appearance = try container.decodeIfPresent(AppearanceSettings.self, forKey: .appearance) ?? AppearanceSettings()
        self.heatmap = try container.decodeIfPresent(HeatmapSettings.self, forKey: .heatmap) ?? HeatmapSettings()
        self.repoList = try container.decodeIfPresent(RepoListSettings.self, forKey: .repoList) ?? RepoListSettings()
        self.localProjects = try container.decodeIfPresent(LocalProjectsSettings.self, forKey: .localProjects) ?? LocalProjectsSettings()
        self.gitLabReferenceMonitor = try container.decodeIfPresent(GitLabReferenceMonitorSettings.self, forKey: .gitLabReferenceMonitor)
            ?? container.decodeIfPresent(GitLabReferenceMonitorSettings.self, forKey: .legacyIssueNumberMonitor)
            ?? GitLabReferenceMonitorSettings()
        self.gitLabPullRequestNotifications = try container.decodeIfPresent(
            GitLabPullRequestNotificationSettings.self,
            forKey: .gitLabPullRequestNotifications
        ) ?? GitLabPullRequestNotificationSettings()
        self.aiSummaries = try container.decodeIfPresent(AISummarySettings.self, forKey: .aiSummaries) ?? AISummarySettings()
        self.gitlabArchives = try container.decodeIfPresent(GitLabArchiveSettings.self, forKey: .gitlabArchives) ?? GitLabArchiveSettings()
        self.menuCustomization = try container.decodeIfPresent(MenuCustomization.self, forKey: .menuCustomization) ?? MenuCustomization()
        self.keyboardShortcuts = try container.decodeIfPresent(KeyboardShortcutSettings.self, forKey: .keyboardShortcuts) ?? KeyboardShortcutSettings()
        self.refreshInterval = try container.decodeIfPresent(RefreshInterval.self, forKey: .refreshInterval) ?? .sixHours
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.debugPaneEnabled = try container.decodeIfPresent(Bool.self, forKey: .debugPaneEnabled) ?? false
        self.diagnosticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .diagnosticsEnabled) ?? false
        self.loggingVerbosity = try container.decodeIfPresent(LogVerbosity.self, forKey: .loggingVerbosity) ?? .info
        self.fileLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .fileLoggingEnabled) ?? false
        let hasGitLabHost = container.contains(.gitlabHost)
        let decodedGitLabHost = try container.decodeIfPresent(URL.self, forKey: .gitlabHost) ?? URL(string: "https://gitlab.com")!
        self.gitlabHost = decodedGitLabHost
        self.enterpriseHost = try container.decodeIfPresent(URL.self, forKey: .enterpriseHost)
        if container.contains(.gitlabAccounts) {
            let decodedAccounts = try container.decodeIfPresent([GitLabAccountSettings].self, forKey: .gitlabAccounts) ?? []
            let normalizedAccounts = Self.normalizedAccounts(decodedAccounts)
            self.gitlabAccounts = hasGitLabHost
                ? Self.accounts(normalizedAccounts, ensuringPrimaryHost: decodedGitLabHost)
                : normalizedAccounts
        } else {
            let account = GitLabAccountSettings(id: GitLabAccountSettings.hostKey(for: decodedGitLabHost), host: decodedGitLabHost)
            self.gitlabAccounts = Self.normalizedAccounts([account])
        }
        self.gitlabHost = self.gitlabAccounts.first?.host ?? decodedGitLabHost
        self.authMethod = .pat
        self.language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.appearance, forKey: .appearance)
        try container.encode(self.heatmap, forKey: .heatmap)
        try container.encode(self.repoList, forKey: .repoList)
        try container.encode(self.localProjects, forKey: .localProjects)
        try container.encode(self.gitLabReferenceMonitor, forKey: .gitLabReferenceMonitor)
        try container.encode(self.gitLabPullRequestNotifications, forKey: .gitLabPullRequestNotifications)
        try container.encode(self.aiSummaries, forKey: .aiSummaries)
        try container.encode(self.gitlabArchives, forKey: .gitlabArchives)
        try container.encode(self.menuCustomization, forKey: .menuCustomization)
        try container.encode(self.keyboardShortcuts, forKey: .keyboardShortcuts)
        try container.encode(self.refreshInterval, forKey: .refreshInterval)
        try container.encode(self.launchAtLogin, forKey: .launchAtLogin)
        try container.encode(self.debugPaneEnabled, forKey: .debugPaneEnabled)
        try container.encode(self.diagnosticsEnabled, forKey: .diagnosticsEnabled)
        try container.encode(self.loggingVerbosity, forKey: .loggingVerbosity)
        try container.encode(self.fileLoggingEnabled, forKey: .fileLoggingEnabled)
        try container.encode(self.gitlabHost, forKey: .gitlabHost)
        try container.encodeIfPresent(self.enterpriseHost, forKey: .enterpriseHost)
        try container.encode(self.gitlabAccounts, forKey: .gitlabAccounts)
        try container.encode(self.authMethod, forKey: .authMethod)
        try container.encode(self.language, forKey: .language)
    }

    private static func normalizedAccounts(_ accounts: [GitLabAccountSettings]) -> [GitLabAccountSettings] {
        var seen: Set<String> = []
        return accounts.compactMap { account in
            let normalized = account.normalized()
            let key = normalized.accountID
            guard seen.insert(key).inserted else { return nil }

            return normalized
        }
    }

    private static func accounts(
        _ accounts: [GitLabAccountSettings],
        ensuringPrimaryHost host: URL
    ) -> [GitLabAccountSettings] {
        guard accounts.isEmpty == false else { return [] }

        let hostKey = GitLabAccountSettings.hostKey(for: host)
        guard accounts.contains(where: { $0.hostKey == hostKey }) == false else { return accounts }

        let primary = GitLabAccountSettings(id: hostKey, host: host)
        return [primary] + accounts
    }
}

public struct KeyboardShortcutSettings: Equatable, Codable, Sendable {
    public var issueNavigator: MenuKeyboardShortcut = .commandF
    public var refreshNow: MenuKeyboardShortcut = .commandR

    public init() {}

    enum CodingKeys: String, CodingKey {
        case issueNavigator
        case refreshNow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.issueNavigator = try container.decodeIfPresent(
            MenuKeyboardShortcut.self,
            forKey: .issueNavigator
        ) ?? .commandF
        self.refreshNow = try container.decodeIfPresent(MenuKeyboardShortcut.self, forKey: .refreshNow) ?? .commandR
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.issueNavigator, forKey: .issueNavigator)
        try container.encode(self.refreshNow, forKey: .refreshNow)
    }
}

public struct AISummarySettings: Equatable, Codable, Sendable {
    public static let defaultProvider: AISummaryProvider = .openAIResponses
    public static let defaultModel = "gpt-5.5"
    public static let defaultOpenAIResponsesEndpoint = URL(string: "https://api.openai.com/v1/responses")!

    public var provider: AISummaryProvider
    public var enabled: Bool
    public var model: String
    public var requestURL: URL?

    public init(
        provider: AISummaryProvider = Self.defaultProvider,
        enabled: Bool = false,
        model: String? = nil,
        requestURL: URL? = nil
    ) {
        self.provider = provider
        self.enabled = enabled
        self.model = Self.normalizedModel(model ?? Self.defaultModel(for: provider), provider: provider)
        self.requestURL = Self.normalizedRequestURL(requestURL)
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case enabled
        case model
        case requestURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.provider = try container.decodeIfPresent(AISummaryProvider.self, forKey: .provider) ?? Self.defaultProvider
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.model = try Self.normalizedModel(
            container.decodeIfPresent(String.self, forKey: .model) ?? Self.defaultModel(for: self.provider),
            provider: self.provider
        )
        self.requestURL = try Self.normalizedRequestURLString(
            container.decodeIfPresent(String.self, forKey: .requestURL)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.provider, forKey: .provider)
        try container.encode(self.enabled, forKey: .enabled)
        try container.encode(Self.normalizedModel(self.model, provider: self.provider), forKey: .model)
        if let requestURL = Self.normalizedRequestURL(self.requestURL) {
            try container.encode(requestURL.absoluteString, forKey: .requestURL)
        }
    }

    public var resolvedRequestURL: URL {
        Self.normalizedRequestURL(self.requestURL) ?? Self.defaultOpenAIResponsesEndpoint
    }

    public static var modelOptions: [AISummaryModelOption] {
        Self.modelOptions(for: defaultProvider)
    }

    public static func modelOptions(for provider: AISummaryProvider) -> [AISummaryModelOption] {
        switch provider {
        case .openAIResponses:
            [
                AISummaryModelOption(id: "gpt-5.5", label: "GPT-5.5")
            ]
        case .claudeCode:
            [
                AISummaryModelOption(id: "sonnet", label: "Sonnet"),
                AISummaryModelOption(id: "opus", label: "Opus")
            ]
        }
    }

    public static func defaultModel(for provider: AISummaryProvider) -> String {
        switch provider {
        case .openAIResponses:
            self.defaultModel
        case .claudeCode:
            "sonnet"
        }
    }

    public static func normalizedModel(_ model: String) -> String {
        self.normalizedModel(model, provider: self.defaultProvider)
    }

    public static func normalizedModel(_ model: String, provider: AISummaryProvider) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return Self.defaultModel(for: provider) }
        guard Self.modelOptions(for: provider).contains(where: { $0.id == trimmed }) else {
            return Self.defaultModel(for: provider)
        }

        return trimmed
    }

    public static func normalizedRequestURLString(_ value: String?) -> URL? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let url = URL(string: trimmed)
        else { return nil }

        return Self.normalizedRequestURL(url)
    }

    public static func normalizedRequestURL(_ url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else { return nil }

        return url
    }
}

public enum AISummaryProvider: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case openAIResponses
    case claudeCode

    public var id: String {
        self.rawValue
    }

    public var label: String {
        switch self {
        case .openAIResponses:
            "OpenAI Responses"
        case .claudeCode:
            "Claude Agent"
        }
    }
}

public struct AISummaryModelOption: Equatable, Codable, Hashable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct MenuKeyboardShortcut: Equatable, Codable, Hashable, Sendable {
    public var key: String
    public var modifiers: Set<MenuKeyboardShortcutModifier>

    public init(key: String, modifiers: Set<MenuKeyboardShortcutModifier>) {
        let normalizedKey: String = switch key {
        case " ", "\r", "\t": key
        default: key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        self.key = normalizedKey
        self.modifiers = normalizedKey.isEmpty ? [] : modifiers
    }

    enum CodingKeys: String, CodingKey {
        case key
        case modifiers
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let rawValue = try? container.decode(String.self)
        {
            self = IssueNavigatorShortcut(rawValue: rawValue)?.keyboardShortcut ?? .none
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        let modifiers = try container.decodeIfPresent([MenuKeyboardShortcutModifier].self, forKey: .modifiers) ?? []
        self.init(key: key, modifiers: Set(modifiers))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.key, forKey: .key)
        try container.encode(
            MenuKeyboardShortcutModifier.displayOrder.filter { self.modifiers.contains($0) },
            forKey: .modifiers
        )
    }

    public var isEnabled: Bool {
        self.key.isEmpty == false
    }

    public var label: String {
        guard self.isEnabled else { return "None" }

        let modifierLabel = MenuKeyboardShortcutModifier.displayOrder
            .filter { self.modifiers.contains($0) }
            .map(\.symbol)
            .joined()
        return modifierLabel + self.displayKey
    }

    private var displayKey: String {
        switch self.key {
        case " ": "Space"
        case "\r": "Return"
        case "\t": "Tab"
        default:
            self.key.count == 1 ? self.key.uppercased() : self.key
        }
    }

    public static let none = MenuKeyboardShortcut(key: "", modifiers: [])
    public static let commandF = MenuKeyboardShortcut(key: "f", modifiers: [.command])
    public static let commandShiftF = MenuKeyboardShortcut(key: "f", modifiers: [.command, .shift])
    public static let commandOptionF = MenuKeyboardShortcut(key: "f", modifiers: [.command, .option])
    public static let controlF = MenuKeyboardShortcut(key: "f", modifiers: [.control])
    public static let commandR = MenuKeyboardShortcut(key: "r", modifiers: [.command])
}

public enum MenuKeyboardShortcutModifier: String, CaseIterable, Codable, Hashable, Sendable {
    case command
    case shift
    case option
    case control

    public var symbol: String {
        switch self {
        case .command: "⌘"
        case .shift: "⇧"
        case .option: "⌥"
        case .control: "⌃"
        }
    }

    public static let displayOrder: [MenuKeyboardShortcutModifier] = [
        .command,
        .shift,
        .option,
        .control
    ]
}

public enum IssueNavigatorShortcut: String, Equatable, Codable, Hashable, Sendable {
    case commandF
    case commandShiftF
    case commandOptionF
    case controlF
    case none

    public var label: String {
        self.keyboardShortcut.label
    }

    public var keyboardShortcut: MenuKeyboardShortcut {
        switch self {
        case .commandF: .commandF
        case .commandShiftF: .commandShiftF
        case .commandOptionF: .commandOptionF
        case .controlF: .controlF
        case .none: .none
        }
    }
}

public enum AuthMethod: String, CaseIterable, Equatable, Codable, Sendable {
    case pat

    public var label: String {
        "Personal Access Token"
    }
}

public struct HeatmapSettings: Equatable, Codable {
    public var display: HeatmapDisplay = .inline
    public var span: HeatmapSpan = .twelveMonths

    public init() {}
}

public struct AccountScopedRepositoryLists: Equatable, Codable, Sendable, Hashable {
    public var pinnedRepositoriesByAccount: [String: [String]]
    public var hiddenRepositoriesByAccount: [String: [String]]
    public var hiddenGroupsByAccount: [String: [String]]

    public init(
        pinnedRepositoriesByAccount: [String: [String]] = [:],
        hiddenRepositoriesByAccount: [String: [String]] = [:],
        hiddenGroupsByAccount: [String: [String]] = [:]
    ) {
        self.pinnedRepositoriesByAccount = Self.normalizedRepositoryMap(pinnedRepositoriesByAccount)
        self.hiddenRepositoriesByAccount = Self.normalizedRepositoryMap(hiddenRepositoriesByAccount)
        self.hiddenGroupsByAccount = Self.normalizedGroupMap(hiddenGroupsByAccount)
    }

    enum CodingKeys: String, CodingKey {
        case pinnedRepositoriesByAccount
        case hiddenRepositoriesByAccount
        case hiddenGroupsByAccount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            pinnedRepositoriesByAccount: container.decodeIfPresent(
                [String: [String]].self,
                forKey: .pinnedRepositoriesByAccount
            ) ?? [:],
            hiddenRepositoriesByAccount: container.decodeIfPresent(
                [String: [String]].self,
                forKey: .hiddenRepositoriesByAccount
            ) ?? [:],
            hiddenGroupsByAccount: container.decodeIfPresent(
                [String: [String]].self,
                forKey: .hiddenGroupsByAccount
            ) ?? [:]
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.pinnedRepositoriesByAccount, forKey: .pinnedRepositoriesByAccount)
        try container.encode(self.hiddenRepositoriesByAccount, forKey: .hiddenRepositoriesByAccount)
        try container.encode(self.hiddenGroupsByAccount, forKey: .hiddenGroupsByAccount)
    }

    public static func normalizedAccountID(_ accountID: String?) -> String? {
        let normalized = accountID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard normalized.isEmpty == false else { return nil }

        return normalized
    }

    public var hasPinnedRepositories: Bool {
        self.pinnedRepositoriesByAccount.values.contains { !$0.isEmpty }
    }

    public var allPinnedRepositories: [String] {
        self.flatten(self.pinnedRepositoriesByAccount)
    }

    public func pinnedRepositories(forAccountID accountID: String?) -> [String]? {
        self.values(in: self.pinnedRepositoriesByAccount, forAccountID: accountID)
    }

    public func hiddenRepositories(forAccountID accountID: String?) -> [String]? {
        self.values(in: self.hiddenRepositoriesByAccount, forAccountID: accountID)
    }

    public func hiddenGroups(forAccountID accountID: String?) -> [String]? {
        self.values(in: self.hiddenGroupsByAccount, forAccountID: accountID)
    }

    public mutating func setPinnedRepositories(_ repositories: [String], forAccountID accountID: String?) {
        guard let key = Self.normalizedAccountID(accountID) else { return }

        self.pinnedRepositoriesByAccount[key] = Self.normalizedRepositories(repositories)
    }

    public mutating func setHiddenRepositories(_ repositories: [String], forAccountID accountID: String?) {
        guard let key = Self.normalizedAccountID(accountID) else { return }

        self.hiddenRepositoriesByAccount[key] = Self.normalizedRepositories(repositories)
    }

    public mutating func setHiddenGroups(_ groups: [String], forAccountID accountID: String?) {
        guard let key = Self.normalizedAccountID(accountID) else { return }

        self.hiddenGroupsByAccount[key] = Self.normalizedGroups(groups)
    }

    public func hash(into hasher: inout Hasher) {
        self.hash(self.pinnedRepositoriesByAccount, into: &hasher)
        self.hash(self.hiddenRepositoriesByAccount, into: &hasher)
        self.hash(self.hiddenGroupsByAccount, into: &hasher)
    }

    private func values(in map: [String: [String]], forAccountID accountID: String?) -> [String]? {
        guard let key = Self.normalizedAccountID(accountID) else { return nil }

        return map[key]
    }

    private func flatten(_ map: [String: [String]]) -> [String] {
        map.keys.sorted().flatMap { map[$0] ?? [] }
    }

    private func hash(_ map: [String: [String]], into hasher: inout Hasher) {
        for key in map.keys.sorted() {
            hasher.combine(key)
            hasher.combine(map[key] ?? [])
        }
    }

    private static func normalizedRepositoryMap(_ map: [String: [String]]) -> [String: [String]] {
        map.reduce(into: [:]) { result, entry in
            guard let key = self.normalizedAccountID(entry.key) else { return }

            result[key] = self.normalizedRepositories(entry.value)
        }
    }

    private static func normalizedGroupMap(_ map: [String: [String]]) -> [String: [String]] {
        map.reduce(into: [:]) { result, entry in
            guard let key = self.normalizedAccountID(entry.key) else { return }

            result[key] = self.normalizedGroups(entry.value)
        }
    }

    private static func normalizedRepositories(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = RepositoryVisibilityRules.normalizeRepositoryPath(trimmed)
            guard trimmed.isEmpty == false, seen.insert(normalized).inserted else { return nil }

            return trimmed
        }
    }

    private static func normalizedGroups(_ values: [String]) -> [String] {
        RepositoryVisibilityRules.normalizedGroupPaths(values)
    }
}

public struct RepoListSettings: Equatable, Codable {
    public var displayLimit: Int = 6
    public var showForks = false
    public var showArchived = false
    public var menuSortKey: RepositorySortKey = .activity
    public var pinnedRepositories: [String] = [] // owner/name
    public var hiddenRepositories: [String] = [] // owner/name
    public var hiddenGroups: [String] = [] // group/subgroup
    public var accountScopedRepositoryLists = AccountScopedRepositoryLists()
    public var ownerFilter: [String] = [] // owner names to include (empty = show all)

    public init() {}

    enum CodingKeys: String, CodingKey {
        case displayLimit
        case showForks
        case showArchived
        case menuSortKey
        case pinnedRepositories
        case hiddenRepositories
        case hiddenGroups
        case accountScopedRepositoryLists
        case ownerFilter
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.displayLimit = try container.decodeIfPresent(Int.self, forKey: .displayLimit) ?? 6
        self.showForks = try container.decodeIfPresent(Bool.self, forKey: .showForks) ?? false
        self.showArchived = try container.decodeIfPresent(Bool.self, forKey: .showArchived) ?? false
        self.menuSortKey = try container.decodeIfPresent(RepositorySortKey.self, forKey: .menuSortKey) ?? .activity
        self.pinnedRepositories = try container.decodeIfPresent([String].self, forKey: .pinnedRepositories) ?? []
        self.hiddenRepositories = try container.decodeIfPresent([String].self, forKey: .hiddenRepositories) ?? []
        self.hiddenGroups = try RepositoryVisibilityRules.normalizedGroupPaths(
            container.decodeIfPresent([String].self, forKey: .hiddenGroups) ?? []
        )
        self.accountScopedRepositoryLists = try container.decodeIfPresent(
            AccountScopedRepositoryLists.self,
            forKey: .accountScopedRepositoryLists
        ) ?? AccountScopedRepositoryLists()
        self.ownerFilter = try container.decodeIfPresent([String].self, forKey: .ownerFilter) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.displayLimit, forKey: .displayLimit)
        try container.encode(self.showForks, forKey: .showForks)
        try container.encode(self.showArchived, forKey: .showArchived)
        try container.encode(self.menuSortKey, forKey: .menuSortKey)
        try container.encode(self.pinnedRepositories, forKey: .pinnedRepositories)
        try container.encode(self.hiddenRepositories, forKey: .hiddenRepositories)
        try container.encode(self.hiddenGroups, forKey: .hiddenGroups)
        try container.encode(self.accountScopedRepositoryLists, forKey: .accountScopedRepositoryLists)
        try container.encode(self.ownerFilter, forKey: .ownerFilter)
    }

    public var hasPinnedRepositories: Bool {
        !self.pinnedRepositories.isEmpty || self.accountScopedRepositoryLists.hasPinnedRepositories
    }

    public var allPinnedRepositories: [String] {
        self.pinnedRepositories + self.accountScopedRepositoryLists.allPinnedRepositories
    }

    public func pinnedRepositories(forAccountID accountID: String?) -> [String] {
        self.accountScopedRepositoryLists.pinnedRepositories(forAccountID: accountID) ?? self.pinnedRepositories
    }

    public func hiddenRepositories(forAccountID accountID: String?) -> [String] {
        self.accountScopedRepositoryLists.hiddenRepositories(forAccountID: accountID) ?? self.hiddenRepositories
    }

    public func hiddenGroups(forAccountID accountID: String?) -> [String] {
        self.accountScopedRepositoryLists.hiddenGroups(forAccountID: accountID) ?? self.hiddenGroups
    }

    public mutating func setPinnedRepositories(_ repositories: [String], forAccountID accountID: String?) {
        guard AccountScopedRepositoryLists.normalizedAccountID(accountID) != nil else {
            self.pinnedRepositories = Self.normalizedRepositories(repositories)
            return
        }

        self.accountScopedRepositoryLists.setPinnedRepositories(repositories, forAccountID: accountID)
    }

    public mutating func setHiddenRepositories(_ repositories: [String], forAccountID accountID: String?) {
        guard AccountScopedRepositoryLists.normalizedAccountID(accountID) != nil else {
            self.hiddenRepositories = Self.normalizedRepositories(repositories)
            return
        }

        self.accountScopedRepositoryLists.setHiddenRepositories(repositories, forAccountID: accountID)
    }

    public mutating func setHiddenGroups(_ groups: [String], forAccountID accountID: String?) {
        guard AccountScopedRepositoryLists.normalizedAccountID(accountID) != nil else {
            self.hiddenGroups = RepositoryVisibilityRules.normalizedGroupPaths(groups)
            return
        }

        self.accountScopedRepositoryLists.setHiddenGroups(groups, forAccountID: accountID)
    }

    @discardableResult
    public mutating func pinRepository(_ fullName: String, forAccountID accountID: String?) -> Bool {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }

        let normalized = RepositoryVisibilityRules.normalizeRepositoryPath(trimmed)
        var pinned = self.pinnedRepositories(forAccountID: accountID)
        var hidden = self.hiddenRepositories(forAccountID: accountID)
        let alreadyPinned = pinned.contains {
            RepositoryVisibilityRules.normalizeRepositoryPath($0) == normalized
        }
        let isHidden = hidden.contains {
            RepositoryVisibilityRules.normalizeRepositoryPath($0) == normalized
        }
        guard !alreadyPinned || isHidden else { return false }

        if !alreadyPinned {
            pinned.append(trimmed)
        }
        hidden.removeAll {
            RepositoryVisibilityRules.normalizeRepositoryPath($0) == normalized
        }
        self.setPinnedRepositories(pinned, forAccountID: accountID)
        self.setHiddenRepositories(hidden, forAccountID: accountID)
        return true
    }

    public func isPinned(fullName: String, accountID: String?) -> Bool {
        let normalized = RepositoryVisibilityRules.normalizeRepositoryPath(fullName)
        return self.pinnedRepositories(forAccountID: accountID).contains {
            RepositoryVisibilityRules.normalizeRepositoryPath($0) == normalized
        }
    }

    public func isHidden(fullName: String, accountID: String?) -> Bool {
        RepositoryVisibilityRules.isHidden(
            fullName: fullName,
            hiddenRepositories: Set(self.hiddenRepositories(forAccountID: accountID)),
            hiddenGroups: self.hiddenGroups(forAccountID: accountID)
        )
    }

    public func hiddenGroup(for fullName: String, accountID: String?) -> String? {
        RepositoryVisibilityRules.hiddenGroup(
            for: fullName,
            hiddenGroups: self.hiddenGroups(forAccountID: accountID)
        )
    }

    private static func normalizedRepositories(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = RepositoryVisibilityRules.normalizeRepositoryPath(trimmed)
            guard trimmed.isEmpty == false, seen.insert(normalized).inserted else { return nil }

            return trimmed
        }
    }
}

public struct AppearanceSettings: Equatable, Codable {
    public static let minimumStatusIconExpressionIntervalSeconds = 1
    public static let maximumStatusIconExpressionIntervalSeconds = 60

    public var showContributionHeader = true
    public var showRateLimitMeterInMenuBar = true
    public var statusIconExpressionIntervalSeconds = 10
    public var cardDensity: CardDensity = .comfortable
    public var accentTone: AccentTone = .gitlabGreen
    public var activityScope: GlobalActivityScope = .myActivity

    public init() {}

    enum CodingKeys: String, CodingKey {
        case showContributionHeader
        case showRateLimitMeterInMenuBar
        case statusIconExpressionIntervalSeconds
        case cardDensity
        case accentTone
        case activityScope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.showContributionHeader = try container.decodeIfPresent(Bool.self, forKey: .showContributionHeader) ?? true
        self.showRateLimitMeterInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showRateLimitMeterInMenuBar) ?? true
        let interval = try container.decodeIfPresent(Int.self, forKey: .statusIconExpressionIntervalSeconds) ?? 10
        self.statusIconExpressionIntervalSeconds = Self.clampedStatusIconExpressionIntervalSeconds(interval)
        self.cardDensity = try container.decodeIfPresent(CardDensity.self, forKey: .cardDensity) ?? .comfortable
        self.accentTone = try container.decodeIfPresent(AccentTone.self, forKey: .accentTone) ?? .gitlabGreen
        self.activityScope = try container.decodeIfPresent(GlobalActivityScope.self, forKey: .activityScope) ?? .myActivity
    }

    public static func clampedStatusIconExpressionIntervalSeconds(_ value: Int) -> Int {
        min(max(value, self.minimumStatusIconExpressionIntervalSeconds), self.maximumStatusIconExpressionIntervalSeconds)
    }
}

public struct LocalProjectsSettings: Equatable, Codable {
    public var rootPath: String?
    public var rootBookmarkData: Data?
    public var autoSyncEnabled: Bool = false
    public var showDirtyFilesInMenu: Bool = false
    public var fetchInterval: LocalProjectsRefreshInterval = .oneHour
    public var maxDepth: Int = LocalProjectsConstants.defaultMaxDepth
    public var worktreeFolderName: String = ".work"
    public var preferredTerminal: String?
    public var ghosttyOpenMode: GhosttyOpenMode = .tab
    public var preferredLocalPathsByFullName: [String: String] = [:]

    public init() {
        #if DEBUG
            self.rootPath = "~/Projects"
        #endif
    }
}

public struct GitLabReferenceMonitorSettings: Equatable, Codable, Sendable {
    public var enabled = false

    public init() {}
}

public struct GitLabPullRequestNotificationSettings: Equatable, Codable, Sendable {
    public var enabled = false
    public var newPullRequests = true
    public var pullRequestUpdates = true
    public var reviewRequests = false
    public var comments = false
    public var clickAction: GitLabPullRequestNotificationClickAction = .openInBrowser

    public init() {}

    enum CodingKeys: String, CodingKey {
        case enabled
        case newPullRequests
        case pullRequestUpdates
        case reviewRequests
        case comments
        case clickAction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.newPullRequests = try container.decodeIfPresent(Bool.self, forKey: .newPullRequests) ?? true
        self.pullRequestUpdates = try container.decodeIfPresent(Bool.self, forKey: .pullRequestUpdates) ?? true
        self.reviewRequests = try container.decodeIfPresent(Bool.self, forKey: .reviewRequests) ?? false
        self.comments = try container.decodeIfPresent(Bool.self, forKey: .comments) ?? false
        self.clickAction = try container.decodeIfPresent(
            GitLabPullRequestNotificationClickAction.self,
            forKey: .clickAction
        ) ?? .openInBrowser
    }
}

public enum GitLabPullRequestNotificationClickAction: String, CaseIterable, Hashable, Codable, Sendable {
    case openInBrowser
    case openIssueNavigator

    public var label: String {
        switch self {
        case .openInBrowser: "Default browser"
        case .openIssueNavigator: "Issue Navigator"
        }
    }
}

public struct GitLabArchiveSettings: Equatable, Codable, Sendable {
    public var sources: [GitLabArchiveSource] = []
    public var preferArchiveWhenRateLimited = true
    public var staleAfterSeconds: TimeInterval = 15 * 60

    public init() {}
}

public struct GitLabArchiveSource: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var localRepositoryPath: String?
    public var remoteURL: String?
    public var branch: String
    public var importedDatabasePath: String
    public var format: GitLabArchiveFormat

    public init(
        id: String = UUID().uuidString,
        name: String,
        enabled: Bool = true,
        localRepositoryPath: String?,
        remoteURL: String?,
        branch: String = "main",
        importedDatabasePath: String,
        format: GitLabArchiveFormat = .discrawlSnapshot
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.localRepositoryPath = localRepositoryPath
        self.remoteURL = remoteURL
        self.branch = branch
        self.importedDatabasePath = importedDatabasePath
        self.format = format
    }
}

public enum GitLabArchiveFormat: String, Equatable, Codable, Sendable {
    case discrawlSnapshot

    public var label: String {
        switch self {
        case .discrawlSnapshot: "Discrawl snapshot"
        }
    }
}

public enum LocalProjectsRefreshInterval: String, CaseIterable, Equatable, Codable {
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case fifteenMinutes
    case oneHour

    public var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .oneHour: 3600
        }
    }

    public var label: String {
        switch self {
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .oneHour: "1 hour"
        }
    }
}

public enum GhosttyOpenMode: String, CaseIterable, Equatable, Codable {
    case newWindow
    case tab

    public var label: String {
        switch self {
        case .newWindow: "New Window"
        case .tab: "Tab"
        }
    }
}

public enum RefreshInterval: String, CaseIterable, Equatable, Codable {
    case thirtyMinutes
    case oneHour
    case sixHours
    case twelveHours
    case oneDay

    public var seconds: TimeInterval {
        switch self {
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .sixHours: 6 * 60 * 60
        case .twelveHours: 12 * 60 * 60
        case .oneDay: 24 * 60 * 60
        }
    }

    public var label: String {
        switch self {
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .sixHours: "6 hours"
        case .twelveHours: "12 hours"
        case .oneDay: "1 day"
        }
    }

    public init(from decoder: Decoder) throws {
        if let rawValue = try? decoder.singleValueContainer().decode(String.self) {
            self = Self.interval(forStoredValue: rawValue)
            return
        }

        let container = try decoder.container(keyedBy: RefreshIntervalCodingKey.self)
        self = Self.interval(forStoredValue: container.allKeys.first?.stringValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }

    private static func interval(forStoredValue value: String?) -> RefreshInterval {
        switch value {
        case thirtyMinutes.rawValue:
            .thirtyMinutes
        case oneHour.rawValue:
            .oneHour
        case sixHours.rawValue:
            .sixHours
        case twelveHours.rawValue:
            .twelveHours
        case oneDay.rawValue:
            .oneDay
        case "oneMinute", "twoMinutes", "fiveMinutes", "fifteenMinutes":
            .sixHours
        default:
            .sixHours
        }
    }
}

private struct RefreshIntervalCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

public enum HeatmapDisplay: String, CaseIterable, Equatable, Codable {
    case inline
    case submenu

    public var label: String {
        switch self {
        case .inline: "Inline"
        case .submenu: "Submenu"
        }
    }
}

public enum CardDensity: String, CaseIterable, Equatable, Codable {
    case comfortable
    case compact

    public var label: String {
        switch self {
        case .comfortable: "Comfortable"
        case .compact: "Compact"
        }
    }
}

public enum AccentTone: String, CaseIterable, Equatable, Codable {
    case system
    case gitlabGreen

    public var label: String {
        switch self {
        case .system: "System accent"
        case .gitlabGreen: "Contribution greens"
        }
    }
}

public enum GlobalActivityScope: String, CaseIterable, Equatable, Codable, Sendable {
    case allActivity
    case myActivity

    public var label: String {
        switch self {
        case .allActivity: "All activity"
        case .myActivity: "My activity"
        }
    }
}
