import Foundation
import SwiftUI
import Testing
@testable import Locky

@Suite struct NodeTests {
    @Test func viewsParseFromLua() throws {
        let sandbox = try Sandbox()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        _ = runtime.bootForTest()
        let view = try #require(try runtime.eval("""
            local ui = locky.ui
            local skip = false
            return ui.vstack {
              spacing = 8, align = "leading", padding = { 4, 8 },
              ui.text("Hi", { size = 20, weight = "bold", color = "accent", case = "upper" }),
              skip and ui.text("never"),
              ui.each({ 1, 2 }, function(n) return ui.dot({ size = n }) end),
              ui.time("HH:mm", { mono = true }),
              ui.progress(0.5, { color = { "#ff0000", "#0000ff", angle = 0 } }),
              ui.rect({ width = 10, height = 2, radius = 1, color = "fg", rotation = 45 }),
              ui.spacer(),
            }
            """).first)
        let node = try Node(lua: view)
        guard case .vstack(let children) = node.kind else { Issue.record("expected a vstack"); return }
        #expect(node.spacing == 8 && node.align == "leading" && node.padding == [4, 8])
        #expect(children.map(\.kind) == [.text("Hi"), .dot, .dot, .time("HH:mm"), .progress(0.5), .shape("rect"), .spacer])
        #expect(children[0].color == .color("accent") && children[0].textCase == "upper" && children[0].size == 20)
        #expect(children[4].color == .gradient(["#ff0000", "#0000ff"], angle: 0))
        #expect(children[5].rotation == 45)
    }

    @Test func badViewsExplainThemselves() throws {
        #expect {
            try Node(lua: .table(["nonsense": .bool(true)]))
        } throws: { ($0 as? LuaError)?.message.contains("not a view") == true }
        #expect {
            try Node(lua: .table(["vstack": .array([.table(["text": .string("a"), "size": .string("big")])])]))
        } throws: { ($0 as? LuaError)?.message.contains("vstack[1]: 'size' must be a number") == true }
    }

    @Test func colorsResolveThroughThePalette() {
        let style = LockyStyle(palette: ["accent": "#ff0000"], scale: 2)
        #expect(style.color("accent") == Color(hex: "#ff0000"))
        #expect(style.color("#00ff00") == Color(hex: "#00ff00"))
        #expect(style.s(10) == 20)
    }

    @Test func anchorsPlaceBoxes() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let size = CGSize(width: 100, height: 50)
        #expect(Anchor.top.frame(size: size, offset: CGPoint(x: 0, y: 10), in: bounds) == CGRect(x: 450, y: 10, width: 100, height: 50))
        #expect(Anchor.bottomRight.frame(size: size, offset: CGPoint(x: -20, y: -20), in: bounds) == CGRect(x: 880, y: 430, width: 100, height: 50))
        #expect(Anchor.center.frame(size: size, offset: .zero, in: bounds) == CGRect(x: 450, y: 225, width: 100, height: 50))
        #expect(Layout.scale(for: CGSize(width: 1728, height: 1117)) == 1.2)
    }
}

@Suite struct DateFormatTests {
    @Test func patternsAreUsedAsTheyAre() {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 12; components.hour = 9; components.minute = 5
        let date = Calendar.current.date(from: components)!
        #expect(SystemInfo.format(date, "mm") == "05")
        #expect(SystemInfo.format(date, "HH") == "09")
        #expect(SystemInfo.format(date, "HH:mm") == "09:05")
        #expect(!SystemInfo.format(date, "skeleton:MMMMd").isEmpty)
    }

    /// Digits roll unless the format shows seconds. The "s" of "skeleton:" is not a seconds field.
    @Test func onlyASecondsFieldShowsSeconds() {
        #expect(NodeView.showsSeconds("HH:mm:ss"))
        #expect(NodeView.showsSeconds("skeleton:jms"))
        #expect(!NodeView.showsSeconds("HH:mm"))
        #expect(!NodeView.showsSeconds("skeleton:EEEEdMMMM"))
        #expect(!NodeView.showsSeconds("EEEE 'stamp'"))
    }
}
