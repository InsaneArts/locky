import Foundation

/// What the theme editor selects: a widget, by its place in the theme's list, or the password field.
enum EditorItem: Hashable, Sendable {
    case widget(Int)
    case passwordField
}

/// Where a dragged widget lands: pinned to the anchor of the part of the screen it is in, so it keeps its place
/// on screens of other sizes, and at its offset from that anchor.
enum Placing {
    /// The grid's spacing, in layout points. It divides 1440 × 900 and its center, so the screen's edges and center
    /// lie on grid lines.
    static let grid: CGFloat = 30

    /// The anchor for a widget whose frame is `frame`: the third of the screen its center is in, across and down.
    static func anchor(for frame: CGRect, in bounds: CGRect) -> Anchor {
        let column = min(max(Int(((frame.midX - bounds.minX) / (bounds.width / 3)).rounded(.down)), 0), 2)
        let row = min(max(Int(((frame.midY - bounds.minY) / (bounds.height / 3)).rounded(.down)), 0), 2)
        let anchors: [[Anchor]] = [[.topLeft, .top, .topRight], [.left, .center, .right], [.bottomLeft, .bottom, .bottomRight]]
        return anchors[row][column]
    }

    /// The offset that puts a box of `frame.size` at `frame.origin`, from `anchor`.
    static func offset(of frame: CGRect, from anchor: Anchor, in bounds: CGRect) -> CGPoint {
        let origin = anchor.frame(size: frame.size, offset: .zero, in: bounds).origin
        return CGPoint(x: frame.minX - origin.x, y: frame.minY - origin.y)
    }

    /// The anchor and the offset, in whole points, for a widget dropped with its frame at `frame`. With `snap`, the
    /// widget's anchored corner, edge, or center lands on the grid.
    static func place(_ frame: CGRect, in bounds: CGRect, snap: Bool) -> (anchor: Anchor, offset: CGPoint) {
        let anchor = anchor(for: frame, in: bounds)
        let offset = offset(of: frame, from: anchor, in: bounds)
        let step = snap ? grid : 1
        return (anchor, CGPoint(x: (offset.x / step).rounded() * step, y: (offset.y / step).rounded() * step))
    }
}
