import Foundation
import Testing
@testable import Locky

@Suite struct LuaVMTests {
    private func run(_ vm: LuaVM, _ source: String, budget: Double = 1) throws -> [LuaValue] {
        let chunk = try vm.load(source, chunkName: "=test")
        defer { vm.release(chunk) }
        return try vm.call(chunk, budget: budget)
    }

    @Test func valuesCrossBothWays() throws {
        let vm = try LuaVM()
        let results = try run(vm, "return 1, 2.5, 'two', true, nil, {a = 3, b = {c = 'd'}}, {4, 5}, {}")
        #expect(results == [.int(1), .double(2.5), .string("two"), .bool(true), .nil,
                            .table(["a": .int(3), "b": .table(["c": .string("d")])]), .array([.int(4), .int(5)]), .array([])])

        let echo = try vm.load("return ...", chunkName: "=echo")
        let value: LuaValue = .table(["list": .array([.string("x"), .double(1.5)]), "flag": .bool(false), "text": .string("ünïcödé\u{2028}")])
        #expect(try vm.call(echo, [value, .int(-7)], budget: 1) == [value, .int(-7)])
        vm.release(echo)
    }

    @Test func sparseListsAndFunctionsAreRefused() throws {
        let vm = try LuaVM()
        #expect(try run(vm, "return {1, 2, a = 3}") == [.table(["1": .int(1), "2": .int(2), "a": .int(3)])])
        #expect(try run(vm, "return {1, 2, a = 3}").first?.array == [.int(1), .int(2)])
        #expect(throws: LuaError.self) { try run(vm, "return {[1] = 'a', [3] = 'c'}") }
        #expect(throws: LuaError.self) { try run(vm, "return function() end") }
    }

    /// The budget counts running, not waiting: a busy Mac, or a native call that blocks, must not stop
    /// code that works (a flaky test caught a widget stopped while the test run loaded every core).
    @Test func waitingDoesNotCountAgainstTheBudget() throws {
        let vm = try LuaVM()
        let exported = try vm.runPrelude("""
            local native = ...
            native.wait()
            return { done = true }
            """, chunkName: "=wait", natives: ["wait": { _ in usleep(300_000); return [] }], budget: 0.1)
        #expect(exported["done"] == .bool(true))
        // Running past the budget still stops.
        #expect {
            try run(vm, "while true do end", budget: 0.1)
        } throws: { ($0 as? LuaError)?.message.contains("time budget exceeded") == true }
    }

    /// Waiting is free only up to ten times the budget and a second: a loop of calls that block (a slow network
    /// file read, IPC) uses almost no CPU time, and would hold the Lua queue for as long as it likes.
    @Test func aLoopOfBlockingCallsStopsAtTheHardLimit() throws {
        let vm = try LuaVM()
        let start = Date()
        #expect {
            // 100 waits of 50 ms: 5 s, where the hard limit of a 0.1 s budget is 2 s.
            try vm.runPrelude("local native = ... for i = 1, 100 do native.wait() end", chunkName: "=wait",
                              natives: ["wait": { _ in usleep(50_000); return [] }], budget: 0.1)
        } throws: { ($0 as? LuaError)?.message.contains("time budget exceeded") == true }
        #expect(Date().timeIntervalSince(start) < 4)
    }

    @Test func anEndlessLoopStopsAtItsBudget() throws {
        let vm = try LuaVM()
        let cpu = cpuSeconds {
            #expect {
                try run(vm, "while true do end", budget: 0.2)
            } throws: { ($0 as? LuaError)?.message.contains("time budget exceeded") == true }
        }
        #expect(cpu < 1)
        // The state is still usable.
        #expect(try run(vm, "return 40 + 2") == [.int(42)])
    }

    @Test func runawayMemoryStops() throws {
        let vm = try LuaVM(memoryLimit: 16 << 20)
        #expect {
            try run(vm, "local t = {} for i = 1, 1e9 do t[i] = ('x'):rep(64) .. i end", budget: 10)
        } throws: { ($0 as? LuaError)?.message.contains("not enough memory") == true }
        vm.collectGarbage()
        #expect(vm.memoryUsed < 16 << 20)
        #expect(try run(vm, "return 'still alive'") == [.string("still alive")])
    }

    @Test func dangerousFunctionsAreGone() throws {
        let vm = try LuaVM()
        let results = try run(vm, """
            return os.exit == nil, os.execute == nil, io.popen == nil, package.loadlib == nil, string.dump == nil,
                   debug.sethook == nil, debug.getregistry == nil, debug.setmetatable == nil,
                   debug.traceback ~= nil, debug.getinfo ~= nil, package.cpath == ""
            """)
        #expect(results == Array(repeating: .bool(true), count: 11))
    }

    @Test func sourceCompileErrorsNameTheFile() throws {
        let vm = try LuaVM()
        #expect {
            _ = try vm.load("local x = ", chunkName: "@~/.config/locky/init.lua")
        } throws: { ($0 as? LuaError)?.message.hasPrefix("~/.config/locky/init.lua:1:") == true }
    }

    @Test func registryReferencesAreCounted() throws {
        let vm = try LuaVM()
        let before = vm.liveRefs
        let chunk = try vm.load("return 1", chunkName: "=x")
        #expect(vm.liveRefs == before + 1)
        vm.release(chunk)
        #expect(vm.liveRefs == before)
    }
}
