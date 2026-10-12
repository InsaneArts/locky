import AppKit
import Carbon

/// A global keyboard shortcut: a virtual key code, which names a key by its place on the keyboard (kVK_ANSI_L is
/// where US keyboards have L), and the modifiers held with it. settings.json keeps it as
/// `{ "key": 37, "modifiers": ["control", "option", "command"] }`.
struct Shortcut: Equatable, Sendable {
    struct Modifiers: OptionSet, Sendable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        /// In the order macOS shows them: ⌃⌥⇧⌘.
        private static let table: [(modifier: Modifiers, name: String, symbol: String, flag: NSEvent.ModifierFlags, carbon: Int)] = [
            (.control, "control", "⌃", .control, controlKey),
            (.option, "option", "⌥", .option, optionKey),
            (.shift, "shift", "⇧", .shift, shiftKey),
            (.command, "command", "⌘", .command, cmdKey),
        ]

        /// The four modifiers in `flags`; Caps Lock, Fn, and the rest are left out.
        init(_ flags: NSEvent.ModifierFlags) {
            self.init(Self.table.filter { flags.contains($0.flag) }.map(\.modifier))
        }

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// From settings.json's names; nil if one is not a modifier's name.
        init?(names: [LuaValue]) {
            var modifiers: Modifiers = []
            for name in names {
                guard let entry = Self.table.first(where: { $0.name == name.string }) else { return nil }
                modifiers.insert(entry.modifier)
            }
            self = modifiers
        }

        var names: [String] { Self.table.filter { contains($0.modifier) }.map(\.name) }
        var symbols: String { Self.table.filter { contains($0.modifier) }.map(\.symbol).joined() }
        var carbon: UInt32 { UInt32(Self.table.filter { contains($0.modifier) }.reduce(0) { $0 | $1.carbon }) }
    }

    var keyCode: UInt16
    var modifiers: Modifiers

    init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// From settings.json. A missing modifiers list is none. nil if the value is not a shortcut, or breaks the
    /// rule in `isValid`: a hand-edited `"modifiers": []` must not turn a letter key into a global shortcut.
    init?(_ value: LuaValue) {
        let names = value["modifiers"].isNil ? [] : value["modifiers"].array
        guard let code = value["key"].int, let keyCode = UInt16(exactly: code), let names,
              let modifiers = Modifiers(names: names) else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
        guard isValid else { return nil }
    }

    var settingsValue: LuaValue {
        .table(["key": .int(Int(keyCode)), "modifiers": .array(modifiers.names.map(LuaValue.string))])
    }

    /// A global shortcut needs ⌘ or ⌃, so typing never sets it off: ⌥ alone is how many layouts type characters
    /// (⌥L is "@" on a German keyboard), and a global shortcut takes the key from every app, the lock's password
    /// field included. F-keys need neither: nobody types them. ⌃⌥⌘Q is the lock's emergency quit.
    var isValid: Bool {
        if keyCode == UInt16(kVK_ANSI_Q), modifiers == [.control, .option, .command] { return false }
        return !modifiers.isDisjoint(with: [.command, .control]) || Self.functionKeys.contains(Int(keyCode))
    }

    /// As macOS menus show it, such as "⌃⌥⌘L". The key's character comes from the ASCII-capable keyboard layout,
    /// as in macOS's own menus: a Georgian or Russian layout still shows "L" for the L key, and a French one its "L".
    @MainActor
    var display: String { modifiers.symbols + Self.keyName(keyCode) }

    private static let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11,
                                       kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    /// Keys whose character is invisible or the same on every layout.
    private static let keyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
        kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ].merging(functionKeys.enumerated().map { ($1, "F\($0 + 1)") }) { name, _ in name }

    @MainActor
    private static func keyName(_ keyCode: UInt16) -> String {
        if let name = keyNames[Int(keyCode)] { return name }
        guard let character = character(keyCode) else { return "Key \(keyCode)" }
        // Titlecase, as menus show letters: "l" reads "L", and Georgian, whose capitals are for all-caps text only,
        // stays as it is. So does a letter that would grow ("ß" to "Ss").
        let title = character.capitalized
        return title.count == character.count ? title : character
    }

    /// What the key types in the ASCII-capable keyboard layout, without modifiers. nil for keys that type nothing
    /// visible.
    @MainActor
    private static func character(_ keyCode: UInt16) -> String? {
        guard let layout = layoutData(), let bytes = CFDataGetBytePtr(layout) else { return nil }
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate($0, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                           &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length)
        let invisible = CharacterSet.controlCharacters.union(.whitespacesAndNewlines)
        return text.unicodeScalars.allSatisfy(invisible.contains) ? nil : text
    }

    /// The current ASCII-capable keyboard layout's key map (the current layout's when it is one). Text Input Sources
    /// must be read on the main thread.
    @MainActor
    private static func layoutData() -> CFData? {
        for copy in [TISCopyCurrentASCIICapableKeyboardLayoutInputSource, TISCopyCurrentKeyboardLayoutInputSource] {
            if let source = copy()?.takeRetainedValue(), let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
                return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            }
        }
        return nil
    }
}

