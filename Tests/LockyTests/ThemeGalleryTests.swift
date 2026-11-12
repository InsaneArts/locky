import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Locky

/// The gallery's pure parts: Import Theme…'s checks.
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
}

/// A theme's colors as the windows show them: its dots, its accent, and whether its page is light.
@Suite struct ThemeLookTests {
    /// The accent comes first, then the theme's other colors, the most colorful first. Two roles of one color make
    /// one dot, and a color with alpha counts as it looks over the background.
    @Test func theDotsAreTheThemesOwnColorsTheAccentFirst() {
        let look = ThemeLook(palette: ["bg": "#000000", "fg": "#ffffff", "muted": "#ffffff80", "accent": "#ff0000", "danger": "#ff0000",
                                       "sky": "#0000ff", "surface": "#101010"])
        #expect(look.swatches == ["#ff0000", "#0000ff", "#ffffff", "#808080", "#101010", "#000000"])
        #expect(look.accent == "#ff0000")
    }

    @Test func atMostSixDots() {
        let palette = Dictionary(uniqueKeysWithValues: (0..<12).map { ("c\($0)", String(format: "#%02x%02x00", $0 * 20, 255 - $0 * 20)) })
        #expect(ThemeLook(palette: palette).swatches.count == 6)
    }

    /// A theme with no colors of its own shows Locky's defaults.
    @Test func aThemeWithoutColorsShowsTheDefaults() {
        let look = ThemeLook(palette: [:])
        #expect(look.accent == "#0a84ff")
        #expect(look.swatches.first == "#0a84ff" && look.swatches.count == 6)
        #expect(!look.isLight)
    }

    /// The page is light for a light background, and the words on the accent read on it.
    @Test func aLightThemeHasALightPageAndReadableWordsOnItsAccent() {
        let poster = ThemeLook(palette: ["bg": "#F1EFE8", "fg": "#0A0A0A", "accent": "#DA291C"])
        #expect(poster.isLight)
        // The cream background reads on the red: it is the words' color.
        #expect(poster.onAccent == "#f1efe8")
        // A pale accent on a pale background: black words.
        #expect(ThemeLook(palette: ["bg": "#ffffff", "accent": "#ffee88"]).onAccent == "#000000")
        // A dark accent on a dark background: white words.
        #expect(ThemeLook(palette: ["bg": "#000000", "accent": "#220000"]).onAccent == "#ffffff")
    }
}

/// The Themes window as Locky makes it, out of sight. The sidebar's list has the keyboard when the gallery shows, and
/// again after Customize, whose canvas takes the keyboard and leaves the window after the gallery is back.
@MainActor
@Suite(.serialized) struct GalleryKeyboardTests {
    private func wait(_ timeout: Double = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        return condition()
    }

    private func press(_ window: NSWindow, _ code: UInt16, _ text: String, function: Bool = false) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            window.sendEvent(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: function ? [.numericPad, .function] : [], timestamp: 0,
                                              windowNumber: window.windowNumber, context: nil, characters: text,
                                              charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!)
        }
    }

    /// Whether the down arrow changes the theme in use, as it does while the list has the keyboard.
    private func downArrowMoves(_ window: NSWindow, _ model: AppModel, within timeout: Double = 2) async -> Bool {
        let before = model.activeTheme
        press(window, 125, String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), function: true)
        return await wait(timeout) { model.activeTheme != before }
    }

    @Test(arguments: ["Done", "Escape"])
    func theListHasTheKeysAgainAfterCustomize(_ way: String) async throws {
        _ = NSApplication.shared
        let sandbox = try Sandbox()
        try sandbox.write("settings.json", #"{ "privacy": true }"#)
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        model.screenshots = true
        model.refresh()
        try #require(await wait(10) { model.inspection.loaded })
        let controller = LockyWindowController(model: model, onClose: {})
        let window = try #require(controller.window)
        defer { window.close() }
        try #require(await wait { window.firstResponder !== window })
        #expect(await downArrowMoves(window, model), "the list takes the arrows before Customize")

        model.customize(model.activeTheme)
        try #require(await wait { window.firstResponder is CanvasOverlay })
        if way == "Done" { model.finishEditing() } else { press(window, 53, "\u{1b}") }
        #expect(model.editingTheme == nil)
        #expect(await wait { window.firstResponder !== window && !(window.firstResponder is CanvasOverlay) },
                "first responder: \(String(describing: window.firstResponder))")
        #expect(await downArrowMoves(window, model), "the list takes the arrows after Customize")
        // Return opens Customize for the theme in use.
        press(window, 36, "\r")
        #expect(await wait { model.editingTheme == model.activeTheme })
    }

    /// A theme that does not load has no canvas: why it does not load takes the keyboard instead, and gives it back.
    @Test(arguments: ["Done", "Escape"])
    func theListHasTheKeysAgainAfterCustomizeForAThemeThatDoesNotLoad(_ way: String) async throws {
        _ = NSApplication.shared
        let sandbox = try Sandbox()
        try sandbox.write("settings.json", #"{ "privacy": true }"#)
        try sandbox.write("themes/broken.lua", "error('broken')")
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        model.screenshots = true
        model.refresh()
        try #require(await wait(10) { model.inspection.loaded && model.inspection.theme("broken")?.error != nil })
        let controller = LockyWindowController(model: model, onClose: {})
        let window = try #require(controller.window)
        defer { window.close() }
        try #require(await wait { window.firstResponder !== window })

        model.customize("broken")
        try #require(await wait { window.firstResponder !== window && model.editingTheme == "broken" })
        try await Task.sleep(for: .milliseconds(200))
        if way == "Done" { model.finishEditing() } else { press(window, 53, "\u{1b}") }
        #expect(await wait { model.editingTheme == nil })
        // The list takes the keyboard a turn after it shows; nothing in the window tells when, so the arrow tries again.
        var moved = false
        for _ in 0..<10 where !moved { moved = await downArrowMoves(window, model, within: 0.3) }
        #expect(moved, "the list takes the arrows after Customize")
    }
}
