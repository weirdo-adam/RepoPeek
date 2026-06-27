import AppKit
import RepoPeekCore
import SwiftUI

struct SettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    var body: some View {
        TabView(selection: self.$session.settingsSelectedTab) {
            GeneralSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label(self.t("General"), systemImage: "gear") }
                .tag(SettingsTab.general)
            KeyboardShortcutSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label(self.t("Shortcuts"), systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            DisplaySettingsView(session: self.session, appState: self.appState)
                .tabItem { Label(self.t("Display"), systemImage: "rectangle.3.group") }
                .tag(SettingsTab.display)
            RepoSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label(self.t("Repositories"), systemImage: "tray.full") }
                .tag(SettingsTab.repositories)
            AccountSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label(self.t("Accounts"), systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
            NotificationSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label(self.t("Notifications"), systemImage: "bell.badge") }
                .tag(SettingsTab.notifications)
            AdvancedSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label(self.t("Advanced"), systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.advanced)
            #if DEBUG
                if self.session.settings.debugPaneEnabled {
                    DebugSettingsView(session: self.session, appState: self.appState)
                        .tabItem { Label(self.t("Debug"), systemImage: "ant.fill") }
                        .tag(SettingsTab.debug)
                }
            #endif
            AboutSettingsView(language: self.session.settings.language)
                .tabItem { Label(self.t("About"), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .tabViewStyle(.automatic)
        .environment(\.locale, Locale(identifier: L10n.localeIdentifier(for: self.session.settings.language)))
        .frame(
            minWidth: SettingsTab.windowWidth,
            maxWidth: .infinity,
            minHeight: SettingsTab.windowHeight,
            maxHeight: .infinity
        )
        .background(SettingsWindowConfigurator())
        .onChange(of: self.session.settings.debugPaneEnabled) { _, enabled in
            #if DEBUG
                if !enabled, self.session.settingsSelectedTab == .debug {
                    self.session.settingsSelectedTab = .general
                }
            #endif
        }
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        SettingsWindowConfigurationView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        (nsView as? SettingsWindowConfigurationView)?.configureWindow()
    }
}

private final class SettingsWindowConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.configureWindow()
    }

    func configureWindow() {
        guard let window else { return }

        window.styleMask.insert(.resizable)
        window.contentMinSize = NSSize(
            width: SettingsTab.windowWidth,
            height: SettingsTab.windowHeight
        )
        window.contentMaxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        DispatchQueue.main.async {
            guard let window = self.window else { return }

            window.styleMask.insert(.resizable)
            window.standardWindowButton(.zoomButton)?.isEnabled = true
        }
    }
}