extension Settings {
    /// settings.json's shortcut: the global Lock Now shortcut. Missing, or not a valid shortcut, is none.
    var shortcut: Shortcut? {
        get { Shortcut(self["shortcut"]) }
        set { self["shortcut"] = newValue?.settingsValue ?? .nil }
    }
}

/// Why a shortcut could not be registered, in words for the settings window.
struct HotkeyError: LocalizedError, Equatable {
    let status: OSStatus

    var errorDescription: String? {
        switch Int(status) {
        case eventHotKeyExistsErr: "Another app already uses this shortcut"
        // macOS 15.0 and 15.1 refused shortcuts with only ⌥, or ⌥⇧, in sandboxed apps, with this error.
        case eventHotKeyInvalidErr, eventInternalErr: "macOS does not allow this shortcut"
        default: "Could not register the shortcut (error \(status))"
        }
    }
}

/// The global Lock Now shortcut, through Carbon hot keys: they need no Accessibility or Input Monitoring permission.
@MainActor
final class HotkeyCenter {
    /// The shortcut registered now.
    private(set) var shortcut: Shortcut?
    fileprivate let action: () -> Void
    /// Tells this center's hot key from another center's: every center's handler sees every press.
    fileprivate let id: UInt32
    nonisolated(unsafe) private var hotKey: EventHotKeyRef?
    nonisolated(unsafe) private var handler: EventHandlerRef?
    private static var nextID: UInt32 = 1

    init(action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// Registers `shortcut` in place of the one before; if that fails, none is registered. The registration is
    /// exclusive, so an app that holds the shortcut exclusively makes this throw, and an app that registers it later
    /// gets no presses while Locky holds it. A shared registration would never report a conflict.
    func register(_ shortcut: Shortcut) throws(HotkeyError) {
        unregister()
        if handler == nil {
            var pressedType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &pressedType,
                                             Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw HotkeyError(status: status) }
        }
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.modifiers.carbon, EventHotKeyID(signature: hotKeySignature, id: id),
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        guard status == noErr, let hotKey else { throw HotkeyError(status: status) }
        self.hotKey = hotKey
        self.shortcut = shortcut
    }

    /// Frees the shortcut, for one while the settings window records a new one.
    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        shortcut = nil
    }
}

/// "LCKY": marks Locky's hot keys.
private let hotKeySignature: OSType = 0x4C43_4B59

/// Carbon calls this on the main thread for each hot key press in the app.
private func hotKeyPressed(_: EventHandlerCallRef?, event: EventRef?, context: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKey = EventHotKeyID()
    guard let event, let context,
          GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                            MemoryLayout<EventHotKeyID>.size, nil, &hotKey) == noErr,
          hotKey.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
    let id = hotKey.id
    let center = Unmanaged<HotkeyCenter>.fromOpaque(context).takeUnretainedValue()
    return MainActor.assumeIsolated {
        guard id == center.id else { return OSStatus(eventNotHandledErr) }
        center.action()
        return noErr
    }
}
