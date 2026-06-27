import Foundation
import Observation
import RepoPeekCore

@Observable
final class Session {
    var account: AccountState = .loggedOut
    var accountUsers: [String: UserIdentity] = [:]
    var accountErrors: [String: String] = [:]
    var hasStoredTokens = false
    var accessibleRepositories: [Repository] = []
    var repositories: [Repository] = []
    var menuSnapshot: MenuSnapshot?
    var menuDisplayIndex: [String: RepositoryDisplayModel] = [:]
    var hasLoadedRepositories = false
    var isRefreshingRepositories = false
    var settings = UserSettings()
    var settingsSelectedTab: SettingsTab = .general
    var rateLimitReset: Date?
    var rateLimitDiagnostics: DiagnosticsSummary = .empty
    var rateLimitCacheSummary: RepoPeekCacheSummary?
    var lastError: String?
    var contributionHeatmap: [HeatmapCell] = []
    var contributionUser: String?
    var contributionError: String?
    var contributionIsLoading = false
    var globalActivityEvents: [ActivityEvent] = []
    var globalActivityError: String?
    var globalCommitEvents: [RepoCommitSummary] = []
    var globalCommitError: String?
    var heatmapRange: HeatmapRange = HeatmapFilter.range(
        span: .twelveMonths,
        now: Date(),
        calendar: HeatmapFilter.gitLabCalendar(),
        alignToWeek: true
    )
    var menuRepoSelection: MenuRepoSelection = .all
    var menuRepoSearchQuery = ""
    var menuRepoSearchExpanded = false
    var recentIssueScope: RecentIssueScope = .all
    var recentIssueLabelSelection: Set<String> = []
    var recentPullRequestScope: RecentPullRequestScope = .all
    var recentPullRequestEngagement: RecentPullRequestEngagement = .all
    var localRepoIndex: LocalRepoIndex = .empty
    var localDiscoveredRepoCount = 0
    var localProjectsScanInProgress = false
    var localProjectsAccessDenied = false
    var gitLabReferenceMatches: [GitLabReferenceMatch] = []
    var gitLabReferenceMatch: GitLabReferenceMatch?

    var rateLimitDisplayState: RateLimitDisplayState {
        RateLimitDisplayState(
            diagnostics: self.rateLimitDiagnostics,
            cacheSummary: self.rateLimitCacheSummary,
            authMethod: self.settings.authMethod
        )
    }
}

enum AccountState: Equatable {
    case loggedOut
    case loggingIn
    case loggedIn(UserIdentity)

    var isLoggedIn: Bool {
        if case .loggedIn = self { return true }
        return false
    }
}
