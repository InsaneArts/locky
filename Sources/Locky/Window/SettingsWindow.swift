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
        // The screen can have changed since the last open, as when the window moved from a short screen to a tall one.
        tabs.fit(window, animate: false)
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

    /// `frame` moved up until its bottom edge is on the screen, and on a screen shorter than it, the screen's height:
    /// AppKit keeps only the top edge of a window that is not resizable on screen. The pane then scrolls.
    static func fitted(_ frame: CGRect, in visible: CGRect?) -> CGRect {
        guard let visible else { return frame }
        var fitted = frame
        fitted.size.height = min(frame.height, visible.height)
        fitted.origin.y = min(max(frame.maxY - fitted.height, visible.minY), visible.maxY - fitted.height)
        return fitted
    }

    /// Gives the window `frame` fitted to `visible`. The pane's preferred size follows the fitted height: AppKit holds
    /// the window to it above the priority of a frame change, so without this a shorter window keeps the pane's height.
    func place(_ window: NSWindow, _ frame: CGRect, in visible: CGRect?, animate: Bool) {
        let fitted = Self.fitted(frame, in: visible)
        tabViewItems[selectedTabViewItemIndex].viewController?.preferredContentSize = window.contentRect(forFrameRect: fitted).size
        window.setFrame(fitted, display: true, animate: animate)
    }

    /// Gives the window the selected pane's size with its top edge where it was, fitted to its screen.
    func fit(_ window: NSWindow, animate: Bool) {
        guard let pane = (tabViewItems[selectedTabViewItemIndex].identifier as? String).flatMap(AppModel.Section.init(rawValue:)) else { return }
        var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: Self.size(of: pane)))
        frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        place(window, frame, in: (window.screen ?? NSScreen.main)?.visibleFrame, animate: animate)
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

    /// The window takes the pane's title and size, with its top edge where it was while it then fits on the screen;
    /// the resize is at once with Reduce Motion. The first selection, while the window is put together, changes nothing.
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let window = view.window, let pane = (tabViewItem?.identifier as? String).flatMap(AppModel.Section.init(rawValue:)) else { return }
        window.title = pane.title
        fit(window, animate: window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if !AppDelegate.isTool { UserDefaults.standard.set(pane.rawValue, forKey: Self.paneKey) }
        window.makeFirstResponder(nil)
    }
}
