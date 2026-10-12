import AppKit
import SwiftUI

/// A theme's lock screen, live: laid out at 1440×900 like a real screen and scaled down to fit. A change to the
/// theme itself (the editor's) shows in place. Any other change builds the new screen out of sight and fades it in
/// over the old one, so the preview never goes blank. It stops while its window is hidden, so a forgotten window
/// costs nothing.
struct ThemePreview: NSViewRepresentable {
    var theme: String
    /// The app's copy of settings.json, which the preview applies as a lock would.
    var settings: Settings
    /// Changes when a Lua file or an asset changes (Inspection.sources): the preview starts again.
    var sources = 0
    /// The config folder Lua reads, the store's.
    var config = RuntimePath.defaultConfig
    /// Keeps running behind other windows: for screenshots.
    var alwaysLive = false

    func makeNSView(context: Context) -> ThemePreviewView { ThemePreviewView() }

    func updateNSView(_ view: ThemePreviewView, context: Context) {
        view.alwaysLive = alwaysLive
        view.config = config
        view.show(ThemePreviewView.Key(theme: theme, settings: settings, sources: sources))
    }

    static func dismantleNSView(_ view: ThemePreviewView, coordinator: ()) {
        view.stop()
    }
}

@MainActor
final class ThemePreviewView: NSView {
    static let layoutSize = CGSize(width: 1440, height: 900)

    /// What a preview shows: a theme, with settings.json, from Lua files as they are.
    struct Key: Equatable {
        var theme: String
        var settings: Settings
        var sources: Int

        /// Whether showing `next` takes a new session rather than a reload in place: another theme, changed Lua
        /// files, or another settings.json value the screen shows. The first reading of the files (0 before)
        /// changes nothing.
        func needsRestart(for next: Key) -> Bool {
            theme != next.theme || (sources != 0 && sources != next.sources) || Self.shared(settings) != Self.shared(next.settings)
        }

        /// The window's changes to this theme, which a reload in place shows.
        var edit: LuaValue { settings["themes"][theme] }

        /// settings.json's values a preview shows, apart from the window's changes to themes.
        static func shared(_ settings: Settings) -> Settings {
            Settings(settings.values.filter { ["hour24", "privacy", "message", "packs", "battery_saver"].contains($0.key) })
        }
    }

    var alwaysLive = false
    var config = RuntimePath.defaultConfig
    /// Rounds the corners, in screen points.
    private let clip = NSView()
    /// Holds each session's screen at the layout size; its frame is the scaled-down size.
    private let stage = NSView()

    private struct Shown {
        let session: LockSession
        let container: NSView
        var key: Key
    }

    private var current: Shown?
    /// A session loading out of sight, which replaces the current one once it is ready.
    private var incoming: Shown?
    private var wanted: Key?
    private var reloading = false
    private var occlusion: NSObjectProtocol?
    /// When shader animations start: each session of this preview takes up the last one's animation.
    private let epoch = CACurrentMediaTime()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clip.wantsLayer = true
        clip.layer?.backgroundColor = NSColor.black.cgColor
        clip.layer?.cornerRadius = 10
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        stage.wantsLayer = true
        clip.addSubview(stage)
        addSubview(clip)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ key: Key) {
        wanted = key
        advance()
    }

    func stop() {
        wanted = nil
        endSessions()
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
    }

    private var visible: Bool { alwaysLive || (window?.occlusionState.contains(.visible) ?? false) }

    /// Moves toward the wanted key: starts a session, reloads the current one in place, or replaces it.
    private func advance() {
        guard let wanted, visible else { return }
        if let incoming {
            // One that is loading shows the theme's changes once it is in front.
            if incoming.key.needsRestart(for: wanted) { begin(wanted) }
            return
        }
        guard let current else {
            begin(wanted)
            return
        }
        guard current.key != wanted else { return }
        if current.key.needsRestart(for: wanted) {
            begin(wanted)
            return
        }
        // The files read for the first time, or another theme's changes: nothing new to show.
        guard current.key.edit != wanted.edit else {
            self.current?.key = wanted
            return
        }
        guard !reloading else { return }
        reloading = true
        let session = current.session
        Task {
            let shown = await session.reload(settings: wanted.settings)
            reloading = false
            guard self.current?.session === session else { return }
            if shown { self.current?.key = wanted } else { begin(wanted) }
            advance()
        }
    }

    /// Starts a session for `key` out of sight; it fades in once it is ready.
    private func begin(_ key: Key) {
        if let incoming {
            incoming.session.end("replaced")
            incoming.container.removeFromSuperview()
        }
        let container = NSView(frame: CGRect(origin: .zero, size: Self.layoutSize))
        container.wantsLayer = true
        container.alphaValue = 0
        stage.addSubview(container)
        var options = LockSession.Options(theme: key.theme, previewSize: Self.layoutSize, settings: key.settings, container: container, epoch: epoch)
        options.path = .standard(config: config)
        let session = LockSession(mode: .embedded, options: options)
        session.onReady = { [weak self, weak session] in
            if let self, let session { promote(session) }
        }
        incoming = Shown(session: session, container: container, key: key)
        session.begin()
    }

    /// Fades a ready session in over the current one, which ends once it is covered.
    private func promote(_ session: LockSession) {
        guard let incoming, incoming.session === session else { return }
        let old = current
        current = incoming
        self.incoming = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            incoming.container.animator().alphaValue = 1
        }, completionHandler: {
            MainActor.assumeIsolated {
                old?.session.end("replaced")
                old?.container.removeFromSuperview()
            }
        })
        advance()
    }

    private func endSessions() {
        for shown in [current, incoming].compactMap({ $0 }) {
            shown.session.end("preview closed")
            shown.container.removeFromSuperview()
        }
        current = nil
        incoming = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
        guard let window else { return }
        occlusion = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window,
                                                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.visibilityChanged() }
        }
        visibilityChanged()
    }

    /// A hidden preview ends its sessions; it starts again when its window shows.
    private func visibilityChanged() {
        if visible { advance() } else { endSessions() }
    }

    override func layout() {
        super.layout()
        let size = Self.layoutSize
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        guard scale.isFinite, scale > 0 else { return }
        let fitted = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        clip.frame = CGRect(x: ((bounds.width - fitted.width) / 2).rounded(), y: ((bounds.height - fitted.height) / 2).rounded(),
                            width: fitted.width, height: fitted.height)
        stage.frame = clip.bounds
        stage.setBoundsSize(size)
        // Each screen fills the stage at the layout size, whatever size the stage had when the screen was made.
        for container in stage.subviews {
            container.frame = stage.bounds
            for screen in container.subviews { screen.frame = container.bounds }
        }
    }
}
