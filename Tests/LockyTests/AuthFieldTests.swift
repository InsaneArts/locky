import AppKit
import SwiftUI
import Testing
@testable import Locky

@MainActor
@Suite(.serialized) struct AuthFieldFocusTests {
    /// The field a rebuild makes during the wait after wrong passwords (a display plugged in, the power changing)
    /// is disabled when it asks for focus; it must take the keyboard when the wait ends. The window sits far
    /// off the screen.
    @Test func aFieldMadeDuringTheWaitTakesTheKeyboardAfterIt() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        let model = AuthModel()
        model.wrong = 3
        model.checking = true
        window.contentView = NSHostingView(rootView: AuthPanel(auth: Theme.Auth(), style: LockyStyle(), touchID: nil, model: model,
                                                               unlock: {}, failed: {}))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(700))  // the field asks for focus at 250 ms, while disabled
        model.checking = false
        try await Task.sleep(for: .milliseconds(500))
        let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        #expect(responder.contains("Text"), "the first responder is \(responder)")
    }
}

/// What the field and the line under it say, and how the field shakes.
@MainActor
@Suite struct FieldTextTests {
    @Test(arguments: [
        (1, false, "Try again in 1 second"), (8, false, "Try again in 8 seconds"), (59, false, "Try again in 59 seconds"),
        (60, false, "Try again in 1 minute"), (89, false, "Try again in 2 minutes"), (300, false, "Try again in 5 minutes"),
        // The wait says more than a wrong password does.
        (8, true, "Try again in 8 seconds"),
        (0, true, "Wrong Password"), (0, false, nil),
    ] as [(Int, Bool, String?)])
    func note(waitLeft: Int, wrongShown: Bool, text: String?) {
        #expect(AuthPanel.note(waitLeft: waitLeft, wrongShown: wrongShown) == text)
    }

    /// VoiceOver hears the wait with the wrong password, since the field refuses keys until it ends, and the way out
    /// with the wrong password that makes the lock name it.
    @Test(arguments: [
        (0, false, "Wrong Password"), (1, false, "Wrong Password. Try again in 1 second"),
        (300, false, "Wrong Password. Try again in 5 minutes"),
        (1, true, "Wrong Password. Try again in 1 second. Press Control-Option-Command-Q to switch to the macOS lock screen"),
        (0, true, "Wrong Password. Press Control-Option-Command-Q to switch to the macOS lock screen"),
    ])
    func announcement(waitLeft: Int, wayOut: Bool, text: String) {
        #expect(AuthPanel.announcement(waitLeft: waitLeft, wayOut: wayOut) == text)
    }

    @Test(arguments: [
        // touchIDOffered, listening, placeholder, hint, text
        (true, true, "", true, "Touch ID or Enter Password"), (true, true, "Enter Password", true, "Touch ID or Enter Password"),
        (true, false, "", true, "Enter Password"), (true, false, "Enter Password", true, "Enter Password"),
        (false, true, "", true, "Enter Password"), (false, true, "Enter Password", true, nil),
        (false, false, "", true, "Enter Password"), (false, false, "Enter Password", true, nil),
        (true, true, "", false, nil), (true, true, "Enter Password", false, nil),
        (true, false, "", false, nil), (true, false, "Enter Password", false, nil),
        (false, true, "", false, nil), (false, true, "Enter Password", false, nil),
        (false, false, "", false, nil), (false, false, "Enter Password", false, nil),
    ] as [(Bool, Bool, String, Bool, String?)])
    func statusText(touchIDOffered: Bool, listening: Bool, placeholder: String, hint: Bool, text: String?) {
        #expect(AuthPanel.statusText(touchIDOffered: touchIDOffered, listening: listening, placeholder: placeholder, hint: hint) == text)
    }

