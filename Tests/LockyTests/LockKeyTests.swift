import AppKit
import SwiftUI
import Testing
@testable import Locky

/// The Touch ID button. No test installs the event tap or locks: the watchdog's clock and the macOS lock are stand-ins.
@MainActor @Suite struct LockKeyTests {
    /// A clock that runs only when the test says, and a record of what the button did.
    @MainActor final class Harness {
        var scheduled: [(at: Double, work: @MainActor () -> Void)] = []
        var now = 0.0
        var locks = 0
        var engaged: [String] = []
        var locked = false
        var up = false
        /// When the lock comes up, in seconds after the press; nil: never.
        var upAt: Double?

        lazy var key = LockKey(isLocked: { [unowned self] in locked }, lockIsUp: { [unowned self] in up || upAt.map { now >= $0 } == true },
                               lock: { [unowned self] in locks += 1 },
                               engage: { [unowned self] in engaged.append($0); return true },
                               after: { [unowned self] seconds, work in scheduled.append((now + seconds, work)) })

        /// Runs what is due, in time order, until nothing is left.
        func runAll() {
            while let next = scheduled.indices.min(by: { scheduled[$0].at < scheduled[$1].at }) {
                let item = scheduled.remove(at: next)
                now = item.at
                item.work()
            }
        }
    }

    /// Only type 14, subtype 16, data1 0 is dropped, and only with the tap on and no lock on or starting.
    @Test(arguments: [UInt32(14), 10, 11], [Int16(16), 8, 0])
    func onlyTheButtonsPressIsDropped(_ type: UInt32, _ subtype: Int16) {
        for data1 in [0, 1, 0x0a00] {
            for enabled in [true, false] {
                for locked in [true, false] {
                    let expected = type == 14 && subtype == 16 && data1 == 0 && enabled && !locked
                    #expect(LockKey.shouldBlock(type: type, subtype: subtype, data1: data1, enabled: enabled, locked: locked) == expected)
                }
            }
        }
    }

    /// A press as macOS posts it reads as subtype 16, data1 0; a key press is no system-defined event.
    @Test func thePressReadsAsSubtype16() throws {
        let press = try #require(NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                    context: nil, subtype: 16, data1: 0, data2: 0)?.cgEvent)
        let fields = try #require(LockKey.fields(press))
        #expect(fields.subtype == 16 && fields.data1 == 0)
        #expect(LockKey.shouldBlock(type: press.type.rawValue, subtype: fields.subtype, data1: fields.data1, enabled: true, locked: false))
        let key = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        #expect(LockKey.fields(key) == nil)
    }

    /// No lock within 2 seconds of a dropped press: the macOS lock screen, once.
    @Test func noLockMeansTheMacOSLockScreen() {
        let harness = Harness()
        harness.key.pressed()
        #expect(harness.key.pending)
        harness.runAll()
        #expect(harness.locks == 1)
        #expect(harness.engaged.count == 1)
        #expect(abs(harness.now - LockKey.deadline) < 1e-9)
        #expect(!harness.key.pending)
    }

    /// A lock that comes up in time ends the wait, also when it is unlocked again before 2 seconds.
    @Test func aLockInTimeLeavesTheMacOSLockScreenAlone() {
        let harness = Harness()
        harness.upAt = 0.3
        harness.key.pressed()
        harness.runAll()
        #expect(harness.locks == 1 && harness.engaged.isEmpty && !harness.key.pending)
        #expect(harness.now < 0.5)
    }

    /// A lock that comes up just before the deadline counts.
    @Test func theLastLookCounts() {
        let late = Harness()
        late.upAt = LockKey.deadline - 0.05
        late.key.pressed()
        late.runAll()
        #expect(late.engaged.isEmpty)
    }

    /// settings.json's lock_key: off when missing; on stores true, off stores no key.
    @Test func theSettingIsOffByDefault() {
        var settings = Settings()
        #expect(settings.lockKey == false)
        settings.lockKey = true
        #expect(settings["lock_key"] == .bool(true))
        #expect(Settings(["lock_key": .bool(true)]).lockKey)
        #expect(Settings(["lock_key": .string("yes")]).lockKey == false)
        settings.lockKey = false
        #expect(settings["lock_key"].isNil)
    }

    /// The Welcome's page 2 footer names the Touch ID button only while it still shows the macOS lock screen.
    @Test func theFooterNamesTheButtonAsItBehaves() {
        #expect(WelcomeView.lockScreenFooter(hasButton: true, buttonLocks: false)
            == "The Apple menu's Lock Screen, ⌃⌘Q, and the Touch ID button still show the macOS lock screen. Locky does not change the macOS password setting.")
        let without = "The Apple menu's Lock Screen and ⌃⌘Q still show the macOS lock screen. Locky does not change the macOS password setting."
        #expect(WelcomeView.lockScreenFooter(hasButton: true, buttonLocks: true) == without)
        #expect(WelcomeView.lockScreenFooter(hasButton: false, buttonLocks: false) == without)
    }

    /// The row builds with and without Accessibility, in both appearances, and its switch writes lock_key.
    @Test(arguments: [true, false], [NSAppearance.Name.aqua, .darkAqua])
    func theRowBuilds(_ trusted: Bool, _ appearance: NSAppearance.Name) throws {
        _ = NSApplication.shared
        let sandbox = try Sandbox()
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        let view = NSHostingView(rootView: Form { LockKeyToggle(model: model, trusted: .constant(trusted)) }.formStyle(.grouped))
        view.appearance = NSAppearance(named: appearance)
        view.frame.size = CGSize(width: 520, height: 200)
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.height > 0)
        model.store.bool("lock_key", default: false).wrappedValue = true
        #expect(model.store.settings.lockKey)
    }
}
