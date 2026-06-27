import AppKit
import Kingfisher
import RepoPeekCore
import SwiftUI
import UserNotifications

@main
struct RepoPeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    @State private var appState: AppState
    private let menuManager: StatusBarMenuManager

    init() {
        let appState = AppState()
        let menuManager = StatusBarMenuManager(appState: appState)
        self._appState = State(wrappedValue: appState)
        self.menuManager = menuManager
        self.appDelegate.configure(menuManager: menuManager)
    }

    @SceneBuilder
    var body: some Scene {
        WindowGroup("RepoPeekLifecycleKeepalive") {
            RepoPeekLifecycleKeepaliveView()
        }
        .defaultSize(width: 20, height: 20)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView(session: self.appState.session, appState: self.appState)
        }
        .defaultSize(width: SettingsTab.windowWidth, height: SettingsTab.windowHeight)
        .windowResizability(.contentMinSize)
    }
}

private struct RepoPeekLifecycleKeepaliveView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 20, height: 20)
            .onAppear {
                SettingsOpener.shared.configure {
                    self.openSettings()
                }
                if let window = NSApp.windows.first(where: { $0.title == "RepoPeekLifecycleKeepalive" }) {
                    window.styleMask = [.borderless]
                    window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient, .canJoinAllSpaces]
                    window.isExcludedFromWindowsMenu = true
                    window.level = .floating
                    window.isOpaque = false
                    window.alphaValue = 0
                    window.backgroundColor = .clear
                    window.hasShadow = false
                    window.ignoresMouseEvents = true
                    window.canHide = false
                    window.setContentSize(NSSize(width: 1, height: 1))
                    window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
                }
            }
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuManager: StatusBarMenuManager?
    private var suppressIssueNavigatorReopenUntil: Date?

    func configure(menuManager: StatusBarMenuManager) {
        self.menuManager = menuManager
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard ensureSingleInstance() else {
            NSApp.terminate(nil)
            return
        }

        configureImagePipeline()
        UNUserNotificationCenter.current().delegate = RepoPeekNotificationResponseHandler.shared
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.notificationBrowserOpenRequested),
            name: .notificationBrowserOpenRequested,
            object: nil
        )
        self.menuManager?.ensureStatusItems()
    }

    func applicationWillTerminate(_: Notification) {
        self.menuManager?.tearDownStatusItems()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ application: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        if let suppressIssueNavigatorReopenUntil, Date() < suppressIssueNavigatorReopenUntil {
            return false
        }
        self.suppressIssueNavigatorReopenUntil = nil

        let visibleUserWindows = application.windows.filter {
            $0.isVisible && !$0.isExcludedFromWindowsMenu && $0.alphaValue > 0
        }
        if visibleUserWindows.isEmpty == false {
            application.activate(ignoringOtherApps: true)
            visibleUserWindows.forEach { $0.makeKeyAndOrderFront(nil) }
        }
        return false
    }

    @objc private func notificationBrowserOpenRequested() {
        self.suppressIssueNavigatorReopenUntil = Date().addingTimeInterval(2)
    }
}

extension AppDelegate {
    /// Prevent multiple instances when LS UI flag is unavailable under SwiftPM.
    private func ensureSingleInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }

        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && !$0.isEqual(NSRunningApplication.current)
        }
        return others.isEmpty
    }

    private func configureImagePipeline() {
        let cache = ImageCache(name: "RepoPeekAvatars")
        cache.memoryStorage.config.totalCostLimit = 64 * 1024 * 1024
        cache.diskStorage.config.sizeLimit = 64 * 1024 * 1024
        KingfisherManager.shared.cache = cache
    }
}