    @Test func theShakeStartsAndEndsStillAndStaysWithinItsAmplitude() {
        func x(_ phase: CGFloat) -> CGFloat { Shake(phase: phase, amplitude: 10).effectValue(size: .zero).m31 }
        #expect(x(0) == 0 && x(1) == 0 && x(3) == 0)
        for step in 1..<100 { #expect(abs(x(CGFloat(step) / 100)) <= 10) }
        // The first swing is the widest, and the last one has almost died down.
        #expect(abs(x(1.0 / 12) - 9.17) < 0.01 && abs(x(11.0 / 12)) < 0.9)
    }

    /// The quiet color of glass, and of Tokyo Night, whose muted color must be lifted, on their own bg.
    @Test(arguments: [("#1c3a66", "#ffffff", "#ffffffb3"), ("#1a1b26", "#c0caf5", "#565f89")])
    func theQuietColorReadsOnTheThemesBg(bg: String, fg: String, muted: String) throws {
        let style = LockyStyle(palette: ["bg": bg, "fg": fg, "muted": muted])
        let color = try #require(NSColor(style.quiet(on: nil)).usingColorSpace(.sRGB))
        let backdrop = try #require(Contrast.over(bg, Contrast.RGB(r: 0, g: 0, b: 0)))
        let a = color.alphaComponent
        let text = Contrast.RGB(r: color.redComponent * a + backdrop.r * (1 - a), g: color.greenComponent * a + backdrop.g * (1 - a),
                                b: color.blueComponent * a + backdrop.b * (1 - a))
        #expect(Contrast.ratio(text, backdrop) >= 4.5)
    }

    /// The glass and the halo's edge leave text on something lighter than the palette: the quiet color keeps 4.5:1
    /// with 12% of fg over the palette's backdrop. Tokyo Night's muted color needs the lift on its pill and on the
    /// screen; a short fg ("#ccc") lifts it the same way.
    @Test(arguments: [("#c0caf5", nil), ("#c0caf5", "surface"), ("#ccc", nil)] as [(String, String?)])
    func theQuietColorKeepsAMarginOverThePalette(fg: String, surface: String?) throws {
        let palette = ["bg": "#1a1b26", "fg": fg, "muted": "#565f89", "surface": "#24283bcc"]
        let style = LockyStyle(palette: palette)
        let color = try #require(NSColor(style.quiet(on: surface)).usingColorSpace(.sRGB))
        let fgColor = try #require(NSColor(hex: fg))
        let margin = String(format: "#%02x%02x%02x1f", Int((fgColor.redComponent * 255).rounded()),
                            Int((fgColor.greenComponent * 255).rounded()), Int((fgColor.blueComponent * 255).rounded()))
        var layers = ["#1a1b26"]
        if let surface { layers.append(try #require(palette[surface])) }
        layers.append(margin)
        let backdrop = layers.reduce(Contrast.RGB(r: 0, g: 0, b: 0)) { Contrast.over($1, $0)! }
        let a = color.alphaComponent
        let text = Contrast.RGB(r: color.redComponent * a + backdrop.r * (1 - a), g: color.greenComponent * a + backdrop.g * (1 - a),
                                b: color.blueComponent * a + backdrop.b * (1 - a))
        #expect(Contrast.ratio(text, backdrop) >= 4.5)
    }
}

/// The model, not the view, decides when a check may start.
@MainActor
@Suite struct AuthModelTests {
    @Test func wrongPasswordShowsUntilTheNextKey() {
        let model = AuthModel()
        #expect(!model.wrongShown)
        model.failed()
        #expect(model.wrongShown)
        model.password = "a"
        #expect(!model.wrongShown)
    }

    @Test func noCheckStartsDuringTheWaitOrAnotherCheck() async {
        let model = AuthModel()
        for _ in 0..<3 { model.failed() }
        #expect(model.waitLeft > 0)
        #expect(!model.beginCheck())
        #expect(!model.checking)
        // The third wrong password waits one second.
        let deadline = Date().addingTimeInterval(5)
        while model.waitLeft > 0, Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(model.beginCheck())
        #expect(model.checking)
        #expect(!model.beginCheck())
        model.endCheck()
        #expect(!model.checking)
    }

    @Test func aCheckThatRunsLongIsSlowUntilItEnds() async throws {
        let model = AuthModel(slowAfter: .milliseconds(50))
        var calls = 0
        model.onSlowCheck = { calls += 1 }
        // A check that ends in time is never slow.
        #expect(model.beginCheck())
        model.endCheck()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!model.slowCheck && calls == 0)

        #expect(model.beginCheck())
        let deadline = Date().addingTimeInterval(3)
        while !model.slowCheck, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.slowCheck && calls == 1)
        model.endCheck()
        #expect(!model.slowCheck)
    }
}

@Suite struct PasswordAttemptsTests {
    /// UserDefaults of their own, so no test touches the app's.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "locky-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func threeFreeTriesThenWaitsThatDoubleUpTo30SecondsThen5Minutes() {
        #expect((0...12).map(PasswordAttempts.wait(after:)) == [0, 0, 0, 1, 2, 4, 8, 16, 30, 30, 300, 300, 300])
    }

