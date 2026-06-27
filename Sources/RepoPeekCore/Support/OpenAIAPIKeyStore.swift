import Foundation

public enum OpenAIAPIKeySource: Equatable, Sendable {
    case keychain
    case environment(String)
    case missing
}

public struct OpenAIAPIKeyResolution: Equatable, Sendable {
    public let key: String?
    public let source: OpenAIAPIKeySource

    public init(key: String?, source: OpenAIAPIKeySource) {
        self.key = key
        self.source = source
    }
}

public struct OpenAIAPIKeyStore: Sendable {
    public static let appEnvironmentVariable = "REPOPEEK_OPENAI_API_KEY"
    public static let standardEnvironmentVariable = "OPENAI_API_KEY"

    private let tokenStore: TokenStore
    private let environment: @Sendable (String) -> String?

    public init(
        tokenStore: TokenStore = .shared,
        environment: @escaping @Sendable (String) -> String? = OpenAIAPIKeyStore.processEnvironmentValue
    ) {
        self.tokenStore = tokenStore
        self.environment = environment
    }

    public func resolve() -> OpenAIAPIKeyResolution {
        if let stored = try? self.tokenStore.loadOpenAIAPIKey(), stored.isEmpty == false {
            return OpenAIAPIKeyResolution(key: stored, source: .keychain)
        }

        for name in [Self.appEnvironmentVariable, Self.standardEnvironmentVariable] {
            if let key = self.environment(name)?.trimmingCharacters(in: .whitespacesAndNewlines),
               key.isEmpty == false
            {
                return OpenAIAPIKeyResolution(key: key, source: .environment(name))
            }
        }

        return OpenAIAPIKeyResolution(key: nil, source: .missing)
    }

    public static func processEnvironmentValue(_ name: String) -> String? {
        ProcessInfo.processInfo.environment[name]
    }
}
