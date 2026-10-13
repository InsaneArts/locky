import AppKit
import SwiftUI
import Testing
@testable import Locky

@Suite struct PlacingTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func aWidgetPinsToThePartOfTheScreenItIsIn() {
        #expect(Placing.anchor(for: CGRect(x: 30, y: 20, width: 200, height: 40), in: screen) == .topLeft)
        #expect(Placing.anchor(for: CGRect(x: 620, y: 100, width: 200, height: 100), in: screen) == .top)
        #expect(Placing.anchor(for: CGRect(x: 1200, y: 800, width: 200, height: 60), in: screen) == .bottomRight)
        #expect(Placing.anchor(for: CGRect(x: 620, y: 400, width: 200, height: 100), in: screen) == .center)
        // Off the screen counts as the nearest part.
        #expect(Placing.anchor(for: CGRect(x: -500, y: 2000, width: 100, height: 100), in: screen) == .bottomLeft)
    }

    @Test func theOffsetKeepsTheWidgetWhereItWasDropped() {
        let frame = CGRect(x: 1180, y: 812, width: 220, height: 48)
        let (anchor, offset) = Placing.place(frame, in: screen, snap: false)
        #expect(anchor == .bottomRight)
        #expect(offset == CGPoint(x: -40, y: -40))
        #expect(anchor.frame(size: frame.size, offset: offset, in: screen) == frame)
    }

    @Test func theGridSnapsTheAnchoredEdge() {
        // Centered at the top: its center snaps across, its top edge down.
        let frame = CGRect(x: 612, y: 106, width: 230, height: 120)
        let (anchor, offset) = Placing.place(frame, in: screen, snap: true)
        #expect(anchor == .top)
        #expect(offset == CGPoint(x: 0, y: 120))
        let snapped = anchor.frame(size: frame.size, offset: offset, in: screen)
        #expect(snapped.midX == 720 && snapped.minY == 120)
    }
}

/// The Themes page with a real preview, driven with mouse events sent straight to the canvas: nothing moves the
/// pointer. LOCKY_TEST_SHOTS=<folder> saves what the window shows at each step.
@MainActor
@Suite(.serialized) struct CanvasTests {
    @MainActor
    private struct Page {
        let sandbox: Sandbox
        let model: AppModel
        let window: NSWindow
        let overlay: CanvasOverlay
        var preview: ThemePreviewView { overlay.preview! }
    }

