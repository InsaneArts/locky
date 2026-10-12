import AppKit
import SwiftUI
import Testing
@testable import Locky

/// Renders views offscreen and checks where things land.
@MainActor
@Suite struct LayoutRenderTests {
    /// The x of the first column, from the left, where the rendered image has a strongly blue pixel.
    private func blueColumn(_ node: Node, width: CGFloat = 400, height: CGFloat = 40) -> Int? {
        let view = NodeView(node: node).environment(\.lockyStyle, LockyStyle(palette: [:], scale: 1)).frame(width: width, height: height, alignment: .leading)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage, let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let perRow = image.bytesPerRow, perPixel = image.bitsPerPixel / 8
        let y = image.height / 2
        for x in 0..<image.width {
            let p = bytes + y * perRow + x * perPixel
            // Pixel order may be RGBA or BGRA; blue is the one channel near 255 with the other two low.
            let c = (p[0], p[1], p[2])
            if (c.0 < 60 && c.1 < 60 && c.2 > 200) || (c.0 > 200 && c.1 < 60 && c.2 < 60 && image.bitmapInfo.contains(.byteOrder32Little)) { return x }
        }
        return nil
    }

    private func square(_ color: String) -> LuaValue {
        .table(["shape": .string("rect"), "width": .int(10), "height": .int(10), "color": .string(color)])
    }

    /// A spacer wrapped in .equatable() stops pushing (found while building themes).
    @Test func aSpacerPushesSiblingsApartInAFixedWidthStack() throws {
        let row = try Node(lua: .table([
            "hstack": .array([square("#ff0000"), .table(["spacer": .bool(true)]), square("#0000ff")]),
            "width": .int(300),
        ]))
        let x = try #require(blueColumn(row))
        #expect(x >= 285, "the blue square should sit at the right end of the 300-point row, found x = \(x)")
    }

    @Test func aFlexibleBarFillsItsRow() throws {
        // A progress bar between two squares takes the rest of the row, so the blue square ends up at the right.
        let row = try Node(lua: .table([
            "hstack": .array([square("#ff0000"), .table(["progress": .double(0.5), "color": .string("#00ff00")]), square("#0000ff")]),
            "width": .int(300),
        ]))
        let x = try #require(blueColumn(row))
        #expect(x >= 285, "found x = \(x)")
    }

    @Test func childrenInheritTheirStacksColor() throws {
        // Text with no color of its own, inside a blue stack, draws blue (it used to reset to system white).
        let stack = try Node(lua: .table(["vstack": .array([.table(["text": .string("██████"), "size": .int(30)])]), "color": .string("#0000ff")]))
        #expect(blueColumn(stack) != nil)
    }
}
