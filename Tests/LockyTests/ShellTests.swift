import AppKit
import Carbon
import Foundation
import Testing
@testable import Locky

/// The windows' shared API: what the Themes, Settings, and Welcome windows, the menus, and the command line call.
@MainActor
@Suite struct ShellTests {
    /// Polls `condition` on the main actor, where the model lives.
    private func wait(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        return condition()
    }

    // MARK: Windows

    @Test(arguments: [("dashboard", .themes), ("widgets", .themes), ("themes", .themes), ("settings", .settings), ("plugins", .plugins),
                      ("config", .config), ("welcome", .welcome), ("nope", nil)] as [(String, AppModel.Section?)])
    func aWindowArgumentNamesAWindowOrAPane(_ argument: String, _ section: AppModel.Section?) {
        #expect(AppModel.Section(argument: argument) == section)
    }

    @Test func theSettingsWindowOpensOnGeneral() {
        #expect(AppModel.Section.settings.title == "General")
        #expect(AppModel.Section.panes == [.settings, .plugins, .config])
    }

    @Test func windowWithoutASectionOpensTheThemesWindow() {
        #expect(CLI.GUILaunch.parse(["window"]).window == .themes)
        let widgets = CLI.GUILaunch.parse(["window", "widgets"])
        #expect(widgets.window == .themes && widgets.opensWidgetGallery)
        #expect(!CLI.GUILaunch.parse(["window", "themes"]).opensWidgetGallery)
        #expect(CLI.GUILaunch.parse(["window", "config"]).window == .config)
        #expect(CLI.GUILaunch.parse(["preview"]).window == nil)
    }

    @Test func aRequestedSizeKeepsTheMinimum() {
        #expect(LockyWindowController.clamped(CGSize(width: 600, height: 400)) == CGSize(width: 980, height: 640))
        #expect(LockyWindowController.clamped(CGSize(width: 1600, height: 1000)) == CGSize(width: 1600, height: 1000))
    }

    @Test func doneEndsCustomizeAndWhatItHadOpen() throws {
        let model = AppModel(store: SettingsStore(config: try Sandbox().config))
        model.customize("glass")
        #expect(model.editingTheme == "glass")
        model.addingWidget = true
        model.editorRequest = .export
        model.finishEditing()
        #expect(model.editingTheme == nil && !model.addingWidget && model.editorRequest == nil)
    }

