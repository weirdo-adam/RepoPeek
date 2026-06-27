import Foundation
@testable import RepoPeekCore
import Testing

struct RateLimitStatusFormatterTests {
    @Test
    func `compact summary uses observed cached rate limits`() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let summary = RepoPeekCacheSummary(
            databasePath: "/tmp/cache.sqlite",
            exists: true,
            apiResponseCount: 1,
            rateLimitCount: 0,
            latestResponses: [
                RepoPeekCachedResponseSummary(
                    method: "GET",
                    url: "https://gitlab.example.com/api/v4/projects",
                    hasETag: true,
                    statusCode: 200,
                    fetchedAt: now,
                    rateLimitResource: "core",
                    rateLimitRemaining: 4901,
                    rateLimitReset: now.addingTimeInterval(600)
                )
            ],
            rateLimits: []
        )

        let text = RateLimitStatusFormatter.compactSummary(
            diagnostics: .empty,
            cacheSummary: summary,
            now: now
        )

        #expect(text.contains("core"))
        #expect(text.contains("4.9K left"))
    }

    @Test
    func `sections separate observed and active limits`() {
        let now = Date(timeIntervalSinceReferenceDate: 2000)
        let summary = RepoPeekCacheSummary(
            databasePath: "/tmp/cache.sqlite",
            exists: true,
            apiResponseCount: 1,
            rateLimitCount: 1,
            latestResponses: [
                RepoPeekCachedResponseSummary(
                    method: "GET",
                    url: "https://gitlab.example.com/api/v4/search",
                    hasETag: false,
                    statusCode: 200,
                    fetchedAt: now,
                    rateLimitResource: "search",
                    rateLimitRemaining: 29,
                    rateLimitReset: now.addingTimeInterval(60)
                )
            ],
            rateLimits: [
                RepoPeekRateLimitSummary(
                    resource: "core",
                    remaining: 0,
                    resetAt: now.addingTimeInterval(120),
                    lastError: "API rate limit exceeded"
                )
            ]
        )

        let sections = RateLimitStatusFormatter.sections(
            diagnostics: .empty,
            cacheSummary: summary,
            now: now
        )

        #expect(sections.map(\.title) == ["Current Blocker", "REST Search"])
        #expect(sections[0].resourceRows.first?.text == "core blocked")
        #expect(sections[0].resourceRows.first?.detailText == "API rate limit exceeded")
        #expect(sections[1].rows.first?.contains("search") == true)
    }

    @Test
    func `sections group observed resources by gitlab bucket family`() {
        let now = Date(timeIntervalSinceReferenceDate: 3000)
        let summary = RepoPeekCacheSummary(
            databasePath: "/tmp/cache.sqlite",
            exists: true,
            apiResponseCount: 3,
            rateLimitCount: 0,
            latestResponses: [
                RepoPeekCachedResponseSummary(
                    method: "GET",
                    url: "https://gitlab.example.com/api/v4/projects/1",
                    hasETag: false,
                    statusCode: 200,
                    fetchedAt: now,
                    rateLimitResource: "core",
                    rateLimitLimit: 5000,
                    rateLimitRemaining: 4990,
                    rateLimitReset: now.addingTimeInterval(600)
                ),
                RepoPeekCachedResponseSummary(
                    method: "GET",
                    url: "https://gitlab.example.com/api/v4/search",
                    hasETag: false,
                    statusCode: 200,
                    fetchedAt: now,
                    rateLimitResource: "search",
                    rateLimitLimit: 30,
                    rateLimitRemaining: 25,
                    rateLimitReset: now.addingTimeInterval(600)
                ),
                RepoPeekCachedResponseSummary(
                    method: "GET",
                    url: "https://gitlab.example.com/api/v4/version",
                    hasETag: false,
                    statusCode: 200,
                    fetchedAt: now,
                    rateLimitResource: "metadata",
                    rateLimitLimit: 1000,
                    rateLimitRemaining: 800,
                    rateLimitReset: now.addingTimeInterval(600)
                )
            ],
            rateLimits: []
        )

        let sections = RateLimitStatusFormatter.sections(
            diagnostics: .empty,
            cacheSummary: summary,
            now: now
        )

        #expect(sections.map(\.title) == ["Current Status", "REST Core", "REST Search", "Other Resources"])
        #expect(sections[1].rows.first?.contains("core") == true)
        #expect(sections[2].rows.first?.contains("search") == true)
        #expect(sections[3].rows.first?.contains("metadata") == true)
    }

    @Test
    func `sections render live REST rate limit snapshot`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 4000)
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://gitlab.example.com/api/v4")),
            rateLimitReset: nil,
            lastRateLimitError: nil,
            etagEntries: 0,
            backoffEntries: 0,
            restRateLimit: RateLimitSnapshot(
                resource: "core",
                limit: 5000,
                remaining: 3900,
                used: 1100,
                reset: now.addingTimeInterval(600),
                fetchedAt: now
            )
        )

        let sections = RateLimitStatusFormatter.sections(
            diagnostics: diagnostics,
            cacheSummary: nil,
            now: now
        )

        #expect(sections.map(\.title) == ["Current Status", "Details"])
        #expect(sections[1].rows[0].contains("REST: core · 3900/5000 · resets in 10 min."))
        #expect(sections[1].resourceRows[0].text.contains("REST: core"))

        let cachedCore = RepoPeekCacheSummary(
            databasePath: "/tmp/cache.sqlite",
            exists: true,
            apiResponseCount: 1,
            rateLimitCount: 0,
            latestResponses: [
                RepoPeekCachedResponseSummary(
                    method: "GET",
                    url: "https://gitlab.example.com/api/v4/projects",
                    hasETag: true,
                    statusCode: 200,
                    fetchedAt: now,
                    rateLimitResource: "core",
                    rateLimitLimit: 5000,
                    rateLimitRemaining: 3800,
                    rateLimitReset: now.addingTimeInterval(600)
                )
            ],
            rateLimits: []
        )

        let sectionsWithCache = RateLimitStatusFormatter.sections(
            diagnostics: diagnostics,
            cacheSummary: cachedCore,
            now: now
        )
        #expect(sectionsWithCache.map(\.title) == ["Current Status", "Details", "REST Core"])
    }

    @Test
    func `sections show endpoint cooldowns`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 5000)
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://gitlab.example.com/api/v4")),
            rateLimitReset: nil,
            lastRateLimitError: nil,
            etagEntries: 0,
            backoffEntries: 1,
            endpointCooldowns: [
                EndpointCooldownSummary(
                    endpoint: "commit activity",
                    repository: "example/clawsweeper-state",
                    url: "https://gitlab.example.com/api/v4/projects/example%2Fclawsweeper-state/events",
                    retryAfter: now.addingTimeInterval(60)
                )
            ],
            restRateLimit: nil
        )

        let sections = RateLimitStatusFormatter.sections(
            diagnostics: diagnostics,
            cacheSummary: nil,
            now: now
        )

        #expect(sections.map(\.title) == ["Current Blocker", "Endpoint Cooldowns"])
        #expect(sections[0].resourceRows.first?.text == "Endpoint cooldown")
        #expect(sections[0].resourceRows.first?.detailText == "example/clawsweeper-state commit activity · retry in 1 min.")
        #expect(sections[1].rows == ["example/clawsweeper-state commit activity · retry in 1 min."])
    }

    @Test
    func `compact summary mentions endpoint cooldown first`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 6000)
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://gitlab.example.com/api/v4")),
            rateLimitReset: nil,
            lastRateLimitError: nil,
            etagEntries: 0,
            backoffEntries: 1,
            endpointCooldowns: [
                EndpointCooldownSummary(
                    endpoint: "commit activity",
                    repository: "example/example",
                    url: "https://gitlab.example.com/api/v4/projects/example%2Fexample/events",
                    retryAfter: now.addingTimeInterval(30)
                )
            ],
            restRateLimit: RateLimitSnapshot(
                resource: "core",
                limit: 5000,
                remaining: 4400,
                used: 600,
                reset: now.addingTimeInterval(600),
                fetchedAt: now
            )
        )

        let summary = RateLimitStatusFormatter.compactSummary(
            diagnostics: diagnostics,
            cacheSummary: nil,
            now: now
        )
        let state = RateLimitDisplayState(diagnostics: diagnostics)

        #expect(summary == "Blocked: Endpoint cooldown · example/example commit activity · retry in 30 sec.")
        #expect(state.isLimited(now: now))
    }

    @Test
    func `current blocker explains shared token budget while live bucket stays visible`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 7000)
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://gitlab.example.com/api/v4")),
            rateLimitReset: now.addingTimeInterval(120),
            lastRateLimitError: "GitLab rate limit hit; resets in 2 min.",
            etagEntries: 0,
            backoffEntries: 0,
            restRateLimit: RateLimitSnapshot(
                resource: "core",
                limit: 5000,
                remaining: 2692,
                used: 2308,
                reset: now.addingTimeInterval(120),
                fetchedAt: now
            )
        )

        let summary = RateLimitStatusFormatter.compactSummary(
            diagnostics: diagnostics,
            cacheSummary: nil,
            now: now
        )
        let sections = RateLimitStatusFormatter.sections(
            diagnostics: diagnostics,
            cacheSummary: nil,
            now: now
        )

        #expect(summary.contains("Blocked: REST core blocked"))
        #expect(summary.contains("Shared GitLab user budget"))
        #expect(sections.map(\.title) == ["Current Blocker", "Details"])
        #expect(sections[0].resourceRows.first?.quotaText == "0 left")
        #expect(sections[0].resourceRows.first?.resetText == "resets in 2 min.")
        #expect(sections[1].resourceRows.first?.text.contains("2692/5000") == true)
    }

    @Test
    func `budget model explains auth actor and shared token budget`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 8000)
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://gitlab.example.com/api/v4")),
            rateLimitReset: now.addingTimeInterval(120),
            lastRateLimitError: "GitLab rate limit hit; resets in 2 min.",
            etagEntries: 0,
            backoffEntries: 0,
            restRateLimit: nil
        )

        let sections = RateLimitStatusFormatter.sections(
            diagnostics: diagnostics,
            cacheSummary: nil,
            authMethod: .pat,
            now: now
        )

        #expect(sections.map(\.title).prefix(2) == ["Current Blocker", "Budget Model"])
        #expect(sections[1].rows.contains("RepoPeek auth: PAT"))
        #expect(sections[1].rows.contains("Budget actor: token owner"))
        #expect(sections[1].rows.contains { $0.contains("PAT owner") })
        #expect(sections[1].rows.contains { $0.contains("Other GitLab clients may still work") })
    }
}
