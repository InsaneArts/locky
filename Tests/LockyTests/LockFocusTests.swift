import AppKit
import SwiftUI
import Testing
@testable import Locky

/// Polls `condition` on the main actor, where the screens live, for up to ten seconds: in a full run other suites keep
/// the main actor busy.
@MainActor
func waitUntil(_ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(10)
    while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    return condition()
}

/// Every key typed during a lock goes to the password field, without a click: from the field's first frame, after
/// anything took the keyboard, and after a click anywhere on a shield.
@MainActor
@Suite(.serialized) struct LockFocusTests {
    /// A shield as a lock makes it, far off the screen, made key. `transitions`: the scene in a TransitionStage, as a
    /// lock with lock_animation has it while it comes in.
    private func shield(transitions: Bool = false, allowsKey: Bool = true) -> (ShieldWindow, LockScreenView) {
        _ = NSApplication.shared
        let frame = CGRect(x: allowsKey ? -20000 : -24000, y: -20000, width: 1440, height: 900)
        let window = ShieldWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.allowsKey = allowsKey
        let screen = LockScreenView()
        LockSession.prepare(window, scene: screen, transitions: transitions, comingIn: transitions, reduceTransparency: false)
        window.setFrame(frame, display: false)
        window.makeKeyAndOrderFront(nil)
        return (window, screen)
    }

    private func field(_ model: AuthModel, touchID: TouchID? = nil) -> NSHostingView<AuthPanel> {
        NSHostingView(rootView: AuthPanel(auth: Theme.Auth(), style: LockyStyle(), touchID: touchID, model: model, unlock: {}, failed: {}))
    }

