import AppKit
import RepoPeekCore
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    private var normalizedCurrentUsername: String? {
        guard case let .loggedIn(user) = self.session.account else { return nil }

        return user.username.lowercased()
    }

    private var showOnlyMyRepos: Bool {
        guard let username = self.normalizedCurrentUsername else { return false }

        return OwnerFilter.normalize(self.session.settings.repoList.ownerFilter) == [username]
    }

    private func toggleShowOnlyMyRepos(_ enabled: Bool) {
        guard let username = self.normalizedCurrentUsername else { return }

        self.session.settings.repoList.ownerFilter = enabled ? [username] : []

        self.appState.persistSettings()
        self.appState.requestRefresh(cancelInFlight: true)
    }

    var body: some View {
        VStack(spacing: 12) {
            Form {
                Section {
                    Toggle(self.t("Launch at login"), isOn: self.$session.settings.launchAtLogin)
                        .onChange(of: self.session.settings.launchAtLogin) { _, value in
                            LaunchAtLoginHelper.set(enabled: value)
                            self.appState.persistSettings()
                        }
                    Picker(self.t("Language"), selection: self.$session.settings.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(L10n.label(for: language, settings: self.session.settings)).tag(language)
                        }
                    }
                    .onChange(of: self.session.settings.language) { _, _ in
                        self.appState.persistSettings()
                        NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
                    }
                } footer: {
                    Text(self.t("Automatically opens RepoPeek when you start your Mac."))
                }

                Section {
                    Toggle(self.t("Show contribution header"), isOn: self.$session.settings.appearance.showContributionHeader)
                        .onChange(of: self.session.settings.appearance.showContributionHeader) { _, _ in
                            self.appState.persistSettings()
                        }
                    Toggle(self.t("Show GitLab rate-limit count in menu bar"), isOn: self.$session.settings.appearance.showRateLimitMeterInMenuBar)
                        .onChange(of: self.session.settings.appearance.showRateLimitMeterInMenuBar) { _, _ in
                            self.appState.persistSettings()
                            NotificationCenter.default.post(name: .menuDiagnosticsDidChange, object: nil)
                        }
                    LabeledContent(self.t("Status icon expression")) {
                        HStack(spacing: 6) {
                            RepositoryDisplayLimitControl(
                                value: self.statusIconExpressionIntervalBinding,
                                range: AppearanceSettings.minimumStatusIconExpressionIntervalSeconds ... AppearanceSettings.maximumStatusIconExpressionIntervalSeconds,
                                decrementLabel: self.t("Change expression less often"),
                                incrementLabel: self.t("Change expression more often")
                            )
                            Text(self.t("sec."))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .help(self.t("Controls how often idle menu bar icon expressions change."))
                    Picker(self.t("Activity feed"), selection: self.$session.settings.appearance.activityScope) {
                        ForEach(GlobalActivityScope.allCases, id: \.self) { scope in
                            Text(self.t(scope.label)).tag(scope)
                        }
                    }
                    .onChange(of: self.session.settings.appearance.activityScope) { _, _ in
                        self.appState.persistSettings()
                        self.appState.requestRefresh()
                    }
                    Picker(self.t("Repository heatmap"), selection: self.$session.settings.heatmap.display) {
                        ForEach(HeatmapDisplay.allCases, id: \.self) { display in
                            Text(self.t(display.label)).tag(display)
                        }
                    }
                    .onChange(of: self.session.settings.heatmap.display) { _, _ in
                        self.appState.persistSettings()
                    }
                    Picker(self.t("Heatmap window"), selection: self.$session.settings.heatmap.span) {
                        ForEach(HeatmapSpan.allCases, id: \.self) { span in
                            Text(self.t(span.label)).tag(span)
                        }
                    }
                    .onChange(of: self.session.settings.heatmap.span) { _, _ in
                        self.appState.persistSettings()
                        self.appState.updateHeatmapRange(now: Date())
                    }
                } header: {
                    Text(self.t("Display"))
                } footer: {
                    Text(self.t("Repository heatmaps show recent commit activity for each repository."))
                }

                Section {
                    LabeledContent(self.t("Repositories shown")) {
                        RepositoryDisplayLimitControl(
                            value: self.repoDisplayLimitBinding,
                            range: AppLimits.MainMenu.minimumRepositoryDisplayLimit ... AppLimits.MainMenu.maximumRepositoryDisplayLimit,
                            decrementLabel: self.t("Show fewer repositories"),
                            incrementLabel: self.t("Show more repositories")
                        )
                    }
                    Picker(self.t("Menu sort"), selection: self.$session.settings.repoList.menuSortKey) {
                        ForEach(RepositorySortKey.settingsCases, id: \.self) { sortKey in
                            Text(self.t(sortKey.settingsLabel)).tag(sortKey)
                        }
                    }
                    .onChange(of: self.session.settings.repoList.menuSortKey) { _, _ in
                        self.appState.persistSettings()
                    }
                    Toggle(self.t("Include forked repositories"), isOn: self.$session.settings.repoList.showForks)
                        .onChange(of: self.session.settings.repoList.showForks) { _, _ in
                            self.appState.persistSettings()
                            self.appState.requestRefresh(cancelInFlight: true)
                        }
                    Toggle(self.t("Include archived repositories"), isOn: self.$session.settings.repoList.showArchived)
                        .onChange(of: self.session.settings.repoList.showArchived) { _, _ in
                            self.appState.persistSettings()
                            self.appState.requestRefresh(cancelInFlight: true)
                        }
                    Toggle(self.t("Show only my repositories"), isOn: Binding(
                        get: { self.showOnlyMyRepos },
                        set: { self.toggleShowOnlyMyRepos($0) }
                    ))
                    .disabled(self.normalizedCurrentUsername == nil)
                } header: {
                    Text(self.t("Repositories"))
                } footer: {
                    Text(self.t("Filters apply to repo lists and search. 'Show only my repositories' hides repos owned by organizations and other users."))
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(self.t("Quit RepoPeek")) { NSApp.terminate(nil) }
            }
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }

    private var repoDisplayLimitBinding: Binding<Int> {
        Binding(
            get: { self.session.settings.repoList.displayLimit },
            set: { newValue in
                self.session.settings.repoList.displayLimit = min(
                    max(newValue, AppLimits.MainMenu.minimumRepositoryDisplayLimit),
                    AppLimits.MainMenu.maximumRepositoryDisplayLimit
                )
                self.appState.persistSettings()
                NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
            }
        )
    }

    private var statusIconExpressionIntervalBinding: Binding<Int> {
        Binding(
            get: { self.session.settings.appearance.statusIconExpressionIntervalSeconds },
            set: { newValue in
                let clampedValue = AppearanceSettings.clampedStatusIconExpressionIntervalSeconds(newValue)
                guard self.session.settings.appearance.statusIconExpressionIntervalSeconds != clampedValue else { return }

                self.session.settings.appearance.statusIconExpressionIntervalSeconds = clampedValue
                self.appState.persistSettings()
                NotificationCenter.default.post(name: .menuDiagnosticsDidChange, object: nil)
            }
        )
    }
}

private struct RepositoryDisplayLimitControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let decrementLabel: String
    let incrementLabel: String
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 0) {
            self.iconButton(systemName: "minus", label: self.decrementLabel) {
                self.update(self.value - 1)
            }
            .disabled(self.value <= self.range.lowerBound)

            Divider()
                .frame(height: 18)

            TextField("", text: self.$draft)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .rounded).monospacedDigit().weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(width: 42, height: 28)
                .focused(self.$isEditing)
                .onSubmit(self.commitDraft)

            Divider()
                .frame(height: 18)

            self.iconButton(systemName: "plus", label: self.incrementLabel) {
                self.update(self.value + 1)
            }
            .disabled(self.value >= self.range.upperBound)
        }
        .frame(height: 30)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
        }
        .fixedSize()
        .onAppear {
            self.draft = "\(self.value)"
        }
        .onChange(of: self.value) { _, newValue in
            guard !self.isEditing else { return }

            self.draft = "\(newValue)"
        }
        .onChange(of: self.isEditing) { _, isEditing in
            if !isEditing {
                self.commitDraft()
            }
        }
    }

    private func iconButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func commitDraft() {
        let parsed = Int(self.draft.trimmingCharacters(in: .whitespacesAndNewlines)) ?? self.value
        self.update(parsed)
    }

    private func update(_ newValue: Int) {
        let clamped = min(max(newValue, self.range.lowerBound), self.range.upperBound)
        self.value = clamped
        self.draft = "\(clamped)"
    }
}
