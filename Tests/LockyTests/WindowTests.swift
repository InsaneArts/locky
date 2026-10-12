import AppKit
import Foundation
import Testing
@testable import Locky

@Suite struct WindowTests {
    @Test func aPlacementSurvivesTheTripThroughSettings() {
        let entry: LuaValue = .table([
            "ref": .int(2), "widget": .string("clock"), "anchor": .string("top-left"),
            "offset": .array([.int(12), .double(-3.5)]), "card": .bool(false),
            "size": .array([.int(100), .int(40)]), "opts": .table(["size": .int(30)]),
        ])
        let placement = EditorPlacement(entry: entry)
        #expect(placement.ref == 2 && placement.anchor == "top-left" && placement.x == 12 && placement.y == -3.5 && placement.card == false)
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
        let inspection = await Inspection.load(config: sandbox.config)
        #expect(inspection.loaded)
        #expect(inspection.theme("mine")?.name == "Mine")
        #expect(inspection.theme("mine")?.palette["bg"] == "#123456")
        #expect(inspection.theme("broken")?.error?.contains("expected table") == true)
        #expect(inspection.widget("w")?.card == true)
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
        #expect(SettingsPage.duration(1e300) == "Off")
        #expect(SettingsPage.duration(90) == "90 s")
        let placement = EditorPlacement(entry: .table(["widget": .string("clock"), "offset": .array([.double(.infinity), .double(-1e12)])]))
        #expect(placement.x == 0 && placement.y == -100_000)
        // And it saves as JSON can hold it.
        #expect((try? placement.settingsValue.jsonObject()) != nil)
    }
}

@Suite struct ReviewFollowUpTests {
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
