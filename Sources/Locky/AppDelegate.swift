import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var session: LockSession?
    /// Messages that arrived during a lock, shown once it opens: an alert would take the keyboard from the
    /// password field.
    private var pendingMessages: [(title: String, text: String)] = []
    /// The themes the Theme menu lists, worked out in the background (it runs init.lua).
    private var themeNames: [String] = []
    /// settings.json: what the menu and the window change.
    private let store = SettingsStore(lastGood: SettingsStore.defaultLastGood)
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
    private var windowController: LockyWindowController?
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: store.config, withIntermediateDirectories: true)
        store.migrateMenuTheme()
        store.watch()
        store.onChange = { [weak self] in
            guard let self else { return }
            applyAppSettings()
            if windowController?.window?.isVisible == true { model.refresh() }
        }
        applyAppSettings()
        scheduleUpdateChecks()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locky")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        refreshThemeNames()
        // `locky preview` and `locky lock` (main.swift) start here with their options.
        let launch = CLI.GUILaunch.parse(Array(CommandLine.arguments.dropFirst()))
        if let mode = launch.mode {
            start(mode, options: LockSession.Options(theme: launch.theme, previewSize: launch.size ?? CGSize(width: 1440, height: 900),
                                                     behind: launch.behind, settings: store.settings))
        }
        if let section = launch.window {
            model.selectedTheme = launch.theme
            model.screenshots = launch.behind
            showWindow(section, behind: launch.behind, size: launch.size)
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
    /// and compare. It changes nothing; the menu and the window say what is new.
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

    /// Opening Locky again (from Finder, Spotlight, or the Dock) opens its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(nil)
        return false
    }

    private func showWindow(_ section: AppModel.Section?, behind: Bool = false, size: CGSize? = nil) {
        let controller = windowController ?? LockyWindowController(model: model)
        windowController = controller
        controller.show(section, behind: behind, size: size)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Lock Now", #selector(lockNow)))
        menu.addItem(item("Preview", #selector(previewFromMenu)))
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
        for name in themeNames.isEmpty ? Self.builtInThemeNames() : themeNames {
            let entry = item(name, #selector(pickTheme(_:)))
            entry.representedObject = name
            entry.state = name == pickedTheme ? .on : .off
            themes.addItem(entry)
        }
        menu.addItem(submenu("Theme", themes))

        let plugins = NSMenu()
        plugins.autoenablesItems = false
        for (title, action) in [("Install Missing", #selector(syncPlugins)), ("Update All", #selector(updatePlugins)),
                                ("Remove Unused", #selector(cleanPlugins))] {
            let busy = model.packRunning != nil
            let entry = item(busy ? "\(title) (busy…)" : title, action)
            entry.isEnabled = !busy
            plugins.addItem(entry)
        }
        plugins.addItem(.separator())
        plugins.addItem(item("Open Plugins Folder", #selector(openPlugins)))
        let updates = model.available.count
        menu.addItem(submenu(updates == 0 ? "Plugins" : updates == 1 ? "Plugins (1 update)" : "Plugins (\(updates) updates)", plugins))

        menu.addItem(.separator())
        menu.addItem(item("Dashboard…", #selector(openDashboard)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Check Config", #selector(checkConfig)))
        menu.addItem(item("Open Config Folder", #selector(openConfig)))
        menu.addItem(item("Open Log", #selector(openLog)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Locky", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    /// Themes in the config folder and the built-in runtime and packages.
    static func builtInThemeNames() -> [String] {
        RuntimePath.standard().findAll("themes", suffix: ".lua").map(\.name).sorted()
    }

    /// Adds the themes of the packages init.lua adds (installed ones, and local { dir = ... } ones). Runs
    /// init.lua, so it works in the background.
    private func refreshThemeNames() {
        Task.detached {
            var path = RuntimePath.standard()
            for spec in PackManager(path: path).specs().specs {
                let folder = spec.dir.map { URL(fileURLWithPath: $0) } ?? path.packs.appending(path: spec.name)
                if FileManager.default.fileExists(atPath: folder.path) { path.insertPackage(folder) }
            }
            let names = path.findAll("themes", suffix: ".lua").map(\.name).sorted()
            await MainActor.run { [weak self] in self?.themeNames = names }
        }
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
    @objc private func previewFromMenu() { preview(theme: nil) }

    /// A preview window of `theme` (nil: the theme a lock would use), replacing an open preview.
    private func preview(theme: String?) {
        guard session?.mode != .lock else { return }
        if session?.mode == .preview { session?.end("another preview") }
        start(.preview, options: LockSession.Options(theme: theme ?? scheduledTheme(), settings: store.settings))
    }

    @objc private func openDashboard() { showWindow(.dashboard) }
    @objc private func openSettings() { showWindow(.settings) }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        pickedTheme = sender.representedObject as? String
        restartPreview()
    }

    @objc private func followConfig() {
        pickedTheme = nil
        restartPreview()
    }

    @objc private func syncPlugins() { runPack(.sync) }
    @objc private func updatePlugins() { runPack(.update) }
    @objc private func cleanPlugins() { runPack(.clean) }

    private func runPack(_ action: PackManager.Action) {
        model.runPack(action) { [weak self] report in
            self?.refreshThemeNames()
            self?.show(title: "Plugins", text: report.text)
        }
    }

    @objc private func openPlugins() {
        try? FileManager.default.createDirectory(at: RuntimePath.defaultPacks, withIntermediateDirectories: true)
        NSWorkspace.shared.open(RuntimePath.defaultPacks)
    }

    @objc private func checkConfig() {
        Task.detached {
            let report = CLI.checkReport(theme: nil)
            await MainActor.run { [weak self] in self?.show(title: "Check Config", text: report.text) }
        }
    }

    @objc private func openConfig() {
        CLI.ensureConfig()
        NSWorkspace.shared.open(RuntimePath.defaultConfig)
    }

    @objc private func openLog() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Locky/locky.log")
        LogFile.shared.write(level: "info", message: "log opened", source: "locky")
        NSWorkspace.shared.open(url)
    }

    private func restartPreview() {
        guard session?.mode == .preview else { return }
        session?.end("theme changed")
        start(.preview, options: LockSession.Options(settings: store.settings))
    }

    private func start(_ mode: LockSession.Mode, options: LockSession.Options) {
        guard session == nil else { return }
        let session = LockSession(mode: mode, options: options)
        session.onEnd = { [weak self, weak session] in
            guard let self else { return }
            self.session = nil
            refreshThemeNames()
            // What arrived during the lock, now that the password field no longer needs the keyboard.
            let waiting = pendingMessages
            pendingMessages = []
            for message in waiting { show(title: message.title, text: message.text) }
            // Someone typed wrong passwords and the camera caught them: show the photos.
            if mode == .lock, let session {
                Task { [weak self] in
                    if await !session.photosTaken().isEmpty { self?.showWindow(.dashboard) }
                }
            }
        }
        self.session = session
        session.begin()
    }

    private func show(title: String, text: String) {
        if session?.mode == .lock {
            pendingMessages.append((title, text))
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = String(text.prefix(4000))
        NSApp.activate()
        alert.runModal()
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
