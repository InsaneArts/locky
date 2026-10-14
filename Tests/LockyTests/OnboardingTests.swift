import Foundation
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

    /// `locky window welcome` (and window-shot.sh) opens it; the Lua Config pane keeps "config" for them.
    @MainActor @Test func theWelcomeOpensFromTheCommandLine() {
        #expect(CLI.GUILaunch.parse(["window", "welcome"]).window == .welcome)
        #expect(AppModel.Section.config.title == "Lua Config" && AppModel.Section(rawValue: "config") == .config)
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
