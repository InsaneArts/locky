import Foundation
import IOKit.ps

/// The Mac's power source and Low Power Mode, for settings.json's battery_saver, and a way to turn the displays off.
enum Power {
    /// True while the Mac runs on its battery, or a UPS's. A Mac without a battery reports AC power.
    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type != kIOPSACPowerValue
    }

    static var lowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

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
    /// settings.json's battery_saver: whether the lock screen saves power on battery or in Low Power Mode. Off when
    /// missing.
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
}

/// Calls `onChange` when the Mac moves between its battery and a power adapter, or Low Power Mode turns on or off.
/// `Power.onBattery` and `Power.lowPowerMode` then say which.
@MainActor
final class PowerObserver {
    private let onChange: () -> Void
    private var last: (Bool, Bool)
    nonisolated(unsafe) private var source: CFRunLoopSource?
    nonisolated(unsafe) private var token: NSObjectProtocol?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        last = (Power.onBattery, Power.lowPowerMode)
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
    }

    deinit {
        if let source { CFRunLoopSourceInvalidate(source) }
        if let token { NotificationCenter.default.removeObserver(token) }
    }

    private func check() {
        let now = (Power.onBattery, Power.lowPowerMode)
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
