import Foundation

/// Persists simple user settings in UserDefaults.
public struct SettingsStore {
    private let defaults: UserDefaults
    static let storageKey = "com.weirdoadam.repopeek.settings"
    private let key = Self.storageKey
    private static let currentVersion = 4

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> UserSettings {
        guard let data = defaults.data(forKey: key) else {
            return UserSettings()
        }

        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(SettingsEnvelope.self, from: data) {
            var settings = envelope.settings
            if envelope.version < Self.currentVersion {
                Self.applyMigrations(to: &settings, fromVersion: envelope.version)
                self.save(settings)
            }
            return settings
        }
        return UserSettings()
    }

    public func save(_ settings: UserSettings) {
        let envelope = SettingsEnvelope(version: Self.currentVersion, settings: settings)
        if let data = try? JSONEncoder().encode(envelope) {
            self.defaults.set(data, forKey: self.key)
        }
    }

    private static func applyMigrations(to settings: inout UserSettings, fromVersion: Int) {
        guard fromVersion < self.currentVersion else { return }

        if fromVersion < 4, settings.refreshInterval == .thirtyMinutes {
            settings.refreshInterval = .sixHours
        }
    }
}

private struct SettingsEnvelope: Codable {
    let version: Int
    let settings: UserSettings
}
