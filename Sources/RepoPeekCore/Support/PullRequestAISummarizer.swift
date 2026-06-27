import Foundation

public enum PullRequestAISummarizerError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case invalidHTTPResponse(Int)
    case missingTextOutput
    case claudeCodeUnavailable(String)
    case claudeCodeFailed(Int32, String)
    case invalidSummaryJSON

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "OpenAI API key is not configured."
        case let .invalidHTTPResponse(statusCode):
            "OpenAI API request failed with HTTP \(statusCode)."
        case .missingTextOutput:
            "OpenAI API response did not include text output."
        case let .claudeCodeUnavailable(reason):
            "Claude Agent CLI is unavailable: \(reason)"
        case let .claudeCodeFailed(statusCode, message):
            "Claude Agent CLI failed with status \(statusCode): \(message)"
        case .invalidSummaryJSON:
            "AI response did not include valid summary JSON."
        }
    }
}

public struct PullRequestAISummarizer {
    public static let maximumBatchSize = 12
    public static let defaultTransport: OpenAIResponsesTransport = { request in
        try await URLSession.shared.data(for: request)
    }

    public static let defaultClaudeCodeRunner: ClaudeCodeProcessRunner = ClaudeCodeClient.defaultRunner

    static let instructions = """
    You summarize GitLab merge requests for a macOS menu bar app sidebar.
    Return only valid JSON matching {"summaries":[{"url":"...","summary":"..."}]}.
    Each summary must be one concise factual sentence, 32 words or fewer.
    Prefer the input language when it is clear. Do not use markdown.
    """

    private let apiKeyStore: OpenAIAPIKeyStore
    private let openAIClient: OpenAIResponsesClient
    private let claudeCodeClient: ClaudeCodeClient

    public init(
        apiKeyStore: OpenAIAPIKeyStore = OpenAIAPIKeyStore(),
        transport: @escaping OpenAIResponsesTransport = PullRequestAISummarizer.defaultTransport,
        claudeCodeRunner: @escaping ClaudeCodeProcessRunner = PullRequestAISummarizer.defaultClaudeCodeRunner
    ) {
        self.apiKeyStore = apiKeyStore
        self.openAIClient = OpenAIResponsesClient(transport: transport)
        self.claudeCodeClient = ClaudeCodeClient(runner: claudeCodeRunner)
    }

    public func summarizeMergeRequests(
        in matches: [GitLabReferenceMatch],
        settings: AISummarySettings
    ) async throws -> [GitLabReferenceMatch] {
        guard settings.enabled else { return matches }

        let candidates = Self.candidateMatches(from: matches)
        guard candidates.isEmpty == false else { return matches }

        let output = try await self.createSummaryResponse(for: candidates, settings: settings)
        let summaries = try Self.parseSummaries(from: output)
        guard summaries.isEmpty == false else { return matches }

        return matches.map { match in
            guard let summary = summaries[match.url] else { return match }

            return match.withAISummary(summary)
        }
    }

    private func createSummaryResponse(
        for candidates: [GitLabReferenceMatch],
        settings: AISummarySettings
    ) async throws -> String {
        switch settings.provider {
        case .openAIResponses:
            try await self.createOpenAISummaryResponse(for: candidates, settings: settings)
        case .claudeCode:
            try await self.claudeCodeClient.createTextResponse(
                model: AISummarySettings.normalizedModel(settings.model, provider: .claudeCode),
                instructions: Self.instructions,
                input: Self.makeInputText(for: candidates),
                jsonSchema: Self.summaryJSONSchema
            )
        }
    }

    private func createOpenAISummaryResponse(
        for candidates: [GitLabReferenceMatch],
        settings: AISummarySettings
    ) async throws -> String {
        guard let apiKey = self.apiKeyStore.resolve().key else {
            throw PullRequestAISummarizerError.missingAPIKey
        }

        return try await self.openAIClient.createTextResponse(
            endpoint: settings.resolvedRequestURL,
            apiKey: apiKey,
            model: AISummarySettings.normalizedModel(settings.model, provider: .openAIResponses),
            instructions: Self.instructions,
            input: Self.makeInputText(for: candidates),
            maxOutputTokens: 900
        )
    }

    public static func candidateMatches(
        from matches: [GitLabReferenceMatch],
        limit: Int = Self.maximumBatchSize
    ) -> [GitLabReferenceMatch] {
        Array(
            matches.lazy
                .filter { $0.kind == .pullRequest && $0.aiSummary == nil }
                .prefix(limit)
        )
    }

