import Foundation
@testable import RepoPeek
import RepoPeekCore
import Testing

struct GlobalActivityCacheStoreTests {
    @Test
    func `fetch plan resumes from cached coverage end day`() throws {
        let calendar = Self.calendar()
        let range = try HeatmapRange(
            start: #require(Self.date(2026, 1, 1, calendar: calendar)),
            end: #require(Self.date(2026, 1, 31, calendar: calendar))
        )
        let eventDate = try #require(Self.date(2026, 1, 20, hour: 15, calendar: calendar))
        let event = try Self.event(date: eventDate, path: "events/1")
        let cache = GlobalActivityCache(
            hostKey: "gitlab.example.com",
            username: "alice",
            scope: .myActivity,
            coverageStart: range.start,
            coverageEnd: range.end,
            fetchedAt: range.end,
            events: [event]
        )

        let plan = GlobalActivityCachePlanner.fetchPlan(cache: cache, range: range, calendar: calendar)

        #expect(plan.cachedEvents == [event])
        #expect(plan.after == range.end)
        #expect(plan.before == range.end)
    }

    @Test
    func `merged cache dedupes fetched events and keeps events from range end day`() throws {
        let calendar = Self.calendar()
        let range = try HeatmapRange(
            start: #require(Self.date(2026, 1, 1, calendar: calendar)),
            end: #require(Self.date(2026, 1, 31, calendar: calendar))
        )
        let eventDate = try #require(Self.date(2026, 1, 31, hour: 15, calendar: calendar))
        let event = try Self.event(date: eventDate, path: "events/2")
        let cache = GlobalActivityCache(
            hostKey: "gitlab.example.com",
            username: "alice",
            scope: .myActivity,
            coverageStart: range.start,
            coverageEnd: range.end,
            fetchedAt: range.end,
            events: [event]
        )

        let merged = GlobalActivityCachePlanner.mergedCache(
            cache: cache,
            fetchedEvents: [event],
            hostKey: cache.hostKey,
            username: cache.username,
            scope: cache.scope,
            range: range,
            fetchedAt: range.end,
            calendar: calendar
        )

        #expect(merged.events == [event])
        #expect(GlobalActivityCachePlanner.events(in: merged.events, range: range, calendar: calendar) == [event])
    }

    @Test
    func `cache store round trips and clears activity cache`() throws {
        let calendar = Self.calendar()
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: "GlobalActivityCacheStoreTests.\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let store = GlobalActivityCacheStore(baseURL: baseURL)
        let range = try HeatmapRange(
            start: #require(Self.date(2026, 1, 1, calendar: calendar)),
            end: #require(Self.date(2026, 1, 31, calendar: calendar))
        )
        let cache = try GlobalActivityCache(
            hostKey: "gitlab.example.com/group",
            username: "alice",
            scope: .allActivity,
            coverageStart: range.start,
            coverageEnd: range.end,
            fetchedAt: range.end,
            events: [Self.event(date: range.end, path: "events/3")]
        )

        store.save(cache)
        let loaded = try #require(store.load(hostKey: cache.hostKey, username: cache.username, scope: cache.scope))

        #expect(loaded == cache)
        store.clear()
        #expect(store.load(hostKey: cache.hostKey, username: cache.username, scope: cache.scope) == nil)
    }

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        calendar: Calendar
    ) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    }

    private static func event(date: Date, path: String) throws -> ActivityEvent {
        try ActivityEvent(
            title: "Push",
            actor: "alice",
            date: date,
            url: #require(URL(string: "https://gitlab.example.com/\(path)")),
            eventType: "pushed"
        )
    }
}
