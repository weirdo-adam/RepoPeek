import Foundation
@testable import RepoPeekCore
import Testing

struct ReleaseSelectionTests {
    @Test
    func `gitlab release decodes released date and self link`() throws {
        let release = try releaseResponse(
            name: "v0.4.1",
            tagName: "v0.4.1",
            releasedAt: "2026-05-01T12:00:00Z",
            createdAt: "2026-05-01T11:00:00Z",
            url: "https://gitlab.example.com/group/project/-/releases/v0.4.1"
        )

        #expect(release.tagName == "v0.4.1")
        #expect(release.releasedAt == Date(timeIntervalSince1970: 1_777_636_800))
        #expect(release.links?.selfUrl?.absoluteString == "https://gitlab.example.com/group/project/-/releases/v0.4.1")
    }

    @Test
    func `gitlab release summary date falls back to created date`() throws {
        let release = try releaseResponse(
            name: "v0.5.0",
            tagName: "v0.5.0",
            releasedAt: nil,
            createdAt: "2026-05-02T12:00:00Z",
            url: "https://gitlab.example.com/group/project/-/releases/v0.5.0"
        )

        let publishedAt = release.releasedAt ?? release.createdAt ?? .distantPast
        #expect(publishedAt == Date(timeIntervalSince1970: 1_777_723_200))
    }
}

private func releaseResponse(
    name: String,
    tagName: String,
    releasedAt: String?,
    createdAt: String?,
    url: String
) throws -> GitLabRelease {
    var fields = [
        "\"name\": \"\(name)\"",
        "\"tag_name\": \"\(tagName)\"",
        "\"_links\": {\"self\": \"\(url)\"}"
    ]
    if let releasedAt {
        fields.append("\"released_at\": \"\(releasedAt)\"")
    }
    if let createdAt {
        fields.append("\"created_at\": \"\(createdAt)\"")
    }
    let json = "{\(fields.joined(separator: ","))}"
    return try JSONDecoding.decode(GitLabRelease.self, from: Data(json.utf8))
}
