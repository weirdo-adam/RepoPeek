import Foundation

public struct RateLimitDisplayRow: Codable, Equatable, Sendable {
    public let text: String
    public let resource: String?
    public let quotaText: String?
    public let resetText: String?
    public let detailText: String?
    public let percentRemaining: Double?

    public init(
        text: String,
        resource: String? = nil,
        quotaText: String? = nil,
        resetText: String? = nil,
        detailText: String? = nil,
        percentRemaining: Double? = nil
    ) {
        self.text = text
        self.resource = resource
        self.quotaText = quotaText
        self.resetText = resetText
        self.detailText = detailText
        self.percentRemaining = percentRemaining
    }
}

public struct RateLimitDisplaySection: Codable, Equatable, Sendable {
    public let title: String?
    public let rows: [String]
    public let resourceRows: [RateLimitDisplayRow]

    public init(title: String?, rows: [String]) {
        self.title = title
        self.rows = rows
        self.resourceRows = rows.map { RateLimitDisplayRow(text: $0) }
    }

    public init(title: String?, resourceRows: [RateLimitDisplayRow]) {
        self.title = title
        self.rows = resourceRows.map(\.text)
        self.resourceRows = resourceRows
    }
}

public enum RateLimitStatusFormatter {
    public static func compactSummary(
        diagnostics: DiagnosticsSummary,
        cacheSummary: RepoPeekCacheSummary?,
        authMethod _: AuthMethod? = nil,
        now: Date = Date()
    ) -> String {
        if let blocker = currentBlockerRows(
            diagnostics: diagnostics,
            cacheSummary: cacheSummary,
            now: now
        ).first {
            return "Blocked: \(self.compactBlockerSummary(blocker))"
        }

        var rows: [String] = []
        if let rest = diagnostics.restRateLimit {
            rows.append(Self.snapshotText(label: "REST", snapshot: rest, now: now, compact: true))
        }
        if rows.isEmpty, let cacheSummary {
            rows = Self.observedRateLimitRows(from: cacheSummary)
                .prefix(2)
                .map { Self.cachedResponseText($0, now: now, compact: true) }
        }
        if rows.isEmpty, let active = cacheSummary?.rateLimits.first {
            rows.append(Self.activeLimitText(active, now: now, compact: true))
        }

        return rows.isEmpty ? "No current blocker" : "OK: " + rows.joined(separator: " · ")
    }

    public static func sections(
        diagnostics: DiagnosticsSummary,
        cacheSummary: RepoPeekCacheSummary?,
        authMethod: AuthMethod? = nil,
        now: Date = Date()
    ) -> [RateLimitDisplaySection] {
        var sections: [RateLimitDisplaySection] = []
        var currentRows: [String] = []
        let blockerRows = Self.currentBlockerRows(
            diagnostics: diagnostics,
            cacheSummary: cacheSummary,
            now: now
        )
        if blockerRows.isEmpty == false {
            sections.append(RateLimitDisplaySection(
                title: "Current Blocker",
                resourceRows: blockerRows
            ))
        } else {
            sections.append(RateLimitDisplaySection(
                title: "Current Status",
                rows: ["No active GitLab blocker."]
            ))
        }
        if let authMethod {
            sections.append(RateLimitDisplaySection(
                title: "Budget Model",
                resourceRows: Self.budgetModelRows(authMethod: authMethod, isCoreBlocked: blockerRows.contains { $0.resource == "core" })
            ))
        }

        if let rest = diagnostics.restRateLimit {
            currentRows.append(Self.snapshotText(label: "REST", snapshot: rest, now: now))
        }
        if let error = diagnostics.lastRateLimitError, Self.blockerRows(blockerRows, alreadyRepresent: error) == false {
            currentRows.append(error)
        }
        if currentRows.isEmpty == false {
            sections.append(RateLimitDisplaySection(title: "Details", rows: currentRows))
        }
        let endpointCooldowns = diagnostics.endpointCooldowns.filter { $0.retryAfter > now }
        if endpointCooldowns.isEmpty == false {
            sections.append(RateLimitDisplaySection(
                title: "Endpoint Cooldowns",
                rows: endpointCooldowns.map { Self.endpointCooldownText($0, now: now) }
            ))
        }

        if let cacheSummary {
            let observed = Self.observedRateLimitRows(from: cacheSummary)
            if observed.isEmpty == false {
                sections.append(contentsOf: Self.observedSections(from: observed, now: now))
            }
            if cacheSummary.rateLimits.isEmpty == false {
                let activeResources = Set(blockerRows.compactMap(\.resource))
                let storedRows = cacheSummary.rateLimits
                    .filter { activeResources.contains($0.resource) == false || $0.resetAt <= now }
                    .map { Self.activeLimitText($0, now: now) }
                if storedRows.isEmpty == false {
                    sections.append(RateLimitDisplaySection(
                        title: "Stored Blockers",
                        rows: storedRows
                    ))
                }
            }
        }

        return sections.isEmpty
            ? [RateLimitDisplaySection(title: nil, rows: ["No rate-limit data yet"])]
            : sections
    }

