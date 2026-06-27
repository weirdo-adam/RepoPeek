import AppKit
import Logging
import OSLog
import RepoPeekCore

@MainActor
final class StatusBarMenuManager: NSObject, NSMenuDelegate {
    private static let minimumMainMenuItems = 3
    static let hiddenGitLabReferenceItemLength: CGFloat = 0
    static let gitLabReferenceMaxStatusItemLength: CGFloat = 360
    static let gitLabReferenceRepositoryTitleLimit = 30
    static let gitLabReferenceSummaryTitleLimit = 28
    private static let submenuWindowGap: CGFloat = 0
    private static let submenuWindowOverlapTolerance: CGFloat = 1
    static let statusIconRunningAnimationInterval: TimeInterval = 0.10
    static let statusIconActiveDirectionTickRange = 16 ... 32
    let appState: AppState
    let statusBar: NSStatusBar
    var mainMenu: NSMenu?
    var statusItem: NSStatusItem?
    var gitLabReferenceStatusItem: NSStatusItem?
    var gitLabReferenceMenu: NSMenu?
    lazy var menuBuilder = StatusBarMenuBuilder(appState: self.appState, target: self)
    private let menuItemFactory = MenuItemViewFactory()
    var statusIconAnimationTimer: Timer?
    var statusIconAnimationTimerInterval: TimeInterval?
    var statusIconAnimationKind: RepoPeekStatusIconKind?
    var statusIconAnimationFrame = 0
    var statusIconExpressionVariant = 0
    var statusIconDirection = RepoPeekStatusIconDirection.random()
    var statusIconActiveDirectionTicksRemaining = 16
    lazy var recentMenuService = RecentMenuService { [weak appState = self.appState] hostKey in
        guard let appState else { return GitLabClient() }

        return await appState.gitLabClient(forHostKey: hostKey)
    }

    private lazy var recentListCoordinator = RecentListMenuCoordinator(
        appState: self.appState,
        menuBuilder: self.menuBuilder,
        menuItemFactory: self.menuItemFactory,
        menuService: self.recentMenuService,
        actionHandler: self
    )
    lazy var localGitMenuCoordinator = LocalGitMenuCoordinator(
        appState: self.appState,
        menuBuilder: self.menuBuilder,
        menuItemFactory: self.menuItemFactory,
        recentMenuService: self.recentMenuService,
        actionHandler: self
    )
    lazy var changelogMenuCoordinator = ChangelogMenuCoordinator(
        appState: self.appState,
        menuBuilder: self.menuBuilder,
        menuItemFactory: self.menuItemFactory
    )
    lazy var activityMenuCoordinator = ActivityMenuCoordinator(
        appState: self.appState,
        menuBuilder: self.menuBuilder,
        actionHandler: self
    )
    private let signposter = OSSignposter(subsystem: "com.weirdoadam.repopeek", category: "menu")
    private let logger = RepoPeekLogging.logger("menu-state")
    private weak var menuResizeWindow: NSWindow?
    private var lastMainMenuWidth: CGFloat?
    private var lastMainMenuSignature: MenuBuildSignature?
    private var lastMainMenuWidthSignature: MenuBuildSignature?
    private var pendingMenuReopen = false
    var mainMenuKeyMonitor: Any?
    var lastHandledMainMenuKeyEventNumber: Int?
    var gitLabReferenceSyncTask: Task<Void, Never>?
    var gitLabReferenceMenuMatches: [GitLabReferenceMatch] = []
    private lazy var issueNavigatorWindowController = IssueNavigatorWindowController(appState: self.appState)
    var webURLBuilder: RepoWebURLBuilder {
        RepoWebURLBuilder(host: self.appState.session.settings.gitlabHost)
    }

    private weak var checkoutProgressWindow: NSWindow?

