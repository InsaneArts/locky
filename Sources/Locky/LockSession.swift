import AppKit
import ApplicationServices
import Carbon
import GuardCore
import SwiftUI

/// One locked (or previewed) screen: a window per display, the Lua runtime, and the way out.
///
/// The password field never waits for Lua: it appears with the shield, in the last theme's style (or the
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
    }

    let mode: Mode
    var onEnd: (() -> Void)?
    /// Embedded only: called once, when the theme shows with each widget drawn and the background loaded (or
    /// after two seconds at most), so a preview can swap this session in without a blank moment.
    var onReady: (() -> Void)?
    /// Instances that have drawn or failed at least once.
    private var heard = Set<Int>()
    /// Embedded only: called after each layout of the screen, so the theme editor's canvas follows the widgets.
    var onLayout: (() -> Void)?

    private let options: Options
    private var runtime: LuaRuntime?
    private var started: LuaRuntime.Started?
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
    /// settings.json's display_off: the displays go dark after that many seconds without input.
    private var displayOff: DisplayOff?
    private var inputMonitor: Any?
    /// Asks to activate Locky at the lock's first input, so its kiosk options apply.
    private var activationMonitor: Any?
    /// When to take a photo of whoever types wrong passwords, and the photos this lock took.
    private lazy var intruder = IntruderPolicy(settings: options.settings)
    private(set) var photos: [URL] = []
    private var capturing: Task<Void, Never>?

    /// The last theme's password field look, so the next lock's field appears in it at once.
    private static var lastLook: (auth: Theme.Auth, palette: [String: String], font: FontSpec)?
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
        if mode == .lock {
            // Before the shield activates Locky.
            if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() { previousApp = front }
            lockGuard = LockGuard { [weak self] reason in self?.handOver(reason) }
            // Without its guard, a crash would leave the shield's open session behind: the macOS lock instead.
            if lockGuard == nil { handOver("the guard did not start") }
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
        if let size = (mode == .lock ? NSScreen.screens.first?.frame : CGRect(origin: .zero, size: options.previewSize))?.size {
            environment.screen = size
        }
        keyboardObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { environment.keyboard = Keyboard.current() } }

        // The app's copy of settings.json: while the file has an error, that is the last one that read without one.
        let runtime = LuaRuntime(path: options.path, environment: environment, settings: options.settings, delegate: LuaRuntime.Delegate(
            present: { [weak self] id, node in Task { @MainActor in self?.deliver(id, replacingViews: true) { $0.present(node) } } },
            failed: { [weak self] id, message, disabled in Task { @MainActor in self?.deliver(id, replacingViews: false) { $0.fail(message, disabled: disabled) } } }
        ))
        self.runtime = runtime

        // A preview kept behind other windows (for screenshots) never asks for Touch ID: its Touch ID view is
        // hidden, so macOS would show its own prompt on top of whatever the user is doing.
        let touchID = TouchID()
        if touchID.isAvailable, mode != .embedded, !(mode == .preview && options.behind), options.settings["touch_id"].bool != false {
            self.touchID = touchID
        } else if touchID.isAvailable, mode != .lock, options.settings["touch_id"].bool != false {
            touchIDPicture = true
        }

        // A check that hangs leaves the field disabled: the message then names ⌃⌥⌘Q, and grows.
        authModel.onSlowCheck = { [weak self] in self?.screens.first?.needsLayout = true }

        // Cover the screen and show the password field first. The theme fills in when Lua is ready.
        openWindows()
        if let first = screens.first {
            let look = Self.lastLook ?? (Theme.fallback.auth, Theme.fallback.palette, Theme.fallback.font)
            installAuth(look.auth, style: LockyStyle(palette: look.palette, font: look.font, scale: Layout.scale(for: first.bounds.size)))
        }
        if mode == .lock {
            installEmergencyExit()
            reclaimKeyboardSoon()
            startDisplayOff()
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
        guard mode == .embedded else { return }
        let ready = onReady
        onReady = nil
        ready?()
    }

    /// Every widget has drawn (or failed) and measured itself, and the background has loaded.
    private var isReady: Bool {
        guard let started, let screen = screens.first else { return false }
        return started.instances.allSatisfy { $0.map(heard.contains) ?? true } && screen.widgets.allSatisfy(\.isSettled)
            && ((screen.background as? BackgroundLoading)?.isLoaded ?? true)
    }

    func end(_ reason: String) {
        guard !ended else { return }
        ended = true
        if mode != .embedded { LogFile.shared.write(level: "info", message: "\(mode == .lock ? "lock" : "preview") ended: \(reason)", source: "locky") }
        lockGuard?.release()
        runtime?.stop()
        touchID?.stop()
        touchIDFallback?.cancel()
        revealTask?.cancel()
        keyboardCheck?.cancel()
        if let keyTap {
            CGEvent.tapEnable(tap: keyTap.port, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), keyTap.source, .commonModes)
            CFMachPortInvalidate(keyTap.port)
        }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let activityMonitor { NSEvent.removeMonitor(activityMonitor) }
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        if let activationMonitor { NSEvent.removeMonitor(activationMonitor) }
        displayOff?.stop()
        powerObserver = nil
        idleTimer?.cancel()
        if let keyboardObserver { DistributedNotificationCenter.default().removeObserver(keyboardObserver) }
        if mode == .lock { NSApp.presentationOptions = [] }
        if let napGuard { ProcessInfo.processInfo.endActivity(napGuard) }
        observers.forEach { $0.0.removeObserver($0.1) }
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
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = Motion.easeOut
                closing.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: {
                MainActor.assumeIsolated { closing.forEach { $0.orderOut(nil) } }
            })
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
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.runtime?.setPaused(true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) {
            $0.runtime?.setPaused(false)
            $0.touchID?.restart()
            $0.displayOff?.noteActivity()
        }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.runtime?.realign() }
        guard mode == .lock else { return }
        // A display added, removed, or rearranged during the lock gets covered too.
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.rebuildForDisplays() }
        // Anything that takes the keyboard (another app, a system prompt) gives it back to the password field.
        observe(.default, NSApplication.didResignActiveNotification) { $0.keyboardTaken() }
        observe(.default, NSWindow.didResignKeyNotification) { session in
            DispatchQueue.main.async { if !session.ended, !(session.windows.first?.isKeyWindow ?? true) { session.keyboardTaken() } }
        }
    }

    private func reclaimKeyboard() {
        guard mode == .lock, !ended else { return }
        NSApp.activate()
        windows.first?.makeKeyAndOrderFront(nil)
        NSApp.presentationOptions = Self.kioskOptions
        authModel.focusRequest += 1
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

    /// Secure keyboard entry is on for another app (Terminal's Secure Keyboard Entry, a focused password field).
    private static var secureInputElsewhere: Bool {
        guard IsSecureEventInputEnabled() else { return false }
        return (CGSessionCopyCurrentDictionary() as? [String: Any])?["kCGSSessionSecureInputPID"] as? Int != Int(getpid())
    }

    private func checkKeyboard(_ reason: String) {
        keyboardCheck = nil
        guard mode == .lock, !ended else { return }
        let secureInput = Self.secureInputElsewhere
        switch Self.keyboardAction(holds: holdsKeyboard, tapped: keyTap != nil, trusted: AXIsProcessTrusted(), secureInput: secureInput) {
        case .keep:
            // While the tap holds the keys, another app may turn secure keyboard entry on: check each second.
            guard !holdsKeyboard else { return }
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
        displayOff?.noteActivity()
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

    private func openWindows() {
        // From the first frame, the last theme's bg: the scene fades in over it.
        let backdrop = Self.backdrop(Self.lastLook?.palette ?? Theme.fallback.palette)
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
            let screen = LockScreenView()
            screen.layer?.backgroundColor = backdrop.cgColor
            window.contentView = screen
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
                window.contentView = view
                window.setFrame(screen.frame, display: true)
                window.orderFrontRegardless()
                windows.append(window)
                screens.append(view)
            }
            windows.first?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            NSApp.presentationOptions = Self.kioskOptions
        }
        windows.forEach { $0.appearance = NSAppearance(named: .darkAqua) }
    }

    /// New windows for the displays there are now, with the theme and each widget's latest view, without
    /// restarting Lua. The password field keeps what was typed.
    private func rebuildForDisplays() {
        guard mode == .lock, !ended else { return }
        LogFile.shared.write(level: "info", message: "displays changed: \(NSScreen.screens.count) now", source: "locky")
        let old = windows
        windows = []
        screens = []
        hosts = [:]
        openWindows()
        old.forEach { $0.orderOut(nil) }
        if let started { buildScreens(started) } else if let first = screens.first {
            let look = Self.lastLook ?? (Theme.fallback.auth, Theme.fallback.palette, Theme.fallback.font)
            installAuth(look.auth, style: LockyStyle(palette: look.palette, font: look.font, scale: Layout.scale(for: first.bounds.size)))
        }
        touchID?.restart()
        reclaimKeyboard()
    }

    private func installAuth(_ spec: Theme.Auth, style: LockyStyle) {
        guard let screen = screens.first else { return }
        let runtime = self.runtime
        authModel.user = Auth.user(privacy: privacy)
        let panel = AuthPanel(auth: spec, style: style, touchID: touchID, model: authModel,
                              unlock: { [weak self] in self?.end("password") },
                              failed: { [weak self] in
                                  runtime?.queue.async { runtime?.emit("auth_failed") }
                                  self?.wrongPassword()
                              },
                              onSize: { [weak screen] size in screen?.authSize = size }, interactive: mode != .embedded,
                              touchIDPicture: touchIDPicture)
        screen.auth = (NSHostingView(rootView: panel), spec)
    }

    /// The photos this lock took, once a capture still running has finished.
    func photosTaken() async -> [URL] {
        await capturing?.value
        return photos
    }

    /// Counts a wrong password; at settings.json's intruder_photo, takes one photo with the camera. The camera
    /// never asks for permission here: Settings asks when the photo is turned on.
    private func wrongPassword() {
        // From the third, the message names ⌃⌥⌘Q, and grows.
        screens.first?.needsLayout = true
        guard mode == .lock, intruder.wrongPassword() else { return }
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
            self?.authModel.succeeded()
            self?.end("Touch ID")
        }
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
        if mode != .embedded {
            Self.lastLook = (theme.auth, theme.palette, theme.font)
            if options.remembers { Self.lastPrivacy = started.privacy }
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
        let light = (NSColor(hex: theme.palette["bg"] ?? "#000000")?.usingColorSpace(.sRGB)).map {
            0.2126 * $0.redComponent + 0.7152 * $0.greenComponent + 0.0722 * $0.blueComponent > 0.5
        } ?? false
        windows.forEach { $0.appearance = NSAppearance(named: light ? .aqua : .darkAqua) }
        if mode == .embedded { screens.forEach { $0.appearance = NSAppearance(named: light ? .aqua : .darkAqua) } }
        // Under the theme's field until the scene shows: its own bg, as the next lock's first frame has it.
        let backdrop = Self.backdrop(theme.palette)
        windows.forEach { $0.backgroundColor = backdrop }
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
                    host.fail("theme \(theme.id): no widget named \"\(placement.widget)\"", disabled: true)
                }
            }
            if main {
                // In every mode, so a preview shows what a lock shows.
                let scrim = ScrimHost(rootView: LegibilityScrim(color: style.color("bg")))
                scrim.setAccessibilityElement(false)
                screen.scrim = scrim
                // A lock with ⌃⌥⌘Q always has the view: the line naming it may join the message.
                let exit = mode == .lock && emergencyExit
                screen.message = started.message != nil || exit
                    ? NSHostingController(rootView: LockMessage(text: started.message, model: authModel, exit: exit, auth: theme.auth, style: style))
                    : nil
                if mode != .lock, !started.problems.isEmpty {
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
        if next.problems != old.problems {
            screen.banner = next.problems.isEmpty ? nil : NSHostingView(rootView: ProblemsBanner(problems: next.problems))
        }
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
                host.fail("theme \(next.theme.id): no widget named \"\(next.theme.widgets[index].widget)\"", disabled: true)
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

    private func startDisplayOff() {
        guard let seconds = options.settings.displayOff, seconds > 0 else { return }
        let off = DisplayOff(after: seconds, sleep: { Power.sleepDisplays() })
        displayOff = off
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]) {
            [weak off] event in
            off?.noteActivity()
            return event
        }
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
        }
    }

    /// The macOS lock screen is up.
    private static var systemLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
    }

    /// settings.json's emergency_exit, on unless false: ⌃⌥⌘Q switches to the macOS lock screen.
    private var emergencyExit: Bool { options.settings["emergency_exit"].bool != false }

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
    /// The legibility scrim behind the password field, its message, and the glance hint: right above the background,
    /// so it dims neither the widgets nor the overlay above them.
    var scrim: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let scrim {
                if let background { addSubview(scrim, positioned: .above, relativeTo: background) } else { addSubview(scrim, positioned: .below, relativeTo: nil) }
            }
            needsLayout = true
        }
    }
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
            if let auth { addSubview(auth.view) }
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
            }
            needsLayout = true
        }
    }
    private let dimLayer = CALayer()

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
        widget.onResize = { [weak self] in self?.needsLayout = true }
        // Widgets stay under an overlay, if the theme has one, and always under the password field, its message, and
        // banners: a widget placed where the field is must not cover it.
        if let above = overlay ?? auth?.view ?? message?.view ?? banner {
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
        let above = overlay ?? auth?.view ?? message?.view ?? banner
        for widget in list where widget.superview === self {
            if let above { addSubview(widget, positioned: .below, relativeTo: above) } else { addSubview(widget) }
        }
    }

    /// A new background over the old one once it has loaded, so the screen never goes blank: at once in the theme
    /// editor's preview, else faded in. It replaces one still loading.
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
            guard fadesIn else {
                view.alphaValue = 1
                incomingBackground = nil
                background = view
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = Motion.easeOut
                view.animator().alphaValue = 1
            }, completionHandler: {
                MainActor.assumeIsolated { [weak self] in
                    guard let self, incomingBackground === view else { return }
                    incomingBackground = nil
                    background = view
                }
            })
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
            if animated { view.animator().alphaValue = 1 } else { view.alphaValue = 1 }
        }
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
                if fadesIn {
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
        if let scrim {
            // Around the field and its message, with room to fade out. None while the field measures itself.
            if let field = auth?.view.frame, authSize.width > 0 {
                let text = message?.view.frame ?? .zero
                scrim.frame = (text.isEmpty ? field : field.union(text)).insetBy(dx: -48 * scale, dy: -48 * scale).integral
            } else {
                scrim.frame = .zero
            }
        }
        banner?.frame = CGRect(x: 16, y: 16, width: min(bounds.width - 32, 640), height: 200)
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
}

/// The legibility scrim's view. A decoration, like the overlay: it takes no clicks.
final class ScrimHost: NSHostingView<LegibilityScrim> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
