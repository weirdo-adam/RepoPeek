import AppKit
import RepoPeekCore
import SwiftUI

struct RepoMenuActionContext: Hashable {
    let fullName: String
    let lookupKey: String?
    let accountID: String?
}

extension RepositoryDisplayModel {
    var menuActionContext: RepoMenuActionContext {
        RepoMenuActionContext(
            fullName: self.title,
            lookupKey: self.source.lookupKey,
            accountID: self.source.identity?.accountID
        )
    }
}

extension StatusBarMenuBuilder {
    func paddedSeparator() -> NSMenuItem {
        self.viewItem(for: MenuPaddedSeparatorView(), enabled: false)
    }

    func repoCardSeparator() -> NSMenuItem {
        self.viewItem(for: RepoCardSeparatorRowView(), enabled: false)
    }

    func repoMenuItem(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenuItem {
        let card = RepoMenuCardView(
            repo: repo,
            isPinned: isPinned,
            showHeatmap: self.appState.session.settings.heatmap.display == .inline,
            heatmapRange: self.appState.session.heatmapRange,
            accentTone: self.appState.session.settings.appearance.accentTone,
            showDirtyFiles: self.appState.session.settings.localProjects.showDirtyFilesInMenu,
            language: self.appState.session.settings.language,
            onOpen: { [weak target] in
                target?.openRepoFromMenu(fullName: repo.title)
            }
        )
        let submenu = self.repoSubmenu(for: repo, isPinned: isPinned)
        if let cached = self.repoMenuItemCache[repo.id] {
            // Remove from current menu if attached (prevents crash when reusing cached items)
            cached.menu?.removeItem(cached)
            self.menuItemFactory.updateItem(cached, with: card, highlightable: true, showsSubmenuIndicator: true)
            cached.isEnabled = true
            cached.submenu = submenu
            cached.target = self.target
            cached.action = #selector(self.target.menuItemNoOp(_:))
            return cached
        }
        let item = self.viewItem(for: card, enabled: true, highlightable: true, submenu: submenu)
        self.repoMenuItemCache[repo.id] = item
        return item
    }

    func repoSubmenu(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenu {
        let signature = self.repoSubmenuSignature(for: repo, isPinned: isPinned)
        if let cached = self.repoSubmenuCache[repo.id], cached.signature == signature {
            return cached.menu
        }
        let menu = self.makeRepoSubmenu(for: repo, isPinned: isPinned)
        self.repoSubmenuCache[repo.id] = RepoSubmenuCacheEntry(menu: menu, signature: signature)
        return menu
    }

    func repoFullName(for menu: NSMenu) -> String? {
        self.repoSubmenuCache.first(where: { $0.value.menu === menu })?.value.signature.fullName
    }

    func repoContext(for menu: NSMenu) -> RepoRecentMenuContext? {
        let cacheEntry = self.repoSubmenuCache.first(where: { $0.value.menu === menu })
        let represented = menu.supermenu?.items.first(where: { $0.submenu === menu })?.representedObject
        let fullName = cacheEntry?.value.signature.fullName
            ?? self.repoFullName(for: menu)
            ?? (represented as? RepoMenuActionContext)?.fullName
            ?? (represented as? String)
        guard let fullName, fullName.contains("/") else { return nil }

        let model = cacheEntry.flatMap { self.appState.session.menuDisplayIndex[$0.key] }
            ?? self.repoDisplayModel(fullName: fullName)
        let hostKey = model?.source.identity?.accountID
            ?? model?.source.identity?.host
            ?? self.appState.session.localRepoIndex.status(forFullName: fullName)?.remoteWebURLHost.map {
                GitLabAccountSettings.hostKey(for: $0)
            }
        return RepoRecentMenuContext(fullName: fullName, hostKey: hostKey, kind: .commits)
    }

    func refreshRepoSubmenu(_ menu: NSMenu, fullName: String) {
        guard let repo = self.repoDisplayModel(fullName: fullName) else { return }

        let isPinned = self.isPinned(repoFullName: repo.title, accountID: repo.source.identity?.accountID)
        self.populateRepoSubmenu(menu, for: repo, isPinned: isPinned)
        let signature = self.repoSubmenuSignature(for: repo, isPinned: isPinned)
        let cacheKey = self.repoSubmenuCache.first(where: { $0.value.menu === menu })?.key ?? repo.id
        self.repoSubmenuCache[cacheKey] = RepoSubmenuCacheEntry(menu: menu, signature: signature)
        self.refreshMenuViewHeights(in: menu)
        menu.update()
    }

    private func repoSubmenuSignature(for repo: RepositoryDisplayModel, isPinned: Bool) -> RepoSubmenuSignature {
        let changelogPresentation = self.target.cachedChangelogPresentation(
            fullName: repo.title,
            releaseTag: repo.source.latestRelease?.tag
        )
        let changelogHeadline = self.target.cachedChangelogHeadline(fullName: repo.title)
        return RepoSubmenuSignature(
            repo: repo,
            settings: self.appState.session.settings,
            heatmapRange: self.appState.session.heatmapRange,
            recentCounts: RepoRecentCountSignature(
                commits: self.target.cachedRecentCommitCount(cacheKey: repo.recentMenuCacheKey),
                commitsDigest: self.target.cachedRecentCommitDigest(cacheKey: repo.recentMenuCacheKey)
            ),
            changelogPresentation: changelogPresentation,
            changelogHeadline: changelogHeadline,
            isPinned: isPinned
        )
    }

    private func repoDisplayModel(fullName: String, now: Date = Date()) -> RepositoryDisplayModel? {
        let normalized = fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let session = self.appState.session
        if let model = session.menuDisplayIndex[normalized] {
            return model
        }

        let repositories = session.repositories.isEmpty
            ? (session.menuSnapshot?.repositories ?? [])
            : session.repositories
        guard let repo = repositories.first(where: {
            $0.fullName.lowercased() == normalized ||
                $0.lookupKey == normalized ||
                $0.id.lowercased() == normalized
        }) else {
            return nil
        }

        return RepositoryDisplayModel(repo: repo, localStatus: session.localRepoIndex.status(for: repo), now: now)
    }

    private func isPinned(repoFullName: String, accountID: String?) -> Bool {
        self.appState.session.settings.repoList.isPinned(fullName: repoFullName, accountID: accountID)
    }

    func updateChangelogRow(fullName: String, releaseTag: String?) {
        guard let cached = self.repoSubmenuCache[fullName]
            ?? self.repoSubmenuCache.first(where: { $0.value.signature.fullName == fullName })?.value
        else { return }
        guard let item = cached.menu.items.first(where: {
            guard let identifier = $0.representedObject as? RepoSubmenuRowIdentifier else { return false }

            return identifier.fullName == fullName && identifier.kind == .changelog
        }) else { return }

        let presentation = self.target.cachedChangelogPresentation(fullName: fullName, releaseTag: releaseTag)
        let headline = self.target.cachedChangelogHeadline(fullName: fullName)
        let title = headline == nil ? (presentation?.title ?? self.t("Changelog")) : self.t("Changelog")
        let badgeText = headline ?? presentation?.badgeText
        let detailText = headline == nil ? presentation?.detailText : nil
        let row = RecentListSubmenuRowView(
            title: title,
            systemImage: "doc.text",
            badgeText: badgeText,
            detailText: detailText
        )
        self.menuItemFactory.updateItem(item, with: row, highlightable: true, showsSubmenuIndicator: true)
        self.refreshMenuViewHeights(in: cached.menu)
        cached.menu.update()
    }

    func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func infoMessageItem(_ title: String) -> NSMenuItem {
        let view = MenuInfoTextRowView(text: title, lineLimit: 5)
        return self.viewItem(for: view, enabled: false)
    }

    func rateLimitSectionHeaderItem(_ title: String) -> NSMenuItem {
        self.viewItem(for: RateLimitSectionHeaderView(title: title), enabled: false)
    }

    func rateLimitResourceItem(_ row: RateLimitDisplayRow) -> NSMenuItem {
        self.viewItem(for: RateLimitResourceRowView(row: row, language: self.appState.session.settings.language), enabled: false)
    }

    func rateLimitsMenuItem(now: Date = Date()) -> NSMenuItem {
        let item = NSMenuItem(title: self.t("GitLab API Status"), action: nil, keyEquivalent: "")
        item.image = self.cachedSystemImage(named: "speedometer")
        item.submenu = self.rateLimitsSubmenu(now: now)
        return item
    }

    func rateLimitsMenuItemIfNeeded(now: Date = Date()) -> NSMenuItem? {
        guard self.appState.session.rateLimitDisplayState.isLimited(now: now) else { return nil }

        return self.rateLimitsMenuItem(now: now)
    }

    func rateLimitsStatusMenuItem(now: Date = Date()) -> NSMenuItem {
        let state = self.appState.session.rateLimitDisplayState
        let view = RateLimitStatusRowView(
            title: self.t("GitLab API Status"),
            summary: state.compactSummary(now: now),
            isLimited: state.isLimited(now: now)
        )
        return self.viewItem(
            for: view,
            enabled: true,
            highlightable: true,
            submenu: self.rateLimitsSubmenu(state: state, now: now)
        )
    }

    func rateLimitsStatusMenuItemIfNeeded(now: Date = Date()) -> NSMenuItem? {
        guard self.appState.session.rateLimitDisplayState.isLimited(now: now) else { return nil }

        return self.rateLimitsStatusMenuItem(now: now)
    }

    private func rateLimitsSubmenu(now: Date = Date()) -> NSMenu {
        self.rateLimitsSubmenu(state: self.appState.session.rateLimitDisplayState, now: now)
    }

    private func rateLimitsSubmenu(state: RateLimitDisplayState, now: Date) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target

        let sections = state.sections(now: now)
        for (index, section) in sections.enumerated() {
            if index > 0 {
                submenu.addItem(.separator())
            }
            if let title = section.title {
                submenu.addItem(self.rateLimitSectionHeaderItem(self.t(title)))
            }
            for row in section.resourceRows {
                submenu.addItem(self.rateLimitResourceItem(row))
            }
        }

        return submenu
    }

    func actionItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        keyEquivalentModifierMask: NSEvent.ModifierFlags = .command,
        represented: Any? = nil,
        systemImage: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = keyEquivalent.isEmpty ? [] : keyEquivalentModifierMask
        item.target = self.target
        if let represented { item.representedObject = represented }
        if let systemImage, let image = self.cachedSystemImage(named: systemImage) {
            item.image = image
        }
        return item
    }

