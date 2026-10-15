import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Locky

@Suite struct OnboardingTests {
    /// UserDefaults of its own, gone after the test.
    final class Defaults {
        let name = "locky-tests-\(UUID().uuidString)"
        let defaults: UserDefaults

        init() { defaults = UserDefaults(suiteName: name)! }
        deinit { defaults.removePersistentDomain(forName: name) }
    }

    /// The Welcome opens by itself on the first launch only, and never in a tool run (screenshots, the source tree).
    @MainActor @Test func theWelcomeOpensOnceAndNeverInAToolRun() {
        let store = Defaults()
        #expect(WelcomeView.opensAtLaunch(store.defaults, isTool: true) == false)
        #expect(store.defaults.bool(forKey: WelcomeView.shownKey) == false)
        #expect(WelcomeView.opensAtLaunch(store.defaults, isTool: false) == true)
        #expect(WelcomeView.opensAtLaunch(store.defaults, isTool: false) == false)
    }

    /// `locky window welcome` (and window-shot.sh) opens it.
    @MainActor @Test func theWelcomeOpensFromTheCommandLine() {
        #expect(CLI.GUILaunch.parse(["window", "welcome"]).window == .welcome)
    }

    /// Three pages in order: the first has no Back, the last no Continue.
    @MainActor @Test func thePagesGoInOrder() {
        #expect(WelcomeView.Page.allCases == [.welcome, .lockScreen, .safety])
        #expect(WelcomeView.Page.welcome.previous == nil && WelcomeView.Page.welcome.next == .lockScreen)
        #expect(WelcomeView.Page.safety.previous == .lockScreen && WelcomeView.Page.safety.next == nil)
    }

    /// `window welcome --page 2` (window-shot.sh's PAGE) opens on the second page; anything else on the first.
    @MainActor @Test(arguments: [(["window", "welcome", "--page", "2"], .lockScreen), (["window", "welcome", "--page", "3"], .safety),
                                 (["window", "welcome"], .welcome), (["window", "welcome", "--page", "9"], .welcome),
                                 (["window", "welcome", "--page", "x"], .welcome)] as [([String], WelcomeView.Page)])
    func aToolRunOpensOnThePageItNames(_ arguments: [String], _ page: WelcomeView.Page) {
        #expect(WelcomeWindowController.firstPage(arguments) == page)
    }

    /// Return is Continue and then Done, ⌘[ is Back, and Esc closes. A closed Welcome opens again on the first page,
    /// with the switch's memory gone.
    @MainActor @Test func theKeysMoveThroughThePagesAndClose() async throws {
        _ = NSApplication.shared
        let model = AppModel(store: SettingsStore(config: try Sandbox().config))
        var closed = 0
        let controller = WelcomeWindowController(model: model) { closed += 1 }
        let window = try #require(controller.window)
        controller.show(behind: true)
        defer { window.orderOut(nil) }
        func press(_ code: UInt16, _ text: String, _ modifiers: NSEvent.ModifierFlags = []) async {
            window.contentView?.layoutSubtreeIfNeeded()
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
                                         context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
            // As NSApplication sends a key: a key equivalent first, then the keyboard's view.
            if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
        }
        /// Polls on the main actor while the window lays out, as a window on screen would.
        func settles(_ condition: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(5)
            while !condition(), Date() < deadline {
                window.contentView?.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(20))
            }
            return condition()
        }
        let visit = controller.visit
        await press(36, "\r")
        #expect(await settles { visit.page == .lockScreen })
        await press(33, "[", .command)
        #expect(await settles { visit.page == .welcome })
        await press(36, "\r")
        #expect(await settles { visit.page == .lockScreen })
        await press(36, "\r")
        #expect(await settles { visit.page == .safety })
        visit.turnedOff = AutoLockSettings(systemSleep: true)
        await press(36, "\r")
        #expect(await settles { closed == 1 && !window.isVisible })
        #expect(visit.page == .welcome && visit.turnedOff == nil)

