import Foundation
@testable import RepoPeekCore
import Testing

struct GlobalActivityTests {
    @Test
    func `global activity scope labels`() {
        #expect(GlobalActivityScope.allActivity.label == "All activity")
        #expect(GlobalActivityScope.myActivity.label == "My activity")
    }

    @Test
    func `repository events include latest activity fallback`() throws {
        let url = try #require(URL(string: "https://gitlab.com/example/RepoPeek/-/commit/abc"))
        let latest = ActivityEvent(
            title: "Push",
            actor: "example",
            date: Date(timeIntervalSinceReferenceDate: 100),
            url: url,
            eventType: "pushed"
        )
        let repo = Repository(
            id: "1",
            name: "RepoPeek",
            owner: "example",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: latest,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )

        let events = GlobalActivityMerger.repositoryEvents(from: [repo])

        #expect(events == [latest])
    }

    @Test
    func `repository events prefer explicit event list`() throws {
        let url = try #require(URL(string: "https://gitlab.com/example/RepoPeek"))
        let latest = ActivityEvent(
            title: "Project activity",
            actor: "example",
            date: Date(timeIntervalSinceReferenceDate: 100),
            url: url,
            eventType: "updated"
        )
        let explicit = ActivityEvent(
            title: "Opened merge request",
            actor: "bot",
            date: Date(timeIntervalSinceReferenceDate: 200),
            url: url.appending(path: "-/merge_requests/1"),
            eventType: "MergeRequest"
        )
        let repo = Repository(
            id: "1",
            name: "RepoPeek",
            owner: "example",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: latest,
            activityEvents: [explicit],
            traffic: nil,
            heatmap: []
        )

        #expect(GlobalActivityMerger.repositoryEvents(from: [repo]) == [explicit])
    }

    @Test
    func `global activity merge dedupes and keeps newest actor scoped events`() throws {
        let firstURL = try #require(URL(string: "https://gitlab.com/example/RepoPeek/-/commit/abc"))
        let secondURL = try #require(URL(string: "https://gitlab.com/example/RepoPeek/-/merge_requests/1"))
        let first = ActivityEvent(title: "Push", actor: "example", date: Date(timeIntervalSinceReferenceDate: 100), url: firstURL)
        let second = ActivityEvent(title: "Merge Request", actor: "example", date: Date(timeIntervalSinceReferenceDate: 200), url: secondURL)
        let other = ActivityEvent(title: "Push", actor: "bot", date: Date(timeIntervalSinceReferenceDate: 300), url: firstURL)

        let events = GlobalActivityMerger.merge(
            userEvents: [first],
            repoEvents: [other, second, first],
            scope: .myActivity,
            username: "example",
            limit: 10
        )

        #expect(events == [second, first])
    }
}
