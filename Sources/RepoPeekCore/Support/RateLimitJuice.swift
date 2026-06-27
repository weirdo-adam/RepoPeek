import Foundation

public struct RateLimitJuice: Equatable, Sendable {
    public let restPercent: Double?
    public let restRemaining: Int?
    public let restLimit: Int?
    public let isRestLimited: Bool

    public init(
        diagnostics: DiagnosticsSummary,
        cacheSummary: RepoPeekCacheSummary? = nil,
        now: Date = Date()
    ) {
        let cachedCore = cacheSummary.flatMap { Self.cachedInfo(resource: "core", in: $0) }
            ?? cacheSummary.flatMap { Self.cachedInfo(resource: "rate", in: $0) }
        let activeLimits = cacheSummary?.rateLimits.filter { $0.resetAt > now } ?? []

        self.restRemaining = diagnostics.restRateLimit?.remaining ?? cachedCore?.remaining
        self.restLimit = diagnostics.restRateLimit?.limit ?? cachedCore?.limit
        self.restPercent = Self.percent(remaining: self.restRemaining, limit: self.restLimit)
        self.isRestLimited = diagnostics.rateLimitReset.map { $0 > now } ?? false
            || activeLimits.contains { $0.resource == "core" || $0.resource == "rate" }
    }

    public var hasData: Bool {
        self.restPercent != nil || self.isRestLimited
    }

    public var displayRestPercent: Double? {
        self.isRestLimited ? 0 : self.restPercent
    }

    public var compactRestText: String? {
        if self.isRestLimited { return "0" }
        if let restRemaining { return Self.shortCount(restRemaining) }
        if let restPercent { return "\(Int(restPercent.rounded()))%" }
        return nil
    }

    private static func cachedInfo(resource: String, in summary: RepoPeekCacheSummary) -> CachedRateLimitInfo? {
        guard let row = summary.latestResponses.first(where: { $0.rateLimitResource == resource }) else { return nil }

        return CachedRateLimitInfo(remaining: row.rateLimitRemaining, limit: row.rateLimitLimit)
    }

    static func percent(remaining: Int?, limit: Int?) -> Double? {
        guard let remaining, let limit, limit > 0 else { return nil }

        let raw = (Double(remaining) / Double(limit)) * 100
        return min(100, max(0, raw))
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

    private struct CachedRateLimitInfo {
        let remaining: Int?
        let limit: Int?
    }
}
