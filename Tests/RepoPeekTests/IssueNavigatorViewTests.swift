@testable import RepoPeek
import Testing

struct IssueNavigatorViewTests {
    @Test
    func `initial reference matches do not get overwritten by clipboard seed`() {
        #expect(!IssueNavigatorView.shouldSeedClipboardOnAppear(hasInitialMatches: true))
        #expect(IssueNavigatorView.shouldSeedClipboardOnAppear(hasInitialMatches: false))
    }
}
