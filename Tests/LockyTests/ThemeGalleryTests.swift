import Foundation
import SwiftUI
import Testing
@testable import Locky

/// The gallery's pure parts: the grid's columns, and where an arrow key goes.
@MainActor
@Suite struct ThemeGalleryTests {
    // MARK: The grid

    /// The window's content at 980, 1240, and 1600 pt wide, less the page's padding; and a width under one column.
    @Test(arguments: [(932, 4), (1192, 6), (1232, 6), (100, 1)] as [(CGFloat, Int)])
    func theGridFitsColumnsAsTheAdaptiveItemDoes(_ width: CGFloat, _ columns: Int) {
        #expect(ThemeGallery.columns(width: width) == columns)
    }

    /// Three columns of eight themes, and Event Horizon does not load:
    ///
    ///     Aurora   Bauhaus  Deep Blue
    ///     Dots     Event    Fog
    ///     Gruvbox  Haze
    private let themes = ["aurora", "bauhaus", "deepblue", "dots", "event", "fog", "gruvbox", "haze"].map { id in
        Inspection.ThemeInfo(id: id, name: id, error: id == "event" ? "themes/event.lua:3: attempt to index a nil value" : nil)
    }

    private func neighbor(_ id: String, _ direction: MoveCommandDirection, rightToLeft: Bool = false) -> String? {
        ThemeGallery.neighbor(of: id, in: themes, columns: 3, direction: direction, rightToLeft: rightToLeft)
    }

    @Test func leftAndRightStepByOneAndUpAndDownByARow() {
        #expect(neighbor("aurora", .right) == "bauhaus" && neighbor("bauhaus", .left) == "aurora")
        #expect(neighbor("deepblue", .right) == "dots" && neighbor("dots", .left) == "deepblue")
        #expect(neighbor("aurora", .down) == "dots" && neighbor("dots", .up) == "aurora")
        #expect(neighbor("dots", .down) == "gruvbox" && neighbor("fog", .up) == "deepblue")
    }

    @Test func aStepPastEitherEndGoesNowhere() {
        #expect(neighbor("aurora", .left) == nil && neighbor("aurora", .up) == nil)
        #expect(neighbor("haze", .right) == nil && neighbor("haze", .down) == nil)
        // No theme under Fog: the last row is short.
        #expect(neighbor("fog", .down) == nil)
        #expect(neighbor("gone", .right) == nil)
    }

    @Test func aThemeThatDoesNotLoadIsSkipped() {
        #expect(neighbor("dots", .right) == "fog" && neighbor("fog", .left) == "dots")
        #expect(neighbor("bauhaus", .down) == "haze" && neighbor("haze", .up) == "bauhaus")
        // Nothing that loads after it: the step goes nowhere.
        let last = [themes[0], themes[4]]
        #expect(ThemeGallery.neighbor(of: "aurora", in: last, columns: 3, direction: .right, rightToLeft: false) == nil)
    }

    /// A right-to-left grid starts on the right, so the left arrow goes on through the list.
    @Test func leftAndRightSwapForRightToLeft() {
        #expect(neighbor("bauhaus", .left, rightToLeft: true) == "deepblue")
        #expect(neighbor("bauhaus", .right, rightToLeft: true) == "aurora")
        #expect(neighbor("aurora", .down, rightToLeft: true) == "dots")
    }
}
