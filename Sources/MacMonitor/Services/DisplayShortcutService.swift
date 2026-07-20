import AppKit
import Carbon
import CoreGraphics

public struct DisplayKeyboardShortcut: Codable, Hashable {
    public let keyCode: UInt32
    public let modifiers: UInt
    public let keyLabel: String

    public init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
        self.keyLabel = keyLabel
    }

    public var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
            .intersection(.deviceIndependentFlagsMask)
    }

    public var displayText: String {
        var text = ""
        let flags = modifierFlags
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + keyLabel
    }
}

public enum DisplayShortcutAction {
    case multiDisplayPower
    case reconnectAll
}

@MainActor
public final class DisplayShortcutService: ObservableObject {
    public static let shared = DisplayShortcutService()

    @Published public private(set) var shortcuts: [String: DisplayKeyboardShortcut] = [:]
    @Published public private(set) var multiDisplayIdentifiers: Set<String> = []

    private let storageKey = "MacMonitor.displayKeyboardShortcuts"
    private let multiDisplayIdentifiersKey = "MacMonitor.multiDisplayShortcutIdentifiers"
    private let multiDisplayActionKey = "__multiDisplayPower__"
    private let reconnectAllActionKey = "__reconnectAllDisplays__"
    private let hotKeySignature: OSType = 0x4D4D4F4E // "MMON"
    private var eventHandler: EventHandlerRef?
    private var registrations: [String: EventHotKeyRef] = [:]
    private var displayIdentifierByHotKeyID: [UInt32: String] = [:]
    private var nextHotKeyID: UInt32 = 1

    private init() {
        installEventHandler()
        loadShortcuts()
        loadMultiDisplayIdentifiers()
        registerStoredShortcuts()
    }

    public func shortcut(for displayIdentifier: DisplayIdentifier) -> DisplayKeyboardShortcut? {
        shortcuts[displayIdentifier.id]
    }

    public func shortcut(for action: DisplayShortcutAction) -> DisplayKeyboardShortcut? {
        shortcuts[actionKey(for: action)]
    }

    public func isIncludedInMultiDisplayShortcut(_ displayIdentifier: DisplayIdentifier) -> Bool {
        multiDisplayIdentifiers.contains(displayIdentifier.id)
    }

    public func setIncludedInMultiDisplayShortcut(
        _ included: Bool,
        displayIdentifier: DisplayIdentifier
    ) {
        if included {
            multiDisplayIdentifiers.insert(displayIdentifier.id)
        } else {
            multiDisplayIdentifiers.remove(displayIdentifier.id)
        }
        persistMultiDisplayIdentifiers()
    }

    public func clearShortcuts() {
        for identifier in Array(registrations.keys) {
            unregisterShortcut(for: identifier)
        }
        shortcuts.removeAll()
        multiDisplayIdentifiers.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: multiDisplayIdentifiersKey)
    }

    @discardableResult
    public func setShortcut(
        _ shortcut: DisplayKeyboardShortcut?,
        for displayIdentifier: DisplayIdentifier
    ) -> Bool {
        setShortcut(shortcut, forKey: displayIdentifier.id)
    }

    @discardableResult
    public func setShortcut(
        _ shortcut: DisplayKeyboardShortcut?,
        for action: DisplayShortcutAction
    ) -> Bool {
        setShortcut(shortcut, forKey: actionKey(for: action))
    }

    private func setShortcut(_ shortcut: DisplayKeyboardShortcut?, forKey key: String) -> Bool {
        let previousShortcut = shortcuts[key]

        if let shortcut,
           shortcuts.contains(where: {
               $0.key != key &&
               $0.value.keyCode == shortcut.keyCode &&
               $0.value.modifiers == shortcut.modifiers
           }) {
            return false
        }

        unregisterShortcut(for: key)

        if let shortcut {
            guard register(shortcut, for: key) else {
                if let previousShortcut {
                    _ = register(previousShortcut, for: key)
                }
                return false
            }
            shortcuts[key] = shortcut
        } else {
            shortcuts.removeValue(forKey: key)
        }

        persistShortcuts()
        return true
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            let service = Unmanaged<DisplayShortcutService>
                .fromOpaque(userData)
                .takeUnretainedValue()
            Task { @MainActor in
                service.handleHotKey(id: hotKeyID.id)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func registerStoredShortcuts() {
        for (identifier, shortcut) in shortcuts {
            _ = register(shortcut, for: identifier)
        }
    }

    private func register(_ shortcut: DisplayKeyboardShortcut, for identifier: String) -> Bool {
        guard eventHandler != nil else { return false }

        let hotKeyID = nextHotKeyID
        nextHotKeyID &+= 1

        var registration: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            carbonModifiers(from: shortcut.modifierFlags),
            EventHotKeyID(signature: hotKeySignature, id: hotKeyID),
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &registration
        )

        guard status == noErr, let registration else { return false }
        registrations[identifier] = registration
        displayIdentifierByHotKeyID[hotKeyID] = identifier
        return true
    }

    private func unregisterShortcut(for identifier: String) {
        guard let registration = registrations.removeValue(forKey: identifier) else { return }
        UnregisterEventHotKey(registration)
        displayIdentifierByHotKeyID = displayIdentifierByHotKeyID.filter { $0.value != identifier }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private func handleHotKey(id: UInt32) {
        guard let identifier = displayIdentifierByHotKeyID[id] else {
            NSSound.beep()
            return
        }

        let success: Bool
        switch identifier {
        case multiDisplayActionKey:
            success = DisplayPowerService.shared.toggleDisplays(
                withIdentifiers: multiDisplayIdentifiers
            )
        case reconnectAllActionKey:
            success = DisplayPowerService.shared.resetDisplayConnections()
        default:
            guard let display = DisplayManager.shared.displays.first(where: {
                $0.identifier.id == identifier
            }) else {
                NSSound.beep()
                return
            }
            success = DisplayPowerService.shared.toggleDisplay(display)
        }

        if success {
            DisplayManager.shared.refreshDisplays()
        } else {
            NSSound.beep()
        }
    }

    private func loadShortcuts() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([String: DisplayKeyboardShortcut].self, from: data) else {
            return
        }
        shortcuts = stored
    }

    private func loadMultiDisplayIdentifiers() {
        let stored = UserDefaults.standard.stringArray(forKey: multiDisplayIdentifiersKey) ?? []
        multiDisplayIdentifiers = Set(stored)
    }

    private func persistShortcuts() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func persistMultiDisplayIdentifiers() {
        UserDefaults.standard.set(Array(multiDisplayIdentifiers).sorted(), forKey: multiDisplayIdentifiersKey)
    }

    private func actionKey(for action: DisplayShortcutAction) -> String {
        switch action {
        case .multiDisplayPower:
            return multiDisplayActionKey
        case .reconnectAll:
            return reconnectAllActionKey
        }
    }
}
