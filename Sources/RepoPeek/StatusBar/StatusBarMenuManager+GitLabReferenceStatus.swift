import AppKit

extension StatusBarMenuManager {
    @objc func gitLabReferenceMatchChanged() {
        self.gitLabReferenceSyncTask?.cancel()
        self.gitLabReferenceSyncTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }

            self?.gitLabReferenceSyncTask = nil
            self?.preloadIssueNavigatorPreviewForCurrentGitLabReferences()
            self?.syncGitLabReferenceStatusItem()
        }
    }

    func syncGitLabReferenceStatusItem() {
        let matches = self.appState.session.gitLabReferenceMatches
        guard self.appState.session.gitLabReferenceMatch != nil, matches.isEmpty == false else {
            self.hideGitLabReferenceStatusItem()
            return
        }

        let item = self.lazyGitLabReferenceStatusItem()
        let menu = self.lazyGitLabReferenceMenu()
        self.populateGitLabReferenceMenu(menu, matches: matches)
        item.length = NSStatusItem.variableLength
        if let button = item.button {
            button.isHidden = false
            button.isEnabled = true
            button.image = NSImage(
                systemSymbolName: self.gitLabReferenceSystemImage(for: matches),
                accessibilityDescription: self.gitLabReferenceAccessibilityDescription(for: matches)
            )
            button.image?.isTemplate = true
            button.imageScaling = .scaleNone
            (button.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
            self.setButtonTitle(self.gitLabReferenceTitle(for: matches), for: button)
            button.toolTip = self.gitLabReferenceMenuTitle(for: matches)
            button.target = self
            button.action = #selector(self.gitLabReferenceStatusItemClicked(_:))
            _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            self.clampGitLabReferenceStatusItemLength(item, button: button)
        }
        item.menu = nil
        item.isVisible = true
        self.auditStatusItems("syncGitLabReferenceStatusItem visible")
    }

    private func hideGitLabReferenceStatusItem() {
        guard let item = self.gitLabReferenceStatusItem else { return }

        self.gitLabReferenceMenu = nil
        self.gitLabReferenceMenuMatches = []
        self.collapseGitLabReferenceStatusItem(item)
        self.auditStatusItems("hideGitLabReferenceStatusItem")
    }

    private func collapseGitLabReferenceStatusItem(_ item: NSStatusItem) {
        item.menu = nil
        item.length = Self.hiddenGitLabReferenceItemLength
        if let button = item.button {
            button.isHidden = true
            button.isEnabled = false
            button.image = nil
            button.title = ""
            button.toolTip = nil
            button.imagePosition = .imageOnly
            button.target = nil
            button.action = nil
        }
        item.isVisible = true
    }

    private func lazyGitLabReferenceStatusItem() -> NSStatusItem {
        if let item = self.gitLabReferenceStatusItem {
            return item
        }

        let item = self.statusBar.statusItem(withLength: Self.hiddenGitLabReferenceItemLength)
        item.autosaveName = "repopeek-reference"
        item.button?.imageScaling = .scaleNone
        self.gitLabReferenceStatusItem = item
        self.collapseGitLabReferenceStatusItem(item)
        self.auditStatusItems("lazyGitLabReferenceStatusItem created collapsed")
        return item
    }

    func removeGitLabReferenceStatusItem() {
        self.gitLabReferenceMenu = nil
        self.gitLabReferenceMenuMatches = []
        guard let item = self.gitLabReferenceStatusItem else { return }

        self.collapseGitLabReferenceStatusItem(item)
        self.gitLabReferenceStatusItem = nil
        self.statusBar.removeStatusItem(item)
        self.auditStatusItems("removeGitLabReferenceStatusItem")
    }

    func lazyGitLabReferenceMenu() -> NSMenu {
        if let menu = self.gitLabReferenceMenu {
            return menu
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        self.gitLabReferenceMenu = menu
        return menu
    }
}
