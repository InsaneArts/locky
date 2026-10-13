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
        try sandbox.write("init.lua", "locky.setup({ theme = 'from-init', message = 'from init', privacy = false })")
        try Settings(["theme": .string("from-settings"), "privacy": .bool(true)]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        let config = try config(runtime)
        #expect(config["theme"] == .string("from-settings"))
        #expect(config["privacy"] == .bool(true))
        // A key settings.json leaves out keeps init.lua's value.
        #expect(config["message"] == .string("from init"))
    }

    /// A module init.lua requires may read the user's name as it loads: privacy must be on by then.
    @Test func codeInitLuaRunsSeesSettingsPrivacy() throws {
        let sandbox = try Sandbox()
        try sandbox.write("settings.json", #"{ "privacy": true }"#)
        try sandbox.write("lua/mymod.lua", "return { user = locky.sys.user().name, host = locky.sys.hostname().name }")
        try sandbox.write("init.lua", "MOD = require('mymod')")
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        #expect(try runtime.eval("return MOD.user, MOD.host") == [.string("user"), .string("Mac")])
    }

    @Test func settingsWinOverPluginScripts() throws {
        let sandbox = try Sandbox()
        try sandbox.write("settings.json", #"{ "theme": "from-settings" }"#)
        try sandbox.write("plugin/setup.lua", "locky.setup({ theme = 'from-plugin', message = 'from the plugin' })")
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        let config = try config(runtime)
        #expect(config["theme"] == .string("from-settings"))
        #expect(config["message"] == .string("from the plugin"))
    }

    @Test func setupChecksItsTypes() throws {
        for (option, expected) in [
            ("theme = 5", "opts.theme: expected string, got number"), ("hour24 = 1", "opts.hour24: expected boolean, got number"), ("privacy = 'yes'", "opts.privacy: expected boolean, got string"),
            ("message = {}", "opts.message: expected string, got table"), ("background = 'x'", "opts.background: expected table, got string"),
            ("palette = 5", "opts.palette: expected table, got number"), ("widgets = true", "opts.widgets: expected table, got boolean"),
        ] {
            let sandbox = try Sandbox()
            try sandbox.write("init.lua", "locky.setup({ \(option) })")
            let problems = runtime(sandbox).bootForTest()
            #expect(problems.count == 1 && problems[0].contains("init.lua:1: \(expected)"), "\(problems)")
        }
    }

    /// auto_unlock is gone: a config that sets it, with any value, still loads, and hears so once.
    @Test func autoUnlockIsReportedOnceAndIgnored() async throws {
        for (initLua, settings) in [("locky.setup({ auto_unlock = 30 })", "{}"), ("locky.setup({ auto_unlock = '60' })", #"{ "auto_unlock": 0 }"#),
                                    ("", #"{ "auto_unlock": 60 }"#)] {
            let sandbox = try Sandbox()
            try sandbox.write("init.lua", initLua)
            try sandbox.write("settings.json", settings)
            let runtime = runtime(sandbox)
            let started = await runtime.start(theme: "default")
            runtime.stop()
            #expect(started.problems == [LuaRuntime.autoUnlockRemoved], "\(initLua) \(settings)")
        }
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ theme = 'default' })")
        #expect(runtime(sandbox).bootForTest().isEmpty)
    }

    /// Lua and the host read privacy and hour24 alike: only true turns privacy on, and only true or false forces
    /// the clock. Values set around locky.setup cannot hide names in widgets but not in the password field.
    @Test func privacyAndHour24ReadTheSameInLuaAndTheHost() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.config.privacy = 1 locky.config.hour24 = 1")
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        let config = try config(runtime)
        #expect(config["privacy"] == .bool(false))
        #expect(config["hour24"] == .nil)
        let time = "os.time({ year = 2026, month = 1, day = 2, hour = 17, min = 5 })"
        let lua = try runtime.eval("return locky.sys.user().name, locky.date.format('time', \(time)), locky.date.locale().hour24")
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 17, minute: 5)))
        #expect(lua == [.string(NSUserName()), .string(SystemInfo.format(date, "time")), SystemInfo.locale()["hour24"]])
    }

    /// A function in hour24 failed config(), and the lock lost the message and privacy with it.
    @Test func anOddHour24CostsNothingElse() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ message = 'hi', privacy = true }) locky.config.hour24 = function() end")
        let runtime = runtime(sandbox)
        let started = await runtime.start(theme: "default")
        runtime.stop()
        #expect(started.message == "hi")
        #expect(started.privacy)
        #expect(started.hour24 == nil)
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
        #expect(try loadTheme(runtime)["edited"] == .bool(true))
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

    /// settings.json is the last layer for widget options too, over init.lua's locky.setup({ widgets = ... }).
    @Test func settingsOptionsWinOverInitLuas() throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { widgets = { { 'two', opts = { size = 20, font = 'theme' } } } }")
        try sandbox.write("plugin/w.lua", "locky.widget.define('two', { opts = { size = 1 }, init = function(self) OPTS = self.opts end, render = function() end })")
        try sandbox.write("init.lua", "locky.setup({ widgets = { two = { size = 99, color = 'red' } } })")
        try Settings(["themes": .table(["t": .table(["widgets": .array([
            .table(["ref": .int(1), "widget": .string("two"), "opts": .table(["size": .int(50)])]),
        ])])])]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        _ = try loadTheme(runtime)
        let id = try runtime.sync { try runtime.call("create", [.int(1)], budget: 1) }.first ?? .nil
        _ = try runtime.sync { try runtime.call("init", [id], budget: 1) }
        #expect(try runtime.eval("return OPTS.size, OPTS.color, OPTS.font") == [.int(50), .string("red"), .string("theme")])
    }

    /// Saved when the theme had { one, two, one }: entry 1 was placement 3, now gone, and entry 2 is placement 1,
    /// still there. A stale ref looks for its widget by name only among placements no exact ref names.
    @Test func anExactRefKeepsItsPlacement() throws {
        let sandbox = try themeSandbox()
        try Settings(["themes": .table(["t": .table(["widgets": .array([
            .table(["ref": .int(3), "widget": .string("one"), "anchor": .string("bottom-right")]),
            .table(["ref": .int(1), "widget": .string("one"), "anchor": .string("top-left")]),
            .table(["ref": .int(5), "widget": .string("two"), "anchor": .string("bottom")]),
        ])])])]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        let widgets = try loadTheme(runtime)["widgets"].array ?? []
        #expect(widgets.map { $0["widget"] } == [.string("one"), .string("two")])
        #expect(widgets.map { $0["anchor"] } == [.string("top-left"), .string("bottom")])
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
        #expect(theme["edited"] == .bool(false))
    }

    /// Every field is checked, so a bad one never reaches the theme, where it failed the whole theme.
    @Test(arguments: [
        (#"{ "widgets": [ { "ref": 2, "widget": "two", "offset": [10] } ] }"#, ".widgets[1].offset"),
        (#"{ "widgets": [ { "widget": "three", "size": "big" } ] }"#, ".widgets[1].size"),
        (#"{ "widgets": [ { "widget": "three", "card": "fancy" } ] }"#, ".widgets[1].card"),
        (#"{ "widgets": [ { "widget": "three", "align": 5 } ] }"#, ".widgets[1].align"),
        (#"{ "widgets": [ { "widget": "three", "display": "every" } ] }"#, ".widgets[1].display"),
        (#"{ "widgets": [ { "ref": "2", "widget": "two" } ] }"#, ".widgets[1].ref"),
        (#"{ "widgets": { "a": { "widget": "three" } } }"#, ".widgets"),
        ("5", ""),
        (#"{ "background": { "blur": "soft" } }"#, ".background.blur"),
        (##"{ "background": { "gradient": ["#000000", 5] } }"##, ".background.gradient"),
        (#"{ "auth": 5 }"#, ".auth"),
        (#"{ "auth": { "anchor": "middle" } }"#, ".auth.anchor"),
        (#"{ "auth": { "offset": [1] } }"#, ".auth.offset"),
    ])
    func aBadFieldIsReportedAndTheThemeLoadsWithoutTheEdit(edit: String, field: String) async throws {
        let sandbox = try themeSandbox()
        try sandbox.write("settings.json", #"{ "themes": { "t": \#(edit) } }"#)
        let runtime = runtime(sandbox)
        let started = await runtime.start(theme: "t")
        runtime.stop()
        #expect(started.theme.id == "t")
        #expect(started.theme.widgets.map(\.widget) == ["one", "two"])
        #expect(started.theme.background == .color("#111111"))
        #expect(started.problems.contains { $0.hasPrefix("settings.json themes.t\(field):") }, "\(started.problems)")
    }

    /// A file the edit names and that is not there fails only on the Swift side; the theme loads without the edit.
    @Test(arguments: [#"{ "shader": "nope" }"#, #"{ "image": "nope.jpg" }"#])
    func aMissingFileIsReportedAndTheThemeLoadsWithoutTheEdit(background: String) async throws {
        let sandbox = try themeSandbox()
        try sandbox.write("settings.json", #"{ "themes": { "t": { "background": \#(background), "widgets": [ { "widget": "three" } ] } } }"#)
        let runtime = runtime(sandbox)
        let started = await runtime.start(theme: "t")
        runtime.stop()
        #expect(started.theme.id == "t")
        #expect(started.theme.background == .color("#111111"))
        #expect(started.theme.widgets.map(\.widget) == ["one", "two"])
        #expect(started.problems.count == 1)
        #expect(started.problems.first?.hasPrefix("settings.json themes.t: background: no ") == true, "\(started.problems)")
    }

    @Test func theDefaultThemeSurvivesABadEdit() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("settings.json", #"{ "themes": { "default": { "widgets": [ { "widget": "clock", "size": "big" } ] } } }"#)
        let runtime = runtime(sandbox)
        let started = await runtime.start(theme: nil)
        runtime.stop()
        // Not the bare fallback, which has no clock.
        #expect(started.theme.id == "default")
        #expect(started.theme.widgets.contains { $0.widget == "clock" })
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

    @Test func settingsMoveThePasswordField() async throws {
        let sandbox = try themeSandbox()
        try sandbox.write("settings.json", #"{ "themes": { "t": { "auth": { "anchor": "top-left", "offset": [40, 50] } } } }"#)
        let runtime = runtime(sandbox)
        let started = await runtime.start(theme: "t")
        runtime.stop()
        #expect(started.problems.isEmpty, "\(started.problems)")
        #expect(started.theme.auth.anchor == .topLeft)
        #expect(started.theme.auth.offset == CGPoint(x: 40, y: 50))
        // Only the place changes; the rest of the field is the theme's.
        #expect(started.theme.auth.style == "pill")
    }

    /// The theme editor's preview tells a changed widget from an unchanged one by the options it gets.
    @Test func eachPlacementCarriesTheOptionsItsInstanceGets() async throws {
        let sandbox = try themeSandbox()
        try sandbox.write("init.lua", "locky.setup({ widgets = { two = { color = 'red' } } })")
        try Settings(["themes": .table(["t": .table(["widgets": .array([
            .table(["ref": .int(2), "widget": .string("two"), "opts": .table(["size": .int(50)])]),
        ])])])]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        let started = await runtime.start(theme: "t")
        runtime.stop()
        #expect(started.theme.widgets.first?.options == .table(["size": .int(50), "color": .string("red")]))
    }

    /// What the editor shows for a placement: its options before settings.json's, and the field's own place.
    @Test func theLayoutHasOptionsBeforeSettingsAndThePasswordFieldsPlace() throws {
        let sandbox = try themeSandbox()
        try sandbox.write("init.lua", "locky.setup({ widgets = { two = { color = 'red' } } })")
        try Settings(["themes": .table(["t": .table([
            "widgets": .array([.table(["ref": .int(2), "widget": .string("two"), "opts": .table(["size": .int(50)])])]),
            "auth": .table(["anchor": .string("top")]),
        ])])]).save(config: sandbox.config)
        let runtime = runtime(sandbox)
        _ = runtime.bootForTest()
        let layout = try runtime.sync { try runtime.call("theme_layout", [.string("t")], budget: 1) }.first ?? .nil
        #expect(layout["widgets"][1]["opts"] == .table(["size": .int(20), "color": .string("red")]))
        #expect(layout["auth"]["anchor"] == .string("bottom"))
        #expect(layout["auth"]["offset"] == .array([.int(0), .int(-60)]))
        #expect(layout["card_style"] == .string("glass"))
    }

    @Test func theCatalogHasEachWidgetsOptionsAndChoices() throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/w.lua", """
        locky.widget.define("w", { opts = { style = "list", size = 12 }, choices = { style = { "list", "dots" } }, render = function() end })
        """)
        try sandbox.write("init.lua", "locky.setup({ widgets = { w = { size = 14 } } })")
        let runtime = runtime(sandbox)
        #expect(runtime.bootForTest().isEmpty)
        let catalog = try runtime.sync { try runtime.call("widget_catalog", budget: 1) }.first?.array ?? []
        let w = try #require(catalog.first { $0["name"] == .string("w") })
        #expect(w["opts"] == .table(["style": .string("list"), "size": .int(14)]))
        // Without init.lua's: what kind of value each option takes.
        #expect(w["defaults"] == .table(["style": .string("list"), "size": .int(12)]))
        #expect(w["choices"]["style"] == .array([.string("list"), .string("dots")]))
    }

    @Test func choicesMustBeListsOfStrings() throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/w.lua", "locky.widget.define('w', { choices = { style = 'list' }, render = function() end })")
        let problems = runtime(sandbox).bootForTest()
        #expect(problems.first?.contains("spec.choices: expected lists of strings by option") == true, "\(problems)")
    }

    /// The window reads these lists with try?, so one theme or widget that failed them emptied the whole page.
    @Test func oneOddThemeOrWidgetSpoilsOnlyItsOwnRow() throws {
        let sandbox = try themeSandbox()
        try sandbox.write("themes/cycle.lua", "local p = { accent = '#ff0000' } p.self = p return { palette = p }")
        try sandbox.write("themes/keys.lua", "return { palette = { [true] = '#ffffff', [0] = '#000000', [2.5] = 'x', accent = '#00ff00' } }")
        try sandbox.write("themes/odd.lua", "return { name = { 'not text' }, author = 5, dir = function() end }")
        try sandbox.write("themes/broken.lua", "error(setmetatable({}, { __tostring = function() error('worse') end }))")
        try sandbox.write("plugin/z.lua", "local d = {} d[1] = d locky.widget.define('z', { description = d, render = function() end })")
        let runtime = runtime(sandbox)
        _ = runtime.bootForTest()
        let infos = try runtime.sync { try runtime.call("theme_infos", budget: 5) }.first?.array ?? []
        func info(_ id: String) -> LuaValue { infos.first { $0["id"] == .string(id) } ?? .nil }
        #expect(info("t")["error"] == .nil && info("default")["name"] == .string("Aurora"))
        #expect(info("cycle")["palette"]["accent"] == .string("#ff0000"))
        #expect(info("keys")["palette"]["accent"] == .string("#00ff00"))
        #expect(info("odd")["name"] == .string("odd") && info("odd")["author"] == .nil && info("odd")["dir"] == .nil)
        #expect(info("broken")["error"] == .string("(error object is a table value)"))

        let catalog = try runtime.sync { try runtime.call("widget_catalog", budget: 1) }.first?.array ?? []
        #expect(catalog.contains { $0["name"] == .string("z") && $0["description"] == .nil })
        #expect(catalog.contains { $0["name"] == .string("three") && $0["description"] == .string("widget three") })
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

    @Test func aTypoAtLaunchKeepsTheLastGoodSettings() throws {
        let sandbox = try Sandbox()
        let lastGood = sandbox.root.appending(path: "support/last-good.json")
        let good = Settings(["auto_lock": .table(["idle_minutes": .int(5)]), "emergency_exit": .bool(false)])
        try good.save(config: sandbox.config)
        _ = SettingsStore(config: sandbox.config, lastGood: lastGood)
        // A hand edit loses a comma; then the Mac restarts.
        try sandbox.write("settings.json", #"{ "emergency_exit": false "auto_lock": {} }"#)
        let relaunched = SettingsStore(config: sandbox.config, lastGood: lastGood)
        #expect(relaunched.problem != nil)
        #expect(relaunched.settings == good)
        // Restoring writes those settings back, the broken file moved aside.
        try relaunched.resetBrokenFile()
        #expect(Settings.load(config: sandbox.config).settings == good)
        #expect(relaunched.problem == nil)
    }

    @Test func aSaveThroughASymlinkKeepsAnEditNoEventReported() throws {
        let sandbox = try Sandbox()
        let target = sandbox.root.appending(path: "dotfiles/locky/settings.json")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{ "theme": "glass" }"#.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: Settings.url(config: sandbox.config), withDestinationURL: target)
        let store = SettingsStore(config: sandbox.config)
        // A git pull in the dotfiles changes the target; the config folder sees nothing.
        try #"{ "theme": "glass", "emergency_exit": false }"#.write(to: target, atomically: true, encoding: .utf8)
        store.update { $0["privacy"] = .bool(true) }
        let saved = Settings.load(file: target).settings
        #expect(saved["emergency_exit"] == .bool(false))
        #expect(saved["privacy"] == .bool(true))
        #expect(store.settings == saved)
        // A broken target is never written over.
        try "{ broken".write(to: target, atomically: true, encoding: .utf8)
        store.update { $0["privacy"] = .bool(false) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "{ broken")
        #expect(store.problem != nil)
    }

    @Test func aLinkToAMissingFileIsAProblemAndKeepsTheLastGoodSettings() throws {
        let sandbox = try Sandbox()
        let lastGood = sandbox.root.appending(path: "support/last-good.json")
        let good = Settings(["theme": .string("glass"), "privacy": .bool(true)])
        try good.save(config: sandbox.config)
        _ = SettingsStore(config: sandbox.config, lastGood: lastGood)
        // The dotfiles volume is not mounted at login: settings.json links to nothing.
        try FileManager.default.removeItem(at: Settings.url(config: sandbox.config))
        try FileManager.default.createSymbolicLink(at: Settings.url(config: sandbox.config),
                                                   withDestinationURL: sandbox.root.appending(path: "Volumes/dotfiles/settings.json"))
        let store = SettingsStore(config: sandbox.config, lastGood: lastGood)
        #expect(store.problem?.contains("not there") == true)
        #expect(store.settings == good)
        #expect(Settings.load(file: lastGood).settings == good)
        // A change waits for the link to work again, and the link stays.
        store.update { $0["theme"] = .string("mocha") }
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: Settings.url(config: sandbox.config).path)) != nil)
    }

    @Test func restoringKeepsASymlinkedFileLinked() throws {
        let sandbox = try Sandbox()
        let target = sandbox.root.appending(path: "dotfiles/settings.json")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{ "theme": "glass" }"#.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: Settings.url(config: sandbox.config), withDestinationURL: target)
        let store = SettingsStore(config: sandbox.config)
        try "{ broken".write(to: target, atomically: true, encoding: .utf8)
        store.reload()
        #expect(store.problem != nil)
        try store.resetBrokenFile()
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: Settings.url(config: sandbox.config).path) == target.path)
        #expect(Settings.load(file: target).settings["theme"] == .string("glass"))
    }

    @Test func aSaveThatWouldPassOneMegabyteIsRefused() throws {
        let sandbox = try Sandbox()
        let store = SettingsStore(config: sandbox.config)
        store.update { $0["theme"] = .string("glass") }
        store.update { $0["message"] = .string(String(repeating: "x", count: 1_100_000)) }
        #expect(store.problem?.contains("1 MB") == true)
        #expect(Settings.load(config: sandbox.config).settings["theme"] == .string("glass"))
        #expect(store.settings["theme"] == .string("glass"))
    }

    @Test func theStoresOwnSaveReportsOneChange() throws {
        let sandbox = try Sandbox()
        let store = SettingsStore(config: sandbox.config)
        var changes = 0
        store.onChange = { changes += 1 }
        // A whole number as a double comes back as an integer.
        store.update { $0["display_off"] = .double(60) }
        store.reload()
        #expect(changes == 1)
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

@Suite struct ThemeScheduleTests {
    private func date(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: hour, minute: minute))!
    }

    @Test func dayAndNightFollowTheClock() throws {
        let schedule = try #require(ThemeSchedule(settings: .table([
            "mode": .string("time"), "day": .string("glass"), "night": .string("default"),
            "day_starts": .string("07:00"), "night_starts": .string("19:30"),
        ])))
        #expect(schedule.theme(at: date(6, 59), dark: false) == "default")
        #expect(schedule.theme(at: date(7, 0), dark: true) == "glass")
        #expect(schedule.theme(at: date(19, 29), dark: false) == "glass")
        #expect(schedule.theme(at: date(19, 30), dark: false) == "default")
        #expect(schedule.theme(at: date(0, 0), dark: false) == "default")
    }

    @Test func aDayThatCrossesMidnightWorks() throws {
        // A night-shift schedule: "day" from 22:00 to 06:00.
        var schedule = ThemeSchedule(mode: .time)
        schedule.day = "phosphor"
        schedule.night = "mocha"
        schedule.dayStarts = 22 * 60
        schedule.nightStarts = 6 * 60
        #expect(schedule.theme(at: date(23, 0), dark: false) == "phosphor")
        #expect(schedule.theme(at: date(3, 0), dark: false) == "phosphor")
        #expect(schedule.theme(at: date(12, 0), dark: false) == "mocha")
    }

    @Test func lightAndDarkFollowTheAppearance() throws {
        var settings = Settings()
        var schedule = ThemeSchedule(mode: .appearance)
        schedule.light = "station"
        schedule.dark = "synthwave"
        settings.schedule = schedule
        // A round trip through settings.json.
        #expect(settings.schedule == schedule)
        #expect(settings.schedule?.theme(at: Date(), dark: true) == "synthwave")
        #expect(settings.schedule?.theme(at: Date(), dark: false) == "station")
        // A slot with no theme leaves the choice to the rest of the settings.
        schedule.light = nil
        #expect(schedule.theme(at: Date(), dark: false) == nil)
    }

    @Test func badValuesMeanNoSchedule() {
        #expect(ThemeSchedule(settings: .nil) == nil)
        #expect(ThemeSchedule(settings: .table(["mode": .string("moon")])) == nil)
        #expect(ThemeSchedule.minutes("25:00") == nil)
        #expect(ThemeSchedule.minutes("7:05") == 425)
        #expect(ThemeSchedule.clock(425) == "07:05")
    }
}

@Suite struct SettingsOrderFollowUpTests {
    @Test func pluginScriptsSeeSettingsPrivacyOverInitLuas() throws {
        let sandbox = try Sandbox()
        try sandbox.write("settings.json", #"{ "privacy": true }"#)
        try sandbox.write("init.lua", "locky.setup({ privacy = false })")
        try sandbox.write("plugin/p.lua", "NAME = locky.sys.user().name")
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        #expect(runtime.bootForTest().isEmpty)
        #expect(try runtime.eval("return NAME") == [.string("user")])
        runtime.stop()
    }

    @Test func aCoreFailureKeepsPrivacyAndTheMessage() async throws {
        let sandbox = try Sandbox()
        // A module of the user's that shadows the core's and fails stops the core from starting.
        try sandbox.write("lua/locky/ui.lua", "error('shadowed')")
        let settings = Settings(["privacy": .bool(true), "message": .string("If found, call 555")])
        let runtime = LuaRuntime(path: sandbox.path(), settings: settings, delegate: Recorder().delegate)
        let started = await runtime.start(theme: nil)
        runtime.stop()
        #expect(started.problems.first?.contains("core failed") == true)
        #expect(started.privacy)
        #expect(started.message == "If found, call 555")
    }

    @Test func aPaletteThatRefersToItselfManyTimesStillLists() throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { name = 'T' }")
        try sandbox.write("themes/cycle3.lua", "local p = { accent = '#ff0000' } p.a = p p.b = p p.c = p return { palette = p }")
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        _ = runtime.bootForTest()
        let list = try runtime.sync { try runtime.call("theme_infos", budget: 2) }.first?.array ?? []
        runtime.stop()
        #expect(list.contains { $0["id"] == .string("t") })
        #expect(list.first { $0["id"] == .string("cycle3") }?["palette"]["accent"] == .string("#ff0000"))
    }
}
