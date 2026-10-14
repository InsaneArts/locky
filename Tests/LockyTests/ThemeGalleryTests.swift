import Foundation
import SwiftUI
import Testing
@testable import Locky

/// The gallery's pure parts: Import Theme…'s checks, the grid's columns, and where an arrow key goes.
@MainActor
@Suite struct ThemeGalleryTests {
    private let edit: LuaValue = .table(["widgets": .array([.table(["widget": .string("clock"), "anchor": .string("center")])])])

    // MARK: Import

    @Test func onlyAFileExportThemeWroteImports() throws {
        let sandbox = try Sandbox()
        let message = "Choose a file made with Export Theme…. A theme written in Lua goes in \(LuaError.shortenPaths(sandbox.config.path))/themes."
        let lua = "return { name = 'Mine', background = { color = '#112233' } }"
        #expect(ThemeImport.check(lua, inspection: Inspection(), config: sandbox.config)
            == .failure(ImportProblem(title: "Can't Import This File", message: message)))
        #expect(ThemeImport.notExported(config: sandbox.config) == ImportProblem(title: "Can't Import This File", message: message))
    }

    @Test func aThemeMadeFromAnotherThanLockysDoesNotImport() throws {
        let sandbox = try Sandbox()
        let text = try ThemeFile(base: "mine", name: "Mine Copy", edits: []).source()
        #expect(ThemeImport.check(text, inspection: Inspection(), config: sandbox.config)
            == .failure(ImportProblem(title: "Can't Import This Theme", message: "It is made from “mine”, which is not one of Locky's themes.")))
    }

    /// As the window reads the widgets: Locky's own import, and a plugin's do not.
    @Test func aThemeWithPluginWidgetsDoesNotImport() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/shell.lua", "locky.widget.define('shell', { render = function() end })")
        let inspection = await Inspection.load(config: sandbox.config, settings: Locky.Settings())
        let plugin: LuaValue = .table(["widgets": .array([.table(["widget": .string("shell"), "opts": .table(["cmd": .string("curl x | sh")])])])])
        let text = try ThemeFile(base: "default", name: "Lake", edits: [edit, plugin]).source()
        #expect(ThemeImport.check(text, inspection: inspection, config: sandbox.config)
            == .failure(ImportProblem(title: "Can't Import This Theme",
                                      message: "It uses widgets from plugins: shell. Locky imports only themes that use its own widgets.")))
    }

    @Test func anExportedBuiltInThemeImports() async throws {
        let sandbox = try Sandbox()
        let inspection = await Inspection.load(config: sandbox.config, settings: Locky.Settings())
        let file = ThemeFile(base: "default", name: "Lake", edits: [edit])
        #expect(ThemeImport.check(try file.source(), inspection: inspection, config: sandbox.config) == .success(file))
    }

    // MARK: The grid

    /// The window's content at 980, 1240, and 1600 pt wide, less the page's padding; and a width under one column.
    @Test(arguments: [(932, 4), (1192, 6), (1232, 6), (100, 1)] as [(CGFloat, Int)])
    func theGridFitsColumnsAsTheAdaptiveItemDoes(_ width: CGFloat, _ columns: Int) {
        #expect(ThemeGallery.columns(width: width) == columns)
    }

    /// Three columns of eight themes, and Event Horizon does not load:
    ///
    ///     Aurora   Bauhaus  Deep Blue
    ///     Dots     Event    Fog
    ///     Gruvbox  Haze
    private let themes = ["aurora", "bauhaus", "deepblue", "dots", "event", "fog", "gruvbox", "haze"].map { id in
        Inspection.ThemeInfo(id: id, name: id, error: id == "event" ? "themes/event.lua:3: attempt to index a nil value" : nil)
    }

    private func neighbor(_ id: String, _ direction: MoveCommandDirection, rightToLeft: Bool = false) -> String? {
        ThemeGallery.neighbor(of: id, in: themes, columns: 3, direction: direction, rightToLeft: rightToLeft)
    }

    @Test func leftAndRightStepByOneAndUpAndDownByARow() {
        #expect(neighbor("aurora", .right) == "bauhaus" && neighbor("bauhaus", .left) == "aurora")
        #expect(neighbor("deepblue", .right) == "dots" && neighbor("dots", .left) == "deepblue")
        #expect(neighbor("aurora", .down) == "dots" && neighbor("dots", .up) == "aurora")
        #expect(neighbor("dots", .down) == "gruvbox" && neighbor("fog", .up) == "deepblue")
    }

    @Test func aStepPastEitherEndGoesNowhere() {
        #expect(neighbor("aurora", .left) == nil && neighbor("aurora", .up) == nil)
        #expect(neighbor("haze", .right) == nil && neighbor("haze", .down) == nil)
        // No theme under Fog: the last row is short.
        #expect(neighbor("fog", .down) == nil)
    }

    /// No tile is in use, such as when the theme's file was deleted: a step forward finds the first theme that loads, and
    /// a step back the last, as a list with no selection does.
    @Test func anArrowWithNoThemeInUseStartsAtAnEnd() {
        #expect(neighbor("gone", .right) == "aurora" && neighbor("gone", .down) == "aurora")
        #expect(neighbor("gone", .left) == "haze" && neighbor("gone", .up) == "haze")
        #expect(neighbor("gone", .left, rightToLeft: true) == "aurora" && neighbor("gone", .right, rightToLeft: true) == "haze")
        // Event Horizon does not load, at either end.
        let ends = [themes[4], themes[0], themes[1], themes[4]]
        #expect(ThemeGallery.neighbor(of: "gone", in: ends, columns: 3, direction: .right, rightToLeft: false) == "aurora")
        #expect(ThemeGallery.neighbor(of: "gone", in: ends, columns: 3, direction: .left, rightToLeft: false) == "bauhaus")
        #expect(ThemeGallery.neighbor(of: "gone", in: [themes[4]], columns: 3, direction: .down, rightToLeft: false) == nil)
    }

    @Test func aThemeThatDoesNotLoadIsSkipped() {
        #expect(neighbor("dots", .right) == "fog" && neighbor("fog", .left) == "dots")
        #expect(neighbor("bauhaus", .down) == "haze" && neighbor("haze", .up) == "bauhaus")
        // Nothing that loads after it: the step goes nowhere.
        let last = [themes[0], themes[4]]
        #expect(ThemeGallery.neighbor(of: "aurora", in: last, columns: 3, direction: .right, rightToLeft: false) == nil)
    }

    /// A right-to-left grid starts on the right, so the left arrow goes on through the list.
    @Test func leftAndRightSwapForRightToLeft() {
        #expect(neighbor("bauhaus", .left, rightToLeft: true) == "deepblue")
        #expect(neighbor("bauhaus", .right, rightToLeft: true) == "aurora")
        #expect(neighbor("aurora", .down, rightToLeft: true) == "dots")
    }
}
