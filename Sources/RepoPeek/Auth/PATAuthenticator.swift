import Foundation
import OSLog
import RepoPeekCore

public enum PATAuthError: Error, LocalizedError {
    case invalidToken
    case forbidden(String)
    case networkError(Error)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidToken:
            "Invalid token"
        case let .forbidden(message):
            message
        case let .networkError(error):
            error.localizedDescription
        case .invalidResponse:
            "Invalid response from server"
        }
    }
}

/// Handles GitLab Personal Access Token authentication.
@MainActor
public final class PATAuthenticator {
    private let tokenStore: TokenStore
    private let signposter = OSSignposter(subsystem: "com.weirdoadam.repopeek", category: "pat-auth")
    private var cachedPAT: String?
    private var hasLoadedPAT = false
    private var cachedPATsByAccountID: [String: String?] = [:]
    private var cachedPATsByHost: [String: String?] = [:]
    private let session: URLSession

    public init(
        tokenStore: TokenStore = .shared,
        session: URLSession = .shared
    ) {
        self.tokenStore = tokenStore
        self.session = session
    }

    /// Validates PAT via GET /user, stores on success, returns UserIdentity.
    public func authenticate(pat: String, host: URL) async throws -> UserIdentity {
        let signpost = self.signposter.beginInterval("authenticate")
        defer { self.signposter.endInterval("authenticate", signpost) }

        let apiHost = Self.apiHost(for: host)
        let userURL = apiHost.appendingPathComponent("user")

        var request = URLRequest(url: userURL)
        request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await self.session.data(for: request)
        } catch {
            throw PATAuthError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PATAuthError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw PATAuthError.invalidToken
        case 403:
            throw PATAuthError.forbidden(
                "Access forbidden. Token may lack required scopes (api, read_user, read_repository)."
            )
        default:
            throw PATAuthError.invalidResponse
        }

        struct UserResponse: Decodable {
            let login: String?
            let username: String?
        }

        let user: UserResponse
        do {
            user = try JSONDecoder().decode(UserResponse.self, from: data)
        } catch {
            throw PATAuthError.invalidResponse
        }

        let username = user.username ?? user.login ?? ""
        let accountID = GitLabAccountSettings.accountID(host: host, username: username)
        try self.tokenStore.savePAT(pat, accountID: accountID)
        if (try? self.tokenStore.loadPAT(forHost: host)) == nil {
            try? self.tokenStore.savePAT(pat, forHost: host)
        }
        if GitLabAccountSettings.hostKey(for: host) == "gitlab.com" {
            try? self.tokenStore.savePAT(pat)
            self.cachedPAT = pat
            self.hasLoadedPAT = true
        }
        self.cachedPATsByAccountID[accountID] = pat
        self.cachedPATsByHost[GitLabAccountSettings.hostKey(for: host)] = pat
        await DiagnosticsLogger.shared.message("PAT login succeeded; token stored.")

        return UserIdentity(username: username, host: host)
    }

    /// Loads the stored PAT from Keychain.
    public func loadPAT() -> String? {
        if self.hasLoadedPAT { return self.cachedPAT }
        self.hasLoadedPAT = true
        let pat = try? self.tokenStore.loadPAT()
        self.cachedPAT = pat
        return pat
    }

    public func loadPAT(host: URL) -> String? {
        let key = GitLabAccountSettings.hostKey(for: host)
        if let cached = self.cachedPATsByHost[key] {
            return cached
        }

        let pat = try? self.tokenStore.loadPAT(forHost: host)
        self.cachedPATsByHost[key] = pat
        return pat
    }

    public func loadPAT(account: GitLabAccountSettings) -> String? {
        let accountID = account.accountID
        if let cached = self.cachedPATsByAccountID[accountID] {
            return cached
        }

        let pat = (try? self.tokenStore.loadPAT(accountID: accountID))
            ?? self.loadPAT(host: account.host)
        self.cachedPATsByAccountID[accountID] = pat
        return pat
    }

    /// Clears the stored PAT.
    public func logout() async {
        self.tokenStore.clearPAT()
        self.cachedPAT = nil
        self.hasLoadedPAT = false
        self.cachedPATsByAccountID.removeAll()
        self.cachedPATsByHost.removeAll()
        await DiagnosticsLogger.shared.message("PAT cleared.")
    }

    public func logout(host: URL) async {
        self.tokenStore.clearPAT(forHost: host)
        self.cachedPATsByHost[GitLabAccountSettings.hostKey(for: host)] = nil
        if GitLabAccountSettings.hostKey(for: host) == "gitlab.com" {
            self.cachedPAT = nil
            self.hasLoadedPAT = false
        }
        await DiagnosticsLogger.shared.message("PAT cleared for host \(GitLabAccountSettings.hostKey(for: host)).")
    }

    public func logout(account: GitLabAccountSettings, clearHostFallback: Bool) async {
        self.tokenStore.clearPAT(accountID: account.accountID)
        self.cachedPATsByAccountID[account.accountID] = nil
        if clearHostFallback {
            await self.logout(host: account.host)
        } else {
            await DiagnosticsLogger.shared.message("PAT cleared for account \(account.accountID).")
        }
    }

    /// Converts a GitLab host URL to its API endpoint.
    private static func apiHost(for host: URL) -> URL {
        (try? GitLabClient.apiHost(for: host)) ?? host.appendingPathComponent("api/v4")
    }
}
