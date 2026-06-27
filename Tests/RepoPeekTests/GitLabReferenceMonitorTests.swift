import Foundation
@testable import RepoPeekCore
import Testing

@MainActor
struct GitLabReferenceMonitorTests {
    @Test
    func `bare numbers and issue prefixes become issue queries`() {
        #expect(GitLabReferenceTranslator.query(from: "73655") == .issueNumber(73655))
        #expect(GitLabReferenceTranslator.query(from: "7") == .issueNumber(7))
        #expect(GitLabReferenceTranslator.query(from: "#7") == .issueNumber(7))
        #expect(GitLabReferenceTranslator.query(from: "gl-42") == .issueNumber(42))
        #expect(GitLabReferenceTranslator.query(from: "GL-42") == .issueNumber(42))
        #expect(GitLabReferenceTranslator.query(from: " #78096. ") == .issueNumber(78096))
        #expect(GitLabReferenceTranslator.query(from: "a73655") == nil)
    }

    @Test
    func `commit hashes become commit queries`() {
        #expect(GitLabReferenceTranslator.query(from: "4992546") == .commitHash("4992546"))
        #expect(GitLabReferenceTranslator.query(from: " - bare short SHA: 4992546") == .commitHash("4992546"))
        #expect(GitLabReferenceTranslator.query(from: "ffd212ca43") == .commitHash("ffd212ca43"))
        #expect(
            GitLabReferenceTranslator.query(from: "d04517cefff3af339f560a8e388cacc3898e6562") ==
                .commitHash("d04517cefff3af339f560a8e388cacc3898e6562")
        )
        #expect(GitLabReferenceTranslator.query(from: "1234567") == .commitHash("1234567"))
        #expect(GitLabReferenceTranslator.query(from: "abcdef") == nil)
    }

    @Test
    func `owner repo issue shorthand becomes repository scoped issue query`() {
        #expect(
            GitLabReferenceTranslator.query(from: "example/summarize#215") ==
                .repositoryIssueNumber(repositoryFullName: "example/summarize", number: 215)
        )
        #expect(
            GitLabReferenceTranslator.query(from: "example/clawsweeper#57") ==
                .repositoryIssueNumber(repositoryFullName: "example/clawsweeper", number: 57)
        )
        #expect(
            GitLabReferenceTranslator.query(from: " example/summarize#215. ") ==
                .repositoryIssueNumber(repositoryFullName: "example/summarize", number: 215)
        )
        #expect(
            GitLabReferenceTranslator.query(from: "  - scoped issue shorthand: example/summarize#215") ==
                .repositoryIssueNumber(repositoryFullName: "example/summarize", number: 215)
        )
    }

    @Test
    func `repo name issue shorthand becomes repository name scoped issue query`() {
        #expect(
            GitLabReferenceTranslator.query(from: "discrawl#64") ==
                .repositoryNameIssueNumber(repositoryName: "discrawl", number: 64)
        )
        #expect(
            GitLabReferenceTranslator.query(from: " Discrawl#64. ") ==
                .repositoryNameIssueNumber(repositoryName: "Discrawl", number: 64)
        )
        #expect(
            GitLabReferenceTranslator.query(from: "example/RepoPeek#66") ==
                .repositoryIssueNumber(repositoryFullName: "example/RepoPeek", number: 66)
        )
        #expect(
            GitLabReferenceTranslator.query(from: "https://gitlab.com/example/RepoPeek/-/merge_requests/66") ==
                .repositoryIssueNumber(repositoryFullName: "example/RepoPeek", number: 66)
        )
    }

    @Test
    func `chained owner repo issue shorthand becomes multiple repository scoped issue queries`() {
        #expect(
            GitLabReferenceTranslator.queries(from: "example/repo-beta#70/#71") == [
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 70),
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 71)
            ]
        )
        #expect(
            GitLabReferenceTranslator.queries(from: "make - example/repo-beta#70/#71: work") == [
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 70),
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 71)
            ]
        )
    }

    @Test
    func `ranged owner repo issue shorthand becomes repository scoped issue series`() {
        #expect(
            GitLabReferenceTranslator.queries(from: "example/repo-beta#66-#69") == [
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 66),
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 67),
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 68),
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 69)
            ]
        )
        #expect(
            GitLabReferenceTranslator.queries(from: "also make example/repo-beta#66-#69 work (series)") == [
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 66),
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 67),
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 68),
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 69)
            ]
        )
        #expect(
            GitLabReferenceTranslator.queries(from: "example/repo-beta#66-69") == [
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 66),
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 67),
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 68),
                .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 69)
            ]
        )
    }

    @Test
    func `gitlab issue and MR urls become repository scoped issue queries`() {
        #expect(
            GitLabReferenceTranslator.query(from: "https://gitlab.com/example/example/-/issues/73655") ==
                .repositoryIssueNumber(repositoryFullName: "example/example", number: 73655)
        )
        #expect(
            GitLabReferenceTranslator.query(from: "https://gitlab.com/example/example/-/merge_requests/123") ==
                .repositoryIssueNumber(repositoryFullName: "example/example", number: 123)
        )
        #expect(
            GitLabReferenceTranslator.query(from: "https://gitlab.com/example/example/-/issues/1234567") ==
                .repositoryIssueNumber(repositoryFullName: "example/example", number: 1_234_567)
        )
        #expect(
            GitLabReferenceTranslator.query(from: "https://gitlab.com/example/example/-/merge_requests/1234567") ==
                .repositoryIssueNumber(repositoryFullName: "example/example", number: 1_234_567)
        )
    }

    @Test
    func `gitlab commit urls become repository scoped commit queries`() {
        #expect(
            GitLabReferenceTranslator.query(from: "https://gitlab.com/example/example/-/commit/ffd212ca43abcdef") ==
                .repositoryCommitHash(repositoryFullName: "example/example", hash: "ffd212ca43abcdef")
        )
        #expect(
            GitLabReferenceTranslator.query(from: "https://gitlab.com/example/example/-/commits/ffd212ca43") ==
                .repositoryCommitHash(repositoryFullName: "example/example", hash: "ffd212ca43")
        )
        #expect(
            GitLabReferenceTranslator.query(from: "https://gitlab.com/example/example/-/merge_requests/57843/changes/d04517cefff3af339f560a8e388cacc3898e6562") ==
                .repositoryCommitHash(repositoryFullName: "example/example", hash: "d04517cefff3af339f560a8e388cacc3898e6562")
        )
    }

    @Test
    func `distinct commit hashes with shared display prefix remain distinct`() {
        let first = "abcdef1234000000000000000000000000000000"
        let second = "abcdef1234ffffffffffffffffffffffffffffff"

        #expect(GitLabReferenceTranslator.queries(from: "commits \(first) \(second)") == [
            .commitHash(first),
            .commitHash(second)
        ])
    }

    @Test
    func `gitlab pipeline urls become repository scoped workflow run queries`() {
        #expect(
            GitLabReferenceTranslator.query(from: "https://gitlab.com/example/songsee/-/pipelines/25620622163") ==
                .repositoryWorkflowRun(repositoryFullName: "example/songsee", runID: 25_620_622_163)
        )
    }

    @Test
    func `multiple bare issue references inherit repository context`() {
        let text = """
        Found 5 more in example/gogcli after clean main pull.

        1. #569 release/bottle codesigning
        2. #568 local self-sign MR
        3. #567 Win11 access_denied
        4. #338 Workspace invalid_rapt
        5. #468 Google Meet MR
        """
        #expect(
            GitLabReferenceTranslator.queries(from: text) == [
                .repositoryIssueNumber(repositoryFullName: "example/gogcli", number: 569),
                .repositoryIssueNumber(repositoryFullName: "example/gogcli", number: 568),
                .repositoryIssueNumber(repositoryFullName: "example/gogcli", number: 567),
                .repositoryIssueNumber(repositoryFullName: "example/gogcli", number: 338),
                .repositoryIssueNumber(repositoryFullName: "example/gogcli", number: 468)
            ]
        )
    }

    @Test
    func `multiple grouped issue references use line scoped repository context`() {
        let text = """
            - example/discrawl: #61, #62, #63
            - example/acpx: #294, #295, #296, #297, #303
            - example/example.ai: #132, #133, #134
            - example/oracle: #188
            - example/spogo: #26
            - example/gitcrawl: #14
        """
        #expect(GitLabReferenceTranslator.queries(from: text) == [
            .repositoryIssueNumber(repositoryFullName: "example/discrawl", number: 61),
            .repositoryIssueNumber(repositoryFullName: "example/discrawl", number: 62),
            .repositoryIssueNumber(repositoryFullName: "example/discrawl", number: 63),
            .repositoryIssueNumber(repositoryFullName: "example/acpx", number: 294),
            .repositoryIssueNumber(repositoryFullName: "example/acpx", number: 295),
            .repositoryIssueNumber(repositoryFullName: "example/acpx", number: 296),
            .repositoryIssueNumber(repositoryFullName: "example/acpx", number: 297),
            .repositoryIssueNumber(repositoryFullName: "example/acpx", number: 303),
            .repositoryIssueNumber(repositoryFullName: "example/example.ai", number: 132),
            .repositoryIssueNumber(repositoryFullName: "example/example.ai", number: 133),
            .repositoryIssueNumber(repositoryFullName: "example/example.ai", number: 134),
            .repositoryIssueNumber(repositoryFullName: "example/oracle", number: 188),
            .repositoryIssueNumber(repositoryFullName: "example/spogo", number: 26),
            .repositoryIssueNumber(repositoryFullName: "example/gitcrawl", number: 14)
        ])
    }

    @Test
    func `multiple repository issue references allow space before issue number`() {
        let text = """
          - example/birdclaw #23: X bookmarks max_results=90 workaround. Small, 4 files, tests
            included, strong real-world bug proof. Best first review.
          - example/birdclaw #18: --early-stop dedupe saturation for likes/bookmarks. Larger but
            self-contained, lots of tests/docs, live smoke in MR body.
          - example/oracle #194: browser upload ZIP bundle format. Medium 17-file feature, tests/
            docs/changelog included. Worth review before it rots.
          - example/example.me #224: blog post "When Claude Emails Claude". Clean, old green CI,
            content-only-ish plus hero image. Likely easy land/close decision.
          - example/camsnap #2: Docker + GHCR publishing. Small 4-file MR but DIRTY; good review/fix
            candidate if Docker support still wanted.

          Skipped for now:
        """
        #expect(GitLabReferenceTranslator.queries(from: text).map(\.displayText) == [
            "example/birdclaw#23",
            "example/birdclaw#18",
            "example/oracle#194",
            "example/example.me#224",
            "example/camsnap#2"
        ])
    }

    @Test
    func `multiple parser ignores slash words that are not repository context`() {
        let text = """
        Found items in example/gogcli.

        1. #569 release/bottle codesigning
        2. #568 local self-sign MR
        """
        #expect(GitLabReferenceTranslator.queries(from: text) == [
            .repositoryIssueNumber(repositoryFullName: "example/gogcli", number: 569),
            .repositoryIssueNumber(repositoryFullName: "example/gogcli", number: 568)
        ])
    }

    @Test
    func `multiple parser ignores ordered list numbers`() {
        let text = """
        1. #10 first
        2. #11 second
        """
        #expect(GitLabReferenceTranslator.queries(from: text) == [.issueNumber(10), .issueNumber(11)])
    }

    @Test
    func `bare MR references inherit selected repository list item context`() {
        let text = """
        1. example/Peekaboo

        - Do: MR #139, maybe #138 in same pass.
        - Why: small, concrete stale-tool-schema prompt fix; tests added. #138 is a 1-line community docs add.
        - Risk: low. Proof path: Swift/package tests around PeekabooAgentRuntime.
        """
        #expect(GitLabReferenceTranslator.queries(from: text) == [
            .repositoryIssueNumber(repositoryFullName: "example/Peekaboo", number: 139),
            .repositoryIssueNumber(repositoryFullName: "example/Peekaboo", number: 138)
        ])
    }

    @Test
    func `bare references stay unscoped when selection has multiple repository list items`() {
        let text = """
        1. example/Peekaboo
        2. example/gogcli

        - Do: MR #139
        """
        #expect(GitLabReferenceTranslator.queries(from: text) == [.issueNumber(139)])
    }

    @Test
    func `explicit repository context beats selected repository list item context`() {
        let text = """
        1. example/Peekaboo

        Found in example/gogcli: #569
        """
        #expect(GitLabReferenceTranslator.queries(from: text) == [
            .repositoryIssueNumber(repositoryFullName: "example/gogcli", number: 569)
        ])
    }

    @Test
    func `bare numbers in MR and issue prose become multiple references`() {
        let text = """
        any chance you can review MR 75133, 78985 and 82724 for inclusion? They are all related to bugs/issues with subagents, delegated tasks to harnesses like codex and claude.

        I also have a security fix/enhancement I have proposed that has been out there for a while. That is 76949.
        """
        #expect(GitLabReferenceTranslator.queries(from: text) == [
            .issueNumber(75133),
            .issueNumber(78985),
            .issueNumber(82724),
            .issueNumber(76949)
        ])

        #expect(GitLabReferenceTranslator.queries(from: "MR #123, 456 and 789") == [
            .issueNumber(123),
            .issueNumber(456),
            .issueNumber(789)
        ])

        #expect(GitLabReferenceTranslator.queries(from: "please review merge requests 123 and 456") == [
            .issueNumber(123),
            .issueNumber(456)
        ])

        #expect(GitLabReferenceTranslator.queries(from: """
        I also have a security fix/enhancement I have proposed that has been out there for a while.
        That is 76949.
        """) == [.issueNumber(76949)])
    }

    @Test
    func `contextual bare issue parser ignores years`() {
        let text = "please review MR 68 from 2026"
        #expect(GitLabReferenceTranslator.queries(from: text) == [.issueNumber(68)])
        #expect(GitLabReferenceTranslator.queries(from: "please review MR 2026") == [.issueNumber(2026)])
        #expect(GitLabReferenceTranslator.queries(from: "please review issue 1999") == [.issueNumber(1999)])
    }

    @Test
    func `contextual bare issue parser ignores incidental sentence numbers`() {
        #expect(GitLabReferenceTranslator.queries(from: "please review MR 68 with 2 commits") == [.issueNumber(68)])
        #expect(GitLabReferenceTranslator.queries(from: "please review MR 123 on macOS 15") == [.issueNumber(123)])
        #expect(GitLabReferenceTranslator.queries(from: "this MR has 2 commits").isEmpty)
        #expect(GitLabReferenceTranslator.queries(from: "I have issues with 2 things").isEmpty)
        #expect(GitLabReferenceTranslator.queries(from: "please review MR 123 adds support") == [.issueNumber(123)])
        #expect(GitLabReferenceTranslator.queries(from: "issue 456 deletes stale state") == [.issueNumber(456)])
        #expect(GitLabReferenceTranslator.queries(from: "please review MRs 123 and 456 add support") == [.issueNumber(123), .issueNumber(456)])
        #expect(GitLabReferenceTranslator.queries(from: "please review MRs 123 and 456 add 2 tests") == [.issueNumber(123), .issueNumber(456)])
        #expect(GitLabReferenceTranslator.queries(from: "please review MRs 123 and 456 add / remove support") == [.issueNumber(123), .issueNumber(456)])
        #expect(GitLabReferenceTranslator.queries(from: "closed issues 12 and 13 delete stale state") == [.issueNumber(12), .issueNumber(13)])
    }

    @Test
    func `numbered repository headings inherit context after nested count summary`() {
        let text = """
          1. example/repopeek
              - 0 issues / 1 MR
              - MR #44: clean, pipeline green
          2. example/clawsweeper-state
              - 1 issue / 1 MR
              - MR #3: 95 add / 8 del / 7 files, security checks green
              - issue #268 needs maintainer decision
          3. example/wacli
              - 0 issues / 1 merge request
              - merge request #267: 474 additions and 5 deletions
        """

        #expect(GitLabReferenceTranslator.queries(from: text) == [
            .repositoryIssueNumber(repositoryFullName: "example/repopeek", number: 44),
            .repositoryIssueNumber(repositoryFullName: "example/clawsweeper-state", number: 3),
            .repositoryIssueNumber(repositoryFullName: "example/clawsweeper-state", number: 268),
            .repositoryIssueNumber(repositoryFullName: "example/wacli", number: 267)
        ])
    }

    @Test
    func `ordered list parser prefers leading references over incidental references`() {
        let text = """
        1. #2172 — schema text extensions
           URL: https://gitlab.com/example/clawhub/-/merge_requests/2172
           Why: small, real bug, linked #874.
        2. #2173 — canonical /user/<handle> profile route
           URL: https://gitlab.com/example/clawhub/-/merge_requests/2173
        3. #2186 — OpenAPI package catalog docs
           URL: https://gitlab.com/example/clawhub/-/merge_requests/2186
        """
        #expect(GitLabReferenceTranslator.queries(from: text) == [
            .repositoryIssueNumber(repositoryFullName: "example/clawhub", number: 2172),
            .repositoryIssueNumber(repositoryFullName: "example/clawhub", number: 2173),
            .repositoryIssueNumber(repositoryFullName: "example/clawhub", number: 2186)
        ])
    }

    @Test
    func `multiple parser dedupes references after inheriting scoped context`() {
        let text = "example/gogcli#569 #569 https://gitlab.com/example/gogcli/-/issues/569"
        #expect(GitLabReferenceTranslator.queries(from: text) == [
            .repositoryIssueNumber(repositoryFullName: "example/gogcli", number: 569)
        ])
    }

    @Test
    func `local path candidates trim prompt separators`() {
        let text = "gpt-5.5 high fast · ~/Projects/repo-beta · -"
        #expect(GitLabReferenceLocalContext.localPathCandidates(in: text) == ["~/Projects/repo-beta"])
    }

    @Test
    func `remote urls become gitlab repository full names`() {
        #expect(
            GitLabReferenceLocalContext.gitLabRepositoryFullName(
                fromRemoteURL: "https://gitlab.com/example/repo-beta.git"
            ) == "example/repo-beta"
        )
        #expect(
            GitLabReferenceLocalContext.gitLabRepositoryFullName(
                fromRemoteURL: "git@gitlab.com:example/repo-beta.git"
            ) == "example/repo-beta"
        )
        #expect(
            GitLabReferenceLocalContext.gitLabRepositoryFullName(
                fromRemoteURL: "git@gitlab.com:group/subgroup/repo-beta.git"
            ) == "group/subgroup/repo-beta"
        )
        #expect(
            GitLabReferenceLocalContext.gitLabRepositoryFullName(
                fromRemoteURL: "https://gitlab.example.com/root/platform/repo-beta.git"
            ) == "root/platform/repo-beta"
        )
    }

    @Test
    func `bare references inherit local repository context`() async {
        let status = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/repo-beta"),
            name: "repo-beta",
            fullName: "example/repo-beta",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )
        let index = LocalRepoIndex(statuses: [status])
        let text = """
        - MRs:
            - #61 feat: add checkpoint ledger store
            - #60 docs: sharpen agent workspace positioning

        gpt-5.5 high fast · /tmp/repo-beta · -
        """
        let repositoryFullName = await GitLabReferenceLocalContext.repositoryFullName(in: text, localRepoIndex: index)
        let queries: [GitLabReferenceQuery] = GitLabReferenceLocalContext.queries(
            GitLabReferenceTranslator.queries(from: text),
            applyingRepositoryFullName: repositoryFullName
        )
        let expected: [GitLabReferenceQuery] = [
            .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 61),
            .repositoryIssueNumber(repositoryFullName: "example/repo-beta", number: 60)
        ]
        #expect(queries == expected)
    }

    @Test
    func `bare commit references inherit unique local commit context`() async throws {
        let repoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoURL) }

        try runGit(["init"], in: repoURL)
        try runGit(["config", "user.email", "repopeek-tests@example.com"], in: repoURL)
        try runGit(["config", "user.name", "RepoPeek Tests"], in: repoURL)
        try "hello\n".write(to: repoURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "init"], in: repoURL)
        let sha = try runGit(["rev-parse", "HEAD"], in: repoURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let shortSHA = String(sha.prefix(7))

        let status = LocalRepoStatus(
            path: repoURL,
            name: "RepoPeek",
            fullName: "example/RepoPeek",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )
        let queries = await GitLabReferenceLocalContext.queries(
            [.commitHash(shortSHA)],
            applyingLocalRepositoryContextFrom: LocalRepoIndex(statuses: [status])
        )

        #expect(queries == [.repositoryCommitHash(repositoryFullName: "example/RepoPeek", hash: shortSHA)])
    }

    @Test
    func `repo name issue references inherit unique local repository context`() async {
        let status = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/discrawl"),
            name: "discrawl",
            fullName: "example/discrawl",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )

        let queries = await GitLabReferenceLocalContext.queries(
            [.repositoryNameIssueNumber(repositoryName: "discrawl", number: 64)],
            applyingLocalRepositoryContextFrom: LocalRepoIndex(statuses: [status])
        )

        #expect(queries == [.repositoryIssueNumber(repositoryFullName: "example/discrawl", number: 64)])
    }

    @Test
    func `local repository context beats prose slash words`() {
        let text = """
        - #2124 header avatar controls
        - #2128 content container constraints
        - #908 upload page validation errors hidden. Likely fix: surface validationError inline/toast on publish/upload forms.
        - #937 clawhub update --all false local changes.
        - #951 onlycrabs.ai README mismatch.

        Skipped: #2126 too large, #1110 conflicts + API feature, #1712 stats/accounting touches telemetry semantics.

        gpt-5.5 high fast · ~/Projects/clawhub · Context 67% left
        """
        let queries = GitLabReferenceTranslator.queries(
            from: text,
            repositoryContextOverride: "example/clawhub"
        )
        #expect(queries.map(\.displayText) == [
            "example/clawhub#2124",
            "example/clawhub#2128",
            "example/clawhub#908",
            "example/clawhub#937",
            "example/clawhub#951",
            "example/clawhub#2126",
            "example/clawhub#1110",
            "example/clawhub#1712"
        ])
    }
}

@discardableResult
private func runGit(_ arguments: [String], in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = directory
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    if process.terminationStatus != 0 {
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: errorData, encoding: .utf8) ?? "git failed"
        throw NSError(domain: "GitLabReferenceMonitorTests", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
    }
    return String(data: data, encoding: .utf8) ?? ""
}