    private static func observedSections(
        from rows: [RepoPeekCachedResponseSummary],
        now: Date
    ) -> [RateLimitDisplaySection] {
        let grouped = Dictionary(grouping: rows) { Self.resourceGroup(for: $0.rateLimitResource) }
        return ResourceGroup.allCases.compactMap { group in
            guard let rows = grouped[group], rows.isEmpty == false else { return nil }

            return RateLimitDisplaySection(
                title: group.title,
                resourceRows: rows.map { Self.cachedResponseRow($0, now: now) }
            )
        }
    }

    public static func observedRateLimitRows(from summary: RepoPeekCacheSummary) -> [RepoPeekCachedResponseSummary] {
        var seen: Set<String> = []
        var rows: [RepoPeekCachedResponseSummary] = []
        for response in summary.latestResponses {
            guard let resource = response.rateLimitResource, resource.isEmpty == false else { continue }
            guard seen.insert(resource).inserted else { continue }

            rows.append(response)
        }
        return rows
    }

    private static func endpointCooldownText(_ cooldown: EndpointCooldownSummary, now: Date) -> String {
        let label = if let repository = cooldown.repository {
            "\(repository) \(cooldown.endpoint)"
        } else {
            cooldown.endpoint
        }

        return "\(label) · retry \(RelativeFormatter.string(from: cooldown.retryAfter, relativeTo: now))"
    }

