import Foundation
import RepoPeekCore
import Testing

struct RepoAutocompleteSuggestionsTests {
    @Test
    func `empty query returns recents prefix`() {
        let prefetched = [
            Self.make("example/RepoPeek"),
            Self.make("example/repo-alpha"),
            Self.make("acme-org/sample-app")
        ]

        let results = RepoAutocompleteSuggestions.suggestions(query: "  ", prefetched: prefetched, limit: 2)
        #expect(results.map(\.fullName) == ["example/RepoPeek", "example/repo-alpha"])
    }

    @Test
    func `non matching query does not fallback to recents`() {
        let prefetched = [
            Self.make("example/RepoPeek"),
            Self.make("acme-org/sample-app")
        ]

        let results = RepoAutocompleteSuggestions.suggestions(query: "zzzz-not-a-repo", prefetched: prefetched, limit: 8)
        #expect(results.isEmpty)
    }

    @Test
    func `matching query filters and ranks by name`() {
        let prefetched = [
            Self.make("example/RepoPeek"),
            Self.make("acme-org/sample-app"),
            Self.make("example/repo-alpha")
        ]

        let results = RepoAutocompleteSuggestions.suggestions(query: "sample", prefetched: prefetched, limit: 8)
        #expect(results.first?.fullName == "acme-org/sample-app")
        #expect(results.contains(where: { $0.fullName == "example/RepoPeek" }) == false)
    }

    @Test
    func `slash query requires final repository segment match`() {
        let prefetched = [
            Self.make("example/frontend/web-frontend"),
            Self.make("example/search-service")
        ]

        let results = RepoAutocompleteSuggestions.suggestions(query: "example/search", prefetched: prefetched, limit: 8)
        #expect(results.map(\.fullName) == ["example/search-service"])
    }

    @Test
    func `slash query does not return owner only matches`() {
        let prefetched = [
            Self.make("example/frontend/web-frontend")
        ]

        let results = RepoAutocompleteSuggestions.suggestions(query: "example/search", prefetched: prefetched, limit: 8)
        #expect(results.isEmpty)
    }
}

private extension RepoAutocompleteSuggestionsTests {
    static func make(_ fullName: String) -> Repository {
        let parts = fullName.split(separator: "/").map(String.init)
        let owner = parts.dropLast().joined(separator: "/")
        let name = parts.last ?? fullName
        return Repository(
            id: fullName,
            name: name,
            owner: owner,
            isFork: false,
            isArchived: false,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: 0,
            openPulls: 0,
            stars: 0,
            forks: 0,
            pushedAt: nil,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )
    }
}
