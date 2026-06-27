import Foundation

public extension Error {
    var userFacingMessage: String {
        if let decodingError = self as? DecodingError {
            return decodingError.userFacingMessage
        }
        if let glError = self as? GitLabAPIError {
            return glError.displayMessage
        }
        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet: return "No internet connection."
            case .timedOut: return "Request timed out."
            case .cannotLoadFromNetwork: return "Rate limited; retry soon."
            case .cannotParseResponse: return "GitLab returned an unexpected response."
            case .userAuthenticationRequired: return "Authentication required. Please sign in again."
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid:
                return "Enterprise host certificate is not trusted."
            default: break
            }
        }
        return localizedDescription
    }
}

private extension DecodingError {
    var userFacingMessage: String {
        switch self {
        case let .keyNotFound(key, _):
            return "Response missing expected field '\(key.stringValue)'. Try again or update \(RepoPeekProductConstants.displayName)."
        case .valueNotFound:
            return "Response missing expected data. Try again or update \(RepoPeekProductConstants.displayName)."
        case .typeMismatch:
            return "Response had unexpected data. Try again or update \(RepoPeekProductConstants.displayName)."
        case .dataCorrupted:
            return "Response was malformed. Try again or update \(RepoPeekProductConstants.displayName)."
        @unknown default:
            return "Response could not be decoded. Try again or update \(RepoPeekProductConstants.displayName)."
        }
    }
}
