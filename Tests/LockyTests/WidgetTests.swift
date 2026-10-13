import Foundation
import Testing
@testable import Locky

/// The core widgets' helpers, run in a real Lua state.
@Suite struct WidgetTests {
    private func runtime(_ sandbox: Sandbox) -> LuaRuntime {
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        _ = runtime.bootForTest()
        return runtime
    }

    @Test func aDateShowsInAnotherTimeZone() throws {
        let runtime = runtime(try Sandbox())
        defer { runtime.stop() }
        // 2026-01-15 12:00 UTC.
        #expect(try runtime.eval("return locky.date.format('HH:mm', 1768478400, 'Asia/Tokyo')") == [.string("21:00")])
        #expect(try runtime.eval("return locky.date.format('HH:mm', 1768478400, 'America/New_York')") == [.string("07:00")])
        #expect(try runtime.eval("return locky.date.format('ZZZZZ', 1768478400, 'Asia/Kolkata')") == [.string("+05:30")])
        #expect(throws: (any Error).self) { try runtime.eval("return locky.date.format('HH:mm', 0, 'Mars/Olympus')") }
    }
}
