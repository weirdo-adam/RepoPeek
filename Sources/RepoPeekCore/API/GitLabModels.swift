import Foundation

enum GitLabDateParser {
    static func date(from rawValue: String?) -> Date? {
        guard let rawValue else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: rawValue) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }
}

struct GitLabCurrentUser: Decodable {
    let id: Int
    let username: String
    let webUrl: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case webUrl = "web_url"
    }
}

struct GitLabProject: Decodable {
    let id: Int
    let name: String
    let path: String?
    let pathWithNamespace: String
    let archived: Bool?
    let starCount: Int?
    let forksCount: Int?
    let openIssuesCount: Int?
    let lastActivityAt: Date?
    let webUrl: URL?
    let namespace: Namespace?
    let forkedFromProject: ForkedProject?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case pathWithNamespace = "path_with_namespace"
        case archived
        case starCount = "star_count"
        case forksCount = "forks_count"
        case openIssuesCount = "open_issues_count"
        case lastActivityAt = "last_activity_at"
        case webUrl = "web_url"
        case namespace
        case forkedFromProject = "forked_from_project"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decodeIfPresent(String.self, forKey: .path)
        self.pathWithNamespace = try container.decode(String.self, forKey: .pathWithNamespace)
        self.archived = try container.decodeIfPresent(Bool.self, forKey: .archived)
        self.starCount = try container.decodeIfPresent(Int.self, forKey: .starCount)
        self.forksCount = try container.decodeIfPresent(Int.self, forKey: .forksCount)
        self.openIssuesCount = try container.decodeIfPresent(Int.self, forKey: .openIssuesCount)
        let lastActivity = try container.decodeIfPresent(String.self, forKey: .lastActivityAt)
        self.lastActivityAt = GitLabDateParser.date(from: lastActivity)
        self.webUrl = try container.decodeIfPresent(URL.self, forKey: .webUrl)
        self.namespace = try container.decodeIfPresent(Namespace.self, forKey: .namespace)
        self.forkedFromProject = try container.decodeIfPresent(ForkedProject.self, forKey: .forkedFromProject)
    }

    struct Namespace: Decodable {
        let fullPath: String?

        enum CodingKeys: String, CodingKey {
            case fullPath = "full_path"
        }
    }

    struct ForkedProject: Decodable {}
}

extension GitLabProject {
    func repository(webHost: URL) -> Repository {
        let projectPath = self.pathWithNamespace.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fallbackName = projectPath.split(separator: "/").last.map(String.init) ?? self.name
        let repoName: String = if let path, path.isEmpty == false {
            path
        } else {
            fallbackName
        }
        let namespacePath = self.namespace?.fullPath ?? projectPath
            .split(separator: "/")
            .dropLast()
            .map(String.init)
            .joined(separator: "/")
        let host = GitLabAccountSettings.hostKey(for: webHost)
        let identity = RepositoryIdentity(
            host: host,
            projectPath: projectPath
        )

        let projectURL = self.webUrl ?? webHost.appending(path: projectPath)
        let latestActivity = self.lastActivityAt.map {
            ActivityEvent(
                title: "Project activity",
                actor: namespacePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                date: $0,
                url: projectURL,
                eventType: "PushEvent",
                metadata: ActivityMetadata(
                    actor: namespacePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                    action: "Updated",
                    target: projectPath,
                    url: projectURL
                )
            )
        }

        return Repository(
            id: identity.lookupKey,
            identity: identity,
            name: repoName,
            owner: namespacePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            isFork: self.forkedFromProject != nil,
            isArchived: self.archived ?? false,
            viewerCanRead: true,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: self.openIssuesCount ?? 0,
            openPulls: 0,
            stars: self.starCount ?? 0,
            forks: self.forksCount ?? 0,
            pushedAt: self.lastActivityAt,
            latestRelease: nil,
            latestActivity: latestActivity,
            activityEvents: latestActivity.map { [$0] } ?? [],
            traffic: nil,
            heatmap: []
        )
    }
}

struct GitLabUser: Decodable {
    let username: String?
    let name: String?
    let avatarUrl: URL?
    let webUrl: URL?

    enum CodingKeys: String, CodingKey {
        case username
        case name
        case avatarUrl = "avatar_url"
        case webUrl = "web_url"
    }
}

struct GitLabLabel: Decodable {
    let name: String
    let color: String?
}

struct GitLabIssue: Decodable {
    let iid: Int
    let title: String
    let webUrl: URL
    let updatedAt: Date
    let createdAt: Date?
    let author: GitLabUser?
    let assignees: [GitLabUser]?
    let userNotesCount: Int?
    let labels: [RepoIssueLabel]

