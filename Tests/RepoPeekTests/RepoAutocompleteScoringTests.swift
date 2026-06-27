import Foundation
@testable import RepoPeekCore
import Testing

struct RepoAutocompleteScoringTests {
    @Test
    func `exact full name wins`() {
        let exact = Self.repo(owner: "example", name: "RepoPeek")
        let prefix = Self.repo(owner: "example", name: "Repo")

        let scored = RepoAutocompleteScoring.scored(
            repos: [prefix, exact],
            query: "example/RepoPeek",
            sourceRank: 0
        )
        let sorted = RepoAutocompleteScoring.sort(scored)
        #expect(sorted.first?.repo.fullName == "example/RepoPeek")
    }

    @Test
    func `repo name beats owner match`() {
        let ownerMatch = Self.repo(owner: "repo", name: "alpha")
        let repoMatch = Self.repo(owner: "example", name: "repo")

        let scored = RepoAutocompleteScoring.scored(
            repos: [ownerMatch, repoMatch],
            query: "repo",
            sourceRank: 0
        )
        let sorted = RepoAutocompleteScoring.sort(scored)
        #expect(sorted.first?.repo.fullName == "example/repo")
    }

    @Test
    func `subsequence matches are included`() {
        let repo = Self.repo(owner: "example", name: "RepoPeek")
        let score = RepoAutocompleteScoring.score(repo: repo, query: "rpk")
        #expect(score != nil)
    }

    @Test
    func `owner plus repo beats repo only`() {
        let exactOwner = Self.repo(owner: "example", name: "repo")
        let otherOwner = Self.repo(owner: "other", name: "repo")

        let scored = RepoAutocompleteScoring.scored(
            repos: [otherOwner, exactOwner],
            query: "example/repo",
            sourceRank: 0
        )
        let sorted = RepoAutocompleteScoring.sort(scored)
        #expect(sorted.first?.repo.fullName == "example/repo")
    }

    @Test
    func `slash query does not score owner only match`() {
        let repo = Self.repo(owner: "example/frontend", name: "web-frontend")
        #expect(RepoAutocompleteScoring.score(repo: repo, query: "example/search") == nil)
    }

    @Test
    func `slash query can match repo name under deeper group`() {
        let repo = Self.repo(owner: "example/frontend", name: "search-web")
        #expect(RepoAutocompleteScoring.score(repo: repo, query: "example/search") != nil)
    }
}

private extension RepoAutocompleteScoringTests {
    static func repo(owner: String, name: String) -> Repository {
        Repository(
            id: UUID().uuidString,
            name: name,
            owner: owner,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: 0,
            openPulls: 0,
            stars: 0,
            pushedAt: nil,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
    }
}
