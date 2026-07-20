import AppKit
import SwiftUI

struct DisplayShortcutRecorder: NSViewRepresentable {
    let shortcut: DisplayKeyboardShortcut?
    var shortcutName = "Display power"
    let onChange: (DisplayKeyboardShortcut?) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.target = context.coordinator
        button.action = #selector(Coordinator.startRecording(_:))
        button.shortcutName = shortcutName
        button.onChange = { shortcut in
            context.coordinator.parent.onChange(shortcut)
        }
        button.updateShortcut(shortcut)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        context.coordinator.parent = self
        button.shortcutName = shortcutName
        button.onChange = { shortcut in
            context.coordinator.parent.onChange(shortcut)
        }
        if !button.isRecording {
            button.updateShortcut(shortcut)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: DisplayShortcutRecorder

        init(parent: DisplayShortcutRecorder) {
            self.parent = parent
        }

        @objc func startRecording(_ sender: ShortcutRecorderButton) {
            sender.beginRecording()
        }
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    var onChange: ((DisplayKeyboardShortcut?) -> Bool)?
    var shortcutName = "Display power"
    private(set) var isRecording = false
    private var shortcut: DisplayKeyboardShortcut?

    override var acceptsFirstResponder: Bool { true }

    func updateShortcut(_ shortcut: DisplayKeyboardShortcut?) {
        self.shortcut = shortcut
        updateTitle()
    }

    func beginRecording() {
        isRecording = true
        title = "Type shortcut…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            finishRecording()
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 { // Delete / Forward Delete
            if onChange?(nil) != false {
                shortcut = nil
            }
            finishRecording()
            return
        }

        let modifiers = event.modifierFlags
            .intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty, !Self.modifierKeyCodes.contains(event.keyCode) else {
            NSSound.beep()
            return
        }

        let newShortcut = DisplayKeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyLabel: Self.keyLabel(for: event)
        )
        if onChange?(newShortcut) != false {
            shortcut = newShortcut
        }
        finishRecording()
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign, isRecording {
            isRecording = false
            updateTitle()
        }
        return didResign
    }

    private func finishRecording() {
        isRecording = false
        updateTitle()
        window?.makeFirstResponder(nil)
    }

    private func updateTitle() {
        title = shortcut?.displayText ?? "Record Shortcut"
        setAccessibilityLabel(shortcut == nil
            ? "Record \(shortcutName.lowercased()) shortcut"
            : "\(shortcutName) shortcut: \(shortcut?.displayText ?? "")")
    }

    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private static func keyLabel(for event: NSEvent) -> String {
        let knownKeys: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 71: "Clear",
            76: "⌅", 115: "Home", 116: "Page Up", 119: "End", 121: "Page Down",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        if let knownKey = knownKeys[event.keyCode] {
            return knownKey
        }
        let characters = event.charactersIgnoringModifiers?.uppercased() ?? ""
        return characters.isEmpty ? "Key \(event.keyCode)" : characters
    }
}
