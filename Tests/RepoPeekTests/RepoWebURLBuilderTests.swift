import Foundation
@testable import RepoPeek
import Testing

struct RepoWebURLBuilderTests {
    @Test
    func `gitlab routes preserve subgroup project paths`() throws {
        let host = try #require(URL(string: "https://gitlab.example.com"))
        let builder = RepoWebURLBuilder(host: host)
        let fullName = "group/subgroup/project"

        #expect(builder.repoURL(fullName: fullName)?.absoluteString == "https://gitlab.example.com/group/subgroup/project")
        #expect(builder.issuesURL(fullName: fullName)?.absoluteString == "https://gitlab.example.com/group/subgroup/project/-/issues")
        #expect(builder.pullsURL(fullName: fullName)?.absoluteString == "https://gitlab.example.com/group/subgroup/project/-/merge_requests")
        #expect(builder.pipelinesURL(fullName: fullName)?.absoluteString == "https://gitlab.example.com/group/subgroup/project/-/pipelines")
        #expect(builder.releasesURL(fullName: fullName)?.absoluteString == "https://gitlab.example.com/group/subgroup/project/-/releases")
        #expect(builder.tagsURL(fullName: fullName)?.absoluteString == "https://gitlab.example.com/group/subgroup/project/-/tags")
        #expect(builder.branchesURL(fullName: fullName)?.absoluteString == "https://gitlab.example.com/group/subgroup/project/-/branches")
        #expect(builder.repoPathURL(fullName: fullName, path: "commits")?.absoluteString == "https://gitlab.example.com/group/subgroup/project/-/commits")
        #expect(builder.branchURL(fullName: fullName, branch: "feature/gitlab")?.absoluteString == "https://gitlab.example.com/group/subgroup/project/-/tree/feature/gitlab")
    }
}
