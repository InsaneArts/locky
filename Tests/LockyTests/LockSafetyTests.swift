import AppKit
import Testing
@testable import Locky

/// The lock's ways out and its hold on the keyboard.
@MainActor
@Suite struct LockSafetyTests {
    private func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                         characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: code)!
    }

    @Test func onlyControlOptionCommandQSwitchesToTheMacOSLock() {
        #expect(LockSession.isEmergencyExit(key(12, [.control, .option, .command])))
        // Caps Lock or Fn on does not stop it.
        #expect(LockSession.isEmergencyExit(key(12, [.control, .option, .command, .capsLock, .function])))
        #expect(!LockSession.isEmergencyExit(key(12, [.control, .option, .command, .shift])))
        #expect(!LockSession.isEmergencyExit(key(12, [.control, .command])))
        #expect(!LockSession.isEmergencyExit(key(13, [.control, .option, .command])))
    }
}
