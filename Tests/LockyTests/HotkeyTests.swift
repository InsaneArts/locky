import AppKit
import Carbon
import Testing
@testable import Locky

@MainActor
@Suite struct HotkeyTests {
    private let lockNow = Shortcut(keyCode: UInt16(kVK_ANSI_L), modifiers: [.control, .option, .command])

    @Test func aShortcutRoundTripsThroughSettingsJSON() throws {
        #expect(lockNow.settingsValue == .table(["key": .int(37), "modifiers": .array([.string("control"), .string("option"), .string("command")])]))
        #expect(Shortcut(lockNow.settingsValue) == lockNow)

        let sandbox = try Sandbox()
        var settings = Settings()
        settings.shortcut = lockNow
        try settings.save(config: sandbox.config)
        #expect(Settings.load(config: sandbox.config).settings.shortcut == lockNow)
        // Clearing it removes the key.
        settings.shortcut = nil
        #expect(settings["shortcut"] == .nil)
    }

    @Test func handWrittenShortcutsParseInAnyOrder() {
        let written = LuaValue.table(["key": .int(37), "modifiers": .array([.string("command"), .string("control"), .string("option")])])
        #expect(Shortcut(written) == lockNow)
        // An F-key needs no modifiers list.
        #expect(Shortcut(.table(["key": .int(kVK_F5)])) == Shortcut(keyCode: UInt16(kVK_F5), modifiers: []))
    }

    @Test func whatIsNotAShortcutReadsAsNone() {
        let bad: [LuaValue] = [
            .nil,
            .string("⌃⌥⌘L"),
            .table(["modifiers": .array([.string("command")])]),
            .table(["key": .int(-1), "modifiers": .array([.string("command")])]),
            .table(["key": .double(37.5), "modifiers": .array([.string("command")])]),
            .table(["key": .int(37), "modifiers": .array([.string("cmd")])]),
            .table(["key": .int(37), "modifiers": .array([.int(1)])]),
            .table(["key": .int(37), "modifiers": .string("command")]),
            // A letter alone would lock the screen whenever someone typed it.
            .table(["key": .int(37), "modifiers": .array([])]),
        ]
        for value in bad { #expect(Shortcut(value) == nil, "\(value)") }
    }

    @Test func aShortcutNeedsCommandOrControlExceptAnFKey() {
        let l = UInt16(kVK_ANSI_L)
        #expect(!Shortcut(keyCode: l, modifiers: []).isValid)
        #expect(!Shortcut(keyCode: l, modifiers: [.shift]).isValid)
        #expect(!Shortcut(keyCode: UInt16(kVK_Space), modifiers: [.shift]).isValid)
        // ⌥ alone types characters on many layouts (⌥L is "@" in German), a password's included.
        #expect(!Shortcut(keyCode: l, modifiers: [.option]).isValid)
        #expect(!Shortcut(keyCode: l, modifiers: [.option, .shift]).isValid)
        for modifier: Shortcut.Modifiers in [.command, .control] {
            #expect(Shortcut(keyCode: l, modifiers: [modifier]).isValid)
            #expect(Shortcut(keyCode: l, modifiers: [modifier, .shift]).isValid)
            #expect(Shortcut(keyCode: l, modifiers: [modifier, .option]).isValid)
        }
        // The lock's emergency quit stays free.
        #expect(!Shortcut(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.control, .option, .command]).isValid)
        #expect(Shortcut(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.control, .option, .command, .shift]).isValid)
        for key in [kVK_F1, kVK_F12, kVK_F20] {
            #expect(Shortcut(keyCode: UInt16(key), modifiers: []).isValid)
            #expect(Shortcut(keyCode: UInt16(key), modifiers: [.shift]).isValid)
        }
    }

    @Test func modifiersComeFromTheFourModifierKeysOnly() {
        #expect(Shortcut.Modifiers([.command, .shift, .capsLock, .function, .numericPad]) == [.command, .shift])
        #expect(Shortcut.Modifiers([.control, .option]) == [.control, .option])
        #expect(Shortcut.Modifiers([.capsLock]).isEmpty)
        #expect(Shortcut.Modifiers([.control, .option, .shift, .command]).carbon == UInt32(controlKey | optionKey | shiftKey | cmdKey))
    }

    @Test func keysWithoutALayoutCharacterHaveFixedNames() {
        #expect(Shortcut(keyCode: UInt16(kVK_F5), modifiers: []).display == "F5")
        #expect(Shortcut(keyCode: UInt16(kVK_F20), modifiers: [.shift]).display == "⇧F20")
        #expect(Shortcut(keyCode: UInt16(kVK_Space), modifiers: [.control, .option, .command]).display == "⌃⌥⌘Space")
        #expect(Shortcut(keyCode: UInt16(kVK_Return), modifiers: [.command]).display == "⌘↩")
        #expect(Shortcut(keyCode: UInt16(kVK_Escape), modifiers: [.control]).display == "⌃⎋")
        // macOS's order, whatever the order they were added in.
        #expect(Shortcut(keyCode: UInt16(kVK_F1), modifiers: [.command, .shift, .option, .control]).display == "⌃⌥⇧⌘F1")
    }

    @Test func aLetterKeyShowsTheASCIILayoutsCharacter() {
        let display = lockNow.display
        #expect(display.hasPrefix("⌃⌥⌘"))
        let key = display.dropFirst(3)
        #expect(!key.isEmpty && !key.hasPrefix("Key"), "\(display)")
        // Whatever layout is selected (Georgian, Russian), the L key reads as a Latin letter, as in macOS's menus.
        let latin = key.unicodeScalars.allSatisfy(\.isASCII)
        #expect(latin, "\(display)")
    }

    /// Registers a real hot key for a moment: ⌃⌥⇧⌘F20, which no keyboard in use is likely to press.
    @Test func aShortcutHeldElsewhereIsReportedAndFreedByUnregister() throws {
        let shortcut = Shortcut(keyCode: UInt16(kVK_F20), modifiers: [.control, .option, .shift, .command])
        let first = HotkeyCenter {}
        try first.register(shortcut)
        #expect(first.shortcut == shortcut)

        let second = HotkeyCenter {}
        #expect(throws: HotkeyError(status: OSStatus(eventHotKeyExistsErr))) { try second.register(shortcut) }
        #expect(second.shortcut == nil)

        first.unregister()
        #expect(first.shortcut == nil)
        try second.register(shortcut)
        // Registering again replaces the registration instead of colliding with it.
        try second.register(shortcut)
        second.unregister()
    }

    @Test func registrationErrorsReadAsSentences() {
        #expect(HotkeyError(status: OSStatus(eventHotKeyExistsErr)).localizedDescription == "Another app already uses this shortcut")
        #expect(HotkeyError(status: OSStatus(eventInternalErr)).localizedDescription == "macOS does not allow this shortcut")
        #expect(HotkeyError(status: -50).localizedDescription == "Could not register the shortcut (error -50)")
    }
}