    private func type(_ characters: String, in window: NSWindow) {
        for character in characters.map(String.init) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                         context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: 0)
            window.sendEvent(try! #require(event))
        }
    }

    /// A click at `point`, in the screen's flipped coordinates.
    private func click(_ point: CGPoint, on screen: LockScreenView) {
        guard let window = screen.window else { return }
        let location = screen.convert(point, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            window.sendEvent(try! #require(event))
        }
    }

    /// The first key after a field appears (the lock's start, the theme's field taking over, new windows for a display)
    /// lands in it, before SwiftUI asks for focus; also while the lock comes in.
    @Test(arguments: [false, true])
    func theFirstKeyLandsInANewField(transitions: Bool) {
        let (window, screen) = shield(transitions: transitions)
        defer { window.orderOut(nil) }
        let model = AuthModel()
        screen.auth = (field(model), Theme.Auth())
        type("ab", in: window)
        #expect(model.password == "ab")
        #expect(screen.fieldHasKeyboard)
    }

    /// The session gives a new field the keyboard at once, so it shows its caret before anyone types.
    @Test func aNewFieldTakesTheKeyboardAtOnce() {
        let (window, screen) = shield()
        defer { window.orderOut(nil) }
        screen.auth = (field(AuthModel()), Theme.Auth())
        #expect(screen.focusField())
        #expect(screen.fieldHasKeyboard)
    }

    /// Whatever held the keyboard last (nothing, or the window itself), the next key goes to the field.
    @Test func aKeyAfterTheFieldLostTheKeyboardLandsInIt() {
        let (window, screen) = shield()
        defer { window.orderOut(nil) }
        let model = AuthModel()
        screen.auth = (field(model), Theme.Auth())
        screen.focusField()
        window.makeFirstResponder(nil)
        #expect(!screen.fieldHasKeyboard)
        type("x", in: window)
        #expect(model.password == "x" && screen.fieldHasKeyboard)
    }

    /// A click on the scene, the message, the ⌃⌥⌘Q line, or beside the field leaves the field with the keyboard, also
    /// when it had lost it before.
    @Test(arguments: ["scene", "message", "way out", "beside the field"])
    func aClickAnywhereLeavesTheFieldWithTheKeyboard(target: String) {
        let (window, screen) = shield()
        defer { window.orderOut(nil) }
        let model = AuthModel()
        // Stuck, so the ⌃⌥⌘Q line shows, without the wait that would disable the field.
        model.wrong = 3
        screen.auth = (field(model), Theme.Auth())
        screen.authSize = CGSize(width: 240, height: 64)
        screen.message = NSHostingController(rootView: LockMessage(text: "If found, call 555-0100", model: nil, exit: false, auth: Theme.Auth(),
                                                                   style: LockyStyle()))
        screen.wayOut = NSHostingController(rootView: LockMessage(text: nil, model: model, exit: true, auth: Theme.Auth(), style: LockyStyle()))
        screen.layoutSubtreeIfNeeded()
        screen.focusField()
        window.makeFirstResponder(nil)
        let point: CGPoint = switch target {
        case "message": CGPoint(x: screen.message!.view.frame.midX, y: screen.message!.view.frame.midY)
        case "way out": CGPoint(x: screen.wayOut!.view.frame.midX, y: max(screen.wayOut!.view.frame.midY, 1))
        case "beside the field": CGPoint(x: screen.auth!.view.frame.minX + 2, y: screen.auth!.view.frame.minY + 2)
        default: CGPoint(x: 40, y: 40)
        }
        click(point, on: screen)
        #expect(screen.fieldHasKeyboard, "after a click on the \(target)")
    }

    /// A click on another display's shield, which never becomes key, leaves the main shield's field with the keyboard.
    @Test func aClickOnAnotherDisplaysShieldKeepsTheField() {
        let (window, screen) = shield()
        let (other, otherScreen) = shield(allowsKey: false)
        defer { window.orderOut(nil); other.orderOut(nil) }
        screen.auth = (field(AuthModel()), Theme.Auth())
        screen.focusField()
        window.makeKey()
        click(CGPoint(x: 100, y: 100), on: otherScreen)
        #expect(screen.fieldHasKeyboard && !other.isKeyWindow)
    }

    /// A hidden field (a theme that shows it on activity) keeps the keyboard: the key that shows it counts.
    @Test func aHiddenFieldTakesTheFirstKey() {
        let (window, screen) = shield()
        defer { window.orderOut(nil) }
        let model = AuthModel()
        screen.auth = (field(model), Theme.Auth())
        screen.setAuthVisible(false, dim: 0, animated: false)
        type("k", in: window)
        #expect(model.password == "k")
    }

    /// After a password check and after the wait that wrong passwords bring, the field takes the keys again.
    @Test func theFieldTakesKeysAfterACheckAndTheWait() async {
        let (window, screen) = shield()
        defer { window.orderOut(nil) }
        let model = AuthModel()
        screen.auth = (field(model), Theme.Auth())
        screen.focusField()
        _ = model.beginCheck()
        // The disabled field gives up the keyboard while the check runs.
        #expect(await waitUntil { !screen.fieldHasKeyboard })
        model.endCheck()
        for _ in 0..<3 { model.failed() }
        #expect(model.waitLeft > 0)
        #expect(await waitUntil { model.waitLeft == 0 })
        // The field takes the keyboard back by itself once it is enabled again.
        #expect(await waitUntil { screen.fieldHasKeyboard })
        type("w", in: window)
        #expect(model.password == "w" && screen.fieldHasKeyboard)
    }

    /// Touch ID listening again with a new context (after the system cancelled it, or a wake) makes a new glyph; the field
    /// keeps the keyboard.
    @Test func aNewTouchIDGlyphLeavesTheFieldWithTheKeyboard() async {
        let (window, screen) = shield()
        defer { window.orderOut(nil) }
        let touchID = TouchID()
        screen.auth = (field(AuthModel(), touchID: touchID), Theme.Auth())
        screen.focusField()
        let generation = touchID.generation
        touchID.restart()
        #expect(await waitUntil { touchID.generation > generation })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(screen.fieldHasKeyboard)
    }

    /// Caps Lock and the other modifiers change nothing about who has the keyboard.
    @Test func aModifierKeepsTheFieldWithTheKeyboard() throws {
        let (window, screen) = shield()
        defer { window.orderOut(nil) }
        screen.auth = (field(AuthModel()), Theme.Auth())
        screen.focusField()
        let flags = try #require(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [.capsLock], timestamp: 0,
                                                  windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                                                  isARepeat: false, keyCode: 57))
        window.sendEvent(flags)
        #expect(screen.fieldHasKeyboard)
    }

    /// The theme editor's preview: its field never takes the keyboard, which the canvas keeps.
    @Test func theEditorsFieldNeverTakesTheKeyboard() async {
        let (window, screen) = shield()
        defer { window.orderOut(nil) }
        let panel = AuthPanel(auth: Theme.Auth(), style: LockyStyle(), touchID: nil, model: AuthModel(), unlock: {}, failed: {}, interactive: false)
        screen.auth = (NSHostingView(rootView: panel), Theme.Auth())
        #expect(!screen.focusField())
        try? await Task.sleep(for: .milliseconds(400))
        #expect(!screen.fieldHasKeyboard)
    }
}

