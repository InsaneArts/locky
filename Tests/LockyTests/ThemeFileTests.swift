import Foundation
import Testing
@testable import Locky

@Suite struct ThemeFileTests {
    private let edit: LuaValue = .table([
        "background": .table(["color": .string("#203040")]),
        "widgets": .array([.table(["ref": .int(2), "widget": .string("clock"), "anchor": .string("center"),
                                   "offset": .array([.int(0), .int(0)]), "opts": .table(["size": .int(90)])])]),
        "auth": .table(["anchor": .string("top"), "offset": .array([.int(0), .int(40)])]),
    ])

    @Test func aFileReadsBackAsItWasWritten() throws {
        let file = ThemeFile(base: "default", name: "Night ]] Lake ]=] \"quoted\"", edits: [edit])
        let text = try file.source()
        #expect(ThemeFile.parse(text) == file)
        // The name's brackets do not end the long string.
        #expect(text.contains("[==[") && text.contains("]==]))"))
    }

    @Test func onlyWhatTheWindowWritesReads() throws {
        let text = try ThemeFile(base: "default", name: "Lake", edits: [edit]).source()
        // Code anywhere, another function, or a base that could break out of its string: none read.
        #expect(ThemeFile.parse(text + "os.execute('touch /tmp/x')\n") == nil)
        #expect(ThemeFile.parse("os.execute('x')\n" + text) == nil)
        #expect(ThemeFile.parse("--[[\n--]] os.execute('x') --\n" + text) != nil, "comments before the return are allowed")
        #expect(ThemeFile.parse(text.replacingOccurrences(of: "locky.theme.derive", with: "locky.theme.extend")) == nil)
        #expect(ThemeFile.parse(text.replacingOccurrences(of: "\"default\"", with: "\"de\" .. x .. \"fault\"")) == nil)
        #expect(ThemeFile.parse(text.replacingOccurrences(of: "\"name\" : \"Lake\"", with: "\"name\" : \"Two\\nlines\"")) == nil)
        #expect(ThemeFile.parse(text.replacingOccurrences(of: "\"edits\" : [", with: "\"edits\" : [ 1, ")) == nil)
        #expect(ThemeFile.parse(String(repeating: "-- x\n", count: 300_000) + text) == nil)
    }

    @Test func aNewThemeGetsAnIdOfItsOwn() {
        #expect(ThemeFile.id(for: "My Night Lake!", taken: []) == "my-night-lake")
        #expect(ThemeFile.id(for: "Aurora", taken: ["aurora", "aurora-2"]) == "aurora-3")
        #expect(ThemeFile.id(for: "日本", taken: []) == "theme")
        #expect(ThemeFile.id(for: "../../x", taken: []) == "x")
    }

    @Test func aCopyOfAMadeThemeStartsFromItsBase() throws {
        let sandbox = try Sandbox()
        let first = ThemeFile(base: "default", name: "Lake", edits: [edit])
        try sandbox.write("themes/lake.lua", try first.source())
        let more: LuaValue = .table(["auth": .table(["anchor": .string("bottom")])])
        let copy = ThemeFile.made(from: "lake", edit: more, name: "Lake 2", config: sandbox.config)
        #expect(copy == ThemeFile(base: "default", name: "Lake 2", edits: [edit, more]))
        // A theme the window did not make is the base itself, and no change adds no edit.
        #expect(ThemeFile.made(from: "default", edit: .nil, name: "Plain", config: sandbox.config) == ThemeFile(base: "default", name: "Plain", edits: []))
        #expect(ThemeFile.isBuiltIn("default") && ThemeFile.isBuiltIn("mocha") && !ThemeFile.isBuiltIn("lake"))
    }

    @Test func anInstalledThemeLoadsWithItsChanges() async throws {
        let sandbox = try Sandbox()
        try await ThemeFile(base: "default", name: "Lake", edits: [edit]).install(as: "lake", config: sandbox.config)
        let layout = try await Inspection.layout(of: "lake", config: sandbox.config, wallpaper: nil).get()
        #expect(layout.name == "Lake")
        #expect(layout.background["color"] == .string("#203040"))
        #expect(layout.widgets.count == 1 && layout.widgets[0]["widget"] == .string("clock") && layout.widgets[0]["anchor"] == .string("center"))
        // The change's options are the theme's own now, over the default theme's.
        #expect(layout.widgets[0]["opts"]["size"] == .int(90) && layout.widgets[0]["opts"]["weight"] == .string("light"))
        #expect(layout.auth["anchor"] == .string("top"))
        let info = await Inspection.load(config: sandbox.config, settings: Locky.Settings()).theme("lake")
        #expect(info?.name == "Lake" && info?.description == "Made from Aurora.")
        // A second one with the same id is refused.
        await #expect(throws: LuaError.self) { try await ThemeFile(base: "default", name: "Lake", edits: []).install(as: "lake", config: sandbox.config) }
    }

    @Test func aCopyOfTheUsersOwnThemeInstalls() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/mine.lua", "return { name = 'Mine', background = { color = '#112233' } }")
        try await ThemeFile(base: "mine", name: "Mine Copy", edits: []).install(as: "mine-copy", config: sandbox.config)
        let layout = try await Inspection.layout(of: "mine-copy", config: sandbox.config, wallpaper: nil).get()
        #expect(layout.name == "Mine Copy" && layout.background["color"] == .string("#112233"))
    }

    @Test func aThemeThatFailsIsNotInstalled() async throws {
        let sandbox = try Sandbox()
        let bad: LuaValue = .table(["widgets": .array([.table(["widget": .string("clock"), "anchor": .string("nowhere")])])])
        await #expect(throws: LuaError.self) { try await ThemeFile(base: "default", name: "Bad", edits: [bad]).install(as: "bad", config: sandbox.config) }
        await #expect(throws: LuaError.self) { try await ThemeFile(base: "missing", name: "Gone", edits: []).install(as: "gone", config: sandbox.config) }
        #expect(!FileManager.default.fileExists(atPath: sandbox.config.appending(path: "themes").path))
    }

    @Test func aThemeThatDerivesFromItselfFails() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/loop.lua", try ThemeFile(base: "loop", name: "Loop", edits: []).source())
        let result = await Inspection.layout(of: "loop", config: sandbox.config, wallpaper: nil)
        guard case .failure(let error) = result else { Issue.record("loaded"); return }
        #expect(error.message.contains("derives from itself"))
    }
}
