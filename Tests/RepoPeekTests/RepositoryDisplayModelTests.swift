import Foundation
@testable import RepoPeek
import RepoPeekCore
import Testing

struct RepositoryDisplayModelTests {
    @Test
    func `maps release and activity`() throws {
        let release = try Release(
            name: "v1.0",
            tag: "v1.0",
            publishedAt: Date().addingTimeInterval(-3600),
            url: #require(URL(string: "https://example.com"))
        )
        let activity = try ActivityEvent(
            title: "Fix bug",
            actor: "alice",
            date: Date().addingTimeInterval(-1800),
            url: #require(URL(string: "https://example.com/1"))
        )
        let repo = Repository(
            id: "1",
            name: "Repo",
            owner: "me",
            sortOrder: 0,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .passing,
            openIssues: 2,
            openPulls: 3,
            latestRelease: release,
            latestActivity: activity,
            activityEvents: [activity],
            traffic: TrafficStats(uniqueVisitors: 5, uniqueCloners: 2),
            heatmap: []
        )
        let vm = RepositoryDisplayModel(repo: repo, now: Date())
        #expect(vm.releaseLine?.contains(release.name) == true)
        #expect(vm.activityLine?.contains("alice") == true)
        #expect(vm.activityEvents.count == 1)
        #expect(vm.issues == 2)
        #expect(vm.pulls == 3)
        #expect(vm.trafficVisitors == 5)
    }

    @Test
    func `unknown merge request count renders as placeholder`() throws {
        let vm = RepositoryDisplayModel(repo: Self.repo(openPulls: 0), now: Date())

        let mergeRequestStat = try #require(vm.stats.first { $0.id == "mrs" })
        #expect(mergeRequestStat.value == nil)
        #expect(mergeRequestStat.valueText == "--")
    }

    @Test
    func `hydrated zero merge request count renders as zero`() throws {
        var repo = Self.repo(openPulls: 0)
        repo.detailCacheState = RepoDetailCacheState(
            openPulls: .fresh,
            ci: .missing,
            activity: .missing,
            traffic: .missing,
            heatmap: .missing,
            release: .missing
        )

        let vm = RepositoryDisplayModel(repo: repo, now: Date())

        let mergeRequestStat = try #require(vm.stats.first { $0.id == "mrs" })
        #expect(mergeRequestStat.value == 0)
        #expect(mergeRequestStat.valueText == "0")
    }

    private static func repo(openPulls: Int) -> Repository {
        Repository(
            id: "1",
            name: "Repo",
            owner: "me",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: openPulls,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
    }
}