    @Test func theNextTryWaitsFromTheLastWrongPassword() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var attempts = PasswordAttempts()
        for second in 0..<3 { attempts.fail(at: start.addingTimeInterval(Double(second))) }
        #expect(attempts.count == 3)
        #expect(attempts.nextTry == start.addingTimeInterval(3))
        attempts = PasswordAttempts(count: 2, last: start)
        #expect(attempts.nextTry == nil)
    }

    @Test func theCountOutlastsTheLockAndEndsAfter15QuietMinutes() {
        withDefaults { defaults in
            let start = Date(timeIntervalSince1970: 1_000_000)
            var attempts = PasswordAttempts.load(defaults, now: start)
            for _ in 0..<4 { attempts.fail(at: start) }
            attempts.save(defaults)
            #expect(PasswordAttempts.load(defaults, now: start.addingTimeInterval(60)) == PasswordAttempts(count: 4, last: start))
            #expect(PasswordAttempts.load(defaults, now: start.addingTimeInterval(15 * 60)) == PasswordAttempts())
            // A wrong password after the quiet time counts as the first.
            attempts.fail(at: start.addingTimeInterval(15 * 60))
            #expect(attempts.count == 1)
        }
    }

    @Test func aLastFailureInTheFutureCountsAsNow() {
        withDefaults { defaults in
            let now = Date(timeIntervalSince1970: 1_000_000)
            PasswordAttempts(count: 10, last: now.addingTimeInterval(86_400)).save(defaults)
            let loaded = PasswordAttempts.load(defaults, now: now)
            #expect(loaded.nextTry == now.addingTimeInterval(300))
        }
    }

    /// A clock set back must not keep the count forever: the next lock saves the failure at now.
    @MainActor @Test func aFutureFailureIsForgotten15MinutesAfterTheNextLock() {
        withDefaults { defaults in
            PasswordAttempts(count: 10, last: Date().addingTimeInterval(86_400)).save(defaults)
            _ = AuthModel(defaults: defaults)
            #expect(PasswordAttempts.load(defaults, now: Date().addingTimeInterval(16 * 60)) == PasswordAttempts())
        }
    }

    @MainActor @Test func theWaitCountsDownAndEnds() async {
        let model = AuthModel()
        for _ in 0..<4 { model.failed() }
        // What the field shows, every 50 ms until the wait ends (a loaded test run can delay a step).
        var shown = [model.waitLeft]
        let deadline = Date().addingTimeInterval(10)
        while model.waitLeft > 0, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            if shown.last != model.waitLeft { shown.append(model.waitLeft) }
        }
        #expect(shown.first == 2 && shown.last == 0 && shown == shown.sorted(by: >), "\(shown)")
    }

    @MainActor @Test func aSuccessStartsTheCountAgainAndANewModelKeepsTheWait() async {
        withDefaults { defaults in
            let model = AuthModel(defaults: defaults)
            for _ in 0..<3 { model.failed() }
            #expect(model.wrong == 3)
            #expect(model.waitLeft == 1)
            // The next lock, or a relaunch, waits too; its own count of wrong passwords starts at 0.
            let next = AuthModel(defaults: defaults)
            #expect(next.waitLeft == 1)
            #expect(next.wrong == 0)
            next.failed()
            #expect(next.waitLeft == 2)
            next.succeeded()
            #expect(PasswordAttempts.load(defaults) == PasswordAttempts())
            #expect(AuthModel(defaults: defaults).waitLeft == 0)
        }
    }
}

