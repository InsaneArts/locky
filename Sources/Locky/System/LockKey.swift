import AppKit
import GuardCore

extension Settings {
    /// settings.json's lock_key: the Touch ID button shows Locky's lock instead of the macOS one. Off when missing.
    var lockKey: Bool {
        get { self["lock_key"].bool ?? false }
        set { self["lock_key"] = newValue ? .bool(true) : .nil }
    }
}

/// The Touch ID button, with lock_key on and Accessibility granted: a press shows Locky's lock, not the macOS one.
///
/// A press posts a system-defined event (type 14, subtype 16, data1 0) about 80 ms before macOS locks, and an active
/// event tap that drops it stops that lock. The tap takes only type 14, drops only that one event, and only while
/// Locky is not locked: during a lock the press goes on to macOS, which locks over Locky. The tap runs on the main
/// thread on purpose: if Locky hangs, macOS turns the tap off and the button locks as before, instead of Locky
/// dropping a press it cannot act on. A dropped press that brings no lock up within 2 seconds locks the Mac with the
/// macOS lock screen.
@MainActor
final class LockKey {
    /// How long a dropped press waits for Locky's lock before the macOS lock screen, and how often it looks.
    nonisolated static let deadline = 2.0
    nonisolated static let interval = 0.1

    private let isLocked: () -> Bool
    private let lockIsUp: () -> Bool
    private let lock: () -> Void
    private let engage: (_ reason: String) -> Bool
    private let after: (_ seconds: Double, _ work: @escaping @MainActor () -> Void) -> Void
    private var tap: (port: CFMachPort, source: CFRunLoopSource)?
    /// From a dropped press until its lock is up or the macOS lock screen was asked for: another press goes to macOS.
    private(set) var pending = false
    /// A subtype 16 event with other data is logged once per launch.
    private var loggedOther = false

    /// `isLocked`: a Locky lock is on. `lockIsUp`: it is on screen and has the keyboard. `lock`: Lock Now's lock.
    /// Tests pass `engage` and `after` so nothing locks and no time passes.
    init(isLocked: @escaping () -> Bool, lockIsUp: @escaping () -> Bool, lock: @escaping () -> Void,
         engage: @escaping (_ reason: String) -> Bool = { SystemLock.engage(reason: $0) },
         after: @escaping (_ seconds: Double, _ work: @escaping @MainActor () -> Void) -> Void = { seconds, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated(work) }
         }) {
        self.isLocked = isLocked
        self.lockIsUp = lockIsUp
        self.lock = lock
        self.engage = engage
        self.after = after
    }

    /// Drop only the Touch ID button's press, and only while the tap is on and Locky is not locked or starting a lock.
    nonisolated static func shouldBlock(type: UInt32, subtype: Int16, data1: Int, enabled: Bool, locked: Bool) -> Bool {
        type == 14 && subtype == 16 && data1 == 0 && enabled && !locked
    }

    /// A system-defined event's subtype and data1; nil for any other event.
    nonisolated static func fields(_ event: CGEvent) -> (subtype: Int16, data1: Int)? {
        guard event.type.rawValue == 14, let event = NSEvent(cgEvent: event), event.type == .systemDefined else { return nil }
        return (event.subtype.rawValue, event.data1)
    }

    /// Installs the tap when `on` (lock_key on and Accessibility granted), and removes it when not.
    func apply(_ on: Bool) {
        if on, tap == nil {
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: 1 << 14,
                                               callback: { _, type, event, key in
                                                   guard let key else { return Unmanaged.passUnretained(event) }
                                                   let lockKey = Unmanaged<LockKey>.fromOpaque(key).takeUnretainedValue()
                                                   let drop = MainActor.assumeIsolated { lockKey.tapped(type, event) }
                                                   return drop ? nil : Unmanaged.passUnretained(event)
                                               }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
                  let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
                LogFile.shared.write(level: "error", message: "the Touch ID button: the event tap failed; the button shows the macOS lock screen",
                                     source: "locky")
                return
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            tap = (port, source)
            LogFile.shared.write(level: "info", message: "the Touch ID button shows Locky's lock", source: "locky")
        } else if !on, let tap {
            CGEvent.tapEnable(tap: tap.port, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tap.source, .commonModes)
            CFMachPortInvalidate(tap.port)
            self.tap = nil
            LogFile.shared.write(level: "info", message: "the Touch ID button shows the macOS lock screen", source: "locky")
        }
    }

    /// An event from the tap. true drops it. Short: macOS turns off a tap that is slow to answer.
    private func tapped(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // While it is off, the button shows the macOS lock screen.
            if let tap { CGEvent.tapEnable(tap: tap.port, enable: true) }
            LogFile.shared.write(level: "warn", message: "the Touch ID button: macOS turned the event tap off (\(type.rawValue)); turned it on again",
                                 source: "locky")
            return false
        }
        guard let (subtype, data1) = Self.fields(event) else { return false }
        if subtype == 16, data1 != 0, !loggedOther {
            loggedOther = true
            LogFile.shared.write(level: "info", message: "the Touch ID button: passed on a subtype 16 event with data1 \(data1)", source: "locky")
        }
        guard Self.shouldBlock(type: type.rawValue, subtype: subtype, data1: data1, enabled: tap != nil, locked: isLocked() || pending) else {
            return false
        }
        pressed()
        return true
    }

    /// A dropped press: Lock Now's lock after the tap returns, and the macOS lock screen if it is not up within 2 seconds.
    func pressed() {
        pending = true
        LogFile.shared.write(level: "info", message: "the Touch ID button: locking", source: "locky")
        after(0) { [self] in lock() }
        watch(checks: Int((Self.deadline / Self.interval).rounded()))
    }

    private func watch(checks: Int) {
        after(Self.interval) { [self] in
            if lockIsUp() {
                pending = false
                return
            }
            guard checks <= 1 else { return watch(checks: checks - 1) }
            pending = false
            let reason = "the Touch ID button: Locky's lock did not come up within 2 seconds"
            if engage(reason) {
                LogFile.shared.write(level: "warn", message: "\(reason); switched to the macOS lock screen", source: "locky")
            } else {
                LogFile.shared.write(level: "error", message: "\(reason), and the macOS lock screen is out of reach", source: "locky")
            }
        }
    }
}
