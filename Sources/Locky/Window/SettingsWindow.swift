import AppKit
import SwiftUI

/// The Settings window, as macOS apps have it: a toolbar of panes (General, Plugins, Lua Config), the pane's name as the
/// title, a fixed width and a height per pane, minimize and zoom dimmed, and the last pane again on the next open.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let tabs: SettingsTabViewController
    private let onClose: () -> Void
    /// The first open centers the window; later ones leave it where it was.
    private var opened = false

    /// The pane shown last ("settingsPane"), else General.
    static var lastPane: AppModel.Section {
        UserDefaults.standard.string(forKey: SettingsTabViewController.paneKey).flatMap(AppModel.Section.init(rawValue:))
            .flatMap { AppModel.Section.panes.contains($0) ? $0 : nil } ?? .settings
    }

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.onClose = onClose
        tabs = SettingsTabViewController(model: model)
        let general = SettingsTabViewController.size(of: .settings)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: general), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.toolbarStyle = .preference
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.contentViewController = tabs
        // The tab view controller sized the window to its own view.
        window.setContentSize(general)
        window.title = AppModel.Section.settings.title
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Shows `pane`, or the pane shown last. `behind` keeps the window behind other windows, for screenshots.
    func show(_ pane: AppModel.Section?, behind: Bool) {
        guard let window else { return }
        tabs.select(pane ?? Self.lastPane)
        if !opened {
            opened = true
            window.center()
        }
        if behind {
            window.orderBack(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        // No text field starts out focused with its text selected.
        window.makeFirstResponder(nil)
    }

    /// A text field that has the keyboard, such as the lock screen message, saves first: it saves when focus leaves.
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        onClose()
    }
}

/// The Settings window's panes. With the toolbar style, the tab view controller puts them in the window's toolbar.
final class SettingsTabViewController: NSTabViewController {
    static let paneKey = "settingsPane"

    init(model: AppModel) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        add(.settings, SettingsPage(model: model))
        add(.plugins, PluginsPage(model: model))
        add(.config, ConfigPage(model: model))
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A pane's content size: one width for all, and a height that fits the pane. General fits its tallest usual state
    /// without scrolling: a Touch ID Mac that has not allowed Accessibility, as every new install starts, with the Open at
    /// login subtitle (744.5 pt measured).
    static func size(of pane: AppModel.Section) -> CGSize {
        switch pane {
        case .plugins: CGSize(width: 640, height: 520)
        case .config: CGSize(width: 640, height: 360)
        default: CGSize(width: 640, height: 745)
        }
    }

    func select(_ pane: AppModel.Section) {
        if let index = tabViewItems.firstIndex(where: { $0.identifier as? String == pane.rawValue }) { selectedTabViewItemIndex = index }
    }

    /// A pane's own toolbar and title never reach the window: a child hosting controller bridges nothing.
    private func add(_ pane: AppModel.Section, _ root: some View) {
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        hosting.preferredContentSize = Self.size(of: pane)
        hosting.title = pane.title
        let item = NSTabViewItem(viewController: hosting)
        item.identifier = pane.rawValue
        item.label = pane.title
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: nil)
        addTabViewItem(item)
    }

    /// The window takes the pane's title and size, with its top edge where it was; the resize is at once with Reduce
    /// Motion. The first selection, while the window is put together, changes nothing.
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let window = view.window, let pane = (tabViewItem?.identifier as? String).flatMap(AppModel.Section.init(rawValue:)) else { return }
        window.title = pane.title
        let old = window.frame
        var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: Self.size(of: pane)))
        frame.origin = CGPoint(x: old.minX, y: old.maxY - frame.height)
        window.setFrame(frame, display: true, animate: window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if !AppDelegate.isTool { UserDefaults.standard.set(pane.rawValue, forKey: Self.paneKey) }
        window.makeFirstResponder(nil)
    }
}
