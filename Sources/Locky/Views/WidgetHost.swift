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
    let placement: Theme.Placement
    let model = WidgetModel()
    var onResize: (() -> Void)?
    private var hosting: NSHostingView<WidgetView>!

    init(placement: Theme.Placement, theme: Theme, style: LockyStyle, showsErrors: Bool) {
        self.placement = placement
        super.init(frame: .zero)
        let card = placement.card.map { Theme.Card(style: $0, radius: theme.card.radius, fill: theme.card.fill, border: theme.card.border) }
        let view = WidgetView(model: model, placement: placement, card: card, showsErrors: showsErrors, style: style) { [weak self] size in
            guard let self, size != model.contentSize else { return }
            model.contentSize = size
            onResize?()
        }
        hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        addSubview(hosting)
    }

    required init?(coder: NSCoder) { fatalError() }

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
            let shape = RoundedRectangle(cornerRadius: card.radius * style.scale, style: .continuous)
            let padded = content.padding(16 * style.scale)
            switch card.style {
            case "solid":
                padded.background(style.color(card.fill ?? "surface"), in: shape)
                    .overlay(shape.strokeBorder(style.color(card.border ?? "border"), lineWidth: 1))
            case "outline":
                padded.overlay(shape.strokeBorder(style.color(card.border ?? "border"), lineWidth: 1.5 * style.scale))
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
