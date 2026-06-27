import AppKit
import RepoPeekCore

extension StatusBarMenuBuilder {
    func makeRepoSubmenu(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenu {
        RepoSubmenuBuilder(menuBuilder: self).makeRepoSubmenu(for: repo, isPinned: isPinned)
    }

    func populateRepoSubmenu(_ menu: NSMenu, for repo: RepositoryDisplayModel, isPinned: Bool) {
        RepoSubmenuBuilder(menuBuilder: self).populateRepoSubmenu(menu, for: repo, isPinned: isPinned)
    }
}