        controller.show(behind: true)
        await press(36, "\r")
        #expect(await settles { visit.page == .lockScreen })
        await press(53, "\u{1b}")
        #expect(await settles { closed == 2 && !window.isVisible })
        #expect(visit.page == .welcome)
    }

    /// Page 2 with every row it can have (approval in Login Items, a shortcut problem, the Touch ID button) keeps the
    /// first page's height, and its Form scrolls what does not fit: a Form that grew the window made AppKit's layout
    /// loop until the app stopped.
    @MainActor @Test func theSecondPageKeepsTheFirstPagesHeight() async throws {
        _ = NSApplication.shared
        let mac = PermissionsTests.Mac()
        mac.loginItem = .requiresApproval
        let model = AppModel(store: SettingsStore(config: try Sandbox().config), permissions: Permissions(system: mac.system))
        model.shortcutProblem = "Another app uses this shortcut."
        let controller = WelcomeWindowController(model: model) {}
        let window = try #require(controller.window)
        controller.show(behind: true)
        defer { window.orderOut(nil) }
        func settle() async {
            for _ in 0..<20 {
                window.contentView?.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        await settle()
        let first = window.frame.height
        controller.visit.page = .lockScreen
        await settle()
        #expect(window.frame.height == first)
        #expect(mac.quiet)
    }

    /// Each page lays out at the window's width, in light and dark.
    @MainActor @Test(arguments: WelcomeView.Page.allCases, [NSAppearance.Name.aqua, .darkAqua])
    func eachPageBuilds(_ page: WelcomeView.Page, _ appearance: NSAppearance.Name) throws {
        _ = NSApplication.shared
        let model = AppModel(store: SettingsStore(config: try Sandbox().config))
        let visit = WelcomeVisit()
        visit.page = page
        let view = NSHostingView(rootView: WelcomeView(model: model, visit: visit, close: {}))
        view.appearance = NSAppearance(named: appearance)
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.width == 560 && view.fittingSize.height > 300)
    }

    /// docs/security.md opens with the last page's three lines, word for word.
    @Test func theLastPageSaysWhatSecurityMDSays() throws {
        let doc = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../docs/security.md")
        let text = try String(contentsOf: doc, encoding: .utf8)
        let section = try #require(text.range(of: "## If something goes wrong\n\n").map { text[$0.upperBound...] })
        let lines = section.components(separatedBy: "\n\n").first
        #expect(lines == [WelcomeView.guardLine, WelcomeView.wayOutLine, WelcomeView.unlockOnlyLine].map { "- \($0)" }.joined(separator: "\n"))
    }

    /// The line under Lock Now never promises Touch ID to a Mac or a setting that does not offer it.
    @MainActor @Test func theUnlockLineNamesOnlyWhatWorks() {
        #expect(WelcomeView.unlockLine(touchID: true) == "Unlock with Touch ID or your password.")
        #expect(WelcomeView.unlockLine(touchID: false) == "Unlock with your password.")
    }

    /// "Lock automatically" says what is stored, in Settings' words; with nothing stored, what turning it on stores.
    @MainActor @Test(arguments: [
        (AutoLockSettings(idleMinutes: 5, systemSleep: true), "After 5 minutes of inactivity and when the Mac sleeps."),
        (AutoLockSettings(idleMinutes: 15, systemSleep: true, screenSaver: true),
         "After 15 minutes of inactivity, when the screen saver starts or the display turns off, and when the Mac sleeps."),
        (AutoLockSettings(systemSleep: true), "When the Mac sleeps."),
        (AutoLockSettings(displaySleep: true), "When the screen saver starts or the display turns off."),
        (AutoLockSettings(), "After 5 minutes of inactivity and when the Mac sleeps."),
        (AutoLockSettings(idleMinutes: 1), "After 1 minute of inactivity."),
    ] as [(AutoLockSettings, String)])
    func theAutoLockLineSaysWhatIsStored(_ triggers: AutoLockSettings, _ line: String) {
        #expect(WelcomeView.autoLockSummary(triggers) == line)
    }

    /// Off then on brings back a stricter setup, not the default, and keeps auto_lock's other keys. On leaves a trigger
    /// set elsewhere alone.
    @MainActor @Test func theAutoLockSwitchRestoresWhatItTurnedOff() {
        var settings = Settings(["auto_lock": .table(["idle_minutes": .int(15), "screen_saver": .bool(true), "system_sleep": .bool(true),
                                                      "later": .string("kept")])])
        var turnedOff: AutoLockSettings?
        WelcomeView.setAutoLock(false, in: &settings, turnedOff: &turnedOff)
        #expect(settings["auto_lock"] == .table(["later": .string("kept")]))
        WelcomeView.setAutoLock(true, in: &settings, turnedOff: &turnedOff)
        #expect(settings["auto_lock"] == .table(["idle_minutes": .int(15), "screen_saver": .bool(true), "system_sleep": .bool(true),
                                                 "later": .string("kept")]))
        var elsewhere = Settings(["auto_lock": .table(["system_sleep": .bool(true)])])
        WelcomeView.setAutoLock(true, in: &elsewhere, turnedOff: &turnedOff)
        #expect(elsewhere["auto_lock"] == .table(["system_sleep": .bool(true)]))
    }

    /// An edit elsewhere cleared auto_lock while the switch still showed on: off remembers nothing, so on stores the default.
    @MainActor @Test func theAutoLockSwitchTurnsOnAfterAnEditElsewhereClearedIt() {
        var settings = Settings()
        var turnedOff: AutoLockSettings?
        WelcomeView.setAutoLock(false, in: &settings, turnedOff: &turnedOff)
        #expect(turnedOff == nil)
        WelcomeView.setAutoLock(true, in: &settings, turnedOff: &turnedOff)
        #expect(settings.autoLock == WelcomeView.defaultAutoLock)
    }

    private let record = #"{"theme": "broken", "fallback": "default", "message": "themes/broken.lua:3: boom", "date": 1000}"#

    @Test func aThemeFailureReadsAsDataOrAsAString() throws {
        let store = Defaults()
        #expect(ThemeFailure.read(store.defaults) == nil)
        store.defaults.set(Data(record.utf8), forKey: ThemeFailure.key)
        let expected = ThemeFailure(theme: "broken", fallback: "default", message: "themes/broken.lua:3: boom", date: 1000)
        #expect(ThemeFailure.read(store.defaults) == expected)
        store.defaults.set(record, forKey: ThemeFailure.key)
        #expect(ThemeFailure.read(store.defaults) == expected)
        store.defaults.set(#"{"theme": "broken"}"#, forKey: ThemeFailure.key)
        #expect(ThemeFailure.read(store.defaults) == nil)
    }

    @Test func aThemeFailureNamesTheThemes() {
        var inspection = Inspection()
        inspection.themes = [Inspection.ThemeInfo(id: "tokyonight", name: "Tokyo Night"), Inspection.ThemeInfo(id: "default", name: "Aurora")]
        let failure = ThemeFailure(theme: "tokyonight", fallback: "default", message: "", date: 0)
        #expect(failure.summary(inspection) == "Tokyo Night failed to load on the last lock; Locky showed Aurora")
        #expect(ThemeFailure(theme: "gone", fallback: "default", message: "", date: 0).summary(inspection)
            == "gone failed to load on the last lock; Locky showed Aurora")
    }

    /// A change to the theme's files or to init.lua after the failure may have fixed it; settings.json does not count.
    @Test func aThemeFailureGoesStaleWhenTheThemeChanges() throws {
        let sandbox = try Sandbox()
        let store = Defaults()
        try sandbox.write("themes/broken.lua", "return {")
        try sandbox.write("init.lua", "")
        try sandbox.write("settings.json", "{}")
        func touch(_ relative: String, _ seconds: Double) throws {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)],
                                                  ofItemAtPath: sandbox.config.appending(path: relative).path)
        }
        for file in ["themes/broken.lua", "init.lua"] { try touch(file, 500) }
        try touch("settings.json", 2000)
        store.defaults.set(record, forKey: ThemeFailure.key)
        #expect(ThemeFailure.current(store.defaults, inspection: Inspection(), config: sandbox.config)?.theme == "broken")

        try touch("themes/broken.lua", 1500)
        #expect(ThemeFailure.current(store.defaults, inspection: Inspection(), config: sandbox.config) == nil)
        try touch("themes/broken.lua", 500)
        try touch("init.lua", 1500)
        #expect(ThemeFailure.current(store.defaults, inspection: Inspection(), config: sandbox.config) == nil)
    }
}
