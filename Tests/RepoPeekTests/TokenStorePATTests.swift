import Foundation
@testable import RepoPeekCore
import Testing

struct TokenStorePATTests {
    @Test
    func `save PAT and load`() throws {
        let service = "com.weirdoadam.repopeek.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let pat = "glpat-test123456789"
        try store.savePAT(pat)

        let loaded = try store.loadPAT()
        #expect(loaded == pat)
    }

    @Test
    func `clear removes PAT`() throws {
        let service = "com.weirdoadam.repopeek.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let pat = "glpat-test123456789"
        try store.savePAT(pat)

        store.clearPAT()

        let loaded = try store.loadPAT()
        #expect(loaded == nil)
    }

    @Test
    func `load PAT when none stored`() throws {
        let service = "com.weirdoadam.repopeek.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let loaded = try store.loadPAT()
        #expect(loaded == nil)
    }

    @Test
    func `clear also clears PAT`() throws {
        let service = "com.weirdoadam.repopeek.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let pat = "glpat-test123456789"
        try store.savePAT(pat)

        // clear() should also clear PAT
        store.clear()

        let loaded = try store.loadPAT()
        #expect(loaded == nil)
    }

    @Test
    func `save PAT overwrites previous`() throws {
        let service = "com.weirdoadam.repopeek.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        try store.savePAT("glpat-first")
        try store.savePAT("glpat-second")

        let loaded = try store.loadPAT()
        #expect(loaded == "glpat-second")
    }

    @Test
    func `save PAT per host`() throws {
        let service = "com.weirdoadam.repopeek.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)

        let gitlabCom = try #require(URL(string: "https://gitlab.com"))
        let selfManaged = try #require(URL(string: "https://code.company.com/gitlab"))
        defer {
            store.clearPAT(forHost: gitlabCom)
            store.clearPAT(forHost: selfManaged)
            store.clear()
        }

        try store.savePAT("glpat-dotcom", forHost: gitlabCom)
        try store.savePAT("glpat-company", forHost: selfManaged)

        #expect(try store.loadPAT(forHost: gitlabCom) == "glpat-dotcom")
        #expect(try store.loadPAT(forHost: selfManaged) == "glpat-company")
    }

    @Test
    func `save PAT per account ID`() throws {
        let service = "com.weirdoadam.repopeek.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        try store.savePAT("glpat-alice", accountID: "gitlab.example.com#alice")
        try store.savePAT("glpat-bob", accountID: "gitlab.example.com#bob")

        #expect(try store.loadPAT(accountID: "gitlab.example.com#alice") == "glpat-alice")
        #expect(try store.loadPAT(accountID: "gitlab.example.com#bob") == "glpat-bob")

        store.clearPAT(accountID: "gitlab.example.com#alice")

        #expect(try store.loadPAT(accountID: "gitlab.example.com#alice") == nil)
        #expect(try store.loadPAT(accountID: "gitlab.example.com#bob") == "glpat-bob")
    }

    @Test
    func `save OpenAI API key trims and loads`() throws {
        let service = "com.weirdoadam.repopeek.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clearAllCredentials() }

        try store.saveOpenAIAPIKey("  sk-test  ")

        #expect(try store.loadOpenAIAPIKey() == "sk-test")
    }

    @Test
    func `clear PAT preserves OpenAI API key`() throws {
        let service = "com.weirdoadam.repopeek.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clearAllCredentials() }

        try store.savePAT("glpat-test")
        try store.saveOpenAIAPIKey("sk-test")

        store.clear()

        #expect(try store.loadPAT() == nil)
        #expect(try store.loadOpenAIAPIKey() == "sk-test")
    }

    @Test
    func `clear all credentials removes OpenAI API key`() throws {
        let service = "com.weirdoadam.repopeek.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)

        try store.savePAT("glpat-test")
        try store.saveOpenAIAPIKey("sk-test")

        store.clearAllCredentials()

        #expect(try store.loadPAT() == nil)
        #expect(try store.loadOpenAIAPIKey() == nil)
    }
}
