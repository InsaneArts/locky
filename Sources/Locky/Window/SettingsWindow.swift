import AppKit
import SwiftUI

/// The Settings window, as macOS apps have it: a toolbar of panes (General, Lock Screen, Unlock, Customization,
/// Plugins), the pane's name as the title, a fixed width and a height per pane, minimize and zoom dimmed, and the last
/// pane again on the next open.
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
    /// Tells when the selected pane's rows change height (watchRows).
    private var rowsObserver: NSObjectProtocol?

    init(model: AppModel) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        add(.settings, SettingsPage(model: model))
        add(.lockScreen, LockScreenPage(model: model))
        add(.unlock, UnlockPage(model: model))
        add(.customization, CustomizationPage(model: model))
        add(.plugins, PluginsPage(model: model))
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Every pane's width: the longest row, "When the screen saver starts or the display turns off", and its switch
    /// fit on one line.
    static let width: CGFloat = 560

    /// A pane's content size until its rows are laid out, and Plugins' always, which lays itself out: the height of
    /// the pane's usual rows. A pane that shows gives the window the height of its rows themselves (rowsHeight), so it
    /// neither scrolls nor leaves empty space under them. A shorter screen gets the screen's height (fit).
    static func size(of pane: AppModel.Section) -> CGSize {
        let height: CGFloat = switch pane {
        case .lockScreen: 412
        case .unlock: 139
        case .customization: 286
        case .plugins: 520
        default: 430
        }
        return CGSize(width: width, height: height)
    }

    private var selectedPane: AppModel.Section? {
        (tabViewItems[selectedTabViewItemIndex].identifier as? String).flatMap(AppModel.Section.init(rawValue:))
    }

    /// The selected pane's form: SwiftUI's scroll view, whose document is as tall as the rows, whatever the window's
    /// height. nil for Plugins, and until the pane has laid itself out.
    private var form: NSScrollView? {
        func first(in view: NSView) -> NSScrollView? { (view as? NSScrollView) ?? view.subviews.lazy.compactMap(first(in:)).first }
        guard selectedPane != .plugins, let view = tabViewItems[selectedTabViewItemIndex].viewController?.view else { return nil }
        view.layoutSubtreeIfNeeded()
        return first(in: view)
    }

    /// The height of the selected pane's rows, as whole points: a window's frame has no half points.
    private var rowsHeight: CGFloat? {
        form?.documentView.flatMap { $0.frame.height > 0 ? $0.frame.height.rounded(.up) : nil }
    }

    /// Keeps the window as tall as the selected pane's rows while they come and go: the camera's row, the photos, the
    /// lock animation's preview, init.lua's problems. The window follows over the 0.2 s the rows take, and at once with
    /// Reduce Motion. A pane whose form is not there yet is looked at again on the next turn of the run loop, and the
    /// window, which has the pane's usual size until then, gets the height of its rows.
    private func watchRows(again: Bool = true) {
        rowsObserver.map(NotificationCenter.default.removeObserver)
        rowsObserver = nil
        guard let document = form?.documentView else {
            if again, selectedPane != .plugins { DispatchQueue.main.async { [weak self] in self?.watchRows(again: false) } }
            return
        }
        document.postsFrameChangedNotifications = true
        rowsObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: document, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.view.window else { return }
                self.fit(window, animate: window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
        }
        if !again, let window = view.window { fit(window, animate: false) }
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
    /// Animated, the window takes 0.2 s, easing out, whatever the distance: AppKit's own resize takes longer the
    /// farther the edge goes, and holds the main thread meanwhile.
    func place(_ window: NSWindow, _ frame: CGRect, in visible: CGRect?, animate: Bool) {
        let fitted = Self.fitted(frame, in: visible)
        guard fitted != window.frame else { return }
        tabViewItems[selectedTabViewItemIndex].viewController?.preferredContentSize = window.contentRect(forFrameRect: fitted).size
        guard animate else { return window.setFrame(fitted, display: true) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = Motion.easeOut
            window.animator().setFrame(fitted, display: true)
        }
    }

    /// Gives the window the selected pane's size, as tall as its rows once they are laid out, with its top edge where it
    /// was, fitted to its screen.
    func fit(_ window: NSWindow, animate: Bool) {
        guard let pane = selectedPane else { return }
        var size = Self.size(of: pane)
        if let rowsHeight { size.height = rowsHeight }
        var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
        frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        place(window, frame, in: (window.screen ?? NSScreen.main)?.visibleFrame, animate: animate)
    }

    func select(_ pane: AppModel.Section) {
        if let index = tabViewItems.firstIndex(where: { $0.identifier as? String == pane.rawValue }) { selectedTabViewItemIndex = index }
        watchRows()
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
        watchRows()
        if !AppDelegate.isTool { UserDefaults.standard.set(pane.rawValue, forKey: Self.paneKey) }
        window.makeFirstResponder(nil)
    }
}
