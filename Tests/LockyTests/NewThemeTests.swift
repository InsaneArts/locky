import AppKit
import Testing
@testable import Locky

/// New Theme…, and what Customize builds a theme with: an animated background, colors, a font, the text widget, and a
/// name. Each change saves to settings.json, Edit ▸ Undo takes it back, the lock screen shows it, and Export bakes it in.
@MainActor
@Suite struct NewThemeTests {
    /// A model on a sandbox config, once the config has been read.
    private func model(_ sandbox: Sandbox) async -> AppModel {
        _ = NSApplication.shared
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        model.refresh()
        await model.firstRead(within: .seconds(5))
        return model
    }

    /// Polls `condition` on the main actor until it holds or `timeout` passes.
    private func wait(timeout: Double = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        return condition()
    }

    /// The theme as a lock would show it, with `settings`.
    private func started(_ theme: String, _ sandbox: Sandbox, settings: Locky.Settings = Locky.Settings()) async -> LuaRuntime.Started {
        let runtime = LuaRuntime(path: RuntimePath.standard(config: sandbox.config), settings: settings, delegate: Recorder().delegate)
        defer { runtime.stop() }
        return await runtime.start(theme: theme)
    }

    @Test func newThemeWritesAnUntitledThemeAndOpensItInCustomize() async throws {
        let sandbox = try Sandbox()
        let model = await model(sandbox)
        let first = try await model.newTheme()
        #expect(first == "untitled-theme" && model.editingTheme == first)
        let text = try String(contentsOf: ThemeFile.file(first, config: sandbox.config), encoding: .utf8)
        #expect(ThemeFile.parse(text) == ThemeFile(base: ThemeFile.blank, name: "Untitled Theme", edits: []))

        let second = try await model.newTheme()
        #expect(second == "untitled-theme-2" && model.editingTheme == second)
        // Both are the person's own, in the gallery's list once the config is read again.
        let listed = await wait { model.inspection.theme(second) != nil }
        #expect(listed && model.inspection.theme(first)?.name == "Untitled Theme")
        #expect(model.ownFile(second)?.name == "Untitled Theme 2")
        #expect(model.canTrash(first) && model.canExport(first))
    }

    @Test func theBlankThemeLoadsAndNoListShowsIt() async throws {
        let sandbox = try Sandbox()
        let blank = await started(ThemeFile.blank, sandbox)
        #expect(blank.problems.isEmpty, "\(blank.problems)")
        #expect(blank.theme.widgets.map(\.widget) == ["date", "clock"] && blank.theme.background == .color("#15171c"))
        #expect(blank.theme.font == FontSpec())
        let names = await Inspection.load(config: sandbox.config, settings: Locky.Settings()).themes.map(\.id)
        #expect(names.contains("default") && !names.contains(ThemeFile.blank))
        // A theme made from it says nothing about where it came from.
        let (id, file) = ThemeFile.untitled(taken: [])
        try await file.install(as: id, config: sandbox.config)
        let info = await Inspection.load(config: sandbox.config, settings: Locky.Settings()).theme(id)
        #expect(info?.name == "Untitled Theme" && info?.description == nil)
    }

    @Test func colorsSaveUndoAndShow() async throws {
        let editor = try await Editor()
        let editing = editor.editing
        #expect(editing.color("fg") == "#f5f5f7" && editing.hasCardFill)
        editor.step { editing.setColors(["fg": "#ff0000", "muted": "#00ff00", "card": "#336699"]) }
        // A color well picks no transparency: secondary text and the cards keep theirs.
        #expect(editor.edit["palette"] == .table(["fg": .string("#ff0000"), "muted": .string("#00ff0099")]))
        #expect(editor.edit["card"] == .table(["fill": .string("#3366992e")]))
        #expect(editor.undo.undoActionName == "Change Colors")
        let shown = await started(editor.id, editor.sandbox, settings: editor.model.store.settings)
        #expect(shown.problems.isEmpty, "\(shown.problems)")
        #expect(shown.theme.palette["fg"] == "#ff0000" && shown.theme.palette["muted"] == "#00ff0099")
        #expect(shown.theme.card.fill == "#3366992e")
        editor.undo.undo()
        #expect(editor.edit.isNil && !editing.colorsChanged)
    }

