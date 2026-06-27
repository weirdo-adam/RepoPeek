import Foundation

public struct GitLabPullRequestNotificationSnapshotStore {
    public static let storageKey = "com.weirdoadam.repopeek.gitlab-mr-notification-snapshots"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = Self.storageKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> GitLabPullRequestNotificationSnapshotState {
        guard let data = self.defaults.data(forKey: self.key) else {
            return GitLabPullRequestNotificationSnapshotState()
        }

        return (try? JSONDecoder().decode(GitLabPullRequestNotificationSnapshotState.self, from: data))
            ?? GitLabPullRequestNotificationSnapshotState()
    }

    public func save(_ state: GitLabPullRequestNotificationSnapshotState) {
        guard let data = try? JSONEncoder().encode(state) else { return }

        self.defaults.set(data, forKey: self.key)
    }

    public func clear() {
        self.defaults.removeObject(forKey: self.key)
    }
}