    func centeredActionItem(
        title: String,
        action: Selector,
        enabled: Bool
    ) -> NSMenuItem {
        let target = self.target
        return self.menuItemFactory.makeItem(
            for: MenuCenteredActionRowView(
                title: title,
                isEnabled: enabled,
                action: { [weak target] in
                    guard enabled else { return }

                    NSApp.sendAction(action, to: target, from: nil)
                }
            ),
            enabled: enabled,
            highlightable: enabled,
            target: self.target,
            action: action
        )
    }

    func cachedSystemImage(named name: String) -> NSImage? {
        let key = "\(name)|\(self.isLightAppearance ? "light" : "dark")"
        if let cached = self.systemImageCache[key] {
            return cached
        }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }

        image.size = NSSize(width: 14, height: 14)
        if name == "eye.slash", self.isLightAppearance {
            let config = NSImage.SymbolConfiguration(hierarchicalColor: .secondaryLabelColor)
            let tinted = image.withSymbolConfiguration(config)
            tinted?.isTemplate = false
            if let tinted {
                self.systemImageCache[key] = tinted
                return tinted
            }
        }
        image.isTemplate = true
        self.systemImageCache[key] = image
        return image
    }

    func viewItem(
        for content: some View,
        enabled: Bool,
        highlightable: Bool = false,
        submenu: NSMenu? = nil
    ) -> NSMenuItem {
        self.menuItemFactory.makeItem(
            for: content,
            enabled: enabled,
            highlightable: highlightable,
            showsSubmenuIndicator: submenu != nil,
            submenu: submenu,
            target: submenu != nil ? self.target : nil,
            action: submenu != nil ? #selector(self.target.menuItemNoOp(_:)) : nil
        )
    }
}