/// The `preview` window, as a lock has its screen: the field has the keyboard from the first frame and after a wake;
/// the first key of a hidden field shows it and lands in it; Caps Lock shows.
@MainActor
@Suite(.serialized) struct PreviewFocusTests {
    private func preview(_ theme: String = "return { background = { color = '#101010' } }",
                         settings: [String: LuaValue] = [:]) throws -> (LockSession, NSWindow, LockScreenView, Sandbox) {
        _ = NSApplication.shared
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", theme)
        var options = LockSession.Options(theme: "t", previewSize: CGSize(width: 1440, height: 900), behind: true)
        options.path = sandbox.path()
        options.remembers = false
        options.settings = Settings(settings.merging(["privacy": .bool(true), "touch_id": .bool(false)]) { a, _ in a })
        let session = LockSession(mode: .preview, options: options)
        session.begin()
        let window = try #require(NSApp.windows.last { $0 is PreviewWindow && $0.isVisible })
        // Off the screen: the window was behind every other one, and is now out of sight too.
        window.setFrameOrigin(CGPoint(x: -20000, y: -20000))
        let screen = try #require(window.contentView as? LockScreenView)
        return (session, window, screen, sandbox)
    }

    private func send(_ type: NSEvent.EventType, _ characters: String = "", flags: NSEvent.ModifierFlags = [], to window: NSWindow) throws {
        let event: NSEvent? = switch type {
        case .keyDown, .flagsChanged:
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                             characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: type == .flagsChanged ? 57 : 0)
        default:
            NSEvent.mouseEvent(with: type, location: CGPoint(x: 10, y: 10), modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 0, pressure: 0)
        }
        // Through the app, as macOS delivers it: the lock's event monitors see it first, then the key window.
        NSApp.sendEvent(try #require(event))
    }

    private func model(_ screen: LockScreenView) -> AuthModel? { (screen.auth?.view as? NSHostingView<AuthPanel>)?.rootView.model }

    @Test func theFieldHasTheKeyboardFromTheFirstFrame() throws {
        let (session, window, screen, sandbox) = try preview()
        defer { session.end("test"); _ = sandbox }
        #expect(screen.fieldHasKeyboard, "the first responder is \(String(describing: window.firstResponder))")
    }

    @Test(arguments: [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification])
    func aWakeGivesTheFieldTheKeyboard(name: Notification.Name) throws {
        let (session, window, screen, sandbox) = try preview()
        defer { session.end("test"); _ = sandbox }
        window.makeFirstResponder(nil)
        NSWorkspace.shared.notificationCenter.post(name: name, object: nil)
        #expect(screen.fieldHasKeyboard)
    }

    /// Glass hides its field until a key: that key shows it, and its character is the first of the password.
    @Test func theKeyThatShowsAHiddenFieldLandsInIt() async throws {
        let (session, window, screen, sandbox) = try preview("return { background = { color = '#101010' }, auth = { reveal = 'activity' } }")
        defer { session.end("test"); _ = sandbox }
        #expect(await waitUntil { screen.glanceHint != nil && !screen.authVisible })
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        try send(.keyDown, "p", to: window)
        #expect(screen.authVisible)
        #expect(model(screen)?.password == "p")
    }

    /// Caps Lock shows from each modifier change the lock sees.
    @Test func capsLockFollowsTheModifierKeys() throws {
        let (session, window, screen, sandbox) = try preview()
        defer { session.end("test"); _ = sandbox }
        try send(.flagsChanged, flags: [.capsLock], to: window)
        #expect(model(screen)?.capsLock == true)
        try send(.flagsChanged, flags: [], to: window)
        #expect(model(screen)?.capsLock == false)
        #expect(screen.fieldHasKeyboard)
    }
}
