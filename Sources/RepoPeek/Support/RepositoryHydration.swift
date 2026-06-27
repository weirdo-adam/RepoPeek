import Foundation
import RepoPeekCore

enum RepositoryHydration {
    static func merge(_ detailed: [Repository], into repos: [Repository]) -> [Repository] {
        let lookup = Dictionary(
            detailed.map { ($0.lookupKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return repos.map { lookup[$0.lookupKey] ?? $0 }
    }

    static func heatmap(
        from events: [ActivityEvent],
        calendar: Calendar = HeatmapFilter.gitLabCalendar()
    ) -> [HeatmapCell] {
        let counts = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.date)
        }
        .mapValues(\.count)

        return counts.keys.sorted().map { day in
            HeatmapCell(date: day, count: counts[day] ?? 0)
        }
    }
}
