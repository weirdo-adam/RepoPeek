import Foundation
import RepoPeekCore

@MainActor
final class GitLabClientRegistry {
    let primaryClient: GitLabClient

    private var clientsByAccountID: [String: GitLabClient] = [:]
    private let tokenStore: TokenStore

    init(primaryClient: GitLabClient, tokenStore: TokenStore = .shared) {
        self.primaryClient = primaryClient
        self.tokenStore = tokenStore
    }

    func client(
        for account: GitLabAccountSettings
    ) async -> GitLabClient {
        let normalized = account.normalized()
        let key = normalized.accountID
        let client = self.cachedClient(for: key)
        let host = normalized.host
        let accountID = normalized.accountID
        let tokenStore = self.tokenStore

        try? await client.setWebHost(host)
        await client.setTokenProvider { @Sendable () async throws -> String? in
            (try? tokenStore.loadPAT(accountID: accountID))
                ?? (try? tokenStore.loadPAT(forHost: host))
        }
        return client
    }

    func removeClient(accountID: String) {
        self.clientsByAccountID[accountID] = nil
    }

    private func cachedClient(for accountID: String) -> GitLabClient {
        if let cached = self.clientsByAccountID[accountID] {
            return cached
        }

        let client = GitLabClient(cacheAccountID: accountID)
        self.clientsByAccountID[accountID] = client
        return client
    }
}
