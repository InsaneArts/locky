import AppKit
import SwiftUI

/// A theme's lock screen, live: laid out at 1440×900 like a real screen and scaled down to fit. Until the live screen
/// is ready, the theme's thumbnail (or its background color) stands in for it. A change to the theme itself (the
/// editor's) shows in place. Another theme shows its own thumbnail at once; any other change builds the new screen
/// out of sight and fades it in over the old one, so the preview never goes blank. It stops while its window is
/// hidden, so a forgotten window costs nothing.
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
    /// The theme editor's canvas: widgets to select and drag, and the grid. nil for a plain preview.
    var canvas: Canvas?
    /// The theme's info, for the placeholder shown until the live screen is ready.
    var info: Inspection.ThemeInfo? = nil

    /// What the theme editor's canvas shows, and what it reports.
    struct Canvas {
        var selection: EditorItem?
        var grid = false
        /// The name on a selected item.
        var name: (EditorItem) -> String
        var select: (EditorItem?) -> Void
        /// A drag ended: the item's new anchor and offset, in layout points.
        var move: (EditorItem, Anchor, CGPoint) -> Void
        /// An arrow key: the selected item moves a step across and down (-1, 0, or 1 each), by the grid with Shift.
        var nudge: (EditorItem, (x: Int, y: Int), Bool) -> Void
        /// Delete: the selected widget goes.
        var remove: (Int) -> Void
        /// Escape with nothing selected: Customize ends.
        var exit: () -> Void
    }

    func makeNSView(context: Context) -> ThemePreviewView { ThemePreviewView() }

    func updateNSView(_ view: ThemePreviewView, context: Context) {
        view.alwaysLive = alwaysLive
        view.config = config
        view.canvas = canvas
        view.info = info
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
    var canvas: ThemePreview.Canvas? {
        didSet {
            overlay.isHidden = canvas == nil
            overlay.needsDisplay = true
            // When the canvas shows, and when another item is selected (an inspector row selects too), the keys go to it.
            if canvas != nil, oldValue == nil || oldValue?.selection != canvas?.selection { overlay.takeKeyboardIfFree() }
        }
    }
    /// The shown theme's info, for the placeholder.
    var info: Inspection.ThemeInfo?
    /// The theme whose placeholder the stage shows; nil for black.
    private var placeholder: Inspection.ThemeInfo?
    /// Rounds the corners, in screen points. Its own layer shows the placeholder, under the screens.
    private let clip = NSView()
    /// Holds each session's screen at the layout size; its frame is the scaled-down size.
    private let stage = NSView()
    private let overlay = CanvasOverlay()

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
        clip.layer?.contentsGravity = .resizeAspectFill
        stage.wantsLayer = true
        clip.addSubview(stage)
        addSubview(clip)
        overlay.preview = self
        overlay.isHidden = true
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ key: Key) {
        wanted = key
        showPlaceholder(for: key.theme)
        advance()
    }

    /// What the stage shows under the screens, so it is never black while a theme's screen loads: the theme's
    /// thumbnail, else its background color, else black.
    private func showPlaceholder(for theme: String) {
        let info = info?.id == theme ? info : nil
        guard info != placeholder else { return }
        placeholder = info
        clip.layer?.contents = info.flatMap(ThemeThumbnails.image(for:))
        clip.layer?.backgroundColor = (info.flatMap { NSColor(hex: $0.palette["bg"] ?? "") } ?? .black).cgColor
    }

    func stop() {
        wanted = nil
        endSessions()
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
    }

    /// The current screen's items the editor can select, with their frames in layout points: none while the screen
    /// shows another theme (one the editor left, waiting for its replacement to load, or the one Locky fell back to),
    /// or the theme without the window's changes.
    var editables: [(item: EditorItem, frame: CGRect)] {
        guard let current, let wanted, !current.key.needsRestart(for: wanted), current.session.shows(theme: wanted.theme) else { return [] }
        return current.session.editables
    }

    /// Puts an item at another place in the current screen while it is dragged.
    func place(_ item: EditorItem, anchor: Anchor, offset: CGPoint) {
        current?.session.place(item, anchor: anchor, offset: offset)
    }

    private var visible: Bool { alwaysLive || (window?.occlusionState.contains(.visible) ?? false) }

    /// Moves toward the wanted key: starts a session, reloads the current one in place, or replaces it.
    private func advance() {
        guard let wanted, visible else { return }
        // Another theme ends this one's screen at once: the new theme's placeholder shows until its own screen is
        // ready, so a name never sits over another theme's picture.
        if let current, current.key.theme != wanted.theme {
            current.session.end("replaced")
            current.container.removeFromSuperview()
            self.current = nil
            overlay.needsDisplay = true
        }
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
            if self.current?.session === session {
                if shown { self.current?.key = wanted } else { begin(wanted) }
            }
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
        session.onLayout = { [weak self, weak session] in
            if let self, let session, current?.session === session { overlay.needsDisplay = true }
        }
        incoming = Shown(session: session, container: container, key: key)
        session.begin()
    }

    /// Fades a ready session in over the current one, or over the placeholder, and the old one ends once it is
    /// covered. Opacity only, so it stays with Reduce Motion.
    private func promote(_ session: LockSession) {
        guard let incoming, incoming.session === session else { return }
        let old = current
        current = incoming
        self.incoming = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = Motion.easeOut
            incoming.container.animator().alphaValue = 1
        }, completionHandler: {
            MainActor.assumeIsolated {
                old?.session.end("replaced")
                old?.container.removeFromSuperview()
            }
        })
        overlay.needsDisplay = true
        advance()
    }

    private func endSessions() {
        for shown in [current, incoming].compactMap({ $0 }) {
            shown.session.end("preview closed")
            shown.container.removeFromSuperview()
        }
        current = nil
        incoming = nil
        overlay.needsDisplay = true
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

    /// While it is a canvas, VoiceOver finds the canvas's buttons here, not the live screen under them, whose password
    /// field takes nothing.
    override func accessibilityChildren() -> [Any]? {
        canvas == nil ? super.accessibilityChildren() : [overlay]
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
        // Each screen fills the stage at the layout size, whatever size the stage had when the screen was made. The size
        // itself, not the stage's bounds: AppKit works those out from the scaled frame, a hair off (900.0000000000001),
        // and a centered widget's frame then rounds out a point too tall.
        for container in stage.subviews {
            container.frame = CGRect(origin: .zero, size: size)
            for screen in container.subviews { screen.frame = container.bounds }
        }
        overlay.frame = clip.frame
    }
}

