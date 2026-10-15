import AppKit
import IOKit.ps
import IOKit.pwr_mgt

/// The power settings in use, as `pmset -g` shows them: a profile per power source ("AC Power", "Battery Power",
/// "UPS Power"). Exported by IOKit, but not in its public headers: looked up by name and called as the C function it
/// is. nil if a macOS release removes it, which reads as Never.
private let IOPMCopyActivePMPreferences: (@convention(c) () -> Unmanaged<CFDictionary>?)? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOPMCopyActivePMPreferences") else { return nil }  // RTLD_DEFAULT
    return unsafeBitCast(symbol, to: (@convention(c) () -> Unmanaged<CFDictionary>?).self)
}()

/// The Mac's power source and Low Power Mode, for still lock screens, and a way to turn the displays off.
enum Power {
    /// True while the Mac runs on its battery, or a UPS's. A Mac without a battery reports AC power.
    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type != kIOPSACPowerValue
    }

    static var lowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// The system's display sleep for the power source in use, in seconds: System Settings › Lock Screen › Turn display
    /// off when inactive. nil for Never, or when the settings cannot be read.
    static var systemDisplaySleep: Double? {
        let source = IOPSCopyPowerSourcesInfo().flatMap { IOPSGetProvidingPowerSourceType($0.takeRetainedValue())?.takeUnretainedValue() as String? }
        return displaySleep(preferences: IOPMCopyActivePMPreferences?()?.takeRetainedValue() as? [String: Any], source: source)
    }

    /// The display sleep of `source`'s profile in `preferences` (IOPMCopyActivePMPreferences), from minutes to seconds.
    /// A Mac that does not say its source is on AC power. 0 minutes is Never: nil.
    static func displaySleep(preferences: [String: Any]?, source: String?) -> Double? {
        guard let profile = preferences?[source ?? kIOPMACPowerKey] as? [String: Any],
              let minutes = (profile["Display Sleep Timer"] as? NSNumber)?.doubleValue, minutes > 0, minutes.isFinite else { return nil }
        return minutes * 60
    }

    /// When a lock turns the displays off: settings.json's display_off, or else the system's display sleep, which
    /// the lock's assertion holds back (DisplayAssertion). nil: the displays stay on, as with the system's Never.
    static func displayOffSeconds(setting: Double?, system: Double?) -> Double? {
        setting ?? system
    }

    /// Turns the displays off now, as `pmset displaysleepnow` does. Tests pass a `run` that records the call: a real
    /// run turns the displays off.
    static func sleepDisplays(run: (_ tool: String, _ arguments: [String]) -> Void = launch) {
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    /// Starts a tool without waiting for it.
    private static func launch(_ tool: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            LogFile.shared.write(level: "warn", message: "could not run \(tool): \(error.localizedDescription)", source: "locky")
        }
    }
}

extension Settings {
    /// settings.json's battery_saver: whether the lock screen is also still on battery. In Low Power Mode or with
    /// Reduce Motion on, it is still anyway. Off when missing.
    var batterySaver: Bool {
        get { self["battery_saver"].bool ?? false }
        set { self["battery_saver"] = newValue ? .bool(true) : .nil }
    }

    /// settings.json's display_off: seconds without a key press or mouse movement on the lock screen before the
    /// displays turn off. nil (missing, or not a positive number) is off.
    var displayOff: Double? {
        get { self["display_off"].number.flatMap { $0 > 0 && $0.isFinite ? $0 : nil } }
        set { self["display_off"] = newValue.map { Int(exactly: $0).map(LuaValue.int) ?? .double($0) } ?? .nil }
    }

    /// settings.json's ambient_after: seconds without input on the lock screen before only its background shows.
    /// Missing (or not a number) is 20; 0 or less is off (nil).
    var ambientAfter: Double? {
        guard let seconds = self["ambient_after"].number, seconds.isFinite else { return 20 }
        return seconds > 0 ? seconds : nil
    }
}

/// While a lock is on: an assertion that keeps idle display sleep, and with it the screen saver, from taking over the
/// shield. The lock turns the displays off itself (DisplayOff). A closed lid or system sleep still sleep the Mac, and
/// macOS releases the assertion if Locky exits.
@MainActor
final class DisplayAssertion {
    /// The power calls, which tests replace.
    struct API: Sendable {
        var create: @Sendable (_ reason: String) -> IOPMAssertionID?
        var release: @Sendable (IOPMAssertionID) -> Void

        static let system = API(create: { reason in
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
            return result == kIOReturnSuccess ? id : nil
        }, release: { _ = IOPMAssertionRelease($0) })
    }

    private let api: API
    private var id: IOPMAssertionID?
    var isHeld: Bool { id != nil }

