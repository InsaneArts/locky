import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var session: LockSession?
    /// A package run in progress; the Plugins items wait for it.
    private var packRunning = false
    /// Messages that arrived during a lock, shown once it opens: an alert would take the keyboard from the
    /// password field.
    private var pendingMessages: [(title: String, text: String)] = []
    /// The themes the Theme menu lists, worked out in the background (it runs init.lua).
    private var themeNames: [String] = []
    /// settings.json: what the menu and the window change.
    private let store = SettingsStore()
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
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Lock Now", #selector(lockNow)))
        menu.addItem(item("Preview", #selector(preview)))
        menu.addItem(.separator())

        let themes = NSMenu()
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
            let entry = item(packRunning ? "\(title) (busy…)" : title, action)
            entry.isEnabled = !packRunning
            plugins.addItem(entry)
        }
        plugins.addItem(.separator())
        plugins.addItem(item("Open Plugins Folder", #selector(openPlugins)))
        menu.addItem(submenu("Plugins", plugins))

        menu.addItem(.separator())
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
        start(.lock, options: LockSession.Options(settings: store.settings))
    }

    /// While locked, nothing quits Locky through the normal path: that would open the Mac.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        session?.mode == .lock ? .terminateCancel : .terminateNow
    }
    @objc private func preview() { start(.preview, options: LockSession.Options(settings: store.settings)) }

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
        guard !packRunning else { return }
        packRunning = true
        Task.detached {
            let report = PackManager(path: .standard()).run(action)
            await MainActor.run { [weak self] in
                self?.packRunning = false
                self?.refreshThemeNames()
                self?.show(title: "Plugins", text: report.text)
            }
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
        session.onEnd = { [weak self] in
            guard let self else { return }
            self.session = nil
            refreshThemeNames()
            // What arrived during the lock, now that the password field no longer needs the keyboard.
            let waiting = pendingMessages
            pendingMessages = []
            for message in waiting { show(title: message.title, text: message.text) }
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
