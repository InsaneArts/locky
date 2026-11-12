import AppKit
import ApplicationServices
import Carbon
import GuardCore
import SwiftUI

/// One locked (or previewed) screen: a window per display, the Lua runtime, and the way out.
///
/// The password field never waits for Lua: it appears with the shield, in the last lock's style (or the
/// fallback's), and takes the theme's style when the theme arrives, if nothing has been typed yet.
@MainActor
final class LockSession: NSObject, NSWindowDelegate {
    /// embedded: inside another view, such as the theme editor's preview. No Touch ID, no keyboard.
    enum Mode { case preview, lock, embedded }

    struct Options {
        var theme: String?
        var previewSize = CGSize(width: 1440, height: 900)
        /// Preview only: open behind other windows without activating, for screenshots.
        var behind = false
        /// settings.json as the lock starts, for the app's own settings. Lua reads its part itself.
        var settings = Settings()
        /// Embedded only: the view the screen goes into, with bounds of previewSize.
        weak var container: NSView?
        /// Keeps this lock's privacy mode for the next launch's first lock; false for tool runs (screenshots).
        var remembers = true
        /// Embedded only: when a shader's animation starts. A preview that replaces its session passes the same
        /// one, so the animation goes on where it was.
        var epoch: CFTimeInterval?
        /// Where Lua finds the config, plugins, and themes; tests pass their own.
        var path = RuntimePath.standard()
        /// Lock only: the lock comes in animated (LockTransition.animatesLock). Without it, the shield is opaque from the
        /// first frame.
        var animated = false
        /// Seconds from the start in which a Touch ID match does not unlock: after the Touch ID button locked, the finger
        /// that pressed it is still on the sensor.
        var touchIDQuiet: Double = 0
        /// Preview only (`preview --transition`): the lock's way in plays as the window opens, over a stand-in desktop,
        /// and Return plays the way out, then the way in again.
        var showsTransition = false
    }

    /// Where the Mac is, for locky.location(): main.swift sets MacLocation.current. nil in tests.
    static var location: (@Sendable () -> MacLocation.Place?)?

    let mode: Mode
    var onEnd: (() -> Void)?
    /// Embedded only: called once, when the theme shows with each widget drawn and the background loaded (or
    /// after two seconds at most), so a preview can swap this session in without a blank moment.
    var onReady: (() -> Void)?
    /// Instances that have drawn or failed at least once.
    private var heard = Set<Int>()
    /// Instances that have drawn something (not nil) or failed: what `locky render` waits for.
    private var answered = Set<Int>()
    /// Embedded only: called after each layout of the screen, so the theme editor's canvas follows the widgets.
    var onLayout: (() -> Void)?

    private let options: Options
    /// When begin ran: the start of Touch ID's quiet time.
    private var beganAt: ContinuousClock.Instant?
    private var runtime: LuaRuntime?
    private(set) var started: LuaRuntime.Started?
    private var windows: [NSWindow] = []
    private var screens: [LockScreenView] = []
    /// Shows the scene once it is ready. buildScreens starts it again, so a rebuild never runs two.
    private var revealTask: Task<Void, Never>?
    private var hosts: [Int: [WidgetHost]] = [:]
    /// Each widget's latest view and failure, for widgets made later: a rebuilt display, or hosts that did
    /// not exist yet when a widget failed in its init.
    private var latest: [Int: [(WidgetHost) -> Void]] = [:]
    /// Wrong passwords count across locks, except in the theme editor's preview, which takes none.
    private lazy var authModel = AuthModel(defaults: mode == .embedded ? nil : .standard)
    private var touchID: TouchID?
    /// A preview without Touch ID on a Mac that has it: its field shows the glyph as a picture.
    private var touchIDPicture = false
    private var touchIDFallback: Task<Void, Never>?
    /// Lock only: locks the Mac with the macOS lock screen if Locky crashes, hangs, or is killed.
    private var lockGuard: LockGuard?
    /// Lock only: the app in front when the lock started, which gets the keyboard back the moment it ends.
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    /// Lock only: takes the keys while another app holds the keyboard (see takeKeyboard).
    private var keyTap: (port: CFMachPort, source: CFRunLoopSource)?
    /// The macOS lock screen was asked for; this lock ends when it is up.
    private var handingOver = false
    /// A pending check that the lock holds the keyboard.
    private var keyboardCheck: Task<Void, Never>?
    /// Lock only: once a second, whether another app's window shows above the shields (watchWindowsAbove).
    private var aboveCheck: Task<Void, Never>?
    private var keyboardObserver: NSObjectProtocol?
    private var activityMonitor: Any?
    private var idleTimer: Task<Void, Never>?
    private var auth: Theme.Auth?
    /// Tells macOS the lock screen is in use, so it does not nap Locky. Idle sleep stays allowed.
    private var napGuard: NSObjectProtocol?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var ended = false
    /// Nothing moves in Low Power Mode, with Reduce Motion on, or on battery with settings.json's battery_saver on.
    private var still = false
    private var powerObserver: PowerObserver?
    /// settings.json's display_off, or the system's display sleep: the displays go dark after that many seconds without
    /// input.
    private var displayOff: AmbientTimer<ContinuousClock>?
    /// Lock only: neither idle display sleep nor the screen saver takes over the shield; displayOff turns the displays off.
    private var displayAwake: DisplayAssertion?
    /// settings.json's ambient_after: only the background shows after that many seconds without input.
    private var ambient: AmbientTimer<ContinuousClock>?
    /// Every input to the lock or the preview: it keeps the displays on, ends the ambient mode, and reads Caps Lock.
    private var inputMonitor: Any?
    /// Lock only: the mouse while another app is active (the event tap holds the keys), which the monitor above misses.
    private var mouseMonitor: Any?
    /// Asks to activate Locky at the lock's first input, so its kiosk options apply.
    private var activationMonitor: Any?
    /// When to take a photo of whoever types wrong passwords, and the photos this lock took.
    private lazy var intruder = IntruderPolicy(settings: options.settings)
    private(set) var photos: [URL] = []
    private var capturing: Task<Void, Never>?
    /// While the lock comes in: makes the windows opaque when it has.
    private var comingIn: Task<Void, Never>?
    /// The preview's Return, which plays the way out and in again.
    private var replayMonitor: Any?
    private var replaying = false

    /// The last lock's password field look, so the next lock's shield and field appear in it at once.
    private static var lastLook: (auth: Theme.Auth, palette: [String: String], font: FontSpec)?
    /// The last lock's palette, kept across launches as lastPrivacy is: the first lock after a relaunch starts in its
    /// bg, not black.
    private static var lastPalette: [String: String]? {
        get { UserDefaults.standard.dictionary(forKey: "lastPalette") as? [String: String] }
        set { UserDefaults.standard.set(newValue, forKey: "lastPalette") }
    }
    /// The shield and the field until the theme arrives: the last lock's look, or after a relaunch its palette with
    /// the fallback's field.
    private static var firstLook: (auth: Theme.Auth, palette: [String: String], font: FontSpec) {
        lastLook ?? (Theme.fallback.auth, lastPalette ?? Theme.fallback.palette, Theme.fallback.font)
    }
    /// Privacy mode as the last lock had it (init.lua may turn it on), until this lock's Lua says. Kept across
    /// launches, so the first lock after a restart does not show the name while Lua starts.
    private static var lastPrivacy: Bool {
        get { UserDefaults.standard.bool(forKey: "lastPrivacy") }
        set { UserDefaults.standard.set(newValue, forKey: "lastPrivacy") }
    }
    private lazy var privacy = options.settings["privacy"].bool ?? Self.lastPrivacy

    init(mode: Mode, options: Options) {
        self.mode = mode
        self.options = options
        super.init()
    }

    func begin() {
        beganAt = .now
        if mode == .lock {
            // Before the shield activates Locky.
            if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() { previousApp = front }
            lockGuard = LockGuard { [weak self] reason in self?.handOver(reason) }
            // Without its guard, a crash would leave the shield's open session behind: the macOS lock instead.
            if lockGuard == nil { handOver("the guard did not start") }
            displayAwake = DisplayAssertion()
        }
        if mode != .embedded {
            napGuard = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Showing the lock screen")
        }
        observeSystem()
        // In every mode: the windows' previews are still under Reduce Motion too.
        still = stillNow
        if mode != .embedded {
            powerObserver = PowerObserver { [weak self] in self?.powerChanged() }
        }

        let environment = LuaRuntime.Environment()
        environment.keyboard = Keyboard.current()
        environment.displays = NSScreen.screens.count
        environment.wallpaper = NSScreen.screens.first.flatMap(Wallpaper.picture(for:))?.path
        environment.location = Self.location
        if let size = (mode == .lock ? NSScreen.screens.first?.frame : CGRect(origin: .zero, size: options.previewSize))?.size {
            environment.screen = size
        }
        keyboardObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { environment.keyboard = Keyboard.current() } }

        // The app's copy of settings.json: while the file has an error, that is the last one that read without one.
        let runtime = LuaRuntime(path: options.path, environment: environment, settings: options.settings, delegate: LuaRuntime.Delegate(
            present: { [weak self] id, node in Task { @MainActor in
                if node != nil { self?.answered.insert(id) }
                self?.deliver(id, replacingViews: true) { $0.present(node) }
            } },
            failed: { [weak self] id, message, _ in Task { @MainActor in
                self?.answered.insert(id)
                self?.deliver(id, replacingViews: false) { $0.fail(message) }
            } }
        ))
        self.runtime = runtime

