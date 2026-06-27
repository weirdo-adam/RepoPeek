public enum ActivityEventType: String, Codable, CaseIterable, Sendable {
    case mergeRequest = "MergeRequest"
    case issue = "Issue"
    case note = "Note"
    case push = "Push"
    case release = "Release"
    case tag = "Tag"
    case branch = "Branch"
    case project = "Project"
    case milestone = "Milestone"
    case snippet = "Snippet"

    public static func parse(_ rawValue: String?) -> ActivityEventType? {
        guard let rawValue else { return nil }

        let normalized = rawValue
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        switch normalized {
        case "mergerequest":
            return .mergeRequest
        case "issue":
            return .issue
        case "note", "comment", "commentedon":
            return .note
        case "push", "pushed", "pushedto":
            return .push
        case "release":
            return .release
        case "tag":
            return .tag
        case "branch":
            return .branch
        case "project":
            return .project
        case "milestone":
            return .milestone
        case "snippet":
            return .snippet
        default:
            return nil
        }
    }
}
