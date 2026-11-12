import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem!
    private var session: LockSession?
    /// settings.json: what the windows change.
    /// A screenshot run (`--behind`), a transition preview (`preview --transition`), or one against the source tree
    /// (LOCKY_RESOURCES): a tool, not the user's Locky. It starts no auto-lock, shortcut, or update checks, and leaves the
    /// user's last good settings, the remembered privacy, and the menu's old theme choice alone.
    static let isTool = CommandLine.arguments.contains("--behind") || ProcessInfo.processInfo.environment["LOCKY_RESOURCES"] != nil
        || CLI.GUILaunch.parse(Array(CommandLine.arguments.dropFirst())).transition
    private let store = SettingsStore(lastGood: isTool ? nil : SettingsStore.defaultLastGood)
    private lazy var model: AppModel = {
        // LOCKY_PERMISSIONS=none in a tool run shows each permission as not granted, for screenshots of those rows: a
        // tool run reads the Terminal's Accessibility, which has it.
        let notGranted = Self.isTool && ProcessInfo.processInfo.environment["LOCKY_PERMISSIONS"] == "none"
        let model = AppModel(store: store, permissions: Permissions(system: .live(notGranted: notGranted)))
        model.lockNow = { [weak self] in self?.lockNow(nil) }
        model.preview = { [weak self] theme in self?.preview(theme: theme) }
        model.recordingShortcut = { [weak self] recording in
            guard let self else { return }
            recordingShortcut = recording
            if recording {
                hotkeys.unregister()
                MainMenu.setLockNowShortcut(nil)
            } else {
                applyShortcut()
            }
        }
        return model
    }()
    /// The three windows, each made the first time it opens.
    private var themesWindow: LockyWindowController?
    private var settingsWindow: SettingsWindowController?
    private var welcomeWindow: WelcomeWindowController?
    /// The Lock Now shortcut, and auto-lock's triggers, both from settings.json.
    private lazy var hotkeys = HotkeyCenter { [weak self] in self?.lockNow(nil) }
    private lazy var autoLock = AutoLock(isLocked: { [weak self] in self?.session?.mode == .lock },
                                         lock: { [weak self] reason in self?.lock(because: reason) })
    /// The Touch ID button, with lock_key on: Lock Now's lock instead of the macOS one.
    private lazy var lockKey = LockKey(isLocked: { [weak self] in self?.session?.mode == .lock },
                                       lockIsUp: { [weak self] in self?.session?.holdsLock == true },
                                       lock: { [weak self] in self?.lock(.user, touchIDQuiet: 1) })
    /// While Settings records a new shortcut, the old one stays free so the recorder sees the keys.
    private var recordingShortcut = false
    /// The menu that opened last: a pop-up or context menu in a window, the status menu, or the menu bar.
    private weak var trackedMenu: NSMenu?

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
        // First: the shortcut below gives Lock Now its key, and a launch-time lock clears the menus.
        MainMenu.install(in: NSApp)
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidBeginTracking(_:)), name: NSMenu.didBeginTrackingNotification,
                                               object: nil)
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
            WeatherCache.removeOldReplies()
            applyAppSettings()
            // A new fix for the weather's Current Location, if Location Services allows it: nothing asks here.
            model.location.refresh()
            scheduleUpdateChecks()
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleRequest(_:)), name: Self.request, object: nil,
                                                                suspensionBehavior: .deliverImmediately)
            // Accessibility may have changed in System Settings: the Touch ID button follows when Locky comes forward.
            NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive(_:)), name: NSApplication.didBecomeActiveNotification,
                                                   object: nil)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locky")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        model.openWindow = { [weak self] in self?.showWindow($0) }
        // Granted in System Settings with Locky behind: the Touch ID button's tap starts without waiting for Locky to
        // come forward.
        if !tool { model.permissions.accessibilityChanged = { [weak self] in self?.applyLockKey() } }
        model.refresh()
        // `locky preview` and `locky lock` (main.swift) start here with their options.
        let launch = CLI.GUILaunch.parse(Array(CommandLine.arguments.dropFirst()))
        if let mode = launch.mode {
            var options = LockSession.Options(theme: launch.theme ?? scheduledTheme(), previewSize: launch.size ?? CGSize(width: 1440, height: 900),
                                              behind: launch.behind, settings: store.settings)
            options.animated = mode == .lock && animates(.user)
            options.showsTransition = launch.transition
            if let style = launch.transitionStyle { options.settings.lockAnimation = style }
            start(mode, options: options)
        }
        if let section = launch.window {
            // Only a launch is a screenshot run: its previews keep running behind other windows.
            model.screenshots = launch.behind
            model.selectingWidget = launch.select
            open(section, theme: launch.theme, widgets: launch.opensWidgetGallery, newWidget: launch.opensNewWidget, behind: launch.behind,
                 size: launch.size)
        } else if launch.mode == nil, WelcomeView.opensAtLaunch(.standard, isTool: tool) {
            showWindow(.welcome)
        }
    }

    /// The settings the app itself acts on: auto-lock's triggers, the Lock Now shortcut, and the Touch ID button.
    private func applyAppSettings() {
        autoLock.apply(store.settings.autoLock)
        applyShortcut()
        applyLockKey()
    }

    /// The Touch ID button's tap, while lock_key is on and Accessibility is granted. Never in a tool run.
    private func applyLockKey() {
        lockKey.apply(!Self.isTool && store.settings.lockKey && AXIsProcessTrusted())
    }

    @objc private func didBecomeActive(_ notification: Notification) {
        // A lock activates Locky at its start and at each keyboard reclaim: nothing is read then.
        guard session?.mode != .lock else { return }
        applyLockKey()
    }

    private func applyShortcut() {
        guard !recordingShortcut else { return }
        // Locky › Lock Now shows the shortcut registered now, as the status menu does.
        defer { MainMenu.setLockNowShortcut(hotkeys.shortcut) }
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
        lock(LockTransition.Trigger(autoLock: reason))
    }

    /// Whether a lock that `trigger` starts now comes in animated: not with lock_animation none, nor while the main
    /// display sleeps.
    private func animates(_ trigger: LockTransition.Trigger) -> Bool {
        LockTransition.animatesLock(trigger, setting: store.settings.lockAnimation != nil, displayAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0)
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
            var options = LockSession.Options(theme: launch.theme ?? scheduledTheme(), settings: store.settings)
            options.animated = animates(.user)
            start(.lock, options: options)
        case .preview?: preview(theme: launch.theme)
        default:
            // In front: a screenshot run takes no requests, so a request that says --behind is not from Locky.
            open(launch.window ?? .themes, theme: launch.theme, widgets: launch.opensWidgetGallery, newWidget: launch.opensNewWidget, behind: false,
                 size: launch.size)
        }
    }

    /// `Locky window`: a window or a Settings pane. For the Themes window, Customize for `theme`, or for the theme in use
    /// with Add Widget open (`widgets`); else the gallery. For General, the New Widget sheet with `newWidget`.
    private func open(_ section: AppModel.Section, theme: String?, widgets: Bool, newWidget: Bool, behind: Bool, size: CGSize?) {
        showWindow(section, behind: behind, size: size)
        if newWidget { model.newWidget = true }
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
            guard !model.inspection.loaded else {
                controller.show(behind: behind)
                return
            }
            // The first launch opens the Welcome before the config is read, and its preview would show Aurora before
            // init.lua's theme: it waits for that read, a fraction of a second, a second at most.
            Task { [weak self] in
                await self?.model.firstRead(within: .seconds(1))
                // A lock may have started in the wait: nothing comes up over it.
                guard let self, session?.mode != .lock else { return }
                controller.show(behind: behind)
            }
        case .settings?, .plugins?:
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

    /// Lock Now, the windows, and Quit.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let failure = ThemeFailure.current(.standard, inspection: model.inspection, config: store.config) {
            // The Themes window's banner has the whole message, and Open.
            let note = item(failure.menuTitle(model.inspection), #selector(openThemes(_:)))
            note.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(note)
            menu.addItem(.separator())
        }
        // Its key equivalent comes from validateMenuItem, as Locky › Lock Now's does.
        menu.addItem(item("Lock Now", #selector(lockNow(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Themes…", #selector(openThemes(_:))))
        menu.addItem(item("Settings…", #selector(openSettings(_:)), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Locky", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    /// During a lock no window may open: the items that open one are dimmed, in the status menu and the main menu.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Both Lock Now items show the registered shortcut, read as their menu opens: the key's character follows the
        // keyboard layout. A shortcut that another app holds is not registered, so it does not show.
        if menuItem.action == #selector(lockNow(_:)) { MainMenu.setKeyEquivalent(hotkeys.shortcut, on: menuItem) }
        return switch menuItem.action {
        case #selector(openThemes(_:)), #selector(openSettings(_:)), #selector(openWelcome(_:)): session?.mode != .lock
        // A sheet over the Themes window, such as Add Widget, holds it: the new theme would open under it.
        case #selector(newTheme(_:)): session?.mode != .lock && themesWindow?.window?.attachedSheet == nil
        default: true
        }
    }

    /// File › New Theme… and the Settings window's New Theme…: a new theme from the blank one, open in Customize in the
    /// Themes window. No form comes first: the theme is named Untitled Theme, and Customize renames it.
    @objc func newTheme(_ sender: Any?) {
        showWindow(.themes)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await model.newTheme()
            } catch {
                guard session?.mode != .lock, let window = themesWindow?.window else { return }
                let alert = NSAlert()
                alert.messageText = "Can't Make a New Theme"
                alert.informativeText = (error as? LuaError)?.message ?? error.localizedDescription
                alert.beginSheetModal(for: window, completionHandler: nil)
            }
        }
    }

    @objc func lockNow(_ sender: Any?) { lock(.user) }

    /// `touchIDQuiet`: seconds in which Touch ID does not unlock, for a lock from the Touch ID button.
    private func lock(_ trigger: LockTransition.Trigger, touchIDQuiet: Double = 0) {
        // A preview open (for a theme author, or behind other windows for screenshots) gives way to the lock.
        if session?.mode == .preview { session?.end("locking") }
        var options = LockSession.Options(theme: scheduledTheme(), settings: store.settings)
        options.animated = animates(trigger)
        options.touchIDQuiet = touchIDQuiet
        start(.lock, options: options)
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

    /// The Themes window on the gallery, where the failed-theme banner shows.
    @objc private func openThemes(_ sender: Any?) {
        showWindow(.themes)
        model.finishEditing()
    }

    /// The Settings window on the pane it showed last.
    @objc func openSettings(_ sender: Any?) { showWindow(SettingsWindowController.lastPane) }
    @objc func openWelcome(_ sender: Any?) { showWindow(.welcome) }

    /// AppKit names the root menu of the menu that opens: the menu bar, or the menu a pop-up button or a right click shows.
    /// During a lock, a menu that opens closes at once: a right click or VoiceOver's VO-Shift-M on the password field opens
    /// the field's context menu, with Paste, above the lock. The close waits for the menu's first run loop pass: a cancel
    /// inside this notification leaves the menu on screen.
    @objc private func menuDidBeginTracking(_ notification: Notification) {
        trackedMenu = notification.object as? NSMenu
        if session?.mode == .lock, let trackedMenu {
            perform(#selector(closeMenu(_:)), with: trackedMenu, afterDelay: 0, inModes: [.common])
        }
    }

    @objc private func closeMenu(_ menu: NSMenu) { menu.cancelTrackingWithoutAnimation() }

    private func start(_ mode: LockSession.Mode, options: LockSession.Options) {
        guard session == nil else { return }
        if mode == .lock { model.locked = true }
        // The Mac may have moved since the last fix: the weather picks the new one up at its next check.
        if mode == .lock, !Self.isTool { model.location.refresh() }
        var options = options
        if Self.isTool { options.remembers = false }
        let session = LockSession(mode: mode, options: options)
        // While locked no menu item exists, so no key equivalent and no service can act: the main menu goes (a regular app
        // gets an empty one from AppKit in place of nil), and a menu that opens during the lock closes at once
        // (menuDidBeginTracking). The lock's end builds the menus again. macOS 26 ignores servicesMenu once it is set, nil
        // included: taking the main menu away is what puts Services out of reach.
        if mode == .lock {
            // A menu that is open as the lock starts closes first: it would take the keys typed at the lock, and Return would
            // choose its highlighted item behind the lock. No fade: a closing menu holds the keys back until it is gone.
            NSApp.mainMenu?.cancelTrackingWithoutAnimation()
            statusItem?.menu?.cancelTrackingWithoutAnimation()
            trackedMenu?.cancelTrackingWithoutAnimation()
            NSApp.mainMenu = nil
            NSApp.servicesMenu = nil
            // A save or open panel ends as its Cancel ends it: one that runs on its own (Export Theme…, a background's
            // Choose…) and one over a window (Import Theme…). The color panel goes; model.locked closes the rest.
            (NSApp.modalWindow as? NSSavePanel)?.cancel(nil)
            for window in NSApp.windows { (window.attachedSheet as? NSSavePanel)?.cancel(nil) }
            if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.orderOut(nil) }
        }
        session.onEnd = { [weak self, weak session] in
            guard let self else { return }
            self.session = nil
            if mode == .lock {
                model.locked = false
                MainMenu.install(in: NSApp)
                MainMenu.setLockNowShortcut(hotkeys.shortcut)
            }
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
}