        // A preview kept behind other windows (for screenshots) never asks for Touch ID: its Touch ID view is
        // hidden, so macOS would show its own prompt on top of whatever the user is doing.
        let touchID = TouchID()
        if touchID.isAvailable, mode != .embedded, !(mode == .preview && options.behind), options.settings.touchID {
            self.touchID = touchID
        } else if touchID.isAvailable, mode != .lock, options.settings.touchID {
            touchIDPicture = true
        }

        // A check that hangs leaves the field disabled: the lock then names ⌃⌥⌘Q in its own row, and VoiceOver says it.
        authModel.onSlowCheck = { [weak self] in
            guard let self else { return }
            screens.first?.needsLayout = true
            if mode == .lock, emergencyExit { AccessibilityNotification.Announcement(AuthPanel.wayOut).post() }
        }

        // Cover the screen and show the password field first. The theme fills in when Lua is ready.
        openWindows(animated: mode == .lock && options.animated)
        if let first = screens.first {
            let look = Self.firstLook
            installAuth(look.auth, style: LockyStyle(palette: look.palette, font: look.font, scale: Layout.scale(for: first.bounds.size)))
        }
        if mode == .preview, options.showsTransition {
            replayMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 36, let self, event.window === windows.first else { return event }
                replay()
                return nil
            }
        }
        if mode != .embedded {
            authModel.capsLock = Self.capsLock(NSEvent.modifierFlags)
            watchInput()
        }
        if mode == .lock {
            installEmergencyExit()
            reclaimKeyboardSoon()
            watchWindowsAbove()
            // The kiosk options (no app switching, no Force Quit) apply only while Locky is the active app, and a
            // non-activating shield does not activate it, even when clicked. Input to the lock is the moment macOS
            // grants an activation: ask then.
            activationMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
                if !NSApp.isActive {
                    NSApp.activate()
                    NSApp.presentationOptions = Self.kioskOptions
                }
                return event
            }
        }
        // Touch ID starts with the theme's field, or after a second with this one if the theme is slow.
        touchIDFallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { self?.startTouchID() }
        }

        if mode != .embedded { LogFile.shared.write(level: "info", message: "\(mode == .lock ? "lock" : "preview") started", source: "locky") }
        Task {
            let started = await runtime.start(theme: options.theme)
            guard !ended else { return }
            apply(started)
        }
    }

    private func deliver(_ id: Int, replacingViews: Bool, _ update: @escaping (WidgetHost) -> Void) {
        heard.insert(id)
        // Keep the latest view, and failures after it, for widgets made later.
        if replacingViews { latest[id] = [update] } else { latest[id, default: []].append(update) }
        hosts[id]?.forEach(update)
    }

    /// Shows the scene of every screen once the theme is whole, or after `limit`: one fade for a lock or a preview, at
    /// once in the theme editor's preview, which onReady then tells.
    private func revealWhenReady(within limit: Duration) async {
        let deadline = ContinuousClock.now + limit
        while !Task.isCancelled, !ended, !isReady, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard !Task.isCancelled, !ended else { return }
        let animated = mode != .embedded
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animated ? 0.25 : 0
            context.timingFunction = Motion.easeOut
            screens.forEach { $0.reveal(animated: animated) }
        }, completionHandler: nil)
        if mode == .preview, options.showsTransition, let screen = screens.first, screen.alphaValue == 0 {
            screen.alphaValue = 1
            comeIn(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
        guard mode == .embedded else { return }
        let ready = onReady
        onReady = nil
        ready?()
    }

    /// Waits, up to `limit`, until every widget has drawn something (or failed) and measured itself. A widget that
    /// waits for data (network, processes, weather) draws nothing until its first reply. `locky render` only: a lock
    /// never waits for Lua.
    func waitForContent(within limit: Duration) async {
        let deadline = ContinuousClock.now + limit
        while !ended, ContinuousClock.now < deadline, let started, let screen = screens.first,
              !(started.instances.allSatisfy { $0.map(answered.contains) ?? true } && screen.widgets.allSatisfy(\.isSettled)) {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    /// Every widget has drawn (or failed) and measured itself, and the background has loaded.
    private var isReady: Bool {
        guard let started, let screen = screens.first else { return false }
        return started.instances.allSatisfy { $0.map(heard.contains) ?? true } && screen.widgets.allSatisfy(\.isSettled)
            && ((screen.background as? BackgroundLoading)?.isLoaded ?? true)
    }

    /// `unlocked`: a correct password or Touch ID ends the lock, which then goes out animated (LockTransition).
    func end(_ reason: String, unlocked: Bool = false) {
        guard !ended else { return }
        ended = true
        if mode != .embedded { LogFile.shared.write(level: "info", message: "\(mode == .lock ? "lock" : "preview") ended: \(reason)", source: "locky") }
        lockGuard?.release()
        runtime?.stop()
        touchID?.stop()
        touchIDFallback?.cancel()
        revealTask?.cancel()
        keyboardCheck?.cancel()
        aboveCheck?.cancel()
        if let keyTap {
            CGEvent.tapEnable(tap: keyTap.port, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), keyTap.source, .commonModes)
            CFMachPortInvalidate(keyTap.port)
        }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let activityMonitor { NSEvent.removeMonitor(activityMonitor) }
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let activationMonitor { NSEvent.removeMonitor(activationMonitor) }
        if let replayMonitor { NSEvent.removeMonitor(replayMonitor) }
        let wasComingIn = comingIn != nil
        comingIn?.cancel()
        displayOff?.stop()
        displayAwake?.release()
        ambient?.stop()
        powerObserver = nil
        idleTimer?.cancel()
        if let keyboardObserver { DistributedNotificationCenter.default().removeObserver(keyboardObserver) }
        if mode == .lock { NSApp.presentationOptions = [] }
        if let napGuard { ProcessInfo.processInfo.endActivity(napGuard) }
        observers.forEach { $0.0.removeObserver($0.1) }
        DistributedNotificationCenter.default().removeObserver(self, name: Self.screenSaverStopped, object: nil)
        windows.forEach { $0.delegate = nil }
        if mode == .lock {
            let closing = windows
            // Input passes through at once; the fade is a picture. A click during it reaches the app behind.
            closing.forEach { $0.ignoresMouseEvents = true }
            if NSApp.isActive, !handingOver, let previousApp, !previousApp.isTerminated {
                // The keys typed next land in the app that was in front. The system may refuse.
                NSApp.yieldActivation(to: previousApp)
                previousApp.activate(from: .current, options: [])
            } else if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain && !closing.contains($0) }) {
                // After a hand-over, the macOS unlock would leave Locky active with no window: a ⌘Q meant for the app
                // behind would quit Locky, and auto-lock with it. (The status item's window cannot become main.)
                NSApp.deactivate()
            }
            if LockTransition.animatesUnlock(unlocked: unlocked, setting: options.settings.lockAnimation != nil, handingOver: handingOver,
                                             comingIn: wasComingIn, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion),
               goOut(closing) {
                Task { [style] in
                    try? await Task.sleep(for: .seconds(LockTransition.length(.unlock, style: style) + 0.02))
                    closing.forEach { $0.orderOut(nil) }
                }
            } else {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.timingFunction = Motion.easeOut
                    closing.forEach { $0.animator().alphaValue = 0 }
                }, completionHandler: {
                    MainActor.assumeIsolated { closing.forEach { $0.orderOut(nil) } }
                })
            }
        } else {
            windows.forEach { $0.orderOut(nil) }
        }
        if mode == .embedded { screens.forEach { $0.removeFromSuperview() } }
        windows = []
        screens = []
        hosts = [:]
        onEnd?()
    }

    func windowWillClose(_ notification: Notification) { end("window closed") }

    // MARK: System events

    private func observeSystem() {
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor (LockSession) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self, !self.ended { action(self) } }
            }
            observers.append((center, token))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        // While the display sleeps nobody sees the widgets: their timers pause until it wakes.
        observe(workspace, NSWorkspace.screensDidSleepNotification) {
            $0.runtime?.setPaused(true)
            $0.setBackgroundsAsleep(true)
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) {
            $0.runtime?.setPaused(false)
            $0.setBackgroundsAsleep(false)
            $0.touchID?.restart()
            $0.displayOff?.noteActivity()
            $0.ambient?.noteActivity()
            $0.refocus()
        }
        observe(workspace, NSWorkspace.didWakeNotification) {
            $0.runtime?.realign()
            $0.refocus()
        }
        guard mode == .lock else { return }
        // The screen saver can still start during a lock (a hot corner starts it whatever holds the display awake), and
        // takes the keyboard and Touch ID while it shows. AppKit holds distributed notifications back while Locky is
        // inactive, unless they are delivered at once.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenSaverDidStop), name: Self.screenSaverStopped,
                                                            object: nil, suspensionBehavior: .deliverImmediately)
        // Animations stall while a display sleeps, and their clock stops while the Mac does: a lock still coming in turns
        // opaque at once, so the screen is covered when it wakes. No queue for the Mac's sleep, so this runs before it.
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.finishComingIn() }
        let token = workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            let finish = { MainActor.assumeIsolated { if let self, !self.ended { self.finishComingIn() } } }
            if Thread.isMainThread { finish() } else { DispatchQueue.main.sync(execute: finish) }
        }
        observers.append((workspace, token))
        // A display added, removed, or rearranged during the lock gets covered too.
        observe(.default, NSApplication.didChangeScreenParametersNotification) { session in
            // Hiding the Dock and the menu bar at the lock's start changes the screens' parameters too: only other
            // displays, or displays that moved or changed size, need new windows (a rebuild ends the way in).
            guard LockSession.displaysChanged(windows: session.windows.map(\.frame), screens: NSScreen.screens.map(\.frame)) else { return }
            session.rebuildForDisplays()
        }
        // Anything that takes the keyboard (another app, a system prompt) gives it back to the password field.
        observe(.default, NSApplication.didResignActiveNotification) { $0.keyboardTaken() }
        observe(.default, NSWindow.didResignKeyNotification) { session in
            DispatchQueue.main.async { if !session.ended, !(session.windows.first?.isKeyWindow ?? true) { session.keyboardTaken() } }
        }
    }

    private func reclaimKeyboard() {
        // Not while the macOS lock screen comes up: it takes the keyboard, and the lock ends once it is up.
        guard mode == .lock, !ended, !handingOver else { return }
        NSApp.activate()
        windows.first?.makeKeyAndOrderFront(nil)
        NSApp.presentationOptions = Self.kioskOptions
        screens.first?.focusField()
        authModel.focusRequest += 1
    }

    private static let screenSaverStopped = Notification.Name("com.apple.screensaver.didstop")

    @objc private nonisolated func screenSaverDidStop(_: Notification) {
        Task { @MainActor [weak self] in
            guard let self, !ended else { return }
            // Touch ID gave up while the screen saver cancelled it.
            touchID?.restart()
            ambient?.noteActivity()
            refocus()
        }
    }

    /// After a wake or the screen saver: the lock asks for the keyboard again, the field takes it, and Caps Lock is read
    /// anew, since its key may have changed while nothing reached the lock.
    private func refocus() {
        guard mode != .embedded else { return }
        authModel.capsLock = Self.capsLock(NSEvent.modifierFlags)
        if mode == .lock { reclaimKeyboard() } else { screens.first?.focusField() }
    }

    /// Moving shaders and videos stop while the displays sleep, and go on when they wake: no one sees them meanwhile.
    /// (A lock can last a night; Lua's timers pause the same way.)
    private func setBackgroundsAsleep(_ asleep: Bool) {
        func walk(_ view: NSView) {
            (view as? ShaderView)?.setAsleep(asleep)
            (view as? VideoView)?.setAsleep(asleep)
            view.subviews.forEach(walk)
        }
        screens.forEach(walk)
    }

    /// macOS treats activation as a request it may refuse: ask a few times, and check that the lock holds the
    /// keyboard 1.5 s after it started.
    private func reclaimKeyboardSoon() {
        keyboardCheck = Task { [weak self] in
            for attempt in 1...5 {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled, !ended else { return }
                if attempt == 5 { checkKeyboard("Locky did not get the keyboard when the lock started") }
                else if !holdsKeyboard { reclaimKeyboard() }
            }
        }
    }

    /// Something took the keyboard: ask for it back, and check that the lock holds it again 1 s later.
    private func keyboardTaken() {
        reclaimKeyboard()
        guard keyboardCheck == nil else { return }
        keyboardCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.checkKeyboard("Locky lost the keyboard and did not get it back")
        }
    }

    /// Locky is the active app, with the main shield key: what is typed goes to the lock.
    private var holdsKeyboard: Bool { NSApp.isActive && windows.first?.isKeyWindow == true }

    /// A lock on screen that gets what is typed: its main shield is key, or its event tap takes the keys.
    var holdsLock: Bool { mode == .lock && !ended && (windows.first?.isKeyWindow == true || keyTap != nil) }

    enum KeyboardAction: Equatable { case keep, tap, handOver }

    /// A lock that does not hold the keyboard must not stay up, since typing would go to the app behind it. It
    /// takes the keys with an event tap if Accessibility allows one, or hands over to the macOS lock screen.
    /// Another app's secure keyboard entry hides the keys from every event tap: a hand-over then too.
    static func keyboardAction(holds: Bool, tapped: Bool, trusted: Bool, secureInput: Bool) -> KeyboardAction {
        if holds { return .keep }
        if secureInput { return .handOver }
        if tapped { return .keep }
        return trusted ? .tap : .handOver
    }

    /// macOS draws some windows above every app's, the shields' level included: "Allow accessory to connect?" for a
    /// new keyboard, for one. Anyone at the Mac could answer it, so the lock hands over to the macOS lock screen, which
    /// keeps such prompts until the Mac is unlocked.
    private func watchWindowsAbove() {
        aboveCheck = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !ended else { return }
                guard !handingOver, let shield = windows.first, shield.windowNumber > 0 else { continue }
                let above = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow], CGWindowID(shield.windowNumber)) as? [[String: Any]] ?? []
                if let owner = Self.windowsAbove(above, ownPID: getpid()).first {
                    handOver("a window of \(owner) showed above the lock")
                }
            }
        }
    }

    /// The apps whose windows, of `above` (CGWindowListCopyWindowInfo's, over the shields), show something: not the
    /// lock's own, not the window server's (the pointer), and not empty or transparent ones.
    nonisolated static func windowsAbove(_ above: [[String: Any]], ownPID: Int32) -> [String] {
        above.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Double],
                  (bounds["Width"] ?? 0) > 1, (bounds["Height"] ?? 0) > 1 else { return nil }
            let owner = info[kCGWindowOwnerName as String] as? String ?? "process \(pid)"
            return owner == "Window Server" ? nil : owner
        }
    }

    /// Secure keyboard entry is on for another app (Terminal's Secure Keyboard Entry, a focused password field).
    private static var secureInputElsewhere: Bool {
        guard IsSecureEventInputEnabled() else { return false }
        return (CGSessionCopyCurrentDictionary() as? [String: Any])?["kCGSSessionSecureInputPID"] as? Int != Int(getpid())
    }

    private func checkKeyboard(_ reason: String) {
        keyboardCheck = nil
        // During a hand-over the macOS lock screen takes the keyboard; one that fails checks again (handOver).
        guard mode == .lock, !ended, !handingOver else { return }
        let secureInput = Self.secureInputElsewhere
        switch Self.keyboardAction(holds: holdsKeyboard, tapped: keyTap != nil, trusted: AXIsProcessTrusted(), secureInput: secureInput) {
        case .keep:
            // While the tap holds the keys, another app may turn secure keyboard entry on: check each second.
            guard !holdsKeyboard else { return }
            // And ask for the keyboard again each second: once whatever took it is gone (the screen saver, a system
            // prompt), the shield is key again, and the field shows that it takes the typing.
            reclaimKeyboard()
            keyboardCheck = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.checkKeyboard("the event tap held the keyboard")
            }
        case .tap:
            if takeKeyboard() {
                LogFile.shared.write(level: "info", message: "took the keyboard with an event tap: \(reason)", source: "locky")
            } else {
                handOver("\(reason), and the event tap failed")
            }
        case .handOver: handOver(secureInput ? "\(reason), and secure keyboard entry in another app hides the keys from an event tap" : reason)
        }
    }

    /// Takes key presses for the rest of the lock with an event tap: while another app is active, they go to
    /// the password field and not to that app.
    private func takeKeyboard() -> Bool {
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                           callback: { _, type, event, session in
                                               guard let session else { return Unmanaged.passUnretained(event) }
                                               let lock = Unmanaged<LockSession>.fromOpaque(session).takeUnretainedValue()
                                               let taken = MainActor.assumeIsolated { lock.tapped(type, event) }
                                               return taken ? nil : Unmanaged.passUnretained(event)
                                           }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        keyTap = (port, source)
        return true
    }

    /// An event from the tap. true keeps it from every other app.
    private func tapped(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let keyTap { CGEvent.tapEnable(tap: keyTap.port, enable: true) }
            return false
        }
        // While Locky holds the keyboard, keys take the usual way, through the event monitors.
        guard !ended, !holdsKeyboard else { return false }
        guard let key = NSEvent(cgEvent: event) else { return true }
        if emergencyExit, Self.isEmergencyExit(key) {
            handOver("⌃⌥⌘Q")
            return true
        }
        noteInput(key)
        if activityMonitor != nil, key.type == .keyDown { activity() }
        windows.first?.sendEvent(key)
        return true
    }

    // MARK: Windows

    private static let kioskOptions: NSApplication.PresentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching,
                                                                         .disableForceQuit, .disableSessionTermination, .disableHideApplication]

    /// A palette's bg, opaque: what shows under the scene until it fades in.
    private static func backdrop(_ palette: [String: String]) -> NSColor {
        palette["bg"].flatMap { NSColor(hex: $0) }?.withAlphaComponent(1) ?? .black
    }

    /// `animated`: a lock or a `preview --transition` comes in with LockTransition.
    private func openWindows(animated: Bool = false) {
        // From the first frame, the last lock's bg: the scene fades in over it.
        let palette = Self.firstLook.palette
        let backdrop = Self.backdrop(palette)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        switch mode {
        case .preview:
            let window = PreviewWindow(contentRect: CGRect(origin: .zero, size: options.previewSize), styleMask: [.titled, .closable, .resizable],
                                       backing: .buffered, defer: false)
            // A preview for screenshots renders at the size asked for, even beyond the screen's visible area.
            window.unconstrained = options.behind
            window.title = "Locky Preview"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.backgroundColor = backdrop
            // Mouse moves end the ambient mode.
            window.acceptsMouseMovedEvents = true
            let screen = LockScreenView()
            screen.layer?.backgroundColor = backdrop.cgColor
            window.contentView = screen
            if options.showsTransition {
                // The stand-in desktop alone until the theme shows: the way in then plays over it (revealWhenReady).
                screen.alphaValue = 0
                window.contentView = Self.standInStage(scene: screen, size: options.previewSize)
            }
            if options.behind {
                window.setContentSize(options.previewSize)
                window.setFrameOrigin(NSPoint(x: NSScreen.main?.visibleFrame.minX ?? 0, y: NSScreen.main?.visibleFrame.minY ?? 0))
            } else {
                window.center()
            }
            windows = [window]
            screens = [screen]
            if options.behind {
                window.orderBack(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
        case .embedded:
            guard let container = options.container else { return }
            let screen = LockScreenView(frame: CGRect(origin: .zero, size: options.previewSize))
            screen.layer?.backgroundColor = backdrop.cgColor
            // The preview fades the whole screen in once it is ready.
            screen.fadesIn = false
            screen.onLayout = { [weak self] in self?.onLayout?() }
            container.addSubview(screen)
            screens = [screen]
        case .lock:
            for (index, screen) in NSScreen.screens.enumerated() {
                let window = ShieldWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                // A panel hides when its app deactivates, and Locky is often not the active app during a lock;
                // nor may anything hide it on purpose.
                window.hidesOnDeactivate = false
                window.canHide = false
                window.becomesKeyOnlyIfNeeded = false
                window.worksWhenModal = true
                // Only the main display's shield takes the keyboard: a click on another display must not send
                // the typing to a window without a password field.
                window.allowsKey = index == 0
                window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                window.backgroundColor = backdrop
                window.hasShadow = false
                window.isReleasedWhenClosed = false
                // Mouse moves show a hidden password field and keep the displays on, also after a rebuild.
                window.acceptsMouseMovedEvents = true
                let view = LockScreenView()
                view.layer?.backgroundColor = backdrop.cgColor
                Self.prepare(window, scene: view, transitions: options.settings.lockAnimation != nil, comingIn: animated,
                             reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
                window.setFrame(screen.frame, display: true)
                window.orderFrontRegardless()
                windows.append(window)
                screens.append(view)
            }
            windows.first?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            NSApp.presentationOptions = Self.kioskOptions
        }
        // The field on a light bg draws light glass, as the theme will.
        windows.forEach { $0.appearance = NSAppearance(named: Design.isLight(palette["bg"]) ? .aqua : .darkAqua) }
        if animated { comeIn(reduceMotion: reduceMotion) }
    }

    // MARK: The way in and out (LockTransition)

    /// A shield's content. With a lock_animation style: the backdrop under the scene, hidden while the window is opaque. Coming
    /// in, the window starts clear, with the backdrop at the back, and still takes every click: input goes to the lock
    /// from the first frame, as with an opaque shield.
    static func prepare(_ window: NSWindow, scene: LockScreenView, transitions: Bool, comingIn: Bool, reduceTransparency: Bool) {
        guard transitions else {
            window.contentView = scene
            return
        }
        let backdrop = LockTransition.backdrop(reduceTransparency: reduceTransparency)
        backdrop.isHidden = !comingIn
        window.contentView = TransitionStage(frame: window.contentRect(forFrameRect: window.frame), scene: scene, backdrop: backdrop)
        guard comingIn else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        // A clear window lets clicks through its clear pixels unless told otherwise.
        window.ignoresMouseEvents = false
    }

    /// The preview's stage: a stand-in desktop with its blurred copy as the backdrop, under the scene.
    private static func standInStage(scene: LockScreenView, size: CGSize) -> TransitionStage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let picture = StandInDesktop.picture(size: size, scale: scale)
        let desktop = NSView()
        desktop.wantsLayer = true
        desktop.layer?.contents = picture
        desktop.layer?.contentsGravity = .resize
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let backdrop = LockTransition.backdrop(reduceTransparency: reduceTransparency,
                                               picture: picture.flatMap { StandInDesktop.blurred($0, scale: scale) })
        return TransitionStage(frame: CGRect(origin: .zero, size: size), scene: scene, backdrop: backdrop, desktop: desktop)
    }

    /// Each window's point at `global` (screen coordinates), in its scene's coordinates.
    private static func point(_ global: CGPoint, in stage: TransitionStage) -> CGPoint {
        guard let window = stage.window else { return CGPoint(x: stage.scene.bounds.midX, y: stage.scene.bounds.midY) }
        return stage.scene.convert(window.convertPoint(fromScreen: global), from: nil)
    }

    /// The lock's style: settings.json's as the lock started, or Focus for a preview with none.
    private var style: LockTransition.Style { options.settings.lockAnimation ?? .focus }

    /// The lock comes in on every window, from the middle of the main display; the windows turn opaque when it has, or at
    /// once if a display or the Mac goes to sleep first (observeSystem).
    private func comeIn(reduceMotion: Bool) {
        let stages = windows.compactMap { $0.contentView as? TransitionStage }
        guard let main = windows.first, let first = stages.first, let start = first.scene.layer?.convertTime(CACurrentMediaTime(), from: nil) else { return }
        let middle = main.convertPoint(toScreen: first.convert(CGPoint(x: first.bounds.midX, y: first.bounds.midY), to: nil))
        for stage in stages {
            LockTransition.comeIn(stage, style: style, origin: Self.point(middle, in: stage), at: start, reduceMotion: reduceMotion)
        }
        comingIn = Task { [weak self, style] in
            try? await Task.sleep(for: .seconds(LockTransition.length(.lock, style: style, reduceMotion: reduceMotion)))
            guard !Task.isCancelled else { return }
            self?.finishComingIn()
        }
    }

    /// The lock has come in: the scene alone covers each display, opaque, for the rest of the lock.
    private func finishComingIn() {
        guard comingIn != nil else { return }
        comingIn?.cancel()
        comingIn = nil
        for window in windows {
            guard let stage = window.contentView as? TransitionStage else { continue }
            LockTransition.finishComingIn(stage)
            guard mode == .lock else { continue }
            window.backgroundColor = stage.scene.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) } ?? .black
            window.isOpaque = true
        }
    }

    /// Starts the way out on `closing`, from the password field's middle. false when a window has no stage, as when
    /// lock_animation was none as the lock started.
    private func goOut(_ closing: [NSWindow]) -> Bool {
        let stages = closing.compactMap { $0.contentView as? TransitionStage }
        guard stages.count == closing.count, let first = stages.first, let start = first.scene.layer?.convertTime(CACurrentMediaTime(), from: nil)
        else { return false }
        let scene = first.scene
        let field = scene.auth.map { CGPoint(x: $0.view.frame.midX, y: $0.view.frame.midY) } ?? CGPoint(x: scene.bounds.midX, y: scene.bounds.midY)
        let global = first.window.map { $0.convertPoint(toScreen: scene.convert(field, to: nil)) } ?? field
        for (window, stage) in zip(closing, stages) {
            window.isOpaque = false
            window.backgroundColor = .clear
            LockTransition.goOut(stage, style: style, origin: Self.point(global, in: stage), at: start)
        }
        return true
    }

    /// The preview's Return: the way out, a moment of the desktop, and the way in again.
    private func replay() {
        guard !replaying, comingIn == nil, let window = windows.first, let stage = window.contentView as? TransitionStage else { return }
        replaying = true
        _ = goOut([window])
        Task { [weak self, style] in
            try? await Task.sleep(for: .seconds(LockTransition.length(.unlock, style: style) + 0.5))
            guard let self, !ended else { return }
            LockTransition.reset(stage)
            replaying = false
            comeIn(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
    }

    /// Whether the shields no longer match the displays: one window per display, at its frame, in order.
    nonisolated static func displaysChanged(windows: [CGRect], screens: [CGRect]) -> Bool {
        windows != screens
    }

    /// New windows for the displays there are now, with the theme and each widget's latest view, without
    /// restarting Lua. The password field keeps what was typed.
    private func rebuildForDisplays() {
        guard mode == .lock, !ended else { return }
        LogFile.shared.write(level: "info", message: "displays changed: \(NSScreen.screens.count) now", source: "locky")
        let old = windows
        // A shader still drawing a way in on an old window stops: the new windows come opaque.
        old.compactMap { $0.contentView as? TransitionStage }.forEach(LockTransition.finishComingIn)
        windows = []
        screens = []
        hosts = [:]
        openWindows()
        old.forEach { $0.orderOut(nil) }
        if let started { buildScreens(started) } else if let first = screens.first {
            let look = Self.firstLook
            installAuth(look.auth, style: LockyStyle(palette: look.palette, font: look.font, scale: Layout.scale(for: first.bounds.size)))
        }
        touchID?.restart()
        // The new windows show everything: the ambient mode starts again from here.
        ambient?.noteActivity()
        reclaimKeyboard()
    }

    private func installAuth(_ spec: Theme.Auth, style: LockyStyle) {
        guard let screen = screens.first else { return }
        let runtime = self.runtime
        authModel.user = Auth.user(privacy: privacy)
        let panel = AuthPanel(auth: spec, style: style, touchID: touchID, model: authModel,
                              unlock: { [weak self] in self?.end("password", unlocked: true) },
                              failed: { [weak self] in
                                  runtime?.queue.async { runtime?.emit("auth_failed") }
                                  self?.wrongPassword()
                              },
                              onSize: { [weak screen] size in screen?.authSize = size }, interactive: mode != .embedded,
                              touchIDPicture: touchIDPicture, exit: mode == .lock && emergencyExit)
        screen.auth = (NSHostingView(rootView: panel), spec)
        // From the field's first frame: no key typed before SwiftUI asks for focus is lost.
        if mode != .embedded { screen.focusField() }
    }

    /// The photos this lock took, once a capture still running has finished.
    func photosTaken() async -> [URL] {
        await capturing?.value
        return photos
    }

    /// Counts a wrong password; at settings.json's intruder_photo, takes one photo with the camera. The camera
    /// never asks for permission here: Settings asks when the photo is turned on.
    private func wrongPassword() {
        // From the third, or with a wait, the lock names ⌃⌥⌘Q, in its own row.
        screens.first?.needsLayout = true
        guard mode == .lock, !ended, intruder.wrongPassword() else { return }
        capturing = Task { [weak self] in
            do {
                let url = try await IntruderCamera().capture()
                self?.photos.append(url)
                LogFile.shared.write(level: "info", message: "took a photo after wrong passwords: \(url.lastPathComponent)", source: "locky")
            } catch {
                LogFile.shared.write(level: "warn", message: "no photo after wrong passwords: \(error)", source: "locky")
            }
        }
    }

    private func startTouchID() {
        touchIDFallback?.cancel()
        touchID?.start { [weak self] in
            guard let self else { return }
            if let left = Self.quietLeft(since: beganAt.map { ContinuousClock.now - $0 } ?? .zero, quiet: options.touchIDQuiet) {
                // The press's own finger: Touch ID listens again once the quiet time is over, for a new touch.
                LogFile.shared.write(level: "info", message: "Touch ID: not unlocking with the finger that pressed the button", source: "locky")
                touchID?.restart(after: left)
                return
            }
            authModel.succeeded()
            end("Touch ID", unlocked: true)
        }
    }

    /// Seconds of the quiet time left `elapsed` after the start, or nil when it is over.
    nonisolated static func quietLeft(since elapsed: Duration, quiet: Double) -> Double? {
        let left = quiet - Double(elapsed.components.seconds) - Double(elapsed.components.attoseconds) / 1e18
        return left > 0 ? left : nil
    }

    private func apply(_ started: LuaRuntime.Started) {
        self.started = started
        let theme = started.theme
        if mode == .preview {
            windows.first?.title = "Locky Preview — \(theme.name)"
            for problem in started.problems { LogFile.shared.write(level: "warn", message: problem, source: "preview") }
        }
        if mode == .lock, let failed = started.failed {
            ThemeFailure(theme: failed.theme, fallback: theme.id, message: failed.problem, date: Date().timeIntervalSince1970).record()
        }
        if privacy != started.privacy {
            privacy = started.privacy
            // The field may already hold typing: change the name it shows, not the field.
            authModel.user = Auth.user(privacy: privacy)
        }
        if mode != .embedded, options.remembers { Self.lastPrivacy = started.privacy }
        // A preview's theme may not be the one the next lock shows: only a lock sets the next one's first frame.
        if mode == .lock {
            Self.lastLook = (theme.auth, theme.palette, theme.font)
            if options.remembers { Self.lastPalette = theme.palette }
        }
        buildScreens(started)
        startTouchID()

        auth = theme.auth
        if theme.auth.reveal == "activity", authModel.password.isEmpty, let screen = screens.first {
            screen.setAuthVisible(false, dim: theme.auth.dim, animated: false)
            guard mode != .embedded else { return }
            windows.forEach { $0.acceptsMouseMovedEvents = true }  // the preview's window; lock windows always do
            activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDown, .scrollWheel]) { [weak self] event in
                self?.activity()
                return event
            }
        }
    }

    /// The theme on every screen: the password field first (it must never wait), then backgrounds and widgets.
    private func buildScreens(_ started: LuaRuntime.Started) {
        let theme = started.theme
        let light = Design.isLight(theme.palette["bg"])
        windows.forEach { $0.appearance = NSAppearance(named: light ? .aqua : .darkAqua) }
        if mode == .embedded { screens.forEach { $0.appearance = NSAppearance(named: light ? .aqua : .darkAqua) } }
        // Under the theme's field until the scene shows: its own bg, as a lock's first frame has it.
        let backdrop = Self.backdrop(theme.palette)
        // A window still coming in stays clear until it has (finishComingIn).
        windows.forEach { if $0.isOpaque { $0.backgroundColor = backdrop } }
        screens.forEach { $0.layer?.backgroundColor = backdrop.cgColor }

        if let first = screens.first {
            let style = LockyStyle(palette: theme.palette, font: theme.font, scale: Layout.scale(for: first.bounds.size))
            // The theme's look, unless typing has begun: replacing the field then would lose it.
            if authModel.password.isEmpty || first.auth == nil {
                touchID?.restartIfRunning()
                installAuth(theme.auth, style: style)
            }
            // Also on the windows a display change makes.
            first.glanceHint = theme.auth.reveal == "activity" ? NSHostingView(rootView: GlanceHint(auth: theme.auth, style: style)) : nil
        }
        for (index, screen) in screens.enumerated() {
            let main = index == 0
            let scale = Layout.scale(for: screen.bounds.size)
            let style = LockyStyle(palette: theme.palette, font: theme.font, scale: scale, hour24: started.hour24, still: still)
            screen.style = style
            let display = windows.indices.contains(index) ? windows[index].screen : NSScreen.main
            screen.background = Backgrounds.makeView(theme.background, screen: display, still: still, epoch: options.epoch)
            if let overlay = theme.overlay {
                screen.overlay = Backgrounds.makeView(overlay, screen: display, overlay: true, still: still, epoch: options.epoch)
            }
            for (offset, placement) in theme.widgets.enumerated() where main || placement.allDisplays {
                let host = WidgetHost(placement: placement, theme: theme, style: style, showsErrors: mode != .lock)
                screen.add(host)
                if let id = started.instances[offset] {
                    hosts[id, default: []].append(host)
                    latest[id]?.forEach { $0(host) }
                } else {
                    host.fail("theme \(theme.id): no widget named \"\(placement.widget)\"")
                }
            }
            if main {
                screen.message = started.message.map {
                    NSHostingController(rootView: LockMessage(text: $0, model: nil, exit: false, auth: theme.auth, style: style))
                }
                // A lock with ⌃⌥⌘Q always has the row: the line naming it shows once someone looks stuck.
                screen.wayOut = mode == .lock && emergencyExit
                    ? NSHostingController(rootView: LockMessage(text: nil, model: authModel, exit: true, auth: theme.auth, style: style))
                    : nil
                // Only the `preview` window, a theme author's tool: the windows list problems in Settings.
                if mode == .preview, !started.problems.isEmpty {
                    screen.banner = NSHostingView(rootView: ProblemsBanner(problems: started.problems))
                }
            }
        }
        // The scene waits until the theme is whole, or not long: a rebuild starts the wait again.
        revealTask?.cancel()
        let limit: Duration = mode == .embedded ? .seconds(2) : .milliseconds(500)
        revealTask = Task { [weak self] in await self?.revealWhenReady(within: limit) }
    }

    // MARK: The theme editor

    /// Embedded only: shows new settings.json changes to this theme in place: its background, its widgets, and the
    /// password field's place. Each widget keeps its view, and one whose options changed draws anew in it. false
    /// when the change needs a new session: the theme no longer loads, or more than those changed.
    func reload(settings: Settings) async -> Bool {
        guard mode == .embedded, !ended, let runtime, let old = started, let screen = screens.first else { return false }
        guard let next = await runtime.reload(theme: old.theme.id, settings: settings, previous: old), !ended else { return false }
        var rest = next.theme
        rest.background = old.theme.background
        rest.widgets = old.theme.widgets
        rest.auth.anchor = old.theme.auth.anchor
        rest.auth.offset = old.theme.auth.offset
        guard rest == old.theme else { return false }
        started = next
        if next.theme.background != old.theme.background,
           !(screen.latestBackground.map { Backgrounds.update($0, from: old.theme.background, to: next.theme.background) } ?? false) {
            screen.replaceBackground(with: Backgrounds.makeView(next.theme.background, screen: NSScreen.main, still: still, epoch: options.epoch))
        }
        if next.theme.auth != old.theme.auth, let field = screen.auth {
            screen.auth = (field.view, next.theme.auth)
            auth = next.theme.auth
        }
        reconcileWidgets(from: old, to: next, on: screen)
        screen.layoutNow()
        return true
    }

    /// Gives each widget's view its new placement. A widget whose instance changed keeps its view, which shows the
    /// old drawing until the new instance draws; new widgets get new views, and views no placement keeps go.
    private func reconcileWidgets(from old: LuaRuntime.Started, to next: LuaRuntime.Started, on screen: LockScreenView) {
        let views = screen.widgets
        var taken = Set<Int>()
        var reuse = [Int?](repeating: nil, count: next.theme.widgets.count)
        // An instance Lua kept keeps its view, before any new instance looks for one.
        for (index, id) in next.instances.enumerated() {
            if let id, let at = old.instances.firstIndex(of: id), views.indices.contains(at), !taken.contains(at) {
                reuse[index] = at
                taken.insert(at)
            }
        }
        // A new instance takes the view at its place, when that view showed the same widget.
        for (index, placement) in next.theme.widgets.enumerated() where reuse[index] == nil {
            if views.indices.contains(index), !taken.contains(index), old.theme.widgets.indices.contains(index),
               old.theme.widgets[index].widget == placement.widget {
                reuse[index] = index
                taken.insert(index)
            }
        }
        var list: [WidgetHost] = []
        for (index, placement) in next.theme.widgets.enumerated() {
            if let at = reuse[index] {
                views[at].update(placement: placement, theme: next.theme, style: screen.style)
                list.append(views[at])
            } else {
                let host = WidgetHost(placement: placement, theme: next.theme, style: screen.style, showsErrors: true)
                screen.add(host)
                list.append(host)
            }
        }
        for (index, view) in views.enumerated() where !taken.contains(index) { screen.remove(view) }
        screen.arrange(list)
        hosts = [:]
        let running = Set(next.instances.compactMap { $0 })
        latest = latest.filter { running.contains($0.key) }
        for (index, host) in list.enumerated() {
            if let id = next.instances[index] {
                hosts[id] = [host]
                // A view new to this instance shows its latest drawing; the instance's own view has it already.
                let own = old.instances.firstIndex(of: id).flatMap { views.indices.contains($0) ? views[$0] : nil }
                if own !== host { latest[id]?.forEach { $0(host) } }
            } else {
                host.fail("theme \(next.theme.id): no widget named \"\(next.theme.widgets[index].widget)\"")
            }
        }
    }

    /// Whether the screen shows `theme` with settings.json's changes to it: not the theme Locky falls back to, and no
    /// change to it left out for a problem. The theme editor edits on the screen only then, so what it changes is what
    /// the screen shows.
    func shows(theme: String) -> Bool {
        guard let started, started.theme.id == theme else { return false }
        let prefix = "settings.json themes.\(theme)"
        return !started.problems.contains { $0.hasPrefix(prefix + ".") || $0.hasPrefix(prefix + ":") }
    }

    /// Embedded only: what the editor can select (the widgets, by their place in the theme's list, and the password
    /// field), with their frames in the screen's points. Widgets that show nothing are left out.
    var editables: [(item: EditorItem, frame: CGRect)] {
        guard mode == .embedded, let screen = screens.first else { return [] }
        var list: [(item: EditorItem, frame: CGRect)] = []
        if let field = screen.auth, screen.authSize.width > 0 { list.append((.passwordField, field.view.frame)) }
        for (index, host) in screen.widgets.enumerated() where host.alphaValue > 0 && host.frame != screen.bounds && !host.frame.isEmpty {
            list.append((.widget(index), host.frame))
        }
        return list
    }

    /// Embedded only: puts `item` at another place at once, before the change is saved, as the editor drags it.
    func place(_ item: EditorItem, anchor: Anchor, offset: CGPoint) {
        guard mode == .embedded, let screen = screens.first else { return }
        switch item {
        case .widget(let index):
            guard screen.widgets.indices.contains(index) else { return }
            screen.widgets[index].move(anchor: anchor, offset: offset)
        case .passwordField:
            guard var field = screen.auth else { return }
            field.spec.anchor = anchor
            field.spec.offset = offset
            screen.auth = field
        }
        screen.layoutSubtreeIfNeeded()
    }

    /// The glance state ends at the first key press or mouse movement: the password field appears, and
    /// goes away again after `idle` seconds without either.
    private func activity() {
        guard let auth, let screen = screens.first else { return }
        if !screen.authVisible {
            screen.setAuthVisible(true, dim: auth.dim, animated: true)
            screen.focusField()
            runtime?.queue.async { [runtime] in runtime?.emit("auth_shown") }
        }
        idleTimer?.cancel()
        idleTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(auth.idle))
            guard !Task.isCancelled, let self, let screen = screens.first, authModel.password.isEmpty else { return }
            screen.setAuthVisible(false, dim: auth.dim, animated: true)
            runtime?.queue.async { [runtime] in runtime?.emit("auth_hidden") }
        }
    }

    // MARK: Power

    /// Whether every lock screen is still: shaders draw once, videos stay on their first frame, and numbers do not
    /// roll. Low Power Mode and Reduce Motion already ask for less; battery_saver asks for it on battery too.
    static func still(lowPower: Bool, reduceMotion: Bool, onBattery: Bool, batterySaver: Bool) -> Bool {
        lowPower || reduceMotion || (batterySaver && onBattery)
    }

    private var stillNow: Bool {
        Self.still(lowPower: Power.lowPowerMode, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                   onBattery: Power.onBattery, batterySaver: options.settings.batterySaver)
    }

    /// The Mac went on battery or off it, into Low Power Mode or out of it, or Reduce Motion changed: the lock is
    /// drawn again, still or moving, with each widget's latest view and what was typed.
    private func powerChanged() {
        let now = stillNow
        guard now != still else { return }
        still = now
        LogFile.shared.write(level: "info", message: now ? "still on" : "still off", source: "locky")
        if mode == .lock { rebuildForDisplays() }
    }

    /// The timers that input restarts: display_off (lock only; the system's display sleep without it, since the lock's
    /// assertion holds that back), and the ambient mode. Input also tells the field whether Caps Lock is on.
    private func watchInput() {
        if mode == .lock, let seconds = Power.displayOffSeconds(setting: options.settings.displayOff, system: Power.systemDisplaySleep) {
            // The ambient mode's timer: once the quiet time is up the displays go off, and input starts it again.
            displayOff = AmbientTimer(after: seconds, clock: ContinuousClock()) { off in if off { Power.sleepDisplays() } }
        }
        if let seconds = options.settings.ambientAfter {
            ambient = AmbientTimer(after: seconds, clock: ContinuousClock()) { [weak self] on in self?.setAmbient(on) }
        }
        inputMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            self?.noteInput(event)
            return event
        }
        // Everything on the screen is the lock: any mouse input is input to it. Mouse events need no permission here.
        guard mode == .lock else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) {
            [weak self] event in
            MainActor.assumeIsolated { self?.noteInput(event) }
        }
    }

    /// Input to the lock, from the event monitor or the event tap.
    private func noteInput(_ event: NSEvent) {
        displayOff?.noteActivity()
        ambient?.noteActivity()
        if event.type == .flagsChanged { authModel.capsLock = Self.capsLock(event.modifierFlags) }
    }

    /// Whether Caps Lock is on in `flags`. A tool run (screenshots) can say it is with LOCKY_CAPS_LOCK=on.
    static func capsLock(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.capsLock) || (AppDelegate.isTool && ProcessInfo.processInfo.environment["LOCKY_CAPS_LOCK"] == "on")
    }

    /// The ambient mode starts or ends on every screen. It ends with the field holding the keyboard, so the key that
    /// ended it lands there.
    private func setAmbient(_ on: Bool) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        screens.forEach { $0.setAmbient(on, reduceMotion: reduceMotion) }
        if !on { screens.first?.focusField() }
    }

    // MARK: Safety

    /// ⌃⌥⌘Q. Only these four keys count, so Caps Lock or Fn being on does not stop it.
    static func isEmergencyExit(_ event: NSEvent) -> Bool {
        event.type == .keyDown && event.keyCode == 12
            && event.modifierFlags.intersection([.control, .option, .command, .shift]) == [.control, .option, .command]
    }

    /// Locks the Mac with the macOS lock screen, then ends this lock once that screen is up, so the desktop
    /// never shows between the two: a way out that never lets anyone in. When the macOS lock is out of reach,
    /// this lock stays.
    private func handOver(_ reason: String) {
        guard mode == .lock, !ended, !handingOver else { return }
        guard SystemLock.engage(reason: reason) else {
            LogFile.shared.write(level: "error", message: "cannot switch to the macOS lock screen (\(reason)); the lock stays", source: "locky")
            // A lock that stays must hold the keyboard, or typing goes to the app behind it: ask again, and check.
            keyboardTaken()
            return
        }
        handingOver = true
        LogFile.shared.write(level: "warn", message: "switching to the macOS lock screen: \(reason)", source: "locky")
        Task { [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                if Self.systemLocked {
                    self?.end("handed over to the macOS lock screen")
                    return
                }
            }
            guard let self, !ended else { return }
            handingOver = false
            LogFile.shared.write(level: "error", message: "the macOS lock screen did not come up (\(reason)); the lock stays", source: "locky")
            keyboardTaken()
        }
    }

    /// The macOS lock screen is up.
    private static var systemLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
    }

    /// settings.json's emergency_exit, on unless false: ⌃⌥⌘Q switches to the macOS lock screen.
    private var emergencyExit: Bool { options.settings.emergencyExit }

    private func installEmergencyExit() {
        guard emergencyExit else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isEmergencyExit(event) else { return event }
            self?.handOver("⌃⌥⌘Q")
            return nil
        }
    }
}