@Suite struct ContrastTests {
    private let black = Contrast.RGB(r: 0, g: 0, b: 0), white = Contrast.RGB(r: 1, g: 1, b: 1)

    @Test func theRatioFollowsWCAG() {
        #expect(abs(Contrast.ratio(black, white) - 21) < 0.001)
        #expect(Contrast.ratio(white, white) == 1)
        // #777777 on white is the classic near miss: 4.48:1.
        let gray = Contrast.over("#777777", black)!
        #expect(abs(Contrast.ratio(gray, white) - 4.48) < 0.01)
    }

    @Test func alphaMixesWithWhatIsBelow() {
        let half = Contrast.over("#ffffff80", black)!
        #expect(abs(half.r - 128.0 / 255) < 0.001 && half.r == half.g && half.g == half.b)
    }

    @Test func readableTextStaysAsItIs() {
        #expect(Contrast.readable("#ffffffb3", fg: "#ffffff", on: ["#1c3a66", "#ffffff1f"]) == "#ffffffb3")
    }

    @Test func faintTextLiftsTowardFgUntilItReads() throws {
        // Tokyo Night: muted on its surface over bg.
        let layers = ["#1a1b26", "#24283bcc"]
        let lifted = try #require(Contrast.readable("#565f89", fg: "#c0caf5", on: layers))
        #expect(lifted != "#565f89")
        let backdrop = Contrast.over(layers[1], Contrast.over(layers[0], black)!)!
        let ratio = Contrast.ratio(Contrast.over(lifted, backdrop)!, backdrop)
        #expect(ratio >= 4.5 && ratio < 5.2, "lifted only as far as needed: \(ratio)")
    }

    @Test func fgIsTheMostItLifts() {
        #expect(Contrast.readable("#333333", fg: "#444444", on: ["#000000"]) == "#444444")
        #expect(Contrast.readable("muted", fg: "#ffffff", on: ["#000000"]) == nil)
    }
}

@MainActor
@Suite struct PreviewTouchIDTests {
    /// The theme editor's preview has no Touch ID of its own, but shows its glyph where the lock would, on a Mac
    /// that has it and unless settings.json turns it off.
    @Test(arguments: [true, false])
    func thePreviewShowsTheGlyphAsAPicture(touchIDOn: Bool) async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { background = { color = '#101010' } }")
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var options = LockSession.Options(theme: "t", container: container)
        options.path = sandbox.path()
        options.settings = Settings(touchIDOn ? [:] : ["touch_id": .bool(false)])
        let session = LockSession(mode: .embedded, options: options)
        session.begin()
        defer { session.end("test") }
        let screen = try #require(container.subviews.first as? LockScreenView)
        let panel = try #require(screen.auth?.view as? NSHostingView<AuthPanel>)
        #expect(panel.rootView.touchID == nil)
        #expect(panel.rootView.touchIDPicture == (touchIDOn && TouchID().isAvailable))
    }
}

/// The lock names ⌃⌥⌘Q under the field once someone looks stuck, and only then.
@MainActor
@Suite struct WayOutTests {
    /// A screen as the lock lays it out: a 240×64 field, the message when there is one, and the way out's row. The
    /// window sits far off the screen, so AppKit lays the screen out on its next pass after the session asks.
    private func lockScreen(field spec: Theme.Auth = Theme.Auth(), message: String? = nil, exit: Bool = true,
                            model: AuthModel) -> (NSWindow, LockScreenView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 1440, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let screen = LockScreenView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        window.contentView = screen
        window.orderBack(nil)
        screen.auth = (NSView(), spec)
        screen.authSize = CGSize(width: 240, height: 64)
        screen.message = message.map { NSHostingController(rootView: LockMessage(text: $0, model: nil, exit: false, auth: spec, style: LockyStyle())) }
        screen.wayOut = NSHostingController(rootView: LockMessage(text: nil, model: model, exit: exit, auth: spec, style: LockyStyle()))
        screen.layoutSubtreeIfNeeded()
        return (window, screen)
    }

