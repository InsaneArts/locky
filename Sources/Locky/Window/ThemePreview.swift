import AppKit
import SwiftUI

/// A theme's lock screen, live: laid out at 1440×900 like a real screen and scaled down to fit. It reads
/// settings.json when it starts, so it shows the window's latest changes after each restart. It stops
/// while its window is hidden, so a forgotten window costs nothing.
struct ThemePreview: NSViewRepresentable {
    var theme: String
    /// Bumped to start the preview again, after a change to the theme.
    var generation = 0
    /// Keeps running behind other windows: for screenshots.
    var alwaysLive = false

    func makeNSView(context: Context) -> ThemePreviewView { ThemePreviewView() }

    func updateNSView(_ view: ThemePreviewView, context: Context) {
        view.alwaysLive = alwaysLive
        view.show(theme: theme, generation: generation)
    }

    static func dismantleNSView(_ view: ThemePreviewView, coordinator: ()) {
        view.stop()
    }
}

@MainActor
final class ThemePreviewView: NSView {
    static let layoutSize = CGSize(width: 1440, height: 900)

    var alwaysLive = false
    /// Rounds the corners, in screen points.
    private let clip = NSView()
    /// Holds the lock screen at the layout size; its frame is the scaled-down size.
    private let canvas = NSView()
    private var session: LockSession?
    private var shown: (theme: String, generation: Int)?
    private var pending: Task<Void, Never>?
    private var occlusion: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clip.wantsLayer = true
        clip.layer?.backgroundColor = NSColor.black.cgColor
        clip.layer?.cornerRadius = 10
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        canvas.wantsLayer = true
        clip.addSubview(canvas)
        addSubview(clip)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Starts the theme, or starts it again for a new generation. Quick changes in a row (a slider
    /// dragged) start it once, after they stop.
    func show(theme: String, generation: Int) {
        guard shown?.theme != theme || shown?.generation != generation else { return }
        let first = shown == nil || shown?.theme != theme
        shown = (theme, generation)
        restart(after: first ? 0 : 0.25)
    }

    func stop() {
        pending?.cancel()
        session?.end("preview closed")
        session = nil
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
    }

    private var visible: Bool { alwaysLive || (window?.occlusionState.contains(.visible) ?? false) }

    private func restart(after delay: Double) {
        pending?.cancel()
        pending = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            session?.end("preview changed")
            session = nil
            // A hidden preview starts when its window shows.
            guard let shown, visible else { return }
            layoutSubtreeIfNeeded()
            let session = LockSession(mode: .embedded, options: LockSession.Options(theme: shown.theme, previewSize: Self.layoutSize, container: canvas))
            self.session = session
            session.begin()
        }
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

    private func visibilityChanged() {
        if visible, session == nil, shown != nil {
            restart(after: 0)
        } else if !visible, session != nil {
            pending?.cancel()
            session?.end("window hidden")
            session = nil
        }
    }

    override func layout() {
        super.layout()
        let size = Self.layoutSize
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        guard scale.isFinite, scale > 0 else { return }
        let fitted = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        clip.frame = CGRect(x: ((bounds.width - fitted.width) / 2).rounded(), y: ((bounds.height - fitted.height) / 2).rounded(),
                            width: fitted.width, height: fitted.height)
        canvas.frame = clip.bounds
        canvas.setBoundsSize(size)
        // The lock screen fills the canvas at the layout size, whatever size the canvas had when it was made.
        for screen in canvas.subviews { screen.frame = canvas.bounds }
    }
}
