import Foundation

public struct GitLabAccountSettings: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var host: URL
    public var username: String?
    public var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case username
        case enabled
    }

    public init(
        id: String = UUID().uuidString,
        name: String? = nil,
        host: URL,
        username: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.host = Self.normalizedHost(host) ?? host
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = trimmedName.isEmpty ? Self.defaultName(for: self.host) : trimmedName
        self.username = username
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        let host = try container.decode(URL.self, forKey: .host)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let username = try container.decodeIfPresent(String.self, forKey: .username)
        let enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.init(id: id, name: name, host: host, username: username, enabled: enabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.host, forKey: .host)
        try container.encodeIfPresent(self.username, forKey: .username)
        try container.encode(self.enabled, forKey: .enabled)
    }

    public static func gitLabCom() -> GitLabAccountSettings {
        let host = URL(string: "https://gitlab.com")!
        return GitLabAccountSettings(id: Self.hostKey(for: host), host: host)
    }

    public var hostKey: String {
        Self.hostKey(for: self.host)
    }

    public var accountID: String {
        Self.accountID(hostKey: self.hostKey, username: self.username)
    }

    public func normalized() -> GitLabAccountSettings {
        GitLabAccountSettings(
            id: self.id,
            name: self.name,
            host: self.host,
            username: self.username,
            enabled: self.enabled
        )
    }

    public static func normalizedHost(_ host: URL) -> URL? {
        guard host.scheme?.lowercased() == "https", host.host != nil else { return nil }

        var components = URLComponents(url: host, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        if components?.path == "/" {
            components?.path = ""
        } else if let path = components?.path, path.hasSuffix("/") {
            components?.path = String(path.dropLast())
        }
        return components?.url
    }

    public static func hostKey(for host: URL) -> String {
        let normalized = Self.normalizedHost(host) ?? host
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

    public static func accountID(host: URL, username: String?) -> String {
        self.accountID(hostKey: self.hostKey(for: host), username: username)
    }

    public static func accountID(hostKey: String, username: String?) -> String {
        guard let username = self.normalizedUsername(username) else { return hostKey }

        return "\(hostKey)#\(username)"
    }

    public static func normalizedUsername(_ username: String?) -> String? {
        let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return nil }

        return trimmed.lowercased()
    }

    public static func defaultName(for host: URL) -> String {
        let normalized = Self.normalizedHost(host) ?? host
        return normalized.host?.lowercased() ?? normalized.absoluteString
    }
}