    /// The way out's height before and after `change`.
    private func messageHeight(exit: Bool, model: AuthModel = AuthModel(slowAfter: .milliseconds(50)),
                               _ change: (AuthModel) async throws -> Void) async throws -> (before: CGFloat, after: CGFloat) {
        let (window, screen) = lockScreen(exit: exit, model: model)
        defer { window.orderOut(nil) }
        let before = screen.wayOut?.view.frame.height ?? -1
        try await change(model)
        screen.needsLayout = true
        await shows(screen)
        return (before, screen.wayOut?.view.frame.height ?? -1)
    }

    /// Lays the screen out until the way out has a height, for up to a second. Under a full test run's load, the
    /// off-screen window's own layout pass can come too late for a fixed wait.
    private func shows(_ screen: LockScreenView) async {
        let deadline = Date().addingTimeInterval(1)
        repeat {
            try? await Task.sleep(for: .milliseconds(20))
            screen.layoutSubtreeIfNeeded()
        } while (screen.wayOut?.view.frame.height ?? 0) <= 0 && Date() < deadline
    }

    /// Aurora's field ends 56 points over the bottom: a one-line message fits under it, the way out under that does
    /// not. The message stays where it is when the way out joins, which goes over the field.
    @Test func theMessageStaysWhereItIsWhenTheWayOutJoins() async throws {
        var spec = Theme.Auth()
        spec.offset = CGPoint(x: 0, y: -56)
        let model = AuthModel()
        let (window, screen) = lockScreen(field: spec, message: "If found, please call 555-0100", model: model)
        defer { window.orderOut(nil) }
        let field = try #require(screen.auth?.view.frame), before = try #require(screen.message?.view.frame)
        #expect(before.minY == field.maxY + 14 && before.height > 0)
        for _ in 0..<3 { model.failed() }
        screen.needsLayout = true
        await shows(screen)
        let wayOut = try #require(screen.wayOut?.view.frame)
        #expect(screen.message?.view.frame == before)
        #expect(wayOut.height > 0 && wayOut.maxY == field.minY - 14 && abs(wayOut.midX - field.midX) <= 1)
    }

    /// With room under the message, the way out follows it as one more line.
    @Test func theWayOutFollowsTheMessageWhenThereIsRoom() async throws {
        var spec = Theme.Auth()
        spec.anchor = .center
        spec.offset = .zero
        let model = AuthModel()
        let (window, screen) = lockScreen(field: spec, message: "If found, please call 555-0100", model: model)
        defer { window.orderOut(nil) }
        for _ in 0..<3 { model.failed() }
        screen.needsLayout = true
        await shows(screen)
        let field = try #require(screen.auth?.view.frame), message = try #require(screen.message?.view.frame)
        let wayOut = try #require(screen.wayOut?.view.frame)
        #expect(message.minY == field.maxY + 14)
        #expect(wayOut.height > 0 && wayOut.minY == message.maxY + 4 && abs(wayOut.midX - field.midX) <= 1)
    }

    @Test func theThirdWrongPasswordNamesTheWayOut() async throws {
        let twice = try await messageHeight(exit: true) { model in for _ in 0..<2 { model.failed() } }
        #expect(twice.before == 0 && twice.after == 0)
        let thrice = try await messageHeight(exit: true) { model in for _ in 0..<3 { model.failed() } }
        #expect(thrice.before == 0 && thrice.after > 0)
    }

