/// A stored global hotkey. `modifiers` holds raw `NSEvent.ModifierFlags` bits
/// (device-independent only); the AppKit conveniences live in the app target.
public struct DisplayKeyboardShortcut: Codable, Hashable {
    public let keyCode: UInt32
    public let modifiers: UInt
    public let keyLabel: String

    public init(keyCode: UInt32, modifiers: UInt, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }
}

public enum DisplayShortcutAction {
    case multiDisplayPower
    case reconnectAll
}