/// The last lock that showed another theme because the chosen one failed to load, for the Themes window and the menu.
/// UserDefaults keeps it under "lastThemeFailure" as JSON data: {"theme", "fallback", "message", "date"}, the date
/// in seconds since 1970.
/// The last lock's theme that did not load, and the theme Locky showed instead. The lock records it in
/// UserDefaults ("lastThemeFailure") as JSON: { "theme", "fallback", "message", "date" }.
struct ThemeFailure: Codable, Equatable {
    var theme: String
    var fallback: String
    /// The theme's first problem.
    var message: String
    /// Seconds since 1970.
    var date: Double

    static let key = "lastThemeFailure"

    func record(in defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}

final class PreviewWindow: NSWindow {
    var unconstrained = false

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        unconstrained ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

/// A shield over one display: a panel that takes the keyboard without activating Locky. Since macOS 14, an
/// activation is only a request, which macOS refuses when no input reached Locky (a lock an auto-lock started);
/// a non-activating panel still becomes key, so what is typed goes to the lock, not to the app behind it.
final class ShieldWindow: NSPanel {
    /// Only the main display's shield, which holds the password field.
    var allowsKey = true
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { allowsKey }

    private var scene: LockScreenView? { contentView as? LockScreenView ?? (contentView as? TransitionStage)?.scene }

