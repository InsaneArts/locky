import AppKit
import SwiftUI

/// The Locky window: the dashboard, themes, plugins, the config, settings, and the first launch's Welcome. While it is open, Locky shows
/// in the Dock and the app switcher like any app; when it closes, Locky goes back to the menu bar only.
@MainActor
final class LockyWindowController: NSWindowController, NSWindowDelegate {
    let model: AppModel

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1240, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentMinSize = CGSize(width: 980, height: 640)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.contentViewController = NSHostingController(rootView: MainView(model: model))
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

    /// Brings the window up at `section`. `behind` keeps it behind other windows, and `size` sets its content
    /// size: both for screenshots.
    func show(_ section: AppModel.Section? = nil, behind: Bool = false, size: CGSize? = nil) {
        if let section { model.section = section }
        model.startWatching()
        model.refresh()
        guard let window else { return }
        if let size { window.setContentSize(size) }
        if behind {
            window.orderBack(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        model.stopWatching()
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MainView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(AppModel.Section.allCases.filter { $0 != .welcome }, selection: Binding(get: { model.section }, set: { if let section = $0 { model.section = section } })) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(badge(for: section))
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            page
                .navigationTitle(model.section.title)
        }
    }

    @ViewBuilder private var page: some View {
        switch model.section {
        case .dashboard: DashboardPage(model: model)
        case .themes: ThemesPage(model: model)
        case .widgets: WidgetsPage(model: model)
        case .plugins: PluginsPage(model: model)
        case .config: ConfigPage(model: model)
        case .settings: SettingsPage(model: model)
        case .welcome: WelcomeView(model: model)
        }
    }

    private func badge(for section: AppModel.Section) -> Int {
        section == .config ? model.inspection.problems.count : 0
    }
}

extension View {
    /// The width of the pages that read from top to bottom (the Dashboard, Plugins, and Settings), from the
    /// leading edge. A grouped form grows no wider than about this by itself. Pages that are a gallery or an
    /// editor (Themes, Widgets, Lua Config) use the whole window.
    func pageWidth() -> some View {
        frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .leading)
    }
}
