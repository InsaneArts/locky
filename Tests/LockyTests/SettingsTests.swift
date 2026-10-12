import AppKit
import Foundation
import Testing
@testable import Locky

@Suite struct SettingsTests {
    private func runtime(_ sandbox: Sandbox) -> LuaRuntime {
        LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
    }

    private func config(_ runtime: LuaRuntime) throws -> LuaValue {
        try runtime.sync { try runtime.call("config", budget: 1) }.first ?? .nil
    }

    @Test func settingsWinOverInitLuaKeyByKey() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ theme = 'from-init', auto_unlock = 30, privacy = false })")
        try Settings(["theme": .string("from-settings"), "privacy": .bool(true)]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        let config = try config(runtime)
        #expect(config["theme"] == .string("from-settings"))
        #expect(config["privacy"] == .bool(true))
        // A key settings.json leaves out keeps init.lua's value.
        #expect(config["auto_unlock"] == .int(30))
    }

    @Test func valuesOfTheWrongTypeAreSkippedAndReported() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ theme = 'from-init' })")
        try sandbox.write("settings.json", #"{ "theme": 5, "hour24": true }"#)
        let runtime = runtime(sandbox)
        let problems = runtime.bootForTest()
        #expect(problems == ["settings.json theme: expected a string, got number"])
        let config = try config(runtime)
        #expect(config["theme"] == .string("from-init"))
        #expect(config["hour24"] == .bool(true))
    }

    @Test func aBrokenFileIsAProblemNotEmptySettingsToOverwrite() throws {
        let sandbox = try Sandbox()
        try sandbox.write("settings.json", "{ \"theme\": ")
        let (settings, problem) = Settings.load(config: sandbox.config)
        #expect(settings == Settings())
        #expect(problem?.contains("not valid JSON") == true)
        #expect(runtime(sandbox).bootForTest().first?.contains("settings.json is not valid JSON") == true)

        try sandbox.write("settings.json", "[1, 2]")
        #expect(Settings.load(config: sandbox.config).problem?.contains("JSON object") == true)
        // No file is no problem.
        try FileManager.default.removeItem(at: Settings.url(config: sandbox.config))
        #expect(Settings.load(config: sandbox.config).problem == nil)
    }

    @Test func savingKeepsKeysThisVersionDoesNotKnow() throws {
        let sandbox = try Sandbox()
        try sandbox.write("settings.json", #"{ "from_the_future": { "a": [1, 2.5, "x"] }, "theme": "old" }"#)
        var settings = Settings.load(config: sandbox.config).settings
        settings["theme"] = .string("new")
        try settings.save(config: sandbox.config)
        let saved = Settings.load(config: sandbox.config).settings
        #expect(saved["from_the_future"]["a"] == .array([.int(1), .double(2.5), .string("x")]))
        #expect(saved["theme"] == .string("new"))
        // Setting nil removes the key.
        settings["theme"] = .nil
        try settings.save(config: sandbox.config)
        #expect(Settings.load(config: sandbox.config).settings.values.keys.sorted() == ["from_the_future"])
    }

    @Test func aSymlinkedFileKeepsItsLink() throws {
        let sandbox = try Sandbox()
        let dotfiles = sandbox.root.appending(path: "dotfiles/settings.json")
        try FileManager.default.createDirectory(at: dotfiles.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: dotfiles, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: Settings.url(config: sandbox.config), withDestinationURL: dotfiles)
        try Settings(["theme": .string("linked")]).save(config: sandbox.config)
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: Settings.url(config: sandbox.config).path)
        #expect(link == dotfiles.path)
        #expect(try String(contentsOf: dotfiles, encoding: .utf8).contains("linked"))
    }

    @Test func packagesFromSettingsLoadBeforeInitLuaRequiresThem() throws {
        let sandbox = try Sandbox()
        let package = sandbox.root.appending(path: "my-plugin")
        try FileManager.default.createDirectory(at: package.appending(path: "lua"), withIntermediateDirectories: true)
        try "return { hello = 'from the plugin' }".write(to: package.appending(path: "lua/myplugin.lua"), atomically: true, encoding: .utf8)
        try Settings(["packs": .array([.table(["dir": .string(package.path)])])]).save(config: sandbox.config)
        // init.lua adds the same package too; settings.json's comes first, and that is not an error.
        try sandbox.write("init.lua", """
        locky.pack.add({ { dir = "\(package.path)" } })
        locky.setup({ message = require("myplugin").hello })
        """)
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        #expect(try config(runtime)["message"] == .string("from the plugin"))
        let specs = try runtime.sync { try runtime.call("pack_specs", budget: 1) }.first?.array ?? []
        #expect(specs.count == 1)
        #expect(specs.first?["from"] == .string("settings"))
        #expect(specs.first?["in_config"] == .bool(true))
    }

    @Test func aBadPackageEntryIsReportedAndTheOthersStillLoad() throws {
        let sandbox = try Sandbox()
        try Settings(["packs": .array([.int(5), .string("someone/locky-weather")])]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        let problems = runtime.bootForTest()
        #expect(problems.count == 1)
        #expect(problems.first == "settings.json packs: [1] spec: expected table, got number")
        let specs = try runtime.sync { try runtime.call("pack_specs", budget: 1) }.first?.array ?? []
        #expect(specs.map { $0["name"] } == [.string("locky-weather")])
    }

    // MARK: Theme changes

    private func themeSandbox() throws -> Sandbox {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", """
        return {
          background = { color = "#111111" },
          widgets = {
            { "one", anchor = "top", opts = { size = 10 } },
            { "two", anchor = "left", offset = { 5, 6 }, opts = { size = 20 } },
          },
        }
        """)
        try sandbox.write("plugin/widgets.lua", """
        for _, name in ipairs({ "one", "two", "three" }) do
          locky.widget.define(name, { description = "widget " .. name, render = function() return locky.ui.text(name) end })
        end
        """)
        return sandbox
    }

    private func loadTheme(_ runtime: LuaRuntime) throws -> LuaValue {
        try runtime.sync { try runtime.call("load_theme", [.string("t")], budget: 1) }.first ?? .nil
    }

    @Test func settingsReplaceAThemesBackgroundOverInitLuas() throws {
        let sandbox = try themeSandbox()
        try sandbox.write("init.lua", "locky.setup({ background = { color = '#00ff00' } })")
        let runtime1 = runtime(sandbox)
        _ = runtime1.bootForTest()
        #expect(try loadTheme(runtime1)["background"]["color"] == .string("#00ff00"))

        try Settings(["themes": .table(["t": .table(["background": .table(["wallpaper": .bool(true), "blur": .int(12)])])])])
            .save(config: sandbox.config)
        let runtime2 = runtime(sandbox)
        _ = runtime2.bootForTest()
        let background = try loadTheme(runtime2)["background"]
        #expect(background["wallpaper"] == .bool(true))
        #expect(background["blur"] == .int(12))
        #expect(background["color"] == .nil)
    }

    @Test func widgetEditsKeepTheThemesOptionsAndAddNewWidgets() throws {
        let sandbox = try themeSandbox()
        try Settings(["themes": .table(["t": .table(["widgets": .array([
            .table(["ref": .int(2), "widget": .string("two"), "anchor": .string("bottom"), "offset": .array([.int(1), .int(2)])]),
            .table(["widget": .string("three"), "anchor": .string("top-right"), "card": .bool(true)]),
        ])])])]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        let widgets = try loadTheme(runtime)["widgets"].array ?? []
        #expect(widgets.map { $0["widget"] } == [.string("two"), .string("three")])
        #expect(widgets[0]["anchor"] == .string("bottom"))
        #expect(widgets[0]["offset"] == .array([.int(1), .int(2)]))
        #expect(widgets[1]["card"] == .bool(true))
        // "two" keeps the options the theme gave it.
        #expect(try runtime.eval("return locky.theme.current.widgets[1].opts.size") == [.int(20)])
    }

    @Test func aRefFindsItsWidgetAfterTheThemeReorders() throws {
        let sandbox = try themeSandbox()
        // Saved when "two" was the first placement; the theme has since put "one" first.
        try Settings(["themes": .table(["t": .table(["widgets": .array([
            .table(["ref": .int(1), "widget": .string("two"), "anchor": .string("center")]),
            .table(["ref": .int(3), "widget": .string("gone"), "anchor": .string("center")]),
        ])])])]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        let widgets = try loadTheme(runtime)["widgets"].array ?? []
        #expect(widgets.map { $0["widget"] } == [.string("two")])
        #expect(try runtime.eval("return locky.theme.current.widgets[1].opts.size") == [.int(20)])
    }

    @Test func aBadEditIsReportedAndTheThemeLoadsWithoutIt() throws {
        let sandbox = try themeSandbox()
        try Settings(["themes": .table(["t": .table([
            "background": .table(["color": .string("#ff0000")]),
            "widgets": .array([.table(["widget": .string("one"), "anchor": .string("middle")])]),
        ])])]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        _ = runtime.bootForTest()
        let theme = try loadTheme(runtime)
        #expect(theme["problems"][0].string?.contains("widgets[1].anchor") == true)
        // Nothing of the edit applies, the background included.
        #expect(theme["background"]["color"] == .string("#111111"))
        #expect(theme["widgets"].array?.map { $0["widget"] } == [.string("one"), .string("two")])
    }

    @Test func falseSurvivesTheTripToTheWindow() throws {
        let sandbox = try themeSandbox()
        try sandbox.write("themes/f.lua", "return { widgets = { { 'one', card = false } } }")
        let runtime = runtime(sandbox)
        _ = runtime.bootForTest()
        let layout = try runtime.sync { try runtime.call("theme_layout", [.string("f")], budget: 1) }.first ?? .nil
        #expect(layout["widgets"][0]["card"] == .bool(false))
    }

    @Test func themeLayoutIgnoresTheWindowsChanges() throws {
        let sandbox = try themeSandbox()
        try Settings(["themes": .table(["t": .table(["widgets": .array([])])])]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        _ = runtime.bootForTest()
        #expect(try loadTheme(runtime)["widgets"].array?.isEmpty == true)
        let layout = try runtime.sync { try runtime.call("theme_layout", [.string("t")], budget: 1) }.first ?? .nil
        #expect(layout["widgets"].array?.map { $0["widget"] } == [.string("one"), .string("two")])
        #expect(layout["widgets"][1]["offset"] == .array([.int(5), .int(6)]))
        #expect(layout["background"]["color"] == .string("#111111"))
    }

    @Test func theWidgetCatalogNamesEachWidgetsFile() throws {
        let sandbox = try themeSandbox()
        let runtime = runtime(sandbox)
        _ = runtime.bootForTest()
        let catalog = try runtime.sync { try runtime.call("widget_catalog", budget: 1) }.first?.array ?? []
        let three = try #require(catalog.first { $0["name"] == .string("three") })
        #expect(three["description"] == .string("widget three"))
        #expect(three["file"].string?.hasSuffix("config/plugin/widgets.lua") == true)
        // The core widgets are there too.
        #expect(catalog.contains { $0["name"] == .string("clock") })
    }
}

@Suite struct HourFormatTests {
    @Test func settingsForceA24Or12HourClock() throws {
        for (hour24, expected) in [(true, "17:05"), (false, "5:05")] {
            let sandbox = try Sandbox()
            try Settings(["hour24": .bool(hour24)]).save(config: sandbox.config)
            let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
            #expect(runtime.bootForTest().isEmpty)
            let time = "os.time({ year = 2026, month = 1, day = 2, hour = 17, min = 5 })"
            #expect(try runtime.eval("return locky.date.format('time', \(time))") == [.string(expected)])
            #expect(try runtime.eval("return locky.date.locale().hour24") == [.bool(hour24)])
            // A pattern is used as it is: the override is only for "time".
            #expect(try runtime.eval("return locky.date.format('HH', \(time))") == [.string("17")])

            let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 17, minute: 5)))
            #expect(SystemInfo.format(date, "time", hour24: hour24) == expected)
        }
    }

    @Test func withoutTheSettingTheSystemDecides() throws {
        let sandbox = try Sandbox()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        _ = runtime.bootForTest()
        let system = SystemInfo.locale()["hour24"]
        #expect(try runtime.eval("return locky.date.locale().hour24") == [system])
    }
}

@Suite struct PrivacyTests {
    private func runtime(privacy: Bool) throws -> (LuaRuntime, Sandbox) {
        let sandbox = try Sandbox()
        try Settings(["privacy": .bool(privacy)]).save(config: sandbox.config)
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        #expect(runtime.bootForTest().isEmpty)
        return (runtime, sandbox)
    }

    @Test func privacyModeGivesGenericNames() throws {
        let (runtime, _) = try runtime(privacy: true)
        #expect(try runtime.eval("local u = locky.sys.user() return u.name, u.full_name") == [.string("user"), .string("")])
        #expect(try runtime.eval("local h = locky.sys.hostname() return h.name, h.host") == [.string("Mac"), .string("mac")])
        let (open, _) = try self.runtime(privacy: false)
        #expect(try open.eval("return locky.sys.user().name") == [.string(NSUserName())])
    }

    @Test func privacyModeHidesAgentTitlesAndWorkspaces() throws {
        let (runtime, _) = try runtime(privacy: true)
        let source = "return require('locky.herdr').parse([==[\(HerdrModuleTests.snapshot)]==])"
        let agents = try runtime.eval(source).first?["agents"].array ?? []
        #expect(agents.map { $0["title"].string } == ["Codex", "Claude", "Claude", "Pi"])
        #expect(agents.allSatisfy { $0["workspace"] == .string("") })
        // Counts stay: they say nothing about the work.
        #expect(try runtime.eval(source + ".need") == [.int(2)])
    }

    @Test func theGreetingLeavesTheNameOut() throws {
        let (runtime, _) = try runtime(privacy: true)
        let text = try runtime.eval("""
            local definition = locky.widget.get("greeting")
            local view = definition.render({ opts = definition.opts, state = { hour = 20 } })
            return view.text
            """)
        #expect(text == [.string("Good evening.")])
    }

    @Test func thePasswordFieldShowsNoName() {
        let user = Auth.user(privacy: true)
        #expect(user.name.isEmpty && user.login == "user" && user.host == "mac" && user.picture == nil)
        #expect(Auth.user(privacy: false).login == NSUserName())
    }
}

@MainActor
@Suite struct LockMessageTests {
    private func screen(authAnchor: Anchor, offset: CGPoint) -> LockScreenView {
        let screen = LockScreenView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var spec = Theme.Auth()
        spec.anchor = authAnchor
        spec.offset = offset
        screen.auth = (NSView(), spec)
        screen.authSize = CGSize(width: 240, height: 120)
        screen.layout()
        return screen
    }

    @Test func theMessageSitsUnderTheFieldWhenThereIsRoom() throws {
        let screen = screen(authAnchor: .center, offset: .zero)
        let auth = try #require(screen.auth?.view.frame)
        let frame = screen.messageFrame(size: CGSize(width: 300, height: 20), scale: 1)
        #expect(frame.minY == auth.maxY + 14)
        #expect(frame.midX == auth.midX)
    }

    @Test func aFieldAtTheBottomEdgeGetsTheMessageAboveIt() throws {
        let screen = screen(authAnchor: .bottom, offset: CGPoint(x: 0, y: -20))
        let auth = try #require(screen.auth?.view.frame)
        let frame = screen.messageFrame(size: CGSize(width: 300, height: 20), scale: 1)
        #expect(frame.maxY == auth.minY - 14)
    }

    @Test func settingsCarryTheMessageToTheLockScreen() async throws {
        let sandbox = try Sandbox()
        try Settings(["message": .string("  If found, call 555-0100  ")]).save(config: sandbox.config)
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        let started = await runtime.start(theme: "default")
        runtime.stop()
        #expect(started.message == "If found, call 555-0100")
    }
}

@MainActor
@Suite struct SettingsStoreTests {
    @Test func changesSaveAtOnce() throws {
        let sandbox = try Sandbox()
        let store = SettingsStore(config: sandbox.config)
        var changes = 0
        store.onChange = { changes += 1 }
        store.update { $0["theme"] = .string("mocha") }
        #expect(Settings.load(config: sandbox.config).settings["theme"] == .string("mocha"))
        store.update { $0["theme"] = .string("mocha") }  // no change, no save
        #expect(changes == 1)
    }

    @Test func aBrokenFileIsNeverOverwritten() throws {
        let sandbox = try Sandbox()
        try sandbox.write("settings.json", "{ broken")
        let store = SettingsStore(config: sandbox.config)
        #expect(store.problem != nil)
        store.update { $0["theme"] = .string("mocha") }
        #expect(try String(contentsOf: Settings.url(config: sandbox.config), encoding: .utf8) == "{ broken")
        // Reset moves it aside and starts empty.
        try store.resetBrokenFile()
        #expect(store.problem == nil)
        let aside = try FileManager.default.contentsOfDirectory(atPath: sandbox.config.path).filter { $0.hasPrefix("settings.json.broken-") }
        #expect(aside.count == 1)
        store.update { $0["theme"] = .string("mocha") }
        #expect(Settings.load(config: sandbox.config).settings["theme"] == .string("mocha"))
    }

    @Test func theMenusOldThemeChoiceMovesIn() throws {
        let sandbox = try Sandbox()
        let defaults = try #require(UserDefaults(suiteName: "locky-tests-\(UUID().uuidString)"))
        defaults.set("wordclock", forKey: "theme")
        let store = SettingsStore(config: sandbox.config)
        store.migrateMenuTheme(defaults)
        #expect(store.settings["theme"] == .string("wordclock"))
        #expect(defaults.string(forKey: "theme") == nil)
    }

    @Test func anEditInAnotherEditorShowsUp() async throws {
        let sandbox = try Sandbox()
        let store = SettingsStore(config: sandbox.config)
        store.watch()
        // An in-place write, as some editors save.
        let url = Settings.url(config: sandbox.config)
        FileManager.default.createFile(atPath: url.path, contents: Data(#"{ "theme": "glass" }"#.utf8))
        var seen = false
        for _ in 0..<250 where !seen {
            try await Task.sleep(for: .milliseconds(20))
            seen = store.settings["theme"] == .string("glass")
        }
        #expect(seen)
    }
}
