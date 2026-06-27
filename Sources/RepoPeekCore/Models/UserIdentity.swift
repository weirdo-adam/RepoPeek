import Foundation

public struct UserIdentity: Equatable, Sendable {
    public let username: String
    public let host: URL

    public init(username: String, host: URL) {
        self.username = username
        self.host = host
    }
}
