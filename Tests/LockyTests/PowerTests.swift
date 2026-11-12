import AppKit
import Testing
@testable import Locky

@Suite struct PowerSettingsTests {
    @Test func batterySaverIsOffUnlessTrue() {
        #expect(Settings().batterySaver == false)
        #expect(Settings(["battery_saver": .bool(true)]).batterySaver)
        #expect(Settings(["battery_saver": .string("yes")]).batterySaver == false)
        var settings = Settings()
        settings.batterySaver = true
        #expect(settings["battery_saver"] == .bool(true))
        settings.batterySaver = false
        #expect(settings.values.isEmpty)
    }

    @Test func displayOffIsSecondsAndMissingIsOff() {
        #expect(Settings().displayOff == nil)
        #expect(Settings(["display_off": .int(30)]).displayOff == 30)
        #expect(Settings(["display_off": .double(2.5)]).displayOff == 2.5)
        for value: LuaValue in [.int(0), .int(-5), .string("30"), .bool(true)] {
            #expect(Settings(["display_off": value]).displayOff == nil, "\(value)")
        }
        var settings = Settings()
        settings.displayOff = 30
        #expect(settings["display_off"] == .int(30))
        settings.displayOff = nil
        #expect(settings.values.isEmpty)
    }

    @Test func powerSettingsRoundTripThroughSettingsJSON() throws {
        let sandbox = try Sandbox()
        var settings = Settings()
        settings.batterySaver = true
        settings.displayOff = 45
        try settings.save(config: sandbox.config)
        let loaded = Settings.load(config: sandbox.config).settings
        #expect(loaded.batterySaver)
        #expect(loaded.displayOff == 45)
    }
}

@Suite struct PowerTests {
    /// The runner records the call instead of running it: a real run turns the displays off.
    @Test func sleepDisplaysRunsPmset() {
        var calls: [(String, [String])] = []
        Power.sleepDisplays { calls.append(($0, $1)) }
        #expect(calls.count == 1)
        #expect(calls.first?.0 == "/usr/bin/pmset")
        #expect(calls.first?.1 == ["displaysleepnow"])
    }

    /// Posts to this process's own notification centers. Assumes nobody plugs or unplugs the Mac, or changes Reduce
    /// Motion, meanwhile.
    @MainActor
    @Test func aPowerNotificationWithoutAChangeCallsNothing() async throws {
        var changes = 0
        let observer = PowerObserver { changes += 1 }
        NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: ProcessInfo.processInfo)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(changes == 0)
        withExtendedLifetime(observer) {}
    }
}

@MainActor
@Suite struct StillTests {
    /// Low Power Mode and Reduce Motion still every lock screen; battery_saver stills it on battery too.
    @Test(arguments: [
        // lowPower, reduceMotion, onBattery, batterySaver, still
        (false, false, false, false, false), (false, false, false, true, false),
        (false, false, true, false, false), (false, false, true, true, true),
        (false, true, false, false, true), (false, true, false, true, true),
        (false, true, true, false, true), (false, true, true, true, true),
        (true, false, false, false, true), (true, false, false, true, true),
        (true, false, true, false, true), (true, false, true, true, true),
        (true, true, false, false, true), (true, true, false, true, true),
        (true, true, true, false, true), (true, true, true, true, true),
    ])
    func stillness(lowPower: Bool, reduceMotion: Bool, onBattery: Bool, batterySaver: Bool, still: Bool) {
        #expect(LockSession.still(lowPower: lowPower, reduceMotion: reduceMotion, onBattery: onBattery, batterySaver: batterySaver) == still)
    }
}
