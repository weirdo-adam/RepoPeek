import Foundation
@testable import RepoPeek
import RepoPeekCore
import Testing

struct HeatmapSizingTests {
    @Test
    func `pads heatmap to full grid`() {
        // 3 weeks worth of data (21 cells) should be padded to 53 * 7
        let cells = (0 ..< 21).map { HeatmapCell(date: Date().addingTimeInterval(Double($0) * 86400), count: $0 % 3) }
        let reshaped = HeatmapLayout.reshape(cells: cells, columns: 53)
        #expect(reshaped.count == 53)
        #expect(reshaped.allSatisfy { $0.count == HeatmapLayout.rows })
    }

    @Test
    func `column count keeps GitLab style minimum across configured heatmap range`() throws {
        let calendar = try HeatmapFilter.gitLabCalendar(timeZone: #require(TimeZone(secondsFromGMT: 0)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 29, hour: 12)))

        #expect(HeatmapLayout.columnCount(
            range: HeatmapFilter.range(span: .oneMonth, now: now, calendar: calendar, alignToWeek: true),
            calendar: calendar
        ) == 53)
        #expect(HeatmapLayout.columnCount(
            range: HeatmapFilter.range(span: .threeMonths, now: now, calendar: calendar, alignToWeek: true),
            calendar: calendar
        ) == 53)
        #expect(HeatmapLayout.columnCount(
            range: HeatmapFilter.range(span: .sixMonths, now: now, calendar: calendar, alignToWeek: true),
            calendar: calendar
        ) == 53)
        #expect(HeatmapLayout.columnCount(
            range: HeatmapFilter.range(span: .twelveMonths, now: now, calendar: calendar, alignToWeek: true),
            calendar: calendar
        ) == 53)
    }

    @Test
    func `normalizes sparse heatmap cells across range`() throws {
        let calendar = try HeatmapFilter.gitLabCalendar(timeZone: #require(TimeZone(secondsFromGMT: 0)))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 10)))
        let hitDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 3, hour: 12)))
        let outside = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 11)))

        let cells = [
            HeatmapCell(date: hitDay, count: 2),
            HeatmapCell(date: hitDay, count: 5),
            HeatmapCell(date: outside, count: 9)
        ]
        let normalized = HeatmapLayout.normalizedCells(
            cells: cells,
            range: HeatmapRange(start: start, end: end),
            calendar: calendar
        )

        #expect(normalized.count == 10)
        #expect(normalized[0].date == start)
        #expect(normalized[2].count == 7)
        #expect(normalized.last?.date == end)
    }
}
