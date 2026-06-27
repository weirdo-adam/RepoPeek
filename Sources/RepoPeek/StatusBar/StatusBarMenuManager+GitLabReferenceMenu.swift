import AppKit
import RepoPeekCore

extension StatusBarMenuManager {
    func populateGitLabReferenceMenu(_ menu: NSMenu, matches: [GitLabReferenceMatch]) {
        guard self.gitLabReferenceMenuMatches != matches else { return }

        menu.removeAllItems()
        self.gitLabReferenceMenuMatches = matches

        if matches.count == 1, let match = matches.first {
            self.addGitLabReferenceItems(to: menu, match: match, includeBrowserPreview: true)
            return
        }

        for match in matches {
            let item = NSMenuItem(title: self.gitLabReferenceTitle(for: match), action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: self.gitLabReferenceSystemImage(for: match), accessibilityDescription: match.kind.label)
            item.image?.isTemplate = true

            let submenu = NSMenu()
            submenu.autoenablesItems = false
            self.addGitLabReferenceItems(to: submenu, match: match, includeBrowserPreview: true)
            item.submenu = submenu
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let item = NSMenuItem(
            title: L10n.format(
                "Open %@ refs in Issue Navigator…",
                settings: self.appState.session.settings,
                "\(matches.count)"
            ),
            action: #selector(self.openGitLabReferenceMatchesInIssueNavigator),
            keyEquivalent: ""
        )
        item.target = self
        item.image = NSImage(
            systemSymbolName: "rectangle.and.text.magnifyingglass",
            accessibilityDescription: L10n.t("Issue Navigator", settings: self.appState.session.settings)
        )
        item.image?.isTemplate = true
        menu.addItem(item)
    }

    func addGitLabReferenceItems(to menu: NSMenu, match: GitLabReferenceMatch, includeBrowserPreview: Bool) {
        guard includeBrowserPreview else { return }

        let browserItem = NSMenuItem()
        let browserView = GitLabReferenceBrowserMenuItemView(match: match)
        browserItem.view = browserView
        browserItem.toolTip = self.gitLabReferenceMenuTitle(for: match)
        menu.addItem(browserItem)
    }

    func gitLabReferenceMenuTitle(for match: GitLabReferenceMatch) -> String {
        let state = match.state.map { "\($0.label) " } ?? ""
        let kind = match.kind.label
        return "\(state)\(kind): \(match.title)"
    }

    func gitLabReferenceMenuTitle(for matches: [GitLabReferenceMatch]) -> String {
        if matches.count == 1, let match = matches.first {
            return self.gitLabReferenceMenuTitle(for: match)
        }
        if let repo = self.commonRepositoryFullName(in: matches) {
            return "\(matches.count) GitLab references in \(repo)"
        }
        return "\(matches.count) GitLab references"
    }

    func refreshGitLabReferenceMenuIfNeeded(_ menu: NSMenu) {
        guard menu === self.gitLabReferenceMenu,
              self.appState.session.gitLabReferenceMatches.isEmpty == false
        else {
            return
        }

        self.populateGitLabReferenceMenu(menu, matches: self.appState.session.gitLabReferenceMatches)
    }

    func gitLabReferenceSystemImage(for match: GitLabReferenceMatch) -> String {
        switch match.kind {
        case .issue:
            match.state == .closed ? "checkmark.circle" : "exclamationmark.circle"
        case .pullRequest:
            switch match.state {
            case .merged:
                "arrow.triangle.merge"
            case .closed:
                "xmark.circle"
            case .open, nil:
                "arrow.triangle.branch.circle"
            }
        case .commit:
            "number.square"
        case .workflowRun:
            "play.circle"
        }
    }

    func gitLabReferenceSystemImage(for matches: [GitLabReferenceMatch]) -> String {
        guard matches.count != 1, let first = matches.first else {
            return matches.first.map(self.gitLabReferenceSystemImage(for:)) ?? "number.square"
        }

        if matches.allSatisfy({ $0.kind == first.kind }) {
            return self.gitLabReferenceSystemImage(for: first)
        }
        return "list.bullet.rectangle"
    }

    func gitLabReferenceAccessibilityDescription(for matches: [GitLabReferenceMatch]) -> String {
        if matches.count == 1, let match = matches.first {
            return match.kind.label
        }
        return "\(matches.count) GitLab References"
    }

    func gitLabReferenceTitle(for matches: [GitLabReferenceMatch]) -> String {
        guard matches.count != 1 else {
            return matches.first.map(self.gitLabReferenceTitle(for:)) ?? ""
        }

        let repoSuffix = self.commonRepositoryFullName(in: matches)
            .map { " " + Self.truncatedMiddle($0, maxCharacters: Self.gitLabReferenceRepositoryTitleLimit) }
            ?? ""
        return "\(matches.count) GitLab refs\(repoSuffix)"
    }

    func gitLabReferenceTitle(for match: GitLabReferenceMatch) -> String {
        var parts = [self.gitLabReferenceText(for: match)]
        if let state = match.state?.label {
            parts.append(state)
        }
        parts.append(Self.truncatedMiddle(match.repositoryFullName, maxCharacters: Self.gitLabReferenceRepositoryTitleLimit))
        let prefix = parts.joined(separator: " ")
        let title = Self.truncatedTail(match.title, maxCharacters: Self.gitLabReferenceSummaryTitleLimit)
        return "\(prefix): \(title)"
    }

    func gitLabReferenceText(for match: GitLabReferenceMatch) -> String {
        switch match.query {
        case let .issueNumber(number),
             let .repositoryNameIssueNumber(_, number),
             let .repositoryIssueNumber(_, number):
            "#\(number)"
        case let .commitHash(hash),
             let .repositoryCommitHash(_, hash):
            String(hash.prefix(10))
        case let .repositoryWorkflowRun(_, runID):
            "Run \(runID)"
        }
    }

    func commonRepositoryFullName(in matches: [GitLabReferenceMatch]) -> String? {
        guard let first = matches.first?.repositoryFullName else { return nil }

        return matches.allSatisfy { $0.repositoryFullName.caseInsensitiveCompare(first) == .orderedSame } ? first : nil
    }

    func clampGitLabReferenceStatusItemLength(_ item: NSStatusItem, button: NSStatusBarButton) {
        let fitted = button.fittingSize.width
        let desired = fitted.isFinite && fitted > 0
            ? ceil(fitted + 6)
            : Self.gitLabReferenceMaxStatusItemLength
        item.length = min(desired, Self.gitLabReferenceMaxStatusItemLength)
    }

    static func truncatedTail(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters, maxCharacters > 3 else {
            return value
        }

        return "\(value.prefix(maxCharacters - 3))..."
    }

    static func truncatedMiddle(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters, maxCharacters > 5 else {
            return value
        }

        let available = maxCharacters - 3
        let headCount = available / 2
        let tailCount = available - headCount
        return "\(value.prefix(headCount))...\(value.suffix(tailCount))"
    }
}
