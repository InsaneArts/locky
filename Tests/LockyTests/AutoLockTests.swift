import AppKit
import Foundation
import IOKit.pwr_mgt
import Testing
@testable import Locky

@Suite struct AutoLockSettingsTests {
    @Test func aMissingKeyIsOffAndAMissingTableIsAllOff() {
        #expect(Settings().autoLock == AutoLockSettings())
        #expect(AutoLockSettings(.table(["display_sleep": .bool(true)])) == AutoLockSettings(displaySleep: true))
        let all = AutoLockSettings(.table(["idle_minutes": .int(5), "display_sleep": .bool(true), "system_sleep": .bool(true),
                                           "screen_saver": .bool(true)]))
        #expect(all == AutoLockSettings(idleMinutes: 5, displaySleep: true, systemSleep: true, screenSaver: true))
    }

    @Test func valuesThatMakeNoSenseAreOff() {
        for minutes: LuaValue in [.int(0), .int(-3), .string("5"), .bool(true)] {
            #expect(AutoLockSettings(.table(["idle_minutes": minutes])).idleMinutes == nil, "\(minutes)")
        }
        #expect(AutoLockSettings(.table(["display_sleep": .string("yes")])).displaySleep == false)
        #expect(AutoLockSettings(.string("on")) == AutoLockSettings())
        #expect(AutoLockSettings(.table(["idle_minutes": .double(2.5)])).idleMinutes == 2.5)
    }

    @Test func settingsRoundTripThroughSettingsJSON() throws {
        let sandbox = try Sandbox()
        for autoLock in [AutoLockSettings(idleMinutes: 5, systemSleep: true), AutoLockSettings(idleMinutes: 2.5, displaySleep: true, screenSaver: true),
                         AutoLockSettings(screenSaver: true)] {
            var settings = Settings()
            settings.autoLock = autoLock
            try settings.save(config: sandbox.config)
            #expect(Settings.load(config: sandbox.config).settings.autoLock == autoLock)
        }
        // Only what is on is written, whole minutes as integers.
        #expect(AutoLockSettings(idleMinutes: 5, systemSleep: true).settingsValue == .table(["idle_minutes": .int(5), "system_sleep": .bool(true)]))
        // All off drops the key.
        var settings = Settings(["auto_lock": .table(["display_sleep": .bool(true)])])
        settings.autoLock = AutoLockSettings()
        #expect(settings.values.isEmpty)
    }
}

@Suite struct IdleDecisionTests {
    private let threshold = 300.0
    /// The count started long ago, so the idle time alone decides.
    private func count() -> AutoLock.IdleCount { AutoLock.IdleCount(restartedAt: 0) }

    private func decide(now: Double = 10_000, idle: Double, locked: Bool = false, keptAwake: Bool = false,
                        _ count: inout AutoLock.IdleCount) -> AutoLock.IdleDecision {
        AutoLock.idleDecision(now: now, idle: idle, threshold: threshold, locked: locked, keptAwake: keptAwake, count: &count)
    }

    @Test func beforeTheThresholdItWaitsExactlyUntilIt() {
        var count = count()
        var asked = false
        let decision = AutoLock.idleDecision(now: 10_000, idle: 100, threshold: threshold, locked: false,
                                             keptAwake: { asked = true; return false }(), count: &count)
        #expect(decision == .wait(200))
        // The power assertions are read only when the time is up.
        #expect(!asked)
        #expect(count == self.count())
    }

    @Test func atTheThresholdItLocksAndHoldsTheCount() {
        var count = count()
        #expect(decide(idle: 300, &count) == .lock)
        #expect(count.hold == .lock)
        var later = self.count()
        #expect(decide(idle: 5000, &later) == .lock)
    }

    @Test func aDisplayKeptAwakeHoldsTheCountAndChecksAgain() {
        var count = count()
        #expect(decide(idle: 900, keptAwake: true, &count) == .wait(AutoLock.recheck))
        #expect(count.hold == .keptAwake)
        // Still kept awake a minute later: the same again.
        #expect(decide(now: 10_060, idle: 960, keptAwake: true, &count) == .wait(AutoLock.recheck))
        #expect(count.restartedAt == 0)
        // Input during the video ends the hold; the input idle time counts.
        #expect(decide(now: 10_120, idle: 20, keptAwake: true, &count) == .wait(280))
        #expect(count.hold == nil)
    }

