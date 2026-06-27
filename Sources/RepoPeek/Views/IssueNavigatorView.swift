import AppKit
import RepoPeekCore
import SwiftUI

struct IssueNavigatorView: View {
    private enum Metrics {
        static let sidebarHorizontalGutter: CGFloat = 16
        static let sidebarMinWidth: CGFloat = 380
        static let sidebarIdealWidth: CGFloat = 470
        static let sidebarMaxWidth: CGFloat = 560
        static let sidebarPadding: CGFloat = 14
        static let resultListPadding: CGFloat = 8
        static let controlHeight: CGFloat = 28
        static let controlCornerRadius: CGFloat = 10
    }

    let appState: AppState
    @State private var searchText = ""
    @State private var kindFilter: IssueNavigatorKindFilter = .all
    @State private var selectedScope = IssueNavigatorScope.all
    @State private var results: [GitLabReferenceMatch] = []
    @State private var selectedURL: URL?
    @State private var isSearching = false
    @State private var statusText = "Loading recent issues and merge requests."
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var summaryTask: Task<Void, Never>?
    @State private var isSummarizing = false
    @State private var searchGeneration = UUID()
    @State private var clipboardText: String?
    @State private var clipboardQueries: [GitLabReferenceQuery] = []
    @State private var browserNavigationVersion = 0
    let browserStore: IssueNavigatorBrowserStore

    private var repositories: [Repository] {
        self.appState.gitLabReferenceRepositories()
    }

    private var language: AppLanguage {
        self.appState.session.settings.language
    }

    private var scopes: [IssueNavigatorScope] {
        [.all] + self.repositories.map { IssueNavigatorScope(fullName: $0.fullName, title: $0.fullName) }
    }

    private var selectedMatch: GitLabReferenceMatch? {
        guard let selectedURL else { return self.results.first }

        return self.results.first { $0.url == selectedURL } ?? self.results.first
    }

    init(
        appState: AppState,
        initialMatches: [GitLabReferenceMatch] = [],
        browserStore: IssueNavigatorBrowserStore = IssueNavigatorBrowserStore()
    ) {
        let matches = initialMatches.issueNavigatorOrderPreservingDeduped()
        let initialStatus = matches.isEmpty
            ? L10n.t("Loading recent issues and merge requests.", settings: appState.session.settings)
            : L10n.t("References in pasted order", settings: appState.session.settings)
        self.appState = appState
        self.browserStore = browserStore
        self._results = State(initialValue: matches)
        self._selectedURL = State(initialValue: matches.first?.url)
        self._statusText = State(initialValue: initialStatus)
    }

