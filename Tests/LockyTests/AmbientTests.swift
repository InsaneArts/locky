import AppKit
import IOKit.pwr_mgt
import Synchronization
import Testing
@testable import Locky

/// A clock that moves only when the test moves it.
final class ManualClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (a: Instant, b: Instant) -> Bool { a.offset < b.offset }
    }

    private let time = Mutex(Instant(offset: .zero))
    var now: Instant { time.withLock { $0 } }
    var minimumResolution: Duration { .zero }

    func advance(by duration: Duration) { time.withLock { $0 = $0.advanced(by: duration) } }

    /// Polls: the test's advance comes from the main actor, between these checks.
    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        while now < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}

@MainActor
@Suite struct AmbientTimerTests {
    private final class Changes {
        var list: [Bool] = []
    }

    private func timer(_ seconds: Double = 20) -> (AmbientTimer<ManualClock>, ManualClock, Changes) {
        let clock = ManualClock(), changes = Changes()
        let timer = AmbientTimer(after: seconds, clock: clock) { changes.list.append($0) }
        return (timer, clock, changes)
    }

    @Test func theLockGoesAmbientAfterItsQuietTime() async {
        let (timer, clock, changes) = timer()
        defer { timer.stop() }
        clock.advance(by: .seconds(19))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(changes.list.isEmpty && !timer.isAmbient)
        clock.advance(by: .seconds(1))
        #expect(await waitUntil { changes.list == [true] })
        #expect(timer.isAmbient)
    }

    @Test func inputEndsItAndStartsTheCountAgain() async {
        let (timer, clock, changes) = timer()
        defer { timer.stop() }
        clock.advance(by: .seconds(20))
        #expect(await waitUntil { timer.isAmbient })
        timer.noteActivity()
        #expect(changes.list == [true, false] && !timer.isAmbient)
        clock.advance(by: .seconds(10))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!timer.isAmbient)
        clock.advance(by: .seconds(10))
        #expect(await waitUntil { changes.list == [true, false, true] })
    }

    @Test func inputDuringTheCountPushesItBack() async {
        let (timer, clock, changes) = timer()
        defer { timer.stop() }
        clock.advance(by: .seconds(15))
        timer.noteActivity()
        // Input without the ambient mode says nothing.
        #expect(changes.list.isEmpty)
        clock.advance(by: .seconds(15))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!timer.isAmbient)
        clock.advance(by: .seconds(5))
        #expect(await waitUntil { timer.isAmbient })
    }

    @Test func stopEndsItForGood() async {
        let (timer, clock, changes) = timer()
        timer.stop()
        timer.noteActivity()
        clock.advance(by: .seconds(60))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(changes.list.isEmpty)
    }

    @Test func ambientAfterIsSecondsWith20ByDefaultAnd0Off() {
        #expect(Settings().ambientAfter == 20)
        #expect(Settings(["ambient_after": .int(60)]).ambientAfter == 60)
        #expect(Settings(["ambient_after": .double(2.5)]).ambientAfter == 2.5)
        #expect(Settings(["ambient_after": .int(0)]).ambientAfter == nil)
        #expect(Settings(["ambient_after": .int(-1)]).ambientAfter == nil)
        #expect(Settings(["ambient_after": .string("never")]).ambientAfter == 20)
    }
}

/// Only the background shows in the ambient mode; the rest comes back as it was.
@MainActor
@Suite struct AmbientScreenTests {
    private func widget() -> WidgetHost {
        let placement = Theme.Placement(widget: "w", anchor: .center, offset: .zero, size: CGSize(width: 100, height: 40), align: nil, card: nil,
                                        allDisplays: false, known: true)
        return WidgetHost(placement: placement, theme: .fallback, style: LockyStyle(), showsErrors: true)
    }

    private func hidden(_ view: NSView?) -> Bool {
        (view?.layer?.animation(forKey: "locky.ambient") as? CABasicAnimation)?.toValue as? Float == -1
    }

