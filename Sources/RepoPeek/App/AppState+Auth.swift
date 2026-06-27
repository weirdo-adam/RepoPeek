import Foundation
import RepoPeekCore

extension AppState {
    /// GitLab authentication is PAT-only.
    func quickLogin() async {
        self.session.account = .loggedOut
        self.session.settings.authMethod = .pat
        self.persistSettings()
        self.session.lastError = "Sign in with a GitLab personal access token."
    }

    /// Authenticates with a Personal Access Token.
    func loginWithPAT(_ pat: String, host: URL) async {
        self.session.account = .loggingIn
        self.session.lastError = nil

        do {
            _ = try await self.authenticateGitLabAccount(name: nil, host: host, pat: pat)
            self.session.settings.authMethod = .pat
        } catch {
            self.session.account = .loggedOut
            self.session.settings.authMethod = .pat
            self.persistSettings()
            self.session.lastError = error.localizedDescription
        }
    }

    /// Logs out the current user, clearing tokens based on the current auth method.
    func logoutCurrentMethod() async {
        for account in self.session.settings.gitlabAccounts {
            await self.patAuth.logout(account: account, clearHostFallback: true)
        }
        self.session.account = .loggedOut
        self.session.accountUsers = [:]
        self.session.accountErrors = [:]
        self.session.hasStoredTokens = false
        self.session.accessibleRepositories = []
        self.session.repositories = []
        self.session.menuSnapshot = nil
        self.session.menuDisplayIndex = [:]
        self.session.hasLoadedRepositories = false
        self.menuSnapshotStore.clear()
        self.session.settings.authMethod = .pat
        self.persistSettings()
    }
}
