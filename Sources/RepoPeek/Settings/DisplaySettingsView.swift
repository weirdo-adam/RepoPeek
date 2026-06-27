import RepoPeekCore
import SwiftUI

struct DisplaySettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(self.t("Customize the menu layout and repo submenu items."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) { self.resetToDefaults() } label: {
                    Text(self.t("Reset to Defaults"))
                }
                .buttonStyle(.bordered)
            }

            HStack(alignment: .top, spacing: 16) {
                self.mainMenuList()
                self.repoSubmenuList()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear { self.normalizeCustomization() }
    }

    private var mainMenuItems: [MainMenuItemID] {
        self.session.settings.menuCustomization.mainMenuOrder
    }

    private var repoSubmenuItems: [RepoSubmenuItemID] {
        self.session.settings.menuCustomization.repoSubmenuOrder
    }

    private func mainMenuList() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(self.t("Main Menu"))
                .font(.headline)
            List {
                ForEach(self.mainMenuItems, id: \.self) { item in
                    self.menuRow(
                        title: self.t(item.title),
                        subtitle: item.subtitle.map(self.t),
                        systemImage: item.systemImage,
                        isRequired: item.isRequired,
                        isVisible: self.mainMenuVisibility(for: item)
                    )
                }
                .onMove(perform: self.moveMainMenuItems)
            }
            .frame(minWidth: 230, maxWidth: .infinity, minHeight: 360)
        }
    }

    private func repoSubmenuList() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(self.t("Repo Submenu"))
                .font(.headline)
            List {
                ForEach(self.repoSubmenuItems, id: \.self) { item in
                    self.menuRow(
                        title: self.t(item.title),
                        subtitle: item.subtitle.map(self.t),
                        systemImage: nil,
                        isRequired: false,
                        isVisible: self.repoSubmenuVisibility(for: item)
                    )
                }
                .onMove(perform: self.moveRepoSubmenuItems)
            }
            .frame(minWidth: 230, maxWidth: .infinity, minHeight: 360)
        }
    }

    private func menuRow(
        title: String,
        subtitle: String?,
        systemImage: String?,
        isRequired: Bool,
        isVisible: Binding<Bool>
    ) -> some View {
        let effectiveSubtitle: String? = {
            if isRequired {
                if let subtitle, subtitle.isEmpty == false {
                    return self.format("Required · %@", subtitle)
                }
                return self.t("Required")
            }
            return subtitle
        }()

        return HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isVisible.wrappedValue ? .secondary : .tertiary)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(isVisible.wrappedValue ? .primary : .secondary)
                Text(effectiveSubtitle ?? " ")
                    .font(.caption)
                    .foregroundStyle(effectiveSubtitle == nil ? .clear : .secondary)
            }
            Spacer()
            Toggle(self.t("Visible"), isOn: isVisible)
                .labelsHidden()
                .disabled(isRequired)
        }
        .padding(.vertical, 3)
    }

    private func moveMainMenuItems(from offsets: IndexSet, to destination: Int) {
        var customization = self.session.settings.menuCustomization
        customization.mainMenuOrder.move(fromOffsets: offsets, toOffset: destination)
        self.updateCustomization(customization)
    }

    private func moveRepoSubmenuItems(from offsets: IndexSet, to destination: Int) {
        var customization = self.session.settings.menuCustomization
        customization.repoSubmenuOrder.move(fromOffsets: offsets, toOffset: destination)
        self.updateCustomization(customization)
    }

    private func mainMenuVisibility(for item: MainMenuItemID) -> Binding<Bool> {
        Binding(
            get: {
                if item.isRequired { return true }
                return !self.session.settings.menuCustomization.hiddenMainMenuItems.contains(item)
            },
            set: { isVisible in
                guard item.isRequired == false else { return }

                var customization = self.session.settings.menuCustomization
                if isVisible {
                    customization.hiddenMainMenuItems.remove(item)
                } else {
                    customization.hiddenMainMenuItems.insert(item)
                }
                self.updateCustomization(customization)
            }
        )
    }

    private func repoSubmenuVisibility(for item: RepoSubmenuItemID) -> Binding<Bool> {
        Binding(
            get: {
                !self.session.settings.menuCustomization.hiddenRepoSubmenuItems.contains(item)
            },
            set: { isVisible in
                var customization = self.session.settings.menuCustomization
                if isVisible {
                    customization.hiddenRepoSubmenuItems.remove(item)
                } else {
                    customization.hiddenRepoSubmenuItems.insert(item)
                }
                self.updateCustomization(customization)
            }
        )
    }

    private func updateCustomization(_ customization: MenuCustomization) {
        self.session.settings.menuCustomization = customization
        self.appState.persistSettings()
        self.appState.requestRefresh()
    }

    private func resetToDefaults() {
        self.updateCustomization(MenuCustomization())
    }

    private func normalizeCustomization() {
        var customization = self.session.settings.menuCustomization
        customization.normalize()
        if customization != self.session.settings.menuCustomization {
            self.updateCustomization(customization)
        }
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }

    private func format(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, settings: self.session.settings, arguments)
    }
}