    static func makeInputText(for matches: [GitLabReferenceMatch]) throws -> String {
        let payload = AISummaryPromptPayload(
            items: matches.map(AISummaryPromptItem.init(match:))
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        let json = String(data: data, encoding: .utf8) ?? "{\"items\":[]}"

        return """
        Summarize these GitLab merge requests for the RepoPeek Issue Navigator sidebar.

        Input JSON:
        \(json)
        """
    }

    static func parseSummaries(from text: String) throws -> [URL: String] {
        let data = try Self.jsonObjectData(from: text)
        let decoder = JSONDecoder()

        if let envelope = try? decoder.decode(AISummaryResponseEnvelope.self, from: data) {
            return Self.summaryMap(from: envelope.summaries)
        }
        if let entries = try? decoder.decode([AISummaryResponseEntry].self, from: data) {
            return Self.summaryMap(from: entries)
        }
        if let dictionary = try? decoder.decode([String: String].self, from: data) {
            return dictionary.reduce(into: [URL: String]()) { result, pair in
                guard let url = URL(string: pair.key),
                      let summary = pair.value.trimmedNilIfEmpty
                else { return }

                result[url] = summary
            }
        }

        throw PullRequestAISummarizerError.invalidSummaryJSON
    }

    static let summaryJSONSchema = """
    {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "summaries": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "url": {
                "type": "string"
              },
              "summary": {
                "type": "string"
              }
            },
            "required": [
              "url",
              "summary"
            ]
          }
        }
      },
      "required": [
        "summaries"
      ]
    }
    """

    private static func jsonObjectData(from text: String) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil
        {
            return data
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end
        else {
            throw PullRequestAISummarizerError.invalidSummaryJSON
        }

        let json = String(trimmed[start ... end])
        guard let data = json.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else {
            throw PullRequestAISummarizerError.invalidSummaryJSON
        }

        return data
    }

    private static func summaryMap(from entries: [AISummaryResponseEntry]) -> [URL: String] {
        entries.reduce(into: [URL: String]()) { result, entry in
            guard let url = URL(string: entry.url),
                  let summary = entry.summary.trimmedNilIfEmpty
            else { return }

            result[url] = summary
        }
    }
}

public typealias OpenAIResponsesTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
public typealias ClaudeCodeProcessRunner = @Sendable ([String]) async throws -> ClaudeCodeProcessResult

public struct ClaudeCodeProcessResult: Equatable, Sendable {
    public let statusCode: Int32
    public let stdout: String
    public let stderr: String

