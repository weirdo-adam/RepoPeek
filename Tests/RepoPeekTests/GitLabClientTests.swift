import Foundation
@testable import RepoPeekCore
import Testing

struct GitLabClientTests {
    @Test
    func `api host uses GitLab v4 path`() throws {
        let gitlabCom = try GitLabClient.apiHost(for: #require(URL(string: "https://gitlab.com")))
        let selfManaged = try GitLabClient.apiHost(for: #require(URL(string: "https://gitlab.example.com")))
        let brandedSelfManaged = try GitLabClient.apiHost(for: #require(URL(string: "https://gitlab.internal.example.com")))
        let relativeSelfManaged = try GitLabClient.apiHost(for: #require(URL(string: "https://gitlab.internal.example.com:8443/gitlab/")))

        #expect(gitlabCom.absoluteString == "https://gitlab.com/api/v4")
        #expect(selfManaged.absoluteString == "https://gitlab.example.com/api/v4")
        #expect(brandedSelfManaged.absoluteString == "https://gitlab.internal.example.com/api/v4")
        #expect(relativeSelfManaged.absoluteString == "https://gitlab.internal.example.com:8443/gitlab/api/v4")
    }

    @Test
    func `web host preserves self managed port and relative path`() async throws {
        let client = GitLabClient()
        try await client.setWebHost(#require(URL(string: "https://gitlab.internal.example.com:8443/gitlab/")))

        let webHost = await client.webHost
        let apiHost = await client.apiHost
        #expect(webHost.absoluteString == "https://gitlab.internal.example.com:8443/gitlab")
        #expect(apiHost.absoluteString == "https://gitlab.internal.example.com:8443/gitlab/api/v4")
    }

    @Test
    func `membership projects query requests simple project inventory`() {
        let items = GitLabRestAPI.membershipProjectsQueryItems(page: 2)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })

        #expect(values["membership"] == "true")
        #expect(values["simple"] == "true")
        #expect(values["order_by"] == "last_activity_at")
        #expect(values["sort"] == "desc")
        #expect(values["per_page"] == "100")
        #expect(values["page"] == "2")
    }

    @Test
    func `gitlab project maps to repository identity with subgroup path`() throws {
        let data = Data("""
        {
          "id": 101,
          "name": "Project",
          "path": "project",
          "path_with_namespace": "group/subgroup/project",
          "archived": true,
          "star_count": 7,
          "forks_count": 2,
          "open_issues_count": 4,
          "last_activity_at": "2026-05-01T12:00:00Z",
          "web_url": "https://gitlab.example.com/group/subgroup/project",
          "namespace": {"full_path": "group/subgroup"}
        }
        """.utf8)

        let project = try JSONDecoding.decode(GitLabProject.self, from: data)
        let repo = try project.repository(webHost: #require(URL(string: "https://gitlab.example.com")))

        #expect(repo.id == "gitlab.example.com/group/subgroup/project")
        #expect(repo.fullName == "group/subgroup/project")
        #expect(repo.owner == "group/subgroup")
        #expect(repo.name == "project")
        #expect(repo.isArchived)
        #expect(repo.stars == 7)
        #expect(repo.forks == 2)
        #expect(repo.openIssues == 4)
        #expect(repo.openPulls == 0)
        #expect(repo.identity?.lookupKey == repo.id)
    }

    @Test
    func `repository list fetches membership projects with PAT`() async throws {
        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            #expect(request.url?.path == "/api/v4/projects")
            #expect(request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "glpat_test")

            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "page" })?
                .value
            if page == "1" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["X-Next-Page": "2"]
                )!
                let data = Data("""
                [
                  {
                    "id": 101,
                    "name": "Project A",
                    "path": "project-a",
                    "path_with_namespace": "group/project-a",
                    "archived": false,
                    "star_count": 1,
                    "forks_count": 0,
                    "open_issues_count": 0,
                    "last_activity_at": "2026-05-01T12:00:00Z",
                    "web_url": "https://gitlab.com/group/project-a",
                    "namespace": {"full_path": "group"}
                  }
                ]
                """.utf8)
                return (data, response)
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            [
              {
                "id": 102,
                "name": "Project B",
                "path": "project-b",
                "path_with_namespace": "group/subgroup/project-b",
                "archived": false,
                "star_count": 2,
                "forks_count": 1,
                "open_issues_count": 3,
                "last_activity_at": "2026-05-02T12:00:00Z",
                "web_url": "https://gitlab.com/group/subgroup/project-b",
                "namespace": {"full_path": "group/subgroup"}
              }
            ]
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let client = Self.gitLabClient(session: session, handlerID: handlerID)
        try await client.setWebHost(#require(URL(string: "https://gitlab.com")))
        await client.setTokenProvider { "glpat_test" }

        let repos = try await client.repositoryList(limit: nil)

        #expect(repos.map(\.fullName) == ["group/project-a", "group/subgroup/project-b"])
    }

    @Test
    func `recent issues use encoded GitLab project path`() async throws {
        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            #expect(request.url?.absoluteString.contains("/api/v4/projects/group%2Fsubgroup%2Fproject/issues?") == true)
            #expect(request.url?.absoluteString.contains("/repos/") == false)
            #expect(request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "glpat_test")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer glpat_test")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value) })
            #expect(values["state"] == "opened")
            #expect(values["order_by"] == "updated_at")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            [
              {
                "iid": 7,
                "title": "Fix subgroup issue",
                "web_url": "https://gitlab.internal.example.com/group/subgroup/project/-/issues/7",
                "updated_at": "2026-05-01T12:00:00Z",
                "created_at": "2026-05-01T11:00:00Z",
                "author": {"username": "alice", "avatar_url": "https://example.com/a.png"},
                "assignees": [{"username": "bob"}],
                "user_notes_count": 3,
                "labels": ["backend"]
              }
            ]
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let client = Self.gitLabClient(session: session, handlerID: handlerID)
        try await client.setWebHost(#require(URL(string: "https://gitlab.internal.example.com")))
        await client.setTokenProvider { "glpat_test" }

        let issues = try await client.recentIssues(owner: "group", name: "subgroup/project", limit: 20)

        #expect(issues.map(\.number) == [7])
        #expect(issues.first?.authorLogin == "alice")
        #expect(issues.first?.assigneeLogins == ["bob"])
    }

    @Test
    func `recent merge requests use encoded GitLab project path`() async throws {
        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            #expect(request.url?.absoluteString.contains("/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests?") == true)
            #expect(request.url?.absoluteString.contains("/repos/") == false)

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            [
              {
                "iid": 9,
                "title": "Ship GitLab menus",
                "web_url": "https://gitlab.internal.example.com/group/subgroup/project/-/merge_requests/9",
                "updated_at": "2026-05-02T12:00:00Z",
                "created_at": "2026-05-02T11:00:00Z",
                "state": "opened",
                "author": {"username": "alice"},
                "draft": false,
                "user_notes_count": 5,
                "labels": ["ui"],
                "source_branch": "feature/gitlab",
                "target_branch": "main",
                "reviewers": [{"username": "carol"}]
              }
            ]
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let client = Self.gitLabClient(session: session, handlerID: handlerID)
        try await client.setWebHost(#require(URL(string: "https://gitlab.internal.example.com")))
        await client.setTokenProvider { "glpat_test" }

        let mergeRequests = try await client.recentMergeRequests(owner: "group", name: "subgroup/project", limit: 20)

        #expect(mergeRequests.map(\.number) == [9])
        #expect(mergeRequests.first?.headRefName == "feature/gitlab")
        #expect(mergeRequests.first?.requestedReviewerLogins == ["carol"])
    }

    @Test
    func `open merge request count uses GitLab total header`() async throws {
        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            #expect(request.url?.absoluteString.contains("/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests?") == true)

            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value) })
            #expect(values["state"] == "opened")
            #expect(values["per_page"] == "1")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-Total": "42"]
            )!
            return (Data("[]".utf8), response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let client = Self.gitLabClient(session: session, handlerID: handlerID)
        try await client.setWebHost(#require(URL(string: "https://gitlab.internal.example.com")))
        await client.setTokenProvider { "glpat_test" }

        let count = try await client.openMergeRequestCount(owner: "group", name: "subgroup/project")

        #expect(count == 42)
    }

    @Test
    func `authorized GET replays cached response on not modified`() async throws {
        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        let recorder = RequestRecorder()
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            let requestNumber = recorder.record(request)
            #expect(request.url?.absoluteString.contains("/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests?") == true)

            if requestNumber == 1 {
                #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "ETag": "etag-1",
                        "X-Total": "42",
                        "X-RateLimit-Resource": "core",
                        "X-RateLimit-Limit": "5000",
                        "X-RateLimit-Remaining": "4999"
                    ]
                )!
                return (Data("[]".utf8), response)
            }

            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "etag-1")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 304,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let client = Self.gitLabClient(session: session, handlerID: handlerID)
        try await client.setWebHost(#require(URL(string: "https://gitlab.internal.example.com")))
        await client.setTokenProvider { "glpat_test" }

        let first = try await client.openMergeRequestCount(owner: "group", name: "subgroup/project")
        let second = try await client.openMergeRequestCount(owner: "group", name: "subgroup/project")

        #expect(first == 42)
        #expect(second == 42)
        #expect(recorder.count == 2)
        let diagnostics = await client.diagnostics()
        #expect(diagnostics.etagEntries == 1)
        #expect(diagnostics.restRateLimit?.remaining == 4999)
    }

    @Test
    func `rate limited GET records diagnostics and skips active cooldown request`() async throws {
        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        let recorder = RequestRecorder()
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            let requestNumber = recorder.record(request)
            #expect(requestNumber == 1)
            let reset = Int(Date().addingTimeInterval(120).timeIntervalSince1970)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: [
                    "Retry-After": "120",
                    "X-RateLimit-Resource": "core",
                    "X-RateLimit-Limit": "5000",
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": "\(reset)"
                ]
            )!
            return (Data(#"{"message":"rate limited"}"#.utf8), response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let client = Self.gitLabClient(session: session, handlerID: handlerID)
        try await client.setWebHost(#require(URL(string: "https://gitlab.com")))
        await client.setTokenProvider { "glpat_test" }

        do {
            _ = try await client.repositoryList(limit: 1)
            Issue.record("Expected rate-limit error")
        } catch let error as GitLabAPIError {
            guard case let .badStatus(code, message) = error else {
                Issue.record("Expected badStatus, got \(error)")
                return
            }

            #expect(code == 429)
            #expect(message?.contains("GitLab rate limit hit") == true)
        }

        let diagnostics = await client.diagnostics()
        #expect(diagnostics.rateLimitReset != nil)
        #expect(diagnostics.lastRateLimitError?.contains("GitLab rate limit hit") == true)
        #expect(diagnostics.backoffEntries == 1)
        #expect(diagnostics.endpointCooldowns.first?.endpoint == "projects")
        #expect(diagnostics.restRateLimit?.remaining == 0)

        do {
            _ = try await client.repositoryList(limit: 1)
            Issue.record("Expected cached rate-limit error")
        } catch let error as GitLabAPIError {
            guard case let .badStatus(code, _) = error else {
                Issue.record("Expected badStatus, got \(error)")
                return
            }

            #expect(code == 429)
        }
        #expect(recorder.count == 1)
    }

    @Test
    func `user activity events use authenticated events endpoint with date range`() async throws {
        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            #expect(request.url?.path == "/api/v4/events")
            #expect(request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "glpat_test")

            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value) })
            #expect(values["scope"] == "created_by_me")
            #expect(values["after"] == "2026-05-01")
            #expect(values["before"] == "2026-05-29")
            #expect(values["per_page"] == "100")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            [
              {
                "action_name": "pushed",
                "target_type": "PushEvent",
                "created_at": "2026-05-28T12:00:00Z",
                "author_username": "alice",
                "target_url": "https://gitlab.com/group/project/-/commit/abc",
                "push_data": {"commit_title": "Align activity calendar", "commit_to": "abc"}
              }
            ]
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let after = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let before = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 29)))
        let client = Self.gitLabClient(session: session, handlerID: handlerID)
        try await client.setWebHost(#require(URL(string: "https://gitlab.com")))
        await client.setTokenProvider { "glpat_test" }

        let events = try await client.userActivityEvents(
            username: "alice",
            scope: .myActivity,
            after: after,
            before: before,
            limit: 100
        )

        #expect(events.count == 1)
        #expect(events.first?.actor == "alice")
        #expect(events.first?.title == "Push: Align activity calendar")
    }
}

