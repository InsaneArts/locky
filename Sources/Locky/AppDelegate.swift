import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var session: LockSession?
    /// settings.json: what the menu and the window change.
    /// A screenshot run (`--behind`) or one against the source tree (LOCKY_RESOURCES): a tool, not the user's
    /// Locky. It starts no auto-lock, shortcut, or update checks, and leaves the user's last good settings, the
    /// remembered privacy, and the menu's old theme choice alone.
    static let isTool = CommandLine.arguments.contains("--behind") || ProcessInfo.processInfo.environment["LOCKY_RESOURCES"] != nil
    private let store = SettingsStore(lastGood: isTool ? nil : SettingsStore.defaultLastGood)
    private lazy var model: AppModel = {
        let model = AppModel(store: store)
        model.lockNow = { [weak self] in self?.lockNow() }
        model.preview = { [weak self] theme in self?.preview(theme: theme) }
        model.recordingShortcut = { [weak self] recording in
            guard let self else { return }
            recordingShortcut = recording
            if recording { hotkeys.unregister() } else { applyShortcut() }
        }
        return model
    }()
    /// The three windows, each made the first time it opens.
    private var themesWindow: LockyWindowController?
    private var settingsWindow: SettingsWindowController?
    private var welcomeWindow: WelcomeWindowController?
    /// The Lock Now shortcut, and auto-lock's triggers, both from settings.json.
    private lazy var hotkeys = HotkeyCenter { [weak self] in self?.lockNow() }
    private lazy var autoLock = AutoLock(isLocked: { [weak self] in self?.session?.mode == .lock },
                                         lock: { [weak self] reason in self?.lock(because: reason) })
    /// While Settings records a new shortcut, the old one stays free so the recorder sees the keys.
    private var recordingShortcut = false
    /// The theme picked in the menu (settings.json's theme). It wins over init.lua's until "Use init.lua's
    /// Theme" clears it.
    private var pickedTheme: String? {
        get { store.settings["theme"].string }
        set { store.update { $0["theme"] = newValue.map(LuaValue.string) ?? .nil } }
    }

    /// A second launch's request to this one: its arguments, as the command line gave them.
    static let request = Notification.Name("com.tornikegomareli.Locky.request")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A tool run draws in the appearance LOCKY_APPEARANCE names ("light" or "dark"), for screenshots of both;
        // anything else leaves the Mac's own.
        if Self.isTool {
            switch ProcessInfo.processInfo.environment["LOCKY_APPEARANCE"] {
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            default: break
            }
        }
        // No tabs: the windows are a main window, a settings window, and the Welcome.
        NSWindow.allowsAutomaticWindowTabbing = false
        try? Settings.createFolder(store.config)
        if !Self.isTool { store.migrateMenuTheme() }
        store.watch()
        let tool = Self.isTool
        store.onChange = { [weak self] in
            guard let self else { return }
            if !tool { applyAppSettings() }
            if [themesWindow?.window, settingsWindow?.window, welcomeWindow?.window].contains(where: { $0?.isVisible == true }) { model.refresh() }
        }
        if !tool {
            IntruderLog().prune()
            applyAppSettings()
            scheduleUpdateChecks()
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleRequest(_:)), name: Self.request, object: nil,
                                                                suspensionBehavior: .deliverImmediately)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locky")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        model.openWindow = { [weak self] in self?.showWindow($0) }
        model.refresh()
        // `locky preview` and `locky lock` (main.swift) start here with their options.
        let launch = CLI.GUILaunch.parse(Array(CommandLine.arguments.dropFirst()))
        if let mode = launch.mode {
            start(mode, options: LockSession.Options(theme: launch.theme, previewSize: launch.size ?? CGSize(width: 1440, height: 900),
                                                     behind: launch.behind, settings: store.settings))
        }
        if let section = launch.window {
            // Only a launch is a screenshot run: its previews keep running behind other windows.
            model.screenshots = launch.behind
            open(section, theme: launch.theme, widgets: launch.opensWidgetGallery, behind: launch.behind, size: launch.size)
        } else if launch.mode == nil, WelcomeView.opensAtLaunch(.standard, isTool: tool) {
            showWindow(.welcome)
        }
    }

    /// The settings the app itself acts on: auto-lock's triggers and the Lock Now shortcut.
    private func applyAppSettings() {
        autoLock.apply(store.settings.autoLock)
        applyShortcut()
    }

    private func applyShortcut() {
        guard !recordingShortcut else { return }
        guard let shortcut = store.settings.shortcut else {
            hotkeys.unregister()
            model.shortcutProblem = nil
            return
        }
        guard shortcut != hotkeys.shortcut else { return }
        do {
            try hotkeys.register(shortcut)
            model.shortcutProblem = nil
        } catch {
            model.shortcutProblem = error.localizedDescription
        }
    }

    private func lock(because reason: String) {
        LogFile.shared.write(level: "info", message: "auto-lock: \(reason)", source: "locky")
        lockNow()
    }

    /// Once a day, a minute after launch first, if settings.json's update_check is not off: fetch the plugins
    /// and compare. It changes nothing; Settings › Plugins says what is new.
    private func scheduleUpdateChecks() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                guard let self else { return }
                if store.settings["update_check"].bool != false, session?.mode != .lock { model.checkForUpdates() }
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    /// Another launch's arguments: open a window, preview, or lock, as that launch would have.
    @objc private func handleRequest(_ notification: Notification) {
        let arguments = notification.userInfo?["arguments"] as? [String] ?? []
        // Any process can post it: during a lock, nothing it asks for (a window, a preview) may come up.
        guard session?.mode != .lock else {
            LogFile.shared.write(level: "warn", message: "ignored a request from another launch during a lock: \(arguments.joined(separator: " "))", source: "locky")
            return
        }
        let launch = CLI.GUILaunch.parse(arguments)
        LogFile.shared.write(level: "info", message: "request from another launch: \(arguments.joined(separator: " "))", source: "locky")
        switch launch.mode {
        case .lock?:
            if session?.mode == .preview { session?.end("locking") }
            start(.lock, options: LockSession.Options(theme: launch.theme ?? scheduledTheme(), settings: store.settings))
        case .preview?: preview(theme: launch.theme)
        default:
            // In front: a screenshot run takes no requests, so a request that says --behind is not from Locky.
            open(launch.window ?? .themes, theme: launch.theme, widgets: launch.opensWidgetGallery, behind: false, size: launch.size)
        }
    }

    /// `Locky window`: a window or a Settings pane. For the Themes window, Customize for `theme`, or for the theme in use
    /// with Add Widget open (`widgets`); else the gallery.
    private func open(_ section: AppModel.Section, theme: String?, widgets: Bool, behind: Bool, size: CGSize?) {
        showWindow(section, behind: behind, size: size)
        guard section == .themes else { return }
        if let theme {
            model.customize(theme)
            model.addingWidget = widgets
        } else if widgets {
            model.customizeInUse(addingWidget: true)
        } else {
            model.finishEditing()
        }
    }

    /// Opening Locky again (from Finder, Spotlight, or the Dock) brings the Welcome forward while it is open, else opens
    /// the Themes window; never during a lock: the window would take the keyboard from the lock.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard session?.mode != .lock else {
            LogFile.shared.write(level: "warn", message: "ignored a reopen during a lock", source: "locky")
            return false
        }
        showWindow(welcomeWindow?.window?.isVisible == true ? .welcome : .themes)
        return false
    }

    /// The one way a window opens: the Welcome, the Settings window at a pane, or the Themes window (any other section,
    /// and nil). `behind` keeps it behind other windows and `size` sizes the Themes window: both for screenshots.
    private func showWindow(_ section: AppModel.Section?, behind: Bool = false, size: CGSize? = nil) {
        // During a lock nothing may come up: a window would take the keyboard from the lock.
        guard session?.mode != .lock else {
            LogFile.shared.write(level: "warn", message: "ignored a window during a lock: \(section?.rawValue ?? "themes")", source: "locky")
            return
        }
        // Locky is an accessory app, which has no Dock icon and no menu bar: a window to work in needs both.
        if !behind { NSApp.setActivationPolicy(.regular) }
        switch section {
        case .welcome?:
            model.refresh()
            let controller = welcomeWindow ?? WelcomeWindowController(model: model) { [weak self] in self?.closed(self?.welcomeWindow?.window) }
            welcomeWindow = controller
            controller.show(behind: behind)
        case .settings?, .plugins?, .config?:
            model.startWatching()
            model.refresh()
            let controller = settingsWindow ?? SettingsWindowController(model: model) { [weak self] in self?.closed(self?.settingsWindow?.window) }
            settingsWindow = controller
            controller.show(section, behind: behind)
        default:
            model.startWatching()
            model.refresh()
            let controller = themesWindow ?? LockyWindowController(model: model) { [weak self] in self?.closed(self?.themesWindow?.window) }
            themesWindow = controller
            controller.show(behind: behind, size: size)
        }
    }

    private func closed(_ window: NSWindow?) {
        if let window { updateActivationPolicy(closing: window) }
    }

    /// After `closing` closes: Locky goes back to the menu bar only, unless another of its windows stays open, and stops
    /// following the config once neither the Themes nor the Settings window does. A minimized window counts as open.
    private func updateActivationPolicy(closing: NSWindow) {
        func staysOpen(_ window: NSWindow?) -> Bool { window.map { $0 !== closing && ($0.isVisible || $0.isMiniaturized) } ?? false }
        let themesOrSettings = staysOpen(themesWindow?.window) || staysOpen(settingsWindow?.window)
        if !themesOrSettings { model.stopWatching() }
        if !themesOrSettings, !staysOpen(welcomeWindow?.window) { NSApp.setActivationPolicy(.accessory) }
    }

    /// Lock Now, a quick theme change, and the window: everything else is in the window.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let failure = ThemeFailure.current(.standard, inspection: model.inspection, config: store.config) {
            let note = NSMenuItem(title: failure.summary(model.inspection), action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
            menu.addItem(.separator())
        }
        menu.addItem(item("Lock Now", #selector(lockNow)))
        menu.addItem(.separator())

        let themes = NSMenu()
        if store.settings.schedule != nil {
            let note = NSMenuItem(title: "The theme schedule picks the theme", action: nil, keyEquivalent: "")
            note.isEnabled = false
            themes.addItem(note)
            themes.addItem(item("Change the Schedule…", #selector(openSettings)))
            themes.addItem(.separator())
        }
        let follow = item("Use init.lua's Theme", #selector(followConfig))
        follow.state = pickedTheme == nil ? .on : .off
        themes.addItem(follow)
        themes.addItem(.separator())
        // By name once the window's model has read the themes; until then (a moment after launch), by id.
        let listed = model.inspection.loaded ? model.inspection.themes.map { ($0.id, $0.name) } : Self.builtInThemeNames().map { ($0, $0) }
        for (id, name) in listed.sorted(by: { $0.1.localizedStandardCompare($1.1) == .orderedAscending }) {
            let entry = item(name, #selector(pickTheme(_:)))
            entry.representedObject = id
            entry.state = id == pickedTheme ? .on : .off
            themes.addItem(entry)
        }
        menu.addItem(submenu("Theme", themes))
        menu.addItem(item("Preview Theme", #selector(previewTheme)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Welcome…", #selector(openWelcome)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Locky", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    /// Themes in the config folder and the built-in runtime and packages.
    static func builtInThemeNames() -> [String] {
        RuntimePath.standard().findAll("themes", suffix: ".lua").map(\.name).sorted()
    }

    @objc private func lockNow() {
        // A preview open (for a theme author, or behind other windows for screenshots) gives way to the lock.
        if session?.mode == .preview { session?.end("locking") }
        start(.lock, options: LockSession.Options(theme: scheduledTheme(), settings: store.settings))
    }

    /// The theme schedule's pick for now, when the schedule is on and has a theme for now.
    private func scheduledTheme() -> String? {
        store.settings.schedule?.theme(at: Date(), dark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }

    /// While locked, nothing quits Locky through the normal path: that would open the Mac.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        session?.mode == .lock ? .terminateCancel : .terminateNow
    }
    /// A preview window of `theme` (nil: the theme a lock would use), replacing an open preview.
    private func preview(theme: String?) {
        guard session?.mode != .lock else { return }
        if session?.mode == .preview { session?.end("another preview") }
        start(.preview, options: LockSession.Options(theme: theme ?? scheduledTheme(), settings: store.settings))
    }

    /// The Settings window on the pane it showed last.
    @objc private func openSettings() { showWindow(SettingsWindowController.lastPane) }
    @objc private func openWelcome() { showWindow(.welcome) }
    /// A preview of the theme a lock would use now.
    @objc private func previewTheme() { preview(theme: nil) }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        pickedTheme = sender.representedObject as? String
        restartPreview()
    }

    @objc private func followConfig() {
        pickedTheme = nil
        restartPreview()
    }

    private func restartPreview() {
        guard session?.mode == .preview else { return }
        session?.end("theme changed")
        start(.preview, options: LockSession.Options(settings: store.settings))
    }

    private func start(_ mode: LockSession.Mode, options: LockSession.Options) {
        guard session == nil else { return }
        if mode == .lock { model.locked = true }
        var options = options
        if Self.isTool { options.remembers = false }
        let session = LockSession(mode: mode, options: options)
        session.onEnd = { [weak self, weak session] in
            guard let self else { return }
            self.session = nil
            if mode == .lock { model.locked = false }
            model.refresh()
            if mode == .lock { autoLock.noteUnlock() }
            // Someone typed wrong passwords and the camera caught them: show the photos.
            if mode == .lock, let session {
                Task { [weak self] in
                    if await !session.photosTaken().isEmpty { self?.showWindow(.settings) }
                }
            }
        }
        self.session = session
        session.begin()
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
