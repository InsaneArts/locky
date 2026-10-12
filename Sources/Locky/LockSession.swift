import AppKit
import Carbon
import SwiftUI

/// One locked (or previewed) screen: a window per display, the Lua runtime, and the way out.
///
/// The password field never waits for Lua: it appears with the shield, in the last theme's style (or the
/// fallback's), and takes the theme's style when the theme arrives, if nothing has been typed yet.
@MainActor
final class LockSession: NSObject, NSWindowDelegate {
    enum Mode { case preview, lock }

    struct Options {
        var theme: String?
        var previewSize = CGSize(width: 1440, height: 900)
        /// Preview only: open behind other windows without activating, for screenshots.
        var behind = false
    }

    let mode: Mode
    var onEnd: (() -> Void)?

    private let options: Options
    private var runtime: LuaRuntime?
    private var started: LuaRuntime.Started?
    private var windows: [NSWindow] = []
    private var screens: [LockScreenView] = []
    private var hosts: [Int: [WidgetHost]] = [:]
    /// Each widget's latest view and failure, for widgets made later: a rebuilt display, or hosts that did
    /// not exist yet when a widget failed in its init.
    private var latest: [Int: [(WidgetHost) -> Void]] = [:]
    private let authModel = AuthModel()
    private var touchID: TouchID?
    private var touchIDFallback: Task<Void, Never>?
    private var safetyExit: DispatchWorkItem?
    private var autoUnlock: Task<Void, Never>?
    private var keyMonitor: Any?
    private var keyboardObserver: NSObjectProtocol?
    private var activityMonitor: Any?
    private var idleTimer: Task<Void, Never>?
    private var auth: Theme.Auth?
    /// Tells macOS the lock screen is in use, so it does not nap Locky. Idle sleep stays allowed.
    private var napGuard: NSObjectProtocol?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var ended = false
    private let banner = SafetyBanner.Model()

    /// The last theme's password field look, so the next lock's field appears in it at once.
    private static var lastLook: (auth: Theme.Auth, palette: [String: String], font: FontSpec)?

    init(mode: Mode, options: Options) {
        self.mode = mode
        self.options = options
        super.init()
    }

    func begin() {
        napGuard = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Showing the lock screen")
        observeSystem()

        let environment = LuaRuntime.Environment()
        environment.keyboard = Keyboard.current()
        environment.displays = NSScreen.screens.count
        environment.wallpaper = NSScreen.screens.first.flatMap(Wallpaper.picture(for:))?.path
        if let size = (mode == .preview ? CGRect(origin: .zero, size: options.previewSize) : NSScreen.screens.first?.frame)?.size {
            environment.screen = size
        }
        keyboardObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { environment.keyboard = Keyboard.current() } }

        let runtime = LuaRuntime(environment: environment, delegate: LuaRuntime.Delegate(
            present: { [weak self] id, node in Task { @MainActor in self?.deliver(id, replacingViews: true) { $0.present(node) } } },
            failed: { [weak self] id, message, disabled in Task { @MainActor in self?.deliver(id, replacingViews: false) { $0.fail(message, disabled: disabled) } } }
        ))
        self.runtime = runtime

        // A preview kept behind other windows (for screenshots) never asks for Touch ID: its Touch ID view is
        // hidden, so macOS would show its own prompt on top of whatever the user is doing.
        let touchID = TouchID()
        if touchID.isAvailable, !(mode == .preview && options.behind) { self.touchID = touchID }