    enum CodingKeys: String, CodingKey {
        case iid
        case title
        case webUrl = "web_url"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case author
        case assignees
        case userNotesCount = "user_notes_count"
        case labels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.iid = try container.decode(Int.self, forKey: .iid)
        self.title = try container.decode(String.self, forKey: .title)
        self.webUrl = try container.decode(URL.self, forKey: .webUrl)
        self.updatedAt = try GitLabDateParser.date(from: container.decodeIfPresent(String.self, forKey: .updatedAt)) ?? .distantPast
        self.createdAt = try GitLabDateParser.date(from: container.decodeIfPresent(String.self, forKey: .createdAt))
        self.author = try container.decodeIfPresent(GitLabUser.self, forKey: .author)
        self.assignees = try container.decodeIfPresent([GitLabUser].self, forKey: .assignees)
        self.userNotesCount = try container.decodeIfPresent(Int.self, forKey: .userNotesCount)
        if let labelObjects = try? container.decode([GitLabLabel].self, forKey: .labels) {
            self.labels = labelObjects.map { RepoIssueLabel(name: $0.name, colorHex: ($0.color ?? "").trimmingPrefix("#")) }
        } else {
            let labelNames = (try? container.decode([String].self, forKey: .labels)) ?? []
            self.labels = labelNames.map { RepoIssueLabel(name: $0, colorHex: "") }
        }
    }
}

struct GitLabMergeRequest: Decodable {
    let iid: Int
    let title: String
    let webUrl: URL
    let updatedAt: Date
    let createdAt: Date?
    let state: String?
    let mergedAt: Date?
    let author: GitLabUser?
    let draft: Bool?
    let workInProgress: Bool?
    let userNotesCount: Int?
    let labels: [RepoIssueLabel]
    let sourceBranch: String?
    let targetBranch: String?
    let reviewers: [GitLabUser]?

    enum CodingKeys: String, CodingKey {
        case iid
        case title
        case webUrl = "web_url"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case state
        case mergedAt = "merged_at"
        case author
        case draft
        case workInProgress = "work_in_progress"
        case userNotesCount = "user_notes_count"
        case labels
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
        case reviewers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.iid = try container.decode(Int.self, forKey: .iid)
        self.title = try container.decode(String.self, forKey: .title)
        self.webUrl = try container.decode(URL.self, forKey: .webUrl)
        self.updatedAt = try GitLabDateParser.date(from: container.decodeIfPresent(String.self, forKey: .updatedAt)) ?? .distantPast
        self.createdAt = try GitLabDateParser.date(from: container.decodeIfPresent(String.self, forKey: .createdAt))
        self.state = try container.decodeIfPresent(String.self, forKey: .state)
        self.mergedAt = try GitLabDateParser.date(from: container.decodeIfPresent(String.self, forKey: .mergedAt))
        self.author = try container.decodeIfPresent(GitLabUser.self, forKey: .author)
        self.draft = try container.decodeIfPresent(Bool.self, forKey: .draft)
        self.workInProgress = try container.decodeIfPresent(Bool.self, forKey: .workInProgress)
        self.userNotesCount = try container.decodeIfPresent(Int.self, forKey: .userNotesCount)
        if let labelObjects = try? container.decode([GitLabLabel].self, forKey: .labels) {
            self.labels = labelObjects.map { RepoIssueLabel(name: $0.name, colorHex: ($0.color ?? "").trimmingPrefix("#")) }
        } else {
            let labelNames = (try? container.decode([String].self, forKey: .labels)) ?? []
            self.labels = labelNames.map { RepoIssueLabel(name: $0, colorHex: "") }
        }
        self.sourceBranch = try container.decodeIfPresent(String.self, forKey: .sourceBranch)
        self.targetBranch = try container.decodeIfPresent(String.self, forKey: .targetBranch)
        self.reviewers = try container.decodeIfPresent([GitLabUser].self, forKey: .reviewers)
    }
}

struct GitLabRelease: Decodable {
    let name: String?
    let tagName: String
    let releasedAt: Date?
    let createdAt: Date?
    let links: Links?
    let assets: Assets?

    enum CodingKeys: String, CodingKey {
        case name
        case tagName = "tag_name"
        case releasedAt = "released_at"
        case createdAt = "created_at"
        case links = "_links"
        case assets
    }

    struct Links: Decodable {
        let selfUrl: URL?

        enum CodingKeys: String, CodingKey {
            case selfUrl = "self"
        }
    }

    struct Assets: Decodable {
        let count: Int?
        let links: [AssetLink]?
        let sources: [AssetLink]?
    }

    struct AssetLink: Decodable {
        let name: String?
        let url: URL?
        let directAssetUrl: URL?

        enum CodingKeys: String, CodingKey {
            case name
            case url
            case directAssetUrl = "direct_asset_url"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.tagName = try container.decode(String.self, forKey: .tagName)
        self.releasedAt = try GitLabDateParser.date(from: container.decodeIfPresent(String.self, forKey: .releasedAt))
        self.createdAt = try GitLabDateParser.date(from: container.decodeIfPresent(String.self, forKey: .createdAt))
        self.links = try container.decodeIfPresent(Links.self, forKey: .links)
        self.assets = try container.decodeIfPresent(Assets.self, forKey: .assets)
    }
}

struct GitLabPipeline: Decodable {
    let id: Int
    let iid: Int?
    let status: String?
    let ref: String?
    let source: String?
    let updatedAt: Date?
    let createdAt: Date?
    let webUrl: URL?
    let user: GitLabUser?

