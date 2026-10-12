import Foundation
import Testing
@testable import Locky

/// Cases a code review found that could crash the app (ending the lock) or run past the time budget.
@Suite struct GuardRegressionTests {
    private func runtime() throws -> LuaRuntime {
        let sandbox = try Sandbox()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        #expect(runtime.bootForTest().isEmpty)
        return runtime
    }

    private func expectStops(_ runtime: LuaRuntime, _ source: String, within seconds: Double = 1.5, sourceLocation: SourceLocation = #_sourceLocation) {
        let start = Date()
        #expect(throws: LuaError.self, sourceLocation: sourceLocation) { try runtime.eval(source, budget: 0.2) }
        #expect(Date().timeIntervalSince(start) < seconds, "\(source)", sourceLocation: sourceLocation)
    }

    @Test func aPushNearTheHardLimitDoesNotAbort() throws {
        let vm = try LuaVM(memoryLimit: 4 << 20)  // hard limit 8 MB
        let fill = try vm.load("T = {} for i = 1, 400 do T[i] = string.rep('x', 20000) .. i end", chunkName: "=fill")
        _ = try? vm.call(fill, budget: 2)  // stops with a memory error past 4 MB, keeping what it made
        let echo = try vm.load("return #(...)", chunkName: "=echo")
        // A 6 MB argument goes past the hard limit while Locky pushes it: before the fix, this aborted the app.
        let result = Result { try vm.call(echo, [.string(String(repeating: "y", count: 6 << 20))], budget: 1) }
        if case .failure(let error) = result { #expect((error as? LuaError)?.message.contains("memory") == true) }
    }

    @Test func handlersAndReadersCannotOutrunTheBudget() throws {
        let runtime = try runtime()
        expectStops(runtime, "xpcall(function() error('bug') end, function() while true do end end)")
        expectStops(runtime, "xpcall(function() while true do end end, function() while true do end end)")
        expectStops(runtime, "local f repeat f = load(function() while true do end end) until f")
        // A C function the count hook cannot interrupt still counts as a failure when it overran.
        expectStops(runtime, "table.move({}, 1, 4e7, 1, {})", within: 5)
        #expect(try runtime.eval("return 1") == [.int(1)])
    }

    @Test func trimIsLinear() throws {
        let runtime = try runtime()
        let start = Date()
        #expect(try runtime.eval("return locky.str.trim(string.rep(' ', 1000000) .. 'x' .. string.rep(' ', 1000000))", budget: 2) == [.string("x")])
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(try runtime.eval("return locky.str.trim('  a b  '), locky.str.trim('   ')") == [.string("a b"), .string("")])
    }

    @Test func badArgumentsAreErrorsNotCrashes() throws {
        let runtime = try runtime()
        let nul = try runtime.eval(#"return select(2, pcall(locky.system, { "echo", "a\0b" }))"#)
        #expect(nul.first?.string?.contains("NUL") == true)
        let timer = try runtime.eval("return select(2, pcall(locky.defer, function() end, 1e12))")
        #expect(timer.first?.string?.contains("1e9") == true)
    }

    @Test func standardFunctionsBehave() throws {
        let runtime = try runtime()
        // Chunks from load, loadfile, and dofile keep their globals.
        #expect(try runtime.eval("return load('return type(print)')()") == [.string("function")])
        // No finalizer can be attached to file handles or widget instances.
        #expect(try runtime.eval("return getmetatable(io.stdout)") == [.bool(false)])
        // A failing wrapped coroutine is closed, so its <close> variables run.
        #expect(try runtime.eval("""
            local closed = false
            local f = coroutine.wrap(function()
              local guard <close> = setmetatable({}, { __close = function() closed = true end })
              coroutine.yield()
              error("boom")
            end)
            f()
            pcall(f)
            return closed
            """) == [.bool(true)])
    }

    @Test func pipesAreRefused() throws {
        let runtime = try runtime()
        let fifo = FileManager.default.temporaryDirectory.appending(path: "locky-fifo-\(UUID().uuidString)").path
        #expect(mkfifo(fifo, 0o600) == 0)
        defer { unlink(fifo) }
        let start = Date()
        let result = try runtime.eval("return select(2, pcall(io.open, '\(fifo)'))")
        #expect(result.first?.string?.contains("only regular files") == true)
        #expect(Date().timeIntervalSince(start) < 1)
    }
}

/// Values Lua makes easily (0/0, 1/0, empty lists) that once crashed the app.
@Suite struct OddValueTests {
    @Test func viewsRejectOrClampOddNumbers() throws {
        #expect { try Node(lua: .table(["text": .string("x"), "padding": .double(.infinity)])) } throws: {
            ($0 as? LuaError)?.message.contains("finite") == true
        }
        #expect { try Node(lua: .table(["text": .string("x"), "offset": .array([.double(.nan), .int(0)])])) } throws: { _ in true }
        let empty = try Node(lua: .table(["text": .string("x"), "padding": .array([])]))
        #expect(empty.padding == nil)
        let chart = try Node(lua: .table(["chart": .array([]), "slots": .int(-1)]))
        #expect(chart.slots == 2)
        let huge = try Node(lua: .table(["text": .string("x"), "lines": .double(9.3e18), "width": .double(1e300)]))
        #expect(huge.lines == 10_000 && huge.width == 100_000)
    }

    @Test func themesIgnoreOddPlacementsAndDurations() throws {
        let theme = try Theme(lua: .table([
            "id": .string("t"),
            "auth": .table(["idle": .double(.infinity), "offset": .array([.double(.nan), .int(0)])]),
            "widgets": .array([.table(["widget": .string("w"), "offset": .array([.double(.infinity), .int(0)]), "size": .array([.double(.nan), .int(10)])])]),
        ]), path: try Sandbox().path())
        #expect(theme.auth.idle == 20)
        #expect(theme.auth.offset == CGPoint(x: 0, y: -60))
        #expect(theme.widgets.first?.offset == .zero && theme.widgets.first?.size == nil)
    }
}

@Suite struct ViewLimitTests {
    @Test func aWidgetCannotDrawWithoutLimit() throws {
        let dots = LuaValue.array(Array(repeating: .table(["dot": .bool(true)]), count: Node.viewLimit + 10))
        #expect { try Node(lua: .table(["vstack": dots])) } throws: { ($0 as? LuaError)?.message.contains("too many views") == true }
        let long = try Node(lua: .table(["text": .string(String(repeating: "a", count: 50_000))]))
        if case .text(let text) = long.kind { #expect(text.count == Node.textLimit) }
    }
}