    private func open() async throws -> Page {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", """
        return { background = { color = '#203040' }, auth = { anchor = 'bottom', offset = { 0, -60 } },
                 widgets = { { 'box', anchor = 'center' }, { 'box', anchor = 'top-right', offset = { -30, 30 }, opts = { label = 'two' } } } }
        """)
        try sandbox.write("plugin/box.lua", """
        locky.widget.define('box', { size = { 200, 100 }, opts = { label = 'box', size = 20, bold = false },
          choices = { label = { 'box', 'two', 'three' } },
          render = function(self) return locky.ui.text(self.opts.label, { size = self.opts.size }) end })
        """)
        _ = NSApplication.shared
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        model.screenshots = true
        model.selectedTheme = "t"
        model.section = .themes
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1240, height: 780), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ThemesPage(model: model))
        model.refresh()
        var overlay: CanvasOverlay?
        // The grid as the defaults have it: the page may first see the last test's.
        let grid = UserDefaults.standard.bool(forKey: "themeEditorGrid")
        let ready = await wait(window) {
            overlay = Self.find(CanvasOverlay.self, in: window.contentView!)
            return overlay.map { !$0.isHidden && $0.preview!.canvas?.grid == grid && $0.preview!.editables.contains { $0.item == .widget(0) } } ?? false
        }
        try #require(ready, "the canvas never showed the theme's widgets")
        return Page(sandbox: sandbox, model: model, window: window, overlay: overlay!)
    }

    /// Polls `condition` while the window lays out, as a window on screen would.
    private func wait(_ window: NSWindow, timeout: Double = 8, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            window.contentView?.layoutSubtreeIfNeeded()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return condition()
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews { if let match = find(type, in: child) { return match } }
        return nil
    }

    /// A mouse event at a point of the screen, in layout points.
    private func event(_ type: NSEvent.EventType, at point: CGPoint, on page: Page) -> NSEvent {
        let scale = page.overlay.bounds.width / ThemePreviewView.layoutSize.width
        let location = page.overlay.convert(CGPoint(x: point.x * scale, y: point.y * scale), to: nil)
        return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: page.window.windowNumber,
                                  context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func drag(_ page: Page, from start: CGPoint, by delta: CGPoint) {
        page.overlay.mouseDown(with: event(.leftMouseDown, at: start, on: page))
        for step in 1...4 {
            let point = CGPoint(x: start.x + delta.x * Double(step) / 4, y: start.y + delta.y * Double(step) / 4)
            page.overlay.mouseDragged(with: event(.leftMouseDragged, at: point, on: page))
        }
        page.overlay.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: start.x + delta.x, y: start.y + delta.y), on: page))
    }

    private func frame(of item: EditorItem, _ page: Page) -> CGRect? {
        page.preview.editables.first { $0.item == item }?.frame
    }

    private func shoot(_ page: Page, _ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["LOCKY_TEST_SHOTS"], let view = page.window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appending(path: "\(name).png"))
    }

    private func saved(_ page: Page) -> Locky.Settings { Locky.Settings.load(config: page.sandbox.config).settings }

    @Test func draggingAWidgetSavesWhereItWasDroppedAndThePreviewKeepsIt() async throws {
        let page = try await open()
        shoot(page, "1-theme")
        let box = try #require(frame(of: .widget(0), page))
        #expect(box == CGRect(x: 620, y: 400, width: 200, height: 100))
        // From the center to near the top-left corner: pinned there, 60 and 70 points in.
        drag(page, from: CGPoint(x: box.midX, y: box.midY), by: CGPoint(x: -560, y: -330))
        let entry = saved(page).themeEdit("t", "widgets")[0]
        #expect(entry["anchor"] == .string("top-left") && entry["offset"] == .array([.int(60), .int(70)]) && entry["ref"] == .int(1))
        // The other widget stays as the theme has it.
        #expect(saved(page).themeEdit("t", "widgets")[1]["offset"] == .array([.int(-30), .int(30)]))
        #expect(await wait(page.window) { page.preview.canvas?.selection == .widget(0) })
        // The preview shows the saved place once it has reloaded, and keeps it.
        #expect(await wait(page.window) { frame(of: .widget(0), page) == CGRect(x: 60, y: 70, width: 200, height: 100) })
        try await Task.sleep(for: .milliseconds(400))
        #expect(frame(of: .widget(0), page) == CGRect(x: 60, y: 70, width: 200, height: 100))
        shoot(page, "2-dragged")
    }

    @Test func theGridSnapsADrag() async throws {
        UserDefaults.standard.set(true, forKey: "themeEditorGrid")
        defer { UserDefaults.standard.set(false, forKey: "themeEditorGrid") }
        let page = try await open()
        let box = try #require(frame(of: .widget(0), page))
        drag(page, from: CGPoint(x: box.midX, y: box.midY), by: CGPoint(x: -551, y: -322))
        // 69 and 78 points in, onto the 30-point grid.
        let entry = saved(page).themeEdit("t", "widgets")[0]
        #expect(entry["anchor"] == .string("top-left") && entry["offset"] == .array([.int(60), .int(90)]))
        shoot(page, "3-grid")
    }

    @Test func aClickSelectsWithoutSavingAndAClickElsewhereClears() async throws {
        let page = try await open()
        let box = try #require(frame(of: .widget(1), page))
        let center = CGPoint(x: box.midX, y: box.midY)
        page.overlay.mouseDown(with: event(.leftMouseDown, at: center, on: page))
        page.overlay.mouseUp(with: event(.leftMouseUp, at: center, on: page))
        #expect(await wait(page.window) { page.preview.canvas?.selection == .widget(1) })
        #expect(saved(page)["themes"].isNil)
        shoot(page, "4-selected")
        page.overlay.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 300, y: 600), on: page))
        page.overlay.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 300, y: 600), on: page))
        #expect(await wait(page.window) { page.preview.canvas?.selection == nil })
    }

    /// After a switch to another theme, the old theme's screen stays until the new one is ready: its widgets are not
    /// the new theme's to drag.
    @Test func theCanvasWaitsForTheNextThemesScreen() async throws {
        let page = try await open()
        try page.sandbox.write("themes/u.lua", "return { background = { color = '#402020' }, widgets = { { 'box', anchor = 'top' } } }")
        page.model.refresh()
        // The new file starts t's preview again; wait for it to be back.
        #expect(await wait(page.window) { page.model.inspection.theme("u") != nil })
        try await Task.sleep(for: .milliseconds(300))
        #expect(await wait(page.window) { frame(of: .widget(1), page) != nil })
        page.model.selectedTheme = "u"
        #expect(await wait(page.window) { page.preview.editables.isEmpty })
        #expect(await wait(page.window) { frame(of: .widget(0), page) == CGRect(x: 620, y: 0, width: 200, height: 100) })
    }

    @Test func aDragIsOneStepEditUndoTakesBack() async throws {
        let page = try await open()
        let box = try #require(frame(of: .widget(0), page))
        drag(page, from: CGPoint(x: box.midX, y: box.midY), by: CGPoint(x: -560, y: -330))
        #expect(!saved(page)["themes"].isNil)
        let undo = try #require(page.window.undoManager)
        #expect(undo.undoMenuItemTitle == "Undo Move Box")
        // The preview shows the drop before the undo, as it would for a person.
        #expect(await wait(page.window) { frame(of: .widget(0), page) == CGRect(x: 60, y: 70, width: 200, height: 100) })
        undo.undo()
        #expect(saved(page)["themes"].isNil)
        #expect(await wait(page.window) { frame(of: .widget(0), page) == box })
        undo.redo()
        #expect(saved(page).themeEdit("t", "widgets")[0]["anchor"] == .string("top-left"))
    }

    @Test func thePasswordFieldMovesToo() async throws {
        let page = try await open()
        #expect(await wait(page.window) { frame(of: .passwordField, page) != nil })
        let field = try #require(frame(of: .passwordField, page))
        drag(page, from: CGPoint(x: field.midX, y: field.midY), by: CGPoint(x: 400, y: -40))
        let dropped = field.offsetBy(dx: 400, dy: -40)
        let place = Placing.place(dropped, in: CGRect(origin: .zero, size: ThemePreviewView.layoutSize), snap: false)
        let auth = saved(page).themeEdit("t", "auth")
        #expect(auth["anchor"] == .string(place.anchor.rawValue))
        #expect(auth["offset"] == .array([.int(Int(place.offset.x)), .int(Int(place.offset.y))]))
        #expect(await wait(page.window) { frame(of: .passwordField, page) == dropped })
    }
}

@Suite struct OptionControlTests {
    /// The agents widget's offline line: text, or false to hide the widget when herdr is off.
    @Test func textThatCanBeOffKeepsItsKind() {
        let own: LuaValue = .string("herdr is not running")
        // Turned off by the theme or by init.lua: a switch that turns the widget's own text back on.
        #expect(OptionControl.textOrOff(.bool(false), own: own, inherited: .bool(false)) == "herdr is not running")
        // Turned back on in the window: still a switch, so it can go off again.
        #expect(OptionControl.textOrOff(.string("offline"), own: own, inherited: .bool(false)) == "herdr is not running")
        // Text the theme never turns off, and a true switch, stay as they are.
        #expect(OptionControl.textOrOff(.string("offline"), own: own, inherited: .string("x")) == nil)
        #expect(OptionControl.textOrOff(.bool(false), own: .bool(true), inherited: .bool(false)) == nil)
        #expect(OptionControl.textOrOff(.bool(false), own: nil, inherited: .bool(false)) == nil)
    }
}

@MainActor
@Suite struct ThemeEditingTests {
    /// The case Lua's anExactRefKeepsItsPlacement covers: the editor's list must be the one the preview shows.
    @Test func theListMatchesWhatLuaShows() {
        let original: [LuaValue] = [.table(["widget": .string("one")]), .table(["widget": .string("two")])]
        let entries: [LuaValue] = [
            .table(["ref": .int(3), "widget": .string("one"), "anchor": .string("bottom-right")]),
            .table(["ref": .int(1), "widget": .string("one"), "anchor": .string("top-left")]),
            .table(["ref": .int(5), "widget": .string("two"), "anchor": .string("bottom")]),
            .table(["widget": .string("three")]),
        ]
        let list = EditorPlacement.resolve(entries, theme: original)
        #expect(list.map(\.widget) == ["one", "two", "three"])
        #expect(list.map(\.anchor) == ["top-left", "bottom", "center"])
        #expect(list.map(\.base) == [0, 1, nil])
    }

    @Test func aPlacementTakesTheThemesOptionsAndCard() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { widgets = { { 'w', card = false, opts = { size = 30 } } } }")
        try sandbox.write("plugin/w.lua", "locky.widget.define('w', { card = true, opts = { size = 12, label = 'w' }, render = function() end })")
        // AppModel reads NSApp's appearance, which a test process has only once something makes the application.
        _ = NSApplication.shared
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        model.refresh()
        let deadline = Date().addingTimeInterval(5)
        while !model.inspection.loaded, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let editing = ThemeEditing(theme: Inspection.ThemeInfo(id: "t", name: "t"), model: model)
        await editing.load()
        let placement = try #require(editing.placements.first)
        #expect(editing.inherited(placement) == ["size": .int(30), "label": .string("w")])
        // The theme says no card, over the widget's own default.
        #expect(!editing.card(placement))
        // A widget the window adds starts with the widget's own options.
        let index = editing.add("w")
        let added = editing.placements[index]
        #expect(editing.inherited(added) == ["size": .int(12), "label": .string("w")])
        #expect(editing.card(added))
    }

    @Test func undoAndRedoPutTheThemesChangesBack() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { widgets = { { 'w', anchor = 'top' } } }")
        try sandbox.write("plugin/w.lua", "locky.widget.define('w', { render = function() end })")
        _ = NSApplication.shared
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        model.store.update { $0["theme"] = .string("t") }
        let editing = ThemeEditing(theme: Inspection.ThemeInfo(id: "t", name: "t"), model: model)
        await editing.load()
        let undo = UndoManager()
        undo.groupsByEvent = false
        editing.undoManager = undo
        let step = { (change: () -> Void) in
            undo.beginUndoGrouping()
            change()
            undo.endUndoGrouping()
        }
        step { editing.add("w") }
        step { editing.setAuth(anchor: "top-left", x: 30, y: 30) }
        let changed = model.store.settings
        #expect(undo.undoActionName == "Move Password Field")
        // No change, no step: outside a group, a step would raise.
        editing.setAuth(anchor: "top-left", x: 30, y: 30)
        #expect(undo.undoActionName == "Move Password Field")

        undo.undo()
        #expect(model.store.settings.themeEdit("t", "auth").isNil)
        #expect(editing.placements.count == 2)
        #expect(undo.undoActionName == "Add W" && undo.redoActionName == "Move Password Field")
        undo.undo()
        // Back to no changes at all; the rest of settings.json stays.
        #expect(model.store.settings["themes"].isNil && model.store.settings["theme"] == .string("t"))
        #expect(Locky.Settings.load(config: sandbox.config).settings["themes"].isNil)
        undo.redo()
        undo.redo()
        #expect(model.store.settings == changed)
    }

    /// Off and on again, a widget goes back to the theme's card, in the theme's style: the switch saves only a change.
    @Test func theCardSwitchKeepsTheThemesStyle() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { widgets = { { 'w', card = 'outline' } } }")
        try sandbox.write("plugin/w.lua", "locky.widget.define('w', { render = function() end })")
        _ = NSApplication.shared
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        let editing = ThemeEditing(theme: Inspection.ThemeInfo(id: "t", name: "t"), model: model)
        await editing.load()
        var placement = try #require(editing.placements.first)
        #expect(editing.card(placement))
        placement.card = editing.cardValue(false, for: placement)
        #expect(placement.card == .bool(false) && !editing.card(placement))
        placement.card = editing.cardValue(true, for: placement)
        #expect(placement.card == nil && editing.card(placement))
        #expect(placement.settingsValue["card"] == .nil)
    }
}
