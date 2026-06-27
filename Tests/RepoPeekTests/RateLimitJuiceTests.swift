import Foundation
@testable import RepoPeekCore
import Testing

struct RateLimitJuiceTests {
    @Test
    func `uses live diagnostics before cached responses`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://api.gitlab.com")),
            rateLimitReset: nil,
            lastRateLimitError: nil,
            etagEntries: 0,
            backoffEntries: 0,
            restRateLimit: RateLimitSnapshot(
                resource: "core",
                limit: 5000,
                remaining: 2500,
                used: 2500,
                reset: now.addingTimeInterval(60),
                fetchedAt: now
            )
        )

        let juice = RateLimitJuice(diagnostics: diagnostics, now: now)

        #expect(juice.restPercent == 50)
        #expect(juice.compactRestText == "2.5K")
        #expect(juice.hasData)
    }

    @Test
    func `uses cached REST limits when live diagnostics are empty`() {
        let now = Date(timeIntervalSinceReferenceDate: 200)
        let summary = RepoPeekCacheSummary(
            databasePath: "/tmp/cache.sqlite",
            exists: true,
            apiResponseCount: 1,
            rateLimitCount: 0,
            latestResponses: [
                RepoPeekCachedResponseSummary(
                    method: "GET",
                    url: "https://api.gitlab.com/user/repos",
                    hasETag: true,
                    statusCode: 200,
                    fetchedAt: now,
                    rateLimitResource: "core",
                    rateLimitLimit: 5000,
                    rateLimitRemaining: 4000,
                    rateLimitReset: now.addingTimeInterval(600)
                )
            ],
            rateLimits: []
        )

        let juice = RateLimitJuice(diagnostics: .empty, cacheSummary: summary, now: now)

        #expect(juice.restPercent == 80)
        #expect(juice.compactRestText == "4K")
        #expect(juice.hasData)
    }

    @Test
    func `display state uses same cached value for menu bar and menu summary`() {
        let now = Date(timeIntervalSinceReferenceDate: 250)
        let summary = RepoPeekCacheSummary(
            databasePath: "/tmp/cache.sqlite",
            exists: true,
            apiResponseCount: 1,
            rateLimitCount: 0,
            latestResponses: [
                RepoPeekCachedResponseSummary(
                    method: "GET",
                    url: "https://api.gitlab.com/user/repos",
                    hasETag: true,
                    statusCode: 200,
                    fetchedAt: now,
                    rateLimitResource: "core",
                    rateLimitLimit: 5000,
                    rateLimitRemaining: 4948,
                    rateLimitReset: now.addingTimeInterval(600)
                )
            ],
            rateLimits: []
        )
        let state = RateLimitDisplayState(diagnostics: .empty, cacheSummary: summary)

        #expect(state.juice.compactRestText == "4.9K")
        #expect(state.compactSummary(now: now).contains("4.9K/5K left"))
        #expect(state.sections(now: now).flatMap(\.rows).contains { $0.contains("4948/5000") })
    }

    @Test
    func `active limit renders as empty lane`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 300)
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://api.gitlab.com")),
            rateLimitReset: now.addingTimeInterval(60),
            lastRateLimitError: nil,
            etagEntries: 0,
            backoffEntries: 0,
            restRateLimit: nil
        )

        let juice = RateLimitJuice(diagnostics: diagnostics, now: now)

        #expect(juice.isRestLimited)
        #expect(juice.displayRestPercent == 0)
        #expect(juice.compactRestText == "0")
        #expect(juice.hasData)
    }

    @Test
    func `uses cached rate limit alias when core resource is absent`() {
        let now = Date(timeIntervalSinceReferenceDate: 350)
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
                    rateLimitResource: "rate",
                    rateLimitLimit: 600,
                    rateLimitRemaining: 300,
                    rateLimitReset: now.addingTimeInterval(600)
                )
            ],
            rateLimits: []
        )

        let juice = RateLimitJuice(diagnostics: .empty, cacheSummary: summary, now: now)

        #expect(juice.restPercent == 50)
        #expect(juice.compactRestText == "300")
    }

    @Test
    func `display state ignores expired active limits`() {
        let now = Date(timeIntervalSinceReferenceDate: 400)
        let summary = RepoPeekCacheSummary(
            databasePath: "/tmp/cache.sqlite",
            exists: true,
            apiResponseCount: 0,
            rateLimitCount: 1,
            latestResponses: [],
            rateLimits: [
                RepoPeekRateLimitSummary(
                    resource: "core",
                    remaining: 0,
                    resetAt: now.addingTimeInterval(-1),
                    lastError: "old limit"
                )
            ]
        )

        #expect(RateLimitDisplayState(diagnostics: .empty, cacheSummary: summary).isLimited(now: now) == false)
    }
}