    @Test func aCheckThatHangsNamesTheWayOut() async throws {
        let hung = try await messageHeight(exit: true) { model in
            _ = model.beginCheck()
            let deadline = Date().addingTimeInterval(3)
            while !model.slowCheck, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(hung.before == 0 && hung.after > 0)
    }

    @Test func withoutTheExitNothingIsNamed() async throws {
        let off = try await messageHeight(exit: false) { model in for _ in 0..<3 { model.failed() } }
        #expect(off.after == 0)
    }

    /// Ten wrong passwords, ⌃⌥⌘Q, and the macOS unlock: a lock in the next 5 minutes starts with its field disabled and
    /// no wrong password of its own. It names the way out from the start.
    @Test func aLockThatStartsInTheWaitNamesTheWayOut() async throws {
        let name = "locky-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        PasswordAttempts(count: 10, last: Date()).save(defaults)
        let model = AuthModel(defaults: defaults)
        #expect(model.waited && model.waitLeft > 0 && model.wrong == 0)
        let waiting = try await messageHeight(exit: true, model: model) { _ in }
        #expect(waiting.before > 0)
        // A lock with no wait behind it starts without the line.
        let fresh = AuthModel(defaults: defaults)
        fresh.succeeded()
        #expect(!AuthModel(defaults: defaults).waited)
    }

    /// Twelve wrong passwords, ⌃⌥⌘Q, and the macOS unlock; a lock 6 minutes later starts with no wait, but the count
    /// carries over, so its first wrong password waits 5 minutes. The way out shows with that wait.
    @Test func aWaitFromACarriedCountNamesTheWayOut() async throws {
        let name = "locky-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        PasswordAttempts(count: 12, last: Date().addingTimeInterval(-360)).save(defaults)
        let model = AuthModel(defaults: defaults)
        #expect(model.waitLeft == 0 && !model.waited)
        let carried = try await messageHeight(exit: true, model: model) { model in model.failed() }
        #expect(model.wrong == 1 && model.waitLeft > 59)
        #expect(carried.before == 0 && carried.after > 0)
    }
}

@Suite struct SafeLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 240, height: 64)

    @Test func aFramePastAnEdgeMovesBackInside() {
        func kept(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            Layout.keep(CGRect(origin: CGPoint(x: x, y: y), size: size), inside: screen, margin: 16).origin
        }
        #expect(kept(-40, 300) == CGPoint(x: 16, y: 300))
        #expect(kept(600, -10) == CGPoint(x: 600, y: 16))
        #expect(kept(1300, 300) == CGPoint(x: 1440 - 16 - 240, y: 300))
        #expect(kept(600, 880) == CGPoint(x: 600, y: 900 - 16 - 64))
        #expect(kept(600, 400) == CGPoint(x: 600, y: 400))
        // Wider than the screen: its left edge stays on the margin.
        #expect(Layout.keep(CGRect(x: -100, y: 400, width: 2000, height: 20), inside: screen, margin: 16).minX == 16)
    }

    /// An offset that reaches past the edge leaves the field 16 points inside it.
    @MainActor @Test func thePasswordFieldStaysOnTheScreen() {
        let view = LockScreenView(frame: screen)
        var spec = Theme.Auth()
        spec.anchor = .bottomLeft
        spec.offset = CGPoint(x: -40, y: 30)
        view.auth = (NSView(), spec)
        view.authSize = size
        view.layout()
        #expect(view.auth?.view.frame == CGRect(x: 16, y: 900 - 16 - 64, width: 240, height: 64))
    }
}

@MainActor
@Suite struct GlanceHintTests {
    private func screen(reveal: String) async throws -> (LockSession, LockScreenView) {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { background = { color = '#101010' }, auth = { reveal = '\(reveal)' } }")
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var options = LockSession.Options(theme: "t", container: container)
        options.path = sandbox.path()
        let session = LockSession(mode: .embedded, options: options)
        session.begin()
        let screen = try #require(container.subviews.first as? LockScreenView)
        let deadline = Date().addingTimeInterval(3)
        while screen.background == nil, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        return (session, screen)
    }

