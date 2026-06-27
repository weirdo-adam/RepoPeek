import Foundation
import RepoPeekCore

struct GlobalActivityCache: Codable, Equatable {
    let hostKey: String
    let username: String
    let scope: GlobalActivityScope
    var coverageStart: Date
    var coverageEnd: Date
    var fetchedAt: Date
    var events: [ActivityEvent]
}

struct GlobalActivityFetchPlan: Equatable {
    let cachedEvents: [ActivityEvent]
    let after: Date
    let before: Date
}

enum GlobalActivityCachePlanner {
    static func fetchPlan(
        cache: GlobalActivityCache?,
        range: HeatmapRange,
        calendar: Calendar
    ) -> GlobalActivityFetchPlan {
        let rangeStart = calendar.startOfDay(for: range.start)
        let rangeEnd = calendar.startOfDay(for: range.end)
        guard let cache else {
            return GlobalActivityFetchPlan(cachedEvents: [], after: rangeStart, before: rangeEnd)
        }

        let cachedEvents = self.events(in: cache.events, range: range, calendar: calendar)
        guard calendar.startOfDay(for: cache.coverageStart) <= rangeStart else {
            return GlobalActivityFetchPlan(cachedEvents: cachedEvents, after: rangeStart, before: rangeEnd)
        }

        let latestCachedDay = cachedEvents
            .map { calendar.startOfDay(for: $0.date) }
            .max()
        let cachedEnd = calendar.startOfDay(for: cache.coverageEnd)
        let coveredThrough = min(max(cachedEnd, rangeStart), rangeEnd)
        let resumeAfter = latestCachedDay.map { max($0, coveredThrough) } ?? coveredThrough
        return GlobalActivityFetchPlan(
            cachedEvents: cachedEvents,
            after: resumeAfter,
            before: rangeEnd
        )
    }

    // swiftlint:disable:next function_parameter_count
    static func mergedCache(
        cache: GlobalActivityCache?,
        fetchedEvents: [ActivityEvent],
        hostKey: String,
        username: String,
        scope: GlobalActivityScope,
        range: HeatmapRange,
        fetchedAt: Date,
        calendar: Calendar,
        limit: Int = AppLimits.GlobalActivity.cacheEventLimit
    ) -> GlobalActivityCache {
        let rangeStart = calendar.startOfDay(for: range.start)
        let rangeEnd = calendar.startOfDay(for: range.end)
        let existingEvents = cache?.events ?? []
        let retentionStart = calendar.date(
            byAdding: .day,
            value: -AppLimits.GlobalActivity.cacheRetentionDays,
            to: rangeEnd
        ) ?? rangeStart
        let retainedStart = min(rangeStart, calendar.startOfDay(for: retentionStart))
        let retainedEvents = (existingEvents + fetchedEvents).filter { event in
            let day = calendar.startOfDay(for: event.date)
            return day >= retainedStart && day <= rangeEnd
        }
        let events = Array(self.dedupedSorted(retainedEvents).prefix(max(limit, 0)))
        let coverageStart = min(cache.map { calendar.startOfDay(for: $0.coverageStart) } ?? rangeStart, rangeStart)
        let coverageEnd = max(cache.map { calendar.startOfDay(for: $0.coverageEnd) } ?? rangeEnd, rangeEnd)

        return GlobalActivityCache(
            hostKey: hostKey,
            username: username,
            scope: scope,
            coverageStart: coverageStart,
            coverageEnd: coverageEnd,
            fetchedAt: fetchedAt,
            events: events
        )
    }

    static func events(
        in events: [ActivityEvent],
        range: HeatmapRange,
        calendar: Calendar
    ) -> [ActivityEvent] {
        let start = calendar.startOfDay(for: range.start)
        let end = calendar.startOfDay(for: range.end)
        return self.dedupedSorted(events).filter { event in
            let day = calendar.startOfDay(for: event.date)
            return day >= start && day <= end
        }
    }

    private static func dedupedSorted(_ events: [ActivityEvent]) -> [ActivityEvent] {
        let sorted = events.sorted { $0.date > $1.date }
        var seen: Set<String> = []
        var results: [ActivityEvent] = []
        results.reserveCapacity(sorted.count)
        for event in sorted {
            let key = "\(event.url.absoluteString)|\(event.date.timeIntervalSinceReferenceDate)|\(event.actor)"
            guard seen.insert(key).inserted else { continue }

            results.append(event)
        }
        return results
    }
}

struct GlobalActivityCacheStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseURL: URL?

    init(fileManager: FileManager = .default, baseURL: URL? = nil) {
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.baseURL = baseURL ?? Self.defaultBaseURL(fileManager: fileManager)
    }

    func load(hostKey: String, username: String, scope: GlobalActivityScope) -> GlobalActivityCache? {
        guard let url = self.cacheFileURL(hostKey: hostKey, username: username, scope: scope),
              let data = try? Data(contentsOf: url)
        else { return nil }

        do {
            return try self.decoder.decode(GlobalActivityCache.self, from: data)
        } catch {
            try? self.fileManager.removeItem(at: url)
            return nil
        }
    }

    func save(_ cache: GlobalActivityCache) {
        guard let url = self.cacheFileURL(
            hostKey: cache.hostKey,
            username: cache.username,
            scope: cache.scope
        ) else { return }

        do {
            try self.fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try self.encoder.encode(cache)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    func clear() {
        guard let baseURL else { return }

        try? self.fileManager.removeItem(at: baseURL)
    }

    private func cacheFileURL(hostKey: String, username: String, scope: GlobalActivityScope) -> URL? {
        guard let baseURL else { return nil }

        return baseURL
            .appending(path: Self.safePathComponent(hostKey))
            .appending(path: "\(Self.safePathComponent(username)).\(scope.rawValue).json")
    }

    private static func defaultBaseURL(fileManager: FileManager) -> URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "RepoPeek"
        return support
            .appending(path: bundleID)
            .appending(path: "GlobalActivityCache")
    }

    private static func safePathComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = raw.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
        let value = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return value.isEmpty ? "default" : value
    }
}