    /// `Locky window widgets` at launch: the theme in use is init.lua's, which only the first read of the config knows.
    @Test func customizingTheThemeInUseWaitsForTheConfig() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ theme = 'matrix' })")
        _ = NSApplication.shared
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        model.refresh()
        model.customizeInUse(addingWidget: true)
        #expect(model.editingTheme == nil)
        #expect(await wait { model.inspection.loaded })
        #expect(model.editingTheme == "matrix" && model.addingWidget)
    }

    // MARK: Themes

    /// A model of a sandbox whose config has been read.
    private func loaded(_ sandbox: Sandbox) async -> AppModel {
        _ = NSApplication.shared
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        model.refresh()
        _ = await wait { model.inspection.loaded }
        return model
    }

    /// Choosing init.lua's own theme is its own reset.
    @Test func usingAThemeStoresItUnlessInitLuaGivesIt() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ theme = 'matrix' })")
        let model = await loaded(sandbox)
        #expect(model.activeTheme == "matrix")
        model.use("glass")
        #expect(model.store.settings["theme"] == .string("glass") && model.activeTheme == "glass")
        model.use("matrix")
        #expect(model.store.settings["theme"].isNil && model.activeTheme == "matrix")
    }

    @Test func underAScheduleTheSlotThatShowsNowChanges() async throws {
        let sandbox = try Sandbox()
        let model = await loaded(sandbox)
        var schedule = ThemeSchedule(mode: .time)
        schedule.day = "glass"
        schedule.night = "matrix"
        model.store.update { $0.schedule = schedule }
        let other = schedule.theme(at: .now, dark: false) == "glass" ? "matrix" : "glass"
        model.use("poster")
        let changed = try #require(model.store.settings.schedule)
        #expect(changed.theme(at: .now, dark: false) == "poster" && Set([changed.day, changed.night]) == ["poster", other])
        #expect(model.store.settings["theme"].isNil && model.activeTheme == "poster")
        // A schedule with nothing for now leaves the choice to settings.json's theme.
        model.store.update { $0.schedule = ThemeSchedule(mode: .appearance) }
        model.use("poster")
        #expect(model.store.settings["theme"] == .string("poster"))
        #expect(model.store.settings.schedule?.light == nil && model.store.settings.schedule?.dark == nil)
    }

    @Test func onlyYourOwnThemeGoesToTheTrash() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/mine.lua", "return { name = 'Mine' }")
        let model = await loaded(sandbox)
        #expect(model.canTrash("mine") && !model.canTrash("default"))
        var schedule = ThemeSchedule(mode: .time)
        schedule.day = "mine"
        schedule.night = "matrix"
        model.store.update { settings in
            settings["theme"] = .string("mine")
            settings.schedule = schedule
            settings.setThemeEdit("mine", "background", .table(["color": .string("#000000")]))
        }
        model.customize("mine")
        try model.trash("mine", using: { try FileManager.default.removeItem(at: $0) })
        #expect(!FileManager.default.fileExists(atPath: sandbox.config.appending(path: "themes/mine.lua").path))
        let settings = model.store.settings
        #expect(settings["theme"].isNil && settings.schedule?.day == nil && settings.schedule?.night == "matrix")
        // Put Back in the Finder brings the theme back with its changes.
        #expect(!settings["themes"]["mine"].isNil)
        #expect(model.editingTheme == nil)
    }

    @Test func anInstalledThemeTakesAFreeID() async throws {
        let sandbox = try Sandbox()
        let model = await loaded(sandbox)
        let file = ThemeFile(base: "tokyonight", name: "Tokyo Night Copy", edits: [])
        #expect(try await model.install(file) == "tokyo-night-copy")
        #expect(try await model.install(file) == "tokyo-night-copy-2")
        #expect(FileManager.default.fileExists(atPath: sandbox.config.appending(path: "themes/tokyo-night-copy-2.lua").path))
    }

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

    // MARK: Inspection

    @Test func themesListByTheirNames() {
        var inspection = Inspection()
        inspection.themes = [Inspection.ThemeInfo(id: "wordclock", name: "Word Clock"), Inspection.ThemeInfo(id: "default", name: "Aurora"),
                             Inspection.ThemeInfo(id: "deepblue", name: "Deep Blue")]
        #expect(inspection.themesByName.map(\.id) == ["default", "deepblue", "wordclock"])
    }

    /// Locky's own widgets name no source: only someone else's do.
    @Test func aWidgetSaysWhereItComesFrom() {
        func source(_ file: URL) -> String? { Inspection.WidgetInfo(name: "w", file: file).source }
        #expect(source(RuntimePath.builtInRuntime.appending(path: "plugin/clock.lua")) == nil)
        #expect(source(RuntimePath.resources.appending(path: "packages/sakura/plugin/sakura.lua")) == nil)
        #expect(source(RuntimePath.defaultConfig.appending(path: "plugin/mine.lua")) == "Lua Config")
        #expect(source(RuntimePath.defaultPacks.appending(path: "locky-weather/plugin/big.lua")) == "locky-weather")
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

    @Test func aFailedThemeNamesItselfInTheMenu() {
        var inspection = Inspection()
        inspection.themes = [Inspection.ThemeInfo(id: "tokyonight", name: "Tokyo Night")]
        #expect(ThemeFailure(theme: "tokyonight", fallback: "default", message: "", date: 0).menuTitle(inspection) == "Tokyo Night Didn't Load")
        #expect(ThemeFailure(theme: "gone", fallback: "default", message: "", date: 0).menuTitle(inspection) == "gone Didn't Load")
    }
}
