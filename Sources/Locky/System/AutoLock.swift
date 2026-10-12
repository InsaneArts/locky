import AppKit
import IOKit.pwr_mgt

/// settings.json's auto_lock: what locks the screen by itself, as
/// `{ "idle_minutes": 5, "display_sleep": true, "system_sleep": true, "screen_saver": true }`. A missing key is off,
/// and a missing auto_lock is all off.
struct AutoLockSettings: Equatable, Sendable {
    /// Minutes without keyboard, mouse, or trackpad input. nil is off.
    var idleMinutes: Double?
    /// When the displays go to sleep.
    var displaySleep: Bool
    /// Before the Mac sleeps, so the lock is up when it wakes.
    var systemSleep: Bool
    /// When the screen saver starts.
    var screenSaver: Bool

    init(idleMinutes: Double? = nil, displaySleep: Bool = false, systemSleep: Bool = false, screenSaver: Bool = false) {
        self.idleMinutes = idleMinutes
        self.displaySleep = displaySleep
        self.systemSleep = systemSleep
        self.screenSaver = screenSaver
    }

    init(_ value: LuaValue) {
        self.init(idleMinutes: value["idle_minutes"].number.flatMap { $0 > 0 && $0.isFinite ? $0 : nil },
                  displaySleep: value["display_sleep"].bool ?? false,
                  systemSleep: value["system_sleep"].bool ?? false,
                  screenSaver: value["screen_saver"].bool ?? false)
    }

    /// Only what is on, and nil when nothing is, which drops the key from settings.json.
    var settingsValue: LuaValue {
        var table: [String: LuaValue] = [:]
        if let idleMinutes { table["idle_minutes"] = Int(exactly: idleMinutes).map(LuaValue.int) ?? .double(idleMinutes) }
        if displaySleep { table["display_sleep"] = .bool(true) }
        if systemSleep { table["system_sleep"] = .bool(true) }
        if screenSaver { table["screen_saver"] = .bool(true) }
        return table.isEmpty ? .nil : .table(table)
    }
}

extension Settings {
    var autoLock: AutoLockSettings {
        get { AutoLockSettings(self["auto_lock"]) }
        set { self["auto_lock"] = newValue.settingsValue }
    }
}

/// Locks the screen by itself, on the triggers `apply` turns on: call it at launch and whenever settings.json
/// changes. Nothing fires while `isLocked()` is true.
@MainActor
final class AutoLock: NSObject {
    /// What the idle trigger knows between checks.
    struct IdleCount: Equatable {
        enum Hold { case lock, keptAwake }

        /// When the count last started again, in seconds on the monotonic clock: when the trigger started, when a
        /// lock opened, or when a display-awake assertion ended.
        var restartedAt: Double
        /// What held the count at the last check. The count starts again when it ends.
        var hold: Hold?
    }

    enum IdleDecision: Equatable {
        case lock
        /// Check again after this many seconds.
        case wait(Double)
    }

    /// Nothing announces the end of a lock or of a display-awake assertion, so the idle trigger looks this often
    /// (in seconds) while either lasts.
    nonisolated static let recheck: Double = 60

    private let isLocked: () -> Bool
    private let lock: (_ reason: String) -> Void
    private var settings: AutoLockSettings?
    private var observers: [NSObjectProtocol] = []
    private var idleCheck: Task<Void, Never>?
    private var count = IdleCount(restartedAt: 0)
    private static let screenSaverStarted = Notification.Name("com.apple.screensaver.didstart")

    init(isLocked: @escaping () -> Bool, lock: @escaping (_ reason: String) -> Void) {
        self.isLocked = isLocked
        self.lock = lock
        super.init()
    }

