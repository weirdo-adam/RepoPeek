import AppKit
import RepoPeekCore
import SwiftUI

struct ContributionHeaderView: View {
    let username: String
    let displayName: String
    @Bindable var session: Session
    let appState: AppState
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: self.titleIconName)
                    .font(.caption.weight(.semibold))
                Text(self.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(self.t("View All"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }
            .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
            self.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: self.username) {
            await self.appState.loadContributionHeatmapIfNeeded(for: self.username)
        }
    }

    private var title: String {
        self.t("Activity")
    }

    private var titleIconName: String {
        "chart.bar.xaxis"
    }

    private var content: some View {
        self.activityContent
    }

    private var activityContent: some View {
        VStack(spacing: 4) {
            HeatmapView(
                cells: self.activityHeatmapCells,
                accentTone: .system,
                range: self.session.heatmapRange,
                height: Self.graphHeight
            )
            HeatmapAxisLabelsView(
                range: self.session.heatmapRange,
                foregroundStyle: MenuHighlightStyle.secondary(self.isHighlighted)
            )
            HStack(spacing: 6) {
                ActivityHeatmapLegendView(isHighlighted: self.isHighlighted)
                Spacer(minLength: 8)
                Text(self.t("Issues, MRs, pushes, and comments."))
                    .lineLimit(1)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }
            .font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(self.format("Activity heatmap for %@", self.displayName))
    }

    private var activityHeatmapCells: [HeatmapCell] {
        Self.activityHeatmapCells(
            events: self.session.globalActivityEvents,
            range: self.session.heatmapRange,
            calendar: HeatmapFilter.gitLabCalendar()
        )
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }

    private func format(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, settings: self.session.settings, arguments)
    }

    static func activityHeatmapCells(
        events: [ActivityEvent],
        range: HeatmapRange,
        calendar: Calendar
    ) -> [HeatmapCell] {
        let start = calendar.startOfDay(for: range.start)
        let end = calendar.startOfDay(for: range.end)
        let counts = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.date)
        }
        .mapValues(\.count)

        var cells: [HeatmapCell] = []
        var day = start
        while day <= end {
            cells.append(HeatmapCell(date: day, count: counts[day] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }

            day = next
        }
        return cells
    }

    private static let graphHeight: CGFloat = 48
    private static let loadingHeight: CGFloat = graphHeight
}

private struct ActivityHeatmapLegendView: View {
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< 5, id: \.self) { bucket in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(self.color(for: bucket))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(for bucket: Int) -> Color {
        if self.isHighlighted {
            return Color(nsColor: .selectedMenuItemTextColor).opacity([0.36, 0.56, 0.72, 0.86, 0.96][bucket])
        }
        if bucket == 0 {
            return Color(nsColor: .quaternaryLabelColor)
        }
        return Color(nsColor: .controlAccentColor).opacity([0.22, 0.36, 0.5, 0.65][bucket - 1])
    }
}