        // Cover the screen and show the password field first. The theme fills in when Lua is ready.
        openWindows()
        if let first = screens.first {
            let look = Self.lastLook ?? (Theme.fallback.auth, Theme.fallback.palette, Theme.fallback.font)
            installAuth(look.auth, style: LockyStyle(palette: look.palette, font: look.font, scale: Layout.scale(for: first.bounds.size)))
        }
        if mode == .lock {
            armSafety(after: 60)
            reclaimKeyboardSoon()
        }
        // Touch ID starts with the theme's field, or after a second with this one if the theme is slow.
        touchIDFallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { self?.startTouchID() }
        }

        LogFile.shared.write(level: "info", message: "\(mode == .lock ? "lock" : "preview") started", source: "locky")
        Task {
            let started = await runtime.start(theme: options.theme)
            guard !ended else { return }
            apply(started)
        }
    }

    private func deliver(_ id: Int, replacingViews: Bool, _ update: @escaping (WidgetHost) -> Void) {
        // Keep the latest view, and failures after it, for widgets made later.
        if replacingViews { latest[id] = [update] } else { latest[id, default: []].append(update) }
        hosts[id]?.forEach(update)
    }

    func end(_ reason: String) {
        guard !ended else { return }
        ended = true
        LogFile.shared.write(level: "info", message: "\(mode == .lock ? "lock" : "preview") ended: \(reason)", source: "locky")
        runtime?.stop()
        touchID?.stop()
        touchIDFallback?.cancel()
        safetyExit?.cancel()
        autoUnlock?.cancel()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let activityMonitor { NSEvent.removeMonitor(activityMonitor) }
        idleTimer?.cancel()
        if let keyboardObserver { DistributedNotificationCenter.default().removeObserver(keyboardObserver) }
        if mode == .lock { NSApp.presentationOptions = [] }
        if let napGuard { ProcessInfo.processInfo.endActivity(napGuard) }
        observers.forEach { $0.0.removeObserver($0.1) }
        windows.forEach { $0.delegate = nil; $0.orderOut(nil) }
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
        }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.runtime?.realign() }
        guard mode == .lock else { return }
        // A display added, removed, or rearranged during the lock gets covered too.
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.rebuildForDisplays() }
        // Anything that takes the keyboard (another app, a system prompt) gives it back to the password field.
        observe(.default, NSApplication.didResignActiveNotification) { $0.reclaimKeyboard() }
        observe(.default, NSWindow.didResignKeyNotification) { session in
            DispatchQueue.main.async { if !session.ended, !(session.windows.first?.isKeyWindow ?? true) { session.reclaimKeyboard() } }
        }
    }

    private func reclaimKeyboard() {
        guard mode == .lock, !ended else { return }
        NSApp.activate()
        windows.first?.makeKeyAndOrderFront(nil)
        NSApp.presentationOptions = Self.kioskOptions
        authModel.focusRequest += 1
    }

    /// macOS treats activation as a request it may refuse; check a few times that the lock got the keyboard.
    private func reclaimKeyboardSoon() {
        Task { [weak self] in
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !ended else { return }
                if !NSApp.isActive || !(windows.first?.isKeyWindow ?? false) { reclaimKeyboard() }
            }
        }
    }

    // MARK: Windows

    private static let kioskOptions: NSApplication.PresentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching,
                                                                         .disableForceQuit, .disableSessionTermination, .disableHideApplication]

    private func openWindows() {
        switch mode {
        case .preview:
            let window = PreviewWindow(contentRect: CGRect(origin: .zero, size: options.previewSize), styleMask: [.titled, .closable, .resizable],
                                       backing: .buffered, defer: false)
            // A preview for screenshots renders at the size asked for, even beyond the screen's visible area.
            window.unconstrained = options.behind
            window.title = "Locky Preview"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.backgroundColor = .black
            let screen = LockScreenView()
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
        case .lock:
            for (index, screen) in NSScreen.screens.enumerated() {
                let window = ShieldWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                // Only the main display's shield takes the keyboard: a click on another display must not send
                // the typing to a window without a password field.
                window.allowsKey = index == 0
                window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                window.backgroundColor = .black
                window.hasShadow = false
                window.isReleasedWhenClosed = false
                let view = LockScreenView()
                window.contentView = view
                window.setFrame(screen.frame, display: true)
                window.orderFrontRegardless()
                windows.append(window)
                screens.append(view)
            }
            NSApp.activate()
            windows.first?.makeKey()
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
        let panel = AuthPanel(auth: spec, style: style, user: Auth.user, touchID: touchID, model: authModel,
                              unlock: { [weak self] in self?.end("password") },
                              failed: { runtime?.queue.async { runtime?.emit("auth_failed") } },
                              onSize: { [weak screen] size in screen?.authSize = size })
        screen.auth = (NSHostingView(rootView: panel), spec)
    }

    private func startTouchID() {
        touchIDFallback?.cancel()
        touchID?.start { [weak self] in self?.end("Touch ID") }
    }

    private func apply(_ started: LuaRuntime.Started) {
        self.started = started
        let theme = started.theme
        if mode == .preview {
            windows.first?.title = "Locky Preview — \(theme.name)"
            for problem in started.problems { LogFile.shared.write(level: "warn", message: problem, source: "preview") }
        }
        if mode == .lock, started.autoUnlock > 0 { armSafety(after: started.autoUnlock) }
        else if mode == .lock { banner.opensAt = nil; autoUnlock?.cancel(); safetyExit?.cancel() }
        Self.lastLook = (theme.auth, theme.palette, theme.font)
        buildScreens(started)
        startTouchID()

        auth = theme.auth
        if theme.auth.reveal == "activity", authModel.password.isEmpty {
            screens.first?.setAuthVisible(false, dim: theme.auth.dim, animated: false)
            windows.forEach { $0.acceptsMouseMovedEvents = true }
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

        if let first = screens.first {
            let style = LockyStyle(palette: theme.palette, font: theme.font, scale: Layout.scale(for: first.bounds.size))
            // The theme's look, unless typing has begun: replacing the field then would lose it.
            if authModel.password.isEmpty || first.auth == nil {
                touchID?.restartIfRunning()
                installAuth(theme.auth, style: style)
            }
        }
        for (index, screen) in screens.enumerated() {
            let main = index == 0
            let scale = Layout.scale(for: screen.bounds.size)
            let style = LockyStyle(palette: theme.palette, font: theme.font, scale: scale, hour24: started.hour24)
            screen.style = style
            screen.background = Backgrounds.makeView(theme.background, screen: windows[index].screen)
            if let overlay = theme.overlay {
                screen.overlay = Backgrounds.makeView(overlay, screen: windows[index].screen, overlay: true)
            }
            for (offset, placement) in theme.widgets.enumerated() where main || placement.allDisplays {
                let host = WidgetHost(placement: placement, theme: theme, style: style, showsErrors: mode == .preview)
                screen.add(host)
                if let id = started.instances[offset] {
                    hosts[id, default: []].append(host)
                    latest[id]?.forEach { $0(host) }
                } else {
                    host.fail("theme \(theme.id): no widget named \"\(placement.widget)\"", disabled: true)
                }
            }
            if main {
                if mode == .lock { screen.banner = NSHostingView(rootView: SafetyBanner(model: banner)) }
                if mode == .preview, !started.problems.isEmpty {
                    screen.banner = NSHostingView(rootView: ProblemsBanner(problems: started.problems))
                }
            }
            screen.reveal()
        }
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

    // MARK: Safety

    /// Prototype only. The lock opens after `seconds`. If the main thread hangs, a timer on another thread
    /// ends the process 5 s later, which takes the shield with it. ⌃⌥⌘Q quits at once.
    private func armSafety(after seconds: Double) {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Only these four keys count, so Caps Lock or Fn being on does not stop it.
                if event.modifierFlags.intersection([.control, .option, .command, .shift]) == [.control, .option, .command], event.keyCode == 12 { exit(0) }
                return event
            }
        }
        safetyExit?.cancel()
        autoUnlock?.cancel()
        let exitLater = DispatchWorkItem { exit(0) }
        safetyExit = exitLater
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds + 5, execute: exitLater)
        banner.opensAt = Date().addingTimeInterval(seconds)
        autoUnlock = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.end("auto_unlock") }
        }
    }
}

