import Foundation
@testable import RepoPeek
import RepoPeekCore
import Testing

struct MenuSnapshotStoreTests {
    @Test
    func `snapshot store round trips and clears repository snapshot`() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuSnapshotStoreTests.\(UUID().uuidString)", isDirectory: true)
        let store = MenuSnapshotStore(baseURL: root)
        let snapshot = MenuSnapshot(
            repositories: [
                Repository(
                    id: "gitlab.com/example/repo",
                    identity: RepositoryIdentity(
                        host: "gitlab.com",
                        projectPath: "example/repo"
                    ),
                    name: "repo",
                    owner: "example",
                    sortOrder: nil,
                    error: nil,
                    rateLimitedUntil: nil,
                    ciStatus: .unknown,
                    openIssues: 1,
                    openPulls: 2,
                    pushedAt: Date(timeIntervalSinceReferenceDate: 123),
                    latestRelease: nil,
                    latestActivity: nil,
                    traffic: nil,
                    heatmap: []
                )
            ],
            capturedAt: Date(timeIntervalSinceReferenceDate: 456)
        )

        store.save(snapshot)
        #expect(store.load() == snapshot)

        store.clear()
        #expect(store.load() == nil)
        try? FileManager.default.removeItem(at: root)
    }
}
