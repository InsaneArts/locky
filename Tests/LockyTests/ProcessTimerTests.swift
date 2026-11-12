import Foundation
import Testing
@testable import Locky

@Suite struct ProcessTimerTests {
    /// Running programs must not stop timers: a widget polls a program while a clock ticks.
    @Test func timersKeepFiringWhileProgramsRun() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/both.lua", """
            locky.widget.define("both", {
              init = function(self)
                self:every(0.1, function(self) self.state.ticks = (self.state.ticks or 0) + 1 end)
                self:every(0.3, function(self)
                  self:system({ "echo", "hi" }, function(self, r) self:set({ exits = (self.state.exits or 0) + 1 }) end)
                end)
              end,
              render = function(self) return locky.ui.text((self.state.ticks or 0) .. "/" .. (self.state.exits or 0)) end,
            })
            """)
        try sandbox.write("themes/t.lua", "return { widgets = { { 'both' } } }")
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: recorder.delegate)
        let started = await runtime.start(theme: "t")
        let id = try #require(started.instances[0])
        try await Task.sleep(for: .seconds(3))
        guard case .text(let text)? = (recorder.views[id] ?? nil)?.kind else { Issue.record("no view"); return }
        let parts = text.split(separator: "/").compactMap { Int($0) }
        #expect(parts.count == 2 && parts[0] >= 25 && parts[1] >= 8, "ticks/exits after 3 s: \(text)")
        runtime.stop()
    }
}

@Suite struct ChildProcessTests {
    /// A program that leaves a background child holding its output pipe still reports soon after it exits.
    /// A program that cannot start (here, in a folder that is not there) reports code 126, and Locky goes on: the
    /// pipes and the exit it waited for must not keep it waiting, or crash it when the process object goes.
    @Test func aProgramThatCannotStartReports126() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/nowhere.lua", """
            locky.widget.define("nowhere", {
              init = function(self)
                self:system({ "true" }, { cwd = "/no/such/folder/locky" }, function(self, r)
                  self:set({ code = r.code, err = r.stderr })
                end)
              end,
              render = function(self) return self.state.code and locky.ui.text(tostring(self.state.code)) or nil end,
            })
            """)
        try sandbox.write("themes/t.lua", "return { widgets = { { 'nowhere' } } }")
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: recorder.delegate)
        let started = await runtime.start(theme: "t")
        let id = try #require(started.instances[0])
        #expect(await eventually(timeout: 5) { (recorder.views[id] ?? nil) != nil })
        guard case .text(let code)? = (recorder.views[id] ?? nil)?.kind else { Issue.record("no result"); return }
        #expect(code == "126")
        // The runtime still answers: the failed start left nothing behind on its queue.
        #expect(try runtime.eval("return 1 + 1").first == .int(2))
        runtime.stop()
    }

    @Test func aBackgroundChildDoesNotHoldTheResult() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/bg.lua", """
            locky.widget.define("bg", {
              init = function(self)
                self.state.started = locky.now()
                self:system({ "sh", "-c", "sleep 10 & echo hi" }, function(self, r)
                  self:set({ took = locky.now() - self.state.started, out = r.stdout })
                end)
              end,
              render = function(self) return self.state.took and locky.ui.text(("%.1f"):format(self.state.took)) or nil end,
            })
            """)
        try sandbox.write("themes/t.lua", "return { widgets = { { 'bg' } } }")
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: recorder.delegate)
        let started = await runtime.start(theme: "t")
        let id = try #require(started.instances[0])
        // views[id] holds nil while the widget draws nothing: wait for an actual view. The child lives 10 s and the
        // result may take 5, so a full parallel test run (every core busy spawning processes) does not fail it.
        #expect(await eventually(timeout: 8) { (recorder.views[id] ?? nil) != nil }, "the result should not wait for the 10 s background child")
        guard case .text(let took)? = (recorder.views[id] ?? nil)?.kind else { Issue.record("no result"); return }
        #expect((Double(took) ?? 99) < 5, "took \(took) s")
        runtime.stop()
    }
}
