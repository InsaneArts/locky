import AppKit
import SwiftUI

/// The Themes window: the gallery, and Customize for one theme. It owns its size, so no page grows or shrinks it.
@MainActor
final class LockyWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let model: AppModel
    private let onClose: () -> Void
    private var keyboard: NSKeyValueObservation?

    /// The smallest content size. A size asked for (`Locky window --size`) never goes under it.
    static let minimumSize = CGSize(width: 980, height: 640)

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1240, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        let hosting = NSHostingController(rootView: ThemesPage(model: model))
        // The default, .standardBounds, lets the page grow the window to fit it.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.contentMinSize = Self.minimumSize
        window.setContentSize(CGSize(width: 1240, height: 780))
        // A screenshot run sizes the window as it needs; it must not become the user's saved size.
        if AppDelegate.isTool {
            window.center()
        } else {
            window.setFrameAutosaveName("LockyWindow")
            if !window.setFrameUsingName("LockyWindow") { window.center() }
        }
        super.init(window: window)
        window.delegate = self
        // On the main actor's next turn, once AppKit has finished the change.
        keyboard = window.observe(\.firstResponder) { [weak self] _, _ in
            Task { @MainActor in self?.returnKeyboardToList() }
        }
    }

    /// The gallery's list has the keyboard whenever nothing else in the window does, so the arrow keys and Return work
    /// without a click. When Customize ends, its canvas has the keyboard, and leaves the window a moment after the
    /// gallery is back: AppKit then gives the keyboard to the window, for nobody.
    private func returnKeyboardToList() {
        guard let window, window.firstResponder === window, model.editingTheme == nil,
              let list = Self.list(in: window.contentView) else { return }
        window.makeFirstResponder(list)
    }

    /// The first list that shows in `view`: SwiftUI keeps a page it replaced in the window, invisible, for a moment.
    private static func list(in view: NSView?) -> NSTableView? {
        guard let view, !view.isHidden, view.alphaValue > 0 else { return nil }
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { list(in: $0) }.first
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Brings the window up. `behind` keeps it behind other windows, and `size` sets its content size: both for
    /// screenshots.
    func show(behind: Bool, size: CGSize?) {
        guard let window else { return }
        if let size { window.setContentSize(Self.clamped(size)) }
        if behind {
            window.orderBack(nil)
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// `size`, at least the minimum: the window owns its size, so `setContentSize` does not hold it to the minimum.
    static func clamped(_ size: CGSize) -> CGSize {
        CGSize(width: max(size.width, minimumSize.width), height: max(size.height, minimumSize.height))
    }

    /// The next open shows the gallery.
    func windowWillClose(_ notification: Notification) {
        model.finishEditing()
        onClose()
    }

    // MARK: Menu commands

    // The main menu's items for these have no target: they reach this controller while the Themes window is key.

    @objc func importTheme(_ sender: Any?) {
        model.finishEditing()
        model.importing = true
    }

    @objc func customizeTheme(_ sender: Any?) { model.customize(model.activeTheme) }

    @objc func useTheme(_ sender: Any?) {
        if let id = model.editingTheme { model.use(id) }
    }

    /// The theme in Customize, else the theme in use.
    @objc func previewTheme(_ sender: Any?) { model.preview(model.editingTheme) }

    /// The gallery's Schedule popover, from its toolbar item.
    @objc func scheduleThemes(_ sender: Any?) { model.scheduling = true }

    // The editor runs these: they need its state.
    @objc func duplicateTheme(_ sender: Any?) { model.editorRequest = .duplicate }
    @objc func exportTheme(_ sender: Any?) { model.editorRequest = .export }
    @objc func revertTheme(_ sender: Any?) { model.editorRequest = .revert }

    @objc func trashTheme(_ sender: Any?) {
        guard let id = model.editingTheme, let window else { return }
        do {
            try model.trash(id)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Can't Move the Theme to the Trash"
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window)
        }
    }

    @objc func addWidget(_ sender: Any?) { model.addingWidget = true }

    /// The editor's @AppStorage("themeEditorGrid") follows.
    @objc func toggleGrid(_ sender: Any?) { Self.flip(Self.gridKey, default: false) }
    /// The editor's @AppStorage("customizeInspector") follows.
    @objc func toggleInspector(_ sender: Any?) { Self.flip(Self.inspectorKey, default: true) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // A sheet over the window, such as Add Widget or an alert, holds the window until it closes: a theme command would
        // act under it, or wait behind it.
        if window?.attachedSheet != nil, menuItem.action.map(Self.themeCommands.contains) == true { return false }
        let editing = model.editingTheme
        // A theme command needs a theme that the config's read lists. Until the read does, Customize shows a spinner, and
        // an id from a request may name no theme at all.
        let listed = editing.flatMap { model.inspection.theme($0) == nil ? nil : $0 }
        // Customize edits only a theme that loads: for one that does not, it shows why, and only Move to Trash applies.
        let loads = listed.flatMap { model.inspection.theme($0)?.error == nil ? $0 : nil }
        switch menuItem.action {
        case #selector(customizeTheme(_:)):
            return editing == nil && model.inspection.loaded && model.inspection.theme(model.activeTheme).map { $0.error == nil } == true
        case #selector(useTheme(_:)):
            return loads != nil && loads != model.activeTheme
        case #selector(previewTheme(_:)):
            // The gallery previews the theme in use.
            return editing == nil || loads != nil
        case #selector(scheduleThemes(_:)):
            // The popover hangs from the gallery's toolbar.
            return editing == nil
        case #selector(duplicateTheme(_:)), #selector(addWidget(_:)):
            return loads != nil
        case #selector(exportTheme(_:)):
            return loads.map { model.canExport($0) } == true
        case #selector(revertTheme(_:)):
            return loads.map { !model.store.settings["themes"][$0].isNil } == true
        case #selector(trashTheme(_:)):
            return listed.map { model.canTrash($0) } == true
        case #selector(toggleGrid(_:)):
            menuItem.title = Self.isOn(Self.gridKey, default: false) ? "Hide Grid" : "Show Grid"
            return loads != nil
        case #selector(toggleInspector(_:)):
            menuItem.title = Self.isOn(Self.inspectorKey, default: true) ? "Hide Inspector" : "Show Inspector"
            return loads != nil
        default:
            return true
        }
    }

    /// The commands that act on a theme, which wait while a sheet is over the window.
    private static let themeCommands: Set<Selector> = [
        #selector(importTheme(_:)), #selector(customizeTheme(_:)), #selector(useTheme(_:)), #selector(previewTheme(_:)),
        #selector(scheduleThemes(_:)), #selector(duplicateTheme(_:)), #selector(exportTheme(_:)), #selector(revertTheme(_:)),
        #selector(trashTheme(_:)), #selector(addWidget(_:)),
    ]

    private static let gridKey = "themeEditorGrid"
    private static let inspectorKey = "customizeInspector"

    private static func isOn(_ key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    private static func flip(_ key: String, default fallback: Bool) {
        UserDefaults.standard.set(!isOn(key, default: fallback), forKey: key)
    }
}