    private static func currentBlockerRows(
        diagnostics: DiagnosticsSummary,
        cacheSummary: RepoPeekCacheSummary?,
        now: Date
    ) -> [RateLimitDisplayRow] {
        var rows: [RateLimitDisplayRow] = []
        if let reset = diagnostics.rateLimitReset, reset > now {
            let errorDetail = diagnostics.lastRateLimitError.map {
                Self.cleanedBlockerText($0, fallback: "")
            }
            let detailText = [
                errorDetail,
                Self.sharedUserBudgetText
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            rows.append(RateLimitDisplayRow(
                text: "REST core blocked",
                resource: "core",
                quotaText: "0 left",
                resetText: "resets \(RelativeFormatter.string(from: reset, relativeTo: now))",
                detailText: detailText,
                percentRemaining: 0
            ))
        }

        let activeCooldowns = diagnostics.endpointCooldowns
            .filter { $0.retryAfter > now }
            .sorted { lhs, rhs in
                if lhs.retryAfter != rhs.retryAfter { return lhs.retryAfter < rhs.retryAfter }
                return lhs.url < rhs.url
            }
        for cooldown in activeCooldowns {
            rows.append(RateLimitDisplayRow(
                text: "Endpoint cooldown",
                resource: cooldown.endpoint,
                quotaText: nil,
                resetText: "retry \(RelativeFormatter.string(from: cooldown.retryAfter, relativeTo: now))",
                detailText: Self.endpointCooldownText(cooldown, now: now),
                percentRemaining: nil
            ))
        }

        let activeResources = Set(rows.compactMap(\.resource))
        for limit in cacheSummary?.rateLimits.filter({ $0.resetAt > now }) ?? [] where activeResources.contains(limit.resource) == false {
            rows.append(RateLimitDisplayRow(
                text: "\(limit.resource) blocked",
                resource: limit.resource,
                quotaText: limit.remaining.map { "\($0) left" } ?? "blocked",
                resetText: "resets \(RelativeFormatter.string(from: limit.resetAt, relativeTo: now))",
                detailText: limit.lastError,
                percentRemaining: limit.remaining == 0 ? 0 : nil
            ))
        }

        return rows
    }

    private static func budgetModelRows(authMethod: AuthMethod, isCoreBlocked: Bool) -> [RateLimitDisplayRow] {
        var rows: [RateLimitDisplayRow] = [
            RateLimitDisplayRow(text: Self.authSourceText(for: authMethod)),
            RateLimitDisplayRow(text: Self.budgetActorText(for: authMethod)),
            RateLimitDisplayRow(text: "GitLab API budget is tied to the PAT owner.")
        ]
        if isCoreBlocked {
            rows.append(RateLimitDisplayRow(text: Self.otherClientsText))
        }
        return rows
    }

    private static let sharedUserBudgetText = "Shared GitLab user budget; \(RepoPeekProductConstants.displayName) and other PATs " +
        "for this account can spend this API quota. Extra tokens do not create extra user quota."

    private static let otherClientsText = "Other GitLab clients may still work if they use a different token, " +
        "but the same user quota can still be shared."

    private static func authSourceText(for authMethod: AuthMethod) -> String {
        switch authMethod {
        case .pat:
            "\(RepoPeekProductConstants.displayName) auth: PAT"
        }
    }

    private static func budgetActorText(for authMethod: AuthMethod) -> String {
        switch authMethod {
        case .pat:
            "Budget actor: token owner"
        }
    }

    private static func compactBlockerSummary(_ row: RateLimitDisplayRow) -> String {
        var summary = row.text
        let detail = row.detailText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, detail.isEmpty == false, detail != summary {
            summary += " · \(detail)"
        }
        let reset = row.resetText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reset, reset.isEmpty == false, summary.contains(reset) == false {
            summary += " · \(reset)"
        }
        return summary
    }

    private static func blockerRows(_ rows: [RateLimitDisplayRow], alreadyRepresent error: String) -> Bool {
        let cleaned = Self.cleanedBlockerText(error, fallback: "")
        return rows.contains { row in
            if row.text == error || row.text == cleaned { return true }
            guard let detail = row.detailText else { return false }

            return detail.contains(error) || (cleaned.isEmpty == false && detail.contains(cleaned))
        }
    }

    private static func cleanedBlockerText(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return fallback }

        if trimmed.hasPrefix("GitLab rate limit hit; ") {
            return "REST core " + trimmed.dropFirst("GitLab rate limit hit; ".count)
        }
        return trimmed
    }

    private static func snapshotText(label: String, snapshot: RateLimitSnapshot, now: Date, compact: Bool = false) -> String {
        let text = Self.rateLimitText(RateLimitTextInput(
            resource: snapshot.resource,
            remaining: snapshot.remaining,
            limit: snapshot.limit,
            reset: snapshot.reset,
            fetchedAt: snapshot.fetchedAt
        ), now: now, compact: compact)
        return "\(label): \(text)"
    }

    private static func cachedResponseText(_ row: RepoPeekCachedResponseSummary, now: Date, compact: Bool = false) -> String {
        self.rateLimitText(RateLimitTextInput(
            resource: row.rateLimitResource,
            remaining: row.rateLimitRemaining,
            limit: row.rateLimitLimit,
            reset: row.rateLimitReset,
            fetchedAt: row.fetchedAt
        ), now: now, compact: compact)
    }

