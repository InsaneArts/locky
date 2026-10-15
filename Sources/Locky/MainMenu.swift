import AppKit

/// The menu bar while a Locky window is open: Locky, File, Edit, View, Window, and Help, built at launch and again after
/// each lock. Items without a target go down the key window's responder chain to NSApp and its delegate, so the theme
/// commands reach the Themes window's controller and are dimmed while another window is key. New Theme… reaches the
/// delegate from any window.
@MainActor
enum MainMenu {
    /// Locky › Lock Now: its key equivalent follows the recorded shortcut.
    private static var lockNow: NSMenuItem?
    /// AppKit fills the first Services menu it is given and ignores later ones, so every build uses this one.
    private static let services = NSMenu(title: "Services")

    /// Builds the six menus and sets them on `app`. The end of a lock builds them again: each time a main menu is set,
    /// AppKit adds hidden items to its Edit and View menus, so the old one set again would gain another set.
    static func install(in app: NSApplication) {
        typealias Themes = LockyWindowController
        // A menu has one parent: free the Services menu from the last build, which may still exist.
        services.supermenu?.items.first { $0.submenu === services }?.submenu = nil
        let lock = item("Lock Now", #selector(AppDelegate.lockNow(_:)), symbol: "lock.fill")
        lockNow = lock
        let locky = menu("Locky", [
            item("About Locky", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            // AppKit draws its gear on a Settings item only for its own selectors (orderFrontPreferencesPanel:), so this one
            // names the same symbol.
            item("Settings…", #selector(AppDelegate.openSettings(_:)), key: ",", symbol: "gear"),
            .separator(),
            lock,
            .separator(),
            item(opening: services),
            .separator(),
            item("Hide Locky", #selector(NSApplication.hide(_:)), key: "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Locky", #selector(NSApplication.terminate(_:)), key: "q"),
        ])
        let file = menu("File", [
            item("New Theme…", #selector(AppDelegate.newTheme(_:)), key: "n", symbol: "square.and.pencil"),
            item("Import Theme…", #selector(Themes.importTheme(_:)), symbol: "square.and.arrow.down"),
            .separator(),
            item("Customize Theme…", #selector(Themes.customizeTheme(_:)), symbol: "slider.horizontal.3"),
            item("Use Theme", #selector(Themes.useTheme(_:)), symbol: "checkmark.circle"),
            item("Preview Theme", #selector(Themes.previewTheme(_:)), symbol: "play.rectangle"),
            item("Schedule Themes…", #selector(Themes.scheduleThemes(_:)), symbol: "clock.arrow.2.circlepath"),
            .separator(),
            item("Duplicate Theme…", #selector(Themes.duplicateTheme(_:)), symbol: "plus.square.on.square"),
            item("Export Theme…", #selector(Themes.exportTheme(_:)), symbol: "square.and.arrow.up"),
            item("Revert to Original", #selector(Themes.revertTheme(_:)), symbol: "arrow.uturn.backward"),
            item("Move to Trash", #selector(Themes.trashTheme(_:)), symbol: "trash"),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), key: "w"),
        ])
        // The window answers Undo and Redo, and retitles them ("Undo Move Box"); text views and the canvas answer the rest.
        let edit = menu("Edit", [
            item("Undo", Selector(("undo:")), key: "z"),
            item("Redo", Selector(("redo:")), key: "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), key: "x"),
            item("Copy", #selector(NSText.copy(_:)), key: "c"),
            item("Paste", #selector(NSText.paste(_:)), key: "v"),
            item("Delete", #selector(NSText.delete(_:))),
            item("Select All", #selector(NSText.selectAll(_:)), key: "a"),
            .separator(),
            item("Add Widget…", #selector(Themes.addWidget(_:)), symbol: "plus"),
        ])
        // The Themes window's controller retitles Show Grid and Show Inspector to Hide while they show.
        let view = menu("View", [
            item("Show Grid", #selector(Themes.toggleGrid(_:)), symbol: "grid"),
            item("Show Inspector", #selector(Themes.toggleInspector(_:)), key: "i", modifiers: [.command, .option], symbol: "sidebar.right"),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.control, .command]),
        ])
        let window = menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        let help = menu("Help", [item("Welcome to Locky", #selector(AppDelegate.openWelcome(_:)), symbol: "hand.wave")])
        app.mainMenu = menu("Main Menu", [locky, file, edit, view, window, help].map(item(opening:)))
        // AppKit fills these: the services that apply, the window list, and the help search field.
        app.servicesMenu = services
        app.windowsMenu = window
        app.helpMenu = help
    }

    /// Gives Locky › Lock Now the recorded shortcut, or none.
    static func setLockNowShortcut(_ shortcut: Shortcut?) {
        if let lockNow { setKeyEquivalent(shortcut, on: lockNow) }
    }

    /// Shows `shortcut` as `item`'s key equivalent, or none: Locky › Lock Now and the status menu's Lock Now show it alike.
    static func setKeyEquivalent(_ shortcut: Shortcut?, on item: NSMenuItem) {
        let key = shortcut?.menuKeyEquivalent
        item.keyEquivalent = key?.key ?? ""
        item.keyEquivalentModifierMask = key?.modifiers ?? []
    }

    /// An item. On macOS 26, whose menus show icons for key actions, Locky's own commands carry their symbol; AppKit
    /// gives the standard items theirs.
    private static func item(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command,
                             symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        if #available(macOS 26, *), let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    /// The item that opens `menu`, under the menu's title.
    private static func item(opening menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.items = items
        return menu
    }
}
