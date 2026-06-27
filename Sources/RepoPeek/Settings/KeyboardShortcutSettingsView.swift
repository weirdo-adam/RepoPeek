import RepoPeekCore
import SwiftUI

struct KeyboardShortcutSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            Form {
                Section {
                    self.shortcutRow(
                        title: self.t("Refresh Now"),
                        systemImage: "arrow.clockwise",
                        shortcut: self.$session.settings.keyboardShortcuts.refreshNow
                    )

                    self.shortcutRow(
                        title: self.t("Issue Navigator"),
                        systemImage: "rectangle.and.text.magnifyingglass",
                        shortcut: self.$session.settings.keyboardShortcuts.issueNavigator
                    )
                } header: {
                    Text(self.t("Keyboard Shortcuts"))
                } footer: {
                    Text(self.t("Click a field, then press the shortcut. Delete clears it."))
                }
            }
            .formStyle(.grouped)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onChange(of: self.session.settings.keyboardShortcuts) { _, _ in
            self.appState.persistSettings()
            NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
        }
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }

    private func shortcutRow(title: String, systemImage: String, shortcut: Binding<MenuKeyboardShortcut>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Label {
                Text(title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }

            Spacer(minLength: 16)

            ShortcutRecorderView(
                shortcut: shortcut,
                noneLabel: self.t("None"),
                recordingLabel: self.t("Press shortcut"),
                clearLabel: self.t("Clear shortcut")
            )
            .fixedSize()
        }
    }
}
