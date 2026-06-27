import AppKit
import RepoPeekCore
import SwiftUI

struct MenuLoggedOutView: View {
    let title: String
    let subtitle: String

    init(
        title: String = "Sign in to see your repositories",
        subtitle: String = "Connect your GitLab account to load pins and activity."
    ) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclam")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(self.title)
                .font(.headline)
            Text(self.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}

struct MenuCenteredActionRowView: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        Text(self.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(self.foregroundStyle)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .center)
            .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
            .contentShape(Rectangle())
            .onTapGesture {
                guard self.isEnabled else { return }

                self.action()
            }
    }

    private var foregroundStyle: Color {
        if self.isEnabled {
            return MenuHighlightStyle.primary(self.isHighlighted)
        }
        return Color(nsColor: .secondaryLabelColor)
    }
}

struct MenuEmptyStateView: View {
    let title: String
    let subtitle: String

    init(
        title: String = "No repositories yet",
        subtitle: String = "Pin a repository to see activity here."
    ) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(self.title)
                .font(.headline)
            Text(self.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

struct RateLimitBanner: View {
    let reset: Date
    let text: String
    let accessibilityLabel: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    init(
        reset: Date,
        text: String? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.reset = reset
        let resetText = RelativeFormatter.string(from: reset, relativeTo: Date())
        self.text = text ?? "Rate limit resets \(resetText)"
        self.accessibilityLabel = accessibilityLabel ?? "Rate limit reset: \(resetText)"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.fill")
                .foregroundStyle(.orange)
            Text(self.text)
                .lineLimit(2)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.accessibilityLabel)
    }
}

struct ErrorBanner: View {
    let message: String
    let accessibilityLabel: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(self.message)
                .lineLimit(2)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.accessibilityLabel)
    }
}

struct UpdatingBanner: View {
    let text: String
    let accessibilityLabel: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(self.text)
                .lineLimit(1)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.accessibilityLabel)
    }
}

struct RateLimitStatusRowView: View {
    let title: String
    let summary: String
    let isLimited: Bool
    @Environment(\.menuItemHighlighted) private var isHighlighted

    init(
        title: String = "GitLab API Status",
        summary: String,
        isLimited: Bool
    ) {
        self.title = title
        self.summary = summary
        self.isLimited = isLimited
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speedometer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(self.isLimited ? .orange : MenuHighlightStyle.secondary(self.isHighlighted))

            VStack(alignment: .leading, spacing: 1) {
                Text(self.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                Text(self.summary)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, MenuStyle.filterHorizontalPadding)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(self.title), \(self.summary)")
    }
}

struct MenuInfoTextRowView: View {
    let text: String
    let lineLimit: Int
    private let iconColumnWidth: CGFloat = 18
    private let iconSpacing: CGFloat = 8

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: self.iconSpacing) {
            SubmenuIconPlaceholderView(font: .caption)

            Text(self.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(self.lineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MenuStyle.cardHorizontalPadding)
        .padding(.vertical, MenuStyle.cardVerticalPadding)
    }
}

struct RateLimitSectionHeaderView: View {
    let title: String

    var body: some View {
        HStack {
            Text(self.title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, RateLimitMenuMetrics.horizontalPadding)
        .padding(.top, 7)
        .padding(.bottom, 1)
    }
}

struct RateLimitResourceRowView: View {
    let row: RateLimitDisplayRow
    let language: AppLanguage
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if self.row.resource != nil || self.row.quotaText != nil {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(self.row.resource ?? self.localized(self.row.text))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 8)

                        if let quota = self.row.quotaText {
                            Text(self.localizedRateFragment(quota))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if let percent = self.row.percentRemaining {
                        RateLimitProgressBar(
                            percent: percent,
                            tint: Self.tint(for: percent),
                            accessibilityLabel: self.row.resource ?? self.t("GitLab rate limit"),
                            language: self.language
                        )
                    }

                    if let reset = self.row.resetText, let sampled = self.sampledDetail {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(self.localizedRateFragment(reset))
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text(self.localizedRateFragment(sampled))
                                .lineLimit(1)
                        }
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    } else if let reset = self.row.resetText {
                        Text(self.localizedRateFragment(reset))
                            .font(.caption2)
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(1)
                    }

                    if let detail = self.nonSampledDetail {
                        Text(self.localized(detail))
                            .font(.caption2)
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(self.localized(self.row.text))
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, RateLimitMenuMetrics.horizontalPadding)
        .padding(.vertical, 4)
    }

    private var sampledDetail: String? {
        guard let detail = self.row.detailText, detail.hasPrefix("sampled ") else { return nil }

        return detail
    }

    private var nonSampledDetail: String? {
        guard let detail = self.row.detailText, detail.isEmpty == false else { return nil }

        return self.sampledDetail == nil ? detail : nil
    }

    private func t(_ key: String) -> String {
        L10n.t(key, language: self.language)
    }

    private func format(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, language: self.language, arguments)
    }

    private func localized(_ text: String) -> String {
        self.localizedRateFragment(self.t(text))
    }

    private func localizedRateFragment(_ text: String) -> String {
        if text == "blocked" { return self.t("blocked") }
        if text.hasSuffix(" left") {
            return self.format("%@ left", String(text.dropLast(" left".count)))
        }
        if text.hasPrefix("resets ") {
            return self.format("resets %@", String(text.dropFirst("resets ".count)))
        }
        if text.hasPrefix("reset ") {
            return self.format("reset %@", String(text.dropFirst("reset ".count)))
        }
        if text.hasPrefix("retry ") {
            return self.format("retry %@", String(text.dropFirst("retry ".count)))
        }
        if text.hasPrefix("sampled ") {
            return self.format("sampled %@", String(text.dropFirst("sampled ".count)))
        }
        if text.hasSuffix(" blocked") {
            return self.format("%@ blocked", String(text.dropLast(" blocked".count)))
        }
        return self.t(text)
    }

    private static func tint(for percent: Double) -> Color {
        if percent <= 10 {
            return Color(nsColor: .systemRed)
        }
        if percent <= 30 {
            return Color(nsColor: .systemOrange)
        }
        return Color(nsColor: .systemGreen)
    }
}

private enum RateLimitMenuMetrics {
    static let horizontalPadding: CGFloat = 28
}

struct RateLimitProgressBar: View {
    let percent: Double
    let tint: Color
    let accessibilityLabel: String
    let language: AppLanguage
    @Environment(\.menuItemHighlighted) private var isHighlighted

    private var clamped: Double {
        min(100, max(0, self.percent))
    }

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = proxy.size.width * self.clamped / 100
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MenuHighlightStyle.progressTrack(self.isHighlighted))
                Capsule()
                    .fill(MenuHighlightStyle.progressTint(self.isHighlighted, fallback: self.tint))
                    .frame(width: fillWidth)
            }
            .clipped()
        }
        .frame(height: 6)
        .accessibilityLabel(self.accessibilityLabel)
        .accessibilityValue(L10n.format("%@ percent remaining", language: self.language, "\(Int(self.clamped))"))
    }
}

struct MenuLoadingRowView: View {
    let text: String

    init(text: String = "Loading repositories…") {
        self.text = text
    }

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.regular)
            Text(self.text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}
