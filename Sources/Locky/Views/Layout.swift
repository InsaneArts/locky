import Foundation

enum Anchor: String, Sendable {
    case top, topLeft = "top-left", topRight = "top-right", left, center, right
    case bottom, bottomLeft = "bottom-left", bottomRight = "bottom-right"

    /// The frame of a `size` box placed at this anchor of `bounds`, moved by `offset` (y grows downwards).
    func frame(size: CGSize, offset: CGPoint, in bounds: CGRect) -> CGRect {
        let x: CGFloat = switch self {
        case .topLeft, .left, .bottomLeft: 0
        case .topRight, .right, .bottomRight: bounds.width - size.width
        case .top, .center, .bottom: (bounds.width - size.width) / 2
        }
        let y: CGFloat = switch self {
        case .top, .topLeft, .topRight: 0
        case .bottom, .bottomLeft, .bottomRight: bounds.height - size.height
        case .left, .center, .right: (bounds.height - size.height) / 2
        }
        return CGRect(x: bounds.minX + x + offset.x, y: bounds.minY + y + offset.y, width: size.width, height: size.height)
    }
}

enum Layout {
    /// Themes are designed for 1440×900 points. Bigger screens scale everything up, smaller ones down a little.
    static func scale(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(max(min(size.width / 1440, size.height / 900), 0.8), 2)
    }

    /// `frame` moved inside `bounds` inset by `margin` on every side. A frame bigger than that keeps its top-left
    /// corner on the inset edge.
    static func keep(_ frame: CGRect, inside bounds: CGRect, margin: CGFloat) -> CGRect {
        let (left, top) = (bounds.minX + margin, bounds.minY + margin)
        let x = min(max(frame.minX, left), max(left, bounds.maxX - margin - frame.width))
        let y = min(max(frame.minY, top), max(top, bounds.maxY - margin - frame.height))
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }
}