    /// Starts and stops the triggers to match `settings`. The same settings again change nothing, and the idle
    /// count goes on through changes that leave idle_minutes alone.
    func apply(_ settings: AutoLockSettings) {
        guard settings != self.settings else { return }
        if settings.idleMinutes != self.settings?.idleMinutes {
            idleCheck?.cancel()
            idleCheck = settings.idleMinutes.map { startIdle(threshold: $0 * 60) }
        }
        self.settings = settings

        let workspace = NSWorkspace.shared.notificationCenter
        observers.forEach(workspace.removeObserver)
        observers = []
        if settings.displaySleep {
            observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fire("display sleep") }
            })
        }
        if settings.systemSleep {
            // No queue, so the lock is up before this returns: macOS waits for the observer before it sleeps.
            observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
                Self.onMainNow { self?.fire("system sleep") }
            })
        }
        // AppKit holds distributed notifications back while the app is inactive, as Locky nearly always is,
        // unless they are registered to be delivered at once.
        let distributed = DistributedNotificationCenter.default()
        distributed.removeObserver(self, name: Self.screenSaverStarted, object: nil)
        if settings.screenSaver {
            distributed.addObserver(self, selector: #selector(screenSaverDidStart), name: Self.screenSaverStarted, object: nil,
                                    suspensionBehavior: .deliverImmediately)
        }
    }

    @objc private nonisolated func screenSaverDidStart(_: Notification) {
        Self.onMainNow { self.fire("screen saver") }
    }

    private func fire(_ reason: String) {
        guard !isLocked() else { return }
        lock(reason)
        // The idle count starts again once this lock opens.
        count.hold = .lock
    }

    private func startIdle(threshold: Double) -> Task<Void, Never> {
        count = IdleCount(restartedAt: Self.now())
        return Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.checkIdle(threshold: threshold) else { return }
                // At least a second, so a tiny wait cannot spin the loop, and at most an hour: Duration cannot hold
                // every Double, and a huge idle_minutes would trap.
                try? await Task.sleep(for: .seconds(min(max(delay, 1), 3600)))
            }
        }
    }

    /// Returns the seconds until the next check.
    private func checkIdle(threshold: Double) -> Double {
        let decision = Self.idleDecision(now: Self.now(), idle: Self.idleSeconds(), threshold: threshold, locked: isLocked(),
                                         keptAwake: Self.displayKeptAwake(), count: &count)
        switch decision {
        case .lock:
            fire("idle")
            return min(threshold, Self.recheck)
        case .wait(let seconds):
            return seconds
        }
    }

    /// The idle trigger. `idle` is the seconds since the last input, `threshold` the idle seconds that lock, and
    /// `now` the monotonic clock. A lock, or a display kept awake by another process, holds the count, and it starts
    /// again at the first check after either ends, so an unlock without a key press (Touch ID) cannot lock again at
    /// once, and the end of a video does not lock in the same moment. `keptAwake` is read only when the time is up.
    nonisolated static func idleDecision(now: Double, idle: Double, threshold: Double, locked: Bool, keptAwake: @autoclosure () -> Bool,
                                         count: inout IdleCount) -> IdleDecision {
        if locked {
            count.hold = .lock
            return .wait(min(threshold, recheck))
        }
        if count.hold == .lock {
            count.hold = nil
            count.restartedAt = now
        }
        let counted = min(idle, now - count.restartedAt)
        if counted < threshold {
            count.hold = nil
            return .wait(threshold - counted)
        }
        if keptAwake() {
            count.hold = .keptAwake
            return .wait(min(threshold, recheck))
        }
        if count.hold == .keptAwake {
            count.hold = nil
            count.restartedAt = now
            return .wait(threshold)
        }
        count.hold = .lock
        return .lock
    }

    /// Seconds since the last keyboard, mouse, trackpad, or tablet input. The type is kCGAnyInputEventType (~0),
    /// which Swift does not import; `.null` would count from the last null event, days ago.
    private static func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Whether another process keeps the display awake: a video, a presentation, or a call. If the assertions
    /// cannot be read, the answer is no, and the screen locks.
    private static func displayKeptAwake() -> Bool {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let assertions = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        return keepsDisplayAwake(assertions, ownPID: getpid())
    }

    /// Reads IOPMCopyAssertionsByProcess's result, leaving out Locky's own assertions. Apps still use the old name
    /// of the type (Chrome does).
    nonisolated static func keepsDisplayAwake(_ assertions: [NSNumber: [[String: Any]]], ownPID: pid_t) -> Bool {
        let types: Set<String> = [kIOPMAssertPreventUserIdleDisplaySleep, kIOPMAssertionTypeNoDisplaySleep]
        return assertions.contains { pid, list in
            pid.int32Value != ownPID && list.contains { assertion in
                types.contains(assertion[kIOPMAssertionTypeKey] as? String ?? "")
                    && (assertion[kIOPMAssertionLevelKey] as? Int ?? kIOPMAssertionLevelOn) != kIOPMAssertionLevelOff
            }
        }
    }

    /// Seconds on a clock that counts on while the Mac sleeps.
    private static func now() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1e9
    }

    /// Runs `body` on the main thread and returns after it, from any thread.
    private nonisolated static func onMainNow(_ body: @MainActor () -> Void) {
        if Thread.isMainThread { MainActor.assumeIsolated(body) } else { DispatchQueue.main.sync { MainActor.assumeIsolated(body) } }
    }
}
