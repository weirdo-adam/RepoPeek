import AppKit
import RepoPeekCore
import SwiftUI

struct AdvancedSettingsView: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var openAIAPIKey = ""
    @State private var openAIKeySource: OpenAIAPIKeySource = .missing
    @State private var openAIKeyMessage: String?
    @State private var aiRequestURLText = ""
    @State private var aiRequestURLMessage: String?

    var body: some View {
        Form {
            Section {
                Picker(self.t("Refresh interval"), selection: self.$session.settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases, id: \.self) { interval in
                        Text(self.t(interval.label)).tag(interval)
                    }
                }
                .onChange(of: self.session.settings.refreshInterval) { _, newValue in
                    LaunchAtLoginHelper.set(enabled: self.session.settings.launchAtLogin)
                    self.appState.persistSettings()
                    Task { @MainActor in
                        self.appState.refreshScheduler.configure(interval: newValue.seconds) { [weak appState] in
                            appState?.requestRefresh()
                        }
                    }
                }
            } header: {
                Text(self.t("Refresh"))
            } footer: {
                Text(self.t("Controls how often RepoPeek refreshes GitLab data."))
            }

            Section {
                LabeledContent(self.t("Project folder")) {
                    HStack(spacing: 8) {
                        Text(self.projectFolderLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(self.projectFolderLabelColor)
                        Button(self.t("Choose…")) { self.pickProjectFolder() }
                        if self.session.settings.localProjects.rootPath != nil {
                            Button {
                                self.appState.refreshLocalProjects(forceRescan: true)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help(self.t("Rescan local projects"))
                            Button {
                                self.clearProjectFolder()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(self.t("Clear project folder"))
                        }
                    }
                }

                if let summary = self.localRepoSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(self.t("Auto-sync clean repos"), isOn: self.$session.settings.localProjects.autoSyncEnabled)
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                    .onChange(of: self.session.settings.localProjects.autoSyncEnabled) { _, _ in
                        self.appState.persistSettings()
                        self.appState.refreshLocalProjects()
                        self.appState.requestRefresh(cancelInFlight: true)
                    }

                Toggle(self.t("Show dirty files in menu"), isOn: self.$session.settings.localProjects.showDirtyFilesInMenu)
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                    .onChange(of: self.session.settings.localProjects.showDirtyFilesInMenu) { _, _ in
                        self.appState.persistSettings()
                        NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
                    }

                HStack {
                    Text(self.t("Worktree folder"))
                    Spacer()
                    TextField("", text: self.worktreeFolderBinding)
                        .frame(width: 120)
                        .multilineTextAlignment(.trailing)
                        .disabled(self.session.settings.localProjects.rootPath == nil)
                }

                HStack {
                    Text(self.t("Fetch interval"))
                    Spacer()
                    Picker("", selection: self.$session.settings.localProjects.fetchInterval) {
                        ForEach(LocalProjectsRefreshInterval.allCases, id: \.self) { interval in
                            Text(self.t(interval.label)).tag(interval)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                    .onChange(of: self.session.settings.localProjects.fetchInterval) { _, _ in
                        self.appState.persistSettings()
                        self.appState.refreshLocalProjects()
                    }
                }

                HStack {
                    Text(self.t("Scan depth"))
                    Spacer()
                    Picker("", selection: self.$session.settings.localProjects.maxDepth) {
                        ForEach(1 ... 6, id: \.self) { depth in
                            Text(self.depthLabel(depth))
                                .tag(depth)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                    .onChange(of: self.session.settings.localProjects.maxDepth) { _, _ in
                        self.appState.persistSettings()
                        self.appState.refreshLocalProjects(forceRescan: true)
                    }
                }

                HStack {
                    Text(self.t("Preferred Terminal"))
                    Spacer()
                    Picker("", selection: self.preferredTerminalBinding) {
                        ForEach(TerminalApp.installed, id: \.rawValue) { terminal in
                            HStack {
                                if let icon = terminal.appIcon {
                                    Image(nsImage: icon.resized(to: NSSize(width: 16, height: 16)))
                                }
                                Text(terminal.displayName)
                            }
                            .tag(terminal.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                }

                if self.isGhosttySelected {
                    HStack {
                        Text(self.t("Ghostty opens in"))
                        Spacer()
                        Picker("", selection: self.ghosttyOpenModeBinding) {
                            ForEach(GhosttyOpenMode.allCases, id: \.self) { mode in
                                Text(self.t(mode.label))
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(self.session.settings.localProjects.rootPath == nil)
                    }
                }
            } header: {
                Text(self.t("Local Projects"))
            } footer: {
                Text(self.t("Scans up to the configured depth under the folder, fetches periodically, and can fast-forward pull clean repos."))
            }

            GitLabArchiveSettingsSection(
                settings: self.$session.settings.gitlabArchives,
                language: self.session.settings.language
            ) {
                self.appState.persistSettings()
            }

            Section {
                Toggle(self.t("Watch copied GitLab references"), isOn: self.$session.settings.gitLabReferenceMonitor.enabled)
                    .onChange(of: self.session.settings.gitLabReferenceMonitor.enabled) { _, _ in
                        self.appState.persistSettings()
                        self.appState.updateGitLabReferenceMonitor()
                    }

                if self.session.settings.gitLabReferenceMonitor.enabled {
                    LabeledContent(self.t("Matches")) {
                        Text(self.t("GitLab URLs, issue numbers, commit hashes"))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(self.t("GitLab References"))
            } footer: {
                Text(
                    self.t("Shows the best cached or live match in a separate menu bar item when a copied reference resolves.")
                )
            }

            Section {
                Toggle(self.t("Summarize merge requests"), isOn: self.$session.settings.aiSummaries.enabled)
                    .onChange(of: self.session.settings.aiSummaries.enabled) { _, _ in
                        self.appState.persistSettings()
                    }

                Picker(self.t("Provider"), selection: self.aiSummaryProviderBinding) {
                    ForEach(AISummaryProvider.allCases, id: \.self) { provider in
                        Text(self.t(provider.label)).tag(provider)
                    }
                }
                .pickerStyle(.menu)

                Picker(self.t("Model"), selection: self.aiSummaryModelBinding) {
                    ForEach(self.aiSummaryModelOptions, id: \.id) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.menu)

                if self.isOpenAIResponsesProvider {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(self.t("Request URL"))
                            .font(.subheadline.weight(.semibold))

                        HStack(alignment: .center, spacing: 8) {
                            TextField(AISummarySettings.defaultOpenAIResponsesEndpoint.absoluteString, text: self.$aiRequestURLText)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 360)
                                .layoutPriority(1)
                            Button(self.t("Save")) {
                                self.saveAIRequestURL()
                            }
                            .disabled(self.aiRequestURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button {
                                self.resetAIRequestURL()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderless)
                            .help(self.t("Use default request URL"))
                        }

                        Text(self.aiRequestURLStatusText)
                            .font(.caption)
                            .foregroundStyle(self.aiRequestURLMessage == nil ? .secondary : .primary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(self.t("OpenAI API key"))
                            .font(.subheadline.weight(.semibold))

                        HStack(alignment: .center, spacing: 8) {
                            SecureField(self.t("Paste key"), text: self.$openAIAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 320)
                                .layoutPriority(1)
                            Button(self.t("Save")) {
                                self.saveOpenAIAPIKey()
                            }
                            .disabled(self.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button {
                                self.clearOpenAIAPIKey()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(self.t("Clear OpenAI API key"))
                        }

                        Text(self.openAIKeyStatusText)
                            .font(.caption)
                            .foregroundStyle(self.openAIKeyMessage == nil ? .secondary : .primary)
                    }
                    .padding(.vertical, 4)
                } else {
                    LabeledContent(self.t("Authentication")) {
                        Text(self.t("Uses local Claude Agent CLI authentication."))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(self.t("AI Summaries"))
            } footer: {
                Text(self.t(self.aiSummariesFooterText))
            }

            #if DEBUG
                Section {
                    Toggle(self.t("Enable debug tools"), isOn: self.$session.settings.debugPaneEnabled)
                        .onChange(of: self.session.settings.debugPaneEnabled) { _, _ in
                            self.appState.persistSettings()
                        }
                } header: {
                    Text(self.t("Debug"))
                } footer: {
                    Text(self.t("Developer-only diagnostics and experimental tools."))
                }
            #endif
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear {
            self.ensurePreferredTerminal()
            self.refreshOpenAIKeyStatus()
            self.refreshAIRequestURLText()
            self.appState.updateGitLabReferenceMonitor()
            self.appState.refreshLocalProjects()
        }
    }

    private func depthLabel(_ depth: Int) -> String {
        self.format(depth == 1 ? "%d level" : "%d levels", depth)
    }

    private var projectFolderLabel: String {
        guard let path = self.session.settings.localProjects.rootPath,
              path.isEmpty == false
        else { return self.t("Not set") }

        return PathFormatter.displayString(path)
    }

    private var projectFolderLabelColor: Color {
        self.session.settings.localProjects.rootPath == nil ? .secondary : .primary
    }

    private var localRepoSummary: String? {
        guard self.session.settings.localProjects.rootPath != nil else { return nil }

        if self.session.localProjectsScanInProgress { return self.t("Scanning…") }
        let total = self.session.localDiscoveredRepoCount
        let matched = self.localMatchedRepoCount
        if total == 0 {
            if self.session.localProjectsAccessDenied || self.session.settings.localProjects.rootBookmarkData == nil {
                return self.t("No repositories found yet. Re-choose the folder to grant access.")
            }
            return self.t("No repositories found yet.")
        }
        if matched > 0 {
            return self.format("Found %d local repos · %d match GitLab data.", total, matched)
        }
        return self.format("Found %d local repos.", total)
    }

    private var localMatchedRepoCount: Int {
        let repos = self.session.repositories.isEmpty
            ? (self.session.menuSnapshot?.repositories ?? [])
            : self.session.repositories
        guard repos.isEmpty == false else { return 0 }

        let fullNames = Set(repos.map(\.fullName))
        let repoByName = Dictionary(grouping: repos, by: \.name)
        var matched = 0
        for status in self.session.localRepoIndex.all {
            if let fullName = status.fullName, fullNames.contains(fullName) {
                matched += 1
            } else if let candidates = repoByName[status.name], candidates.count == 1 {
                matched += 1
            }
        }
        return matched
    }

    private var preferredTerminalBinding: Binding<String> {
        Binding(
            get: {
                self.session.settings.localProjects.preferredTerminal ?? TerminalApp.defaultPreferred.rawValue
            },
            set: { newValue in
                self.session.settings.localProjects.preferredTerminal = newValue
                self.appState.persistSettings()
            }
        )
    }

    private var ghosttyOpenModeBinding: Binding<GhosttyOpenMode> {
        Binding(
            get: { self.session.settings.localProjects.ghosttyOpenMode },
            set: { newValue in
                self.session.settings.localProjects.ghosttyOpenMode = newValue
                self.appState.persistSettings()
            }
        )
    }

    private var isGhosttySelected: Bool {
        TerminalApp.resolve(self.session.settings.localProjects.preferredTerminal) == .ghostty
    }

    private var worktreeFolderBinding: Binding<String> {
        Binding(
            get: {
                self.session.settings.localProjects.worktreeFolderName
            },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                self.session.settings.localProjects.worktreeFolderName = trimmed.isEmpty ? ".work" : trimmed
                self.appState.persistSettings()
            }
        )
    }

    private var aiSummaryModelBinding: Binding<String> {
        Binding(
            get: {
                AISummarySettings.normalizedModel(
                    self.session.settings.aiSummaries.model,
                    provider: self.session.settings.aiSummaries.provider
                )
            },
            set: { value in
                self.session.settings.aiSummaries.model = AISummarySettings.normalizedModel(
                    value,
                    provider: self.session.settings.aiSummaries.provider
                )
                self.appState.persistSettings()
            }
        )
    }

    private var aiSummaryProviderBinding: Binding<AISummaryProvider> {
        Binding(
            get: {
                self.session.settings.aiSummaries.provider
            },
            set: { provider in
                guard self.session.settings.aiSummaries.provider != provider else { return }

                self.session.settings.aiSummaries.provider = provider
                self.session.settings.aiSummaries.model = AISummarySettings.defaultModel(for: provider)
                self.appState.persistSettings()
                self.aiRequestURLMessage = nil
            }
        )
    }

    private var aiSummaryModelOptions: [AISummaryModelOption] {
        AISummarySettings.modelOptions(for: self.session.settings.aiSummaries.provider)
    }

    private var isOpenAIResponsesProvider: Bool {
        self.session.settings.aiSummaries.provider == .openAIResponses
    }

    private var aiSummariesFooterText: String {
        switch self.session.settings.aiSummaries.provider {
        case .openAIResponses:
            "Uses OpenAI Responses-compatible API to summarize merge requests in Issue Navigator."
        case .claudeCode:
            "Uses Claude Agent CLI print-mode protocol to summarize merge requests in Issue Navigator."
        }
    }

    private var aiRequestURLStatusText: String {
        if let aiRequestURLMessage {
            return aiRequestURLMessage
        }

        if let requestURL = AISummarySettings.normalizedRequestURL(self.session.settings.aiSummaries.requestURL) {
            return self.format("Using custom request URL: %@", requestURL.absoluteString)
        }

        return self.format(
            "Using default request URL: %@",
            AISummarySettings.defaultOpenAIResponsesEndpoint.absoluteString
        )
    }

    private var openAIKeyStatusText: String {
        if let openAIKeyMessage {
            return openAIKeyMessage
        }

        switch self.openAIKeySource {
        case .keychain:
            return self.t("OpenAI API key stored in Keychain.")
        case let .environment(name):
            return self.format("Using %@", name)
        case .missing:
            return self.t("No OpenAI API key configured.")
        }
    }

    private func pickProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = self.t("Choose")
        if let existing = self.session.settings.localProjects.rootPath {
            panel.directoryURL = URL(fileURLWithPath: PathFormatter.expandTilde(existing), isDirectory: true)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            panel.directoryURL = home.appendingPathComponent("Projects", isDirectory: true)
        }
        if panel.runModal() == .OK, let url = panel.url {
            let filePathURL = (url as NSURL).filePathURL ?? url
            let resolvedPath = filePathURL.resolvingSymlinksInPath().path
            self.session.settings.localProjects.rootPath = PathFormatter.abbreviateHome(resolvedPath)
            self.session.settings.localProjects.rootBookmarkData = SecurityScopedBookmark.create(for: url)
            self.appState.persistSettings()
            self.appState.refreshLocalProjects(forceRescan: true)
            self.appState.requestRefresh(cancelInFlight: true)
        }
    }

    private func clearProjectFolder() {
        self.session.settings.localProjects.rootPath = nil
        self.session.settings.localProjects.rootBookmarkData = nil
        self.appState.persistSettings()
        self.appState.refreshLocalProjects(forceRescan: true)
        self.appState.requestRefresh(cancelInFlight: true)
    }

    private func saveOpenAIAPIKey() {
        do {
            try self.appState.saveOpenAIAPIKey(self.openAIAPIKey)
            self.openAIAPIKey = ""
            self.openAIKeyMessage = self.t("OpenAI API key saved.")
            self.refreshOpenAIKeyStatus()
        } catch {
            self.openAIKeyMessage = self.format("Failed: %@", error.userFacingMessage)
        }
    }

    private func clearOpenAIAPIKey() {
        self.appState.clearOpenAIAPIKey()
        self.openAIAPIKey = ""
        self.openAIKeyMessage = self.t("OpenAI API key cleared.")
        self.refreshOpenAIKeyStatus()
    }

    private func saveAIRequestURL() {
        let trimmed = self.aiRequestURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let requestURL = AISummarySettings.normalizedRequestURLString(trimmed) else {
            self.aiRequestURLMessage = self.t("Request URL must be a valid http:// or https:// URL.")
            return
        }

        self.session.settings.aiSummaries.requestURL = requestURL
        self.aiRequestURLText = requestURL.absoluteString
        self.aiRequestURLMessage = self.t("AI request URL saved.")
        self.appState.persistSettings()
    }

    private func resetAIRequestURL() {
        self.session.settings.aiSummaries.requestURL = nil
        self.aiRequestURLText = AISummarySettings.defaultOpenAIResponsesEndpoint.absoluteString
        self.aiRequestURLMessage = self.t("AI request URL reset to default.")
        self.appState.persistSettings()
    }

    private func refreshAIRequestURLText() {
        let requestURL = AISummarySettings.normalizedRequestURL(self.session.settings.aiSummaries.requestURL)
            ?? AISummarySettings.defaultOpenAIResponsesEndpoint
        self.aiRequestURLText = requestURL.absoluteString
    }

    private func refreshOpenAIKeyStatus() {
        self.openAIKeySource = self.appState.openAIAPIKeySource()
    }

    private func ensurePreferredTerminal() {
        let resolved = TerminalApp.resolve(self.session.settings.localProjects.preferredTerminal).rawValue
        if self.session.settings.localProjects.preferredTerminal != resolved {
            self.session.settings.localProjects.preferredTerminal = resolved
            self.appState.persistSettings()
        }
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }

    private func format(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, settings: self.session.settings, arguments)
    }
}
