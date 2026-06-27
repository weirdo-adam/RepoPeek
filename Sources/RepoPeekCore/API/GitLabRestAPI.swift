import Foundation

struct GitLabRestAPI {
    let apiHost: @Sendable () async -> URL
    let webHost: @Sendable () async -> URL
    let tokenProvider: @Sendable () async throws -> String
    let session: URLSession
    let eTagCache: ETagCache
    let backoffTracker: BackoffTracker
    let responseRecorder: @Sendable (HTTPURLResponse, Date) async -> Void
    let rateLimitErrorRecorder: @Sendable (Date?, String?) async -> Void

    static func membershipProjectsQueryItems(page: Int, perPage: Int = 100) -> [URLQueryItem] {
        [
            URLQueryItem(name: "membership", value: "true"),
            URLQueryItem(name: "simple", value: "true"),
            URLQueryItem(name: "order_by", value: "last_activity_at"),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
    }

    static func projectPath(owner: String, name: String) -> String {
        "\(owner)/\(name)"
            .split(separator: "/")
            .map(String.init)
            .filter { $0.isEmpty == false }
            .joined(separator: "/")
    }

    func fetchCurrentUser() async throws -> GitLabCurrentUser {
        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        let (data, _) = try await self.authorizedGet(
            url: baseURL.appending(path: "/user"),
            token: token
        )
        return try JSONDecoding.decode(GitLabCurrentUser.self, from: data)
    }

    func membershipProjects(limit: Int?) async throws -> [GitLabProject] {
        var page = 1
        var projects: [GitLabProject] = []

        while true {
            let pageProjects = try await self.membershipProjectsPage(page: page)
            projects.append(contentsOf: pageProjects.items)

            if let limit, projects.count >= limit {
                return Array(projects.prefix(limit))
            }
            guard pageProjects.nextPage != nil, pageProjects.items.isEmpty == false else {
                return projects
            }

            page += 1
        }
    }

    func searchProjects(matching query: String, limit: Int) async throws -> [GitLabProject] {
        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        var components = URLComponents(url: self.url(baseURL: baseURL, path: "projects"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "membership", value: "true"),
            URLQueryItem(name: "simple", value: "true"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "order_by", value: "last_activity_at"),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "per_page", value: "\(max(1, min(limit, 100)))")
        ]
        let (data, _) = try await self.authorizedGet(url: components.url!, token: token)
        return try JSONDecoding.decode([GitLabProject].self, from: data)
    }

    func project(owner: String, name: String) async throws -> GitLabProject {
        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        let projectPath = Self.projectPath(owner: owner, name: name)
        let url = self.projectURL(baseURL: baseURL, projectPath: projectPath, suffix: "")
        let (data, _) = try await self.authorizedGet(url: url, token: token)
        return try JSONDecoding.decode(GitLabProject.self, from: data)
    }

