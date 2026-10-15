import Foundation
import Testing
@testable import Locky

@Suite struct HerdrModuleTests {
    /// The shape of `herdr api snapshot` output, trimmed and anonymized.
    static let snapshot = #"""
    {"id":"1","result":{"snapshot":{"version":"0.9.0","focused_pane_id":null,
      "workspaces":[{"workspace_id":"w1","label":"api","number":1},{"workspace_id":"w2","label":"site","number":2}],
      "tabs":[],"panes":[],
      "agents":[
        {"terminal_id":"t1","pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1","agent_status":"working","agent":"claude","display_agent":null,"name":null,"title":null,"terminal_title_stripped":"Write the release notes","focused":false},
        {"terminal_id":"t2","pane_id":"w1:p2","workspace_id":"w1","tab_id":"w1:t1","agent_status":"blocked","agent":"codex","display_agent":null,"name":null,"title":null,"terminal_title_stripped":"[ * ] Action Required | Add rate limiting | api","focused":false},
        {"terminal_id":"t3","pane_id":"w2:p1","workspace_id":"w2","tab_id":"w2:t1","agent_status":"done","agent":"claude","display_agent":null,"name":"blog","title":null,"terminal_title_stripped":"Migrate the blog","focused":false},
        {"terminal_id":"t4","pane_id":"w2:p2","workspace_id":"w2","tab_id":"w2:t1","agent_status":"sleeping","agent":"pi","display_agent":null,"name":null,"title":null,"terminal_title_stripped":null,"focused":false}
      ]}}}
    """#

    @Test func parsesAndSortsAgents() throws {
        let sandbox = try Sandbox()
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        #expect(runtime.bootForTest().isEmpty)
        let result = try runtime.sync { () -> LuaValue in
            return try runtime.evaluate("""
                local data = require('locky.herdr').parse(...)
                return data
                """.replacingOccurrences(of: "...", with: "[==[\(Self.snapshot)]==]"), budget: 1).first ?? .nil
        }
        let agents = result["agents"].array ?? []
        #expect(agents.map { $0["status"].string } == ["blocked", "done", "working", "unknown"])
        #expect(agents[0]["title"] == .string("Add rate limiting"))   // spinner, "Action Required |", and "| api" removed
        #expect(agents[0]["kind"] == .string("Codex") && agents[0]["workspace"] == .string("Api"))
        #expect(agents[1]["title"] == .string("blog"))                // a name wins over the terminal title
        #expect(agents[3]["title"] == .string("Pi"))                  // no title at all: the agent kind
        #expect(result["counts"]["blocked"] == .int(1) && result["counts"]["unknown"] == .int(1))
        #expect(result["need"] == .int(2))
        #expect(try runtime.eval("return require('locky.herdr').parse('not json')") == [.nil])
    }
}

extension HerdrModuleTests {
    private func runtime(privacy: Bool = false) throws -> LuaRuntime {
        let sandbox = try Sandbox()
        try Settings(["privacy": .bool(privacy)]).save(config: sandbox.config)
        let runtime = LuaRuntime(path: sandbox.path(), delegate: Recorder().delegate)
        #expect(runtime.bootForTest().isEmpty)
        withExtendedLifetime(sandbox) {}
        return runtime
    }

    @Test func readsTheScrubbedSnapshot() throws {
        let json = try String(contentsOf: WeatherTests.fixtures.appending(path: "herdr-snapshot.json"), encoding: .utf8)
        let runtime = try runtime()
        let data = try runtime.eval("return require('locky.herdr').parse([==[\(json)]==])").first ?? .nil
        let agents = data["agents"].array ?? []
        #expect(agents.count == 12 && data["need"] == .int(2))
        #expect(agents.prefix(5).map { $0["status"].string } == ["blocked", "done", "working", "working", "working"])
        #expect(agents[0]["title"] == .string("Add rate limiting to the public endpoints") && agents[0]["workspace"] == .string("Api"))
        // Each status keeps herdr's order of changes: the oldest first.
        #expect(agents[0]["id"].string?.hasPrefix("term_") == true && agents.allSatisfy { $0["since"].isNil })
    }

    @Test func aLongTitleEndsOnAWord() throws {
        let runtime = try runtime()
        let title = String(repeating: "word ", count: 12) + "end"
        let json = #"{"result":{"snapshot":{"agents":[{"terminal_id":"t","agent":"claude","agent_status":"working","terminal_title_stripped":"\#(title)"}]}}}"#
        let shown = try runtime.eval("return require('locky.herdr').parse([==[\(json)]==]).agents[1].title").first?.string ?? ""
        #expect(shown == String(repeating: "word ", count: 8).dropLast() + "…")
        #expect(try runtime.eval("local h = require('locky.herdr') return h.duration(20), h.duration(720), h.duration(7300), h.duration(200000)")
                == [.string("now"), .string("12m"), .string("2h"), .string("2d")])
    }
}
