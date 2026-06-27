import AppKit
import RepoPeekCore
import SwiftUI

struct MenuRepoFiltersView: View {
    @Bindable var session: Session
    let repositoryCandidateCount: Int
    let onSearchChange: (String) -> Void
    let onRefresh: () -> Void

    private var availableFilters: [MenuRepoSelection] {
        if self.session.account.isLoggedIn {
            return MenuRepoSelection.allCases
        }
        // Only local filter when logged out (All/Pinned/Work require GitLab)
        return [.local]
    }

    private var filterSelection: Binding<MenuRepoSelection> {
        Binding(
            get: {
                if self.session.account.isLoggedIn { return self.session.menuRepoSelection }
                return .local
            },
            set: { newValue in
                if self.session.account.isLoggedIn {
                    self.session.menuRepoSelection = newValue
                } else {
                    self.session.menuRepoSelection = .local
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            MenuRepoSearchField(
                text: self.searchQuery,
                placeholder: self.t("Search current list"),
                clearLabel: self.t("Clear search")
            )
            .frame(height: 28)

            HStack(spacing: 10) {
                self.filterGroup

                Spacer(minLength: 8)

                self.actionGroup
            }
            .font(.subheadline)
        }
        .padding(.horizontal, MenuStyle.filterHorizontalPadding)
        .padding(.vertical, MenuStyle.filterVerticalPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: self.session.settings.repoList.menuSortKey) { _, _ in
            NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
        }
        .onChange(of: self.session.menuRepoSelection) { _, _ in
            NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
        }
        .onChange(of: self.session.menuRepoSearchQuery) { _, newValue in
            if Self.hasSearchQuery(newValue) {
                self.session.menuRepoSearchExpanded = true
            }
        }
        .onChange(of: self.repositoryCandidateCount) { _, newValue in
            if !Self.offersSearch(
                repositoryCandidateCount: newValue,
                hasSearchQuery: self.hasSearchQuery
            ) {
                self.session.menuRepoSearchExpanded = false
            }
        }
        .onAppear {
            if self.hasSearchQuery {
                self.session.menuRepoSearchExpanded = true
            }
        }
    }

    private var filterGroup: some View {
        HStack(spacing: 0) {
            ForEach(Array(self.availableFilters.enumerated()), id: \.element) { index, selection in
                let label = self.t(selection.label)
                MenuFilterBarButton(
                    isSelected: self.filterSelection.wrappedValue == selection,
                    fixedWidth: selection.menuBarWidth
                ) {
                    self.filterSelection.wrappedValue = selection
                } label: {
                    Text(label)
                        .fontWeight(self.filterSelection.wrappedValue == selection ? .semibold : .medium)
                }
                .accessibilityLabel(label)

                if index < self.availableFilters.count - 1 {
                    MenuFilterBarDivider()
                }
            }
        }
        .padding(2)
        .background(MenuFilterBarBackground())
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    private var actionGroup: some View {
        HStack(spacing: 6) {
            if self.filterSelection.wrappedValue.showsSortControl {
                self.iconButton(
                    isActive: true,
                    symbolName: self.session.settings.repoList.menuSortKey.menuSymbolName,
                    accessibilityLabel: self.format(
                        "Sort by %@",
                        self.t(self.session.settings.repoList.menuSortKey.menuLabel)
                    ),
                    help: self.format(
                        "Sort by %@. Click to cycle.",
                        self.t(self.session.settings.repoList.menuSortKey.menuLabel)
                    ),
                    action: self.cycleSortKey
                )
            }

            self.iconButton(
                isActive: self.session.isRefreshingRepositories || self.session.localProjectsScanInProgress,
                symbolName: self.refreshButtonSymbol,
                accessibilityLabel: self.t("Refresh Now"),
                help: self.t("Refresh Now"),
                action: self.onRefresh
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func iconButton(
        isActive: Bool,
        symbolName: String,
        accessibilityLabel: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        MenuFilterIconButton(isActive: isActive, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .medium))
        }
        .accessibilityLabel(accessibilityLabel)
        .help(help)
    }

    private func cycleSortKey() {
        let cases = RepositorySortKey.menuCases
        guard let index = cases.firstIndex(of: self.session.settings.repoList.menuSortKey) else {
            self.session.settings.repoList.menuSortKey = cases[0]
            return
        }

        self.session.settings.repoList.menuSortKey = cases[(index + 1) % cases.count]
    }

    private var searchQuery: Binding<String> {
        Binding(
            get: { self.session.menuRepoSearchQuery },
            set: { newValue in
                self.session.menuRepoSearchQuery = newValue
                self.session.menuRepoSearchExpanded = Self.hasSearchQuery(newValue)
                self.onSearchChange(newValue)
                if !Self.hasSearchQuery(newValue) {
                    NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
                }
            }
        )
    }

    private var hasSearchQuery: Bool {
        Self.hasSearchQuery(self.session.menuRepoSearchQuery)
    }

    private var refreshButtonSymbol: String {
        if self.session.isRefreshingRepositories || self.session.localProjectsScanInProgress {
            return "arrow.triangle.2.circlepath"
        }
        return "arrow.clockwise"
    }

    nonisolated static func offersSearch(repositoryCandidateCount: Int, hasSearchQuery: Bool) -> Bool {
        hasSearchQuery || repositoryCandidateCount > 0
    }

    nonisolated static func showsSearchField(
        repositoryCandidateCount _: Int,
        hasSearchQuery _: Bool,
        isExpanded _: Bool
    ) -> Bool {
        true
    }

    private static func hasSearchQuery(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }

    private func format(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, settings: self.session.settings, arguments)
    }
}

private struct MenuRepoSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let clearLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: self.$text)
    }

