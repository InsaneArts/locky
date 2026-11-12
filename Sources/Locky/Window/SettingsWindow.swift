import AppKit
import SwiftUI

/// The pane the Settings window shows, remembered for the next open ("settingsPane").
@MainActor @Observable
final class SettingsVisit {
    var pane = AppModel.Section.settings {
        didSet {
            guard pane != oldValue, !AppDelegate.isTool else { return }
            UserDefaults.standard.set(pane.rawValue, forKey: SettingsWindowController.paneKey)
        }
    }
}

/// The Settings window, as System Settings has it: a sidebar of panes under the app's name, and beside it the pane under
/// its own name. One size for every pane, minimize and zoom dimmed, and the last pane again on the next open.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let paneKey = "settingsPane"
    static let sidebarWidth: CGFloat = 215
    /// The window's content size. The pane beside the sidebar is 565 points wide: its longest row, "When the screen
    /// saver starts or the display turns off", and its switch fit on one line. A pane with more rows than fit scrolls.
    static let size = CGSize(width: 780, height: 580)

    let visit = SettingsVisit()
    private let onClose: () -> Void
    /// The first open centers the window; later ones leave it where it was.
    private var opened = false

    /// The pane shown last, else General.
    static var lastPane: AppModel.Section {
        UserDefaults.standard.string(forKey: paneKey).flatMap(AppModel.Section.init(rawValue:))
            .flatMap { AppModel.Section.panes.contains($0) ? $0 : nil } ?? .settings
    }

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: SettingsView(model: model, visit: visit))
        // The default, .standardBounds, lets a pane grow the window to fit it.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(Self.size)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `frame` moved up until its bottom edge is on the screen, and on a screen shorter than it, the screen's height:
    /// AppKit keeps only the top edge of a window that is not resizable on screen. The pane then scrolls.
    static func fitted(_ frame: CGRect, in visible: CGRect?) -> CGRect {
        guard let visible else { return frame }
        var fitted = frame
        fitted.size.height = min(frame.height, visible.height)
        fitted.origin.y = min(max(frame.maxY - fitted.height, visible.minY), visible.maxY - fitted.height)
        return fitted
    }

    /// Shows `pane`, or the pane shown last. `behind` keeps the window behind other windows, for screenshots.
    func show(_ pane: AppModel.Section?, behind: Bool) {
        guard let window else { return }
        visit.pane = pane ?? Self.lastPane
        if !opened {
            opened = true
            window.center()
        }
        // The screen can have changed since the last open, as when the window moved from a short screen to a tall one.
        var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: Self.size))
        frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(Self.fitted(frame, in: (window.screen ?? NSScreen.main)?.visibleFrame), display: true)
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

/// The Settings window's content: the sidebar and the pane it selects. A pane change is at once, with no animation: the
/// arrow keys change it too.
struct SettingsView: View {
    let model: AppModel
    let visit: SettingsVisit

    var body: some View {
        // The sidebar always shows: nothing hides it, and nothing drags it to another width.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // A click on the list's empty part selects nothing: the pane stays.
            List(selection: Binding<AppModel.Section?>(get: { visit.pane }, set: { if let pane = $0 { visit.pane = pane } })) {
                ForEach(AppModel.Section.panes) { pane in
                    HStack(spacing: 8) {
                        PaneIcon(pane: pane)
                        Text(pane.title)
                    }
                    .padding(.vertical, 3)
                    .tag(pane)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { AppHeader() }
            // Before the width: after it, this modifier drops the width, and the sidebar has its narrowest one.
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(SettingsWindowController.sidebarWidth)
        } detail: {
            pane
                .navigationTitle(visit.pane.title)
        }
    }

    @ViewBuilder private var pane: some View {
        switch visit.pane {
        case .lockScreen: LockScreenPage(model: model)
        case .unlock: UnlockPage(model: model)
        case .customization: CustomizationPage(model: model)
        case .plugins: PluginsPage(model: model)
        default: SettingsPage(model: model)
        }
    }
}

/// The app's icon, name, and version, over the sidebar's panes.
private struct AppHeader: View {
    /// nil from the source tree, where no bundle names a version.
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Locky")
                    .font(.headline)
                if let version {
                    Text("Version \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
}

/// A pane's symbol in white on a tile of the pane's color, as System Settings draws its panes.
private struct PaneIcon: View {
    let pane: AppModel.Section

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.gradient)
            .frame(width: 24, height: 24)
            .overlay {
                Image(systemName: pane.symbol)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    private var tint: Color {
        switch pane {
        case .lockScreen: .blue
        case .unlock: .green
        case .customization: .orange
        case .plugins: .purple
        default: .gray
        }
    }
}
