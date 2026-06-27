import AppKit

extension StatusBarMenuManager {
    func preloadGitLabReferenceMenuPreviews(_ menu: NSMenu) {
        var remaining = min(
            AppLimits.GitLabReferenceMonitor.menuWebPreviewPreloadLimit,
            max(1, self.appState.session.gitLabReferenceMatches.count)
        )
        self.preloadGitLabReferenceMenuPreviews(in: menu, remaining: &remaining)
    }

    private func preloadGitLabReferenceMenuPreviews(in menu: NSMenu, remaining: inout Int) {
        guard remaining > 0 else { return }

        for item in menu.items {
            if let browserView = item.view as? GitLabReferenceBrowserMenuItemView {
                browserView.preload()
                remaining -= 1
                if remaining <= 0 { return }
            }
            if let submenu = item.submenu {
                self.preloadGitLabReferenceMenuPreviews(in: submenu, remaining: &remaining)
                if remaining <= 0 { return }
            }
        }
    }

    func unloadGitLabReferenceMenuPreviews(_ menu: NSMenu) {
        for item in menu.items {
            (item.view as? GitLabReferenceBrowserMenuItemView)?.unload()
            if let submenu = item.submenu {
                self.unloadGitLabReferenceMenuPreviews(submenu)
            }
        }
    }
}