    init(api: API = .system) {
        self.api = api
        id = api.create("Locky's lock screen is up")
        if id != nil {
            LogFile.shared.write(level: "info", message: "keeping the display awake during the lock", source: "locky")
        } else {
            LogFile.shared.write(level: "warn", message: "could not keep the display awake: the screen saver may show over the lock", source: "locky")
        }
    }

    /// Once; later calls do nothing.
    func release() {
        guard let id else { return }
        api.release(id)
        self.id = nil
        LogFile.shared.write(level: "info", message: "the display may sleep again", source: "locky")
    }
}

/// The lock's ambient mode: after `seconds` without input, only the theme's background shows. The next input brings
/// the rest back. `clock` is the continuous clock, or a test's own.
@MainActor
final class AmbientTimer<C: Clock> where C.Duration == Duration {
    private let seconds: Duration
    private let clock: C
    private let onChange: (_ ambient: Bool) -> Void
    private var lastActivity: C.Instant
    private var timer: Task<Void, Never>?
    private var stopped = false
    private(set) var isAmbient = false

    /// `seconds` counts up to a day, as DisplayOff's does.
    init(after seconds: Double, clock: C, onChange: @escaping (_ ambient: Bool) -> Void) {
        self.seconds = .seconds(min(max(seconds, 0), 86_400))
        self.clock = clock
        self.onChange = onChange
        lastActivity = clock.now
        arm()
    }

    /// Any input: a key, the mouse, a click, a scroll. Cheap enough for every mouse-moved event.
    func noteActivity() {
        lastActivity = clock.now
        if isAmbient {
            isAmbient = false
            onChange(false)
        }
        if timer == nil, !stopped { arm() }
    }

    func stop() {
        stopped = true
        timer?.cancel()
        timer = nil
    }

    private func arm() {
        let deadline = lastActivity.advanced(by: seconds)
        timer = Task { [weak self, clock] in
            try? await clock.sleep(until: deadline, tolerance: nil)
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    private func fire() {
        timer = nil
        // Input since the timer was set moved the deadline.
        if lastActivity.advanced(by: seconds) > clock.now { arm() } else {
            isAmbient = true
            onChange(true)
        }
    }
}

/// Calls `onChange` when the Mac moves between its battery and a power adapter, Low Power Mode turns on or off, or
/// Reduce Motion does. `Power.onBattery`, `Power.lowPowerMode`, and NSWorkspace then say which.
@MainActor
final class PowerObserver {
    private let onChange: () -> Void
    private var last: (Bool, Bool, Bool)
    nonisolated(unsafe) private var source: CFRunLoopSource?
    nonisolated(unsafe) private var token: NSObjectProtocol?
    nonisolated(unsafe) private var motionToken: NSObjectProtocol?

    private static var now: (Bool, Bool, Bool) {
        (Power.onBattery, Power.lowPowerMode, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        last = Self.now
        // Only for a switch between limited power (a battery or UPS) and AC. IOPSNotificationCreateRunLoopSource also
        // fires for every change in charge, and Apple's header points here for this.
        source = IOPSCreateLimitedPowerNotification({ context in
            guard let context else { return }
            let observer = Unmanaged<PowerObserver>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { observer.check() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        // Posted on a global queue.
        token = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        motionToken = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    deinit {
        if let source { CFRunLoopSourceInvalidate(source) }
        if let token { NotificationCenter.default.removeObserver(token) }
        if let motionToken { NSWorkspace.shared.notificationCenter.removeObserver(motionToken) }
    }

    private func check() {
        let now = Self.now
        guard now != last else { return }
        last = now
        onChange()
    }
}

/// Turns the displays off when the lock screen sees no key press or mouse movement for a while. It turns them off
/// once; the next activity starts the count again.
@MainActor
final class DisplayOff {
    private let seconds: Duration
    private let sleep: () -> Void
    private var lastActivity = ContinuousClock.now
    private var timer: Task<Void, Never>?
    private var stopped = false

    /// `seconds` counts up to a day: Duration cannot hold every Double.
    init(after seconds: Double, sleep: @escaping () -> Void) {
        self.seconds = .seconds(min(max(seconds, 0), 86_400))
        self.sleep = sleep
        arm()
    }

    /// A key press or mouse movement. Cheap enough for every mouse-moved event: it notes the time, and sets a timer
    /// only when the displays went off.
    func noteActivity() {
        lastActivity = .now
        if timer == nil, !stopped { arm() }
    }

    func stop() {
        stopped = true
        timer?.cancel()
        timer = nil
    }

    private func arm() {
        let deadline = lastActivity + seconds
        timer = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    private func fire() {
        timer = nil
        // Activity since the timer was set moved the deadline.
        if lastActivity + seconds > .now { arm() } else { sleep() }
    }
}
