import Foundation
@testable import RepoPeek
import RepoPeekCore
import Testing

struct RepoPeekNotificationResponseHandlerTests {
    @Test
    func `click target defaults older notifications to browser URLs`() throws {
        let url = try #require(URL(string: "https://gitlab.com/example/RepoPeek/-/merge_requests/57"))

        let target = RepoPeekNotificationResponseHandler.clickTarget(from: ["url": url.absoluteString])

        #expect(target == .browser(url))
    }

    @Test
    func `click target opens issue navigator when configured`() {
        let target = RepoPeekNotificationResponseHandler.clickTarget(from: [
            "clickAction": GitLabPullRequestNotificationClickAction.openIssueNavigator.rawValue,
            "url": "https://gitlab.com/example/RepoPeek/-/merge_requests/57",
            "repositoryFullName": "example/RepoPeek",
            "pullRequestNumber": 57,
            "itemTitle": "Add notifications"
        ])

        guard case let .issueNavigator(matches) = target else {
            Issue.record("Expected issue navigator target")
            return
        }

        #expect(matches.count == 1)
        #expect(matches.first?.repositoryFullName == "example/RepoPeek")
        #expect(matches.first?.title == "Add notifications")
        #expect(matches.first?.url.absoluteString == "https://gitlab.com/example/RepoPeek/-/merge_requests/57")
    }

    @Test
    func `click target opens empty issue navigator for old issue navigator notifications`() {
        let target = RepoPeekNotificationResponseHandler.clickTarget(from: [
            "clickAction": GitLabPullRequestNotificationClickAction.openIssueNavigator.rawValue
        ])

        #expect(target == .issueNavigator([]))
    }

    @Test
    func `click target ignores browser action without a valid URL`() {
        let target = RepoPeekNotificationResponseHandler.clickTarget(from: [
            "clickAction": GitLabPullRequestNotificationClickAction.openInBrowser.rawValue
        ])

        #expect(target == .none)
    }
}
