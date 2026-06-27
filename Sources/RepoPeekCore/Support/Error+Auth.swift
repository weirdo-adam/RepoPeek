import Foundation

public extension Error {
    var isAuthenticationFailure: Bool {
        if let gl = self as? GitLabAPIError {
            return gl.isAuthenticationFailure
        }
        if let urlError = self as? URLError, urlError.code == .userAuthenticationRequired {
            return true
        }
        return false
    }
}
