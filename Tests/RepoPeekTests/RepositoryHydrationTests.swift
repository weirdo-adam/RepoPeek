import Foundation
@testable import RepoPeek
import RepoPeekCore
import Testing

struct RepositoryHydrationTests {
    @Test
    func `merge keeps accessible repos and overlays hydrated stats`() {
        let raw = [
            Self.makeRepo("stablyai/orca", issues: 249, pulls: 0),
            Self.makeRepo("example/RepoPeek", issues: 1, pulls: 0)
        ]
        let hydrated = [
            Self.makeRepo("stablyai/orca", issues: 0, pulls: 249)
        ]

        let merged = RepositoryHydration.merge(hydrated, into: raw)

        #expect(merged.map(\.fullName) == ["stablyai/orca", "example/RepoPeek"])
        #expect(merged[0].openIssues == 0)
        #expect(merged[0].openPulls == 249)
        #expect(merged[1].openIssues == 1)
        #expect(merged[1].openPulls == 0)
    }

    @Test
    func `heatmap counts activity by day`() throws {
        let calendar = Self.utcCalendar()
        let firstDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let secondDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)))
        let events = try [
            Self.event(at: #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9)))),
            Self.event(at: #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 18)))),
            Self.event(at: #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 12))))
        ]

        let cells = RepositoryHydration.heatmap(from: events, calendar: calendar)

        #expect(cells.map(\.count) == [2, 1])
        #expect(cells.map { calendar.startOfDay(for: $0.date) } == [firstDay, secondDay])
    }
}

private extension RepositoryHydrationTests {
    static func makeRepo(_ fullName: String, issues: Int, pulls: Int) -> Repository {
        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        return Repository(
            id: fullName,
            name: parts[1],
            owner: parts[0],
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: issues,
            openPulls: pulls,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
    }

    static func event(at date: Date) -> ActivityEvent {
        ActivityEvent(
            title: "Push",
            actor: "alice",
            date: date,
            url: URL(string: "https://gitlab.example.com/group/project")!,
            eventType: "PushEvent"
        )
    }

    static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }
}
