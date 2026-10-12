import AppKit
import Carbon
import Testing
@testable import Locky

@Suite struct ShortcutRecorderTests {
    private func outcome(_ key: Int, _ flags: NSEvent.ModifierFlags = []) -> RecordingOutcome {
        RecordingOutcome(keyCode: UInt16(key), modifierFlags: flags)
    }

    private func shortcut(_ key: Int, _ modifiers: Shortcut.Modifiers) -> RecordingOutcome {
        .record(Shortcut(keyCode: UInt16(key), modifiers: modifiers))
    }

    @Test func escapeCancelsAndDeleteClears() {
        #expect(outcome(kVK_Escape) == .cancel)
        #expect(outcome(kVK_Delete) == .clear)
        #expect(outcome(kVK_ForwardDelete) == .clear)
        // Caps Lock is not a modifier.
        #expect(outcome(kVK_Escape, [.capsLock]) == .cancel)
        // With a modifier they are shortcuts like any other.
        #expect(outcome(kVK_Escape, [.control]) == shortcut(kVK_Escape, [.control]))
        #expect(outcome(kVK_Delete, [.command, .option]) == shortcut(kVK_Delete, [.command, .option]))
    }

    @Test func aKeyThatTypesIsRejected() {
        #expect(outcome(kVK_ANSI_L) == .reject)
        #expect(outcome(kVK_ANSI_L, [.shift]) == .reject)
        #expect(outcome(kVK_Space, [.shift, .capsLock]) == .reject)
        #expect(outcome(kVK_Return) == .reject)
    }

    @Test func aKeyWithCommandControlOrOptionIsRecorded() {
        #expect(outcome(kVK_ANSI_L, [.control, .option, .command]) == shortcut(kVK_ANSI_L, [.control, .option, .command]))
        #expect(outcome(kVK_ANSI_L, [.command, .capsLock]) == shortcut(kVK_ANSI_L, [.command]))
        // Arrows come with the Fn and keypad flags, which are not modifiers either.
        #expect(outcome(kVK_LeftArrow, [.control, .option, .function, .numericPad]) == shortcut(kVK_LeftArrow, [.control, .option]))
    }

    @Test func anFKeyIsRecordedAlone() {
        #expect(outcome(kVK_F5, [.function]) == shortcut(kVK_F5, []))
        #expect(outcome(kVK_F13, [.shift]) == shortcut(kVK_F13, [.shift]))
    }
}
