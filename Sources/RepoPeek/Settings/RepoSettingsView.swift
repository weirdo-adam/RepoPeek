import RepoPeekCore
import SwiftUI

struct RepoSettingsView: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var isAddRuleSheetPresented = false
    @State private var searchQuery = ""
    @State private var selection = Set<String>()
    @State private var allRows: [RepoBrowserRow] = []
    @State private var filteredRows: [RepoBrowserRow] = []
    @State private var statusLine = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(self.t("Browse repositories RepoPeek can access and choose what stays pinned or hidden."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            self.repositorySearchField

            Table(self.filteredRows, selection: self.$selection) {
                TableColumn(self.t("Repository")) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.fullName)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 6) {
                            if row.isFork {
                                Label(self.t("Fork"), systemImage: "tuningfork")
                                    .labelStyle(.titleAndIcon)
                            }
                            if row.isArchived {
                                Label(self.t("Archived"), systemImage: "archivebox")
                                    .labelStyle(.titleAndIcon)
                            }
                            if row.isManual {
                                Label(self.t("Manual"), systemImage: "pencil")
                                    .labelStyle(.titleAndIcon)
                            }
                            if row.ruleKind == .group {
                                Label(self.t("Group Rule"), systemImage: "folder")
                                    .labelStyle(.titleAndIcon)
                            }
                            if row.hiddenByGroup != nil {
                                Label(self.t("Group Hidden"), systemImage: "folder.badge.minus")
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .width(min: 300, ideal: 420, max: .infinity)

                TableColumn(self.t("Issues")) { row in
                    Text(row.issueLabel)
                        .monospacedDigit()
                        .foregroundStyle(row.isManual ? .secondary : .primary)
                }
                .width(min: 56, ideal: 64, max: 76)

                TableColumn(self.t("MRs")) { row in
                    Text(row.pullRequestLabel)
                        .monospacedDigit()
                        .foregroundStyle(row.isManual ? .secondary : .primary)
                }
                .width(min: 44, ideal: 52, max: 64)

                TableColumn(self.t("Stars")) { row in
                    Text(row.starLabel)
                        .monospacedDigit()
                        .foregroundStyle(row.isManual ? .secondary : .primary)
                }
                .width(min: 52, ideal: 64, max: 76)

                TableColumn(self.t("Updated")) { row in
                    Text(row.updatedLabel)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 96, max: 120)

                TableColumn(self.t("Visibility")) { row in
                    RepoVisibilityMenu(
                        visibility: row.visibility,
                        available: self.visibilityOptions(for: row),
                        visibleLabel: self.visibleMenuTitle(for: row),
                        language: self.session.settings.language
                    ) { newValue in
                        Task { await self.set(row, to: newValue) }
                    }
                    .frame(width: 128, alignment: .leading)
                }
                .width(min: 128, ideal: 136, max: 144)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 280)
            .onDeleteCommand { self.deleteSelection() }
            .contextMenu(forSelectionType: String.self) { selection in
                let selectedRows = self.selectedRows(for: selection)
                Button(self.t("Pin")) { Task { await self.bulkSet(selection, to: .pinned) } }
                Button(self.t("Hide")) { Task { await self.bulkSet(selection, to: .hidden) } }
                Button(self.visibleActionTitle(for: selectedRows)) { Task { await self.bulkSet(selection, to: .visible) } }
            }

            HStack(spacing: 10) {
                Text(self.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(self.t("Pin")) {
                    Task { await self.bulkSet(self.selection, to: .pinned) }
                }
                .disabled(self.selection.isEmpty)

                Button {
                    self.deleteSelection()
                } label: {
                    Label(self.visibleActionTitle(for: self.selectedRows(for: self.selection)), systemImage: "eye")
                }
                .disabled(self.selection.isEmpty)

                Button(self.t("Refresh Now")) {
                    self.appState.requestRefresh(cancelInFlight: true)
                }
            }
        }
        .padding()
        .onAppear {
            self.rebuildRows()
            Task {
                _ = try? await self.appState.recentRepositories(limit: RepoCacheConstants.maxRepositoriesToPrefetch)
            }
        }
        .onChange(of: self.searchQuery) { _, _ in self.applySearch() }
        .onChange(of: self.session.accessibleRepositories) { _, _ in self.rebuildRows() }
        .onChange(of: self.session.repositories) { _, _ in self.rebuildRows() }
        .onChange(of: self.session.menuSnapshot) { _, _ in self.rebuildRows() }
        .onChange(of: self.session.settings.repoList.pinnedRepositories) { _, _ in self.rebuildRows() }
        .onChange(of: self.session.settings.repoList.hiddenRepositories) { _, _ in self.rebuildRows() }
        .onChange(of: self.session.settings.repoList.hiddenGroups) { _, _ in self.rebuildRows() }
        .onChange(of: self.session.settings.repoList.accountScopedRepositoryLists) { _, _ in self.rebuildRows() }
        .onChange(of: self.session.settings.language) { _, _ in self.applySearch() }
        .sheet(isPresented: self.$isAddRuleSheetPresented) {
            AddRepoRuleSheet(
                session: self.session,
                appState: self.appState,
                onAdd: self.addRule
            )
        }
    }

    private var browserRepositories: [Repository] {
        if !self.session.accessibleRepositories.isEmpty {
            return self.session.accessibleRepositories
        }
        if let snapshotRepos = self.session.menuSnapshot?.repositories, !snapshotRepos.isEmpty {
            return snapshotRepos
        }
        return self.session.repositories
    }

    private var repositorySearchField: some View {
        HStack(spacing: 8) {
            TextField(self.t("Search repositories"), text: self.$searchQuery)
                .textFieldStyle(.roundedBorder)

            Button {
                self.searchQuery = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(self.t("Clear search"))
            .disabled(self.searchQuery.isEmpty)

            Button {
                self.isAddRuleSheetPresented = true
            } label: {
                Label(self.t("Add Rule") + "…", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .help(self.t("Add Rule"))
        }
    }

    private func addRule(kind: RepoRuleInputKind, path: String, visibility: RepoVisibility) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task {
            if kind == .repository {
                await self.set(trimmed, to: visibility)
            } else {
                await self.appState.hideGroup(trimmed)
            }
        }
    }

    private func set(_ name: String, to visibility: RepoVisibility) async {
        await self.appState.setVisibility(for: name, to: visibility)
    }

    private func set(_ row: RepoBrowserRow, to visibility: RepoVisibility) async {
        if row.ruleKind == .group {
            await self.setGroup(row.rulePath, to: visibility, accountID: row.accountID)
            await self.finishVisibilityChange(rowIDs: [row.id])
            return
        }

        if let hiddenGroup = row.hiddenByGroup {
            guard visibility != .hidden else { return }

            await self.appState.removeHiddenGroup(hiddenGroup, accountID: row.accountID)
        }
        await self.appState.setVisibility(for: row.rulePath, to: visibility, accountID: row.accountID)
        await self.finishVisibilityChange(rowIDs: [row.id])
    }

    private func setGroup(_ groupPath: String, to visibility: RepoVisibility, accountID: String?) async {
        switch visibility {
        case .hidden:
            await self.appState.hideGroup(groupPath, accountID: accountID)
        case .visible:
            await self.appState.removeHiddenGroup(groupPath, accountID: accountID)
        case .pinned:
            break
        }
    }

    private func bulkSet(_ ids: Set<String>, to visibility: RepoVisibility) async {
        let selectedRows = self.allRows.filter { ids.contains($0.id) }
        for row in selectedRows {
            await self.set(row, to: visibility)
        }
        await MainActor.run {
            self.selection.removeAll()
            self.rebuildRows()
        }
    }

    private func deleteSelection() {
        let ids = self.selection
        Task {
            await self.bulkSet(ids, to: .visible)
        }
    }

    private func rebuildRows() {
        self.allRows = RepoBrowserRows.make(
            repositories: self.browserRepositories,
            pinnedRepositories: self.session.settings.repoList.pinnedRepositories,
            hiddenRepositories: self.session.settings.repoList.hiddenRepositories,
            hiddenGroups: self.session.settings.repoList.hiddenGroups,
            accountScopedRepositoryLists: self.session.settings.repoList.accountScopedRepositoryLists,
            now: Date()
        )
        self.applySearch()
    }

    private func visibilityOptions(for row: RepoBrowserRow) -> [RepoVisibility] {
        if row.ruleKind == .group || row.hiddenByGroup != nil {
            return [.hidden, .visible]
        }
        return RepoVisibility.allCases
    }

    private func selectedRows(for ids: Set<String>) -> [RepoBrowserRow] {
        self.allRows.filter { ids.contains($0.id) }
    }

    private func visibleMenuTitle(for row: RepoBrowserRow) -> String {
        if row.visibility != .visible {
            return self.t("Remove Rule")
        }
        return self.t(RepoVisibility.visible.label)
    }

    private func visibleActionTitle(for rows: [RepoBrowserRow]) -> String {
        if rows.contains(where: { $0.visibility != .visible }) {
            return self.t("Remove Rule")
        }
        return self.t("Set Visible")
    }

    private func finishVisibilityChange(rowIDs: Set<String>) async {
        await MainActor.run {
            self.selection.subtract(rowIDs)
            self.rebuildRows()
        }
    }

    private func applySearch() {
        self.filteredRows = RepoBrowserRows.filter(self.allRows, query: self.searchQuery)
        self.selection.formIntersection(Set(self.filteredRows.map(\.id)))
        self.statusLine = RepoBrowserRows.statusLine(
            allRows: self.allRows,
            filteredRows: self.filteredRows,
            language: self.session.settings.language
        )
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }
}

private struct AddRepoRuleSheet: View {
    @Bindable var session: Session
    let appState: AppState
    let onAdd: (RepoRuleInputKind, String, RepoVisibility) -> Void
    private let labelWidth: CGFloat = 96
    private let columnSpacing: CGFloat = 12
    private let fieldWidth: CGFloat = 360
    @Environment(\.dismiss) private var dismiss
    @State private var ruleKind: RepoRuleInputKind = .repository
    @State private var rulePath = ""
    @State private var visibility: RepoVisibility = .pinned

    private var trimmedPath: String {
        self.rulePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pathLabel: String {
        if self.ruleKind == .group {
            return self.t("Group path")
        }
        return self.t("Repository path")
    }

    private var pathPlaceholder: String {
        if self.ruleKind == .group {
            return self.t("group/subgroup")
        }
        return self.t("owner/name")
    }

    private var primaryButtonTitle: String {
        if self.ruleKind == .group {
            return self.t("Hide Group")
        }
        return self.t("Add")
    }

    private var formWidth: CGFloat {
        self.labelWidth + self.columnSpacing + self.fieldWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.t("Add Rule"))
                    .font(.title3.weight(.semibold))
                Text(self.t("Repository rules use owner/name. Group rules use namespace paths such as group/subgroup and hide everything below that path."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Grid(alignment: .leading, horizontalSpacing: self.columnSpacing, verticalSpacing: 12) {
                GridRow {
                    self.formLabel(self.t("Rule Type"))
                    Picker(self.t("Rule Type"), selection: self.$ruleKind) {
                        Text(self.t("Repository")).tag(RepoRuleInputKind.repository)
                        Text(self.t("Group")).tag(RepoRuleInputKind.group)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 176)
                }

                GridRow {
                    self.formLabel(self.pathLabel)
                    RepoRulePathField(
                        placeholder: self.pathPlaceholder,
                        text: self.$rulePath,
                        onCommit: { self.submit(path: $0) },
                        session: self.session,
                        appState: self.appState,
                        language: self.session.settings.language,
                        suggestionsEnabled: self.ruleKind == .repository,
                        commitsSuggestionOnSelect: false
                    )
                    .frame(width: self.fieldWidth)
                }

                if self.ruleKind == .repository {
                    GridRow {
                        self.formLabel(self.t("Rule"))
                        Picker(self.t("Rule"), selection: self.$visibility) {
                            Text(self.t("Pin")).tag(RepoVisibility.pinned)
                            Text(self.t("Hide")).tag(RepoVisibility.hidden)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 176)
                    }
                }

                GridRow {
                    self.formLabel("")
                    HStack(spacing: 10) {
                        Spacer()
                        Button(self.t("Cancel")) {
                            self.dismiss()
                        }
                        .keyboardShortcut(.cancelAction)

                        Button(self.primaryButtonTitle) {
                            self.submit()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(self.trimmedPath.isEmpty)
                    }
                    .frame(width: self.fieldWidth)
                    .padding(.top, 4)
                }
            }
            .frame(width: self.formWidth, alignment: .leading)
        }
        .padding(24)
        .frame(width: 540)
        .onChange(of: self.ruleKind) { _, newValue in
            if newValue == .group {
                self.visibility = .hidden
            }
        }
    }

    private func formLabel(_ label: String) -> some View {
        Text(label.isEmpty ? " " : label)
            .font(.caption.weight(.medium))
            .foregroundStyle(label.isEmpty ? .clear : .secondary)
            .frame(width: self.labelWidth, alignment: .trailing)
    }

    private func submit(path: String? = nil) {
        let targetPath = (path ?? self.rulePath).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetPath.isEmpty else { return }

        self.onAdd(
            self.ruleKind,
            targetPath,
            self.ruleKind == .group ? .hidden : self.visibility
        )
        self.dismiss()
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }
}

private struct RepoVisibilityMenu: View {
    let visibility: RepoVisibility
    let available: [RepoVisibility]
    let visibleLabel: String
    let language: AppLanguage
    var onChange: (RepoVisibility) -> Void

    var body: some View {
        Menu {
            ForEach(self.available) { item in
                Button {
                    self.onChange(item)
                } label: {
                    if item == self.visibility {
                        Label(self.title(for: item), systemImage: "checkmark")
                    } else {
                        Text(self.title(for: item))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(self.t(self.visibility.label))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func t(_ key: String) -> String {
        L10n.t(key, language: self.language)
    }

    private func title(for visibility: RepoVisibility) -> String {
        if visibility == .visible {
            return self.visibleLabel
        }
        return self.t(visibility.label)
    }
}

private enum RepoRuleInputKind: String, CaseIterable, Hashable {
    case repository
    case group
}

// MARK: - Autocomplete helper

private struct RepoRulePathField: View {
    let placeholder: String
    @Binding var text: String
    var onCommit: (String) -> Void
    @Bindable var session: Session
    let appState: AppState
    let language: AppLanguage
    var suggestionsEnabled = true
    var commitsSuggestionOnSelect = true
    @State private var suggestions: [Repository] = []
    @State private var isLoading = false
    @State private var showSuggestions = false
    @State private var selectedIndex = -1
    @State private var keyboardNavigating = false
    @State private var textFieldSize: CGSize = .zero
    @FocusState private var isFocused: Bool
    @State private var searchTask: Task<Void, Never>?

    private var trimmedText: String {
        self.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        TextField(self.placeholder, text: self.$text)
            .textFieldStyle(.roundedBorder)
            .focused(self.$isFocused)
            .onChange(of: self.text) { _, newValue in
                self.keyboardNavigating = false
                self.scheduleSearch(query: newValue, immediate: true)
            }
            .onSubmit { self.commit() }
            .onTapGesture {
                self.showSuggestions = true
                self.scheduleSearch(query: self.text, immediate: true)
            }
            .onMoveCommand(perform: self.handleMove)
            .overlay(alignment: .trailing) {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
                    .opacity(self.isLoading ? 1 : 0)
                    .accessibilityHidden(!self.isLoading)
                    .allowsHitTesting(false)
            }
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { self.textFieldSize = geometry.size }
                        .onChange(of: geometry.size) { _, newSize in
                            self.textFieldSize = newSize
                        }
                }
            )
            .background(
                RepoAutocompleteWindowView(
                    suggestions: self.suggestions,
                    selectedIndex: self.$selectedIndex,
                    keyboardNavigating: self.keyboardNavigating,
                    onSelect: { suggestion in
                        if self.commitsSuggestionOnSelect {
                            self.commit(suggestion)
                        } else {
                            self.acceptSuggestion(suggestion)
                        }
                        DispatchQueue.main.async {
                            self.isFocused = true
                        }
                    },
                    width: self.textFieldSize.width,
                    language: self.language,
                    isShowing: Binding(
                        get: {
                            self.showSuggestions && self.isFocused && !self.suggestions.isEmpty
                        },
                        set: { self.showSuggestions = $0 }
                    )
                )
            )
            .onChange(of: self.isFocused) { _, newValue in
                if newValue {
                    self.scheduleSearch(query: self.text, immediate: true)
                } else {
                    self.hideSuggestionsSoon()
                }
            }
            .onDisappear { self.searchTask?.cancel() }
    }

    private func commit(_ value: String? = nil) {
        let trimmed = (value ?? self.trimmedText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        self.text = ""
        self.suggestions = []
        self.showSuggestions = false
        self.selectedIndex = -1
        self.onCommit(trimmed)
    }

    private func acceptSuggestion(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        self.text = trimmed
        self.suggestions = []
        self.showSuggestions = false
        self.selectedIndex = -1
    }

    private func scheduleSearch(query: String, immediate: Bool = false) {
        self.searchTask?.cancel()
        self.searchTask = Task {
            // Local-only filtering; keep it snappy.
            if !immediate {
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }

            await self.loadSuggestions(query: query)
        }
    }

    private func loadSuggestions(query: String) async {
        guard self.suggestionsEnabled else {
            await MainActor.run {
                self.suggestions = []
                self.showSuggestions = false
                self.isLoading = false
            }
            return
        }

        await MainActor.run {
            self.isLoading = true
            self.showSuggestions = self.isFocused
        }
        defer {
            Task { @MainActor in self.isLoading = false }
        }

        let includeForks = await MainActor.run { self.session.settings.repoList.showForks }
        let includeArchived = await MainActor.run { self.session.settings.repoList.showArchived }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cachedRepositories = await self.cachedRepositories()
        let cachedSuggestions = self.suggestions(
            query: trimmed,
            repositories: cachedRepositories,
            includeForks: includeForks,
            includeArchived: includeArchived
        )

        if !cachedSuggestions.isEmpty {
            await MainActor.run {
                self.applySuggestions(cachedSuggestions)
                self.isLoading = false
            }
        }

        let prefetched = try? await self.appState.recentRepositories(limit: RepoCacheConstants.maxRepositoriesToPrefetch)

        guard !Task.isCancelled else { return }

        let repositories = RepositoryUniquing.byFullName((prefetched ?? []) + cachedRepositories)
        let repos = self.suggestions(
            query: trimmed,
            repositories: repositories,
            includeForks: includeForks,
            includeArchived: includeArchived
        )

        await MainActor.run {
            if !repos.isEmpty || cachedSuggestions.isEmpty {
                self.applySuggestions(repos)
            }
        }
    }

    private func cachedRepositories() async -> [Repository] {
        await MainActor.run {
            RepositoryUniquing.byFullName(
                self.session.accessibleRepositories
                    + (self.session.menuSnapshot?.repositories ?? [])
                    + self.session.repositories
            )
        }
    }

    private func suggestions(
        query: String,
        repositories: [Repository],
        includeForks: Bool,
        includeArchived: Bool
    ) -> [Repository] {
        let filtered = RepositoryFilter.apply(
            repositories,
            includeForks: includeForks,
            includeArchived: includeArchived
        )
        return RepoAutocompleteSuggestions.suggestions(
            query: query,
            prefetched: filtered,
            limit: AppLimits.Autocomplete.settingsSearchLimit
        )
    }

    @MainActor
    private func applySuggestions(_ repos: [Repository]) {
        self.suggestions = repos
        if self.selectedIndex >= self.suggestions.count {
            self.selectedIndex = -1
        }
        // Keep suggestions visible while typing even if focus flickers.
        self.showSuggestions = !self.suggestions.isEmpty && (self.isFocused || !self.trimmedText.isEmpty)
    }

    private func hideSuggestionsSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.showSuggestions = false
            self.selectedIndex = -1
        }
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        guard !self.suggestions.isEmpty else { return }

        switch direction {
        case .down:
            self.keyboardNavigating = true
            let next = self.selectedIndex + 1
            self.selectedIndex = min(next, self.suggestions.count - 1)
        case .up:
            self.keyboardNavigating = true
            let prev = self.selectedIndex - 1
            self.selectedIndex = max(prev, 0)
        default:
            break
        }
    }
}
