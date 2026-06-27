import Foundation
@testable import RepoPeekCore
import Testing

struct RepoPeekCoreModelsTests {
    @Test
    func `user identity init`() throws {
        let host = try #require(URL(string: "https://gitlab.com"))
        let identity = UserIdentity(username: "example", host: host)
        #expect(identity.username == "example")
        #expect(identity.host == host)
    }

    @Test
    func `repository full name and with order`() {
        var repo = Repository(
            id: "1",
            name: "RepoPeek",
            owner: "example",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 1,
            openPulls: 2,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
        #expect(repo.fullName == "example/RepoPeek")
        #expect(repo.lookupKey == "example/repopeek")
        repo = repo.withOrder(5)
        #expect(repo.sortOrder == 5)
    }

    @Test
    func `repository identity lookup key separates same path on different hosts`() {
        let first = Repository(
            id: "1",
            identity: RepositoryIdentity(host: "gitlab.com", projectPath: "group/project"),
            name: "project",
            owner: "group",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
        let second = first.withIdentity(RepositoryIdentity(
            host: "code.company.com",
            projectPath: "group/project"
        ))

        #expect(first.lookupKey == "gitlab.com/group/project")
        #expect(second.lookupKey == "code.company.com/group/project")
        #expect(RepositoryUniquing.byFullName([first, second]).count == 2)
    }

    @Test
    func `repository identity lookup key separates same host accounts`() {
        let first = Repository(
            id: "1",
            identity: RepositoryIdentity(
                host: "gitlab.example.com",
                projectPath: "group/project",
                accountID: "gitlab.example.com#alice"
            ),
            name: "project",
            owner: "group",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
        let second = first.withIdentity(RepositoryIdentity(
            host: "gitlab.example.com",
            projectPath: "group/project",
            accountID: "gitlab.example.com#bob"
        ))

        #expect(first.lookupKey == "gitlab.example.com#alice/group/project")
        #expect(second.lookupKey == "gitlab.example.com#bob/group/project")
        #expect(RepositoryUniquing.byFullName([first, second]).count == 2)
    }

    @Test
    func `local projects refresh interval labels`() {
        #expect(LocalProjectsRefreshInterval.oneMinute.label == "1 minute")
        #expect(LocalProjectsRefreshInterval.twoMinutes.label == "2 minutes")
        #expect(LocalProjectsRefreshInterval.fiveMinutes.label == "5 minutes")
        #expect(LocalProjectsRefreshInterval.fifteenMinutes.label == "15 minutes")
        #expect(LocalProjectsRefreshInterval.oneHour.label == "1 hour")
        #expect(LocalProjectsRefreshInterval.fiveMinutes.seconds == 300)
        #expect(LocalProjectsRefreshInterval.oneHour.seconds == 3600)
    }

    @Test
    func `user settings defaults`() {
        let settings = UserSettings()
        #expect(settings.localProjects.worktreeFolderName == ".work")
        #expect(settings.localProjects.autoSyncEnabled == false)
        #expect(settings.localProjects.fetchInterval == .oneHour)
        #expect(settings.refreshInterval == .sixHours)
    }

    @Test
    func `refresh interval migrates legacy values to six hours`() throws {
        let stringData = Data(#"{"refreshInterval":"fifteenMinutes"}"#.utf8)
        let keyedData = Data(#"{"refreshInterval":{"fiveMinutes":{}}}"#.utf8)

        #expect(try JSONDecoder().decode(UserSettings.self, from: stringData).refreshInterval == .sixHours)
        #expect(try JSONDecoder().decode(UserSettings.self, from: keyedData).refreshInterval == .sixHours)
    }

    @Test
    func `repo recent items init`() throws {
        let now = Date()
        let url = try #require(URL(string: "https://example.com"))
        _ = RepoIssueSummary(
            number: 1,
            title: "Issue",
            url: url,
            updatedAt: now,
            authorLogin: "user",
            authorAvatarURL: url,
            assigneeLogins: ["a"],
            commentCount: 2,
            labels: [RepoIssueLabel(name: "bug", colorHex: "ff0000")]
        )
        _ = RepoPullRequestSummary(
            number: 2,
            title: "MR",
            url: url,
            updatedAt: now,
            authorLogin: nil,
            authorAvatarURL: nil,
            isDraft: false,
            commentCount: 1,
            reviewCommentCount: 0,
            labels: [],
            headRefName: "feature",
            baseRefName: "main"
        )
        _ = RepoReleaseSummary(
            name: "v1",
            tag: "v1.0",
            url: url,
            publishedAt: now,
            isPrerelease: false,
            authorLogin: "user",
            authorAvatarURL: url,
            assetCount: 1,
            downloadCount: 2,
            assets: []
        )
        _ = RepoWorkflowRunSummary(
            name: "CI",
            url: url,
            updatedAt: now,
            status: .passing,
            conclusion: "success",
            branch: "main",
            event: "push",
            actorLogin: "user",
            actorAvatarURL: url,
            runNumber: 12
        )
        _ = RepoTagSummary(name: "v1.0", commitSHA: "abc123")
    }

    @Test
    func `gitlab reference matches prefer newest created date`() throws {
        let url = try #require(URL(string: "https://example.com"))
        let older = GitLabReferenceMatch(
            query: .issueNumber(42),
            title: "Older",
            url: url,
            repositoryFullName: "owner/old",
            kind: .issue,
            state: .open,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let newer = GitLabReferenceMatch(
            query: .issueNumber(42),
            title: "Newer",
            url: url,
            repositoryFullName: "owner/new",
            kind: .pullRequest,
            state: .closed,
            createdAt: Date(timeIntervalSinceReferenceDate: 20),
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        )

        #expect(GitLabReferenceMatch.newestCreated(in: [older, newer])?.repositoryFullName == "owner/new")
    }

    @Test
    func `gitlab reference match stores preview metadata`() throws {
        let url = try #require(URL(string: "https://example.com"))
        let match = GitLabReferenceMatch(
            query: .repositoryIssueNumber(repositoryFullName: "owner/repo", number: 5),
            title: "Title",
            url: url,
            repositoryFullName: "owner/repo",
            kind: .pullRequest,
            state: .open,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 20),
            bodyPreview: "Preview text",
            authorLogin: "alice",
            aiSummary: " Summary text "
        )

        #expect(match.bodyPreview == "Preview text")
        #expect(match.authorLogin == "alice")
        #expect(match.aiSummary == "Summary text")

        let updated = match.withAISummary(" Updated summary ")
        #expect(updated.aiSummary == "Updated summary")
        #expect(updated.bodyPreview == "Preview text")
    }

    @Test
    func `gitlab reference query display text`() {
        #expect(GitLabReferenceQuery.issueNumber(7).displayText == "#7")
        #expect(GitLabReferenceState.open.label == "Open")
        #expect(GitLabReferenceState.closed.label == "Closed")
        #expect(GitLabReferenceState.merged.label == "Merged")
        #expect(
            GitLabReferenceQuery.repositoryNameIssueNumber(
                repositoryName: "discrawl",
                number: 64
            ).displayText == "discrawl#64"
        )
        #expect(
            GitLabReferenceQuery.repositoryIssueNumber(
                repositoryFullName: "example/example",
                number: 73655
            ).displayText == "example/example#73655"
        )
        #expect(GitLabReferenceQuery.commitHash("ffd212ca43abcdef").displayText == "ffd212ca43")
        #expect(
            GitLabReferenceQuery.repositoryCommitHash(
                repositoryFullName: "example/example",
                hash: "ffd212ca43abcdef"
            ).displayText == "example/example@ffd212ca43"
        )
        #expect(
            GitLabReferenceQuery.repositoryWorkflowRun(
                repositoryFullName: "example/songsee",
                runID: 25_620_622_163
            ).displayText == "example/songsee run 25620622163"
        )
        let scoped = GitLabReferenceQuery.repositoryIssueNumber(
            repositoryFullName: "example/example",
            number: 73655
        )
        #expect(scoped.repositoryOwnerAndName?.owner == "example")
        #expect(scoped.repositoryOwnerAndName?.name == "example")
    }

    @Test
    func `backoff tracker lifecycle`() async throws {
        let tracker = BackoffTracker()
        let url = try #require(URL(string: "https://example.com"))
        let now = Date()
        #expect(await tracker.isCoolingDown(url: url, now: now) == false)
        await tracker.setCooldown(url: url, until: now.addingTimeInterval(60))
        #expect(await tracker.isCoolingDown(url: url, now: now) == true)
        #expect(await tracker.cooldown(for: url, now: now) != nil)
        #expect(await tracker.count() == 1)
        await tracker.clear()
        #expect(await tracker.count() == 0)
    }

    @Test
    func `git executable locator version`() {
        let result = GitExecutableLocator.version(at: URL(fileURLWithPath: "/usr/bin/git"))
        #expect(result.version != nil)
        #expect(result.error == nil)
    }
}
