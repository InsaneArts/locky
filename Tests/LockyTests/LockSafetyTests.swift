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

    @Test func aLockWithoutTheKeyboardTapsItOrHandsOver() {
        #expect(LockSession.keyboardAction(holds: true, tapped: false, trusted: false, secureInput: false) == .keep)
        #expect(LockSession.keyboardAction(holds: false, tapped: true, trusted: true, secureInput: false) == .keep)
        #expect(LockSession.keyboardAction(holds: false, tapped: false, trusted: true, secureInput: false) == .tap)
        #expect(LockSession.keyboardAction(holds: false, tapped: false, trusted: false, secureInput: false) == .handOver)
        // Another app's secure keyboard entry: an event tap would not see the keys, which go to that app.
        #expect(LockSession.keyboardAction(holds: false, tapped: false, trusted: true, secureInput: true) == .handOver)
        #expect(LockSession.keyboardAction(holds: false, tapped: true, trusted: true, secureInput: true) == .handOver)
        #expect(LockSession.keyboardAction(holds: true, tapped: false, trusted: true, secureInput: true) == .keep)
    }
}
