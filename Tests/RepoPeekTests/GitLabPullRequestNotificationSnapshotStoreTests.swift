import Foundation
@testable import RepoPeekCore
import Testing

struct GitLabPullRequestNotificationSnapshotStoreTests {
    @Test
    func `snapshot store round trips and clears state`() throws {
        let suiteName = "GitLabPullRequestNotificationSnapshotStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = GitLabPullRequestNotificationSnapshotStore(defaults: defaults)
        let snapshot = GitLabPullRequestNotificationSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            commentCount: 2,
            reviewCommentCount: 1,
            requestedReviewerLogins: ["alice"],
            requestedTeamNames: ["ios"]
        )
        let state = GitLabPullRequestNotificationSnapshotState(
            repositories: ["example/repopeek": [57: snapshot]]
        )

        store.save(state)

        let loaded = store.load()
        #expect(loaded == state)

        store.clear()

        #expect(store.load() == GitLabPullRequestNotificationSnapshotState())
    }

    @Test
    func `snapshot store falls back to empty state for invalid data`() throws {
        let suiteName = "GitLabPullRequestNotificationSnapshotStoreTests.invalid.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(Data([0x00, 0x01]), forKey: GitLabPullRequestNotificationSnapshotStore.storageKey)
        let store = GitLabPullRequestNotificationSnapshotStore(defaults: defaults)

        #expect(store.load() == GitLabPullRequestNotificationSnapshotState())
    }
}
