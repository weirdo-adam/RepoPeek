import Foundation
@testable import RepoPeekCore
import Testing

struct GitLabHelperTests {
    @Test
    func `parses GitLab next page header`() throws {
        let url = try #require(URL(string: "https://gitlab.example.com/api/v4/projects"))
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["X-Next-Page": "4"]
        ))

        #expect(GitLabRestAPI.nextPage(from: response) == 4)
    }
}