    var body: some View {
        IssueNavigatorSplitView(
            sidebarMinWidth: Metrics.sidebarMinWidth,
            sidebarIdealWidth: Metrics.sidebarIdealWidth,
            sidebarMaxWidth: Metrics.sidebarMaxWidth
        ) {
            self.sidebar
        } detail: {
            self.previewPane
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.ultraThinMaterial)
        .frame(minWidth: 980, minHeight: 620)
        .onAppear {
            self.browserStore.onNavigationStateChange = {
                self.browserNavigationVersion &+= 1
            }
            self.updateClipboard(seedIfEmpty: Self.shouldSeedClipboardOnAppear(hasInitialMatches: !self.results.isEmpty))
            if self.results.isEmpty {
                self.scheduleSearch(immediate: true)
            } else {
                self.preloadPreviews(for: self.results)
                self.scheduleAISummaries(for: self.results, generation: self.searchGeneration)
            }
        }
        .onDisappear {
            self.searchGeneration = UUID()
            self.searchTask?.cancel()
            self.summaryTask?.cancel()
            self.isSummarizing = false
            self.browserStore.onNavigationStateChange = nil
            self.browserStore.clear()
        }
        .onReceive(
            Timer.publish(every: 1, tolerance: 0.25, on: .main, in: .common).autoconnect()
        ) { _ in
            self.updateClipboard(seedIfEmpty: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .issueNavigatorUseClipboard)) { _ in
            self.useClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .issueNavigatorRefresh)) { _ in
            self.scheduleSearch(immediate: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .issueNavigatorCopy)) { _ in
            if let match = self.selectedMatch {
                self.copy(match)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .issueNavigatorOpen)) { _ in
            if let match = self.selectedMatch {
                self.open(match)
            }
        }
        .onChange(of: self.searchText) { _, _ in self.scheduleSearch() }
        .onChange(of: self.kindFilter) { _, _ in self.scheduleSearch(immediate: true) }
        .onChange(of: self.selectedScope) { _, _ in self.scheduleSearch(immediate: true) }
    }

    private var sidebar: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Metrics.sidebarHorizontalGutter)
            VStack(spacing: 0) {
                self.sidebarControls
                self.resultPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Color.clear
                .frame(width: Metrics.sidebarHorizontalGutter)
        }
        .frame(maxHeight: .infinity)
        .background(.thinMaterial)
    }

    private var sidebarControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            IssueNavigatorSearchField(
                text: self.$searchText,
                placeholder: self.t("Search issues and merge requests"),
                onSubmit: {
                    if let match = self.selectedMatch {
                        self.open(match)
                    } else {
                        self.scheduleSearch(immediate: true)
                    }
                }
            )
            .frame(height: Metrics.controlHeight)

            HStack(spacing: 8) {
                IssueNavigatorScopePopUp(selection: self.$selectedScope, scopes: self.scopes, language: self.language)
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.controlHeight)

                if self.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            IssueNavigatorKindSegmentedControl(selection: self.$kindFilter, language: self.language)
                .frame(height: Metrics.controlHeight)

            if self.shouldShowClipboardPrompt {
                Button {
                    self.useClipboard()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                        Text(self.format("Clipboard: %@", self.clipboardDisplayText))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.turn.down.left")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 11)
                .frame(height: Metrics.controlHeight)
                .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.22))
                )
            }

            Text(self.statusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Metrics.sidebarPadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var resultPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                IssueNavigatorCountBadge(count: self.results.count, language: self.language)
                Spacer(minLength: 12)
                Text(self.t("Updated newest first"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Metrics.sidebarPadding)
            .padding(.top, 2)
            .padding(.bottom, 10)

            if let errorText {
                self.sidebarMessage(
                    title: self.t("Search failed"),
                    message: errorText,
                    systemImage: "exclamationmark.triangle"
                )
            } else if self.results.isEmpty {
                self.sidebarMessage(
                    title: self.t("No matches"),
                    message: self.statusText,
                    systemImage: "tray"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(self.results, id: \.url) { match in
                            IssueNavigatorResultRow(
                                match: match,
                                now: Date(),
                                isSelected: self.selectedURL == match.url,
                                language: self.language,
                                onOpen: { self.open(match) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                self.select(match)
                            }
                            .contextMenu {
                                Button(self.t("Open in Browser")) { self.open(match) }
                                Button(self.t("Copy URL")) { self.copy(match) }
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.resultListPadding)
                    .padding(.bottom, 14)
                }
                .onChange(of: self.selectedURL) { _, newValue in
                    guard newValue == nil, let first = self.results.first else { return }

                    self.selectedURL = first.url
                }
            }
        }
    }

    private func sidebarMessage(title: String, message: String, systemImage: String) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 68)
            .padding(.bottom, 20)

            Spacer(minLength: 0)
        }
    }

    private var previewPane: some View {
        Group {
            if let match = self.selectedMatch {
                VStack(spacing: 0) {
                    self.previewHeader(for: match)
                    IssueNavigatorBrowserPreview(url: match.url, store: self.browserStore)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.and.text.magnifyingglass")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(.tertiary)
                    Text(self.t("Pick a result"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(self.t("Search by title, URL, owner/repo#number, or commit SHA."))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .padding(26)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func previewHeader(for match: GitLabReferenceMatch) -> some View {
        let canGoBack = self.browserStore.canGoBack(match.url)
        return HStack(spacing: 12) {
            Button { self.browserStore.goBack(match.url) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!canGoBack)
            .help(self.t("Back"))
            ZStack {
                Circle().fill(self.tint(for: match).opacity(0.16))
                Image(systemName: self.symbolName(for: match))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(self.tint(for: match))
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                self.previewHeaderMetadata(for: match)
            }
            Spacer()
        }
        .id(self.browserNavigationVersion)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func previewHeaderMetadata(for match: GitLabReferenceMatch) -> some View {
        HStack(spacing: 6) {
            Text(match.repositoryFullName).lineLimit(1).truncationMode(.middle)
            Text(match.query.displayText)
            if let state = match.state?.label { Text(state) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var shouldShowClipboardPrompt: Bool {
        guard let clipboardText else { return false }

        return self.clipboardQueries.isEmpty == false && clipboardText != self.searchText
    }

    private var clipboardDisplayText: String {
        self.clipboardQueries.map(\.displayText).joined(separator: ", ")
    }

    private var statusLine: String {
        if self.isSearching { return self.t("Searching…") }
        if self.isSummarizing { return self.t("Summarizing merge requests…") }
        if let errorText { return errorText }
        return self.statusText
    }

    private func scheduleSearch(immediate: Bool = false) {
        let generation = UUID()
        self.searchGeneration = generation
        self.searchTask?.cancel()
        self.summaryTask?.cancel()
        self.isSummarizing = false
        self.searchTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }

            await self.performSearch(generation: generation)
        }
    }

    @MainActor
    private func performSearch(generation: UUID) async {
        guard self.isCurrentSearch(generation) else { return }

        let trimmed = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedRepository = self.selectedScope.fullName
        let queries = GitLabReferenceTranslator.queries(
            from: trimmed,
            minimumBareDigits: AppLimits.GitLabReferenceMonitor.minimumBareDigits,
            repositoryContextOverride: selectedRepository
        )
        let canRunTextSearch = queries.isEmpty &&
            (selectedRepository != nil || trimmed.count >= AppLimits.IssueNavigator.minimumSearchCharacters)
        if trimmed.isEmpty || (queries.isEmpty && !canRunTextSearch) {
            self.isSearching = true
            self.errorText = nil
            defer {
                if self.isCurrentSearch(generation) {
                    self.isSearching = false
                }
            }

            do {
                let matches = try await self.appState.recentIssueReferences(
                    repositoryFullName: selectedRepository,
                    includeIssues: self.kindFilter.includeIssues,
                    includePullRequests: self.kindFilter.includePullRequests
                )
                guard self.isCurrentSearch(generation) else { return }

                self.results = matches
                self.selectedURL = matches.first?.url
                self.preloadPreviews(for: matches)
                self.scheduleAISummaries(for: matches, generation: generation)
                if matches.isEmpty {
                    self.statusText = self.t("No recent issues or merge requests in this scope.")
                } else if trimmed.isEmpty {
                    self.statusText = self.t("Recent subscribed and accessible items")
                } else {
                    self.statusText = self.format(
                        "Showing recent items; type at least %d characters to search.",
                        AppLimits.IssueNavigator.minimumSearchCharacters
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrentSearch(generation) else { return }

                self.results = []
                self.selectedURL = nil
                self.errorText = error.userFacingMessage
            }
            return
        }

        guard queries.isEmpty == false || canRunTextSearch else {
            guard self.isCurrentSearch(generation) else { return }

            self.results = []
            self.selectedURL = nil
            self.statusText = self.format(
                "Type at least %d characters, or paste a GitLab reference.",
                AppLimits.IssueNavigator.minimumSearchCharacters
            )
            self.errorText = nil
            return
        }

        self.isSearching = true
        self.errorText = nil
        defer {
            if self.isCurrentSearch(generation) {
                self.isSearching = false
            }
        }

        do {
            async let referenceMatches = self.appState.resolveGitLabReferenceQueries(queries, sourceText: trimmed)
            async let textMatches: [GitLabReferenceMatch] = canRunTextSearch
                ? self.appState.searchIssueReferences(
                    matching: trimmed,
                    repositoryFullName: selectedRepository,
                    includeIssues: self.kindFilter.includeIssues,
                    includePullRequests: self.kindFilter.includePullRequests
                )
                : []

            let resolvedReferenceMatches = await referenceMatches
            let searchedTextMatches = try await textMatches
            guard self.isCurrentSearch(generation) else { return }

            let filteredReferenceMatches = resolvedReferenceMatches.filter { self.kindFilter.matches($0.kind) }
            let combined = queries.isEmpty
                ? Self.deduped(filteredReferenceMatches + searchedTextMatches)
                : (filteredReferenceMatches + searchedTextMatches).issueNavigatorOrderPreservingDeduped()
            self.results = combined
            self.selectedURL = combined.first?.url
            self.preloadPreviews(for: combined)
            self.scheduleAISummaries(for: combined, generation: generation)
            self.statusText = self.status(for: combined, searchedText: trimmed, preservesReferenceOrder: queries.isEmpty == false)
        } catch is CancellationError {
            return
        } catch {
            guard self.isCurrentSearch(generation) else { return }

            self.results = []
            self.selectedURL = nil
            self.errorText = error.userFacingMessage
        }
    }

    private func isCurrentSearch(_ generation: UUID) -> Bool {
        !Task.isCancelled && self.searchGeneration == generation
    }

    private func updateClipboard(seedIfEmpty: Bool) {
        let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, text.isEmpty == false else {
            self.clipboardText = nil
            self.clipboardQueries = []
            return
        }

        let queries = GitLabReferenceTranslator.queries(
            from: text,
            minimumBareDigits: AppLimits.GitLabReferenceMonitor.minimumBareDigits
        )
        self.clipboardText = text
        self.clipboardQueries = queries
        if seedIfEmpty, self.searchText.isEmpty, queries.isEmpty == false {
            self.searchText = text
        }
    }

    nonisolated static func shouldSeedClipboardOnAppear(hasInitialMatches: Bool) -> Bool {
        !hasInitialMatches
    }

    private func useClipboard() {
        guard let clipboardText else { return }

        self.searchText = clipboardText
        self.scheduleSearch(immediate: true)
    }

    private func preloadPreviews(for matches: [GitLabReferenceMatch]) {
        self.browserStore.preload(
            matches
                .prefix(AppLimits.IssueNavigator.webPreviewPreloadLimit)
                .map(\.url)
        )
    }

    private func scheduleAISummaries(for matches: [GitLabReferenceMatch], generation: UUID) {
        self.summaryTask?.cancel()
        self.isSummarizing = false

        guard self.appState.session.settings.aiSummaries.enabled,
              PullRequestAISummarizer.candidateMatches(from: matches).isEmpty == false
        else { return }

        self.summaryTask = Task {
            guard self.isCurrentSearch(generation) else { return }

            self.isSummarizing = true
            do {
                let summarized = try await self.appState.summarizeIssueNavigatorMatches(matches)
                guard self.isCurrentSearch(generation) else { return }

                self.applyAISummaries(from: summarized)
                self.isSummarizing = false
            } catch is CancellationError {
                self.isSummarizing = false
            } catch {
                guard self.isCurrentSearch(generation) else { return }

                self.isSummarizing = false
                self.statusText = self.format("AI summaries unavailable: %@", error.userFacingMessage)
            }
        }
    }

    private func applyAISummaries(from matches: [GitLabReferenceMatch]) {
        let summaries = matches.reduce(into: [URL: String]()) { result, match in
            guard let aiSummary = match.aiSummary else { return }

            result[match.url] = aiSummary
        }
        guard summaries.isEmpty == false else { return }

        self.results = self.results.map { match in
            guard let summary = summaries[match.url] else { return match }

            return match.withAISummary(summary)
        }
    }

    private func select(_ match: GitLabReferenceMatch) {
        if self.selectedURL == match.url {
            self.browserStore.reloadInitialURL(match.url)
        }
        self.selectedURL = match.url
    }

    private static func deduped(_ matches: [GitLabReferenceMatch]) -> [GitLabReferenceMatch] {
        var seen: Set<URL> = []
        return matches
            .filter { seen.insert($0.url).inserted }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
    }

    private func status(
        for matches: [GitLabReferenceMatch],
        searchedText: String,
        preservesReferenceOrder: Bool = false
    ) -> String {
        if matches.isEmpty {
            if searchedText.isEmpty {
                return self.t("No recent items in this scope.")
            }
            return self.t("No matching issues or merge requests.")
        } else if preservesReferenceOrder {
            return self.t("References in pasted order")
        } else {
            return self.t("Updated newest first")
        }
    }

    private func open(_ match: GitLabReferenceMatch) {
        NSWorkspace.shared.open(match.url)
    }

    private func copy(_ match: GitLabReferenceMatch) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(match.url.absoluteString, forType: .string)
    }

    func symbolName(for match: GitLabReferenceMatch) -> String {
        switch match.kind {
        case .issue:
            match.state == .closed ? "checkmark.circle" : "exclamationmark.circle"
        case .pullRequest:
            switch match.state {
            case .merged: "arrow.triangle.merge"
            case .closed: "xmark.circle"
            case .open, nil: "arrow.triangle.pull"
            }
        case .commit:
            "number.square"
        case .workflowRun:
            "play.circle"
        }
    }

    func tint(for match: GitLabReferenceMatch) -> Color {
        switch match.kind {
        case .issue:
            match.state == .closed ? .purple : .green
        case .pullRequest:
            match.state == .merged ? .purple : (match.state == .closed ? .red : .green)
        case .commit, .workflowRun:
            .secondary
        }
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.appState.session.settings)
    }

    private func format(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, settings: self.appState.session.settings, arguments)
    }
}

private struct IssueNavigatorResultRow: View {
    let match: GitLabReferenceMatch
    let now: Date
    let isSelected: Bool
    let language: AppLanguage
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: self.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(self.iconForeground)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(self.match.issueNavigatorTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.primaryForeground)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(self.match.repositoryFullName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let state = match.state?.label {
                        Text(self.t(state))
                    }
                    Text(RelativeFormatter.string(from: self.match.updatedAt, relativeTo: self.now))
                }
                .font(.caption)
                .foregroundStyle(self.secondaryForeground)
                if let summaryText {
                    HStack(alignment: .top, spacing: 5) {
                        if self.match.aiSummary != nil {
                            Image(systemName: "sparkles")
                                .font(.caption2.weight(.semibold))
                                .padding(.top, 1)
                        }
                        Text(summaryText)
                            .font(.caption)
                            .foregroundStyle(self.secondaryForeground)
                            .lineLimit(self.match.aiSummary == nil ? 2 : 4)
                    }
                    .foregroundStyle(self.secondaryForeground)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(self.rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(count: 2, perform: self.onOpen)
    }

    private var symbolName: String {
        switch self.match.kind {
        case .issue:
            self.match.state == .closed ? "checkmark.circle" : "exclamationmark.circle"
        case .pullRequest:
            switch self.match.state {
            case .merged: "arrow.triangle.merge"
            case .closed: "xmark.circle"
            case .open, nil: "arrow.triangle.branch.circle"
            }
        case .commit:
            "number.square"
        case .workflowRun:
            "play.circle"
        }
    }

    private var tint: Color {
        switch self.match.kind {
        case .issue:
            self.match.state == .closed ? .purple : .green
        case .pullRequest:
            self.match.state == .merged ? .purple : (self.match.state == .closed ? .red : .green)
        case .commit, .workflowRun:
            .secondary
        }
    }

    private var primaryForeground: Color {
        self.isSelected ? .white : .primary
    }

    private var secondaryForeground: Color {
        self.isSelected ? Color.white.opacity(0.76) : .secondary
    }

    private var iconForeground: Color {
        self.isSelected ? Color.white.opacity(0.92) : self.tint
    }

    private var summaryText: String? {
        if let aiSummary = self.match.aiSummary, aiSummary.isEmpty == false {
            return aiSummary
        }
        if let bodyPreview = self.match.bodyPreview, bodyPreview.isEmpty == false {
            return bodyPreview
        }
        return nil
    }

    private var rowBackground: Color {
        self.isSelected ? Color.accentColor.opacity(0.86) : .clear
    }

    private func t(_ key: String) -> String {
        L10n.t(key, language: self.language)
    }
}

private struct IssueNavigatorCountBadge: View {
    let count: Int
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 7) {
            Text("\(self.count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(self.t(self.count == 1 ? "match" : "matches"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
    }

    private func t(_ key: String) -> String {
        L10n.t(key, language: self.language)
    }
}

private struct IssueNavigatorSplitView<Sidebar: View, Detail: View>: NSViewRepresentable {
    let sidebarMinWidth: CGFloat
    let sidebarIdealWidth: CGFloat
    let sidebarMaxWidth: CGFloat
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sidebarMinWidth: self.sidebarMinWidth,
            sidebarIdealWidth: self.sidebarIdealWidth,
            sidebarMaxWidth: self.sidebarMaxWidth
        )
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = IssueNavigatorNSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator

        let sidebarHost = NSHostingView(rootView: self.sidebar())
        sidebarHost.translatesAutoresizingMaskIntoConstraints = false
        sidebarHost.wantsLayer = false
        let detailHost = NSHostingView(rootView: self.detail())
        detailHost.translatesAutoresizingMaskIntoConstraints = false
        detailHost.wantsLayer = false

        context.coordinator.sidebarHost = sidebarHost
        context.coordinator.detailHost = detailHost

        splitView.addArrangedSubview(sidebarHost)
        splitView.addArrangedSubview(detailHost)
        sidebarHost.widthAnchor.constraint(greaterThanOrEqualToConstant: self.sidebarMinWidth).isActive = true
        sidebarHost.widthAnchor.constraint(lessThanOrEqualToConstant: self.sidebarMaxWidth).isActive = true
        detailHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 560).isActive = true
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(240), forSubviewAt: 0)
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(230), forSubviewAt: 1)

        DispatchQueue.main.async {
            splitView.setPosition(self.sidebarIdealWidth, ofDividerAt: 0)
        }

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.sidebarMinWidth = self.sidebarMinWidth
        context.coordinator.sidebarIdealWidth = self.sidebarIdealWidth
        context.coordinator.sidebarMaxWidth = self.sidebarMaxWidth
        context.coordinator.sidebarHost?.rootView = self.sidebar()
        context.coordinator.detailHost?.rootView = self.detail()

        if splitView.frame.width > 0, splitView.subviews.first?.frame.width == 0 {
            splitView.setPosition(self.sidebarIdealWidth, ofDividerAt: 0)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        var sidebarMinWidth: CGFloat
        var sidebarIdealWidth: CGFloat
        var sidebarMaxWidth: CGFloat
        var sidebarHost: NSHostingView<Sidebar>?
        var detailHost: NSHostingView<Detail>?

        init(sidebarMinWidth: CGFloat, sidebarIdealWidth: CGFloat, sidebarMaxWidth: CGFloat) {
            self.sidebarMinWidth = sidebarMinWidth
            self.sidebarIdealWidth = sidebarIdealWidth
            self.sidebarMaxWidth = sidebarMaxWidth
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainSplitPosition proposedPosition: CGFloat,
            ofSubviewAt _: Int
        ) -> CGFloat {
            let maximum = min(self.sidebarMaxWidth, splitView.bounds.width - 560 - splitView.dividerThickness)
            return min(max(proposedPosition, self.sidebarMinWidth), maximum)
        }
    }
}

private final class IssueNavigatorNSSplitView: NSSplitView {
    override var dividerThickness: CGFloat {
        1
    }

    override func drawDivider(in rect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        rect.fill()
    }
}

private struct IssueNavigatorSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: self.$text, onSubmit: self.onSubmit)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = self.placeholder
        field.controlSize = .regular
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular), weight: .regular)
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = false
        field.sendsWholeSearchString = true
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = self.$text
        context.coordinator.onSubmit = self.onSubmit
        if field.stringValue != self.text {
            field.stringValue = self.text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }

            self.text.wrappedValue = field.stringValue
        }

        func control(
            _: NSControl,
            textView _: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }

            self.onSubmit()
            return true
        }
    }
}

