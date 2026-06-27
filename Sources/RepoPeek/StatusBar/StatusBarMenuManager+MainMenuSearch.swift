import AppKit

extension StatusBarMenuManager {
    func startObservingMainMenuKeys() {
        guard self.mainMenuKeyMonitor == nil else { return }

        self.mainMenuKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleMainMenuKeyDown(event) ?? event
        }
    }

    func stopObservingMainMenuKeys() {
        guard let monitor = self.mainMenuKeyMonitor else { return }

        NSEvent.removeMonitor(monitor)
        self.mainMenuKeyMonitor = nil
    }

    func handleMainMenuKeyDown(_ event: NSEvent) -> NSEvent? {
        self.handleMainMenuSearchKey(event) ? nil : event
    }

    func handleMainMenuKeyEquivalent(_ event: NSEvent) -> Bool {
        self.handleMainMenuSearchKey(event)
    }

    func handleMainMenuSearchKey(_ event: NSEvent) -> Bool {
        guard self.mainMenu != nil else { return false }
        guard !self.shouldLetMainMenuTextInputHandle(event) else { return false }

        if self.hasHandledMainMenuSearchEvent(event) {
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if self.isMainMenuRepoSearchVisible,
           let action = Self.repoSearchKeyAction(from: event, flags: flags)
        {
            self.applyMainMenuRepoSearchKeyAction(action)
            self.markMainMenuSearchEventHandled(event)
            return true
        }

        guard !self.isMainMenuRepoSearchVisible else { return false }
        guard case let .type(token) = Self.repoSearchKeyAction(from: event, flags: flags) else { return false }
        guard self.shouldOfferMainMenuRepoSearch(hasSearchQuery: false) else { return false }

        self.expandMainMenuRepoSearch(initialQuery: token)
        self.markMainMenuSearchEventHandled(event)
        return true
    }

    func shouldLetMainMenuTextInputHandle(_ event: NSEvent) -> Bool {
        guard let menuWindow = self.mainMenuWindow else { return false }

        if let eventWindow = event.window, eventWindow !== menuWindow {
            return false
        }

        return Self.isTextInputFirstResponder(menuWindow.firstResponder)
    }

    var mainMenuWindow: NSWindow? {
        self.mainMenu?.items.compactMap(\.view).first { $0.window != nil }?.window
    }

    static func isTextInputFirstResponder(_ responder: NSResponder?) -> Bool {
        guard let responder else { return false }

        return self.isTextInputResponderType(type(of: responder))
    }

    static func isTextInputResponderType(_ responderType: NSResponder.Type) -> Bool {
        responderType is NSTextView.Type || responderType is NSTextField.Type
    }

    func hasHandledMainMenuSearchEvent(_ event: NSEvent) -> Bool {
        event.eventNumber != 0 && self.lastHandledMainMenuKeyEventNumber == event.eventNumber
    }

    func markMainMenuSearchEventHandled(_ event: NSEvent) {
        if event.eventNumber != 0 {
            self.lastHandledMainMenuKeyEventNumber = event.eventNumber
        }
    }
}

private enum RepoSearchKeyAction {
    case type(String)
    case deleteBackward
    case cancel
}

private enum RepoSearchKeyCode {
    static let deleteBackward: UInt16 = 51
    static let escape: UInt16 = 53
    static let forwardDelete: UInt16 = 117
}

extension StatusBarMenuManager {
    private static func repoSearchKeyAction(from event: NSEvent, flags: NSEvent.ModifierFlags) -> RepoSearchKeyAction? {
        if flags == .command,
           (event.charactersIgnoringModifiers ?? "").lowercased() == "v",
           let pasted = NSPasteboard.general.string(forType: .string)?
           .trimmingCharacters(in: .whitespacesAndNewlines),
           pasted.isEmpty == false
        {
            return .type(pasted)
        }

        guard self.isPlainTyping(flags: flags) else { return nil }

        switch event.keyCode {
        case RepoSearchKeyCode.deleteBackward, RepoSearchKeyCode.forwardDelete:
            return .deleteBackward
        case RepoSearchKeyCode.escape:
            return .cancel
        default:
            guard let token = self.repoSearchTypingToken(from: event, flags: flags) else { return nil }

            return .type(token)
        }
    }

    private static func repoSearchTypingToken(from event: NSEvent, flags: NSEvent.ModifierFlags) -> String? {
        guard self.isPlainTyping(flags: flags) else { return nil }

        let token = event.characters ?? event.charactersIgnoringModifiers ?? ""
        guard token.count == 1,
              let scalar = token.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.whitespacesAndNewlines.contains(scalar)
        else { return nil }

        return token
    }

    private static func isPlainTyping(flags: NSEvent.ModifierFlags) -> Bool {
        var typingFlags = flags
        typingFlags.remove(.shift)
        typingFlags.remove(.capsLock)
        typingFlags.remove(.numericPad)

        return typingFlags.isEmpty
    }

    private func applyMainMenuRepoSearchKeyAction(_ action: RepoSearchKeyAction) {
        switch action {
        case let .type(token):
            let query = self.appState.session.menuRepoSearchQuery + token
            self.appState.session.menuRepoSearchExpanded = true
            self.applyMainMenuRepoSearch(query)
        case .deleteBackward:
            var query = self.appState.session.menuRepoSearchQuery
            guard query.isEmpty == false else { return }

            query.removeLast()
            if query.isEmpty {
                self.appState.session.menuRepoSearchExpanded = false
            }
            self.applyMainMenuRepoSearch(query)
            if query.isEmpty {
                self.menuFiltersChanged()
            }
        case .cancel:
            self.appState.session.menuRepoSearchExpanded = false
            if self.hasMainMenuRepoSearchQuery {
                self.applyMainMenuRepoSearch("")
            }
            self.menuFiltersChanged()
        }
    }

    private var isMainMenuRepoSearchVisible: Bool {
        MenuRepoFiltersView.showsSearchField(
            repositoryCandidateCount: self.mainMenuRepositoryCandidateCount(),
            hasSearchQuery: self.hasMainMenuRepoSearchQuery,
            isExpanded: self.appState.session.menuRepoSearchExpanded
        )
    }

    private func shouldOfferMainMenuRepoSearch(hasSearchQuery: Bool) -> Bool {
        MenuRepoFiltersView.offersSearch(
            repositoryCandidateCount: self.mainMenuRepositoryCandidateCount(),
            hasSearchQuery: hasSearchQuery
        )
    }

    private func expandMainMenuRepoSearch(initialQuery: String? = nil) {
        let hasSearchQuery = initialQuery != nil || self.hasMainMenuRepoSearchQuery
        guard self.shouldOfferMainMenuRepoSearch(hasSearchQuery: hasSearchQuery) else { return }

        self.appState.session.menuRepoSearchExpanded = true
        if let initialQuery {
            self.appState.session.menuRepoSearchQuery = initialQuery
        }
        self.menuFiltersChanged()
    }

    private var hasMainMenuRepoSearchQuery: Bool {
        !self.appState.session.menuRepoSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func mainMenuRepositoryCandidateCount() -> Int {
        self.menuBuilder.mainMenuPlan().repos.count
    }
}
