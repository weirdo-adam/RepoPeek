import Foundation

public enum GitLabAPIError: Error {
    case badStatus(code: Int, message: String?)
    case invalidHost

    public var displayMessage: String {
        switch self {
        case let .badStatus(code, message):
            message ?? "GitLab returned \(code)."
        case .invalidHost:
            "GitLab host must use HTTPS and a trusted certificate."
        }
    }

    public var isAuthenticationFailure: Bool {
        switch self {
        case let .badStatus(code, _):
            code == 401 || code == 403
        case .invalidHost:
            false
        }
    }
}

extension GitLabAPIError: LocalizedError {
    public var errorDescription: String? {
        self.displayMessage
    }
}