    /// While a field that shows on activity hides, a hint says how to bring it back, where it will appear.
    @Test func aHiddenFieldLeavesAHintInItsPlace() async throws {
        let (session, screen) = try await screen(reveal: "activity")
        defer { session.end("test") }
        let hint = try #require(screen.glanceHint)
        let field = try #require(screen.auth?.view)
        screen.layoutSubtreeIfNeeded()
        #expect(hint.alphaValue == 1 && field.alphaValue < 0.1)
        #expect(abs(hint.frame.midX - field.frame.midX) <= 1 && abs(hint.frame.midY - field.frame.midY) <= 1)
        screen.setAuthVisible(true, dim: 0, animated: false)
        #expect(hint.alphaValue == 0)
        // The hint lies under the field, so a click where it was reaches the field.
        let hit = screen.hitTest(hint.convert(CGPoint(x: hint.bounds.midX, y: hint.bounds.midY), to: screen.superview))
        #expect(hit?.isDescendant(of: field) == true, "the click reaches \(String(describing: hit))")
    }

    /// A key or the mouse brings the field and takes the hint away at once: neither animates.
    @Test func aKeyBringsTheFieldAtOnce() async throws {
        let (session, screen) = try await screen(reveal: "activity")
        defer { session.end("test") }
        let hint = try #require(screen.glanceHint?.layer), field = try #require(screen.auth?.view.layer)
        screen.setAuthVisible(true, dim: 0.25, animated: true)
        #expect(field.opacity == 1 && hint.opacity == 0)
        #expect(field.animationKeys() == nil && hint.animationKeys() == nil)
    }

    @Test func aFieldThatAlwaysShowsHasNoHint() async throws {
        let (session, screen) = try await screen(reveal: "always")
        defer { session.end("test") }
        #expect(screen.glanceHint == nil)
    }
}

/// The lock's first frame is the last theme's bg with the password field; the scene comes in whole once it is ready.
@MainActor
@Suite struct SceneRevealTests {
    private func widget(size: CGSize?) -> WidgetHost {
        let placement = Theme.Placement(widget: "w", anchor: .center, offset: .zero, size: size, align: nil, card: nil, allDisplays: false, known: true)
        return WidgetHost(placement: placement, theme: .fallback, style: LockyStyle(), showsErrors: true)
    }

    @Test func theSceneWaitsAndThenShowsWhole() {
        let screen = LockScreenView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        screen.fadesIn = false
        let background = NSView(), overlay = NSView()
        let sized = widget(size: CGSize(width: 100, height: 40)), unmeasured = widget(size: nil)
        screen.background = background
        screen.overlay = overlay
        screen.add(sized)
        screen.add(unmeasured)
        screen.layoutSubtreeIfNeeded()
        #expect([background, overlay, sized, unmeasured].allSatisfy { $0.alphaValue == 0 })
        screen.reveal(animated: false)
        #expect(background.alphaValue == 1 && overlay.alphaValue == 1 && sized.alphaValue == 1)
        #expect(unmeasured.alphaValue == 0)
        // Measured later, it shows alone.
        unmeasured.model.contentSize = CGSize(width: 50, height: 20)
        screen.needsLayout = true
        screen.layoutSubtreeIfNeeded()
        #expect(unmeasured.alphaValue == 1)
    }

    /// The theme editor's preview, where keys remove widgets and change the background: nothing fades.
    @Test func theEditorsPreviewChangesAtOnce() async throws {
        let screen = LockScreenView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        screen.fadesIn = false
        screen.reveal(animated: false)
        let gone = widget(size: CGSize(width: 100, height: 40))
        screen.add(gone)
        screen.remove(gone)
        #expect(gone.superview == nil)
        let first = NSView(), next = NSView()
        screen.background = first
        screen.replaceBackground(with: next)
        // Nothing to load: it swaps on the next turn of the main actor.
        try await Task.sleep(for: .milliseconds(50))
        #expect(screen.background === next && next.alphaValue == 1 && first.superview == nil)
    }

