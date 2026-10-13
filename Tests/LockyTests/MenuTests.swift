import AppKit
import Carbon
import Testing
@testable import Locky

/// The main menu: every command in its place, with its shortcut, as menus.md's Layout table has them.
@MainActor
@Suite struct MenuTests {
    /// Installs Locky's menus on the app, hands over the main menu, and puts the app's menus back.
    private func installed(_ check: (NSMenu) throws -> Void) throws {
        let app = NSApplication.shared
        let saved = (main: app.mainMenu, services: app.servicesMenu, windows: app.windowsMenu, help: app.helpMenu)
        defer {
            app.mainMenu = saved.main
            app.servicesMenu = saved.services
            app.windowsMenu = saved.windows
            app.helpMenu = saved.help
        }
        MainMenu.install(in: app)
        try check(try #require(app.mainMenu))
    }

    private func menu(_ title: String, in main: NSMenu) throws -> NSMenu {
        try #require(main.items.first { $0.title == title }?.submenu)
    }

    /// Every item, the submenus' included.
    private func items(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) }
    }

    /// A menu's titles with "—" for each separator, as the Layout table writes them.
    private func layout(_ title: String, in main: NSMenu) throws -> [String] {
        try menu(title, in: main).items.map { $0.isSeparatorItem ? "—" : $0.title }
    }

    /// "⇧⌘Z": an item's key equivalent as the menu shows it, where an uppercase key adds Shift. nil without one.
    private func shortcut(_ item: NSMenuItem) -> String? {
        let key = item.keyEquivalent
        guard !key.isEmpty else { return nil }
        var flags = item.keyEquivalentModifierMask
        if key != key.lowercased() { flags.insert(.shift) }
        return Shortcut.Modifiers(flags).symbols + key.uppercased()
    }

    @Test func theSixMenusComeInTheStandardOrder() throws {
        try installed { main throws in
            #expect(main.items.map(\.title) == ["Locky", "File", "Edit", "View", "Window", "Help"])
            // AppKit fills these: the window list and the help search field. It also keeps the first Services menu it is
            // given and ignores later ones, so in a test process that installs more than once only the item is checked.
            #expect(NSApp.windowsMenu === (try menu("Window", in: main)))
            #expect(NSApp.helpMenu === (try menu("Help", in: main)))
            #expect((try menu("Locky", in: main)).items.first { $0.title == "Services" }?.submenu != nil)
        }
    }

    @Test func eachMenuHoldsTheLayoutTablesItems() throws {
        try installed { main throws in
            #expect(try layout("Locky", in: main) == ["About Locky", "—", "Settings…", "—", "Lock Now", "—", "Services", "—", "Hide Locky",
                                                      "Hide Others", "Show All", "—", "Quit Locky"])
            #expect(try layout("File", in: main) == ["Import Theme…", "—", "Customize Theme…", "Use Theme", "Preview Theme", "—",
                                                     "Duplicate Theme…", "Export Theme…", "Revert to Original", "Move to Trash", "—", "Close"])
            #expect(try layout("Edit", in: main) == ["Undo", "Redo", "—", "Cut", "Copy", "Paste", "Delete", "Select All", "—", "Add Widget…"])
            #expect(try layout("View", in: main) == ["Show Grid", "Show Inspector", "—", "Enter Full Screen"])
            // AppKit lists any titled window on screen after these, at once, so a window from another test may follow.
            #expect(try layout("Window", in: main).prefix(4) == ["Minimize", "Zoom", "—", "Bring All to Front"])
            #expect(try layout("Help", in: main) == ["Welcome to Locky"])
        }
    }

    @Test(arguments: [
        ("⌘,", #selector(AppDelegate.openSettings(_:))), ("⌘H", #selector(NSApplication.hide(_:))),
        ("⌥⌘H", #selector(NSApplication.hideOtherApplications(_:))), ("⌘Q", #selector(NSApplication.terminate(_:))),
        ("⌘W", #selector(NSWindow.performClose(_:))), ("⌘Z", Selector(("undo:"))), ("⇧⌘Z", Selector(("redo:"))),
        ("⌘X", #selector(NSText.cut(_:))), ("⌘C", #selector(NSText.copy(_:))), ("⌘V", #selector(NSText.paste(_:))),
        ("⌘A", #selector(NSText.selectAll(_:))), ("⌥⌘I", #selector(LockyWindowController.toggleInspector(_:))),
        ("⌃⌘F", #selector(NSWindow.toggleFullScreen(_:))), ("⌘M", #selector(NSWindow.performMiniaturize(_:))),
    ] as [(String, Selector)])
    func aShortcutSendsItsCommand(_ keys: String, _ action: Selector) throws {
        try installed { main in
            #expect(items(main).filter { shortcut($0) == keys }.map(\.action) == [action])
        }
    }

    /// The app menu's Lock Now: in reach when the menu bar hides the status item.
    @Test func lockNowFollowsSettings() throws {
        try installed { main in
            let locky = try menu("Locky", in: main).items
            let settings = try #require(locky.firstIndex { $0.action == #selector(AppDelegate.openSettings(_:)) })
            try #require(locky.count > settings + 2)
            #expect(locky[settings + 1].isSeparatorItem)
            let lockNow = locky[settings + 2]
            #expect(lockNow.title == "Lock Now" && lockNow.action == #selector(AppDelegate.lockNow(_:)) && lockNow.keyEquivalent.isEmpty)
        }
    }

    @Test func lockNowShowsTheRecordedShortcut() throws {
        try installed { main in
            let lockNow = try #require(items(main).first { $0.action == #selector(AppDelegate.lockNow(_:)) })
            MainMenu.setLockNowShortcut(Shortcut(keyCode: UInt16(kVK_ANSI_L), modifiers: [.control, .option, .command]))
            #expect(lockNow.keyEquivalent == "l" && lockNow.keyEquivalentModifierMask == [.control, .option, .command])
            MainMenu.setLockNowShortcut(nil)
            #expect(lockNow.keyEquivalent.isEmpty)
        }
    }

    @Test func theFileMenuHoldsTheThemeCommands() throws {
        typealias Themes = LockyWindowController
        try installed { main in
            let commands = try menu("File", in: main).items.prefix { $0.action != #selector(NSWindow.performClose(_:)) }.filter { !$0.isSeparatorItem }
            #expect(commands.map(\.title) == ["Import Theme…", "Customize Theme…", "Use Theme", "Preview Theme", "Duplicate Theme…",
                                              "Export Theme…", "Revert to Original", "Move to Trash"])
            #expect(commands.map(\.action) == [#selector(Themes.importTheme(_:)), #selector(Themes.customizeTheme(_:)),
                                               #selector(Themes.useTheme(_:)), #selector(Themes.previewTheme(_:)),
                                               #selector(Themes.duplicateTheme(_:)), #selector(Themes.exportTheme(_:)),
                                               #selector(Themes.revertTheme(_:)), #selector(Themes.trashTheme(_:))])
            // No target: they reach the Themes window's controller only while that window is key, and are dimmed otherwise.
            #expect(commands.allSatisfy { $0.target == nil })
        }
    }

    /// No pages and no sidebar are left to show.
    @Test func theViewMenuNamesNoPage() throws {
        try installed { main in
            let titles = try menu("View", in: main).items.map(\.title)
            #expect(titles.allSatisfy { !["Show Sidebar", "Themes", "Settings", "Plugins"].contains($0) })
        }
    }

    /// Menus show icons for key actions on macOS 26: Locky's own commands carry their symbols, and Settings… the gear
    /// AppKit gives its own Settings selectors.
    @available(macOS 26, *)
    @Test func lockysOwnCommandsCarryTheirSymbols() throws {
        typealias Themes = LockyWindowController
        try installed { main in
            let own = [#selector(AppDelegate.lockNow(_:)), #selector(Themes.importTheme(_:)), #selector(Themes.customizeTheme(_:)),
                       #selector(Themes.useTheme(_:)), #selector(Themes.previewTheme(_:)), #selector(Themes.duplicateTheme(_:)),
                       #selector(Themes.exportTheme(_:)), #selector(Themes.revertTheme(_:)), #selector(Themes.trashTheme(_:)),
                       #selector(Themes.addWidget(_:)), #selector(Themes.toggleGrid(_:)), #selector(Themes.toggleInspector(_:)),
                       #selector(AppDelegate.openWelcome(_:)), #selector(AppDelegate.openSettings(_:))]
            let all = items(main)
            for action in own {
                #expect(all.first { $0.action == action }?.image != nil, "\(action)")
            }
        }
    }
}
