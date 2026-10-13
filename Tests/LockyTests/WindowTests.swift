import AppKit
import Foundation
import Testing
@testable import Locky

@Suite struct WindowTests {
    @Test func widgetsGroupByWhereTheyComeFrom() {
        func widget(_ name: String, _ file: URL) -> Inspection.WidgetInfo { Inspection.WidgetInfo(name: name, file: file) }
        let packages = RuntimePath.resources.appending(path: "packages")
        let groups = WidgetGroup.groups([
            widget("sakura.month", packages.appending(path: "sakura/plugin/sakura.lua")),
            widget("clock", RuntimePath.builtInRuntime.appending(path: "plugin/clock.lua")),
            widget("weather.big", RuntimePath.defaultPacks.appending(path: "locky-weather/plugin/big.lua")),
            widget("matrix.whisper", packages.appending(path: "matrix/plugin/matrix.lua")),
            widget("mine", RuntimePath.defaultConfig.appending(path: "plugin/mine.lua")),
        ])
        #expect(groups.map(\.title) == ["Locky", "Your Config", "Installed", "Matrix Theme", "Sakura Theme"])
        #expect(groups.map { $0.widgets.map(\.name) } == [["clock"], ["mine"], ["weather.big"], ["matrix.whisper"], ["sakura.month"]])
    }