    enum CodingKeys: String, CodingKey {
        case id
        case iid
        case status
        case ref
        case source
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case webUrl = "web_url"
        case user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.iid = try container.decodeIfPresent(Int.self, forKey: .iid)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.ref = try container.decodeIfPresent(String.self, forKey: .ref)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
        self.updatedAt = try GitLabDateParser.date(from: container.decodeIfPresent(String.self, forKey: .updatedAt))
        self.createdAt = try GitLabDateParser.date(from: container.decodeIfPresent(String.self, forKey: .createdAt))
        self.webUrl = try container.decodeIfPresent(URL.self, forKey: .webUrl)
        self.user = try container.decodeIfPresent(GitLabUser.self, forKey: .user)
    }
}

struct GitLabTag: Decodable {
    let name: String
    let target: String?
    let commit: GitLabCommitRef?
}

struct GitLabBranch: Decodable {
    let name: String
    let protected: Bool?
    let commit: GitLabCommitRef?
}

struct GitLabCommitRef: Decodable {
    let id: String?
    let shortId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case shortId = "short_id"
    }
}

struct GitLabContributor: Decodable {
    let name: String?
    let email: String?
    let commits: Int?
}

struct GitLabTreeItem: Decodable {
    let id: String?
    let name: String
    let path: String
    let type: String
    let webUrl: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case type
        case webUrl = "web_url"
    }

    func contentItem(apiURL: URL) -> RepoContentItem {
        RepoContentItem(
            name: self.name,
            path: self.path,
            type: self.contentType,
            size: nil,
            url: apiURL,
            htmlURL: self.webUrl,
            downloadURL: nil
        )
    }

    private var contentType: RepoContentType {
        switch self.type {
        case "tree": .dir
        case "blob": .file
        case "commit": .submodule
        default: .unknown
        }
    }
}

struct GitLabCommit: Decodable {
    let id: String
    let title: String?
    let message: String?
    let webUrl: URL?
    let authoredDate: Date?
    let authorName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case message
        case webUrl = "web_url"
        case authoredDate = "authored_date"
        case authorName = "author_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
        self.webUrl = try container.decodeIfPresent(URL.self, forKey: .webUrl)
        self.authoredDate = try GitLabDateParser.date(from: container.decodeIfPresent(String.self, forKey: .authoredDate))
        self.authorName = try container.decodeIfPresent(String.self, forKey: .authorName)
    }
}

struct GitLabEvent: Decodable {
    let actionName: String?
    let targetType: String?
    let targetTitle: String?
    let targetIid: Int?
    let targetUrl: URL?
    let createdAt: Date?
    let authorUsername: String?
    let author: GitLabUser?
    let projectId: Int?
    let pushData: PushData?
    let note: Note?

    enum CodingKeys: String, CodingKey {
        case actionName = "action_name"
        case targetType = "target_type"
        case targetTitle = "target_title"
        case targetIid = "target_iid"
        case targetUrl = "target_url"
        case createdAt = "created_at"
        case authorUsername = "author_username"
        case author
        case projectId = "project_id"
        case pushData = "push_data"
        case note
    }

    struct PushData: Decodable {
        let commitTitle: String?
        let commitTo: String?
        let ref: String?
        let refType: String?

        enum CodingKeys: String, CodingKey {
            case commitTitle = "commit_title"
            case commitTo = "commit_to"
            case ref
            case refType = "ref_type"
        }
    }

    struct Note: Decodable {
        let body: String?
        let noteableType: String?
        let noteableIid: Int?

        enum CodingKeys: String, CodingKey {
            case body
            case noteableType = "noteable_type"
            case noteableIid = "noteable_iid"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.actionName = try container.decodeIfPresent(String.self, forKey: .actionName)
        self.targetType = try container.decodeIfPresent(String.self, forKey: .targetType)
        self.targetTitle = try container.decodeIfPresent(String.self, forKey: .targetTitle)
        self.targetIid = try container.decodeIfPresent(Int.self, forKey: .targetIid)
        self.targetUrl = try container.decodeIfPresent(URL.self, forKey: .targetUrl)
        self.createdAt = try GitLabDateParser.date(from: container.decodeIfPresent(String.self, forKey: .createdAt))
        self.authorUsername = try container.decodeIfPresent(String.self, forKey: .authorUsername)
        self.author = try container.decodeIfPresent(GitLabUser.self, forKey: .author)
        self.projectId = try container.decodeIfPresent(Int.self, forKey: .projectId)
        self.pushData = try container.decodeIfPresent(PushData.self, forKey: .pushData)
        self.note = try container.decodeIfPresent(Note.self, forKey: .note)
    }
}

private extension String {
    func trimmingPrefix(_ prefix: Character) -> String {
        guard self.first == prefix else { return self }

        return String(self.dropFirst())
    }
}
