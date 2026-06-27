import AppKit
import RepoPeekCore
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var shortcut: MenuKeyboardShortcut
    let noneLabel: String
    let recordingLabel: String
    let clearLabel: String

    var body: some View {
        HStack(spacing: 8) {
            ShortcutRecorderField(
                shortcut: self.$shortcut,
                noneLabel: self.noneLabel,
                recordingLabel: self.recordingLabel
            )
            .frame(width: 112, height: 30)

            Button {
                self.shortcut = .none
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(self.shortcut.isEnabled == false)
            .opacity(self.shortcut.isEnabled ? 1 : 0.45)
            .help(self.clearLabel)
            .accessibilityLabel(self.clearLabel)
        }
    }
}

private struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: MenuKeyboardShortcut
    let noneLabel: String
    let recordingLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: self.$shortcut)
    }

    func makeNSView(context: Context) -> NativeShortcutRecorderField {
        let view = NativeShortcutRecorderField()
        view.onShortcut = { shortcut in
            context.coordinator.shortcut.wrappedValue = shortcut
        }
        return view
    }

    func updateNSView(_ view: NativeShortcutRecorderField, context: Context) {
        context.coordinator.shortcut = self.$shortcut
        view.shortcut = self.shortcut
        view.noneLabel = self.noneLabel
        view.recordingLabel = self.recordingLabel
        view.updateDisplay()
    }

    final class Coordinator {
        var shortcut: Binding<MenuKeyboardShortcut>

        init(shortcut: Binding<MenuKeyboardShortcut>) {
            self.shortcut = shortcut
        }
    }
}

private final class NativeShortcutRecorderField: NSView {
    var shortcut: MenuKeyboardShortcut = .none
    var noneLabel = "None"
    var recordingLabel = "Press shortcut"
    var onShortcut: ((MenuKeyboardShortcut) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.configure()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        self.setRecording(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        self.setRecording(false)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
        self.setRecording(true)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard self.isRecording else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case KeyCode.escape:
            self.finishRecording()
        case KeyCode.delete, KeyCode.forwardDelete:
            self.applyShortcut(.none)
        default:
            guard let shortcut = MenuKeyboardShortcut(event: event) else {
                NSSound.beep()
                return
            }

            self.applyShortcut(shortcut)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard self.isRecording else {
            return super.performKeyEquivalent(with: event)
        }

        self.keyDown(with: event)
        return true
    }

    func updateDisplay() {
        self.label.stringValue = self.isRecording ? self.recordingLabel : self.displayLabel
        self.label.textColor = self.shortcut.isEnabled ? .labelColor : .secondaryLabelColor
        self.layer?.borderColor = self.isRecording
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        self.layer?.backgroundColor = self.isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            : NSColor.textBackgroundColor.withAlphaComponent(0.78).cgColor
    }

    private var displayLabel: String {
        self.shortcut.isEnabled ? self.shortcut.label : self.noneLabel
    }

    private func configure() {
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.layer?.borderWidth = 1
        self.addSubview(self.label)
        self.label.alignment = .center
        self.label.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        self.label.lineBreakMode = .byTruncatingTail
        self.label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
            self.label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
            self.label.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
        self.updateDisplay()
    }

    private func applyShortcut(_ shortcut: MenuKeyboardShortcut) {
        self.shortcut = shortcut
        self.onShortcut?(shortcut)
        self.finishRecording()
    }

    private func finishRecording() {
        self.setRecording(false)
        if self.window?.firstResponder === self {
            self.window?.makeFirstResponder(nil)
        }
    }

    private func setRecording(_ isRecording: Bool) {
        guard self.isRecording != isRecording else { return }

        self.isRecording = isRecording
        self.updateDisplay()
    }

    private enum KeyCode {
        static let escape: UInt16 = 53
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
    }
}