    func makeNSView(context: Context) -> NativeMenuRepoSearchField {
        let field = NativeMenuRepoSearchField()
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.bezelStyle = .roundedBezel
        field.controlSize = .small
        field.font = .preferredFont(forTextStyle: .subheadline)
        field.focusRingType = .none
        field.onCancel = { [weak field] in
            guard let field else { return false }

            if field.stringValue.isEmpty {
                return false
            }

            field.stringValue = ""
            context.coordinator.updateText("")
            return true
        }
        return field
    }

    func updateNSView(_ field: NativeMenuRepoSearchField, context: Context) {
        context.coordinator.text = self.$text
        field.placeholderString = self.placeholder
        field.toolTip = self.placeholder
        if let cell = field.cell as? NSSearchFieldCell {
            cell.searchButtonCell?.setAccessibilityTitle(self.placeholder)
            cell.cancelButtonCell?.setAccessibilityTitle(self.clearLabel)
        }
        if field.stringValue != self.text {
            field.stringValue = self.text
        }
        field.focusWhenAttached()
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }

            self.updateText(field.stringValue)
        }

        func updateText(_ value: String) {
            if self.text.wrappedValue != value {
                self.text.wrappedValue = value
            }
        }
    }
}

private final class NativeMenuRepoSearchField: NSSearchField {
    var onCancel: (() -> Bool)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 28)
    }

    override var needsPanelToBecomeKey: Bool {
        false
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyCode.escape, self.onCancel?() == true {
            return
        }

        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard Self.isPlainTyping(flags: flags) else {
            return false
        }

        return super.performKeyEquivalent(with: event)
    }

    func focusWhenAttached() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }

            if window.firstResponder !== self.currentEditor() {
                window.makeFirstResponder(self)
            }
        }
    }

    private enum KeyCode {
        static let escape: UInt16 = 53
    }

    private static func isPlainTyping(flags: NSEvent.ModifierFlags) -> Bool {
        var typingFlags = flags
        typingFlags.remove(.shift)
        typingFlags.remove(.capsLock)
        typingFlags.remove(.numericPad)

        return typingFlags.isEmpty
    }
}

private struct MenuFilterBarButton<Label: View>: View {
    let isSelected: Bool
    var fixedWidth: CGFloat?
    let action: () -> Void
    private let label: Label

    init(
        isSelected: Bool,
        fixedWidth: CGFloat? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.isSelected = isSelected
        self.fixedWidth = fixedWidth
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: self.action) {
            self.label
                .foregroundStyle(self.isSelected ? Color.primary : Color.secondary)
                .frame(width: self.fixedWidth, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if self.isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.16))
            }
        }
    }
}

private struct MenuFilterIconButton<Label: View>: View {
    let isActive: Bool
    let action: () -> Void
    private let label: Label

    init(
        isActive: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.isActive = isActive
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: self.action) {
            self.label
                .foregroundStyle(self.isActive ? Color.primary : Color.secondary)
                .frame(width: 34, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(self.isActive ? 0.1 : 0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 0.5)
                }
        }
    }
}

private struct MenuFilterBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.45))
            .frame(width: 1, height: 14)
    }
}

private struct MenuFilterBarBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
            }
    }
}

private extension MenuRepoSelection {
    var menuBarWidth: CGFloat {
        switch self {
        case .all: 38
        case .pinned: 58
        case .local: 50
        case .work: 50
        }
    }
}

struct RecentPullRequestFiltersView: View {
    @Bindable var session: Session

    var body: some View {
        HStack(spacing: 6) {
            Picker(self.t("Scope"), selection: self.$session.recentPullRequestScope) {
                ForEach(RecentPullRequestScope.allCases, id: \.self) { scope in
                    Text(self.t(scope.label)).tag(scope)
                }
            }
            .labelsHidden()
            .font(.subheadline)
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()

            Spacer(minLength: 2)

            Picker(self.t("Engagement"), selection: self.$session.recentPullRequestEngagement) {
                ForEach(RecentPullRequestEngagement.allCases, id: \.self) { engagement in
                    Label(self.t(engagement.label), systemImage: engagement.systemImage)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(self.t(engagement.label))
                        .tag(engagement)
                }
            }
            .labelsHidden()
            .font(.subheadline)
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, MenuStyle.filterHorizontalPadding)
        .padding(.vertical, MenuStyle.filterVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: self.session.recentPullRequestScope) { _, _ in
            NotificationCenter.default.post(name: .recentListFiltersDidChange, object: nil)
        }
        .onChange(of: self.session.recentPullRequestEngagement) { _, _ in
            NotificationCenter.default.post(name: .recentListFiltersDidChange, object: nil)
        }
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }
}
