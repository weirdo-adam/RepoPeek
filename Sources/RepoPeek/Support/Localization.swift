import Foundation
import RepoPeekCore

enum L10n {
    static func t(_ key: String, settings: UserSettings) -> String {
        self.t(key, language: settings.language)
    }

    static func t(_ key: String, language: AppLanguage) -> String {
        let resolved = self.resolvedLanguage(language)
        switch resolved {
        case .simplifiedChinese:
            return L10nSimplifiedChinese.strings[key] ?? L10nEnglish.strings[key] ?? key
        case .system, .english:
            return L10nEnglish.strings[key] ?? key
        }
    }

    static func format(_ key: String, settings: UserSettings, _ arguments: CVarArg...) -> String {
        self.format(key, language: settings.language, arguments)
    }

    static func format(_ key: String, settings: UserSettings, _ arguments: [CVarArg]) -> String {
        self.format(key, language: settings.language, arguments)
    }

    static func format(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        self.format(key, language: language, arguments)
    }

    static func format(_ key: String, language: AppLanguage, _ arguments: [CVarArg]) -> String {
        let template = self.t(key, language: language)
        let locale = Locale(identifier: self.localeIdentifier(for: language))
        return String(format: template, locale: locale, arguments: arguments)
    }

    static func label(for language: AppLanguage, settings: UserSettings) -> String {
        switch language {
        case .system:
            self.t("System", settings: settings)
        case .english:
            "English"
        case .simplifiedChinese:
            "简体中文"
        }
    }

    static func localeIdentifier(for language: AppLanguage) -> String {
        self.resolvedLanguage(language).localeIdentifier ?? "en"
    }

    private static func resolvedLanguage(_ language: AppLanguage) -> AppLanguage {
        guard language == .system else { return language }

        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}