final class PreviewWindow: NSWindow {
    var unconstrained = false

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        unconstrained ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

final class ShieldWindow: NSWindow {
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
            oldValue?.removeFromSuperview()
            if let background { addSubview(background, positioned: .below, relativeTo: nil) }
            needsLayout = true
        }
    }
    private(set) var widgets: [WidgetHost] = []
    /// Above the widgets, below the password field and banners.
    var overlay: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            // Above everything there is so far; the password field and banners come later and go on top.
            if let overlay {
                if let above = auth?.view ?? banner { addSubview(overlay, positioned: .below, relativeTo: above) } else { addSubview(overlay) }
            }
            needsLayout = true
        }
    }
    var auth: (view: NSView, spec: Theme.Auth)? {
        didSet {
            oldValue?.view.removeFromSuperview()
            if let auth { addSubview(auth.view) }
            needsLayout = true
        }
    }
    var authSize: CGSize = .zero { didSet { needsLayout = true } }
    private(set) var authVisible = true
    private let dimLayer = CALayer()

    /// Shows or hides the password field. Hidden, it keeps the keyboard focus, so the first key counts.
    func setAuthVisible(_ visible: Bool, dim: Double, animated: Bool) {
        authVisible = visible
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.35 : 0
            context.allowsImplicitAnimation = true
            auth?.view.animator().alphaValue = visible ? 1 : 0.011
            dimLayer.opacity = visible ? Float(dim) : 0
        }
    }
    var banner: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let banner { addSubview(banner) }
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
        // Widgets stay under an overlay, if the theme has one.
        if let overlay { addSubview(widget, positioned: .below, relativeTo: overlay) } else { addSubview(widget) }
    }

    /// Lets the themed content fade in, each widget once it knows its size.
    func reveal() {
        revealed = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        background?.frame = bounds
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
            let measured = widget.placement.size != nil || widget.model.contentSize.width > 0
            if revealed, measured, !shown.contains(ObjectIdentifier(widget)) {
                shown.insert(ObjectIdentifier(widget))
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.35
                    widget.animator().alphaValue = 1
                }
            }
        }
        if let auth {
            if authSize.width > 0 {
                let offset = CGPoint(x: auth.spec.offset.x * scale, y: auth.spec.offset.y * scale)
                auth.view.frame = auth.spec.anchor.frame(size: authSize, offset: offset, in: bounds).integral
            } else {
                auth.view.frame = bounds
            }
        }
        banner?.frame = CGRect(x: 16, y: 16, width: min(bounds.width - 32, 640), height: 200)
    }
}

/// Prototype only: says how the lock opens without a password.
struct SafetyBanner: View {
    @MainActor @Observable
    final class Model {
        var opensAt: Date?
    }

    let model: Model

    var body: some View {
        if let opensAt = model.opensAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Prototype · opens in \(max(0, Int(opensAt.timeIntervalSince(context.date).rounded()))) s · ⌃⌥⌘Q quits")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(.black.opacity(0.35), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
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
