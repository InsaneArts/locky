import Foundation
import Testing
@testable import Locky

@Suite struct RuntimeTests {
    @Test func pcallAndCoroutinesCannotSwallowATimeout() throws {
        let sandbox = try Sandbox()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        #expect(runtime.bootForTest().isEmpty)
        for source in [
            "while true do pcall(function() while true do end end) end",
            "while true do xpcall(function() while true do end end, function() end) end",
            "local co = coroutine.create(function() while true do end end) while true do coroutine.resume(co) end",
            "local f = coroutine.wrap(function() while true do end end) while true do pcall(f) end",
        ] {
            let cpu = cpuSeconds {
                #expect {
                    try runtime.eval(source, budget: 0.2)
                } throws: { ($0 as? LuaError)?.message.contains("time budget exceeded") == true }
            }
            #expect(cpu < 1.5, "\(source)")
        }
        #expect(try runtime.eval("return 1 + 1") == [.int(2)])
    }

    @Test func pluginsCannotLoadBytecodeOrFinalizers() throws {
        let sandbox = try Sandbox()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        _ = runtime.bootForTest()
        let loaded = try runtime.eval("return select(2, load('\\27Lua'))")
        #expect(loaded.first?.string?.contains("binary") == true)
        #expect(throws: LuaError.self) { try runtime.eval("setmetatable({}, { __gc = function() end })") }
        #expect(try runtime.eval("return getmetatable(setmetatable({}, { __index = {} })) ~= nil") == [.bool(true)])
    }

    @Test func initLuaErrorsAreReportedWithTheirLine() throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ theme = 'x' })\nlocal broken = nil + 1\n")
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        let problems = runtime.bootForTest()
        #expect(problems.count == 1)
        #expect(problems.first?.contains("init.lua:2:") == true)
        // What ran before the error still counts.
        #expect(try runtime.sync { try runtime.call("config", budget: 1) }.first?["theme"] == .string("x"))
    }

    @Test func requireSearchesTheRuntimePathAndTheUserWins() throws {
        let sandbox = try Sandbox()
        try sandbox.write("lua/hello.lua", "return { greet = function(name) return 'hello ' .. name end }")
        try sandbox.write("lua/deep/init.lua", "return 'deep'")
        try sandbox.write("lua/locky/ui.lua", "return 'mine'")  // shadows the built-in module, like Neovim
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        _ = runtime.bootForTest()
        #expect(try runtime.eval("return require('hello').greet('you')") == [.string("hello you")])
        #expect(try runtime.eval("return (require('deep'))") == [.string("deep")])
        #expect(try runtime.eval("return (select(2, pcall(require, 'missing'))):find('runtime path') ~= nil") == [.bool(true)])
    }

    @Test func tablesMergeLikeNeovim() throws {
        let sandbox = try Sandbox()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        _ = runtime.bootForTest()
        let merged = try runtime.eval("""
            local t = locky.tbl.deep_extend('force', { a = { b = 1, c = 2 }, list = { 1, 2, 3 } }, { a = { c = 3 }, list = { 9 } })
            return t.a.b, t.a.c, #t.list, t.list[1], locky.tbl.deep_extend('keep', { x = 1 }, { x = 2, y = 3 }).x
            """)
        #expect(merged == [.int(1), .int(3), .int(1), .int(9), .int(1)])
        #expect(try runtime.eval("return table.concat(locky.str.split('a,b,,c', ','), '|')") == [.string("a|b||c")])
        #expect(try runtime.eval("return locky.json.decode(locky.json.encode({ n = 1, s = 'x', l = { true, false } })).l[2]") == [.bool(false)])
    }

    @Test func aThemeLoadsAndItsWidgetsRender() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/hello.lua", """
            locky.widget.define("hello", {
              opts = { word = "world" },
              init = function(self) self:set({ count = 1 }) end,
              render = function(self)
                return locky.ui.hstack { spacing = 4, locky.ui.text("hello " .. self.opts.word), locky.ui.text(self.state.count or 0) }
              end,
            })
            """)
        try sandbox.write("themes/test.lua", """
            return {
              name = "Test",
              palette = { accent = "#ff0000" },
              background = { color = "accent" },
              widgets = { { "hello", anchor = "top", offset = { 0, 40 }, opts = { word = "Locky" } }, { "missing" } },
            }
            """)
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: recorder.delegate)
        let started = await runtime.start(theme: "test")
        #expect(started.theme.name == "Test")
        #expect(started.theme.background == .color("#ff0000"))
        #expect(started.theme.palette["accent"] == "#ff0000")
        #expect(started.instances.count == 2 && started.instances[0] != nil && started.instances[1] == nil)
        #expect(started.problems.contains { $0.contains("missing") })
        let id = try #require(started.instances[0])
        #expect(await eventually { recorder.views[id] != nil })
        let node = try #require(recorder.views[id] ?? nil)
        guard case .hstack(let children) = node.kind else { Issue.record("expected an hstack"); return }
        #expect(children.map(\.kind) == [.text("hello Locky"), .text("1")])
        runtime.stop()
    }

    @Test func aFailingWidgetIsStoppedAfterThreeErrors() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/bad.lua", """
            locky.widget.define("bad", {
              init = function(self) self:every(0.05, function() error("boom") end, { now = false }) end,
              render = function() return locky.ui.text("ok") end,
            })
            locky.widget.define("slow", {
              render = function() while true do end end,
            })
            """)
        try sandbox.write("themes/t.lua", "return { widgets = { { 'bad' }, { 'slow' } } }")
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: recorder.delegate)
        let started = await runtime.start(theme: "t")
        let bad = try #require(started.instances[0]), slow = try #require(started.instances[1])
        #expect(await eventually { recorder.failures[bad]?.disabled == true })
        #expect(recorder.failures[bad]?.message.contains("boom") == true)
        // One timeout is enough.
        #expect(await eventually { recorder.failures[slow]?.disabled == true })
        #expect(recorder.failures[slow]?.message.contains("time budget exceeded") == true)
        runtime.stop()
    }

    @Test func processesRunWithoutBlocking() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/proc.lua", """
            locky.widget.define("proc", {
              init = function(self)
                self:system({ "echo", "hi there" }, function(self, result) self:set({ out = result.stdout, code = result.code }) end)
                self:system({ "definitely-not-a-command-xyz" }, function(self, result) self:set({ missing = result.code }) end)
              end,
              render = function(self)
                if not (self.state.out and self.state.missing) then return nil end
                return locky.ui.text(self.state.out:gsub("\\n", "") .. " " .. self.state.code .. " " .. self.state.missing)
              end,
            })
            """)
        try sandbox.write("themes/t.lua", "return { widgets = { { 'proc' } } }")
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: recorder.delegate)
        let started = await runtime.start(theme: "t")
        let id = try #require(started.instances[0])
        #expect(await eventually { (recorder.views[id] ?? nil)?.kind == .text("hi there 0 127") })
        runtime.stop()
    }

    @Test func eventsReachHandlers() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/ev.lua", """
            locky.widget.define("ev", {
              init = function(self) self:on("auth_failed", function(self) self:set({ fails = (self.state.fails or 0) + 1 }) end) end,
              render = function(self) return locky.ui.text("fails " .. (self.state.fails or 0)) end,
            })
            """)
        try sandbox.write("themes/t.lua", "return { widgets = { { 'ev' } } }")
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: recorder.delegate)
        let started = await runtime.start(theme: "t")
        let id = try #require(started.instances[0])
        runtime.queue.async { runtime.emit("auth_failed") }
        runtime.queue.async { runtime.emit("auth_failed") }
        #expect(await eventually { (recorder.views[id] ?? nil)?.kind == .text("fails 2") })
        runtime.stop()
    }

    @Test func themeErrorsFallBackToTheDefaultTheme() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/broken.lua", "return { widgets = { { 'clock', anchor = 'nowhere' } } }")
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        let started = await runtime.start(theme: "broken")
        #expect(started.theme.id == "default")
        #expect(started.problems.contains { $0.contains("anchor") })
        runtime.stop()
    }

    @Test func theBareFallbackKeepsPrivacyTheMessageAndHour24() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("themes/default.lua", "return 5")  // shadows the built-in default, so no theme loads
        try Settings(["privacy": .bool(true), "message": .string("If found, call 555"), "hour24": .bool(true)]).save(config: sandbox.config)
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        let started = await runtime.start(theme: "nope")
        runtime.stop()
        #expect(started.theme.id == "fallback")
        #expect(started.privacy)
        #expect(started.message == "If found, call 555")
        #expect(started.hour24 == true)
    }
}

@Suite struct RuntimePauseTests {
    @Test func pausedTimersWaitAndResume() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("plugin/count.lua", """
            locky.widget.define("count", {
              init = function(self) self:every(0.05, function(self) self:set({ n = (self.state.n or 0) + 1 }) end) end,
              render = function(self) return locky.ui.text(self.state.n or 0) end,
            })
            """)
        try sandbox.write("themes/t.lua", "return { widgets = { { 'count' } } }")
        let recorder = Recorder()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: recorder.delegate)
        let started = await runtime.start(theme: "t")
        let id = try #require(started.instances[0])
        func count() -> Int { if case .text(let text)? = (recorder.views[id] ?? nil)?.kind { return Int(text) ?? 0 } else { return 0 } }
        #expect(await eventually { count() >= 3 })
        runtime.setPaused(true)
        try await Task.sleep(for: .milliseconds(150))
        let frozen = count()
        try await Task.sleep(for: .milliseconds(400))
        #expect(count() <= frozen + 1, "no ticks while paused")
        runtime.setPaused(false)
        #expect(await eventually { count() > frozen + 3 })
        runtime.setPaused(true)
        runtime.stop()  // stopping while paused must not leak or crash
        try await Task.sleep(for: .milliseconds(100))
    }
}

@Suite struct LogFileTests {
    /// locky.log stays near 2 MB however long Locky runs: past that, it moves to locky.old.log and starts anew.
    @Test func aLongRunMovesTheLogAside() throws {
        let sandbox = try Sandbox()
        let url = sandbox.root.appending(path: "logs/locky.log")
        let log = LogFile(url: url)
        let message = String(repeating: "x", count: 1000)
        for _ in 0..<2200 { log.write(level: "info", message: message, source: "test") }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        #expect(size < 2 << 20, "\(size) bytes")
        #expect(FileManager.default.fileExists(atPath: sandbox.root.appending(path: "logs/locky.old.log").path))
    }
}

@Suite struct WidgetStartTests {
    /// A widget whose options cannot be made (locky.setup gives it a string, not a table) does not start, and says why
    /// instead of leaving only "not started".
    @Test func aWidgetThatCannotStartSaysWhy() async throws {
        let sandbox = try Sandbox()
        try sandbox.write("init.lua", "locky.setup({ widgets = { box = 'big' } })")
        try sandbox.write("plugin/box.lua", "locky.widget.define('box', { render = function() return locky.ui.text('box') end })")
        try sandbox.write("themes/t.lua", "return { widgets = { { 'box' } } }")
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        defer { runtime.stop() }
        let started = await runtime.start(theme: "t")
        #expect(started.instances == [nil])
        #expect(started.problems.contains { $0.contains("box") && $0.contains("table") }, "\(started.problems)")
    }
}
