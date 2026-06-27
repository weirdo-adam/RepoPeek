import Foundation
@testable import RepoPeekCore
import Testing

struct PullRequestAISummarizerTests {
    @Test
    func `AI summary settings expose provider-specific models and request URLs`() {
        #expect(AISummarySettings.modelOptions(for: .openAIResponses).map(\.id) == ["gpt-5.5"])
        #expect(AISummarySettings.modelOptions(for: .claudeCode).map(\.id) == ["sonnet", "opus"])
        #expect(AISummarySettings.normalizedModel("opus", provider: .claudeCode) == "opus")
        #expect(AISummarySettings.normalizedModel("gpt-5.5", provider: .claudeCode) == "sonnet")
        #expect(AISummarySettings.normalizedRequestURLString("notaurl") == nil)
        #expect(
            AISummarySettings.normalizedRequestURLString("https://proxy.example.com/v1/responses")?
                .absoluteString == "https://proxy.example.com/v1/responses"
        )
    }

    @Test
    func `candidate matches include unsummarized merge requests only`() throws {
        let mergeRequests = try (0 ..< 14).map { index in
            try Self.makeMatch(
                number: index + 1,
                kind: .pullRequest,
                url: "https://gitlab.example.com/owner/repo/-/merge_requests/\(index + 1)"
            )
        }
        let issue = try Self.makeMatch(
            number: 99,
            kind: .issue,
            url: "https://gitlab.example.com/owner/repo/-/issues/99"
        )
        let alreadySummarized = try Self.makeMatch(
            number: 100,
            kind: .pullRequest,
            url: "https://gitlab.example.com/owner/repo/-/merge_requests/100",
            aiSummary: "Already summarized."
        )

        let candidates = PullRequestAISummarizer.candidateMatches(
            from: [issue, alreadySummarized] + mergeRequests
        )

        #expect(candidates.count == PullRequestAISummarizer.maximumBatchSize)
        #expect(candidates.allSatisfy { $0.kind == .pullRequest && $0.aiSummary == nil })
        #expect(!candidates.contains { $0.url.absoluteString.contains("issues") })
        #expect(!candidates.contains { $0.url.absoluteString.contains("100") })
    }

    @Test
    func `prompt input uses GitLab merge request context`() throws {
        let match = try Self.makeMatch(
            number: 7,
            kind: .pullRequest,
            url: "https://gitlab.example.com/owner/repo/-/merge_requests/7"
        )

        let input = try PullRequestAISummarizer.makeInputText(for: [match])
        let item = try #require(Self.promptItems(from: input).first)

        #expect(input.contains("GitLab merge requests"))
        #expect(input.contains("RepoPeek Issue Navigator"))
        #expect(item["repository"] as? String == "owner/repo")
        #expect(item["url"] as? String == match.url.absoluteString)
    }

    @Test
    func `summarize merge requests sends responses request to configured endpoint and merges summaries`() async throws {
        let service = "com.weirdoadam.repopeek.auth.tests.\(UUID().uuidString)"
        let tokenStore = TokenStore(service: service)
        defer { tokenStore.clearAllCredentials() }
        try tokenStore.saveOpenAIAPIKey("sk-test")

        let match = try Self.makeMatch(
            number: 12,
            kind: .pullRequest,
            url: "https://gitlab.example.com/owner/repo/-/merge_requests/12"
        )
        let responseText = """
        {"summaries":[{"url":"\(match.url.absoluteString)","summary":"Adds a compact status summary."}]}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output_text": responseText])
        let capturedRequest = CapturedRequest()

        let summarizer = PullRequestAISummarizer(
            apiKeyStore: OpenAIAPIKeyStore(tokenStore: tokenStore, environment: { _ in nil }),
            transport: { request in
                capturedRequest.set(request)
                let requestURL = try #require(request.url)
                let response = try #require(HTTPURLResponse(
                    url: requestURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
                return (responseData, response)
            }
        )

        let summarized = try await summarizer.summarizeMergeRequests(
            in: [match],
            settings: AISummarySettings(
                enabled: true,
                requestURL: URL(string: "https://ai.example.com/v1/responses")
            )
        )

        let request = try #require(capturedRequest.value)
        #expect(request.url?.absoluteString == "https://ai.example.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let requestBody = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        #expect(object["model"] as? String == AISummarySettings.defaultModel)
        #expect(object["store"] as? Bool == false)
        let input = try #require(object["input"] as? String)
        let item = try #require(Self.promptItems(from: input).first)
        #expect(item["url"] as? String == match.url.absoluteString)
        #expect(summarized.first?.aiSummary == "Adds a compact status summary.")
    }

    @Test
    func `summarize merge requests sends claude code print mode request and merges summaries`() async throws {
        let match = try Self.makeMatch(
            number: 12,
            kind: .pullRequest,
            url: "https://gitlab.example.com/owner/repo/-/merge_requests/12"
        )
        let capturedArguments = CapturedArguments()
        let summarizer = PullRequestAISummarizer(
            claudeCodeRunner: { arguments in
                capturedArguments.set(arguments)
                return ClaudeCodeProcessResult(
                    statusCode: 0,
                    stdout: """
                    {"structured_output":{"summaries":[{"url":"\(match.url.absoluteString)","summary":"Highlights the sidebar summary path."}]}}
                    """,
                    stderr: ""
                )
            }
        )

        let summarized = try await summarizer.summarizeMergeRequests(
            in: [match],
            settings: AISummarySettings(provider: .claudeCode, enabled: true, model: "sonnet")
        )

        let arguments = try #require(capturedArguments.value)
        let promptIndex = try #require(arguments.firstIndex(of: "-p"))
        let item = try #require(Self.promptItems(from: arguments[promptIndex + 1]).first)
        #expect(item["url"] as? String == match.url.absoluteString)
        let modelIndex = try #require(arguments.firstIndex(of: "--model"))
        #expect(arguments[modelIndex + 1] == "sonnet")
        let outputFormatIndex = try #require(arguments.firstIndex(of: "--output-format"))
        #expect(arguments[outputFormatIndex + 1] == "json")
        let toolsIndex = try #require(arguments.firstIndex(of: "--tools"))
        #expect(arguments[toolsIndex + 1].isEmpty)
        #expect(arguments.contains("--json-schema"))
        #expect(arguments.contains("--no-session-persistence"))
        #expect(summarized.first?.aiSummary == "Highlights the sidebar summary path.")
    }

    @Test
    func `parse summaries accepts JSON object in surrounding text`() throws {
        let parsed = try PullRequestAISummarizer.parseSummaries(
            from: """
            Here is the JSON:
            {"summaries":[{"url":"https://gitlab.example.com/owner/repo/-/merge_requests/2","summary":"Reviews token storage."}]}
            """
        )

        let url = try #require(URL(string: "https://gitlab.example.com/owner/repo/-/merge_requests/2"))
        #expect(parsed[url] == "Reviews token storage.")
    }

    private static func makeMatch(
        number: Int,
        kind: GitLabReferenceKind,
        url: String,
        aiSummary: String? = nil
    ) throws -> GitLabReferenceMatch {
        let query: GitLabReferenceQuery = switch kind {
        case .issue:
            .repositoryIssueNumber(repositoryFullName: "owner/repo", number: number)
        case .pullRequest:
            .repositoryIssueNumber(repositoryFullName: "owner/repo", number: number)
        case .commit:
            .repositoryCommitHash(repositoryFullName: "owner/repo", hash: "abcdef1234567890")
        case .workflowRun:
            .repositoryWorkflowRun(repositoryFullName: "owner/repo", runID: Int64(number))
        }

        return try GitLabReferenceMatch(
            query: query,
            title: "Review AI summary integration",
            url: #require(URL(string: url)),
            repositoryFullName: "owner/repo",
            kind: kind,
            state: .open,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 20),
            bodyPreview: "This change adds concise summaries to the Issue Navigator sidebar.",
            authorLogin: "alice",
            aiSummary: aiSummary
        )
    }

    private static func promptItems(from input: String) throws -> [[String: Any]] {
        let marker = "Input JSON:"
        guard let markerRange = input.range(of: marker) else {
            return []
        }

        let json = input[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try #require(json.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(object["items"] as? [[String: Any]])
    }
}

private final class CapturedRequest: @unchecked Sendable {
    private var request: URLRequest?

    var value: URLRequest? {
        self.request
    }

    func set(_ request: URLRequest) {
        self.request = request
    }
}

private final class CapturedArguments: @unchecked Sendable {
    private var arguments: [String]?

    var value: [String]? {
        self.arguments
    }

    func set(_ arguments: [String]) {
        self.arguments = arguments
    }
}