    @Test func whileLockedNothingLocksAndNothingIsRead() {
        var count = count()
        var asked = false
        let decision = AutoLock.idleDecision(now: 10_000, idle: 5000, threshold: threshold, locked: true,
                                             keptAwake: { asked = true; return false }(), count: &count)
        #expect(decision == .wait(AutoLock.recheck))
        #expect(!asked)
        #expect(count.hold == .lock)
        // A threshold shorter than the recheck is the wait.
        #expect(AutoLock.idleDecision(now: 10_000, idle: 5000, threshold: 30, locked: true, keptAwake: false, count: &count) == .wait(30))
    }

    @Test func theCountStartsAgainAfterAnUnlock() {
        var count = count()
        _ = decide(idle: 5000, locked: true, &count)
        // Unlocked with Touch ID: no key press, so the input idle time is still long.
        #expect(decide(now: 10_060, idle: 5060, &count) == .wait(300))
        #expect(count == AutoLock.IdleCount(restartedAt: 10_060))
        #expect(decide(now: 10_260, idle: 5260, &count) == .wait(100))
        #expect(decide(now: 10_360, idle: 5360, &count) == .lock)
    }

    @Test func inputAfterTheRestartCountsFromTheInput() {
        var count = AutoLock.IdleCount(restartedAt: 9000)
        #expect(decide(now: 10_000, idle: 50, &count) == .wait(250))
        #expect(decide(now: 10_000, idle: 2000, &count) == .lock)
    }

    @Test func theCountStartsAgainWhenTheDisplayIsNoLongerKeptAwake() {
        var count = count()
        _ = decide(idle: 900, keptAwake: true, &count)
        // The video ended: no lock in the same moment, but a full threshold later.
        #expect(decide(now: 10_060, idle: 960, &count) == .wait(300))
        #expect(count.restartedAt == 10_060)
        #expect(decide(now: 10_360, idle: 1260, &count) == .lock)
    }
}

@Suite struct DisplayAssertionTests {
    private func assertion(_ type: String, level: Int? = Int(kIOPMAssertionLevelOn)) -> [String: Any] {
        var assertion: [String: Any] = [kIOPMAssertionTypeKey: type, kIOPMAssertionNameKey: "test"]
        assertion[kIOPMAssertionLevelKey] = level
        return assertion
    }

    @Test func videoAndCallAssertionsKeepTheDisplayAwake() {
        #expect(AutoLock.keepsDisplayAwake([42: [assertion(kIOPMAssertPreventUserIdleDisplaySleep)]], ownPID: 7))
        // The old name, as Chrome still uses it.
        #expect(AutoLock.keepsDisplayAwake([42: [assertion(kIOPMAssertionTypeNoDisplaySleep)]], ownPID: 7))
        // A dictionary without a level counts as on.
        #expect(AutoLock.keepsDisplayAwake([42: [assertion(kIOPMAssertPreventUserIdleDisplaySleep, level: nil)]], ownPID: 7))
    }

    @Test func otherAssertionsLockyAndLevelOffDoNot() {
        #expect(!AutoLock.keepsDisplayAwake([:], ownPID: 7))
        #expect(!AutoLock.keepsDisplayAwake([7: [assertion(kIOPMAssertPreventUserIdleDisplaySleep)]], ownPID: 7))
        #expect(!AutoLock.keepsDisplayAwake([42: [assertion(kIOPMAssertPreventUserIdleDisplaySleep, level: Int(kIOPMAssertionLevelOff))]], ownPID: 7))
        // Held all the time by macOS itself: system sleep, user activity, and powerd's own display assertion.
        let system = ["PreventUserIdleSystemSleep", "UserIsActive", "InternalPreventDisplaySleep", "NetworkClientActive"].map { assertion($0) }
        #expect(!AutoLock.keepsDisplayAwake([351: system], ownPID: 7))
    }
}

/// Posts NSWorkspace's notifications to this process's own center: nothing outside the test sees them.
@MainActor
@Suite struct AutoLockTriggerTests {
    @Test func sleepTriggersLockAndNothingFiresWhileLocked() async throws {
        var locked = false
        var reasons: [String] = []
        let autoLock = AutoLock(isLocked: { locked }, lock: { reasons.append($0); locked = true })
        autoLock.apply(AutoLockSettings(displaySleep: true, systemSleep: true))
        let workspace = NSWorkspace.shared.notificationCenter

        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Before the post returns, so the windows exist before the Mac sleeps.
        #expect(reasons == ["system sleep"])

        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(reasons == ["system sleep"])

        locked = false
        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        for _ in 0..<100 where reasons.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(reasons == ["system sleep", "display sleep"])

        // Turned off, the triggers are gone.
        locked = false
        autoLock.apply(AutoLockSettings())
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(reasons == ["system sleep", "display sleep"])
    }
}
