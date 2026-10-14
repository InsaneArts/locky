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

    @Test func anArrowKeyMovesAPointOrAGridStep() {
        let offset = CGPoint(x: -40, y: 25)
        #expect(Placing.nudge(offset, x: 1, y: 0, byGrid: false) == CGPoint(x: -39, y: 25))
        #expect(Placing.nudge(offset, x: 0, y: -1, byGrid: false) == CGPoint(x: -40, y: 24))
        #expect(Placing.nudge(offset, x: -1, y: 0, byGrid: true) == CGPoint(x: -70, y: 25))
        #expect(Placing.nudge(offset, x: 0, y: 1, byGrid: true) == CGPoint(x: -40, y: 55))
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
        locky.widget.define('box', { size = { 200, 100 }, opts = { label = 'box', size = 20, bold = false, note = 'hi' },
          choices = { label = { 'box', 'two', 'three' } },
          render = function(self) return locky.ui.text(self.opts.label, { size = self.opts.size }) end })
        """)
        _ = NSApplication.shared
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        model.screenshots = true
        model.customize("t")
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

    /// After a switch to another theme, the old theme's screen ends at once, and the canvas has nothing to drag until
    /// the new theme's screen is ready.
    @Test func theCanvasWaitsForTheNextThemesScreen() async throws {
        let page = try await open()
        try page.sandbox.write("themes/u.lua", "return { background = { color = '#402020' }, widgets = { { 'box', anchor = 'top' } } }")
        page.model.refresh()
        // The new file starts t's preview again; wait for it to be back.
        #expect(await wait(page.window) { page.model.inspection.theme("u") != nil })
        try await Task.sleep(for: .milliseconds(300))
        #expect(await wait(page.window) { frame(of: .widget(1), page) != nil })
        page.model.customize("u")
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

    /// File › Revert to Original reaches the page as a request, which runs the More menu's command and is used up.
    @Test func aFileMenuRevertTakesTheChangesBack() async throws {
        let page = try await open()
        let box = try #require(frame(of: .widget(0), page))
        drag(page, from: CGPoint(x: box.midX, y: box.midY), by: CGPoint(x: -560, y: -330))
        #expect(!saved(page)["themes"].isNil)
        page.model.editorRequest = .revert
        #expect(await wait(page.window) { saved(page)["themes"].isNil })
        #expect(page.model.editorRequest == nil)
        #expect(page.window.undoManager?.undoMenuItemTitle == "Undo Revert to Original")
    }

    private func press(_ key: Int, shift: Bool = false, _ page: Page) {
        let text = String(Character(UnicodeScalar(UInt16(key))!))
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? .shift : [], timestamp: 0,
                                     windowNumber: page.window.windowNumber, context: nil, characters: text,
                                     charactersIgnoringModifiers: text, isARepeat: false, keyCode: 0)!
        page.overlay.keyDown(with: event)
        // The end of the event, which ends its undo step.
        RunLoop.main.run(until: Date())
    }

    @Test func theKeyboardMovesRemovesAndDeselects() async throws {
        let page = try await open()
        let box = try #require(frame(of: .widget(1), page))
        page.overlay.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: box.midX, y: box.midY), on: page))
        page.overlay.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: box.midX, y: box.midY), on: page))
        #expect(await wait(page.window) { page.preview.canvas?.selection == .widget(1) })
        // From the top-right corner's -30, 30: a point left, then a grid step down.
        press(NSLeftArrowFunctionKey, page)
        #expect(await wait(page.window) { saved(page).themeEdit("t", "widgets")[1]["offset"] == .array([.int(-31), .int(30)]) })
        press(NSDownArrowFunctionKey, shift: true, page)
        #expect(await wait(page.window) { saved(page).themeEdit("t", "widgets")[1]["offset"] == .array([.int(-31), .int(60)]) })
        #expect(saved(page).themeEdit("t", "widgets")[1]["anchor"] == .string("top-right"))
        page.window.undoManager?.undo()
        #expect(saved(page).themeEdit("t", "widgets")[1]["offset"] == .array([.int(-31), .int(30)]))

        press(0x7F, page)
        #expect(await wait(page.window) { page.preview.canvas?.selection == nil })
        #expect(saved(page).themeEdit("t", "widgets").array?.count == 1)
        #expect(page.window.undoManager?.undoActionName == "Remove Box")

        page.overlay.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 720, y: 450), on: page))
        page.overlay.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 720, y: 450), on: page))
        #expect(await wait(page.window) { page.preview.canvas?.selection == .widget(0) })
        press(0x1B, page)
        #expect(await wait(page.window) { page.preview.canvas?.selection == nil })
    }

    @Test func escapeClearsTheSelectionThenEndsCustomize() async throws {
        let page = try await open()
        let box = try #require(frame(of: .widget(1), page))
        click(page, at: CGPoint(x: box.midX, y: box.midY))
        #expect(await wait(page.window) { page.preview.canvas?.selection == .widget(1) })
        press(0x1B, page)
        #expect(await wait(page.window) { page.preview.canvas?.selection == nil })
        #expect(page.model.editingTheme == "t")
        press(0x1B, page)
        #expect(page.model.editingTheme == nil)
    }

    /// Escape typed in the inspector's text field stays in the field: the selection under it stays.
    @Test func escapeInATextFieldStaysInTheField() async throws {
        let page = try await open()
        let box = try #require(frame(of: .widget(1), page))
        click(page, at: CGPoint(x: box.midX, y: box.midY))
        // The widget's X offset, once its inspector shows.
        var found: NSTextField?
        #expect(await wait(page.window) {
            found = Self.textField("-30", in: page.window.contentView!)
            return found != nil
        })
        let field = try #require(found)
        #expect(page.window.makeFirstResponder(field))
        // SwiftUI sees the field's focus on its next updates.
        for _ in 0..<20 {
            page.window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        page.window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: page.window.windowNumber,
                                               context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                                               keyCode: 53)!)
        try await Task.sleep(for: .milliseconds(200))
        page.window.contentView?.layoutSubtreeIfNeeded()
        #expect(page.preview.canvas?.selection == .widget(1))
        #expect(page.model.editingTheme == "t")
    }

    /// Escape as a key press sends it: to whatever has the keyboard in the window.
    private func escape(_ page: Page) {
        page.window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: page.window.windowNumber,
                                               context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                                               keyCode: 53)!)
    }

    /// Esc needs no click first: the canvas has the keyboard as soon as Customize opens.
    @Test func escapeEndsCustomizeRightAfterItOpens() async throws {
        let page = try await open()
        #expect(await wait(page.window) { page.window.firstResponder === page.overlay })
        escape(page)
        #expect(page.model.editingTheme == nil)
    }

    /// A theme that does not load has no canvas: why it does not load holds the keyboard, so Esc still ends Customize.
    @Test func escapeEndsCustomizeForAThemeThatDoesNotLoad() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/broken.lua", "error('broken')")
        _ = NSApplication.shared
        let model = AppModel(store: SettingsStore(config: sandbox.config))
        model.customize("broken")
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1240, height: 780), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ThemesPage(model: model))
        model.refresh()
        #expect(await wait(window) { model.inspection.theme("broken")?.error != nil && window.firstResponder !== window })
        window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                          context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                                          keyCode: 53)!)
        #expect(await wait(window) { model.editingTheme == nil })
    }

    /// After an inspector row selects an item, the keys reach the canvas, here from the page itself, which has the
    /// keyboard after the gallery's grid had it.
    @Test func escapeWorksAfterAnInspectorRowSelects() async throws {
        let page = try await open()
        #expect(await wait(page.window) { page.window.firstResponder === page.overlay })
        #expect(page.window.makeFirstResponder(page.window.contentView))
        page.preview.canvas?.select(.widget(1))
        #expect(await wait(page.window) { page.preview.canvas?.selection == .widget(1) && page.window.firstResponder === page.overlay })
        escape(page)
        #expect(await wait(page.window) { page.preview.canvas?.selection == nil })
        escape(page)
        #expect(page.model.editingTheme == nil)
    }

    /// A text field that goes with its item, as after Remove Widget, leaves the keyboard to the canvas.
    @Test func theCanvasTakesTheKeyboardFromAFieldThatGoes() async throws {
        let page = try await open()
        let box = try #require(frame(of: .widget(1), page))
        click(page, at: CGPoint(x: box.midX, y: box.midY))
        var found: NSTextField?
        #expect(await wait(page.window) {
            found = Self.textField("-30", in: page.window.contentView!)
            return found != nil
        })
        let field = try #require(found)
        #expect(page.window.makeFirstResponder(field))
        for _ in 0..<10 {
            page.window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        page.preview.canvas?.select(nil)
        #expect(await wait(page.window) { page.preview.canvas?.selection == nil && page.window.firstResponder === page.overlay })
        escape(page)
        #expect(page.model.editingTheme == nil)
    }

    /// How Customize's inspector can go while a field still has the keyboard.
    enum Leave: CaseIterable { case done, clickOtherWidget, clickEmptyCanvas }

    /// A value typed in the inspector saves when the inspector goes before Return: by Done, or by a click on the canvas.
    @Test(arguments: Leave.allCases) func aTypedValueSavesWhenTheInspectorGoes(_ leave: Leave) async throws {
        let page = try await open()
        let box = try #require(frame(of: .widget(1), page))
        click(page, at: CGPoint(x: box.midX, y: box.midY))
        var found: NSTextField?
        #expect(await wait(page.window) {
            found = Self.textField("-30", in: page.window.contentView!)
            return found != nil
        })
        let field = try #require(found)
        #expect(page.window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("-77", replacementRange: editor.selectedRange())
        for _ in 0..<10 {
            page.window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        switch leave {
        case .done: page.model.finishEditing()
        case .clickOtherWidget:
            let other = try #require(frame(of: .widget(0), page))
            click(page, at: CGPoint(x: other.midX, y: other.midY))
        case .clickEmptyCanvas: click(page, at: CGPoint(x: 300, y: 600))
        }
        #expect(await wait(page.window) { saved(page).themeEdit("t", "widgets")[1]["offset"] == .array([.int(-77), .int(30)]) })
    }

    /// Text typed in an option's field saves the same way, here when Done ends Customize.
    @Test func typedTextSavesWhenTheInspectorGoes() async throws {
        let page = try await open()
        let box = try #require(frame(of: .widget(1), page))
        click(page, at: CGPoint(x: box.midX, y: box.midY))
        var found: NSTextField?
        #expect(await wait(page.window) {
            found = Self.textField("hi", in: page.window.contentView!)
            return found != nil
        })
        let field = try #require(found)
        #expect(page.window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("hello", replacementRange: editor.selectedRange())
        for _ in 0..<10 {
            page.window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        page.model.finishEditing()
        #expect(await wait(page.window) { saved(page).themeEdit("t", "widgets")[1]["opts"]["note"] == .string("hello") })
    }

    /// A value typed for a widget that Remove Widget then takes away goes with it: the widget that moves into its
    /// place keeps where it was.
    @Test func aTypedValueGoesWithItsRemovedWidget() async throws {
        let page = try await open()
        let box = try #require(frame(of: .widget(0), page))
        click(page, at: CGPoint(x: box.midX, y: box.midY))
        var found: NSTextField?
        #expect(await wait(page.window) {
            found = Self.textField("0", in: page.window.contentView!)
            return found != nil
        })
        let field = try #require(found)
        #expect(page.window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("-77", replacementRange: editor.selectedRange())
        for _ in 0..<10 {
            page.window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        // As Remove Widget does: the selection clears, and the widget goes, while the field still has the keyboard.
        page.overlay.delete(nil)
        #expect(await wait(page.window) { saved(page).themeEdit("t", "widgets").array?.count == 1 })
        try await Task.sleep(for: .milliseconds(300))
        page.window.contentView?.layoutSubtreeIfNeeded()
        let moved = saved(page).themeEdit("t", "widgets")[0]
        #expect(moved["anchor"].isNil || moved["anchor"] == .string("top-right"))
        #expect(moved["offset"].isNil || moved["offset"] == .array([.int(-30), .int(30)]))
    }

    /// A drag ends only where the mouse goes up: Escape during one changes nothing.
    @Test func escapeDuringADragChangesNothing() async throws {
        let page = try await open()
        let box = try #require(frame(of: .widget(0), page))
        let start = CGPoint(x: box.midX, y: box.midY)
        page.overlay.mouseDown(with: event(.leftMouseDown, at: start, on: page))
        page.overlay.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: start.x - 100, y: start.y - 100), on: page))
        for _ in 0..<3 {
            press(0x1B, page)
            try await Task.sleep(for: .milliseconds(100))
            page.window.contentView?.layoutSubtreeIfNeeded()
        }
        #expect(page.preview.canvas?.selection == .widget(0))
        #expect(page.model.editingTheme == "t")
        page.overlay.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: start.x - 100, y: start.y - 100), on: page))
        #expect(saved(page).themeEdit("t", "widgets")[0]["offset"] == .array([.int(-100), .int(-100)]))
    }

    /// ⌘. is Escape's twin, which AppKit sends up the responder chain as cancelOperation: during a drag it changes
    /// nothing either. At rest it still clears the selection, then ends Customize.
    @Test func commandPeriodDuringADragChangesNothing() async throws {
        let page = try await open()
        let box = try #require(frame(of: .widget(0), page))
        let start = CGPoint(x: box.midX, y: box.midY), end = CGPoint(x: start.x - 100, y: start.y - 100)
        let commandPeriod = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                             windowNumber: page.window.windowNumber, context: nil, characters: ".",
                                             charactersIgnoringModifiers: ".", isARepeat: false, keyCode: 47)!
        page.overlay.mouseDown(with: event(.leftMouseDown, at: start, on: page))
        page.overlay.mouseDragged(with: event(.leftMouseDragged, at: end, on: page))
        for _ in 0..<2 {
            page.window.sendEvent(commandPeriod)
            try await Task.sleep(for: .milliseconds(100))
            page.window.contentView?.layoutSubtreeIfNeeded()
        }
        #expect(page.preview.canvas?.selection == .widget(0))
        #expect(page.model.editingTheme == "t")
        page.overlay.mouseUp(with: event(.leftMouseUp, at: end, on: page))
        #expect(saved(page).themeEdit("t", "widgets")[0]["offset"] == .array([.int(-100), .int(-100)]))
        page.window.sendEvent(commandPeriod)
        #expect(await wait(page.window) { page.preview.canvas?.selection == nil })
        page.window.sendEvent(commandPeriod)
        #expect(await wait(page.window) { page.model.editingTheme == nil })
    }

    private static func textField(_ value: String, in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable, field.stringValue == value { return field }
        for child in view.subviews { if let match = textField(value, in: child) { return match } }
        return nil
    }

    private func click(_ page: Page, at point: CGPoint) {
        page.overlay.mouseDown(with: event(.leftMouseDown, at: point, on: page))
        page.overlay.mouseUp(with: event(.leftMouseUp, at: point, on: page))
    }

    @Test func voiceOverSeesAGroupOfButtonsThatSelect() async throws {
        let page = try await open()
        let overlay = page.overlay
        // Both widgets and the password field, laid out.
        #expect(await wait(page.window) { page.preview.editables.count == 3 })
        #expect(overlay.isAccessibilityElement() && overlay.accessibilityRole() == .group && overlay.accessibilityLabel() == "Lock Screen")
        let elements = try #require(overlay.accessibilityChildren() as? [CanvasItemElement])
        let again = try #require(overlay.accessibilityChildren() as? [CanvasItemElement])
        // The same objects while nothing changes: AppKit leaves them to the view that made them.
        #expect(elements.count == 3 && zip(elements, again).allSatisfy { $0 === $1 })
        #expect(elements.allSatisfy { ($0.accessibilityParent() as? CanvasOverlay) === overlay && $0.accessibilityRole() == .button })
        #expect(elements.map { $0.accessibilityLabel() ?? "" }.sorted() == ["Box", "Box", "Password Field"])
        // Buttons that work, none of them selected yet.
        #expect(elements.allSatisfy { $0.isAccessibilityEnabled() && !$0.isAccessibilitySelected() })
        let box = try #require(elements.first { $0.item == .widget(1) })
        #expect(box.accessibilityPerformPress())
        #expect(await wait(page.window) { page.preview.canvas?.selection == .widget(1) })
        #expect(elements.filter { $0.isAccessibilitySelected() }.map(\.item) == [.widget(1)])
    }

    /// VoiceOver outlines each item where it is drawn, and finds it there: the canvas is flipped, the screen is not.
    @Test func voiceOverFindsEachItemWhereItIsDrawn() async throws {
        let page = try await open()
        #expect(await wait(page.window) { page.preview.editables.count == 3 })
        let elements = try #require(page.overlay.accessibilityChildren() as? [CanvasItemElement])
        let scale = page.overlay.bounds.width / ThemePreviewView.layoutSize.width
        for element in elements {
            let layout = try #require(frame(of: element.item, page))
            let drawn = CGRect(x: layout.minX * scale, y: layout.minY * scale, width: layout.width * scale, height: layout.height * scale)
            let onScreen = page.window.convertToScreen(page.overlay.convert(drawn, to: nil))
            #expect(element.accessibilityFrame().contains(onScreen), "\(element.item)")
            #expect(page.overlay.accessibilityHitTest(CGPoint(x: onScreen.midX, y: onScreen.midY)) as? CanvasItemElement === element, "\(element.item)")
        }
    }

    /// While it is a canvas, VoiceOver finds only the canvas's buttons there, top to bottom: the live screen under them
    /// has a password field that takes nothing.
    @Test func voiceOverReadsOnlyTheCanvasTopToBottom() async throws {
        let page = try await open()
        #expect(await wait(page.window) { page.preview.editables.count == 3 })
        let children = try #require(page.preview.accessibilityChildren())
        #expect(children.count == 1 && children.first as? CanvasOverlay === page.overlay)
        let elements = try #require(page.overlay.accessibilityChildren() as? [CanvasItemElement])
        // The box at the top right, the one in the center, and the password field at the bottom.
        #expect(elements.map(\.item) == [.widget(1), .widget(0), .passwordField])
    }

    @Test func editDeleteRemovesTheSelectedWidgetOnly() async throws {
        let page = try await open()
        let delete = NSMenuItem(title: "Delete", action: #selector(CanvasOverlay.delete(_:)), keyEquivalent: "")
        #expect(!page.overlay.validateMenuItem(delete))
        #expect(await wait(page.window) { frame(of: .passwordField, page) != nil })
        let field = try #require(frame(of: .passwordField, page))
        click(page, at: CGPoint(x: field.midX, y: field.midY))
        #expect(await wait(page.window) { page.preview.canvas?.selection == .passwordField })
        #expect(!page.overlay.validateMenuItem(delete))
        let box = try #require(frame(of: .widget(1), page))
        click(page, at: CGPoint(x: box.midX, y: box.midY))
        #expect(await wait(page.window) { page.preview.canvas?.selection == .widget(1) })
        #expect(page.overlay.validateMenuItem(delete))
        page.overlay.delete(nil)
        #expect(await wait(page.window) { page.preview.canvas?.selection == nil })
        #expect(saved(page).themeEdit("t", "widgets").array?.count == 1)
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

    /// Theme t from `source`, in the editor, with Edit ▸ Undo steps made one at a time.
    @MainActor
    private struct Fixture {
        let sandbox: Sandbox
        let model: AppModel
        let editing: ThemeEditing
        let undo = UndoManager()

        init(_ source: String) async throws {
            sandbox = try Sandbox()
            try sandbox.write("themes/t.lua", source)
            try sandbox.write("plugin/w.lua", "locky.widget.define('w', { render = function() end })")
            _ = NSApplication.shared
            model = AppModel(store: SettingsStore(config: sandbox.config))
            editing = ThemeEditing(theme: Inspection.ThemeInfo(id: "t", name: "t"), model: model)
            await editing.load()
            undo.groupsByEvent = false
            editing.undoManager = undo
        }

        func step(_ change: () -> Void) {
            undo.beginUndoGrouping()
            change()
            undo.endUndoGrouping()
        }

        var edit: LuaValue { model.store.settings["themes"]["t"] }
    }

    @Test func revertToOriginalTakesEveryChangeBackInOneStep() async throws {
        let editor = try await Fixture("return { widgets = { { 'w', anchor = 'top' } } }")
        let (editing, undo) = (editor.editing, editor.undo)
        #expect(!editing.isChanged)
        editor.step { editing.move(.widget(0), anchor: .topLeft, offset: CGPoint(x: 30, y: 30)) }
        #expect(editing.isChanged)
        editor.step { editing.setAuth(anchor: "top", x: 0, y: 60) }
        let changed = editor.edit

        editor.step { editing.revertToOriginal() }
        #expect(!editing.isChanged && editor.edit.isNil)
        #expect(undo.undoMenuItemTitle == "Undo Revert to Original")
        undo.undo()
        // One step: the move and the password field's place are both back.
        #expect(editor.edit == changed)
        #expect(undo.undoMenuItemTitle == "Undo Move Password Field")
        undo.redo()
        #expect(editor.edit.isNil)
        undo.undo()
        #expect(editor.edit == changed)
    }

    @Test func resetPutsAnItemBackWhereTheThemeHasIt() async throws {
        let editor = try await Fixture("""
        return { auth = { anchor = 'bottom', offset = { 0, -60 } }, widgets = { { 'w', anchor = 'top-right', offset = { -30, 30 } } } }
        """)
        let (editing, undo) = (editor.editing, editor.undo)
        #expect(!editing.isMoved(.widget(0)) && !editing.isMoved(.passwordField))
        editor.step { editing.move(.widget(0), anchor: .center, offset: CGPoint(x: 10, y: 20)) }
        #expect(editing.isMoved(.widget(0)))
        editor.step { editing.resetPlace(.widget(0)) }
        let placement = try #require(editing.placements.first)
        #expect(placement.anchor == "top-right" && placement.x == -30 && placement.y == 30)
        #expect(!editing.isMoved(.widget(0)))
        #expect(undo.undoMenuItemTitle == "Undo Reset Position")
        undo.undo()
        #expect(editing.isMoved(.widget(0)) && editing.placements.first?.anchor == "center")
        undo.redo()

        // A widget the window added has no place of the theme's to go back to.
        var added = 0
        editor.step { added = editing.add("w") }
        #expect(editing.themePlace(editing.placements[added]) == nil && !editing.isMoved(.widget(added)))

        editor.step { editing.setAuth(anchor: "top", x: 0, y: 90) }
        #expect(editing.isMoved(.passwordField))
        editor.step { editing.resetPlace(.passwordField) }
        #expect(editor.edit["auth"].isNil && !editing.isMoved(.passwordField))
        let place = editing.authPlace
        #expect(place.anchor == "bottom" && place.x == 0 && place.y == -60)
        #expect(undo.undoMenuItemTitle == "Undo Reset Position")
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
