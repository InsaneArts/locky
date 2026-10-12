import Foundation
import Testing
@testable import Locky

@Suite struct TimerAccuracyTests {
    /// Clock widgets rely on aligned one-second timers firing every second.
    @Test func alignedTimersFireEverySecond() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/tick.lua", """
            locky.widget.define("tick", {
              init = function(self) self:every(1, function(self) self:set({ n = (self.state.n or 0) + 1 }) end, { align = true, now = false }) end,
              render = function(self) return locky.ui.text(self.state.n or 0) end,
            })
            """)
        try sandbox.write("themes/t.lua", "return { widgets = { { 'tick' } } }")
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: recorder.delegate)
        // A busy parallel test run can resume this task seconds late, after start and after the sleep. So the
        // window counted is from before the start to after the view is read: no more ticks than seconds began.
        let from = Date().timeIntervalSince1970
        let started = await runtime.start(theme: "t")
        let id = try #require(started.instances[0])
        try await Task.sleep(for: .seconds(4.2))
        guard case .text(let text)? = (recorder.views[id] ?? nil)?.kind else { Issue.record("no view"); return }
        let boundaries = Int(Date().timeIntervalSince1970.rounded(.down) - from.rounded(.down))
        let fired = Int(text) ?? 0
        #expect(fired <= boundaries, "fired \(fired) times across \(boundaries) second boundaries")
        #expect(fired >= 3, "fired \(fired) times in 4.2 s or more")
        runtime.stop()
    }
}
