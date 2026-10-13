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
