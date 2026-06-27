import Foundation
import RepoPeekCore

enum IssueNavigatorKindFilter: String, CaseIterable, Identifiable {
    case all
    case issues
    case pullRequests

    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .all: "Issues + MRs"
        case .issues: "Issues"
        case .pullRequests: "Merge Requests"
        }
    }

    func title(language: AppLanguage) -> String {
        L10n.t(self.title, language: language)
    }

    var includeIssues: Bool {
        self != .pullRequests
    }

    var includePullRequests: Bool {
        self != .issues
    }

    func matches(_ kind: GitLabReferenceKind) -> Bool {
        switch self {
        case .all:
            true
        case .issues:
            kind == .issue
        case .pullRequests:
            kind == .pullRequest
        }
    }
}

struct IssueNavigatorScope: Identifiable, Hashable {
    let fullName: String?
    let title: String

    var id: String {
        self.fullName ?? "__all"
    }

    static let all = IssueNavigatorScope(fullName: nil, title: "All Repositories")

    func title(language: AppLanguage) -> String {
        self.fullName == nil ? L10n.t(self.title, language: language) : self.title
    }
}

extension GitLabReferenceMatch {
    var issueNavigatorTitle: String {
        switch self.query {
        case let .issueNumber(number),
             let .repositoryNameIssueNumber(_, number),
             let .repositoryIssueNumber(_, number):
            "#\(number) \(self.title)"
        case let .commitHash(hash),
             let .repositoryCommitHash(_, hash):
            "\(String(hash.prefix(10))) \(self.title)"
        case let .repositoryWorkflowRun(_, runID):
            "Run \(runID) \(self.title)"
        }
    }
}

extension [GitLabReferenceMatch] {
    func issueNavigatorOrderPreservingDeduped() -> [GitLabReferenceMatch] {
        var seen: Set<URL> = []
        return self.filter { seen.insert($0.url).inserted }
    }
}
