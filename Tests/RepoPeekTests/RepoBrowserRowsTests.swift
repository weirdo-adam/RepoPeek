import Foundation
@testable import RepoPeek
import RepoPeekCore
import Testing

struct RepoBrowserRowsTests {
    @Test
    func `make includes accessible repositories with visibility`() {
        let rows = RepoBrowserRows.make(
            repositories: [
                Self.makeRepo("example/RepoPeek", issues: 2, pulls: 1, stars: 42),
                Self.makeRepo("acme-org/sample-app", issues: 5, pulls: 3, stars: 9)
            ],
            pinnedRepositories: ["example/RepoPeek"],
            hiddenRepositories: ["acme-org/sample-app"],
            hiddenGroups: [],
            now: Date(timeIntervalSinceReferenceDate: 1000)
        )

        #expect(rows.map(\.fullName) == ["example/RepoPeek", "acme-org/sample-app"])
        #expect(rows[0].visibility == .pinned)
        #expect(rows[0].issueLabel == "2")
        #expect(rows[0].pullRequestLabel == "1")
        #expect(rows[0].starLabel == "42")
        #expect(rows[1].visibility == .hidden)
        #expect(rows[1].isManual == false)
    }

    @Test
    func `make keeps pinned and hidden manual rows missing from fetch`() {
        let rows = RepoBrowserRows.make(
            repositories: [Self.makeRepo("example/RepoPeek")],
            pinnedRepositories: ["example/missing-pin"],
            hiddenRepositories: ["example/missing-hidden"],
            hiddenGroups: [],
            now: Date(timeIntervalSinceReferenceDate: 1000)
        )

        let manualRows = rows.filter(\.isManual)
        #expect(manualRows.map(\.fullName) == ["example/missing-pin", "example/missing-hidden"])
        #expect(manualRows.map(\.visibility) == [.pinned, .hidden])
        #expect(manualRows.allSatisfy { $0.issueLabel == "-" && $0.updatedLabel == "-" })
    }

    @Test
    func `make emits one unique row when a repo is both pinned and hidden`() {
        let rows = RepoBrowserRows.make(
            repositories: [],
            pinnedRepositories: ["owner/X"],
            hiddenRepositories: ["owner/X"],
            hiddenGroups: [],
            now: Date(timeIntervalSinceReferenceDate: 1000)
        )

        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.count(where: { $0.id == "repository:global:owner/x" }) == 1)
        #expect(rows.first?.visibility == .pinned)
    }

    @Test
    func `make shows loaded repo as pinned when it is both pinned and hidden`() throws {
        let rows = RepoBrowserRows.make(
            repositories: [Self.makeRepo("owner/X")],
            pinnedRepositories: ["owner/X"],
            hiddenRepositories: ["owner/X"],
            hiddenGroups: [],
            now: Date(timeIntervalSinceReferenceDate: 1000)
        )

        let row = try #require(rows.first)
        #expect(row.id == "repository:global:owner/x")
        #expect(row.isManual == false)
        #expect(row.visibility == .pinned)
        #expect(rows.count == 1)
    }

    @Test
    func `make emits one account scoped row when a repo is both pinned and hidden`() {
        let rows = RepoBrowserRows.make(
            repositories: [],
            pinnedRepositories: [],
            hiddenRepositories: [],
            hiddenGroups: [],
            accountScopedRepositoryLists: AccountScopedRepositoryLists(
                pinnedRepositoriesByAccount: ["gitlab.example.com#bob": ["owner/X"]],
                hiddenRepositoriesByAccount: ["gitlab.example.com#bob": ["owner/X"]]
            ),
            now: Date(timeIntervalSinceReferenceDate: 1000)
        )

        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.count(where: { $0.id == "repository:gitlab.example.com#bob:owner/x" }) == 1)
        #expect(rows.first?.visibility == .pinned)
    }

    @Test
    func `matches finds private org repository by owner or name`() {
        let row = RepoBrowserRows.make(
            repositories: [Self.makeRepo("acme-org/sample-app")],
            pinnedRepositories: [],
            hiddenRepositories: [],
            hiddenGroups: [],
            now: Date(timeIntervalSinceReferenceDate: 1000)
        ).first

        #expect(row?.matches("acme") == true)
        #expect(row?.matches("sample") == true)
        #expect(row?.matches("acme sample") == true)
        #expect(row?.matches("example") == false)
    }

    @Test
    func `make marks repositories hidden by group and adds group rule row`() {
        let rows = RepoBrowserRows.make(
            repositories: [
                Self.makeRepo("example/product/product-api"),
                Self.makeRepo("example/devops/ci-pipeline")
            ],
            pinnedRepositories: ["example/product/product-api"],
            hiddenRepositories: [],
            hiddenGroups: ["example/product"],
            now: Date(timeIntervalSinceReferenceDate: 1000)
        )

        let hiddenRepo = rows.first { $0.fullName == "example/product/product-api" }
        let groupRule = rows.first { $0.ruleKind == .group }

        #expect(hiddenRepo?.visibility == .hidden)
        #expect(hiddenRepo?.hiddenByGroup == "example/product")
        #expect(groupRule?.fullName == "example/product")
        #expect(groupRule?.visibility == .hidden)
    }

    @Test
    func `make separates same repository path by account scoped rules`() {
        let alice = Self.makeRepo("team/repo", accountID: "gitlab.example.com#alice")
        let bob = Self.makeRepo("team/repo", accountID: "gitlab.example.com#bob")
        let rows = RepoBrowserRows.make(
            repositories: [alice, bob],
            pinnedRepositories: [],
            hiddenRepositories: [],
            hiddenGroups: [],
            accountScopedRepositoryLists: AccountScopedRepositoryLists(
                pinnedRepositoriesByAccount: ["gitlab.example.com#bob": ["team/repo"]],
                hiddenRepositoriesByAccount: ["gitlab.example.com#alice": ["team/repo"]]
            ),
            now: Date(timeIntervalSinceReferenceDate: 1000)
        )

        #expect(rows.count == 2)
        #expect(Set(rows.map(\.id)).count == 2)
        #expect(rows.first { $0.accountID == "gitlab.example.com#alice" }?.visibility == .hidden)
        #expect(rows.first { $0.accountID == "gitlab.example.com#bob" }?.visibility == .pinned)
    }
}

private extension RepoBrowserRowsTests {
    static func makeRepo(
        _ fullName: String,
        issues: Int = 0,
        pulls: Int = 0,
        stars: Int = 0,
        accountID: String? = nil
    ) -> Repository {
        let parts = fullName.split(separator: "/").map(String.init)
        let owner = parts.dropLast().joined(separator: "/")
        let name = parts.last ?? fullName
        return Repository(
            id: accountID.map { "\($0)/\(fullName.lowercased())" } ?? fullName,
            identity: accountID.map {
                RepositoryIdentity(host: "gitlab.example.com", projectPath: fullName, accountID: $0)
            },
            name: name,
            owner: owner,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: issues,
            openPulls: pulls,
            stars: stars,
            pushedAt: Date(timeIntervalSinceReferenceDate: 100),
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
    }
}
