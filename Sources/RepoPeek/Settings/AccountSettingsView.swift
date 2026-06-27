import Foundation
import RepoPeekCore
import SwiftUI

struct AccountSettingsView: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var accountName = ""
    @State private var hostInput = "https://gitlab.com"
    @State private var patInput = ""
    @State private var isValidatingPAT = false
    @State private var validationError: String?
    @State private var tokenValidation: [String: TokenValidationState] = [:]
    private let fieldMinWidth: CGFloat = 260
    private let spinnerSize: CGFloat = 14
    private let tokenCheckTimeout: TimeInterval = 8

    var body: some View {
        Form {
            Section {
                if self.session.settings.gitlabAccounts.isEmpty {
                    Text(self.t("No GitLab accounts configured."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(self.session.settings.gitlabAccounts) { account in
                        self.accountRow(account)
                    }
                }
            } header: {
                Text(self.t("GitLab Accounts"))
            } footer: {
                Text(self.t("Each GitLab account uses its own Personal Access Token. Enabled accounts are refreshed together."))
            }

            Section {
                GitLabAccountFormView(
                    accountName: self.$accountName,
                    hostInput: self.$hostInput,
                    patInput: self.$patInput,
                    isValidatingPAT: self.isValidatingPAT,
                    fieldMinWidth: self.fieldMinWidth,
                    spinnerSize: self.spinnerSize,
                    createTokenURL: self.createTokenURL(),
                    localize: { self.t($0) },
                    submit: self.loginWithPAT
                )
            } header: {
                Text(self.t("Add or Update Account"))
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let lastError = self.session.lastError, validationError == nil {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .task(id: self.session.settings.gitlabAccounts) {
            await self.validateStoredTokens()
        }
    }

    private func accountRow(_ account: GitLabAccountSettings) -> some View {
        let key = account.accountID
        return GitLabAccountRowView(
            account: account,
            username: self.session.accountUsers[key]?.username ?? account.username,
            statusText: self.tokenStatusText(for: account),
            statusColor: self.tokenStatusColor(for: account),
            isChecking: self.tokenValidation[key] == .checking,
            spinnerSize: self.spinnerSize,
            localize: { self.t($0) },
            setEnabled: { self.appState.setGitLabAccountEnabled(account, enabled: $0) },
            remove: { Task { await self.appState.removeGitLabAccount(account) } },
            checkToken: { Task { await self.validateToken(account) } }
        )
    }

    private func loginWithPAT() {
        Task { @MainActor in
            self.isValidatingPAT = true
            self.validationError = nil

            guard let host = self.normalizedHost() else {
                self.validationError = self.t("Base URL must be a valid https:// URL with a trusted certificate.")
                self.isValidatingPAT = false
                return
            }

            do {
                _ = try await self.appState.authenticateGitLabAccount(
                    name: self.accountName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    host: host,
                    pat: self.patInput
                )
                self.accountName = ""
                self.patInput = ""
                self.hostInput = "https://gitlab.com"
            } catch {
                self.validationError = error.localizedDescription
            }
            self.isValidatingPAT = false
        }
    }

    private func createTokenURL() -> URL {
        let baseHost = self.normalizedHost()?.absoluteString ?? "https://gitlab.com"
        return URL(string: "\(baseHost)/-/user_settings/personal_access_tokens?name=RepoPeek&scopes=api,read_user,read_repository")!
    }

    private func normalizedHost() -> URL? {
        guard self.hostInput.isEmpty == false else { return nil }
        guard var components = URLComponents(string: self.hostInput) else { return nil }

        if components.scheme == nil { components.scheme = "https" }
        guard components.scheme?.lowercased() == "https", components.host != nil else { return nil }

        components.query = nil
        components.fragment = nil
        if components.path == "/" {
            components.path = ""
        } else if components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }
        return components.url
    }

    private func validateStoredTokens() async {
        for account in self.session.settings.gitlabAccounts where account.enabled {
            await self.validateToken(account)
        }
    }

    private func validateToken(_ account: GitLabAccountSettings) async {
        let key = account.accountID
        if self.tokenValidation[key] == .checking { return }
        guard self.appState.patAuth.loadPAT(account: account) != nil else {
            self.tokenValidation[key] = .invalid(self.t("No token stored."))
            return
        }

        self.tokenValidation[key] = .checking
        let started = Date()
        let client = await self.appState.gitLabClient(for: account)
        await self.logAuth("Auth: token check started host=\(key)")
        do {
            let user = try await self.withTimeout(seconds: self.tokenCheckTimeout) {
                try await client.currentUser()
            }
            self.session.accountUsers[key] = user
            self.session.accountErrors[key] = nil
            self.session.lastError = nil
            self.tokenValidation[key] = .valid
            await self.logAuth("Auth: token check ok host=\(key) in \(Self.formatElapsed(since: started))")
        } catch {
            if error.isAuthenticationFailure {
                self.tokenValidation[key] = .invalid("Authentication required.")
                self.session.accountErrors[key] = "Authentication required."
                await self.logAuth("Auth: token check auth failure host=\(key) in \(Self.formatElapsed(since: started))")
                return
            }
            self.tokenValidation[key] = .invalid(error.userFacingMessage)
            self.session.accountErrors[key] = error.userFacingMessage
            await self.logAuth("Auth: token check failed host=\(key) in \(Self.formatElapsed(since: started)): \(error.userFacingMessage)")
        }
    }

    private func tokenStatusText(for account: GitLabAccountSettings) -> String {
        if let error = self.session.accountErrors[account.accountID] {
            return String(format: self.t("Token invalid: %@"), error)
        }
        switch self.tokenValidation[account.accountID] ?? .unknown {
        case .unknown:
            return self.appState.patAuth.loadPAT(account: account) == nil
                ? self.t("No token stored.")
                : self.t("Token status not checked yet.")
        case .checking:
            return self.t("Checking token...")
        case .valid:
            return self.t("Token is valid.")
        case let .invalid(message):
            return String(format: self.t("Token invalid: %@"), message)
        }
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }

    private func tokenStatusColor(for account: GitLabAccountSettings) -> Color {
        if self.session.accountErrors[account.accountID] != nil {
            return .red
        }
        switch self.tokenValidation[account.accountID] {
        case .valid:
            return .green
        case .invalid:
            return .red
        default:
            return .secondary
        }
    }

    private func logAuth(_ message: String) async {
        await DiagnosticsLogger.shared.message(message)
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func formatElapsed(since start: Date) -> String {
        let elapsed = Date().timeIntervalSince(start)
        return String(format: "%.2fs", elapsed)
    }
}

private enum TokenValidationState: Equatable {
    case unknown
    case checking
    case valid
    case invalid(String)
}

private extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
