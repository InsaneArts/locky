import AppKit
import SwiftUI

/// The Welcome's own window: fixed size, close button only, titled "Welcome to Locky".
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void
    /// The page shown and the switch's memory, until the window closes.
    let visit = WelcomeVisit()

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let window = WelcomeWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
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
        let hosting = NSHostingController(rootView: WelcomeView(model: model, visit: visit, close: { [weak self] in self?.close() }))
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
        // After the first page has set the height that the other pages keep.
        if AppDelegate.isTool { visit.page = Self.firstPage(CommandLine.arguments) }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A screenshot run's page: `--page 2` opens on the second. The first without it, or for a page that does not exist.
    static func firstPage(_ arguments: [String]) -> WelcomeView.Page {
        CLI.value("--page", in: arguments).flatMap(Int.init).flatMap { WelcomeView.Page(rawValue: $0 - 1) } ?? .welcome
    }

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
        visit.end()
        onClose()
    }
}

/// Esc closes the Welcome, as its close button does: Esc that no view takes reaches the window as a key, or from a view
/// that reads keys as cancelOperation, which ⌘. sends too. The Lock Now shortcut's recorder takes Esc itself while it
/// records.
private final class WelcomeWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return super.keyDown(with: event) }
        performClose(nil)
    }

    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}
