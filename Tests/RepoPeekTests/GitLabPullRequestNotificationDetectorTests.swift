import Foundation
@testable import RepoPeekCore
import Testing

struct GitLabPullRequestNotificationDetectorTests {
    @Test
    func `first snapshot does not emit backlog`() {
        let settings = Self.enabledSettings()
        let pull = Self.pull(number: 1, updatedAt: Self.date(100))

        let result = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [pull]],
            previousState: GitLabPullRequestNotificationSnapshotState(),
            settings: settings,
            observedAt: Self.date(150)
        )

        #expect(result.events.isEmpty)
        #expect(result.state.repositories["example/repopeek"]?[1]?.updatedAt == Self.date(100))
        #expect(result.state.repositoryBaselines["example/repopeek"] == Self.date(150))
    }

    @Test
    func `new merge request emits after initial snapshot`() {
        let settings = Self.enabledSettings()
        let first = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(100))]],
            previousState: GitLabPullRequestNotificationSnapshotState(),
            settings: settings,
            observedAt: Self.date(150)
        )

        let second = GitLabPullRequestNotificationDetector.events(
            for: [
                "example/RepoPeek": [
                    Self.pull(number: 2, updatedAt: Self.date(200)),
                    Self.pull(number: 1, updatedAt: Self.date(100))
                ]
            ],
            previousState: first.state,
            settings: settings,
            observedAt: Self.date(250)
        )

        #expect(second.events.count == 1)
        #expect(second.events.first?.kind == .newPullRequest)
        #expect(second.events.first?.pullRequestNumber == 2)
    }

    @Test
    func `old merge request re-entering recent window does not emit as new`() {
        let settings = Self.enabledSettings()
        let first = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 10, updatedAt: Self.date(100))]],
            previousState: GitLabPullRequestNotificationSnapshotState(),
            settings: settings,
            observedAt: Self.date(150)
        )

        let second = GitLabPullRequestNotificationDetector.events(
            for: [
                "example/RepoPeek": [
                    Self.pull(number: 2, updatedAt: Self.date(300), createdAt: Self.date(90)),
                    Self.pull(number: 10, updatedAt: Self.date(100))
                ]
            ],
            previousState: first.state,
            settings: settings,
            observedAt: Self.date(350)
        )

        #expect(second.events.isEmpty)
        #expect(second.state.repositories["example/repopeek"]?[2]?.updatedAt == Self.date(300))
    }

    @Test
    func `updated merge request emits once for changed updated at`() {
        let settings = Self.enabledSettings()
        let first = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(100))]],
            previousState: GitLabPullRequestNotificationSnapshotState(),
            settings: settings
        )

        let second = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(200))]],
            previousState: first.state,
            settings: settings
        )
        let third = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(200))]],
            previousState: second.state,
            settings: settings
        )

        #expect(second.events.count == 1)
        #expect(second.events.first?.kind == .pullRequestUpdated)
        #expect(third.events.isEmpty)
    }

    @Test
    func `comment notifications are opt in and suppress generic update duplicate`() {
        var settings = Self.enabledSettings()
        settings.comments = true
        let first = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(100), comments: 1)]],
            previousState: GitLabPullRequestNotificationSnapshotState(),
            settings: settings
        )

        let second = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(200), comments: 2)]],
            previousState: first.state,
            settings: settings
        )

        #expect(second.events.count == 1)
        #expect(second.events.first?.kind == .newComment)
        #expect(second.events.first?.detail == "1 new comment")
    }

    @Test
    func `enabling comment notifications baselines existing counts before emitting`() {
        let disabled = Self.enabledSettings()
        let first = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(100))]],
            previousState: GitLabPullRequestNotificationSnapshotState(),
            settings: disabled,
            observedAt: Self.date(150)
        )

        var enabled = disabled
        enabled.comments = true
        let baseline = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(200), comments: 4, reviewComments: 2)]],
            previousState: first.state,
            settings: enabled,
            observedAt: Self.date(250)
        )
        let next = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(300), comments: 5, reviewComments: 2)]],
            previousState: baseline.state,
            settings: enabled,
            observedAt: Self.date(350)
        )

        #expect(baseline.events.first?.kind != .newComment)
        #expect(baseline.state.commentTrackingRepositories == ["example/repopeek"])
        #expect(next.events.count == 1)
        #expect(next.events.first?.kind == .newComment)
        #expect(next.events.first?.detail == "1 new comment")
    }

    @Test
    func `review request notifications are opt in`() {
        var settings = Self.enabledSettings()
        settings.reviewRequests = true
        let first = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(100))]],
            previousState: GitLabPullRequestNotificationSnapshotState(),
            settings: settings
        )

        let second = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(200), reviewers: ["alice"])]],
            previousState: first.state,
            settings: settings
        )

        #expect(second.events.count == 1)
        #expect(second.events.first?.kind == .reviewRequested)
        #expect(second.events.first?.detail == "Review requested from alice")
    }

    @Test
    func `merged merge request emits as update`() {
        let settings = Self.enabledSettings()
        let first = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(100))]],
            previousState: GitLabPullRequestNotificationSnapshotState(),
            settings: settings
        )

        let second = GitLabPullRequestNotificationDetector.events(
            for: [
                "example/RepoPeek": [
                    Self.pull(
                        number: 1,
                        updatedAt: Self.date(200),
                        state: .closed,
                        mergedAt: Self.date(190)
                    )
                ]
            ],
            previousState: first.state,
            settings: settings
        )

        #expect(second.events.count == 1)
        #expect(second.events.first?.kind == .pullRequestUpdated)
        #expect(second.events.first?.detail == "MR merged")
    }

    @Test
    func `reopened merge request emits as update`() {
        let settings = Self.enabledSettings()
        let first = GitLabPullRequestNotificationDetector.events(
            for: [
                "example/RepoPeek": [
                    Self.pull(number: 1, updatedAt: Self.date(100), state: .closed)
                ]
            ],
            previousState: GitLabPullRequestNotificationSnapshotState(),
            settings: settings
        )

        let second = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(200), state: .open)]],
            previousState: first.state,
            settings: settings
        )

        #expect(second.events.count == 1)
        #expect(second.events.first?.kind == .pullRequestUpdated)
        #expect(second.events.first?.detail == "MR reopened")
    }

    @Test
    func `disabled settings do not update snapshots`() {
        var settings = Self.enabledSettings()
        settings.enabled = false
        let previous = GitLabPullRequestNotificationSnapshotState()

        let result = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(100))]],
            previousState: previous,
            settings: settings
        )

        #expect(result.events.isEmpty)
        #expect(result.state == previous)
    }

    @Test
    func `state is pruned to tracked repositories without replaying unpinned repositories`() {
        let settings = Self.enabledSettings()
        let previous = GitLabPullRequestNotificationSnapshotState(
            repositories: [
                "example/repopeek": [
                    1: GitLabPullRequestNotificationSnapshot(
                        updatedAt: Self.date(100),
                        commentCount: 0,
                        reviewCommentCount: 0,
                        requestedReviewerLogins: [],
                        requestedTeamNames: []
                    )
                ],
                "example/repo-alpha": [
                    2: GitLabPullRequestNotificationSnapshot(
                        updatedAt: Self.date(100),
                        commentCount: 0,
                        reviewCommentCount: 0,
                        requestedReviewerLogins: [],
                        requestedTeamNames: []
                    )
                ]
            ],
            repositoryBaselines: [
                "example/repopeek": Self.date(150),
                "example/repo-alpha": Self.date(150)
            ],
            commentTrackingRepositories: ["example/repopeek", "example/repo-alpha"]
        )

        let result = GitLabPullRequestNotificationDetector.events(
            for: ["example/RepoPeek": [Self.pull(number: 1, updatedAt: Self.date(100))]],
            previousState: previous,
            settings: settings,
            trackedRepositoryFullNames: ["example/RepoPeek"]
        )

        #expect(result.events.isEmpty)
        #expect(result.state.repositories.keys.sorted() == ["example/repopeek"])
        #expect(result.state.repositoryBaselines.keys.sorted() == ["example/repopeek"])
        #expect(result.state.commentTrackingRepositories.isEmpty)
    }

    @Test
    func `re-pinned repository starts from fresh baseline after pruning`() {
        let settings = Self.enabledSettings()
        let previous = GitLabPullRequestNotificationSnapshotState(
            repositories: [
                "example/repo-alpha": [
                    2: GitLabPullRequestNotificationSnapshot(
                        updatedAt: Self.date(100),
                        commentCount: 0,
                        reviewCommentCount: 0,
                        requestedReviewerLogins: [],
                        requestedTeamNames: []
                    )
                ]
            ],
            repositoryBaselines: ["example/repo-alpha": Self.date(150)]
        )

        let pruned = GitLabPullRequestNotificationDetector.events(
            for: [:],
            previousState: previous,
            settings: settings,
            trackedRepositoryFullNames: ["example/RepoPeek"]
        )
        let rePinned = GitLabPullRequestNotificationDetector.events(
            for: ["example/repo-alpha": [Self.pull(number: 2, updatedAt: Self.date(300))]],
            previousState: pruned.state,
            settings: settings,
            trackedRepositoryFullNames: ["example/repo-alpha"],
            observedAt: Self.date(350)
        )

        #expect(pruned.state.repositories.isEmpty)
        #expect(pruned.state.repositoryBaselines.isEmpty)
        #expect(rePinned.events.isEmpty)
        #expect(rePinned.state.repositories["example/repo-alpha"]?[2]?.updatedAt == Self.date(300))
    }

    private static func enabledSettings() -> GitLabPullRequestNotificationSettings {
        var settings = GitLabPullRequestNotificationSettings()
        settings.enabled = true
        return settings
    }

    private static func pull(
        number: Int,
        updatedAt: Date,
        createdAt: Date? = nil,
        state: RepoPullRequestSummary.State = .open,
        mergedAt: Date? = nil,
        comments: Int = 0,
        reviewComments: Int = 0,
        reviewers: [String] = []
    ) -> RepoPullRequestSummary {
        RepoPullRequestSummary(
            number: number,
            title: "Improve notifications",
            url: URL(string: "https://gitlab.com/example/RepoPeek/-/merge_requests/\(number)")!,
            updatedAt: updatedAt,
            createdAt: createdAt ?? updatedAt,
            state: state,
            mergedAt: mergedAt,
            authorLogin: "octocat",
            authorAvatarURL: nil,
            isDraft: false,
            commentCount: comments,
            reviewCommentCount: reviewComments,
            labels: [],
            headRefName: "feature",
            baseRefName: "main",
            requestedReviewerLogins: reviewers
        )
    }

    private static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