/// The theme editor's layer over the preview: the grid, and outlines. While the pointer is over the canvas, every
/// item it can select has a faint outline and the one under the pointer a stronger one; the selected item has the
/// accent color. A click selects an item, and a drag moves it (onto the grid while the grid shows); a click elsewhere
/// clears the selection.
@MainActor
final class CanvasOverlay: NSView {
    weak var preview: ThemePreviewView?
    private var pointerInside = false
    private var hovered: EditorItem?
    /// Hover follows the pointer only in the key window: another window's turn clears it.
    private var resignKey: NSObjectProtocol?
    /// VoiceOver's button for each item. AppKit leaves elements to the view that makes them, so they stay the same
    /// objects while the items stay the same.
    private var elements: [CanvasItemElement] = []
    private struct Drag {
        var item: EditorItem
        var start: CGPoint
        var frame: CGRect
        var placed: (anchor: Anchor, offset: CGPoint)?
    }
    private var drag: Drag?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// A click on the canvas ends typing in the panel, which saves it to the widget it was for.
    override var acceptsFirstResponder: Bool { true }

    private var canvas: ThemePreview.Canvas? { preview?.canvas }
    /// View points per layout point.
    private var scale: CGFloat { bounds.width / ThemePreviewView.layoutSize.width }

    private func layoutPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x / scale, y: point.y / scale)
    }

    /// The item under a point; of several, the smallest, so a widget inside the password field's ring can be picked.
    private func item(at point: CGPoint) -> (item: EditorItem, frame: CGRect)? {
        (preview?.editables ?? []).filter { $0.frame.insetBy(dx: -4, dy: -4).contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignKey { NotificationCenter.default.removeObserver(resignKey) }
        resignKey = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerLeft() }
            }
        }
    }

    /// A hidden canvas hears no pointer: it starts without hover when it shows again.
    override func viewDidHide() {
        super.viewDidHide()
        pointerLeft()
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let found = item(at: layoutPoint(event))?.item
        if found != hovered || !pointerInside {
            pointerInside = true
            hovered = found
            needsDisplay = true
        }
        (found == nil ? NSCursor.arrow : NSCursor.openHand).set()
    }

    override func mouseExited(with event: NSEvent) {
        pointerLeft()
        NSCursor.arrow.set()
    }

    private func pointerLeft() {
        pointerInside = false
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let canvas else { return }
        window?.makeFirstResponder(self)
        let point = layoutPoint(event)
        guard let hit = item(at: point) else {
            canvas.select(nil)
            return
        }
        if canvas.selection != hit.item { canvas.select(hit.item) }
        drag = Drag(item: hit.item, start: point, frame: hit.frame)
        needsDisplay = true
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag, let canvas else { return }
        let point = layoutPoint(event)
        let delta = CGPoint(x: point.x - drag.start.x, y: point.y - drag.start.y)
        // A click that wobbles a little is not a drag.
        guard drag.placed != nil || hypot(delta.x, delta.y) * scale > 3 else { return }
        let placed = Placing.place(drag.frame.offsetBy(dx: delta.x, dy: delta.y), in: CGRect(origin: .zero, size: ThemePreviewView.layoutSize),
                                   snap: canvas.grid)
        preview?.place(drag.item, anchor: placed.anchor, offset: placed.offset)
        drag.placed = placed
        self.drag = drag
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            drag = nil
            (item(at: layoutPoint(event)) == nil ? NSCursor.arrow : NSCursor.openHand).set()
            needsDisplay = true
        }
        guard let drag, let placed = drag.placed else { return }
        canvas?.move(drag.item, placed.anchor, placed.offset)
    }

    /// Gives the canvas the keyboard while no control has it, so Escape, the arrows, and Delete work without a click
    /// first. The window itself, or a view around the canvas (the page, after the gallery's grid had the keys), holds it
    /// for nobody; a text field keeps it. On the next turn of the run loop, once the views that this change adds or
    /// removes are in place.
    func takeKeyboardIfFree() {
        DispatchQueue.main.async { [weak self] in
            guard let self, canvas != nil, !isHiddenOrHasHiddenAncestor, let window else { return }
            let responder = window.firstResponder
            if responder == nil || responder === window || (responder as? NSView).map({ isDescendant(of: $0) }) == true {
                window.makeFirstResponder(self)
            }
        }
    }

    /// Edit ▸ Delete: the selected widget goes.
    @objc func delete(_ sender: Any?) {
        if case .widget(let index)? = canvas?.selection { canvas?.remove(index) }
    }

    /// With the canvas focused: the arrow keys move what is selected, Delete removes a selected widget, and Escape
    /// clears the selection, or with nothing selected ends Customize.
    override func keyDown(with event: NSEvent) {
        // A drag ends only where the mouse goes up: Escape during one does nothing.
        if drag != nil, event.charactersIgnoringModifiers == "\u{1b}" { return }
        guard let canvas, drag == nil else { return super.keyDown(with: event) }
        let byGrid = event.modifierFlags.contains(.shift)
        switch (event.specialKey, canvas.selection) {
        case (.leftArrow?, let item?): canvas.nudge(item, (-1, 0), byGrid)
        case (.rightArrow?, let item?): canvas.nudge(item, (1, 0), byGrid)
        case (.upArrow?, let item?): canvas.nudge(item, (0, -1), byGrid)
        case (.downArrow?, let item?): canvas.nudge(item, (0, 1), byGrid)
        case (.delete?, .widget(let index)?), (.deleteForward?, .widget(let index)?): canvas.remove(index)
        case (_, _?) where event.charactersIgnoringModifiers == "\u{1b}": canvas.select(nil)
        case (_, nil) where event.charactersIgnoringModifiers == "\u{1b}": canvas.exit()
        default: super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let canvas else { return }
        if canvas.grid { drawGrid() }
        let items = preview?.editables ?? []
        // The item being dragged shows as selected from the first frame, before the selection reaches the page.
        let selected = drag?.item ?? canvas.selection
        if pointerInside {
            let strong = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            for (item, frame) in items where item != selected && item != hovered {
                outline(frame, dark: (2, strong ? 0.35 : 0.15), light: (1, .white.withAlphaComponent(strong ? 0.6 : 0.25)))
            }
        }
        if let hovered, hovered != selected, let frame = items.first(where: { $0.item == hovered })?.frame {
            outline(frame, dark: (3, 0.25), light: (1, .white.withAlphaComponent(0.9)))
        }
        if let selected, let frame = items.first(where: { $0.item == selected })?.frame {
            outline(frame, dark: (4, 0.25), light: (2, .controlAccentColor))
        }
    }

    private func drawGrid() {
        let lines = NSBezierPath()
        let size = ThemePreviewView.layoutSize
        for x in stride(from: Placing.grid, to: size.width, by: Placing.grid) {
            lines.move(to: CGPoint(x: x * scale, y: 0))
            lines.line(to: CGPoint(x: x * scale, y: bounds.height))
        }
        for y in stride(from: Placing.grid, to: size.height, by: Placing.grid) {
            lines.move(to: CGPoint(x: 0, y: y * scale))
            lines.line(to: CGPoint(x: bounds.width, y: y * scale))
        }
        lines.lineWidth = 1 / (window?.backingScaleFactor ?? 2)
        // The center lines are a point wide, in the same colors.
        let center = NSBezierPath()
        center.move(to: CGPoint(x: bounds.midX, y: 0))
        center.line(to: CGPoint(x: bounds.midX, y: bounds.height))
        center.move(to: CGPoint(x: 0, y: bounds.midY))
        center.line(to: CGPoint(x: bounds.width, y: bounds.midY))
        center.lineWidth = 1
        // Dark and light at once, so the lines show on any background.
        for path in [lines, center] {
            NSColor.black.withAlphaComponent(0.22).setStroke()
            path.stroke()
            NSColor.white.withAlphaComponent(0.22).setStroke()
            path.stroke()
        }
    }

    private func viewRect(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale).insetBy(dx: -3, dy: -3)
    }

    // MARK: VoiceOver

    // The canvas is a group named "Lock Screen" with a button per item, named as the inspector names it.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Lock Screen" }

    override func accessibilityChildren() -> [Any]? {
        let items = canvas == nil ? [] : preview?.editables ?? []
        if elements.map(\.item) != items.map(\.item) {
            elements = items.map { CanvasItemElement(item: $0.item, parent: self) }
        }
        for (element, editable) in zip(elements, items) {
            element.setAccessibilityLabel(canvas?.name(editable.item))
            // The parent's space starts at its bottom left, as the screen does, and this view is flipped.
            let rect = viewRect(editable.frame)
            element.setAccessibilityFrameInParentSpace(CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height))
        }
        // As people read the screen: top to bottom, then left to right.
        return zip(elements, items).sorted { ($0.1.frame.minY, $0.1.frame.minX) < ($1.1.frame.minY, $1.1.frame.minX) }.map(\.0)
    }

    /// VoiceOver pressed an item's button.
    fileprivate func press(_ item: EditorItem) {
        canvas?.select(item)
    }

    /// Whether VoiceOver's button for `item` is the selected one.
    fileprivate func isSelected(_ item: EditorItem) -> Bool {
        canvas?.selection == item
    }

    /// A rounded line 3 points around an item: a wide dark stroke under a narrow light one, so one of the two reads on
    /// any background.
    private func outline(_ frame: CGRect, dark: (width: CGFloat, alpha: CGFloat), light: (width: CGFloat, color: NSColor)) {
        let path = NSBezierPath(roundedRect: viewRect(frame), xRadius: 4, yRadius: 4)
        path.lineWidth = dark.width
        NSColor.black.withAlphaComponent(dark.alpha).setStroke()
        path.stroke()
        path.lineWidth = light.width
        light.color.setStroke()
        path.stroke()
    }
}

extension CanvasOverlay: NSMenuItemValidation {
    /// Edit ▸ Delete works while a widget is selected; the password field stays.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(delete(_:)) else { return true }
        if case .widget? = canvas?.selection { return true }
        return false
    }
}

/// One item on the canvas, for VoiceOver: a button that selects it.
final class CanvasItemElement: NSAccessibilityElement {
    let item: EditorItem

    init(item: EditorItem, parent: CanvasOverlay) {
        self.item = item
        super.init()
        setAccessibilityParent(parent)
        setAccessibilityRole(.button)
        // An element starts disabled, and VoiceOver reads a disabled button as dimmed.
        setAccessibilityEnabled(true)
    }

    /// The selected item's button reads as selected, as the current Pinned To cell does. AppKit asks on the main thread.
    override func isAccessibilitySelected() -> Bool {
        guard let overlay = accessibilityParent() as? CanvasOverlay else { return false }
        let item = item
        return MainActor.assumeIsolated { overlay.isSelected(item) }
    }

    /// AppKit asks on the main thread.
    override func accessibilityPerformPress() -> Bool {
        guard let overlay = accessibilityParent() as? CanvasOverlay else { return false }
        let item = item
        MainActor.assumeIsolated { overlay.press(item) }
        return true
    }
}