    /// The gallery runs every widget in one runtime, once in each of its families, and hands each card the live
    /// view of the family it shows.
    @MainActor @Test func theGalleryDrawsEachWidget() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/fam.lua", """
            locky.widget.define('fam', { families = { 'circular', 'small' }, render = function(self) return locky.ui.text(self.family) end })
            """)
        let gallery = WidgetGallery()
        let widgets = [Inspection.WidgetInfo(name: "date"), Inspection.WidgetInfo(name: "nerdclock"),
                       Inspection.WidgetInfo(name: "fam", families: ["circular", "small"]), Inspection.WidgetInfo(name: "no.such.widget")]
        gallery.start(widgets: widgets, settings: Settings(), config: sandbox.config, revision: 1)
        defer { gallery.stop() }
        func node(_ name: String, _ family: String? = nil) -> Node? { if case .node(let node, _) = gallery.shown(name, family: family) { node } else { nil } }
        let deadline = Date().addingTimeInterval(5)
        while [node("date"), node("nerdclock"), node("fam", "circular"), node("fam", "small")].contains(where: { $0 == nil }), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(node("date") != nil && node("nerdclock") != nil)
        #expect(node("fam", "circular")?.kind == .text("circular") && node("fam", "small")?.kind == .text("small"))
        if case .failed = gallery.shown("no.such.widget") {} else { Issue.record("an unknown widget should show as failed") }
    }

    @Test func aPlacementSurvivesTheTripThroughSettings() {
        let entry: LuaValue = .table([
            "ref": .int(2), "widget": .string("clock"), "anchor": .string("top-left"),
            "offset": .array([.int(12), .double(-3.5)]), "card": .bool(false),
            "size": .array([.int(100), .int(40)]), "opts": .table(["size": .int(30)]),
        ])
        let placement = EditorPlacement(entry: entry)
        #expect(placement.ref == 2 && placement.anchor == "top-left" && placement.x == 12 && placement.y == -3.5 && placement.card == .bool(false))
        // Fields the editor does not show are kept.
        #expect(placement.settingsValue == entry)
    }

    @Test func theThemesOwnPlacementBecomesARef() {
        let original: LuaValue = .table(["widget": .string("date"), "anchor": .string("top"), "offset": .array([.int(0), .int(100)]),
                                         "size": .array([.int(5), .int(5)])])
        let placement = EditorPlacement(original: original, ref: 1)
        let saved = placement.settingsValue
        #expect(saved["ref"] == .int(1))
        // Lua copies the rest from the theme's placement, so the editor does not write it.
        #expect(saved["size"] == .nil)
        #expect(saved["card"] == .nil)
    }

    /// A card style stays the style: written back as true, it would put the widget on the theme's default card.
    @Test func aCardStyleSurvivesAnEdit() {
        var placement = EditorPlacement(entry: .table(["widget": .string("clock"), "card": .string("outline")]))
        placement.x = 40
        #expect(placement.settingsValue["card"] == .string("outline"))
        #expect(EditorPlacement.isCard(.string("outline")) == true && EditorPlacement.isCard(.string("none")) == false)
        // The theme's own placement leaves the card to the theme.
        let original = EditorPlacement(original: .table(["widget": .string("clock"), "card": .string("outline")]), ref: 1)
        #expect(original.settingsValue["card"] == .nil)
    }

    @Test func themeEditsLeaveNoEmptyTables() {
        var settings = Settings()
        settings.setThemeEdit("glass", "background", .table(["color": .string("#000000")]))
        settings.setThemeEdit("glass", "widgets", .array([]))
        #expect(settings.themeEdit("glass", "background")["color"] == .string("#000000"))
        settings.setThemeEdit("glass", "background", nil)
        settings.setThemeEdit("glass", "widgets", nil)
        #expect(settings["themes"].isNil)
    }

    @Test func installSourcesAreCheckedLikeLockyPackAdd() {
        #expect(PackSpec.problem(source: "someone/locky-weather") == nil)
        #expect(PackSpec.problem(source: "https://github.com/someone/locky-weather.git") == nil)
        #expect(PackSpec.problem(source: "git@github.com:someone/x.git") == nil)
        #expect(PackSpec.problem(source: "") != nil)
        #expect(PackSpec.problem(source: "--upload-pack=evil") != nil)
        #expect(PackSpec.problem(source: "some one/x") != nil)
        #expect(PackSpec.problem(source: "just-a-name") != nil)
        #expect(PackSpec.name(of: .string("https://github.com/someone/locky-weather.git")) == "locky-weather")
        #expect(PackSpec.name(of: .table(["src": .string("a/b"), "name": .string("custom")])) == "custom")
    }

    @Test func theWindowReadsThemesWidgetsPackagesAndBothConfigs() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ theme = 'mine', privacy = true })")
        try sandbox.write("themes/mine.lua", "return { name = 'Mine', description = 'My theme', palette = { bg = '#123456' } }")
        try sandbox.write("themes/broken.lua", "return 5")
        try sandbox.write("plugin/w.lua", "locky.widget.define('w', { card = true, render = function() end })")
        try Settings(["privacy": .bool(false), "packs": .array([.string("someone/locky-weather")])]).save(config: sandbox.config)
        let inspection = await Inspection.load(config: sandbox.config, settings: Settings.load(config: sandbox.config).settings)
        #expect(inspection.loaded)
        #expect(inspection.theme("mine")?.name == "Mine")
        #expect(inspection.theme("mine")?.palette["bg"] == "#123456")
        #expect(inspection.theme("broken")?.error?.contains("expected table") == true)
        #expect(inspection.widget("w")?.card == true)
        // What the editor offers for a core widget's options.
        #expect(inspection.widget("battery")?.choices["style"] == ["row", "compact", "ring"])
        #expect(inspection.widget("clock")?.opts["size"] == .int(180))
        // settings.json wins in config; base is what init.lua says.
        #expect(inspection.config["privacy"] == .bool(false))
        #expect(inspection.base["privacy"] == .bool(true))
        let pack = try #require(inspection.packs.first)
        #expect(pack.name == "locky-weather" && pack.fromSettings && !pack.installed)
    }
}

@Suite struct OddNumberTests {
    /// init.lua's auto_unlock = math.huge, a theme's offset = { math.huge, 0 }: the window once trapped on them.
    @Test func numbersThatAreNotFiniteShowAndSaveSafely() {
        #expect(SettingsPage.duration(.infinity) == "Off")
        #expect(SettingsPage.duration(.nan) == "Off")
        // Over a day is a day, as the runtime clamps it.
        #expect(SettingsPage.duration(1e300) == "1440 min")
        #expect(SettingsPage.duration(100_000) == "1440 min")
        #expect(SettingsPage.duration(90) == "90 s")
        let placement = EditorPlacement(entry: .table(["widget": .string("clock"), "offset": .array([.double(.infinity), .double(-1e12)])]))
        #expect(placement.x == 0 && placement.y == -100_000)
        // And it saves as JSON can hold it.
        #expect((try? placement.settingsValue.jsonObject()) != nil)
    }
}

@Suite struct ReviewFollowUpTests {
    @Test func aPackageNameMatchesLuas() {
        #expect(PackSpec.name(of: .string("someone/locky.github-stars")) == "locky.github-stars")
        #expect(PackSpec.name(of: .string("https://example.com/x/theme.git")) == "theme")
        #expect(PackSpec.name(of: .table(["dir": .string("~/code/my-plugin")])) == "my-plugin")
        // A folder keeps ".git" in its name, as Lua names it.
        #expect(PackSpec.name(of: .table(["dir": .string("~/code/theme.git")])) == "theme.git")
    }

    @Test func switchingTheScheduleModeKeepsTheOtherModesThemes() {
        var schedule = ThemeSchedule(mode: .time)
        schedule.day = "glass"
        schedule.night = "default"
        schedule.dayStarts = 6 * 60 + 30
        schedule.mode = .appearance
        schedule.light = "station"
        let back = ThemeSchedule(settings: schedule.settingsValue)
        #expect(back?.day == "glass" && back?.night == "default" && back?.dayStarts == 390 && back?.light == "station")
    }

    @MainActor
    @Test func aLongMessageStaysOnScreenNextToAFieldAtTheEdge() {
        let screen = LockScreenView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var spec = Theme.Auth()
        spec.anchor = .bottomLeft
        spec.offset = CGPoint(x: 40, y: -40)
        screen.auth = (NSView(), spec)
        screen.authSize = CGSize(width: 240, height: 80)
        screen.layout()
        let frame = screen.messageFrame(size: CGSize(width: 600, height: 18), scale: 1)
        #expect(frame.minX >= 16 && frame.maxX <= 1440 - 16)
    }
}

@Suite struct InstanceLockTests {
    /// Another process holds the lock (a child, as a second Locky would): this one does not get it, and gets it
    /// once that process ends.
    @Test func onlyOneProcessHoldsTheLock() async throws {
        let sandbox = try Sandbox()
        let file = sandbox.root.appending(path: "instance.lock")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let holder = Process()
        holder.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        holder.arguments = ["-e", "use Fcntl ':flock'; open(F, '<', $ARGV[0]) or die; flock(F, LOCK_EX) or die; print \"held\\n\"; $| = 1; sleep 30",
                            file.path]
        let output = Pipe()
        holder.standardOutput = output
        try holder.run()
        defer { holder.terminate() }
        _ = output.fileHandleForReading.availableData  // "held"
        #expect(!InstanceLock.acquire(file))
        holder.terminate()
        holder.waitUntilExit()
        #expect(InstanceLock.acquire(file))
    }
}

/// A click on a widget card on the Widgets page adds the widget to a theme.
@MainActor
@Suite struct AddToThemeTests {
    @Test func addingWritesThePlacementAndShowsTheTheme() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { widgets = { { 'clock', anchor = 'top' } } }")
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        let index = await AddToTheme.add("date", to: Inspection.ThemeInfo(id: "t", name: "T"), model: model)
        #expect(index == 1)
        let widgets = model.store.settings.themeEdit("t", "widgets").array ?? []
        #expect(widgets.map { $0["widget"] } == [.string("clock"), .string("date")])
        #expect(widgets.first?["ref"] == .int(1))
        #expect(model.selectedTheme == "t")
        #expect(model.section == .themes)
        // The settings file says the same.
        #expect(Settings.load(config: sandbox.config).settings.themeEdit("t", "widgets") == model.store.settings.themeEdit("t", "widgets"))
    }

    @Test func aThemeThatDoesNotLoadIsLeftAlone() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "error('broken')")
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        #expect(await AddToTheme.add("date", to: Inspection.ThemeInfo(id: "t", name: "T"), model: model) == nil)
        #expect(model.store.settings.themeEdit("t", "widgets").isNil)
        #expect(model.section == .dashboard)
    }
}
