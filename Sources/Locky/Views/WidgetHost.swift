import AppKit
import SwiftUI

/// What one widget shows now.
@MainActor @Observable
final class WidgetModel {
    var node: Node?
    var error: String?
    var disabled = false
    /// The content's natural size, in points; the screen view lays widgets out with it.
    var contentSize: CGSize = .zero
}

/// One widget on one screen. Widgets never take the mouse or the keyboard: the password field keeps both.
@MainActor
final class WidgetHost: NSView {
    private(set) var placement: Theme.Placement
    let model = WidgetModel()
    var onResize: (() -> Void)?
    private let showsErrors: Bool
    private var hosting: NSHostingView<WidgetView>!

    init(placement: Theme.Placement, theme: Theme, style: LockyStyle, showsErrors: Bool) {
        self.placement = placement
        self.showsErrors = showsErrors
        super.init(frame: .zero)
        hosting = NSHostingView(rootView: view(theme: theme, style: style))
        hosting.sizingOptions = []
        addSubview(hosting)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func view(theme: Theme, style: LockyStyle) -> WidgetView {
        let card = placement.card.map { Theme.Card(style: $0, radius: theme.card.radius, fill: theme.card.fill, border: theme.card.border) }
        return WidgetView(model: model, placement: placement, card: card, showsErrors: showsErrors, style: style) { [weak self] size in
            guard let self, size != model.contentSize else { return }
            model.contentSize = size
            onResize?()
        }
    }

    /// A new place, card, or size for the widget, keeping what it shows: the theme editor's changes.
    func update(placement new: Theme.Placement, theme: Theme, style: LockyStyle) {
        guard new != placement else { return }
        let restyle = new.card != placement.card || new.size != placement.size || new.align != placement.align || new.anchor != placement.anchor
            || new.family != placement.family
        placement = new
        if restyle { hosting.rootView = view(theme: theme, style: style) }
        onResize?()
    }

    /// Another place for the widget while the theme editor drags it.
    func move(anchor: Anchor, offset: CGPoint) {
        placement.anchor = anchor
        placement.offset = offset
        onResize?()
    }

    /// Whether the widget is ready to show: drawn and measured, or with nothing to draw.
    var isSettled: Bool {
        (model.node == nil && model.error == nil) || placement.size != nil || model.contentSize.width > 0
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        hosting.frame = bounds
    }

    func present(_ node: Node?) {
        model.node = node
        model.error = nil
    }

    func fail(_ message: String, disabled: Bool) {
        model.error = message
        model.disabled = disabled
    }

    /// The frame for this widget on a screen of `bounds`, at `scale`. A widget without a size takes its
    /// content's; until that is measured, the frame is the whole screen so the content can measure itself.
    func frame(in bounds: CGRect, scale: CGFloat) -> CGRect {
        let size = placement.size.map { CGSize(width: $0.width * scale, height: $0.height * scale) } ?? model.contentSize
        guard size.width > 0, size.height > 0 else { return bounds }
        let offset = CGPoint(x: placement.offset.x * scale, y: placement.offset.y * scale)
        let frame = placement.anchor.frame(size: size, offset: offset, in: bounds)
        // A view that measured infinite (a plugin bug) is hidden instead of crashing AppKit.
        guard frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite,
              frame.width < 1_000_000, frame.height < 1_000_000 else { return .zero }
        return frame.integral
    }
}

private struct WidgetView: View {
    let model: WidgetModel
    let placement: Theme.Placement
    let card: Theme.Card?
    let showsErrors: Bool
    let style: LockyStyle
    let onSize: (CGSize) -> Void

    var body: some View {
        Group {
            if let size = placement.size {
                chrome.frame(width: size.width * style.scale, height: size.height * style.scale, alignment: alignment)
            } else {
                chrome.fixedSize()
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
        .environment(\.lockyStyle, style)
        .foregroundStyle(style.color("fg"))
    }

    @ViewBuilder private var content: some View {
        if let error = model.error {
            if showsErrors {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium).monospaced())
                    .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.4))
                    .lineLimit(6)
                    .frame(maxWidth: 420, alignment: .leading)
                    .padding(10)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            } else {
                // On a real lock screen a failed widget shows a faint sign instead of an error message.
                Image(systemName: "exclamationmark.triangle").font(.system(size: 13)).opacity(0.35)
            }
        } else if let node = model.node {
            NodeView(node: node)
        }
    }

    @ViewBuilder private var chrome: some View {
        if let card, card.style != "none", model.error == nil, model.node != nil {
            // A circular widget sits on a disc, as on the Lock Screen; the others on a rounded card.
            let shape = placement.family == "circular" ? AnyShape(Circle())
                : AnyShape(RoundedRectangle(cornerRadius: card.radius * style.scale, style: .continuous))
            // With a size, the card fills it and `align` places the content inside, so a dashboard's panels line up.
            // Apple's margins: 16 points; a Lock Screen family's content runs to its edges.
            let lockScreen = ["circular", "rectangular", "inline"].contains(placement.family ?? "")
            let padded = content.padding(lockScreen ? 0 : 16 * style.scale)
                .frame(maxWidth: placement.size == nil ? nil : .infinity, maxHeight: placement.size == nil ? nil : .infinity, alignment: alignment)
            switch card.style {
            case "solid":
                padded.background(style.color(card.fill ?? "surface"), in: shape)
                    .overlay(shape.stroke(style.color(card.border ?? "border"), lineWidth: 1).padding(0.5))
            case "outline":
                padded.overlay(shape.stroke(style.color(card.border ?? "border"), lineWidth: 1.5 * style.scale).padding(0.75 * style.scale))
            default:
                if #available(macOS 26.0, *) {
                    padded.glassEffect(.clear.tint(card.fill.map(style.color) ?? .black.opacity(0.18)), in: shape)
                } else {
                    padded.background(.ultraThinMaterial, in: shape)
                }
            }
        } else {
            content
        }
    }

    private var alignment: Alignment {
        switch placement.align {
        case "leading", "left": .leading
        case "trailing", "right": .trailing
        case "top": .top
        case "bottom": .bottom
        case "top-leading", "top-left": .topLeading
        case "top-trailing", "top-right": .topTrailing
        case "bottom-leading", "bottom-left": .bottomLeading
        case "bottom-trailing", "bottom-right": .bottomTrailing
        default: .center
        }
    }

    /// Where the content sits while the widget's frame is still the whole screen.
    private var frameAlignment: Alignment {
        switch placement.anchor {
        case .topLeft: .topLeading
        case .top: .top
        case .topRight: .topTrailing
        case .left: .leading
        case .right: .trailing
        case .bottomLeft: .bottomLeading
        case .bottom: .bottom
        case .bottomRight: .bottomTrailing
        case .center: .center
        }
    }
}