private extension GitLabClientTests {
    final class RequestRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [URLRequest] = []

        func record(_ request: URLRequest) -> Int {
            self.lock.lock()
            defer { self.lock.unlock() }
            self.requests.append(request)
            return self.requests.count
        }

        var count: Int {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.requests.count
        }
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return config
    }

    static func taggedSession(_: URLSession, handlerID: String) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Handler-ID": handlerID]
        return URLSession(configuration: config)
    }

    static func gitLabClient(session: URLSession, handlerID: String) -> GitLabClient {
        GitLabClient(
            session: self.taggedSession(session, handlerID: handlerID),
            eTagCache: ETagCache(),
            backoffTracker: BackoffTracker()
        )
    }

    // swiftlint:disable static_over_final_class
    final class MockURLProtocol: URLProtocol {
        private static let handlersLock = NSLock()
        private nonisolated(unsafe) static var handlers: [String: @Sendable (URLRequest) throws -> (Data, URLResponse)] = [:]

        static func register(
            handlerID: String,
            handler: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)
        ) {
            self.handlersLock.lock()
            self.handlers[handlerID] = handler
            self.handlersLock.unlock()
        }

        static func unregister(handlerID: String) {
            self.handlersLock.lock()
            self.handlers[handlerID] = nil
            self.handlersLock.unlock()
        }

        override class func canInit(with request: URLRequest) -> Bool {
            request.value(forHTTPHeaderField: "X-Handler-ID") != nil
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard
                let handlerID = request.value(forHTTPHeaderField: "X-Handler-ID"),
                let handler = Self.handler(for: handlerID)
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }

            do {
                let (data, response) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}

        private static func handler(for handlerID: String) -> (@Sendable (URLRequest) throws -> (Data, URLResponse))? {
            self.handlersLock.lock()
            defer { handlersLock.unlock() }
            return self.handlers[handlerID]
        }
    }
    // swiftlint:enable static_over_final_class
}
