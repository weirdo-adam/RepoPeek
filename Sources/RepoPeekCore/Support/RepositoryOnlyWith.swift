import Foundation

public struct RepositoryOnlyWith: Sendable, Equatable {
    public var requireIssues: Bool
    public var requireMRs: Bool

    public init(requireIssues: Bool = false, requireMRs: Bool = false) {
        self.requireIssues = requireIssues
        self.requireMRs = requireMRs
    }

    public static let none = RepositoryOnlyWith()

    public var isActive: Bool {
        self.requireIssues || self.requireMRs
    }

    public func matches(_ repo: Repository) -> Bool {
        let hasIssues = repo.stats.openIssues > 0
        let hasMRs = repo.stats.openPulls > 0

        var ok = false
        if self.requireIssues { ok = ok || hasIssues }
        if self.requireMRs { ok = ok || hasMRs }
        return ok
    }
}