    @Test func everythingButTheBackgroundFadesAndComesBack() throws {
        let screen = LockScreenView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        // In a window, far off the screen, so each view has its layer.
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 1440, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        window.contentView = screen
        window.orderBack(nil)
        let background = NSView(), overlay = NSView(), field = NSView(), shown = widget()
        [background, overlay, field].forEach { $0.wantsLayer = true }
        screen.background = background
        screen.overlay = overlay
        screen.auth = (field, Theme.Auth())
        screen.add(shown)
        screen.layoutSubtreeIfNeeded()
        screen.setAmbient(true, reduceMotion: false)
        #expect(hidden(field) && hidden(shown))
        #expect(background.layer?.animation(forKey: "locky.ambient") == nil && overlay.layer?.animation(forKey: "locky.ambient") == nil)
        let fade = try #require(field.layer?.animation(forKey: "locky.ambient"))
        #expect(fade.duration == 0.6)
        // A widget that joins meanwhile stays hidden with the rest.
        let late = widget()
        screen.add(late)
        screen.needsLayout = true
        screen.layoutSubtreeIfNeeded()
        #expect(hidden(late))
        // Back in 0.3 s, to each view's own alpha.
        screen.setAmbient(false, reduceMotion: false)
        let back = try #require(field.layer?.animation(forKey: "locky.ambient") as? CABasicAnimation)
        #expect(back.toValue as? Float == 0 && back.duration == 0.3 && back.isRemovedOnCompletion)
        #expect(field.alphaValue == 1)
    }

    @Test func reduceMotionFadesFaster() throws {
        let screen = LockScreenView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let field = NSView()
        field.wantsLayer = true
        screen.auth = (field, Theme.Auth())
        screen.setAmbient(true, reduceMotion: true)
        #expect(try #require(field.layer?.animation(forKey: "locky.ambient")).duration == 0.2)
    }
}

/// The assertion that keeps idle display sleep and the screen saver off the lock, with the power calls replaced.
@MainActor
@Suite struct DisplayAwakeTests {
    private final class Calls: Sendable {
        let created = Mutex<[String]>([])
        let released = Mutex<[IOPMAssertionID]>([])
    }

    private func api(_ calls: Calls, fails: Bool = false) -> DisplayAssertion.API {
        DisplayAssertion.API(create: { reason in
            calls.created.withLock { $0.append(reason) }
            return fails ? nil : 42
        }, release: { id in calls.released.withLock { $0.append(id) } })
    }

    @Test func itIsHeldUntilReleasedOnce() {
        let calls = Calls()
        let assertion = DisplayAssertion(api: api(calls))
        #expect(assertion.isHeld && calls.created.withLock { $0.count } == 1)
        assertion.release()
        assertion.release()
        #expect(!assertion.isHeld && calls.released.withLock { $0 } == [42])
    }

    @Test func aFailedAssertionReleasesNothing() {
        let calls = Calls()
        let assertion = DisplayAssertion(api: api(calls, fails: true))
        #expect(!assertion.isHeld)
        assertion.release()
        #expect(calls.released.withLock { $0.isEmpty })
    }

    /// The system's own assertion, created and released for real: nothing turns off or on.
    @Test func theSystemCallsCreateAndRelease() throws {
        let id = try #require(DisplayAssertion.API.system.create("Locky test"))
        DisplayAssertion.API.system.release(id)
    }
}

/// display_off "Like the system": the system's display sleep, which the lock's assertion would otherwise hold back.
@Suite struct SystemDisplaySleepTests {
    private let preferences: [String: Any] = [
        "AC Power": ["Display Sleep Timer": 10, "System Sleep Timer": 0],
        "Battery Power": ["Display Sleep Timer": 2],
    ]

    @Test func theProfileInUseGivesItsDisplaySleep() {
        #expect(Power.displaySleep(preferences: preferences, source: "AC Power") == 600)
        #expect(Power.displaySleep(preferences: preferences, source: "Battery Power") == 120)
        // A Mac that does not say its source is on AC power.
        #expect(Power.displaySleep(preferences: preferences, source: nil) == 600)
    }

    @Test func neverOrNothingReadIsNil() {
        #expect(Power.displaySleep(preferences: ["AC Power": ["Display Sleep Timer": 0]], source: "AC Power") == nil)
        #expect(Power.displaySleep(preferences: preferences, source: "UPS Power") == nil)
        #expect(Power.displaySleep(preferences: nil, source: "AC Power") == nil)
    }

    @Test func displayOffWinsOverTheSystem() {
        #expect(Power.displayOffSeconds(setting: 30, system: 600) == 30)
        #expect(Power.displayOffSeconds(setting: nil, system: 600) == 600)
        // The system's Never keeps the displays on, as the system would.
        #expect(Power.displayOffSeconds(setting: nil, system: nil) == nil)
    }
}
