import Foundation

public struct DiagnosticsSummary: Sendable {
    public let apiHost: URL
    public let rateLimitReset: Date?
    public let lastRateLimitError: String?
    public let etagEntries: Int
    public let backoffEntries: Int
    public let endpointCooldowns: [EndpointCooldownSummary]
    public let restRateLimit: RateLimitSnapshot?

    public init(
        apiHost: URL,
        rateLimitReset: Date?,
        lastRateLimitError: String?,
        etagEntries: Int,
        backoffEntries: Int,
        endpointCooldowns: [EndpointCooldownSummary] = [],
        restRateLimit: RateLimitSnapshot?
    ) {
        self.apiHost = apiHost
        self.rateLimitReset = rateLimitReset
        self.lastRateLimitError = lastRateLimitError
        self.etagEntries = etagEntries
        self.backoffEntries = backoffEntries
        self.endpointCooldowns = endpointCooldowns
        self.restRateLimit = restRateLimit
    }

    public static let empty = DiagnosticsSummary(
        apiHost: URL(string: "https://gitlab.com/api/v4")!,
        rateLimitReset: nil,
        lastRateLimitError: nil,
        etagEntries: 0,
        backoffEntries: 0,
        endpointCooldowns: [],
        restRateLimit: nil
    )
}

public struct EndpointCooldownSummary: Codable, Equatable, Hashable, Sendable {
    public let endpoint: String
    public let repository: String?
    public let url: String
    public let retryAfter: Date

    public init(
        endpoint: String,
        repository: String?,
        url: String,
        retryAfter: Date
    ) {
        self.endpoint = endpoint
        self.repository = repository
        self.url = url
        self.retryAfter = retryAfter
    }
}
