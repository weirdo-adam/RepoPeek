import AppKit

@MainActor
final class MainMenuSearchMenu: NSMenu {
    nonisolated(unsafe) var onKeyEquivalent: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        if self.onKeyEquivalent?(event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