    public init(statusCode: Int32, stdout: String, stderr: String) {
        self.statusCode = statusCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

private struct OpenAIResponsesClient {
    static let defaultEndpoint = AISummarySettings.defaultOpenAIResponsesEndpoint

    private let endpoint: URL
    private let transport: OpenAIResponsesTransport

    init(
        endpoint: URL = Self.defaultEndpoint,
        transport: @escaping OpenAIResponsesTransport
    ) {
        self.endpoint = endpoint
        self.transport = transport
    }

    func createTextResponse(
        endpoint: URL? = nil,
        apiKey: String,
        model: String,
        instructions: String,
        input: String,
        maxOutputTokens: Int
    ) async throws -> String {
        var request = URLRequest(url: endpoint ?? self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            OpenAIResponsesCreateRequest(
                model: model,
                instructions: instructions,
                input: input,
                maxOutputTokens: maxOutputTokens,
                store: false
            )
        )

        let (data, response) = try await self.transport(request)
        if let httpResponse = response as? HTTPURLResponse,
           (200 ..< 300).contains(httpResponse.statusCode) == false
        {
            throw PullRequestAISummarizerError.invalidHTTPResponse(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponsesCreateResponse.self, from: data)
        guard let output = decoded.textOutput else {
            throw PullRequestAISummarizerError.missingTextOutput
        }

        return output
    }
}

private struct ClaudeCodeClient {
    static let defaultRunner: ClaudeCodeProcessRunner = { arguments in
        let process = Process()
        let executable = Self.resolvedExecutable()
        process.executableURL = executable.url
        process.arguments = executable.prefixArguments + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw PullRequestAISummarizerError.claudeCodeUnavailable(error.localizedDescription)
        }

        process.waitUntilExit()
        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ClaudeCodeProcessResult(
            statusCode: process.terminationStatus,
            stdout: stdoutText,
            stderr: stderrText
        )
    }

    private let runner: ClaudeCodeProcessRunner

    init(runner: @escaping ClaudeCodeProcessRunner) {
        self.runner = runner
    }

    func createTextResponse(
        model: String,
        instructions: String,
        input: String,
        jsonSchema: String
    ) async throws -> String {
        let result = try await self.runner([
            "-p",
            input,
            "--system-prompt",
            instructions,
            "--model",
            model,
            "--output-format",
            "json",
            "--json-schema",
            jsonSchema,
            "--max-turns",
            "1",
            "--tools",
            "",
            "--no-session-persistence"
        ])

        guard result.statusCode == 0 else {
            let message = result.stderr.trimmedNilIfEmpty ?? result.stdout.trimmedNilIfEmpty ?? "No output"
            throw PullRequestAISummarizerError.claudeCodeFailed(result.statusCode, message)
        }

        return try Self.extractTextOutput(from: result.stdout)
    }

    private static func extractTextOutput(from stdout: String) throws -> String {
        guard let data = stdout.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ClaudeCodeJSONOutput.self, from: data)
        else {
            return stdout
        }

        if let structuredOutput = decoded.structuredOutput {
            let data = try JSONEncoder().encode(structuredOutput)
            return String(data: data, encoding: .utf8) ?? stdout
        }

        if let result = decoded.result?.trimmedNilIfEmpty {
            return result
        }

        throw PullRequestAISummarizerError.missingTextOutput
    }

    private static func resolvedExecutable() -> (url: URL, prefixArguments: [String]) {
        let fileManager = FileManager.default
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let fallbackDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(fileManager.homeDirectoryForCurrentUser.path)/.local/bin"
        ]

        for directory in pathDirectories + fallbackDirectories {
            let path = URL(fileURLWithPath: directory).appendingPathComponent("claude").path
            guard fileManager.isExecutableFile(atPath: path) else { continue }

            return (URL(fileURLWithPath: path), [])
        }

        return (URL(fileURLWithPath: "/usr/bin/env"), ["claude"])
    }
}

private struct OpenAIResponsesCreateRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let maxOutputTokens: Int
    let store: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case maxOutputTokens = "max_output_tokens"
        case store
    }
}

private struct OpenAIResponsesCreateResponse: Decodable {
    let outputText: String?
    let output: [OpenAIResponsesOutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    var textOutput: String? {
        if let outputText = self.outputText?.trimmedNilIfEmpty {
            return outputText
        }

        let text = self.output?
            .flatMap { $0.content ?? [] }
            .compactMap { $0.text?.trimmedNilIfEmpty }
            .joined(separator: "\n")
        return text?.trimmedNilIfEmpty
    }
}

private struct OpenAIResponsesOutputItem: Decodable {
    let content: [OpenAIResponsesOutputContent]?
}

private struct OpenAIResponsesOutputContent: Decodable {
    let text: String?
}

private struct AISummaryPromptPayload: Encodable {
    let items: [AISummaryPromptItem]
}

private struct AISummaryPromptItem: Encodable {
    let url: String
    let repository: String
    let title: String
    let state: String?
    let author: String?
    let updatedAt: String
    let description: String?

    init(match: GitLabReferenceMatch) {
        self.url = match.url.absoluteString
        self.repository = match.repositoryFullName
        self.title = match.title
        self.state = match.state?.rawValue
        self.author = match.authorLogin
        self.updatedAt = ISO8601DateFormatter().string(from: match.updatedAt)
        self.description = match.bodyPreview?.truncatedForAISummary.trimmedNilIfEmpty
    }
}

private struct AISummaryResponseEnvelope: Codable {
    let summaries: [AISummaryResponseEntry]
}

private struct AISummaryResponseEntry: Codable {
    let url: String
    let summary: String
}

private struct ClaudeCodeJSONOutput: Decodable {
    let result: String?
    let structuredOutput: AISummaryResponseEnvelope?

    enum CodingKeys: String, CodingKey {
        case result
        case structuredOutput = "structured_output"
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var truncatedForAISummary: String {
        guard self.count > 1200 else { return self }

        let index = self.index(self.startIndex, offsetBy: 1200)
        return String(self[..<index])
    }
}
