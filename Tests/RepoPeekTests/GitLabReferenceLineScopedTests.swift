@testable import RepoPeekCore
import Testing

struct GitLabReferenceLineScopedTests {
    @Test
    func `recommendation list keeps MR and issue references scoped to repository`() {
        let text = """
          1. example/repopeek MR #27: update diagnostics. Clean, checks green.
          2. example/acpx issue #344: troubleshooting docs. Label says queueable.
          3. example/wacli merge request #271: bound media downloads.
        """

        #expect(GitLabReferenceTranslator.queries(from: text) == [
            .repositoryIssueNumber(repositoryFullName: "example/repopeek", number: 27),
            .repositoryIssueNumber(repositoryFullName: "example/acpx", number: 344),
            .repositoryIssueNumber(repositoryFullName: "example/wacli", number: 271)
        ])
    }

    @Test
    func `same issue number can still inherit override on another sentence`() {
        let text = """
          other/repo MR #7: scoped external reference.
          MR #7 belongs to the current repository.
        """

        #expect(GitLabReferenceTranslator.queries(
            from: text,
            repositoryContextOverride: "current/repo"
        ) == [
            .repositoryIssueNumber(repositoryFullName: "other/repo", number: 7),
            .repositoryIssueNumber(repositoryFullName: "current/repo", number: 7)
        ])
    }

    @Test
    func `repository scoped MR series does not leak to override context`() {
        #expect(GitLabReferenceTranslator.queries(
            from: "other/repo MR #7 and #8",
            repositoryContextOverride: "current/repo"
        ) == [
            .repositoryIssueNumber(repositoryFullName: "other/repo", number: 7),
            .repositoryIssueNumber(repositoryFullName: "other/repo", number: 8)
        ])
        #expect(GitLabReferenceTranslator.queries(
            from: "other/repo merge requests 7 and 8",
            repositoryContextOverride: "current/repo"
        ) == [
            .repositoryIssueNumber(repositoryFullName: "other/repo", number: 7),
            .repositoryIssueNumber(repositoryFullName: "other/repo", number: 8)
        ])
        #expect(GitLabReferenceTranslator.queries(
            from: "other/repo issue #7 and MR #8",
            repositoryContextOverride: "current/repo"
        ) == [
            .repositoryIssueNumber(repositoryFullName: "other/repo", number: 7),
            .repositoryIssueNumber(repositoryFullName: "other/repo", number: 8)
        ])
        #expect(GitLabReferenceTranslator.queries(
            from: "other/repo gl-42",
            repositoryContextOverride: "current/repo"
        ) == [
            .repositoryIssueNumber(repositoryFullName: "other/repo", number: 42)
        ])
    }

    @Test
    func `sentence boundary returns following references to override context`() {
        #expect(GitLabReferenceTranslator.queries(
            from: "other/repo MR #7. MR #8 belongs to the current repo",
            repositoryContextOverride: "current/repo"
        ) == [
            .repositoryIssueNumber(repositoryFullName: "other/repo", number: 7),
            .repositoryIssueNumber(repositoryFullName: "current/repo", number: 8)
        ])
        #expect(GitLabReferenceTranslator.queries(
            from: "other/repo MR #7; #8 belongs to the current repo",
            repositoryContextOverride: "current/repo"
        ) == [
            .repositoryIssueNumber(repositoryFullName: "other/repo", number: 7),
            .repositoryIssueNumber(repositoryFullName: "current/repo", number: 8)
        ])
    }

    @Test
    func `line scoped repository does not become incidental default context`() {
        #expect(GitLabReferenceTranslator.queries(from: "other/repo #18 also affects MR 18") == [
            .repositoryIssueNumber(repositoryFullName: "other/repo", number: 18),
            .issueNumber(18)
        ])

        let mixedContextQueries = GitLabReferenceTranslator.queries(from: """
          Found in current/repo.
          1. #1
          2. other/repo MR #2
        """)
        #expect(mixedContextQueries.count == 2)
        #expect(mixedContextQueries.contains(
            .repositoryIssueNumber(repositoryFullName: "current/repo", number: 1)
        ))
        #expect(mixedContextQueries.contains(
            .repositoryIssueNumber(repositoryFullName: "other/repo", number: 2)
        ))
    }

    @Test
    func `bare line scoped numbers respect minimum digit setting`() {
        #expect(GitLabReferenceTranslator.queries(
            from: "other/repo MR 7",
            minimumBareDigits: 3,
            repositoryContextOverride: "current/repo"
        ).isEmpty)
        #expect(GitLabReferenceTranslator.queries(
            from: "other/repo MR #7",
            minimumBareDigits: 3,
            repositoryContextOverride: "current/repo"
        ) == [
            .repositoryIssueNumber(repositoryFullName: "other/repo", number: 7)
        ])
    }
}
