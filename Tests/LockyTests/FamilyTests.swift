import Foundation
import Testing
@testable import Locky

/// Apple's widget families: a placement's family sets its size and card, and the widget reads it.
@Suite struct FamilyTests {
    @Test func aFamilySetsTheSizeTheCardAndWhatTheWidgetDraws() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/f.lua", """
            locky.widget.define('f', { families = { 'circular', 'small' }, render = function(self)
              return locky.ui.text(self.family or 'none')
            end })
            """)
        try sandbox.write("themes/t.lua", """
            return { widgets = { { 'f', family = 'circular' }, { 'f', family = 'small' }, { 'f', family = 'rectangular', card = 'solid' },
                                 { 'f', family = 'inline' }, { 'f' } } }
            """)
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: recorder.delegate)
        let started = await runtime.start(theme: "t")
        defer { runtime.stop() }
        #expect(started.problems.isEmpty, "\(started.problems)")
        let placements = started.theme.widgets
        #expect(placements.map(\.family) == ["circular", "small", "rectangular", "inline", nil])
        #expect(placements.map(\.size) == [CGSize(width: 76, height: 76), CGSize(width: 170, height: 170),
                                          CGSize(width: 172, height: 76), nil, nil])
        // The circle and the desktop sizes sit on the theme's card; Lock Screen text on the bare screen.
        #expect(placements.map(\.card) == ["glass", "glass", "solid", nil, nil])
        let ids = started.instances.compactMap { $0 }
        #expect(await eventually { ids.allSatisfy { recorder.views[$0] != nil } })
        #expect(ids.map { recorder.views[$0]??.kind } == [.text("circular"), .text("small"), .text("rectangular"), .text("inline"), .text("none")])
    }

    @Test func anUnknownFamilyIsAProblem() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { widgets = { { 'clock', family = 'huge' } } }")
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        let started = await runtime.start(theme: "t")
        defer { runtime.stop() }
        #expect(started.problems.contains { $0.contains("expected a family") }, "\(started.problems)")
    }

    @Test func gaugesParseFromLua() throws {
        let runtime = LuaRuntime(path: try Sandbox().path(), delegate: Recorder().delegate)
        _ = runtime.bootForTest()
        defer { runtime.stop() }
        let value = try #require(try runtime.eval("""
            return locky.ui.gauge(18, { min = 10, max = 25, value_label = '18°', min_label = '10', max_label = '25',
                                        icon = 'sun.max', label = 'UV', color = { '#00aaff', '#ffcc00' } })
            """).first)
        let node = try Node(lua: value)
        #expect(node.kind == .gauge(18) && node.minValue == 10 && node.maxValue == 25)
        #expect(node.valueLabel == "18°" && node.minLabel == "10" && node.maxLabel == "25" && node.icon == "sun.max" && node.label == "UV")
        #expect(node.color == .gradient(["#00aaff", "#ffcc00"], angle: 90))
        // A label on another view is that view's business, not a gauge's.
        let text = try Node(lua: try #require(try runtime.eval("return locky.ui.text('x', { label = false })").first))
        #expect(text.kind == .text("x") && text.label == nil)
    }
}