    /// The password field takes every key, whether it comes from macOS or the lock's event tap: a key that finds the field
    /// without the keyboard gives it the keyboard first, so its character lands there. A click anywhere leaves the field
    /// with the keyboard too.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown { scene?.focusField() }
        super.sendEvent(event)
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) { scene?.focusField() }
    }
}

/// One display's lock screen. Flipped, so offsets read like screen coordinates: y grows downwards.
@MainActor
final class LockScreenView: NSView {
    var style = LockyStyle()
    var background: NSView? {
        didSet {
            guard oldValue !== background else { return }
            oldValue?.removeFromSuperview()
            // The password field's dim goes onto the new background at the next layout.
            dimLayer.removeFromSuperlayer()
            if let background {
                // Part of the scene, which shows when revealed.
                if !revealed { background.alphaValue = 0 }
                addSubview(background, positioned: .below, relativeTo: nil)
            }
            needsLayout = true
        }
    }
    /// A background fading in over `background` once it has loaded.
    private var incomingBackground: NSView?
    /// The background the screen shows, or is about to: the one a change applies to.
    var latestBackground: NSView? { incomingBackground ?? background }
    /// What changes after the scene showed fades: a widget that measures late, a new background, a removed widget.
    /// Off in the theme editor's preview, where keys cause those changes: they happen at once.
    var fadesIn = true
    /// Called after each layout: the theme editor's canvas follows the widgets.
    var onLayout: (() -> Void)?
    private(set) var widgets: [WidgetHost] = []
    /// Above the widgets, below the password field and banners.
    var overlay: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            // Above everything there is so far; the password field and banners come later and go on top.
            if let overlay {
                if !revealed { overlay.alphaValue = 0 }
                if let above = auth?.view ?? banner { addSubview(overlay, positioned: .below, relativeTo: above) } else { addSubview(overlay) }
            }
            needsLayout = true
        }
    }
    var auth: (view: NSView, spec: Theme.Auth)? {
        didSet {
            needsLayout = true
            // A new place for the same field moves it; a new field replaces it.
            guard oldValue?.view !== auth?.view else { return }
            oldValue?.view.removeFromSuperview()
            if let auth {
                addSubview(auth.view)
                // A new look for the field enters where the old one was in its entrance.
                enter(auth.view, slot: Self.fieldSlot, continuing: oldValue != nil)
            }
        }
    }
    var authSize: CGSize = .zero { didSet { needsLayout = true } }
    private(set) var authVisible = true
    /// Where a hidden password field will appear: "Press any key to unlock". Under the field, which takes the clicks.
    var glanceHint: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let glanceHint {
                glanceHint.alphaValue = authVisible ? 0 : 1
                if let field = auth?.view { addSubview(glanceHint, positioned: .below, relativeTo: field) } else { addSubview(glanceHint) }
                enter(glanceHint, slot: Self.fieldSlot)
            }
            needsLayout = true
        }
    }
    private let dimLayer = CALayer()

    /// SwiftUI's text field in the password field, once it has made it.
    private var textField: NSTextField? {
        func find(_ view: NSView) -> NSTextField? { (view as? NSSecureTextField) ?? view.subviews.lazy.compactMap(find).first }
        return auth.flatMap { find($0.view) }
    }

    /// The password field has its window's keyboard: its field editor is the first responder.
    var fieldHasKeyboard: Bool {
        guard let field = textField, let editor = window?.firstResponder as? NSText else { return false }
        return (editor.delegate as AnyObject?) === field
    }

    /// Gives the password field its window's keyboard, unless it has it or is disabled: during a check, the wait after
    /// wrong passwords, and always in the theme editor's preview. A hidden field (a theme that shows it on activity, the
    /// ambient mode) takes it too, so the first key counts. false: the field does not have the keyboard.
    @discardableResult func focusField() -> Bool {
        guard let window, let view = auth?.view else { return false }
        if textField == nil {
            // SwiftUI makes the text field at the hosting view's first layout.
            layoutSubtreeIfNeeded()
            view.layoutSubtreeIfNeeded()
        }
        guard let field = textField, field.isEnabled else { return false }
        return fieldHasKeyboard || window.makeFirstResponder(field)
    }

    /// The ambient mode: only the background and the overlay show, and they go on moving as they were. Everything else
    /// fades out with an additive opacity animation, so what shows or hides meanwhile (a widget measured late, the
    /// glance) keeps its own alpha for when it comes back. The field keeps the keyboard.
    private(set) var ambient = false

    func setAmbient(_ on: Bool, reduceMotion: Bool) {
        guard on != ambient else { return }
        ambient = on
        // Out slowly, as the scene settles; back at once, as the person who touched the Mac is looking.
        let duration: CFTimeInterval = on ? (reduceMotion ? 0.2 : 0.6) : 0.3
        let timing = CAMediaTimingFunction(name: on ? .easeInEaseOut : .easeOut)
        for layer in ambientLayers { Self.fade(layer, out: on, duration: duration, timing: timing) }
    }

    /// What the ambient mode hides: the widgets, the password field and its lines, the banner, and the field's dim.
    private var ambientLayers: [CALayer] {
        let views: [NSView] = widgets + [auth?.view, glanceHint, message?.view, wayOut?.view, banner].compactMap { $0 }
        return views.compactMap(\.layer) + [dimLayer]
    }

    private static let ambientKey = "locky.ambient"

    /// Fades `layer` out of the ambient mode's view or back, from where an interrupted fade is.
    private static func fade(_ layer: CALayer, out: Bool, duration: CFTimeInterval, timing: CAMediaTimingFunction?) {
        let running = layer.animation(forKey: ambientKey) != nil
        guard out || running else { return }
        let from: Float = !running ? 0 : layer.presentation().map { max(-1, min(0, $0.opacity - layer.opacity)) } ?? -1
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.isAdditive = true
        // Core Animation reads a duration of 0 as its default: a hold starts where it ends.
        animation.fromValue = duration == 0 ? -1 : from
        animation.toValue = out ? -1 : 0
        animation.duration = duration
        animation.timingFunction = timing
        if out {
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
        }
        layer.add(animation, forKey: ambientKey)
    }

    /// Shows or hides the password field. Hidden, it keeps the keyboard focus, so the first key counts. The key or
    /// the mouse that shows it gets the field at once, and only the dim eases in; hiding after idle, when nobody
    /// watches, fades.
    func setAuthVisible(_ visible: Bool, dim: Double, animated: Bool) {
        authVisible = visible
        let (field, hint): (CGFloat, CGFloat) = visible ? (1, 0) : (0.011, 1)
        if animated, !visible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                auth?.view.animator().alphaValue = field
                glanceHint?.animator().alphaValue = hint
            }
        } else {
            auth?.view.alphaValue = field
            glanceHint?.alphaValue = hint
        }
        // A brightness change eases, also when the field came at once.
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(visible ? 0.2 : 0.35)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: visible ? .easeOut : .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        dimLayer.opacity = visible ? Float(dim) : 0
        CATransaction.commit()
    }
    var banner: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let banner { addSubview(banner) }
            needsLayout = true
        }
    }
    /// The lock screen message, above the password field.
    var message: NSHostingController<LockMessage>? {
        didSet {
            oldValue?.view.removeFromSuperview()
            if let message {
                if let banner { addSubview(message.view, positioned: .below, relativeTo: banner) } else { addSubview(message.view) }
                enter(message.view, slot: Self.fieldSlot)
            }
            needsLayout = true
        }
    }
    /// The line that names ⌃⌥⌘Q, in a row of its own: when it joins, the message stays where it is.
    var wayOut: NSHostingController<LockMessage>? {
        didSet {
            oldValue?.view.removeFromSuperview()
            if let wayOut {
                if let banner { addSubview(wayOut.view, positioned: .below, relativeTo: banner) } else { addSubview(wayOut.view) }
                enter(wayOut.view, slot: Self.fieldSlot)
                // SwiftUI can show the line after a layout pass measured it empty: it asks for another one.
                wayOut.rootView.changed = { [weak self] in self?.needsLayout = true }
            }
            needsLayout = true
        }
    }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        dimLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.opacity = 0
        dimLayer.zPosition = 1
    }

    required init?(coder: NSCoder) { fatalError() }

    private var revealed = false
    private var shown = Set<ObjectIdentifier>()

    func add(_ widget: WidgetHost) {
        widgets.append(widget)
        widget.alphaValue = 0
        // A layer from the start: the ambient mode fades it.
        widget.wantsLayer = true
        widget.onResize = { [weak self] in self?.needsLayout = true }
        // Widgets stay under an overlay, if the theme has one, and always under the password field, its message, and
        // banners: a widget placed where the field is must not cover it.
        if let above = overlay ?? auth?.view ?? message?.view ?? wayOut?.view ?? banner {
            addSubview(widget, positioned: .below, relativeTo: above)
        } else {
            addSubview(widget)
        }
    }

    /// Takes a widget off the screen: at once in the theme editor's preview, where a key removed it; else fading out.
    func remove(_ widget: WidgetHost) {
        widgets.removeAll { $0 === widget }
        shown.remove(ObjectIdentifier(widget))
        guard fadesIn else {
            widget.removeFromSuperview()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            widget.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { widget.removeFromSuperview() }
        })
    }

    /// The widgets in this order, the last one in front: the theme editor's list after a change.
    func arrange(_ list: [WidgetHost]) {
        let reordered = list.map(ObjectIdentifier.init) != widgets.map(ObjectIdentifier.init)
        widgets = list
        guard reordered else { return }
        let above = overlay ?? auth?.view ?? message?.view ?? wayOut?.view ?? banner
        for widget in list where widget.superview === self {
            if let above { addSubview(widget, positioned: .below, relativeTo: above) } else { addSubview(widget) }
        }
    }

    /// A new background over the old one once it has loaded, so the screen never goes blank. It replaces one still
    /// loading.
    func replaceBackground(with view: NSView) {
        incomingBackground?.removeFromSuperview()
        incomingBackground = nil
        guard let old = background else {
            background = view
            return
        }
        view.alphaValue = 0
        view.frame = bounds
        addSubview(view, positioned: .above, relativeTo: old)
        incomingBackground = view
        Task { [weak self] in
            // Two seconds at most for a picture or a video to load.
            let deadline = Date().addingTimeInterval(2)
            while !((view as? BackgroundLoading)?.isLoaded ?? true), Date() < deadline {
                try? await Task.sleep(for: .milliseconds(30))
            }
            guard let self, incomingBackground === view else { return }
            // At once: only the theme editor's preview replaces a background (reload), and it fades in as a whole.
            view.alphaValue = 1
            incomingBackground = nil
            background = view
        }
    }

    /// Lays out at once, with nothing animated: the theme editor's keys move widgets up to 30 times a second.
    func layoutNow() {
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    /// Shows the scene: the background, the overlay, and each widget that knows its size. Animated, it fades them in the
    /// caller's animation group, which the session runs over every screen at once. A widget that measures later shows
    /// alone.
    func reveal(animated: Bool) {
        // Widgets at their places before they show.
        layoutSubtreeIfNeeded()
        revealed = true
        var scene = [background, overlay].compactMap { $0 }
        for widget in widgets where Self.measured(widget) && !shown.contains(ObjectIdentifier(widget)) {
            shown.insert(ObjectIdentifier(widget))
            scene.append(widget)
        }
        for view in scene {
            if animated, let widget = view as? WidgetHost, entering(widget) { continue }
            if animated { view.animator().alphaValue = 1 } else { view.alphaValue = 1 }
        }
    }

    // MARK: The lock's way in and out (LockTransition)

    /// While a lock comes in: when its items' entrance starts, in the layer's time. The widgets enter from 0.25 s in turn,
    /// 40 ms apart, and the password field with its lines last. An item that shows later enters at its turn, or at once
    /// when its turn has passed. nil: items show as they always do.
    var entrance: CFTimeInterval? {
        didSet {
            guard entrance != nil else { return }
            for (view, slot) in items { enter(view, slot: slot, continuing: true) }
        }
    }

    /// The password field, its hint, the message, and the way out enter after the widgets.
    private static let fieldSlot = 3

    /// What enters and leaves: the widgets that show and the password field with its lines. The background and the
    /// overlay come with the scene.
    private var items: [(view: NSView, slot: Int)] {
        var list = widgets.filter { shown.contains(ObjectIdentifier($0)) }.enumerated().map { ($0.element as NSView, min($0.offset, 2)) }
        list += [auth?.view, glanceHint, message?.view, wayOut?.view].compactMap { $0.map { ($0, Self.fieldSlot) } }
        return list
    }

    /// Starts `view`'s entrance at its slot's turn. A view new to the screen whose turn has passed starts now, so it never
    /// shows halfway; one that takes another's place (`continuing`) goes on from where that one was.
    private func enter(_ view: NSView, slot: Int, continuing: Bool = false) {
        guard let entrance, let layer = view.layer else { return }
        var begin = entrance + 0.25 + 0.04 * CFTimeInterval(slot)
        if !continuing { begin = max(begin, layer.convertTime(CACurrentMediaTime(), from: nil)) }
        LockTransition.enter(layer, at: begin)
    }

    /// A widget that shows during the entrance: it shows at once, and its entrance animation brings it in. false after the
    /// entrance, when it fades in alone, as always.
    private func entering(_ widget: WidgetHost) -> Bool {
        guard entrance != nil, let slot = widgets.firstIndex(where: { $0 === widget }) else { return false }
        widget.alphaValue = 1
        enter(widget, slot: min(slot, 2))
        return true
    }

    /// The lock goes out: every item leaves at `start`, in `duration`, and stays gone.
    func exit(at start: CFTimeInterval, duration: CFTimeInterval = 0.18) {
        entrance = nil
        for (view, _) in items { if let layer = view.layer { LockTransition.exit(layer, at: start, duration: duration) } }
    }

    /// The preview only: every item as it was before the way in or out.
    func resetTransition() {
        entrance = nil
        for (view, _) in items { if let layer = view.layer { LockTransition.removeItemAnimations(layer) } }
    }

    private static func measured(_ widget: WidgetHost) -> Bool { widget.placement.size != nil || widget.model.contentSize.width > 0 }

    override func layout() {
        super.layout()
        background?.frame = bounds
        incomingBackground?.frame = bounds
        overlay?.frame = bounds
        if dimLayer.superlayer == nil, let backgroundLayer = background?.layer {
            backgroundLayer.addSublayer(dimLayer)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimLayer.frame = bounds
        CATransaction.commit()
        let scale = Layout.scale(for: bounds.size)
        for widget in widgets {
            widget.frame = widget.frame(in: bounds, scale: scale)
            // Measured after the scene showed: alone, as the scene came in.
            if revealed, Self.measured(widget), !shown.contains(ObjectIdentifier(widget)) {
                shown.insert(ObjectIdentifier(widget))
                if entering(widget) {
                    continue
                } else if fadesIn {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.25
                        context.timingFunction = Motion.easeOut
                        widget.animator().alphaValue = 1
                    }
                } else {
                    widget.alphaValue = 1
                }
            }
        }
        if let auth {
            if authSize.width > 0 {
                let offset = CGPoint(x: auth.spec.offset.x * scale, y: auth.spec.offset.y * scale)
                // An offset past the edge must not push the field off the screen.
                let frame = auth.spec.anchor.frame(size: authSize, offset: offset, in: bounds)
                auth.view.frame = Layout.keep(frame, inside: bounds, margin: 16 * scale).integral
            } else {
                auth.view.frame = bounds
            }
        }
        if let glanceHint, let field = auth?.view.frame {
            let size = glanceHint.fittingSize
            glanceHint.frame = CGRect(x: field.midX - size.width / 2, y: field.midY - size.height / 2, width: size.width, height: size.height).integral
        }
        if let message {
            message.view.frame = messageFrame(size: message.sizeThatFits(in: CGSize(width: 520 * scale, height: 400 * scale)), scale: scale)
        }
        if let wayOut {
            let size = wayOut.sizeThatFits(in: CGSize(width: 520 * scale, height: 400 * scale))
            wayOut.view.frame = wayOutFrame(size: size, message: message?.view.frame ?? .zero, scale: scale)
        }
        banner?.frame = CGRect(x: 16, y: 16, width: min(bounds.width - 32, 640), height: 200)
        // What joined the screen during the ambient mode stays hidden with the rest.
        if ambient {
            for layer in ambientLayers where layer.animation(forKey: Self.ambientKey) == nil {
                Self.fade(layer, out: true, duration: 0, timing: nil)
            }
        }
        onLayout?()
    }

    /// Under the password field (and its hint) when there is room, otherwise above it; centered on it, or
    /// lined up with its left edge when the theme lines the hint up that way (a terminal prompt).
    func messageFrame(size: CGSize, scale: CGFloat) -> CGRect {
        let gap = 14 * scale
        guard let frame = auth?.view.frame, let spec = auth?.spec, authSize.width > 0 else {
            return CGRect(x: bounds.midX - size.width / 2, y: bounds.maxY - 28 * scale - size.height, width: size.width, height: size.height).integral
        }
        let below = frame.maxY + gap
        let y = below + size.height <= bounds.maxY - 12 * scale ? below : frame.minY - gap - size.height
        let x = spec.hintAlign == "leading" ? frame.minX : frame.midX - size.width / 2
        // A field near an edge (Poster's is at the bottom left) must not push a long message off the screen.
        let kept = Layout.keep(CGRect(x: x, y: y, width: size.width, height: size.height), inside: bounds, margin: 16 * scale)
        return CGRect(x: kept.minX, y: y, width: size.width, height: size.height).integral
    }

    /// The ⌃⌥⌘Q line: under the message, or under the field without one there, when there is room; else above the
    /// field, or above the message when that sits there. Lined up as the message is.
    func wayOutFrame(size: CGSize, message: CGRect, scale: CGFloat) -> CGRect {
        let gap = 14 * scale, spacing = 4 * scale
        guard let field = auth?.view.frame, let spec = auth?.spec, authSize.width > 0 else {
            // Before the field measures itself: over the message, or where the message goes.
            let y = message.isEmpty ? bounds.maxY - 28 * scale - size.height : message.minY - spacing - size.height
            return CGRect(x: bounds.midX - size.width / 2, y: y, width: size.width, height: size.height).integral
        }
        let text = message.isEmpty ? nil : message
        let below = text.flatMap { $0.minY > field.midY ? $0.maxY + spacing : nil } ?? field.maxY + gap
        let above = text.flatMap { $0.maxY < field.midY ? $0.minY - spacing : nil } ?? field.minY - gap
        let y = below + size.height <= bounds.maxY - 12 * scale ? below : above - size.height
        let x = spec.hintAlign == "leading" ? field.minX : field.midX - size.width / 2
        let kept = Layout.keep(CGRect(x: x, y: y, width: size.width, height: size.height), inside: bounds, margin: 16 * scale)
        return CGRect(x: kept.minX, y: y, width: size.width, height: size.height).integral
    }
}

/// Preview only: what went wrong in init.lua, plugins, or the theme.
private struct ProblemsBanner: View {
    let problems: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(problems.prefix(6).enumerated()), id: \.offset) { _, problem in
                Text(problem.split(separator: "\n").first.map(String.init) ?? problem).lineLimit(2)
            }
        }
        .font(.system(size: 11, weight: .medium).monospaced())
        .foregroundStyle(Color(red: 1, green: 0.5, blue: 0.45))
        .padding(10)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

enum Keyboard {
    /// The selected keyboard layout. Text Input Sources must be read on the main thread.
    @MainActor
    static func current() -> LuaValue {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return .table([:]) }
        func property(_ key: CFString) -> String? {
            guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
            return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        }
        let id = property(kTISPropertyInputSourceID) ?? ""
        let name = property(kTISPropertyLocalizedName) ?? id
        let languages: [String] = {
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
            return Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String] ?? []
        }()
        return .table(["id": .string(id), "name": .string(name), "language": .string(languages.first ?? "")])
    }
}