    @Test func aFontSavesUndoesAndShows() async throws {
        let editor = try await Editor()
        let editing = editor.editing
        editor.step { editing.setFont(FontSpec(family: "Avenir Next", weight: "light")) }
        #expect(editing.font == FontSpec(family: "Avenir Next", weight: "light") && editing.fontChanged)
        let shown = await started(editor.id, editor.sandbox, settings: editor.model.store.settings)
        #expect(shown.theme.font == FontSpec(family: "Avenir Next", weight: "light"))
        // System again: the whole font is saved, so no family is left over.
        editor.step { editing.setFont(FontSpec(design: "serif")) }
        let system = await started(editor.id, editor.sandbox, settings: editor.model.store.settings)
        #expect(system.theme.font == FontSpec(design: "serif"))
        #expect(editor.undo.undoActionName == "Change Font")
        editor.undo.undo()
        editor.undo.undo()
        #expect(editor.edit.isNil)
    }

    @Test func everyBuiltInShaderIsOfferedWithItsOwnColors() async throws {
        let sandbox = try Sandbox()
        let shaders = await Inspection.load(config: sandbox.config, settings: Locky.Settings()).shaders
        let names = shaders.compactMap { $0.background["shader"].string }
        #expect(Set(names).count == names.count, "one choice per shader")
        #expect(["aurora", "snowfall", "rainy", "synthwave"].allSatisfy(names.contains), "\(names)")
        let aurora = try #require(shaders.first { $0.background["shader"] == .string("aurora") })
        #expect(aurora.id == "default" && aurora.name == "Aurora")
        // Roles are the theme's colors as hex, so they draw the same in any theme.
        #expect(aurora.background["colors"].array?.allSatisfy { $0.string?.hasPrefix("#") == true } == true)
        let snowfall = try #require(shaders.first { $0.background["shader"] == .string("snowfall") })
        let picture = try ShaderView.still(url: RuntimePath.resources.appending(path: "packages/snowfall/shaders/snowfall.metal"),
                                           colors: snowfall.background["colors"].array?.compactMap(\.string) ?? [],
                                           params: [], seconds: 30, width: 64, height: 40)
        #expect(picture.width == 64 && picture.height == 40)
    }

    @Test func anAnimatedBackgroundShowsInAnyTheme() async throws {
        let editor = try await Editor()
        let shaders = await Inspection.load(config: editor.sandbox.config, settings: Locky.Settings()).shaders
        let rainy = try #require(shaders.first { $0.background["shader"] == .string("rainy") })
        editor.step { editor.editing.record("Change Background") { editor.model.store.update { $0.setThemeEdit(editor.id, "background", rainy.background) } } }
        let shown = await started(editor.id, editor.sandbox, settings: editor.model.store.settings)
        #expect(shown.problems.isEmpty, "\(shown.problems)")
        guard case .shader(let url, let colors, _, _, _, _, _) = shown.theme.background else {
            Issue.record("no shader: \(shown.theme.background)")
            return
        }
        #expect(url.lastPathComponent == "rainy.metal" && colors == rainy.background["colors"].array?.compactMap(\.string))
        editor.undo.undo()
        #expect(editor.edit.isNil)
    }

    @Test func aRenameKeepsTheIdAndUndoes() async throws {
        let editor = try await Editor()
        #expect(editor.editing.ownName == "Untitled Theme")
        editor.step { try? editor.editing.rename("Night Lake") }
        #expect(editor.model.ownFile(editor.id)?.name == "Night Lake")
        #expect(editor.undo.undoActionName == "Rename Theme")
        editor.undo.undo()
        #expect(editor.model.ownFile(editor.id)?.name == "Untitled Theme")
        editor.undo.redo()
        #expect(editor.model.ownFile(editor.id)?.name == "Night Lake")
        #expect(throws: LuaError.self) { try editor.model.rename(editor.id, to: " ") }
        // Locky's own themes keep their names.
        #expect(editor.model.ownFile("default") == nil)
    }