    private static func cachedResponseRow(_ row: RepoPeekCachedResponseSummary, now: Date) -> RateLimitDisplayRow {
        self.rateLimitRow(RateLimitTextInput(
            resource: row.rateLimitResource,
            remaining: row.rateLimitRemaining,
            limit: row.rateLimitLimit,
            reset: row.rateLimitReset,
            fetchedAt: row.fetchedAt
        ), now: now, compact: false)
    }

    private static func activeLimitText(_ row: RepoPeekRateLimitSummary, now: Date, compact: Bool = false) -> String {
        let reset = RelativeFormatter.string(from: row.resetAt, relativeTo: now)
        let remaining = row.remaining.map { compact ? "\(Self.shortCount($0)) left" : "\($0) left" } ?? "blocked"
        let base = "\(row.resource): \(remaining), resets \(reset)"
        if compact || row.lastError?.isEmpty != false {
            return base
        }
        return "\(base) · \(row.lastError ?? "")"
    }

    private static func resourceGroup(for resource: String?) -> ResourceGroup {
        switch resource {
        case "core", "rate":
            .restCore
        case "search", "code_search":
            .restSearch
        case "integration_manifest":
            .gitLabApp
        case "scim", "audit_log", "source_import":
            .enterpriseAndImport
        default:
            .other
        }
    }

    private static func rateLimitText(_ input: RateLimitTextInput, now: Date, compact: Bool) -> String {
        self.rateLimitRow(input, now: now, compact: compact).text
    }

    private static func rateLimitRow(
        _ input: RateLimitTextInput,
        now: Date,
        compact: Bool
    ) -> RateLimitDisplayRow {
        var parts = [input.resource ?? "unknown"]
        var quotaText: String?
        var resetText: String?
        var percentRemaining: Double?
        if let remaining = input.remaining, let limit = input.limit {
            let remainingText = compact ? Self.shortCount(remaining) : "\(remaining)"
            let limitText = compact ? Self.shortCount(limit) : "\(limit)"
            quotaText = compact ? "\(remainingText)/\(limitText) left" : "\(remainingText)/\(limitText)"
            parts.append(quotaText ?? "")
            if limit > 0 {
                percentRemaining = min(100, max(0, (Double(remaining) / Double(limit)) * 100))
            }
        } else if let remaining = input.remaining {
            let remainingText = compact ? Self.shortCount(remaining) : "\(remaining)"
            quotaText = compact ? "\(remainingText) left" : remainingText
            parts.append(quotaText ?? "")
        }
        if let reset = input.reset {
            let verb = reset > now ? "resets" : "reset"
            resetText = "\(verb) \(RelativeFormatter.string(from: reset, relativeTo: now))"
            parts.append(resetText ?? "")
        }
        let detailText = input.fetchedAt.map {
            "sampled \(RelativeFormatter.string(from: $0, relativeTo: now))"
        }
        return RateLimitDisplayRow(
            text: parts.joined(separator: compact ? " " : " · "),
            resource: input.resource,
            quotaText: quotaText,
            resetText: resetText,
            detailText: detailText,
            percentRemaining: percentRemaining
        )
    }

    private static func shortCount(_ value: Int) -> String {
        if value >= 1000 {
            let rounded = Double(value) / 1000
            return rounded.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(rounded))K"
                : String(format: "%.1fK", rounded)
        }
        return "\(value)"
    }

    private struct RateLimitTextInput {
        let resource: String?
        let remaining: Int?
        let limit: Int?
        let reset: Date?
        let fetchedAt: Date?
    }

    private enum ResourceGroup: Int, CaseIterable {
        case restCore
        case restSearch
        case gitLabApp
        case enterpriseAndImport
        case other

        var title: String {
            switch self {
            case .restCore:
                "REST Core"
            case .restSearch:
                "REST Search"
            case .gitLabApp:
                "GitLab Application"
            case .enterpriseAndImport:
                "Enterprise / Import"
            case .other:
                "Other Resources"
            }
        }
    }
}