    func recentIssues(owner: String, name: String, limit: Int = 20) async throws -> [RepoIssueSummary] {
        let data = try await self.projectListData(
            owner: owner,
            name: name,
            suffix: "issues",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "state", value: "opened"),
                URLQueryItem(name: "order_by", value: "updated_at"),
                URLQueryItem(name: "sort", value: "desc")
            ]
        )
        let issues = try JSONDecoding.decode([GitLabIssue].self, from: data)
        return issues.map(Self.issueSummary(from:))
    }

    func searchIssues(owner: String, name: String, query: String, limit: Int = 20) async throws -> [RepoIssueSummary] {
        let data = try await self.projectListData(
            owner: owner,
            name: name,
            suffix: "issues",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "state", value: "opened"),
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "order_by", value: "updated_at"),
                URLQueryItem(name: "sort", value: "desc")
            ]
        )
        return try JSONDecoding.decode([GitLabIssue].self, from: data).map(Self.issueSummary(from:))
    }

    func issue(owner: String, name: String, iid: Int) async throws -> RepoIssueSummary? {
        let response = try await self.projectItemData(
            owner: owner,
            name: name,
            suffix: "issues/\(iid)",
            allowedStatuses: [200, 404]
        )
        guard response.statusCode != 404 else { return nil }

        return try Self.issueSummary(from: JSONDecoding.decode(GitLabIssue.self, from: response.data))
    }

    func recentMergeRequests(owner: String, name: String, limit: Int = 20) async throws -> [RepoPullRequestSummary] {
        let data = try await self.projectListData(
            owner: owner,
            name: name,
            suffix: "merge_requests",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "state", value: "opened"),
                URLQueryItem(name: "order_by", value: "updated_at"),
                URLQueryItem(name: "sort", value: "desc")
            ]
        )
        let requests = try JSONDecoding.decode([GitLabMergeRequest].self, from: data)
        return requests.map(Self.mergeRequestSummary(from:))
    }

    func openMergeRequestCount(owner: String, name: String) async throws -> Int {
        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        var components = URLComponents(
            url: self.projectURL(
                baseURL: baseURL,
                projectPath: Self.projectPath(owner: owner, name: name),
                suffix: "merge_requests"
            ),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "state", value: "opened"),
            URLQueryItem(name: "per_page", value: "1")
        ]
        let (data, response) = try await self.authorizedGet(url: components.url!, token: token)
        if let total = response.value(forHTTPHeaderField: "X-Total").flatMap(Int.init) {
            return total
        }

        return try JSONDecoding.decode([GitLabMergeRequest].self, from: data).count
    }

    func searchMergeRequests(owner: String, name: String, query: String, limit: Int = 20) async throws -> [RepoPullRequestSummary] {
        let data = try await self.projectListData(
            owner: owner,
            name: name,
            suffix: "merge_requests",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "state", value: "opened"),
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "order_by", value: "updated_at"),
                URLQueryItem(name: "sort", value: "desc")
            ]
        )
        return try JSONDecoding.decode([GitLabMergeRequest].self, from: data).map(Self.mergeRequestSummary(from:))
    }

    func mergeRequest(owner: String, name: String, iid: Int) async throws -> RepoPullRequestSummary? {
        let response = try await self.projectItemData(
            owner: owner,
            name: name,
            suffix: "merge_requests/\(iid)",
            allowedStatuses: [200, 404]
        )
        guard response.statusCode != 404 else { return nil }

        return try Self.mergeRequestSummary(from: JSONDecoding.decode(GitLabMergeRequest.self, from: response.data))
    }

    func recentReleases(owner: String, name: String, limit: Int = 20) async throws -> [RepoReleaseSummary] {
        let projectPath = Self.projectPath(owner: owner, name: name)
        let webHost = await self.webHost()
        let data = try await self.projectListData(
            owner: owner,
            name: name,
            suffix: "releases",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "order_by", value: "released_at"),
                URLQueryItem(name: "sort", value: "desc")
            ]
        )
        let releases = try JSONDecoding.decode([GitLabRelease].self, from: data)
        return releases.map { release in
            let title = (release.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let assets = self.releaseAssets(from: release)
            return RepoReleaseSummary(
                name: title.isEmpty ? release.tagName : title,
                tag: release.tagName,
                url: release.links?.selfUrl ?? self.projectWebURL(
                    webHost: webHost,
                    projectPath: projectPath,
                    components: ["-", "releases", release.tagName]
                ),
                publishedAt: release.releasedAt ?? release.createdAt ?? .distantPast,
                isPrerelease: false,
                authorLogin: nil,
                authorAvatarURL: nil,
                assetCount: release.assets?.count ?? assets.count,
                downloadCount: 0,
                assets: assets
            )
        }
    }

    func recentPipelines(owner: String, name: String, limit: Int = 20) async throws -> [RepoWorkflowRunSummary] {
        let projectPath = Self.projectPath(owner: owner, name: name)
        let webHost = await self.webHost()
        let data = try await self.projectListData(
            owner: owner,
            name: name,
            suffix: "pipelines",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "order_by", value: "updated_at"),
                URLQueryItem(name: "sort", value: "desc")
            ]
        )
        let pipelines = try JSONDecoding.decode([GitLabPipeline].self, from: data)
        return pipelines.map {
            RepoWorkflowRunSummary(
                name: "Pipeline #\($0.iid ?? $0.id)",
                url: $0.webUrl ?? self.projectWebURL(
                    webHost: webHost,
                    projectPath: projectPath,
                    components: ["-", "pipelines", "\($0.id)"]
                ),
                updatedAt: $0.updatedAt ?? $0.createdAt ?? .distantPast,
                status: Self.ciStatus(fromGitLabStatus: $0.status),
                conclusion: $0.status,
                branch: $0.ref,
                event: $0.source,
                actorLogin: $0.user?.username,
                actorAvatarURL: $0.user?.avatarUrl,
                runNumber: $0.iid ?? $0.id
            )
        }
    }

    func recentCommits(owner: String, name: String, limit: Int = 20) async throws -> RepoCommitList {
        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        var components = URLComponents(
            url: self.projectURL(baseURL: baseURL, projectPath: Self.projectPath(owner: owner, name: name), suffix: "repository/commits"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "\(max(1, min(limit, 100)))")]
        let (data, response) = try await self.authorizedGet(url: components.url!, token: token)
        let commits = try JSONDecoding.decode([GitLabCommit].self, from: data)
        let items = commits.compactMap(Self.commitSummary(from:))
        let totalCount = response.value(forHTTPHeaderField: "X-Total").flatMap(Int.init)
        return RepoCommitList(items: items, totalCount: totalCount)
    }

    func commit(owner: String, name: String, sha: String) async throws -> RepoCommitSummary? {
        let response = try await self.projectItemData(
            owner: owner,
            name: name,
            suffix: "repository/commits/\(sha)",
            allowedStatuses: [200, 404]
        )
        guard response.statusCode != 404 else { return nil }

        return try Self.commitSummary(from: JSONDecoding.decode(GitLabCommit.self, from: response.data))
    }

    func recentTags(owner: String, name: String, limit: Int = 20) async throws -> [RepoTagSummary] {
        let data = try await self.projectListData(owner: owner, name: name, suffix: "repository/tags", limit: limit)
        let tags = try JSONDecoding.decode([GitLabTag].self, from: data)
        return tags.map { RepoTagSummary(name: $0.name, commitSHA: $0.commit?.id ?? $0.target ?? "") }
    }

    func recentBranches(owner: String, name: String, limit: Int = 20) async throws -> [RepoBranchSummary] {
        let data = try await self.projectListData(owner: owner, name: name, suffix: "repository/branches", limit: limit)
        let branches = try JSONDecoding.decode([GitLabBranch].self, from: data)
        return branches.map {
            RepoBranchSummary(name: $0.name, commitSHA: $0.commit?.id ?? "", isProtected: $0.protected ?? false)
        }
    }

    func topContributors(owner: String, name: String, limit: Int = 20) async throws -> [RepoContributorSummary] {
        let data = try await self.projectListData(owner: owner, name: name, suffix: "repository/contributors", limit: limit)
        let contributors = try JSONDecoding.decode([GitLabContributor].self, from: data)
        return contributors.map {
            RepoContributorSummary(
                login: $0.name ?? $0.email ?? "Unknown",
                avatarURL: nil,
                url: nil,
                contributions: $0.commits ?? 0
            )
        }
    }

    func repoContents(owner: String, name: String, path: String? = nil) async throws -> [RepoContentItem] {
        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        var components = URLComponents(
            url: self.projectURL(baseURL: baseURL, projectPath: Self.projectPath(owner: owner, name: name), suffix: "repository/tree"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems = [
            URLQueryItem(name: "per_page", value: "100")
        ]
        if let path, path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            queryItems.append(URLQueryItem(name: "path", value: path))
        }
        components.queryItems = queryItems
        let (data, response) = try await self.authorizedGet(url: components.url!, token: token, allowedStatuses: [200, 404])
        guard response.statusCode != 404, data.isEmpty == false else { return [] }

        let items = try JSONDecoding.decode([GitLabTreeItem].self, from: data)
        return items.map { item in
            item.contentItem(apiURL: self.projectURL(
                baseURL: baseURL,
                projectPath: Self.projectPath(owner: owner, name: name),
                suffix: "repository/files/\(Self.encodedProjectPath(item.path))"
            ))
        }
    }

    func repoFileContents(owner: String, name: String, path: String) async throws -> Data {
        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        let fileURL = self.projectURL(
            baseURL: baseURL,
            projectPath: Self.projectPath(owner: owner, name: name),
            suffix: "repository/files/\(Self.encodedProjectPath(path))/raw"
        )
        let (data, _) = try await self.authorizedGet(url: fileURL, token: token)
        return data
    }

    func projectEvents(projectPath: String, limit: Int) async throws -> [ActivityEvent] {
        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        let webHost = await self.webHost()
        var components = URLComponents(
            url: self.projectURL(baseURL: baseURL, projectPath: projectPath, suffix: "events"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "\(max(1, min(limit, 100)))")]
        let (data, _) = try await self.authorizedGet(url: components.url!, token: token)
        let events = try JSONDecoding.decode([GitLabEvent].self, from: data)
        return events.compactMap {
            self.activityEvent(from: $0, projectPath: projectPath, webHost: webHost)
        }
    }

    func userEvents(
        scope: GlobalActivityScope,
        after: Date?,
        before: Date?,
        limit: Int
    ) async throws -> [ActivityEvent] {
        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        let webHost = await self.webHost()
        let perPage = 100
        let maxCount = max(limit, 0)
        guard maxCount > 0 else { return [] }

        var page = 1
        var events: [ActivityEvent] = []
        while events.count < maxCount {
            var components = URLComponents(url: self.url(baseURL: baseURL, path: "events"), resolvingAgainstBaseURL: false)!
            var queryItems = [
                URLQueryItem(name: "scope", value: scope.gitLabEventsScope),
                URLQueryItem(name: "sort", value: "desc"),
                URLQueryItem(name: "per_page", value: "\(min(perPage, maxCount - events.count))"),
                URLQueryItem(name: "page", value: "\(page)")
            ]
            if let after {
                queryItems.append(URLQueryItem(name: "after", value: Self.queryDate(after)))
            }
            if let before {
                queryItems.append(URLQueryItem(name: "before", value: Self.queryDate(before)))
            }
            components.queryItems = queryItems

            let (data, response) = try await self.authorizedGet(url: components.url!, token: token)
            let pageEvents = try JSONDecoding.decode([GitLabEvent].self, from: data)
            events.append(contentsOf: pageEvents.compactMap {
                self.activityEvent(from: $0, projectPath: nil, webHost: webHost)
            })

            guard events.count < maxCount,
                  pageEvents.isEmpty == false,
                  let nextPage = Self.nextPage(from: response)
            else { break }

            page = nextPage
        }

        return Array(events.prefix(maxCount))
    }

    private func membershipProjectsPage(page: Int) async throws -> GitLabProjectPage {
        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        var components = URLComponents(url: self.url(baseURL: baseURL, path: "projects"), resolvingAgainstBaseURL: false)!
        components.queryItems = Self.membershipProjectsQueryItems(page: page)
        let (data, response) = try await self.authorizedGet(url: components.url!, token: token)
        let projects = try JSONDecoding.decode([GitLabProject].self, from: data)
        return GitLabProjectPage(
            items: projects,
            nextPage: Self.nextPage(from: response)
        )
    }

    private func projectListData(
        owner: String,
        name: String,
        suffix: String,
        limit: Int,
        queryItems: [URLQueryItem] = []
    ) async throws -> Data {
        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        var components = URLComponents(
            url: self.projectURL(baseURL: baseURL, projectPath: Self.projectPath(owner: owner, name: name), suffix: suffix),
            resolvingAgainstBaseURL: false
        )!
        var items = queryItems.filter { $0.name != "per_page" }
        items.append(URLQueryItem(name: "per_page", value: "\(max(1, min(limit, 100)))"))
        components.queryItems = items
        let (data, _) = try await self.authorizedGet(url: components.url!, token: token)
        return data
    }

    private func projectItemData(
        owner: String,
        name: String,
        suffix: String,
        allowedStatuses: Set<Int>
    ) async throws -> (data: Data, statusCode: Int) {
        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        let url = self.projectURL(baseURL: baseURL, projectPath: Self.projectPath(owner: owner, name: name), suffix: suffix)
        let (data, response) = try await self.authorizedGet(url: url, token: token, allowedStatuses: allowedStatuses)
        return (data, response.statusCode)
    }

    private static func issueSummary(from issue: GitLabIssue) -> RepoIssueSummary {
        RepoIssueSummary(
            number: issue.iid,
            title: issue.title,
            url: issue.webUrl,
            updatedAt: issue.updatedAt,
            createdAt: issue.createdAt,
            authorLogin: issue.author?.username,
            authorAvatarURL: issue.author?.avatarUrl,
            assigneeLogins: (issue.assignees ?? []).compactMap(\.username),
            commentCount: issue.userNotesCount ?? 0,
            labels: issue.labels
        )
    }

    private static func mergeRequestSummary(from request: GitLabMergeRequest) -> RepoPullRequestSummary {
        RepoPullRequestSummary(
            number: request.iid,
            title: request.title,
            url: request.webUrl,
            updatedAt: request.updatedAt,
            createdAt: request.createdAt,
            state: request.state == "merged" || request.state == "closed" ? .closed : .open,
            mergedAt: request.mergedAt,
            authorLogin: request.author?.username,
            authorAvatarURL: request.author?.avatarUrl,
            isDraft: (request.draft ?? false) || (request.workInProgress ?? false),
            commentCount: request.userNotesCount ?? 0,
            reviewCommentCount: 0,
            labels: request.labels,
            headRefName: request.sourceBranch,
            baseRefName: request.targetBranch,
            requestedReviewerLogins: (request.reviewers ?? []).compactMap(\.username)
        )
    }

    private static func commitSummary(from commit: GitLabCommit) -> RepoCommitSummary? {
        guard let url = commit.webUrl else { return nil }

        let message = (commit.title ?? commit.message ?? commit.id).trimmingCharacters(in: .whitespacesAndNewlines)
        return RepoCommitSummary(
            sha: commit.id,
            message: message,
            url: url,
            authoredAt: commit.authoredDate ?? .distantPast,
            authorName: commit.authorName,
            authorLogin: nil,
            authorAvatarURL: nil
        )
    }

    private func authorizedGet(
        url: URL,
        token: String,
        allowedStatuses: Set<Int> = [200]
    ) async throws -> (Data, HTTPURLResponse) {
        let now = Date()
        if let limitedUntil = await self.eTagCache.rateLimitUntil(now: now) {
            let message = Self.rateLimitMessage(until: limitedUntil, now: now)
            await self.rateLimitErrorRecorder(limitedUntil, message)
            throw GitLabAPIError.badStatus(code: 429, message: message)
        }
        if let cooldown = await self.backoffTracker.cooldown(for: url, now: now) {
            throw GitLabAPIError.badStatus(
                code: 503,
                message: Self.endpointCooldownMessage(until: cooldown, now: now)
            )
        }

        let cached = await self.eTagCache.cachedResponse(for: url)
        var request = URLRequest(url: url)
        request.addValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = cached?.etag {
            request.addValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, responseAny) = try await self.session.data(for: request)
        guard let response = responseAny as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let responseDate = Date()
        await self.responseRecorder(response, responseDate)
        if response.statusCode == 304 {
            guard allowedStatuses.contains(200),
                  let cached,
                  let cachedResponse = cached.httpResponse(for: url)
            else {
                throw GitLabAPIError.badStatus(
                    code: response.statusCode,
                    message: Self.statusMessage(for: response.statusCode, data: data)
                )
            }

            return (cached.data, cachedResponse)
        }
        if Self.shouldCooldown(statusCode: response.statusCode) {
            let cooldown = Self.cooldownUntil(
                from: response,
                defaultDelay: response.statusCode == 429 ? 60 : 30,
                now: responseDate
            )
            await self.backoffTracker.setCooldown(url: url, until: cooldown)

            if response.statusCode == 429 {
                let message = Self.rateLimitMessage(until: cooldown, now: responseDate)
                await self.eTagCache.setRateLimitReset(
                    resource: Self.rateLimitResource(from: response),
                    date: cooldown,
                    message: message
                )
                await self.rateLimitErrorRecorder(cooldown, message)
            }
        }
        guard allowedStatuses.contains(response.statusCode) else {
            throw GitLabAPIError.badStatus(
                code: response.statusCode,
                message: response.statusCode == 429
                    ? Self.rateLimitMessage(
                        until: Self.cooldownUntil(from: response, defaultDelay: 60, now: responseDate),
                        now: responseDate
                    )
                    : Self.statusMessage(for: response.statusCode, data: data)
            )
        }

        if (200 ..< 300).contains(response.statusCode) {
            await self.eTagCache.recordResponse(url: url, data: data, response: response)
        }
        return (data, response)
    }

    private static func shouldCooldown(statusCode: Int) -> Bool {
        statusCode == 429 || (500 ..< 600).contains(statusCode)
    }

    private static func cooldownUntil(
        from response: HTTPURLResponse,
        defaultDelay: TimeInterval,
        now: Date
    ) -> Date {
        let candidates = [
            Self.dateFromEpochHeader("X-RateLimit-Reset", response: response),
            Self.dateFromRateLimitResetHeader(response: response, now: now),
            Self.dateFromRetryAfterHeader(response: response, now: now)
        ].compactMap(\.self)

        if let candidate = candidates.filter({ $0 > now }).min() {
            return candidate
        }
        return now.addingTimeInterval(defaultDelay)
    }

    private static func dateFromEpochHeader(_ field: String, response: HTTPURLResponse) -> Date? {
        guard let rawValue = response.value(forHTTPHeaderField: field),
              let epoch = TimeInterval(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }

        return Date(timeIntervalSince1970: epoch)
    }

    private static func dateFromRateLimitResetHeader(response: HTTPURLResponse, now: Date) -> Date? {
        guard let rawValue = response.value(forHTTPHeaderField: "RateLimit-Reset")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let value = TimeInterval(rawValue)
        else { return nil }

        return value > 1_000_000_000
            ? Date(timeIntervalSince1970: value)
            : now.addingTimeInterval(value)
    }

    private static func dateFromRetryAfterHeader(response: HTTPURLResponse, now: Date) -> Date? {
        guard let rawValue = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            rawValue.isEmpty == false
        else { return nil }

        if let seconds = TimeInterval(rawValue) {
            return now.addingTimeInterval(seconds)
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: rawValue)
    }

    private static func rateLimitResource(from response: HTTPURLResponse) -> String {
        let resource = response.value(forHTTPHeaderField: "X-RateLimit-Resource")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resource, resource.isEmpty == false else { return "core" }

        return resource
    }

    private static func rateLimitMessage(until: Date, now: Date) -> String {
        "GitLab rate limit hit; resets \(RelativeFormatter.string(from: until, relativeTo: now))."
    }

    private static func endpointCooldownMessage(until: Date, now: Date) -> String {
        "GitLab endpoint is cooling down; retry \(RelativeFormatter.string(from: until, relativeTo: now))."
    }

    static func nextPage(from response: HTTPURLResponse) -> Int? {
        guard let raw = response.value(forHTTPHeaderField: "X-Next-Page")?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false
        else { return nil }

        return Int(raw)
    }

    static func statusMessage(for status: Int, data: Data) -> String {
        let fallback = HTTPURLResponse.localizedString(forStatusCode: status)
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return "GitLab returned \(status): \(fallback)."
        }

        let message = Self.message(from: object)
        guard message.isEmpty == false else {
            return "GitLab returned \(status): \(fallback)."
        }

        return "GitLab returned \(status): \(message)."
    }

    private static func message(from object: Any) -> String {
        if let string = object as? String {
            return string
        }
        if let strings = object as? [String] {
            return strings.joined(separator: ", ")
        }
        if let dictionary = object as? [String: Any] {
            if let message = dictionary["message"] {
                return Self.message(from: message)
            }
            return dictionary
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \(Self.message(from: $0.value))" }
                .filter { $0.hasSuffix(": ") == false }
                .joined(separator: ", ")
        }
        return ""
    }

    private func projectURL(baseURL: URL, projectPath: String, suffix: String) -> URL {
        let encoded = Self.encodedProjectPath(projectPath)
        let trimmedSuffix = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = trimmedSuffix.isEmpty ? "projects/\(encoded)" : "projects/\(encoded)/\(trimmedSuffix)"
        return self.url(baseURL: baseURL, path: path)
    }

    private func url(baseURL: URL, path: String) -> URL {
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(base)/\(trimmedPath)")!
    }

    private static func encodedProjectPath(_ projectPath: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return projectPath.addingPercentEncoding(withAllowedCharacters: allowed) ?? projectPath
    }

    private func projectWebURL(webHost: URL, projectPath: String, components: [String]) -> URL {
        var url = webHost
        for component in projectPath.split(separator: "/").map(String.init) + components {
            url.appendPathComponent(component)
        }
        return url
    }

    private func releaseAssets(from release: GitLabRelease) -> [RepoReleaseAssetSummary] {
        let links = (release.assets?.links ?? []) + (release.assets?.sources ?? [])
        return links.compactMap { link in
            guard let name = link.name,
                  let url = link.directAssetUrl ?? link.url
            else { return nil }

            return RepoReleaseAssetSummary(
                name: name,
                sizeBytes: nil,
                downloadCount: 0,
                url: url
            )
        }
    }

    private static func ciStatus(fromGitLabStatus status: String?) -> CIStatus {
        switch status {
        case "success": .passing
        case "failed", "canceled", "skipped": .failing
        case "created", "waiting_for_resource", "preparing", "pending", "running", "manual", "scheduled": .pending
        default: .unknown
        }
    }

    private func activityEvent(from event: GitLabEvent, projectPath: String?, webHost: URL) -> ActivityEvent? {
        guard let date = event.createdAt else { return nil }

        let actor = event.author?.username ?? event.authorUsername ?? event.author?.name ?? "GitLab"
        let title = self.activityTitle(from: event)
        let url = event.targetUrl ?? self.activityFallbackURL(from: event, projectPath: projectPath, webHost: webHost)
        return ActivityEvent(
            title: title,
            actor: actor,
            actorAvatarURL: event.author?.avatarUrl,
            date: date,
            url: url,
            eventType: event.targetType ?? event.actionName,
            metadata: ActivityMetadata(
                actor: actor,
                action: event.actionName ?? "updated",
                target: event.targetTitle ?? projectPath ?? "GitLab activity",
                url: url
            )
        )
    }

    private func activityTitle(from event: GitLabEvent) -> String {
        if let pushTitle = event.pushData?.commitTitle, pushTitle.isEmpty == false {
            return "Push: \(pushTitle)"
        }
        if let noteType = event.note?.noteableType, let iid = event.note?.noteableIid {
            return "Comment on \(noteType) !\(iid)"
        }
        let action = event.actionName ?? "Updated"
        if let target = event.targetTitle, target.isEmpty == false {
            return "\(action.capitalized): \(target)"
        }
        if let targetType = event.targetType, targetType.isEmpty == false {
            return "\(action.capitalized) \(targetType)"
        }
        return action.capitalized
    }

    private func activityFallbackURL(from event: GitLabEvent, projectPath: String?, webHost: URL) -> URL {
        guard let projectPath, projectPath.isEmpty == false else {
            if let projectId = event.projectId {
                return self.projectWebURL(webHost: webHost, projectPath: "\(projectId)", components: [])
            }
            if let authorURL = event.author?.webUrl {
                return authorURL
            }
            return webHost
        }

        if let pushTarget = event.pushData?.commitTo, pushTarget.isEmpty == false {
            return self.projectWebURL(webHost: webHost, projectPath: projectPath, components: ["-", "commit", pushTarget])
        }
        switch event.targetType?.lowercased() {
        case "issue":
            if let iid = event.targetIid {
                return self.projectWebURL(webHost: webHost, projectPath: projectPath, components: ["-", "issues", "\(iid)"])
            }
        case "mergerequest", "merge_request":
            if let iid = event.targetIid {
                return self.projectWebURL(webHost: webHost, projectPath: projectPath, components: ["-", "merge_requests", "\(iid)"])
            }
        default:
            break
        }
        return self.projectWebURL(webHost: webHost, projectPath: projectPath, components: [])
    }

    private static func queryDate(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}

private extension GlobalActivityScope {
    var gitLabEventsScope: String {
        switch self {
        case .allActivity: "all"
        case .myActivity: "created_by_me"
        }
    }
}

private struct GitLabProjectPage {
    let items: [GitLabProject]
    let nextPage: Int?
}
