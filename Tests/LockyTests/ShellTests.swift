import AppKit
import Carbon
import Foundation
import Testing
@testable import Locky

/// The windows' shared API: what the Themes, Settings, and Welcome windows, the menus, and the command line call.
@MainActor
@Suite struct ShellTests {
    /// Light content takes the dark press overlay, as the lock window's appearance does.
    @Test(arguments: [("#F1EFE8", true), ("#02040a", false), (nil, false)] as [(String?, Bool)])
    func aColorIsLightByTheLockWindowsRule(_ hex: String?, _ light: Bool) {
        #expect(Design.isLight(hex) == light)
    }

    // MARK: The schedule and settings.json

    /// A time of day on a calendar of its own, so no test depends on the Mac's time zone.
    private func at(_ hour: Int) -> (date: Date, calendar: Calendar) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return (calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: hour))!, calendar)
    }

    /// The default day runs from 07:00 to 19:00.
    @Test func aThemeGoesToTheSlotThatShowsNow() {
        let (morning, calendar) = at(10)
        let (evening, _) = at(22)
        var schedule = ThemeSchedule(mode: .time)
        schedule.setTheme("glass", at: morning, dark: true, calendar: calendar)
        schedule.setTheme("matrix", at: evening, dark: false, calendar: calendar)
        #expect(schedule.day == "glass" && schedule.night == "matrix" && schedule.light == nil && schedule.dark == nil)
        schedule.mode = .appearance
        schedule.setTheme("poster", at: morning, dark: false, calendar: calendar)
        schedule.setTheme("tokyonight", at: morning, dark: true, calendar: calendar)
        #expect(schedule.light == "poster" && schedule.dark == "tokyonight" && schedule.day == "glass" && schedule.night == "matrix")
    }

    @Test func forgettingAThemeEmptiesEverySlotThatNamesIt() {
        var schedule = ThemeSchedule(mode: .time)
        schedule.day = "mine"
        schedule.night = "matrix"
        schedule.light = "mine"
        schedule.dark = "mine"
        schedule.forget("mine")
        #expect(schedule.day == nil && schedule.night == "matrix" && schedule.light == nil && schedule.dark == nil)
    }

    @Test func theScheduleSaysWhichThemeShowsWhen() {
        var inspection = Inspection()
        inspection.themes = [Inspection.ThemeInfo(id: "default", name: "Aurora"), Inspection.ThemeInfo(id: "matrix", name: "Matrix")]
        var schedule = ThemeSchedule(mode: .time)
        schedule.day = "default"
        schedule.night = "matrix"
        #expect(schedule.summary(inspection) == "Day: Aurora from 07:00 · Night: Matrix from 19:00")
        schedule.mode = .appearance
        schedule.light = "default"
        #expect(schedule.summary(inspection) == "Light: Aurora · Dark: the usual theme")
    }

    @Test func aValueInitLuaAlreadyGivesIsNoKey() {
        var settings = Settings()
        settings.setLuaValue("theme", .string("glass"), base: .string("default"))
        #expect(settings["theme"] == .string("glass"))
        settings.setLuaValue("theme", .string("default"), base: .string("default"))
        #expect(settings["theme"].isNil)
    }

    /// A newer Locky's key in auto_lock outlives a change made here.
    @Test func theTriggersChangeInPlace() {
        var settings = Settings(["auto_lock": .table(["later": .string("kept")])])
        settings.setAutoLock(AutoLockSettings(idleMinutes: 5, systemSleep: true))
        #expect(settings["auto_lock"] == .table(["later": .string("kept"), "idle_minutes": .int(5), "system_sleep": .bool(true)]))
        settings.setAutoLock(AutoLockSettings())
        #expect(settings["auto_lock"] == .table(["later": .string("kept")]))
        // With no other key, all off removes auto_lock.
        var plain = Settings(["auto_lock": .table(["display_sleep": .bool(true)])])
        plain.setAutoLock(AutoLockSettings())
        #expect(plain["auto_lock"].isNil)
    }

    // MARK: Problems

    /// "$CONFIG" and "$PACKS" stand for a sandbox's folders, where the files are.
    @Test(arguments: [
        ("$CONFIG/init.lua:3: attempt to call a nil value (global 'boom')", "$CONFIG/init.lua", 3, "Attempt to call a nil value (global 'boom')"),
        // Lua shortens a long chunk name from the front.
        ("...ocky/init.lua:7: unexpected symbol near '}'", "$CONFIG/init.lua", 7, "Unexpected symbol near '}'"),
        ("~/.config/locky/settings.json is not valid JSON: no value", nil, nil, "~/.config/locky/settings.json is not valid JSON: no value"),
        ("$PACKS/locky-weather/plugin/weather.lua:12: bad argument #1 to 'format'", "$PACKS/locky-weather/plugin/weather.lua", 12,
         "Bad argument #1 to 'format'"),
    ] as [(String, String?, Int?, String)])
    func aProblemNamesItsFileAndLine(_ problem: String, _ file: String?, _ line: Int?, _ message: String) throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "")
        let plugin = sandbox.packs.appending(path: "locky-weather/plugin/weather.lua")
        try FileManager.default.createDirectory(at: plugin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: plugin)
        func real(_ text: String) -> String {
            text.replacingOccurrences(of: "$CONFIG", with: sandbox.config.path).replacingOccurrences(of: "$PACKS", with: sandbox.packs.path)
        }
        let found = ConfigProblem(real(problem), config: sandbox.config)
        #expect(found.message == message)
        #expect(found.file?.path == file.map(real))
        #expect(found.line == line)
    }

    // MARK: Menus

    @Test func aShortcutIsAMenuKeyEquivalent() {
        let lockNow = Shortcut(keyCode: UInt16(kVK_ANSI_L), modifiers: [.control, .option, .command])
        #expect(lockNow.menuKeyEquivalent?.key == "l")
        #expect(lockNow.menuKeyEquivalent?.modifiers == [.control, .option, .command])
        #expect(Shortcut(keyCode: UInt16(kVK_F5), modifiers: []).menuKeyEquivalent?.key == "\u{F708}")
        // A menu cannot show Space.
        #expect(Shortcut(keyCode: UInt16(kVK_Space), modifiers: [.command]).menuKeyEquivalent == nil)
    }
}
