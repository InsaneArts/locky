import AppKit
import SwiftUI

/// The Themes window: the gallery, and Customize for one theme. It owns its size, so no page grows or shrinks it.
@MainActor
final class LockyWindowController: NSWindowController, NSWindowDelegate {
    let model: AppModel
    private let onClose: () -> Void

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
}
