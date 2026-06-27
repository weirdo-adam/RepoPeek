import Foundation

enum RepoRecentMenuKind: Hashable {
    case commits
    case issues
    case pullRequests
    case releases
    case ciRuns
    case tags
    case branches
    case contributors
}

struct RepoRecentMenuContext: Hashable {
    let fullName: String
    let hostKey: String?
    let kind: RepoRecentMenuKind

    init(fullName: String, hostKey: String? = nil, kind: RepoRecentMenuKind) {
        self.fullName = fullName
        self.hostKey = hostKey
        self.kind = kind
    }

    var cacheKey: String {
        Self.cacheKey(fullName: self.fullName, hostKey: self.hostKey)
    }

    static func cacheKey(fullName: String, hostKey: String?) -> String {
        guard let hostKey, hostKey.isEmpty == false else { return fullName }

        return "\(hostKey)/\(fullName)"
    }
}

extension RepositoryDisplayModel {
    var recentMenuCacheKey: String {
        RepoRecentMenuContext.cacheKey(fullName: self.title, hostKey: self.source.identity?.accountID ?? self.source.identity?.host)
    }
}