private struct IssueNavigatorScopePopUp: NSViewRepresentable {
    @Binding var selection: IssueNavigatorScope
    let scopes: [IssueNavigatorScope]
    let language: AppLanguage

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: self.$selection, scopes: self.scopes, language: self.language)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .regular
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.select(_:))
        context.coordinator.configure(popup)
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.selection = self.$selection
        context.coordinator.scopes = self.scopes
        context.coordinator.language = self.language
        context.coordinator.configure(popup)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<IssueNavigatorScope>
        var scopes: [IssueNavigatorScope]
        var language: AppLanguage

        init(selection: Binding<IssueNavigatorScope>, scopes: [IssueNavigatorScope], language: AppLanguage) {
            self.selection = selection
            self.scopes = scopes
            self.language = language
        }

        func configure(_ popup: NSPopUpButton) {
            let representedIDs = popup.itemArray.compactMap { $0.representedObject as? String }
            let scopeIDs = self.scopes.map(\.id)
            if representedIDs != scopeIDs {
                popup.removeAllItems()
                for scope in self.scopes {
                    popup.addItem(withTitle: scope.title(language: self.language))
                    popup.lastItem?.representedObject = scope.id
                }
            } else {
                for (index, scope) in self.scopes.enumerated() {
                    popup.item(at: index)?.title = scope.title(language: self.language)
                }
            }
            if let index = self.scopes.firstIndex(of: self.selection.wrappedValue) {
                popup.selectItem(at: index)
            }
        }

        @objc func select(_ popup: NSPopUpButton) {
            let index = popup.indexOfSelectedItem
            guard self.scopes.indices.contains(index) else { return }

            self.selection.wrappedValue = self.scopes[index]
        }
    }
}