    /// Under the scene, once the theme arrives: its own bg, opaque.
    @Test func theScreenTakesTheThemesBg() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { palette = { bg = '#F1EFE8' }, background = { color = '#101010' } }")
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var options = LockSession.Options(theme: "t", container: container)
        options.path = sandbox.path()
        let session = LockSession(mode: .embedded, options: options)
        session.begin()
        defer { session.end("test") }
        let screen = try #require(container.subviews.first as? LockScreenView)
        let deadline = Date().addingTimeInterval(3)
        while screen.background == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let color = try #require(screen.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) })
        let expected = try #require(NSColor(hex: "#F1EFE8")?.usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - expected.redComponent) < 0.01 && abs(color.blueComponent - expected.blueComponent) < 0.01)
        #expect(color.alphaComponent == 1)
    }
}

/// The theme's bg close around the lock screen's text: readable on a scene that does not match the palette, and
/// nothing darkened around it.
@MainActor
@Suite struct LegibilityHaloTests {
    /// The WCAG ratio between the brightest and the darkest tenth of a rendering's pixels, as the acceptance captures
    /// measure text and what is behind it.
    private func contrast(_ view: some View) throws -> (ratio: Double, light: Double, dark: Double) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let (width, height) = (image.width, image.height)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try #require(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
        let luminances = (0..<(width * height)).map { index in
            let pixel = pixels + index * 4
            return Contrast.luminance(Contrast.RGB(r: Double(pixel[0]) / 255, g: Double(pixel[1]) / 255, b: Double(pixel[2]) / 255))
        }.sorted()
        let tenth = max(1, luminances.count / 10)
        let dark = luminances.prefix(tenth).reduce(0, +) / Double(tenth), light = luminances.suffix(tenth).reduce(0, +) / Double(tenth)
        return ((light + 0.05) / (dark + 0.05), light, dark)
    }

    /// Snowfall's status line on snow brighter than any behind its field: unreadable alone, past 4.5:1 with the halo.
    /// The text, not the snow, is the brightest tenth, so the ratio is the text's against its halo.
    @Test func quietTextReadsOnBrightSnow() throws {
        let style = LockyStyle(palette: ["bg": "#0a1426", "fg": "#f4f8ff", "muted": "#dbe7f7b3"])
        let snow = Contrast.RGB(r: 0.82, g: 0.85, b: 0.90)
        let line = Text("Touch ID or Enter Password")
            .font(style.font(size: 12, weight: "medium", design: nil, family: "Avenir Next", mono: false, italic: false))
            .foregroundStyle(style.quiet(on: nil))
        let plain = try contrast(line.background(Color(red: snow.r, green: snow.g, blue: snow.b)))
        let halo = try contrast(line.legibilityHalo(style).background(Color(red: snow.r, green: snow.g, blue: snow.b)))
        #expect(plain.ratio < 2)
        #expect(halo.ratio >= 4.5 && halo.light < Contrast.luminance(snow), "\(halo)")
    }

    /// Nothing lies between the scene and the widgets: a scene that matches its palette shows as it is around the field
    /// and its message.
    @Test func nothingDarkensTheSceneAroundTheField() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { background = { color = '#101010' }, widgets = { { 'w', anchor = 'bottom' } } }")
        try sandbox.write("plugin/w.lua", "locky.widget.define('w', { render = function(self) return locky.ui.text('w') end })")
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var options = LockSession.Options(theme: "t", container: container)
        options.path = sandbox.path()
        options.settings = Settings(["message": .string("If found, call 555-0100")])
        let session = LockSession(mode: .embedded, options: options)
        session.begin()
        defer { session.end("test") }
        let screen = try #require(container.subviews.first as? LockScreenView)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            screen.layoutSubtreeIfNeeded()
            if screen.message != nil, screen.authSize.width > 0, !screen.widgets.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let background = try #require(screen.background), widget = try #require(screen.widgets.first)
        let order = screen.subviews
        #expect(order.firstIndex(of: widget) == order.firstIndex(of: background).map { $0 + 1 })
    }
}