    init(appState: AppState, statusBar: NSStatusBar = .system) {
        self.appState = appState
        self.statusBar = statusBar
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.menuFiltersChanged),
            name: .menuFiltersDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.menuRepositoriesChanged),
            name: .menuRepositoriesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.menuRepositoriesChanged),
            name: .menuDiagnosticsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.recentListFiltersChanged),
            name: .recentListFiltersDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.gitLabReferenceMatchChanged),
            name: .gitLabReferenceMatchDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.openIssueNavigatorFromNotification(_:)),
            name: .issueNavigatorOpenRequested,
            object: nil
        )
    }

    func tearDownStatusItems() {
        self.stopStatusIconAnimation()
        self.gitLabReferenceSyncTask?.cancel()
        self.gitLabReferenceSyncTask = nil
        self.removeGitLabReferenceStatusItem()
        if let item = self.statusItem {
            item.menu = nil
            item.button?.image = nil
            item.button?.title = ""
            self.statusItem = nil
            self.statusBar.removeStatusItem(item)
        }
        self.mainMenu = nil
        self.auditStatusItems("tearDownStatusItems")
    }

    var isAttached: Bool {
        self.statusItem != nil
    }

    func ensureStatusItems() {
        if self.statusItem == nil {
            let item = self.statusBar.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "repopeek-main"
            item.isVisible = true
            item.button?.imageScaling = .scaleNone
            self.attachMainMenu(to: item)
        }

        self.syncGitLabReferenceStatusItem()
        self.auditStatusItems("ensureStatusItems")
    }

    func attachMainMenu(to statusItem: NSStatusItem) {
        let menu = self.mainMenu ?? self.menuBuilder.makeMainMenu()
        self.mainMenu = menu
        menu.delegate = self
        self.statusItem = statusItem
        statusItem.length = NSStatusItem.variableLength
        statusItem.menu = menu
        if let button = statusItem.button {
            button.isEnabled = true
            button.target = nil
            button.action = nil
        }
        self.applyStatusItemAppearance()
        DispatchQueue.main.async { [weak self] in
            self?.applyStatusItemAppearance()
        }
        self.prepareMainMenuIfNeeded(menu)
        self.logMenuEvent("attachMainMenu statusItem=\(self.objectID(statusItem)) menuItems=\(menu.items.count)")
    }

    func requestMenuReopenAfterClose() {
        self.pendingMenuReopen = true
    }

    // MARK: - Menu actions

    @objc func refreshNow() {
        self.appState.requestRefresh(cancelInFlight: true)
    }

    @objc func openPreferences() {
        SettingsOpener.shared.open()
    }

    @objc func openIssueNavigator() {
        self.openIssueNavigator(matches: [])
    }

    @objc private func openIssueNavigatorFromNotification(_ notification: Notification) {
        let matches = notification.object as? [GitLabReferenceMatch] ?? []
        self.openIssueNavigator(matches: matches)
    }

    private func openIssueNavigator(matches: [GitLabReferenceMatch]) {
        guard self.appState.session.account.isLoggedIn else {
            self.signIn()
            return
        }

        self.issueNavigatorWindowController.show(matches: matches)
    }

    @objc func openAbout() {
        self.appState.session.settingsSelectedTab = .about
        SettingsOpener.shared.open()
    }

    @objc func checkForUpdates() {
        SparkleController.shared.checkForUpdates()
    }

    @objc func menuFiltersChanged() {
        guard let menu = self.mainMenu else { return }

        // Defer menu rebuild to next run loop to avoid modifying menu during layout
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.recentListCoordinator.pruneMenus()
            self.appState.persistSettings()
            let plan = self.menuBuilder.mainMenuPlan()
            self.menuBuilder.populateMainMenu(menu, repos: plan.repos)
            self.lastMainMenuSignature = plan.signature
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            menu.update()
        }
    }

    func applyMainMenuRepoSearch(_ query: String) {
        guard let menu = self.mainMenu else { return }

        self.appState.session.menuRepoSearchQuery = query
        self.menuBuilder.applyRepoListVisibility(in: menu, query: query)
        self.menuBuilder.refreshMenuViewHeights(in: menu)
        menu.update()
    }

    @objc private func recentListFiltersChanged() {
        self.recentListCoordinator.handleFilterChanges()
    }

    private func applyStatusItemAppearance() {
        guard let button = self.statusItem?.button else { return }

        let statusKind = RepoPeekStatusIconKind.resolve(session: self.appState.session)
        self.syncStatusIconAnimation(for: statusKind)
        let displayKind = self.displayStatusIconKind(for: statusKind)
        let statusFrame = displayKind == .running ? self.statusIconAnimationFrame : 0
        self.setButtonImage(
            RepoPeekStatusIconRenderer.makeIcon(
                for: displayKind,
                frame: statusFrame,
                expressionVariant: self.statusIconExpressionVariant,
                direction: self.statusIconDirection
            ),
            for: button
        )
        let juice = RateLimitJuice(
            diagnostics: self.appState.session.rateLimitDiagnostics,
            cacheSummary: self.appState.session.rateLimitCacheSummary
        )
        if self.appState.session.settings.appearance.showRateLimitMeterInMenuBar,
           juice.hasData,
           let text = juice.compactRestText
        {
            self.setButtonTitle(text, for: button)
            button.toolTip = self.statusTooltip(kind: statusKind, juice: juice)
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            button.imageScaling = .scaleNone
        } else {
            self.setButtonTitle(nil, for: button)
            button.toolTip = self.statusTooltip(kind: statusKind, juice: nil)
            button.imageScaling = .scaleNone
        }
    }

    func auditStatusItems(_ context: String) {
        #if DEBUG
            let main = self.statusItem.map { self.objectID($0) } ?? "nil"
            let watcher = self.gitLabReferenceStatusItem.map { self.objectID($0) } ?? "nil"
            self.logMenuEvent("status item audit \(context) main=\(main) watcher=\(watcher)")
        #endif
    }

    @objc func toggleIssueLabelFilter(_ sender: NSMenuItem) {
        guard let label = sender.representedObject as? String else { return }

        self.recentListCoordinator.toggleIssueLabelFilter(label: label)
    }

    @objc func clearIssueLabelFilters() {
        self.recentListCoordinator.clearIssueLabelFilters()
    }

    func menuWillOpen(_ menu: NSMenu) {
        let signpost = self.signposter.beginInterval("menuWillOpen")
        defer { self.signposter.endInterval("menuWillOpen", signpost) }
        if self.prepareGitLabReferenceMenuIfNeeded(menu) { return }
        self.prepareMenuAppearance(menu)
        if self.recentListCoordinator.handleMenuWillOpen(menu) { return }
        if self.localGitMenuCoordinator.handleMenuWillOpen(menu) { return }
        if self.changelogMenuCoordinator.handleMenuWillOpen(menu) { return }
        self.prefetchChangelogIfNeeded(for: menu)
        if menu === self.mainMenu {
            self.startObservingMainMenuKeys()
            self.prepareMainMenuWillOpen(menu)
        } else {
            self.prepareSubmenuWillOpen(menu)
        }
    }

    private func prepareMenuAppearance(_ menu: NSMenu) {
        if menu === self.mainMenu {
            self.logMenuEvent("menuWillOpen mainMenu items=\(menu.items.count)")
        } else {
            self.logMenuEvent("menuWillOpen submenu items=\(menu.items.count)")
        }
        if let app = NSApp {
            menu.appearance = app.effectiveAppearance
        }
    }

    private func prepareGitLabReferenceMenuIfNeeded(_ menu: NSMenu) -> Bool {
        guard menu === self.gitLabReferenceMenu else { return false }

        self.logMenuEvent("menuWillOpen gitLabReferenceMenu items=\(menu.items.count)")
        self.refreshGitLabReferenceMenuIfNeeded(menu)
        self.preloadGitLabReferenceMenuPreviews(menu)
        return true
    }

    private func prefetchChangelogIfNeeded(for menu: NSMenu) {
        guard let fullName = self.menuBuilder.repoFullName(for: menu) else { return }

        let localPath = self.appState.session.localRepoIndex.status(forFullName: fullName)?.path
        let releaseTag = self.appState.session.repositories
            .first(where: { $0.fullName == fullName })?
            .latestRelease?
            .tag
        self.changelogMenuCoordinator.prefetchChangelog(
            fullName: fullName,
            localPath: localPath,
            releaseTag: releaseTag
        )
    }

    private func prepareMainMenuWillOpen(_ menu: NSMenu) {
        self.appState.reloadRateLimitCacheSummary()
        if menu.delegate == nil {
            menu.delegate = self
        }
        self.recentListCoordinator.pruneMenus()
        self.localGitMenuCoordinator.pruneMenus()
        self.changelogMenuCoordinator.pruneMenus()
        if self.appState.session.settings.appearance.showContributionHeader {
            if case let .loggedIn(user) = self.appState.session.account {
                Task { await self.appState.loadContributionHeatmapIfNeeded(for: user.username) }
            }
        }
        let plan = self.menuBuilder.mainMenuPlan()
        let isMenuTooSmall = menu.items.count < Self.minimumMainMenuItems
        if isMenuTooSmall {
            self.logMenuEvent("menuWillOpen mainMenu invalidating cache: items=\(menu.items.count)")
            self.lastMainMenuSignature = nil
        }
        let planDidRebuild = self.rebuildMainMenuIfNeeded(menu, plan: plan, isMenuTooSmall: isMenuTooSmall)
        self.refreshMainMenuMetricsAfterOpen(menu, plan: plan, didRebuildMenu: planDidRebuild)
    }

    private func rebuildMainMenuIfNeeded(_ menu: NSMenu, plan: MainMenuPlan, isMenuTooSmall: Bool) -> Bool {
        var didRebuildMenu = false
        if self.lastMainMenuSignature != plan.signature || menu.items.isEmpty || isMenuTooSmall {
            self.menuBuilder.populateMainMenu(menu, repos: plan.repos)
            self.lastMainMenuSignature = plan.signature
            didRebuildMenu = true
        }
        if didRebuildMenu {
            if let cachedWidth = self.lastMainMenuWidth {
                self.menuBuilder.refreshMenuViewHeights(in: menu, width: cachedWidth)
            } else {
                self.menuBuilder.refreshMenuViewHeights(in: menu)
            }
        }
        return didRebuildMenu
    }

    private func refreshMainMenuMetricsAfterOpen(_ menu: NSMenu, plan: MainMenuPlan, didRebuildMenu: Bool) {
        let shouldRecomputeWidth = self.lastMainMenuWidth == nil || self.lastMainMenuWidthSignature != plan.signature
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if shouldRecomputeWidth {
                let measuredWidth = self.menuBuilder.menuWidth(for: menu)
                let priorWidth = self.lastMainMenuWidth
                let shouldRemeasure = priorWidth == nil || abs(measuredWidth - (priorWidth ?? 0)) > 0.5
                self.lastMainMenuWidth = measuredWidth
                self.lastMainMenuWidthSignature = plan.signature
                if shouldRemeasure, didRebuildMenu {
                    self.menuBuilder.refreshMenuViewHeights(in: menu, width: measuredWidth)
                }
            }
            self.menuBuilder.clearHighlights(in: menu)
            self.startObservingMenuResize(for: menu)
        }
    }

    private func prepareSubmenuWillOpen(_ menu: NSMenu) {
        self.menuBuilder.refreshMenuViewHeights(in: menu)
        self.separateSubmenuWindowAfterOpen(menu)
        if let context = self.menuBuilder.repoContext(for: menu) {
            // Repo submenu opened; prefetch so nested recent lists appear instantly.
            self.recentListCoordinator.prefetchRecentLists(fullName: context.fullName, hostKey: context.hostKey)
            self.refreshRepoCommitPreviewIfNeeded(menu: menu, context: context)
        }
    }

    private func refreshRepoCommitPreviewIfNeeded(menu: NSMenu, context: RepoRecentMenuContext) {
        guard case .loggedIn = self.appState.session.account else { return }
        guard let (owner, name) = self.recentListCoordinator.ownerAndName(from: context.fullName),
              let descriptor = self.recentMenuService.descriptor(for: .commits)
        else { return }

        let now = Date()
        guard descriptor.needsRefresh(context.cacheKey, now, self.recentMenuService.cacheTTL) else {
            self.menuBuilder.refreshRepoSubmenu(menu, fullName: context.fullName)
            return
        }

        Task { @MainActor [weak self, weak menu] in
            guard let self, let menu else { return }

            do {
                _ = try await descriptor.load(
                    context.cacheKey,
                    context.hostKey,
                    owner,
                    name,
                    self.recentMenuService.listLimit
                )
                self.menuBuilder.refreshRepoSubmenu(menu, fullName: context.fullName)
            } catch is AsyncTimeoutError {
                await DiagnosticsLogger.shared.message("Recent commits timed out: \(context.fullName)")
                self.updateRepoCommitPreviewMessage(
                    in: menu,
                    fullName: context.fullName,
                    message: self.recentListCoordinator.timeoutMessage(timeout: self.recentMenuService.loadTimeout)
                )
            } catch {
                await DiagnosticsLogger.shared.message(
                    "Recent commits failed: \(context.fullName) error=\(error.localizedDescription)"
                )
                self.updateRepoCommitPreviewMessage(
                    in: menu,
                    fullName: context.fullName,
                    message: self.recentListCoordinator.failureMessage(for: error)
                )
            }
        }
    }

    private func updateRepoCommitPreviewMessage(in menu: NSMenu, fullName: String, message: String) {
        guard let item = menu.items.first(where: {
            guard let identifier = $0.representedObject as? RepoSubmenuRowIdentifier else { return false }

            return identifier.fullName == fullName && identifier.kind == .commits
        }) else { return }

        item.title = message
        menu.update()
    }

    private func separateSubmenuWindowAfterOpen(_ menu: NSMenu) {
        DispatchQueue.main.async { [weak self, weak menu] in
            guard let self, let menu else { return }

            self.separateSubmenuWindow(menu)
        }
    }

    private func separateSubmenuWindow(_ menu: NSMenu) {
        guard let submenuWindow = menu.items.compactMap(\.view?.window).first,
              let parentItem = menu.supermenu?.items.first(where: { $0.submenu === menu }),
              let parentWindow = parentItem.view?.window ?? menu.supermenu?.items
              .compactMap(\.view?.window)
              .first(where: { $0 !== submenuWindow })
        else {
            return
        }

        let parentFrame = parentWindow.frame
        var submenuFrame = submenuWindow.frame
        let overlap = min(submenuFrame.maxX, parentFrame.maxX) - max(submenuFrame.minX, parentFrame.minX)
        guard overlap > Self.submenuWindowOverlapTolerance else { return }

        let visibleFrame = submenuWindow.screen?.visibleFrame
            ?? parentWindow.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? parentFrame.union(submenuFrame)
        let opensLeft = submenuFrame.midX < parentFrame.midX
        let leftX = parentFrame.minX - submenuFrame.width - Self.submenuWindowGap
        let rightX = parentFrame.maxX + Self.submenuWindowGap
        let leftFits = leftX >= visibleFrame.minX
        let rightFits = rightX + submenuFrame.width <= visibleFrame.maxX

        if opensLeft {
            submenuFrame.origin.x = leftFits || !rightFits
                ? max(leftX, visibleFrame.minX)
                : rightX
        } else {
            submenuFrame.origin.x = rightFits || !leftFits
                ? min(rightX, visibleFrame.maxX - submenuFrame.width)
                : leftX
        }

        submenuWindow.setFrame(submenuFrame, display: true, animate: false)
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === self.gitLabReferenceMenu {
            self.unloadGitLabReferenceMenuPreviews(menu)
            self.gitLabReferenceStatusItem?.menu = nil
        } else if menu === self.mainMenu {
            let shouldReopen = self.pendingMenuReopen
            self.pendingMenuReopen = false
            self.menuBuilder.clearHighlights(in: menu)
            self.stopObservingMenuResize()
            self.stopObservingMainMenuKeys()
            self.lastHandledMainMenuKeyEventNumber = nil
            self.logMenuEvent("menuDidClose mainMenu")
            if shouldReopen {
                self.reopenMainMenu()
            }
        }
    }

    private func reopenMainMenu() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            self.statusItem?.button?.performClick(nil)
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for menuItem in menu.items {
            guard let view = menuItem.view as? MenuItemHighlighting else { continue }

            let highlighted = menuItem == item && menuItem.isEnabled
            view.setHighlighted(highlighted)
        }
    }

    func registerLocalBranchMenu(_ menu: NSMenu, repoPath: URL, fullName: String, localStatus: LocalRepoStatus) {
        self.localGitMenuCoordinator.registerLocalBranchMenu(menu, repoPath: repoPath, fullName: fullName, localStatus: localStatus)
    }

    func registerCombinedBranchMenu(_ menu: NSMenu, repoPath: URL, fullName: String, localStatus: LocalRepoStatus) {
        self.localGitMenuCoordinator.registerCombinedBranchMenu(menu, repoPath: repoPath, fullName: fullName, localStatus: localStatus)
    }

    func registerLocalWorktreeMenu(_ menu: NSMenu, repoPath: URL, fullName: String) {
        self.localGitMenuCoordinator.registerLocalWorktreeMenu(menu, repoPath: repoPath, fullName: fullName)
    }

    func registerChangelogMenu(_ menu: NSMenu, fullName: String, localStatus: LocalRepoStatus?) {
        self.changelogMenuCoordinator.registerChangelogMenu(menu, fullName: fullName, localStatus: localStatus)
    }

    func cachedChangelogPresentation(fullName: String, releaseTag: String?) -> ChangelogRowPresentation? {
        self.changelogMenuCoordinator.cachedPresentation(fullName: fullName, releaseTag: releaseTag)
    }

    func cachedChangelogHeadline(fullName: String) -> String? {
        self.changelogMenuCoordinator.cachedHeadline(fullName: fullName)
    }

    func cloneURL(for fullName: String, context: RepoMenuActionContext? = nil) -> URL? {
        let builder = context.map(self.webURLBuilder(for:)) ?? self.webURLBuilder(forFullName: fullName)
        guard var url = builder.repoURL(fullName: fullName) else { return nil }

        url.appendPathExtension("git")
        return url
    }

    func showCheckoutProgress(fullName: String, destination: URL) {
        self.closeCheckoutProgress()
        let alert = NSAlert()
        alert.messageText = "Checking out \(fullName)"
        alert.informativeText = PathFormatter.displayString(destination.path)

        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.startAnimation(nil)

        let stack = NSStackView(views: [indicator])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        alert.accessoryView = stack

        let window = alert.window
        window.level = .floating
        self.checkoutProgressWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeCheckoutProgress() {
        self.checkoutProgressWindow?.close()
        self.checkoutProgressWindow = nil
    }

    func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func startObservingMenuResize(for menu: NSMenu) {
        self.stopObservingMenuResize()
        guard let window = menu.items.compactMap(\.view).first?.window else { return }

        self.menuResizeWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.menuWindowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    private func stopObservingMenuResize() {
        guard let window = self.menuResizeWindow else { return }

        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: window)
        self.menuResizeWindow = nil
    }

    @objc private func menuWindowDidResize(_: Notification) {
        guard let menu = self.mainMenu else { return }

        let width = self.menuBuilder.menuWidth(for: menu)
        self.lastMainMenuWidth = width
        self.menuBuilder.refreshMenuViewHeights(in: menu, width: width)
        menu.update()
    }

    private func logMenuEvent(_ message: String) {
        self.logger.info("\(message)")
        self.appendClickDiagnostic(message)
        Task { await DiagnosticsLogger.shared.message(message) }
    }

    private func appendClickDiagnostic(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let url = URL(fileURLWithPath: "/tmp/repopeek-clicks.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }

        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        _ = try? handle.write(contentsOf: data)
    }

    private func prepareMainMenuIfNeeded(_ menu: NSMenu) {
        let isMenuTooSmall = menu.items.count < Self.minimumMainMenuItems
        if self.lastMainMenuSignature == nil || menu.items.isEmpty || isMenuTooSmall {
            self.appState.reloadRateLimitCacheSummary()
            let plan = self.menuBuilder.mainMenuPlan()
            self.menuBuilder.populateMainMenu(menu, repos: plan.repos)
            self.lastMainMenuSignature = plan.signature
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            menu.update()
        }
    }

    private func objectID(_ object: AnyObject?) -> String {
        guard let object else { return "nil" }

        return String(ObjectIdentifier(object).hashValue)
    }

    func registerRecentListMenu(_ menu: NSMenu, context: RepoRecentMenuContext) {
        self.recentListCoordinator.registerRecentListMenu(menu, context: context)
    }

    func cachedRecentCommitCount(cacheKey: String) -> Int? {
        self.recentListCoordinator.cachedRecentCommitCount(cacheKey: cacheKey)
    }

    func repoModel(from sender: NSMenuItem) -> RepositoryDisplayModel? {
        let context = self.repoActionContext(from: sender)
        guard let fullName = context?.fullName ?? self.repoFullName(from: sender) else { return nil }

        let normalized = fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let repo = if let lookupKey = context?.lookupKey?.lowercased() {
            self.appState.session.repositories.first(where: { $0.lookupKey == lookupKey || $0.id.lowercased() == lookupKey })
        } else {
            self.appState.session.repositories.first(where: { $0.fullName.lowercased() == normalized })
        }
        guard let repo else { return nil }

        let local = self.appState.session.localRepoIndex.status(forFullName: fullName)
        return RepositoryDisplayModel(repo: repo, localStatus: local)
    }

    func repoFullName(from sender: NSMenuItem) -> String? {
        if let context = sender.representedObject as? RepoMenuActionContext {
            return context.fullName
        }

        return sender.representedObject as? String
    }

    func repoActionContext(from sender: NSMenuItem) -> RepoMenuActionContext? {
        sender.representedObject as? RepoMenuActionContext
    }

    func openRepoPath(sender: NSMenuItem, path: String) {
        guard let fullName = self.repoFullName(from: sender) else { return }

        let builder = self.repoActionContext(from: sender).map(self.webURLBuilder(for:))
            ?? self.webURLBuilder(forFullName: fullName)
        guard let url = builder.repoPathURL(fullName: fullName, path: path) else { return }

        self.open(url: url)
    }

    func webURLBuilder(forFullName fullName: String) -> RepoWebURLBuilder {
        if let host = self.appState.session.localRepoIndex.status(forFullName: fullName)?.remoteWebURLHost {
            return RepoWebURLBuilder(host: host)
        }
        let normalizedFullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let repo = self.appState.session.repositories.first(where: { $0.fullName.lowercased() == normalizedFullName }) {
            if let hostKey = repo.identity?.host {
                if let host = self.appState.hostURL(forHostKey: hostKey) {
                    return RepoWebURLBuilder(host: host)
                }
            }
        }
        return self.webURLBuilder
    }

    func webURLBuilder(for context: RepoMenuActionContext) -> RepoWebURLBuilder {
        if let lookupKey = context.lookupKey?.lowercased(),
           let repo = self.appState.session.repositories.first(where: {
               $0.lookupKey == lookupKey || $0.id.lowercased() == lookupKey
           }),
           let hostKey = repo.identity?.host,
           let host = self.appState.hostURL(forHostKey: hostKey)
        {
            return RepoWebURLBuilder(host: host)
        }

        return self.webURLBuilder(forFullName: context.fullName)
    }

    func open(url: URL) {
        SecurityScopedBookmark.withAccess(
            to: url,
            rootBookmarkData: self.appState.session.settings.localProjects.rootBookmarkData
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openGitLabReferenceMatch(_ sender: Any?) {
        let representedURL = (sender as? NSMenuItem)?.representedObject as? URL
        guard let url = representedURL ?? self.appState.session.gitLabReferenceMatch?.url else {
            self.logMenuEvent("GitLab reference click ignored: no URL")
            return
        }

        self.logMenuEvent("GitLab reference click open url=\(url.absoluteString)")
        self.open(url: url)
    }

    @objc func copyGitLabReferenceURL(_ sender: Any?) {
        let representedURL = (sender as? NSMenuItem)?.representedObject as? URL
        guard let url = representedURL ?? self.appState.session.gitLabReferenceMatch?.url else {
            self.logMenuEvent("GitLab reference copy ignored: no URL")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        self.logMenuEvent("GitLab reference copied url=\(url.absoluteString)")
    }

    @objc func menuItemNoOp(_: NSMenuItem) {}
}

#if DEBUG
    extension StatusBarMenuManager {
        func setMainMenuForTesting(_ menu: NSMenu) {
            self.mainMenu = menu
        }

        func mainMenuPlanForTesting(now: Date = Date()) -> MainMenuPlan {
            self.menuBuilder.mainMenuPlan(now: now)
        }

        func populateMainMenuForTesting(_ menu: NSMenu, repos: [RepositoryDisplayModel]) {
            self.menuBuilder.populateMainMenu(menu, repos: repos)
        }

        func makeLocalWorktreeMenuItemForTesting(
            _ model: LocalRefMenuRowViewModel,
            path: URL,
            fullName: String
        ) -> NSMenuItem {
            self.localGitMenuCoordinator.makeLocalWorktreeMenuItemForTesting(model, path: path, fullName: fullName)
        }

        func isWorktreeMenuItemForTesting(_ item: NSMenuItem) -> Bool {
            self.localGitMenuCoordinator.isWorktreeMenuItemForTesting(item)
        }

        func isRecentListMenu(_ menu: NSMenu) -> Bool {
            self.recentListCoordinator.containsMenuForTesting(menu)
        }

        func syncGitLabReferenceStatusItemForTesting() {
            self.syncGitLabReferenceStatusItem()
        }

        func gitLabReferenceStatusItemForTesting() -> NSStatusItem? {
            self.gitLabReferenceStatusItem
        }

        func gitLabReferenceMenuForTesting() -> NSMenu? {
            self.gitLabReferenceMenu
        }

        func populateGitLabReferenceMenuForTesting(_ menu: NSMenu, matches: [GitLabReferenceMatch]) {
            self.populateGitLabReferenceMenu(menu, matches: matches)
        }

        func statusIconAnimationIntervalForTesting(kind: RepoPeekStatusIconKind) -> TimeInterval {
            self.statusIconAnimationInterval(for: kind)
        }
    }
#endif

extension StatusBarMenuManager {
    func preloadIssueNavigatorPreviewForCurrentGitLabReferences() {
        self.issueNavigatorWindowController.preloadFirstPreview(
            for: self.appState.session.gitLabReferenceMatches
        )
    }

    @objc func openGitLabReferenceMatchesInIssueNavigator() {
        guard self.appState.session.account.isLoggedIn else {
            self.signIn()
            return
        }

        let matches = self.appState.session.gitLabReferenceMatches
        guard matches.isEmpty == false else {
            self.openIssueNavigator()
            return
        }

        self.openIssueNavigator(matches: matches)
    }
}

extension StatusBarMenuManager {
    func setButtonImage(_ image: NSImage, for button: NSStatusBarButton) {
        if button.image === image { return }
        button.image = image
    }

    func setButtonTitle(_ title: String?, for button: NSStatusBarButton) {
        let rawValue = title ?? ""
        let value = rawValue.isEmpty || button.image == nil ? rawValue : " \(rawValue)"
        if button.title != value {
            button.title = value
        }
        let position: NSControl.ImagePosition = value.isEmpty ? .imageOnly : .imageLeft
        if button.imagePosition != position {
            button.imagePosition = position
        }
    }

    func rateLimitTooltip(juice: RateLimitJuice) -> String {
        let rest = self.rateLimitTooltipPart(label: "REST", remaining: juice.restRemaining, limit: juice.restLimit)
        return "\(RepoPeekProductConstants.displayName) rate limits: \(rest)"
    }

    private func statusTooltip(kind: RepoPeekStatusIconKind, juice: RateLimitJuice?) -> String {
        var tooltip = "\(RepoPeekProductConstants.displayName): \(kind.tooltip)"
        if let juice {
            tooltip += "\n\(self.rateLimitTooltip(juice: juice))"
        }
        return tooltip
    }

    func rateLimitTooltipPart(label: String, remaining: Int?, limit: Int?) -> String {
        if let remaining, let limit {
            return "\(label) \(remaining)/\(limit)"
        }
        if let remaining {
            return "\(label) \(remaining) left"
        }
        return "\(label) unknown"
    }
}

extension StatusBarMenuManager {
    @objc func menuRepositoriesChanged() {
        guard let menu = self.mainMenu else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.applyStatusItemAppearance()
            let plan = self.menuBuilder.mainMenuPlan()
            guard self.lastMainMenuSignature != plan.signature else { return }

            self.recentListCoordinator.pruneMenus()
            self.localGitMenuCoordinator.pruneMenus()
            self.changelogMenuCoordinator.pruneMenus()
            self.menuBuilder.populateMainMenu(menu, repos: plan.repos)
            self.lastMainMenuSignature = plan.signature
            self.lastMainMenuWidthSignature = nil
            if let width = self.lastMainMenuWidth {
                self.menuBuilder.refreshMenuViewHeights(in: menu, width: width)
            } else {
                self.menuBuilder.refreshMenuViewHeights(in: menu)
            }
            menu.update()
        }
    }
}
