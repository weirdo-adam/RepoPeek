import Foundation
@testable import RepoPeekCore
import Testing

struct RepositoryFactoryTests {
    @Test
    func `gitlab project maps repository fields`() throws {
        let json = """
        {
          "id": 42,
          "name": "RepoPeek",
          "path": "RepoPeek",
          "path_with_namespace": "example/RepoPeek",
          "archived": true,
          "open_issues_count": 7,
          "star_count": 99,
          "forks_count": 12,
          "last_activity_at": "2025-01-01T00:00:00Z",
          "web_url": "https://gitlab.example.com/example/RepoPeek",
          "namespace": { "full_path": "example" },
          "forked_from_project": {}
        }
        """

        let project = try JSONDecoding.decode(GitLabProject.self, from: Data(json.utf8))
        let repo = try project.repository(webHost: #require(URL(string: "https://gitlab.example.com")))

        #expect(repo.id == "gitlab.example.com/example/repopeek")
        #expect(repo.name == "RepoPeek")
        #expect(repo.owner == "example")
        #expect(repo.isFork == true)
        #expect(repo.isArchived == true)
        #expect(repo.viewerCanRead == true)
        #expect(repo.openIssues == 7)
        #expect(repo.openPulls == 0)
        #expect(repo.stars == 99)
        #expect(repo.forks == 12)
        #expect(repo.ciStatus == .unknown)
        #expect(repo.latestActivity?.title == "Project activity")
        #expect(repo.latestActivity?.actor == "example")
        #expect(repo.activityEvents.count == 1)
        #expect(repo.fullName == "example/RepoPeek")
    }

    @Test
    func `manual repository preserves error and fallback full name`() {
        let limitedUntil = Date(timeIntervalSinceReferenceDate: 999)
        let repo = Repository(
            id: "me/Repo",
            name: "Repo",
            owner: "me",
            sortOrder: nil,
            error: "oops",
            rateLimitedUntil: limitedUntil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )

        #expect(repo.id == "me/Repo")
        #expect(repo.fullName == "me/Repo")
        #expect(repo.error == "oops")
        #expect(repo.rateLimitedUntil == limitedUntil)
        #expect(repo.openIssues == 0)
        #expect(repo.openPulls == 0)
        #expect(repo.stars == 0)
        #expect(repo.forks == 0)
        #expect(repo.heatmap.isEmpty)
    }
}
