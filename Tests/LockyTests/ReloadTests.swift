import Foundation
import Testing
@testable import Locky

/// The theme editor's preview shows each change in place: Lua loads the theme again in the same state.
@Suite struct ReloadTests {
    private func sandbox() throws -> Sandbox {
        let sandbox = try Sandbox()
        try sandbox.write("themes/t.lua", "return { widgets = { { 'counter', opts = { label = 'a' } }, { 'counter', opts = { label = 'b' } } } }")
        try sandbox.write("plugin/counter.lua", """
        STARTS = 0
        locky.widget.define("counter", {
          init = function(self) STARTS = STARTS + 1 end,
          render = function(self) return locky.ui.text(self.opts.label or "?") end,
        })
        """)
        return sandbox
    }

    private func edit(_ widgets: [LuaValue]) -> Settings {
        Settings(["themes": .table(["t": .table(["widgets": .array(widgets)])])])
    }

    @Test func aMoveKeepsTheInstanceAndAnOptionStartsANewOne() async throws {
        let sandbox = try sandbox()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        defer { runtime.stop() }
        let started = await runtime.start(theme: "t")
        let reloaded = try #require(await runtime.reload(theme: "t", settings: edit([
            .table(["ref": .int(1), "widget": .string("counter"), "anchor": .string("top"), "offset": .array([.int(0), .int(40)])]),
            .table(["ref": .int(2), "widget": .string("counter"), "opts": .table(["label": .string("c")])]),
            .table(["widget": .string("counter")]),
        ]), previous: started))
        #expect(reloaded.theme.widgets.map(\.anchor) == [.top, .center, .center])
        #expect(reloaded.instances[0] == started.instances[0])
        #expect(reloaded.instances[1] != started.instances[1] && reloaded.instances[1] != nil)
        #expect(reloaded.instances[2] != nil)
        #expect(try runtime.eval("return STARTS") == [.int(4)])
        // The changed widget's old instance is gone.
        let old = try #require(started.instances[1])
        #expect(try runtime.sync { try runtime.call("render", [.int(old)], budget: 1) }.first?.isNil ?? true)
    }

    /// Customize's Size picker sets a family. The instance keeps the family it was made with, and render draws by it, so
    /// a new family needs a new instance, as a new option does.
    @Test func aNewFamilyStartsANewInstance() async throws {
        let sandbox = try sandbox()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        defer { runtime.stop() }
        let started = await runtime.start(theme: "t")
        let reloaded = try #require(await runtime.reload(theme: "t", settings: edit([
            .table(["ref": .int(1), "widget": .string("counter"), "family": .string("small")]),
            .table(["ref": .int(2), "widget": .string("counter")]),
        ]), previous: started))
        #expect(reloaded.instances[0] != started.instances[0] && reloaded.instances[0] != nil)
        #expect(reloaded.instances[1] == started.instances[1])
    }

    @Test func aWidgetMovedInTheListKeepsItsInstance() async throws {
        let sandbox = try sandbox()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        defer { runtime.stop() }
        let started = await runtime.start(theme: "t")
        let reloaded = try #require(await runtime.reload(theme: "t", settings: edit([
            .table(["ref": .int(2), "widget": .string("counter")]),
            .table(["ref": .int(1), "widget": .string("counter")]),
        ]), previous: started))
        #expect(reloaded.instances == [started.instances[1], started.instances[0]])
        #expect(try runtime.eval("return STARTS") == [.int(2)])
    }

    @Test func removingAWidgetStopsItsInstanceAndItsTimers() async throws {
        let sandbox = try sandbox()
        try sandbox.write("plugin/ticker.lua", """
        TICKS = 0
        locky.widget.define("ticker", { init = function(self) self:every(0.05, function() TICKS = TICKS + 1 end) end, render = function() end })
        """)
        try sandbox.write("themes/t.lua", "return { widgets = { { 'counter' }, { 'ticker' } } }")
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        defer { runtime.stop() }
        let started = await runtime.start(theme: "t")
        let reloaded = try #require(await runtime.reload(theme: "t", settings: edit([.table(["ref": .int(1), "widget": .string("counter")])]),
                                                         previous: started))
        #expect(reloaded.instances == [started.instances[0]])
        let ticks = try runtime.eval("return TICKS").first?.int ?? -1
        try await Task.sleep(for: .milliseconds(200))
        #expect(try runtime.eval("return TICKS").first?.int == ticks)
    }

    @Test func theSameSettingsKeepEveryInstance() async throws {
        let sandbox = try sandbox()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        defer { runtime.stop() }
        let started = await runtime.start(theme: "t")
        let reloaded = try #require(await runtime.reload(theme: "t", settings: Settings(), previous: started))
        #expect(reloaded.instances == started.instances)
        #expect(reloaded.theme == started.theme)
    }

    /// A bad change is reported, and the theme shows without it, as when a lock starts.
    @Test func aBadChangeIsReportedOnceAndLeftOut() async throws {
        let sandbox = try sandbox()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        defer { runtime.stop() }
        let started = await runtime.start(theme: "t")
        let bad = edit([.table(["widget": .string("counter"), "anchor": .string("middle")])])
        let first = try #require(await runtime.reload(theme: "t", settings: bad, previous: started))
        let second = try #require(await runtime.reload(theme: "t", settings: bad, previous: first))
        #expect(second.theme.widgets.count == 2)
        #expect(second.problems.count == 1 && second.problems[0].contains("widgets[1].anchor"), "\(second.problems)")
        let fixed = try #require(await runtime.reload(theme: "t", settings: Settings(), previous: second))
        #expect(fixed.problems.isEmpty)
    }
}
