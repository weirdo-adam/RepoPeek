import Foundation
import Logging
import Security

public enum TokenStoreError: Error {
    case saveFailed
    case loadFailed
}

public enum TokenStoreStorage: Sendable {
    case keychain
    case file(URL)
}

public struct TokenStore: Sendable {
    public static var shared: TokenStore {
        TokenStore()
    }

    private let service: String
    private let accessGroup: String?
    private let storage: TokenStoreStorage
    private let logger = RepoPeekLogging.logger("token-store")

    public init(
        service: String = "com.weirdoadam.repopeek.auth",
        accessGroup: String? = nil,
        storage: TokenStoreStorage? = nil
    ) {
        self.service = service
        self.accessGroup = accessGroup ?? Self.defaultAccessGroup()
        self.storage = storage ?? Self.defaultStorage()
    }

    public func clear() {
        self.clear(account: "default")
        self.clear(account: "client")
        self.clearPAT()
    }

    public func clearAllCredentials() {
        self.clear()
        self.clearOpenAIAPIKey()
    }

    // MARK: - PAT Storage

    public func savePAT(_ token: String) throws {
        let data = Data(token.utf8)
        try self.save(data: data, account: "pat")
    }

    public func savePAT(_ token: String, forHost host: URL) throws {
        let data = Data(token.utf8)
        try self.save(data: data, account: Self.patAccount(forHost: host))
    }

    public func savePAT(_ token: String, accountID: String) throws {
        let data = Data(token.utf8)
        try self.save(data: data, account: Self.patAccount(accountID: accountID))
    }

    public func loadPAT() throws -> String? {
        guard let data = try self.loadData(account: "pat") else { return nil }

        return String(data: data, encoding: .utf8)
    }

    public func loadPAT(accountID: String) throws -> String? {
        guard let data = try self.loadData(account: Self.patAccount(accountID: accountID)) else { return nil }

        return String(data: data, encoding: .utf8)
    }

    public func loadPAT(forHost host: URL) throws -> String? {
        if let data = try self.loadData(account: Self.patAccount(forHost: host)) {
            return String(data: data, encoding: .utf8)
        }

        if Self.normalizedHostKey(for: host) == "gitlab.com" {
            return try self.loadPAT()
        }
        return nil
    }

    public func clearPAT() {
        self.clear(account: "pat")
    }

    public func clearPAT(forHost host: URL) {
        self.clear(account: Self.patAccount(forHost: host))
        if Self.normalizedHostKey(for: host) == "gitlab.com" {
            self.clearPAT()
        }
    }

    public func clearPAT(accountID: String) {
        self.clear(account: Self.patAccount(accountID: accountID))
    }

    // MARK: - OpenAI API Key Storage

    public func saveOpenAIAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            self.clearOpenAIAPIKey()
            return
        }

        try self.save(data: Data(trimmed.utf8), account: Self.openAIAPIKeyAccount)
    }

    public func loadOpenAIAPIKey() throws -> String? {
        guard let data = try self.loadData(account: Self.openAIAPIKeyAccount),
              let key = String(data: data, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              key.isEmpty == false
        else { return nil }

        return key
    }

    public func clearOpenAIAPIKey() {
        self.clear(account: Self.openAIAPIKeyAccount)
    }
}

extension TokenStore {
    static let sharedAccessGroupSuffix = "com.weirdoadam.repopeek.shared"
    private static let storageModeInfoKey = "RepoPeekTokenStore"
    private static let storageModeEnvKey = "REPOPEEK_TOKEN_STORE"
    private static let openAIAPIKeyAccount = "openai-api-key"

