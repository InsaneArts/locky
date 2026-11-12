import AppKit
import ImageIO
import SwiftUI

/// Settings › Lock Screen's picture of the lock animation: the chosen style plays in miniature on the theme in use, over a
/// stand-in desktop, again and again. The way in, a moment locked, the way out, a moment of the desktop. One embedded
/// screen plays every loop. It plays only while the Settings window is in front and shows; otherwise, and with Reduce
/// Motion, the theme's picture stands still in its place.
struct TransitionPreview: NSViewRepresentable {
    var style: LockTransition.Style
    var theme: String
    /// The app's copy of settings.json, which the screen applies as a lock would.
    var settings: Settings
    /// The config folder Lua reads, the store's.
    var config: URL
    /// The theme's info, for its picture.
    var info: Inspection.ThemeInfo?
    var reduceMotion: Bool

    func makeNSView(context: Context) -> TransitionPreviewView { TransitionPreviewView() }

    func updateNSView(_ view: TransitionPreviewView, context: Context) {
        view.still = info.flatMap(ThemeThumbnails.image(for:)) ?? ThemeThumbnails.bundled(theme)
        view.reduceMotion = reduceMotion
        view.style = style
        view.show(TransitionPreviewView.Key(theme: theme, settings: ThemePreviewView.Key.shared(settings), config: config), settings: settings)
    }

    static func dismantleNSView(_ view: TransitionPreviewView, coordinator: ()) {
        view.stop()
    }
}

@MainActor
final class TransitionPreviewView: NSView {
    /// What a new screen takes: another theme, or another value the screen shows, starts one.
    struct Key: Equatable {
        var theme: String
        var settings: Settings
        var config: URL
    }

    /// Plays only in the key window while it shows, and not with Reduce Motion.
    nonisolated static func plays(isKey: Bool, visible: Bool, reduceMotion: Bool) -> Bool {
        isKey && visible && !reduceMotion
    }

    var style = LockTransition.Style.focus {
        didSet { if style != oldValue, stage != nil { play() } }
    }
    var reduceMotion = false {
        didSet { if reduceMotion != oldValue { advance() } }
    }
    /// The theme's picture, shown while nothing plays.
    var still: NSImage? {
        didSet { if session == nil { clip.layer?.contents = still } }
    }

    /// Rounds the corners; its layer shows the still picture, or the desktop while the screen loads.
    private let clip = NSView()
    /// Holds the screen at the layout size; its frame is the scaled-down size.
    private let holder = NSView()
    private var key: Key?
    private var settings = Settings()
    private var session: LockSession?
    private var container: NSView?
    private var stage: TransitionStage?
    private var loop: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    /// The stand-in desktop and its blurred copy, made once.
    private lazy var desktop: (picture: CGImage?, blurred: CGImage?) = {
        let picture = StandInDesktop.picture(size: ThemePreviewView.layoutSize, scale: 0.5, wallpaper: Self.wallpaper())
        return (picture, picture.flatMap { StandInDesktop.blurred($0, scale: 0.5) })
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clip.wantsLayer = true
        clip.layer?.cornerRadius = 8
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.layer?.contentsGravity = .resizeAspectFill
        holder.wantsLayer = true
        clip.addSubview(holder)
        addSubview(clip)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Preview of the lock animation")
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The user's desktop picture when it is an image file Locky can read, made small: else the stand-in's gradient.
    private static func wallpaper() -> CGImage? {
        guard let screen = NSScreen.main, let url = Wallpaper.picture(for: screen),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                               kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary)
    }

    func show(_ key: Key, settings: Settings) {
        self.settings = settings
        if key != self.key {
            self.key = key
            endSession()
        }
        advance()
    }

    func stop() {
        key = nil
        endSession()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// Whether a screen runs now, loading or playing.
    var isRunning: Bool { session != nil }

    private var plays: Bool {
        Self.plays(isKey: window?.isKeyWindow ?? false, visible: window?.occlusionState.contains(.visible) ?? false, reduceMotion: reduceMotion)
    }

    /// Starts a screen when the preview should play and has none; ends it when it should not.
    private func advance() {
        guard plays, let key else {
            endSession()
            return
        }
        guard session == nil else { return }
        // The desktop until the screen is ready: the loop starts with the way in over it.
        clip.layer?.contents = desktop.picture
        let container = NSView(frame: CGRect(origin: .zero, size: ThemePreviewView.layoutSize))
        container.wantsLayer = true
        holder.addSubview(container)
        var options = LockSession.Options(theme: key.theme, previewSize: ThemePreviewView.layoutSize, settings: settings, container: container,
                                          remembers: false)
        options.path = .standard(config: key.config)
        let session = LockSession(mode: .embedded, options: options)
        session.onReady = { [weak self, weak session] in
            if let self, let session { ready(session) }
        }
        self.session = session
        self.container = container
        needsLayout = true
        session.begin()
    }

    /// The screen goes on a stage over the stand-in desktop, and the loop starts.
    private func ready(_ session: LockSession) {
        guard session === self.session, let container, let scene = container.subviews.first as? LockScreenView else { return }
        let picture = NSView()
        picture.wantsLayer = true
        picture.layer?.contents = desktop.picture
        picture.layer?.contentsGravity = .resize
        let backdrop = LockTransition.backdrop(reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                                               picture: desktop.blurred)
        let stage = TransitionStage(frame: container.bounds, scene: scene, backdrop: backdrop, desktop: picture)
        container.addSubview(stage)
        self.stage = stage
        play()
    }

    /// Plays the style from its way in, again and again, until the preview stops or the style changes.
    private func play() {
        loop?.cancel()
        guard let stage else { return }
        LockTransition.reset(stage)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let stage = self.stage else { return }
                let style = self.style
                let scene = stage.scene
                let middle = CGPoint(x: scene.bounds.midX, y: scene.bounds.midY)
                LockTransition.comeIn(stage, style: style, origin: middle, at: Self.now(scene), reduceMotion: false)
                guard await Self.wait(LockTransition.length(.lock, style: style)) else { return }
                LockTransition.finishComingIn(stage)
                guard await Self.wait(1.2) else { return }
                let field = scene.auth.map { CGPoint(x: $0.view.frame.midX, y: $0.view.frame.midY) } ?? middle
                LockTransition.goOut(stage, style: style, origin: field, at: Self.now(scene))
                guard await Self.wait(LockTransition.length(.unlock, style: style) + 1) else { return }
                LockTransition.reset(stage)
            }
        }
    }

    private static func now(_ scene: NSView) -> CFTimeInterval {
        scene.layer?.convertTime(CACurrentMediaTime(), from: nil) ?? CACurrentMediaTime()
    }

    /// false when the loop was cancelled meanwhile.
    private static func wait(_ seconds: Double) async -> Bool {
        (try? await Task.sleep(for: .seconds(seconds))) != nil
    }

    private func endSession() {
        loop?.cancel()
        loop = nil
        if let stage { LockTransition.reset(stage) }
        stage = nil
        session?.end("preview stopped")
        session = nil
        container?.removeFromSuperview()
        container = nil
        clip.layer?.contents = still
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else {
            // Another pane, or the window closed.
            endSession()
            return
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.advance() }
            })
        }
        advance()
    }

    override func layout() {
        super.layout()
        clip.frame = bounds
        holder.frame = clip.bounds
        holder.setBoundsSize(ThemePreviewView.layoutSize)
        for view in holder.subviews { view.frame = CGRect(origin: .zero, size: ThemePreviewView.layoutSize) }
    }
}
