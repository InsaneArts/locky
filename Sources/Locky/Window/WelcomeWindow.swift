import AppKit
import SwiftUI

/// The Welcome's own window: fixed size, close button only, titled "Welcome to Locky".
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Hidden in the title bar, the title still names the window in the Window menu and Mission Control.
        window.title = AppModel.Section.welcome.title
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.tabbingMode = .disallowed
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let hosting = NSHostingController(rootView: WelcomeView(model: model, close: { [weak self] in self?.close() }))
        // The view sets the size.
        hosting.sizingOptions = .preferredContentSize
        window.contentViewController = hosting
        window.delegate = self
        // The hosting controller sizes the window only on its next layout, after center() would run on a 0×0 window.
        // So the window takes its size here. The first size gives the view its title-bar inset, and the second size
        // includes that inset.
        window.setContentSize(hosting.preferredContentSize)
        window.setContentSize(hosting.preferredContentSize)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Brings the window up. `behind` keeps it behind other windows, for screenshots.
    func show(behind: Bool) {
        guard let window else { return }
        if behind {
            window.orderBack(nil)
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
