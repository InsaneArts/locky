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
    /// The message's height before and after `change`, laid out as the lock does it: the session asks for a layout,
    /// and AppKit lays the screen out on its next pass. The window sits far off the screen.
    private func messageHeight(exit: Bool, _ change: (AuthModel) async throws -> Void) async throws -> (before: CGFloat, after: CGFloat) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 1440, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        let screen = LockScreenView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        window.contentView = screen
        window.orderBack(nil)
        screen.auth = (NSView(), Theme.Auth())
        screen.authSize = CGSize(width: 240, height: 64)
        let model = AuthModel(slowAfter: .milliseconds(50))
        screen.message = NSHostingController(rootView: LockMessage(text: nil, model: model, exit: exit, auth: Theme.Auth(), style: LockyStyle()))
        screen.layoutSubtreeIfNeeded()
        let before = screen.message?.view.frame.height ?? -1
        try await change(model)
        screen.needsLayout = true
        try await Task.sleep(for: .milliseconds(100))
        return (before, screen.message?.view.frame.height ?? -1)
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

@MainActor
@Suite struct LegibilityScrimTests {
    /// In every mode, the theme editor's preview too: right above the background, under the widgets, around the field
    /// and the message.
    @Test func theScrimLiesUnderTheWidgetsAroundTheFieldAndTheMessage() async throws {
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
        // Laid out as a window would: nothing else lays out a screen outside one.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            screen.layoutSubtreeIfNeeded()
            if screen.scrim != nil, screen.message != nil, screen.authSize.width > 0, !screen.widgets.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let scrim = try #require(screen.scrim), background = try #require(screen.background), widget = try #require(screen.widgets.first)
        let field = try #require(screen.auth?.view.frame), message = try #require(screen.message?.view.frame)
        let order = screen.subviews
        #expect(order.firstIndex(of: scrim) == order.firstIndex(of: background).map { $0 + 1 })
        #expect((order.firstIndex(of: scrim) ?? 99) < (order.firstIndex(of: widget) ?? -1))
        #expect(!message.isEmpty && scrim.frame == field.union(message).insetBy(dx: -48, dy: -48).integral)
        #expect(scrim.hitTest(CGPoint(x: scrim.frame.midX, y: scrim.frame.midY)) == nil)
    }
}
