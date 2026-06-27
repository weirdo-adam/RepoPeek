import Foundation
@testable import RepoPeekCore
import Testing

struct TokenStoreTests {
    @Test
    func `debug default storage does not use keychain`() throws {
        let service = "com.weirdoadam.repopeek.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service, accessGroup: "com.weirdoadam.repopeek.shared")
        defer { store.clear() }

        let token = "token-\(UUID().uuidString)"

        try store.savePAT(token)
        let loaded = try store.loadPAT()
        #expect(loaded == token)
    }

    @Test
    func `file storage does not use keychain`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repopeek-token-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = "com.weirdoadam.repopeek.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service, storage: .file(directory))
        let token = "debug-token"

        try store.savePAT(token)
        #expect(try store.loadPAT() == token)

        store.clear()
        #expect(try store.loadPAT() == nil)
    }
}
