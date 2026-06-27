import Foundation

public enum AppLanguage: String, CaseIterable, Equatable, Codable, Sendable {
    case system
    case english
    case simplifiedChinese

    public var localeIdentifier: String? {
        switch self {
        case .system:
            nil
        case .english:
            "en"
        case .simplifiedChinese:
            "zh-Hans"
        }
    }
}