private struct IssueNavigatorKindSegmentedControl: NSViewRepresentable {
    @Binding var selection: IssueNavigatorKindFilter
    let language: AppLanguage

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: self.$selection, language: self.language)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: IssueNavigatorKindFilter.allCases.map { $0.title(language: self.language) },
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.select(_:))
        )
        control.controlSize = .regular
        control.segmentStyle = .rounded
        context.coordinator.configure(control)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = self.$selection
        context.coordinator.language = self.language
        context.coordinator.configure(control)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<IssueNavigatorKindFilter>
        var language: AppLanguage

        init(selection: Binding<IssueNavigatorKindFilter>, language: AppLanguage) {
            self.selection = selection
            self.language = language
        }

        func configure(_ control: NSSegmentedControl) {
            let cases = IssueNavigatorKindFilter.allCases
            control.segmentCount = cases.count
            for (index, filter) in cases.enumerated() {
                control.setLabel(filter.title(language: self.language), forSegment: index)
                control.setWidth(0, forSegment: index)
            }
            control.selectedSegment = cases.firstIndex(of: self.selection.wrappedValue) ?? 0
        }

        @objc func select(_ control: NSSegmentedControl) {
            let index = control.selectedSegment
            let cases = IssueNavigatorKindFilter.allCases
            guard cases.indices.contains(index) else { return }

            self.selection.wrappedValue = cases[index]
        }
    }
}

private struct IssueNavigatorBrowserPreview: NSViewRepresentable {
    let url: URL
    let store: IssueNavigatorBrowserStore

    func makeNSView(context _: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context _: Context) {
        let webView = self.store.webView(for: self.url)
        guard webView.superview !== container else {
            webView.frame = container.bounds
            return
        }

        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    static func dismantleNSView(_ container: NSView, coordinator _: ()) {
        for subview in container.subviews {
            subview.removeFromSuperview()
        }
    }
}
