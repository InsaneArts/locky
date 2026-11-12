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

    /// A window another app shows above the shields (macOS's "Allow accessory to connect?") hands the lock over. The
    /// lock's own windows, the pointer (the window server's), and windows that show nothing do not count.
    @Test func onlyAnotherAppsVisibleWindowAboveTheLockCounts() {
        func window(_ owner: String, pid: Int32, width: Double = 400, height: Double = 200, alpha: Double = 1) -> [String: Any] {
            [kCGWindowOwnerName as String: owner, kCGWindowOwnerPID as String: pid, kCGWindowAlpha as String: alpha,
             kCGWindowBounds as String: ["X": 0.0, "Y": 0.0, "Width": width, "Height": height]]
        }
        let own: Int32 = 100
        #expect(LockSession.windowsAbove([], ownPID: own).isEmpty)
        #expect(LockSession.windowsAbove([window("Locky", pid: own)], ownPID: own).isEmpty)
        #expect(LockSession.windowsAbove([window("Window Server", pid: 50, width: 28, height: 28)], ownPID: own).isEmpty)
        #expect(LockSession.windowsAbove([window("UserNotificationCenter", pid: 7, alpha: 0)], ownPID: own).isEmpty)
        #expect(LockSession.windowsAbove([window("UserNotificationCenter", pid: 7, width: 0, height: 0)], ownPID: own).isEmpty)
        #expect(LockSession.windowsAbove([window("Window Server", pid: 50, width: 28, height: 28), window("UserNotificationCenter", pid: 7)],
                                         ownPID: own) == ["UserNotificationCenter"])
    }
}
