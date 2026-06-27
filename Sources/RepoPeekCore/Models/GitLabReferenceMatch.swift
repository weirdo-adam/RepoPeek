import Foundation

public enum GitLabReferenceKind: String, Sendable, Hashable {
    case issue
    case pullRequest
    case commit
    case workflowRun

    public var label: String {
        switch self {
        case .issue: "Issue"
        case .pullRequest: "Merge Request"
        case .commit: "Commit"
        case .workflowRun: "Workflow Run"
        }
    }
}

public enum GitLabReferenceState: String, Sendable, Hashable {
    case open
    case closed
    case merged

    public var label: String {
        switch self {
        case .open: "Open"
        case .closed: "Closed"
        case .merged: "Merged"
        }
    }
}

public enum GitLabReferenceQuery: Sendable, Hashable {
    case issueNumber(Int)
    case repositoryNameIssueNumber(repositoryName: String, number: Int)
    case repositoryIssueNumber(repositoryFullName: String, number: Int)
    case commitHash(String)
    case repositoryCommitHash(repositoryFullName: String, hash: String)
    case repositoryWorkflowRun(repositoryFullName: String, runID: Int64)

    public var displayText: String {
        switch self {
        case let .issueNumber(number): "#\(number)"
        case let .repositoryNameIssueNumber(repositoryName, number): "\(repositoryName)#\(number)"
        case let .repositoryIssueNumber(repositoryFullName, number): "\(repositoryFullName)#\(number)"
        case let .commitHash(hash): String(hash.prefix(10))
        case let .repositoryCommitHash(repositoryFullName, hash): "\(repositoryFullName)@\(hash.prefix(10))"
        case let .repositoryWorkflowRun(repositoryFullName, runID): "\(repositoryFullName) run \(runID)"
        }
    }

    public var repositoryFullName: String? {
        switch self {
        case .issueNumber, .repositoryNameIssueNumber, .commitHash:
            nil
        case let .repositoryIssueNumber(repositoryFullName, _),
             let .repositoryCommitHash(repositoryFullName, _),
             let .repositoryWorkflowRun(repositoryFullName, _):
            repositoryFullName
        }
    }

    public var repositoryName: String? {
        switch self {
        case .issueNumber, .commitHash:
            nil
        case let .repositoryNameIssueNumber(repositoryName, _):
            repositoryName
        case let .repositoryIssueNumber(repositoryFullName, _),
             let .repositoryCommitHash(repositoryFullName, _),
             let .repositoryWorkflowRun(repositoryFullName, _):
            repositoryFullName.split(separator: "/").last.map(String.init)
        }
    }

    public var repositoryOwnerAndName: (owner: String, name: String)? {
        guard let repositoryFullName else { return nil }

        let parts = repositoryFullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].isEmpty == false, parts[1].isEmpty == false else {
            return nil
        }

        return (parts[0], parts[1])
    }
}

public struct GitLabReferenceMatch: Sendable, Hashable {
    public let query: GitLabReferenceQuery
    public let title: String
    public let url: URL
    public let repositoryFullName: String
    public let kind: GitLabReferenceKind
    public let state: GitLabReferenceState?
    public let createdAt: Date?
    public let updatedAt: Date
    public let bodyPreview: String?
    public let authorLogin: String?
    public let aiSummary: String?

    public init(
        query: GitLabReferenceQuery,
        title: String,
        url: URL,
        repositoryFullName: String,
        kind: GitLabReferenceKind,
        state: GitLabReferenceState?,
        createdAt: Date?,
        updatedAt: Date,
        bodyPreview: String? = nil,
        authorLogin: String? = nil,
        aiSummary: String? = nil
    ) {
        self.query = query
        self.title = title
        self.url = url
        self.repositoryFullName = repositoryFullName
        self.kind = kind
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bodyPreview = bodyPreview
        self.authorLogin = authorLogin
        self.aiSummary = aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public static func newestCreated(in matches: [GitLabReferenceMatch]) -> GitLabReferenceMatch? {
        matches.max { lhs, rhs in
            let lhsDate = lhs.createdAt ?? lhs.updatedAt
            let rhsDate = rhs.createdAt ?? rhs.updatedAt
            if lhsDate == rhsDate {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhsDate < rhsDate
        }
    }

    public func withAISummary(_ summary: String?) -> GitLabReferenceMatch {
        GitLabReferenceMatch(
            query: self.query,
            title: self.title,
            url: self.url,
            repositoryFullName: self.repositoryFullName,
            kind: self.kind,
            state: self.state,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt,
            bodyPreview: self.bodyPreview,
            authorLogin: self.authorLogin,
            aiSummary: summary
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
