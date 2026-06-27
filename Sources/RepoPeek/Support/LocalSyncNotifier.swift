import Foundation
import RepoPeekCore

actor LocalSyncNotifier {
    static let shared = LocalSyncNotifier()

    func notifySync(for status: LocalRepoStatus) async {
        await RepoPeekNotifier.shared.notify(RepoPeekNotification(
            identifier: UUID().uuidString,
            body: "Synced \(status.displayName) (\(status.branch))"
        ))
    }
}
