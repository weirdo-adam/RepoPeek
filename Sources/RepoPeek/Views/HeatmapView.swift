import RepoPeekCore
import SwiftUI

struct HeatmapView: View {
    let cells: [HeatmapCell]
    let accentTone: AccentTone
    let range: HeatmapRange?
    private let height: CGFloat?
    @Environment(\.menuItemHighlighted) private var isHighlighted
    private var summary: String {
        let cells = self.renderedCells
        let total = cells.map(\.count).reduce(0, +)
        let maxVal = cells.map(\.count).max() ?? 0
        return "Commit activity heatmap, total \(total) commits, max \(maxVal) in a day."
    }

    init(
        cells: [HeatmapCell],
        accentTone: AccentTone = .gitlabGreen,
        range: HeatmapRange? = nil,
        height: CGFloat? = nil
    ) {
        self.cells = cells
        self.accentTone = accentTone
        self.range = range
        self.height = height
    }

    var body: some View {
        let renderedCells = self.renderedCells
        let columns = self.columnCount

        GeometryReader { proxy in
            HeatmapRasterView(
                cells: renderedCells,
                columns: columns,
                accentTone: self.accentTone,
                isHighlighted: self.isHighlighted
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: self.height)
        .accessibilityLabel(self.summary)
        .accessibilityElement(children: .ignore)
    }

    private var renderedCells: [HeatmapCell] {
        guard let range else { return self.cells }

        return HeatmapLayout.normalizedCells(
            cells: self.cells,
            range: range,
            calendar: HeatmapFilter.gitLabCalendar()
        )
    }

    private var columnCount: Int {
        guard let range else { return HeatmapLayout.columnCount(cellCount: self.cells.count) }

        return HeatmapLayout.columnCount(range: range, calendar: HeatmapFilter.gitLabCalendar())
    }
}

enum HeatmapLayout {
    static let rows = 7
    static let minColumns = 53
    static let spacing: CGFloat = 0.5
    static let cornerRadiusFactor: CGFloat = 0.12
    static let minCellSide: CGFloat = 2
    static let maxCellSide: CGFloat = 10

    static func columnCount(cellCount: Int) -> Int {
        let dataColumns = max(1, Int(ceil(Double(cellCount) / Double(self.rows))))
        return max(dataColumns, self.minColumns)
    }

    static func columnCount(range: HeatmapRange, calendar: Calendar = HeatmapFilter.gitLabCalendar()) -> Int {
        let days = self.dayCount(range: range, calendar: calendar)
        let dataColumns = max(1, Int(ceil(Double(days) / Double(self.rows))))
        return max(dataColumns, self.minColumns)
    }

    static func cellSide(for height: CGFloat) -> CGFloat {
        let totalSpacingY = CGFloat(rows - 1) * self.spacing
        let availableHeight = max(height - totalSpacingY, 0)
        let side = availableHeight / CGFloat(self.rows)
        return max(self.minCellSide, min(self.maxCellSide, floor(side)))
    }

    static func cellSide(forHeight height: CGFloat, width: CGFloat, columns: Int) -> CGFloat {
        let heightSide = self.cellSide(for: height)
        let totalSpacingX = CGFloat(max(columns - 1, 0)) * self.spacing
        let availableWidth = max(width - totalSpacingX, 0)
        let widthSide = availableWidth / CGFloat(max(columns, 1))
        let side = floor(min(heightSide, widthSide))
        return max(self.minCellSide, min(self.maxCellSide, side))
    }

    static func reshape(cells: [HeatmapCell], columns: Int) -> [[HeatmapCell]] {
        var padded = cells
        if padded.count < columns * self.rows {
            let missing = columns * self.rows - padded.count
            padded.append(contentsOf: Array(repeating: HeatmapCell(date: Date(), count: 0), count: missing))
        }
        return stride(from: 0, to: padded.count, by: self.rows).map { index in
            Array(padded[index ..< min(index + self.rows, padded.count)])
        }
    }

    static func normalizedCells(
        cells: [HeatmapCell],
        range: HeatmapRange,
        calendar: Calendar = HeatmapFilter.gitLabCalendar()
    ) -> [HeatmapCell] {
        let start = calendar.startOfDay(for: range.start)
        let end = calendar.startOfDay(for: range.end)
        guard start <= end else { return [] }

        var countsByDay: [Date: Int] = [:]
        for cell in cells {
            let day = calendar.startOfDay(for: cell.date)
            guard day >= start, day <= end else { continue }

            countsByDay[day, default: 0] += cell.count
        }

        var normalized: [HeatmapCell] = []
        normalized.reserveCapacity(self.dayCount(range: range, calendar: calendar))

        var day = start
        while day <= end {
            normalized.append(HeatmapCell(date: day, count: countsByDay[day] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }

            day = next
        }
        return normalized
    }

    static func contentWidth(columns: Int, cellSide: CGFloat) -> CGFloat {
        let totalSpacingX = CGFloat(max(columns - 1, 0)) * self.spacing
        return CGFloat(max(columns, 0)) * cellSide + totalSpacingX
    }

    static func centeredInset(available: CGFloat, content: CGFloat) -> CGFloat {
        guard available > content else { return 0 }

        return floor((available - content) / 2)
    }

    private static func dayCount(range: HeatmapRange, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: range.start)
        let end = calendar.startOfDay(for: range.end)
        guard start <= end else { return 0 }

        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return days + 1
    }
}
