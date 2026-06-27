import AppKit

extension StatusBarMenuManager {
    @objc func gitLabReferenceStatusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let shouldShowMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        guard shouldShowMenu == false else {
            self.showGitLabReferenceMenu(from: sender)
            return
        }

        let matches = self.appState.session.gitLabReferenceMatches
        guard matches.count > 1 else {
            self.showGitLabReferenceMenu(from: sender)
            return
        }

        self.openGitLabReferenceMatchesInIssueNavigator()
    }

    private func showGitLabReferenceMenu(from sender: Any?) {
        guard let item = self.gitLabReferenceStatusItem,
              let button = sender as? NSStatusBarButton ?? item.button
        else { return }

        item.menu = self.lazyGitLabReferenceMenu()
        button.performClick(nil)
    }
}