    static func defaultAccessGroup() -> String? {
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil),
                  let entitlement = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil)
            else {
                return nil
            }

            if let groups = entitlement as? [String] {
                return groups.first(where: { $0.hasSuffix(Self.sharedAccessGroupSuffix) })
            }
            return nil
        #else
            return nil
        #endif
    }

    static func defaultStorage() -> TokenStoreStorage {
        let configured = ProcessInfo.processInfo.environment[Self.storageModeEnvKey]
            ?? Bundle.main.object(forInfoDictionaryKey: Self.storageModeInfoKey) as? String
        switch configured?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "file", "disk":
            return .file(Self.defaultFileDirectory())
        case "keychain":
            return .keychain
        default:
            #if DEBUG
                return .file(Self.defaultFileDirectory())
            #else
                return .keychain
            #endif
        }
    }

    static func defaultFileDirectory() -> URL {
        let fallback = FileManager.default.homeDirectoryForCurrentUser
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fallback
        return base
            .appendingPathComponent(RepoPeekProductConstants.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("DebugAuth", isDirectory: true)
    }

    static func patAccount(forHost host: URL) -> String {
        "pat:\(self.normalizedHostKey(for: host))"
    }

    static func patAccount(accountID: String) -> String {
        "pat:\(self.normalizedAccountID(accountID))"
    }

    static func normalizedAccountID(_ accountID: String) -> String {
        let normalized = accountID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? "default" : normalized
    }

    static func normalizedHostKey(for host: URL) -> String {
        let normalized = GitLabAccountSettings.normalizedHost(host) ?? host
        guard let components = URLComponents(url: normalized, resolvingAgainstBaseURL: false) else {
            return normalized.absoluteString.lowercased()
        }

        var key = components.host?.lowercased() ?? normalized.absoluteString.lowercased()
        if let port = components.port {
            key += ":\(port)"
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        if path.isEmpty == false {
            key += "/\(path)"
        }
        return key
    }
}

private extension TokenStore {
    func save(data: Data, account: String) throws {
        if case let .file(directory) = self.storage {
            try self.saveFile(data: data, account: account, directory: directory)
            return
        }

        let accessGroups = self.accessGroupsForOperation()
        var lastStatus: OSStatus = errSecSuccess
        for (index, group) in accessGroups.enumerated() {
            let query = self.baseQuery(account: account, accessGroup: group)
            let attributes: [CFString: Any] = [kSecValueData: data]
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            var status = SecItemAdd(addQuery as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            }
            if status == errSecSuccess { return }
            lastStatus = status
            let isFinalAttempt = index == accessGroups.count - 1
            if isFinalAttempt || self.shouldRetryWithoutAccessGroup(status: status, accessGroup: group) == false {
                break
            }
        }
        self.logFailure("save", status: lastStatus)
        throw TokenStoreError.saveFailed
    }

    func loadData(account: String) throws -> Data? {
        if case let .file(directory) = self.storage {
            return try self.loadFile(account: account, directory: directory)
        }

        let accessGroups = self.accessGroupsForOperation()
        var lastStatus: OSStatus = errSecSuccess
        for (index, group) in accessGroups.enumerated() {
            var query = self.baseQuery(account: account, accessGroup: group)
            query[kSecReturnData] = true
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound {
                if index == accessGroups.count - 1 { return nil }
                continue
            }
            if status == errSecSuccess, let data = item as? Data { return data }
            lastStatus = status
            let isFinalAttempt = index == accessGroups.count - 1
            if isFinalAttempt || self.shouldRetryWithoutAccessGroup(status: status, accessGroup: group) == false {
                break
            }
        }
        self.logFailure("load", status: lastStatus)
        throw TokenStoreError.loadFailed
    }

    func clear(account: String) {
        if case let .file(directory) = self.storage {
            try? FileManager.default.removeItem(at: self.fileURL(account: account, directory: directory))
            return
        }

        let accessGroups = self.accessGroupsForOperation()
        for group in accessGroups {
            let query = self.baseQuery(account: account, accessGroup: group)
            SecItemDelete(query as CFDictionary)
        }
    }

    func accessGroupsForOperation() -> [String?] {
        guard let accessGroup else { return [nil] }

        return [accessGroup, nil]
    }

    func baseQuery(account: String, accessGroup: String?) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        return query
    }

    func shouldRetryWithoutAccessGroup(status: OSStatus, accessGroup: String?) -> Bool {
        guard accessGroup != nil else { return false }

        switch status {
        case errSecMissingEntitlement, errSecInteractionNotAllowed:
            return true
        default:
            return false
        }
    }

    func logFailure(_ action: String, status: OSStatus) {
        guard status != errSecSuccess else { return }

        let statusMessage = SecCopyErrorMessageString(status, nil) as String?
        if let statusMessage {
            self.logger.error("Keychain \(action) failed: \(statusMessage)")
        } else {
            self.logger.error("Keychain \(action) failed: OSStatus \(status)")
        }
    }

    func saveFile(data: Data, account: String, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = self.fileURL(account: account, directory: directory)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func loadFile(account: String, directory: URL) throws -> Data? {
        let url = self.fileURL(account: account, directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        return try Data(contentsOf: url)
    }

    func fileURL(account: String, directory: URL) -> URL {
        let serviceName = self.sanitizedFileComponent(self.service)
        let accountName = self.sanitizedFileComponent(account)
        return directory.appendingPathComponent("\(serviceName)-\(accountName).json", isDirectory: false)
    }

    func sanitizedFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let result = String(scalars)
        return result.isEmpty ? "value" : result
    }
}
