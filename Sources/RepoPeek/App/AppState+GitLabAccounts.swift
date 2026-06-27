import Foundation
import RepoPeekCore

extension AppState {
    func enabledGitLabAccounts() -> [GitLabAccountSettings] {
        self.session.settings.gitlabAccounts.map { $0.normalized() }.filter(\.enabled)
    }

    func gitLabClient(for account: GitLabAccountSettings) async -> GitLabClient {
        await self.gitLabClientRegistry.client(for: account)
    }

    func gitLabClient(forHostKey hostKey: String?) async -> GitLabClient {
        let accounts = self.enabledGitLabAccounts()
        if let hostKey {
            if let account = accounts.first(where: { $0.accountID == hostKey || $0.hostKey == hostKey }) {
                return await self.gitLabClient(for: account)
            }
        }
        if let account = self.primaryGitLabAccount() {
            return await self.gitLabClient(for: account)
        }
        return self.gitlab
    }

    func gitLabClient(for repo: Repository) async -> GitLabClient {
        await self.gitLabClient(forHostKey: repo.identity?.accountID ?? repo.identity?.host)
    }

    func gitLabClient(forRepositoryFullName fullName: String) async -> GitLabClient {
        let normalized = fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let repositories = self.session.repositories + self.session.accessibleRepositories
        let repo = repositories.first {
            $0.lookupKey == normalized || $0.id.lowercased() == normalized
        } ?? repositories.first {
            $0.fullName.lowercased() == normalized
        }
        return await self.gitLabClient(forHostKey: repo?.identity?.accountID ?? repo?.identity?.host)
    }

    func hostURL(forHostKey hostKey: String?) -> URL? {
        guard let hostKey else { return nil }

        return self.session.settings.gitlabAccounts.first { $0.accountID == hostKey || $0.hostKey == hostKey }?.host
    }

    func hasAnyStoredPAT() -> Bool {
        self.enabledGitLabAccounts().contains { account in
            self.patAuth.loadPAT(account: account) != nil
        }
    }

    func primaryGitLabAccount() -> GitLabAccountSettings? {
        self.enabledGitLabAccounts().first
    }

    func authenticateGitLabAccount(name: String?, host: URL, pat: String) async throws -> UserIdentity {
        let normalizedHost = try GitLabClient.normalizedWebHost(for: host)
        let user = try await self.patAuth.authenticate(pat: pat, host: normalizedHost)
        var account = GitLabAccountSettings(
            name: name,
            host: normalizedHost,
            username: user.username,
            enabled: true
        )
        account.id = account.accountID
        if let existing = self.session.settings.gitlabAccounts.first(where: { $0.accountID == account.accountID }) {
            account.id = existing.id
            if account.name.isEmpty {
                account.name = existing.name
            }
        }

        self.upsertGitLabAccount(account)
        self.session.accountUsers[account.accountID] = user
        self.session.accountErrors[account.accountID] = nil
        self.session.hasStoredTokens = self.hasAnyStoredPAT()
        if self.session.account.isLoggedIn == false {
            self.session.account = .loggedIn(user)
        }
        self.persistSettings()
        _ = await self.gitLabClient(for: account)
        await self.refresh()
        return user
    }

    func removeGitLabAccount(_ account: GitLabAccountSettings) async {
        let key = account.accountID
        let remainingAccountsOnHost = self.session.settings.gitlabAccounts.filter {
            $0.accountID != key && $0.hostKey == account.hostKey
        }
        await self.patAuth.logout(account: account, clearHostFallback: remainingAccountsOnHost.isEmpty)
        self.session.settings.gitlabAccounts.removeAll { $0.accountID == key }
        self.session.accountUsers[key] = nil
        self.session.accountErrors[key] = nil
        self.gitLabClientRegistry.removeClient(accountID: key)
        self.session.settings.gitlabHost = self.session.settings.gitlabAccounts.first?.host ?? RepoPeekAuthDefaults.gitlabHost
        self.persistSettings()
        self.session.hasStoredTokens = self.hasAnyStoredPAT()
        if self.session.hasStoredTokens == false {
            self.menuSnapshotStore.clear()
        }
        await self.refresh()
    }

    func setGitLabAccountEnabled(_ account: GitLabAccountSettings, enabled: Bool) {
        let key = account.accountID
        for index in self.session.settings.gitlabAccounts.indices {
            guard self.session.settings.gitlabAccounts[index].accountID == key else { continue }

            self.session.settings.gitlabAccounts[index].enabled = enabled
        }
        self.persistSettings()
        self.requestRefresh(cancelInFlight: true)
    }

    func recentRepositories(limit: Int?) async throws -> [Repository] {
        let accounts = self.enabledGitLabAccountsWithTokens()
        guard accounts.isEmpty == false else { throw URLError(.userAuthenticationRequired) }

        let perAccountLimit = limit
        return try await self.fetchRepositories(accounts: accounts) { client, account in
            let repos = try await client.recentRepositories(limit: perAccountLimit ?? AppLimits.Autocomplete.addRepoRecentLimit)
            return repos.map { self.repository($0, applyingHostFrom: account) }
        }
    }

    func searchRepositories(matching query: String) async throws -> [Repository] {
        let accounts = self.enabledGitLabAccountsWithTokens()
        guard accounts.isEmpty == false else { throw URLError(.userAuthenticationRequired) }

        return try await self.fetchRepositories(accounts: accounts) { client, account in
            let repos = try await client.searchRepositories(matching: query)
            return repos.map { self.repository($0, applyingHostFrom: account) }
        }
    }

    func enabledGitLabAccountsWithTokens() -> [GitLabAccountSettings] {
        self.enabledGitLabAccounts().filter { self.patAuth.loadPAT(account: $0) != nil }
    }

    private func upsertGitLabAccount(_ account: GitLabAccountSettings) {
        let normalized = account.normalized()
        if let index = self.session.settings.gitlabAccounts.firstIndex(where: { $0.accountID == normalized.accountID }) {
            self.session.settings.gitlabAccounts[index] = normalized
        } else {
            self.session.settings.gitlabAccounts.append(normalized)
        }
        self.session.settings.gitlabHost = self.session.settings.gitlabAccounts.first?.host ?? RepoPeekAuthDefaults.gitlabHost
    }

    private func fetchRepositories(
        accounts: [GitLabAccountSettings],
        operation: @escaping (GitLabClient, GitLabAccountSettings) async throws -> [Repository]
    ) async throws -> [Repository] {
        var repositories: [Repository] = []
        var firstError: Error?

        for account in accounts {
            let client = await self.gitLabClient(for: account)
            do {
                try await repositories.append(contentsOf: operation(client, account))
                self.session.accountErrors[account.accountID] = nil
            } catch {
                firstError = firstError ?? error
                self.session.accountErrors[account.accountID] = error.userFacingMessage
            }
        }

        if repositories.isEmpty, let firstError {
            throw firstError
        }
        return repositories
    }

    func repository(_ repository: Repository, applyingHostFrom account: GitLabAccountSettings) -> Repository {
        guard let identity = repository.identity,
              identity.host != account.hostKey || identity.accountID != account.accountID else { return repository }

        return repository.withIdentity(RepositoryIdentity(
            host: account.hostKey,
            projectPath: identity.projectPath,
            accountID: account.accountID
        ))
    }
}
