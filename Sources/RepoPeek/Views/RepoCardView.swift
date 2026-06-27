import AppKit
import RepoPeekCore
import SwiftUI

struct RepoCardView: View {
    let repo: RepositoryDisplayModel
    let isPinned: Bool
    let unpin: () -> Void
    let hide: () -> Void
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?
    @Bindable var session: Session
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: self.verticalSpacing) {
            self.header
            self.stats
            self.localStatusRow
            self.activity
            self.errorOrLimit
            self.heatmap
        }
        .padding(self.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { self.open(url: self.repoURL()) }
        .accessibilityAction(named: Text(self.t("Move down"))) { self.moveDown?() }
        .accessibilityAction(named: Text(self.t("Move up"))) { self.moveUp?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.accessibilitySummary())
    }

    private func repoURL() -> URL {
        self.webURLBuilder.repoURL(fullName: self.repo.title) ?? self.session.settings.gitlabHost
    }

    private func open(url: URL) {
        SecurityScopedBookmark.withAccess(
            to: url,
            rootBookmarkData: self.session.settings.localProjects.rootBookmarkData
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    private func accessibilitySummary() -> String {
        var parts: [String] = [self.repo.title]
        parts.append(self.format("Pipeline %@", "\(self.repo.ciStatus)"))
        parts.append(self.format("Issues %d", self.repo.issues))
        parts.append(self.format("Merge requests %d", self.repo.pulls))
        if let local = self.repo.localStatus {
            parts.append(self.format("Branch %@", local.branch))
            parts.append(self.format("Sync %@", local.syncDetail))
        }
        if let release = self.repo.releaseLine {
            parts.append(self.format("Release %@", release))
        }
        if let activity = self.repo.activityLine {
            parts.append(self.format("Activity %@", activity))
        }
        return parts.joined(separator: ", ")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.repo.title)
                    .font(.headline)
                    .lineLimit(1)
                if let releaseLine = repo.releaseLine {
                    Text(releaseLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                if self.isPinned { Button(self.t("Unpin"), action: self.unpin) }
                Button(self.t("Hide"), action: self.hide)
                Button(self.t("Open in GitLab")) { self.open(url: self.repoURL()) }
                if let local = self.repo.localStatus {
                    Button(self.t("Open in Finder")) { self.open(url: local.path) }
                    Button(self.t("Open in Terminal")) { self.openTerminal(at: local.path) }
                }
                if let moveUp { Button(self.t("Move up"), action: moveUp) }
                if let moveDown { Button(self.t("Move down"), action: moveDown) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            LinkBadge(
                text: self.t("Pipelines"),
                valueText: nil,
                color: self.ciColor,
                action: { self.open(url: self.pipelinesURL()) }
            )
            LinkBadge(
                text: self.t("Issues"),
                valueText: "\(self.repo.issues)",
                color: Color(nsColor: .windowBackgroundColor),
                action: { self.open(url: self.issuesURL()) }
            )
            LinkBadge(
                text: self.t("MRs"),
                valueText: "\(self.repo.pulls)",
                color: Color(nsColor: .windowBackgroundColor),
                action: { self.open(url: self.pullsURL()) }
            )
            StatBadge(text: self.t("Visitors"), valueText: self.repo.trafficVisitors.map(String.init) ?? "--")
            StatBadge(text: self.t("Cloners"), valueText: self.repo.trafficCloners.map(String.init) ?? "--")
        }
    }

    @ViewBuilder
    private var localStatusRow: some View {
        if let local = self.repo.localStatus {
            HStack(spacing: 6) {
                Image(systemName: local.syncState.symbolName)
                    .foregroundStyle(self.localSyncColor(for: local.syncState))
                Text(local.branch)
                    .font(.caption)
                    .lineLimit(1)
                Text(local.syncDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
        }
    }

    @ViewBuilder
    private var activity: some View {
        if let activity = repo.activityLine, let url = repo.activityURL {
            Button { self.open(url: url) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(activity, systemImage: "text.bubble")
                        .font(.caption)
                        .lineLimit(2)
                        .layoutPriority(1)
                    Spacer(minLength: 6)
                    if let age = self.repo.latestActivityAge {
                        Text(age)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.link)
        }
    }

    @ViewBuilder
    private var errorOrLimit: some View {
        if let error = repo.error {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(self.warningColor)
                Text(error).font(.caption).lineLimit(2)
            }
        } else if let limit = repo.rateLimitedUntil {
            HStack(spacing: 6) {
                Image(systemName: "clock").foregroundStyle(self.warningColor)
                Text(self.format("Rate limited until %@", RelativeFormatter.string(from: limit, relativeTo: Date())))
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var heatmap: some View {
        if self.session.settings.heatmap.display == .inline, !self.repo.heatmap.isEmpty {
            let filtered = HeatmapFilter.filter(self.repo.heatmap, range: self.session.heatmapRange)
            VStack(spacing: 4) {
                HeatmapView(
                    cells: filtered,
                    accentTone: self.session.settings.appearance.accentTone,
                    range: self.session.heatmapRange
                )
                HeatmapAxisLabelsView(range: self.session.heatmapRange, foregroundStyle: Color.secondary)
            }
        }
    }

    private var cardPadding: CGFloat {
        switch self.session.settings.appearance.cardDensity {
        case .comfortable: 14
        case .compact: 10
        }
    }

    private var verticalSpacing: CGFloat {
        switch self.session.settings.appearance.cardDensity {
        case .comfortable: 10
        case .compact: 8
        }
    }

    private var ciColor: Color {
        let isLight = self.colorScheme == .light
        switch self.repo.ciStatus {
        case .passing:
            return isLight
                ? Color(nsColor: NSColor(srgbRed: 0.12, green: 0.55, blue: 0.24, alpha: 1))
                : Color(nsColor: NSColor(srgbRed: 0.23, green: 0.8, blue: 0.4, alpha: 1))
        case .failing:
            return .red
        case .pending:
            return isLight
                ? Color(nsColor: NSColor(srgbRed: 0.0, green: 0.45, blue: 0.9, alpha: 1))
                : Color(nsColor: NSColor(srgbRed: 0.2, green: 0.65, blue: 1.0, alpha: 1))
        case .unknown:
            return .gray
        }
    }

    private var warningColor: Color {
        self.colorScheme == .light ? Color(nsColor: .systemOrange) : Color(nsColor: .systemYellow)
    }

    private func localSyncColor(for state: LocalSyncState) -> Color {
        let isLight = self.colorScheme == .light
        switch state {
        case .synced:
            return isLight
                ? Color(nsColor: NSColor(srgbRed: 0.12, green: 0.55, blue: 0.24, alpha: 1))
                : Color(nsColor: NSColor(srgbRed: 0.23, green: 0.8, blue: 0.4, alpha: 1))
        case .behind:
            return isLight ? Color(nsColor: .systemOrange) : Color(nsColor: .systemYellow)
        case .ahead:
            return isLight ? Color(nsColor: .systemBlue) : Color(nsColor: .systemTeal)
        case .diverged:
            return isLight ? Color(nsColor: .systemOrange) : Color(nsColor: .systemYellow)
        case .dirty:
            return isLight ? Color(nsColor: .systemRed) : Color(nsColor: .systemRed)
        case .unknown:
            return .secondary
        }
    }

    private func issuesURL() -> URL {
        self.webURLBuilder.issuesURL(fullName: self.repo.title) ?? self.repoURL().appendingPathComponent("issues")
    }

    private func pullsURL() -> URL {
        self.webURLBuilder.pullsURL(fullName: self.repo.title) ?? self.repoURL().appendingPathComponent("pulls")
    }

    private func pipelinesURL() -> URL {
        self.webURLBuilder.pipelinesURL(fullName: self.repo.title) ?? self.repoURL().appendingPathComponent("pipelines")
    }

    private var webURLBuilder: RepoWebURLBuilder {
        if let host = self.repo.localStatus?.remoteWebURLHost {
            return RepoWebURLBuilder(host: host)
        }
        if let hostKey = self.repo.source.identity?.host {
            if let host = self.session.settings.gitlabAccounts.first(where: { $0.hostKey == hostKey })?.host {
                return RepoWebURLBuilder(host: host)
            }
        }
        return RepoWebURLBuilder(host: self.session.settings.gitlabHost)
    }

    private func openTerminal(at url: URL) {
        let preferred = self.session.settings.localProjects.preferredTerminal
        let terminal = TerminalApp.resolve(preferred)
        terminal.open(
            at: url,
            rootBookmarkData: self.session.settings.localProjects.rootBookmarkData,
            ghosttyOpenMode: self.session.settings.localProjects.ghosttyOpenMode
        )
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }

    private func format(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, settings: self.session.settings, arguments)
    }
}

private struct CIBadge: View {
    let status: CIStatus
    let runCount: Int?
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(self.color)
                .frame(width: 10, height: 10)
            Text("CI")
                .font(.caption).bold()
            if let runCount {
                Text("\(runCount)")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(self.color.opacity(0.18))
        .foregroundStyle(self.color)
        .clipShape(Capsule(style: .continuous))
        .help(self.helpText)
    }

    private var color: Color {
        .clear
    }

    private var helpText: String {
        ""
    }
}

struct StatBadge: View {
    let text: String
    let valueText: String

    init(text: String, value: Int) {
        self.text = text
        self.valueText = "\(value)"
    }

    init(text: String, valueText: String) {
        self.text = text
        self.valueText = valueText
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(self.text)
                .font(.caption2)
            Text(self.valueText)
                .font(.caption2).bold()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct LinkBadge: View {
    let text: String
    let valueText: String?
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 4) {
                Text(self.text)
                    .font(.caption2)
                if let valueText {
                    Text(valueText)
                        .font(.caption2).bold()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(self.color.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(self.color.opacity(0.35), lineWidth: 1)
            )
            .foregroundStyle(self.color == Color(nsColor: .windowBackgroundColor) ? .primary : self.color)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
