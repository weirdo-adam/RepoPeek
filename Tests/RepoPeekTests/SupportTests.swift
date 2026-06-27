import Foundation
@testable import RepoPeek
@testable import RepoPeekCore
import Testing

@MainActor
struct RefreshAndBackoffTests {
    @Test
    func `force refresh triggers tick`() {
        let scheduler = RefreshScheduler()
        var fired = false
        scheduler.configure(interval: 60, fireImmediately: false) {
            fired = true
        }

        scheduler.forceRefresh()
        #expect(fired)
    }

    @Test
    func `backoff tracks cooldown`() async throws {
        let tracker = BackoffTracker()
        let url = try #require(URL(string: "https://example.com/path"))
        let initial = await tracker.isCoolingDown(url: url)
        #expect(initial == false)

        let until = Date().addingTimeInterval(30)
        await tracker.setCooldown(url: url, until: until)

        let cooling = await tracker.isCoolingDown(url: url)
        #expect(cooling)
        let reported = await tracker.cooldown(for: url)
        #expect(reported != nil)
        if let reported {
            #expect(abs(reported.timeIntervalSince1970 - until.timeIntervalSince1970) < 0.5)
        }
    }

    @Test
    func `maps certificate errors`() {
        let error = URLError(.serverCertificateUntrusted)
        #expect(error.userFacingMessage == "Enterprise host certificate is not trusted.")
    }

    @Test
    func `maps cannot parse response`() {
        let error = URLError(.cannotParseResponse)
        #expect(error.userFacingMessage == "GitLab returned an unexpected response.")
    }

    @Test
    func `authentication failure detection`() {
        let unauthorized: Error = GitLabAPIError.badStatus(code: 401, message: nil)
        #expect(unauthorized.isAuthenticationFailure)

        let refreshFailure: Error = GitLabAPIError.badStatus(
            code: 400,
            message: "Authentication refresh failed (HTTP 400). Please sign in again."
        )
        #expect(!refreshFailure.isAuthenticationFailure)

        let urlAuth: Error = URLError(.userAuthenticationRequired)
        #expect(urlAuth.isAuthenticationFailure)
    }

    @Test
    func `all repository issue search only surfaces total failure`() {
        #expect(AppState.shouldSurfaceIssueSearchFailure(searchedRepositories: 3, failedSearches: 3, matchCount: 0))
        #expect(!AppState.shouldSurfaceIssueSearchFailure(searchedRepositories: 3, failedSearches: 1, matchCount: 0))
        #expect(!AppState.shouldSurfaceIssueSearchFailure(searchedRepositories: 3, failedSearches: 3, matchCount: 1))
    }

    @Test
    func `all repository issue search fanout is capped to recent readable repos`() {
        let base = Date(timeIntervalSinceReferenceDate: 1000)
        var repos = (0 ..< 20).map { index in
            Self.makeIssueNavigatorRepo(
                name: "repo\(index)",
                pushedAt: base.addingTimeInterval(TimeInterval(index))
            )
        }
        repos.append(Self.makeIssueNavigatorRepo(name: "archived", isArchived: true, pushedAt: base.addingTimeInterval(100)))
        repos.append(Self.makeIssueNavigatorRepo(name: "private", viewerCanRead: false, pushedAt: base.addingTimeInterval(101)))

        let selected = AppState.issueNavigatorSearchRepositories(from: repos)

        #expect(selected.count == AppLimits.IssueNavigator.maxRepositorySearchFanout)
        #expect(selected.first?.fullName == "owner/repo19")
        #expect(selected.last?.fullName == "owner/repo8")
        #expect(selected.contains { $0.name == "archived" } == false)
        #expect(selected.contains { $0.name == "private" } == false)
    }

    @Test
    func `navigator result sorting uses updated time before created time`() throws {
        let base = Date(timeIntervalSinceReferenceDate: 1000)
        let recentlyCreated = try Self.makeGitLabReferenceMatch(
            number: 1,
            createdAt: base.addingTimeInterval(300),
            updatedAt: base.addingTimeInterval(10)
        )
        let recentlyUpdated = try Self.makeGitLabReferenceMatch(
            number: 2,
            createdAt: base.addingTimeInterval(1),
            updatedAt: base.addingTimeInterval(200)
        )

        let sorted = AppState.dedupedGitLabReferenceMatches([recentlyCreated, recentlyUpdated])

        #expect(sorted.map(\.title) == ["Match 2", "Match 1"])
    }

    @Test
    func `recent repository candidates respect issue and merge request filters before capping`() {
        let base = Date(timeIntervalSinceReferenceDate: 1000)
        var repos = (0 ..< AppLimits.IssueNavigator.recentRepositoryLimit).map { index in
            Self.makeIssueNavigatorRepo(
                name: "pr\(index)",
                openPulls: 1,
                pushedAt: base.addingTimeInterval(TimeInterval(100 + index))
            )
        }
        repos.append(Self.makeIssueNavigatorRepo(name: "issue", openIssues: 1, pushedAt: base))

        let issueRepos = AppState.issueNavigatorRecentRepositories(
            from: repos,
            includeIssues: true,
            includePullRequests: false
        )
        let pullRepos = AppState.issueNavigatorRecentRepositories(
            from: repos,
            includeIssues: false,
            includePullRequests: true
        )

        #expect(issueRepos.map(\.fullName) == ["owner/issue"])
        #expect(pullRepos.count == AppLimits.IssueNavigator.recentRepositoryLimit)
        #expect(pullRepos.allSatisfy { $0.openPulls > 0 })
    }

    @Test
    func `all repository issue search waits for repository inventory`() async throws {
        let appState = AppState()

        do {
            _ = try await appState.searchIssueReferences(
                matching: "review",
                repositoryFullName: nil,
                includeIssues: true,
                includePullRequests: true
            )
            Issue.record("Expected repository inventory loading error")
        } catch {
            #expect(error.userFacingMessage == "Repository list is still loading. Try again in a moment.")
        }
    }

    @Test
    func `all repository issue search does not fall back to public gitlab when inventory is empty`() async throws {
        let appState = AppState()
        appState.session.hasLoadedRepositories = true

        let matches = try await appState.searchIssueReferences(
            matching: "review",
            repositoryFullName: nil,
            includeIssues: true,
            includePullRequests: true
        )

        #expect(matches.isEmpty)
    }

    private static func makeIssueNavigatorRepo(
        name: String,
        isArchived: Bool = false,
        viewerCanRead: Bool = true,
        openIssues: Int = 0,
        openPulls: Int = 0,
        pushedAt: Date
    ) -> Repository {
        Repository(
            id: "owner/\(name)",
            name: name,
            owner: "owner",
            isArchived: isArchived,
            viewerCanRead: viewerCanRead,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: openIssues,
            openPulls: openPulls,
            pushedAt: pushedAt,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
    }

    private static func makeGitLabReferenceMatch(
        number: Int,
        createdAt: Date,
        updatedAt: Date
    ) throws -> GitLabReferenceMatch {
        let url = try #require(URL(string: "https://gitlab.com/owner/repo/-/issues/\(number)"))
        return GitLabReferenceMatch(
            query: .repositoryIssueNumber(repositoryFullName: "owner/repo", number: number),
            title: "Match \(number)",
            url: url,
            repositoryFullName: "owner/repo",
            kind: .issue,
            state: .open,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
