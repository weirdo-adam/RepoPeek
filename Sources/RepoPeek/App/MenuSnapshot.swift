import Foundation
import RepoPeekCore

struct MenuSnapshot: Codable, Equatable {
    let repositories: [Repository]
    let capturedAt: Date

    func isStale(now: Date, interval: TimeInterval) -> Bool {
        now.timeIntervalSince(self.capturedAt) >= interval
    }
}
