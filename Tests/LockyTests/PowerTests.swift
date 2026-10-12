import Foundation
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

    /// Posts to this process's own notification center. Assumes nobody plugs or unplugs the Mac meanwhile.
    @MainActor
    @Test func aPowerNotificationWithoutAChangeCallsNothing() async throws {
        var changes = 0
        let observer = PowerObserver { changes += 1 }
        NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: ProcessInfo.processInfo)
        try await Task.sleep(for: .milliseconds(100))
        #expect(changes == 0)
        withExtendedLifetime(observer) {}
    }
}

@MainActor
@Suite struct DisplayOffTests {
    /// Counts calls and when the last one came.
    private final class Calls {
        var count = 0
        var last: ContinuousClock.Instant?
        func record() { count += 1; last = .now }
    }

    private func waitFor(_ count: Int, _ calls: Calls, timeout: Double = 3) async throws {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while calls.count < count, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func theDisplaysTurnOffOnceAfterTheQuietTime() async throws {
        let calls = Calls()
        let start = ContinuousClock.now
        let displayOff = DisplayOff(after: 0.4, sleep: calls.record)
        #expect(calls.count == 0)
        try await waitFor(1, calls)
        #expect(calls.count == 1)
        #expect(try #require(calls.last) - start >= .seconds(0.4))
        // Once: no activity, no second call.
        try await Task.sleep(for: .seconds(1))
        #expect(calls.count == 1)
        // Activity starts the count again.
        let activity = ContinuousClock.now
        displayOff.noteActivity()
        try await waitFor(2, calls)
        #expect(calls.count == 2)
        #expect(try #require(calls.last) - activity >= .seconds(0.4))
        displayOff.stop()
    }

    @Test func activityPushesTheTimeBack() async throws {
        let calls = Calls()
        let displayOff = DisplayOff(after: 1, sleep: calls.record)
        try await Task.sleep(for: .seconds(0.3))
        let activity = ContinuousClock.now
        displayOff.noteActivity()
        try await waitFor(1, calls)
        #expect(calls.count == 1)
        // A full second after the activity, not after the start.
        #expect(try #require(calls.last) - activity >= .seconds(1))
        displayOff.stop()
    }

    @Test func stopEndsItForGood() async throws {
        let calls = Calls()
        let displayOff = DisplayOff(after: 0.2, sleep: calls.record)
        displayOff.stop()
        displayOff.noteActivity()
        try await Task.sleep(for: .seconds(0.6))
        #expect(calls.count == 0)
    }
}