    @Test func theTextWidgetDrawsItsOptions() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", """
        return { widgets = {
          { 'text', opts = { text = 'Back at 3', size = 'large', weight = 'bold', alignment = 'leading', color = 'accent' } },
          { 'text' },
        } }
        """)
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: recorder.delegate)
        defer { runtime.stop() }
        let started = await runtime.start(theme: "t")
        #expect(started.problems.isEmpty, "\(started.problems)")
        let ids = started.instances.compactMap { $0 }
        try #require(ids.count == 2)
        _ = await wait { ids.allSatisfy { recorder.views[$0] != nil } }
        let own = try #require(recorder.views[ids[0]] ?? nil)
        #expect(own.kind == .text("Back at 3") && own.size == 40 && own.weight == "bold" && own.textAlign == "leading")
        #expect(own.color == .color("accent"))
        let plain = try #require(recorder.views[ids[1]] ?? nil)
        #expect(plain.kind == .text("Your words") && plain.size == 24 && plain.weight == "regular" && plain.textAlign == "center")
        // In the Add Widget sheet, with menus for its sizes and alignments.
        let info = await Inspection.load(config: sandbox.config, settings: Locky.Settings()).widget("text")
        #expect(info?.choices["size"] == ["small", "medium", "large", "huge"] && info?.origin == .locky)
    }

    /// Export Theme… and Duplicate Theme… write the theme with every change: another Mac shows what Customize showed.
    @Test func exportBakesEveryChangeIn() async throws {
        let editor = try await Editor()
        let editing = editor.editing
        let shaders = await Inspection.load(config: editor.sandbox.config, settings: Locky.Settings()).shaders
        let aurora = try #require(shaders.first { $0.background["shader"] == .string("aurora") })
        editor.step { editing.record("Change Background") { editor.model.store.update { $0.setThemeEdit(editor.id, "background", aurora.background) } } }
        editor.step { editing.setColors(["fg": "#ffeedd", "accent": "#ff9f0a", "card": "#112233"]) }
        editor.step { editing.setFont(FontSpec(family: "Avenir Next", weight: "medium")) }
        editor.step { editing.add("text") }
        editor.step { editing.add("battery", family: "circular") }
        let before = await started(editor.id, editor.sandbox, settings: editor.model.store.settings)

        let file = ThemeFile.made(from: editor.id, edit: editor.model.store.settings["themes"][editor.id], name: "Shared", config: editor.sandbox.config)
        #expect(file.base == ThemeFile.blank && ThemeFile.isBuiltIn(file.base))
        // On another Mac: the file alone, no settings.json.
        let other = try Sandbox()
        try await ThemeFile.parse(try file.source())!.install(as: "shared", config: other.config)
        let after = await started("shared", other)
        #expect(after.problems.isEmpty, "\(after.problems)")
        #expect(after.theme.background == before.theme.background)
        #expect(after.theme.palette == before.theme.palette && after.theme.palette["accent"] == "#ff9f0a")
        #expect(after.theme.font == FontSpec(family: "Avenir Next", weight: "medium"))
        #expect(after.theme.card == before.theme.card && after.theme.card.fill == "#1122332e")
        #expect(after.theme.widgets.map(\.widget) == ["date", "clock", "text", "battery"])
        #expect(after.theme.widgets.map(\.family) == before.theme.widgets.map(\.family))
    }

    /// A new theme in Customize, with Edit ▸ Undo steps made one at a time.
    @MainActor
    private struct Editor {
        let sandbox: Sandbox
        let model: AppModel
        let editing: ThemeEditing
        let id: String
        let undo = UndoManager()

        init() async throws {
            sandbox = try Sandbox()
            _ = NSApplication.shared
            model = AppModel(store: SettingsStore(config: sandbox.config))
            let (id, file) = ThemeFile.untitled(taken: [])
            try await file.install(as: id, config: sandbox.config)
            self.id = id
            // Listed first: Customize renames only a theme the config's read lists as the person's own.
            model.refresh()
            await model.firstRead(within: .seconds(5))
            editing = ThemeEditing(theme: Inspection.ThemeInfo(id: id, name: file.name), model: model)
            await editing.load()
            undo.groupsByEvent = false
            editing.undoManager = undo
        }

        func step(_ change: () -> Void) {
            undo.beginUndoGrouping()
            change()
            undo.endUndoGrouping()
        }

        var edit: LuaValue { model.store.settings["themes"][id] }
    }
}
