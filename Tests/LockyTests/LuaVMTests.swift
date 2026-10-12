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

    @Test func anEndlessLoopStopsAtItsBudget() throws {
        let vm = try LuaVM()
        let start = Date()
        #expect {
            try run(vm, "while true do end", budget: 0.2)
        } throws: { ($0 as? LuaError)?.message.contains("time budget exceeded") == true }
        #expect(Date().timeIntervalSince(start) < 1)
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
