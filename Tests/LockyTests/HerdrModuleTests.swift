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

    /// Agents as locky.herdr gives them: one blocked for 4 minutes, one done for an hour, two working (one for 12
    /// minutes, one since before Locky connected), and three idle.
    static let data = """
        { fetched = locky.now(), need = 2, counts = { blocked = 1, done = 1, working = 2, idle = 3, unknown = 0 }, agents = {
          { id = "t1", status = "blocked", kind = "Codex", title = "Add rate limiting", workspace = "Api", since = 240 },
          { id = "t2", status = "done", kind = "Claude", title = "Migrate the blog", workspace = "Site", since = 3600 },
          { id = "t3", status = "working", kind = "Claude", title = "Write the release notes", workspace = "Api", since = 720 },
          { id = "t4", status = "working", kind = "Claude", title = "Profile the cold start", workspace = "Site" },
          { id = "t5", status = "idle", kind = "Claude", title = "Idle one", workspace = "Api" },
          { id = "t6", status = "idle", kind = "Claude", title = "Idle two", workspace = "Api" },
          { id = "t7", status = "idle", kind = "Claude", title = "Idle three", workspace = "Api" } } }
        """

    /// The texts the agents widget shows for `data` with `opts`, in `family` when given.
    private func shown(_ data: String, opts: String = "{}", family: String = "nil", privacy: Bool = false) throws -> [String] {
        let runtime = try runtime(privacy: privacy)
        let view = try runtime.eval("""
            local def = locky.widget.get("agents")
            local opts = locky.tbl.extend("force", def.opts, \(opts))
            return def.render({ opts = opts, family = \(family), state = { data = \(data) } })
            """).first ?? .nil
        return view.isNil ? [] : WidgetText.of(try Node(lua: view))
    }

    @Test func theListPutsWhoNeedsYouFirstAndCountsTheIdle() throws {
        let texts = try shown(Self.data)
        #expect(texts == ["Agents", "2 need you",
                          "Add rate limiting", "Needs you", " · Api · 4m",
                          "Migrate the blog", "Done", " · Site · 1h",
                          "Write the release notes", "Working", " · Api · 12m",
                          "Profile the cold start", "Working", " · Site",
                          "+ 3 idle"], "\(texts)")
        // Two rows: the rest is counted.
        #expect(try shown(Self.data, opts: "{ rows = 2 }").suffix(1) == ["+ 2 more · 3 idle"])
    }

    @Test func theListSaysWhenThereIsNothingToShow() throws {
        #expect(try shown("false") == ["Herdr isn't running"])
        #expect(try shown("false", opts: "{ offline = false }").isEmpty)
        let none = "{ fetched = 0, need = 0, counts = { blocked = 0, done = 0, working = 0, idle = 0, unknown = 0 }, agents = {} }"
        #expect(try shown(none) == ["Agents", "No agents running"])
        let idle = "{ fetched = 0, need = 0, counts = { blocked = 0, done = 0, working = 0, idle = 1, unknown = 0 }, agents = { { id = 'a', status = 'idle', kind = 'Claude', title = 'Rest', workspace = '' } } }"
        #expect(try shown(idle) == ["Agents", "Nothing needs you", "+ 1 idle"])
        #expect(try shown(idle, opts: "{ style = 'summary' }") == ["1 idle"])
    }

    @Test func everyStyleAndFamilyDraws() throws {
        #expect(try shown(Self.data, opts: "{ style = 'summary' }") == ["2 need you · 2 working"])
        #expect(try shown(Self.data, opts: "{ style = 'board' }").prefix(6) == ["Agents", "Codex", "Add rate limiting", "Needs you", "4m", "Claude"])
        #expect(try shown(Self.data, family: "'circular'") == ["2"])
        #expect(try shown(Self.data, family: "'inline'") == ["2 need you · 2 working"])
        #expect(try shown(Self.data, family: "'rectangular'") == ["Agents", "2 need you · 2 working", "Add rate limiting · 4m"])
        let small = try shown(Self.data, family: "'small'")
        #expect(small == ["2", "Need You", "Add rate limiting", "4m", "Migrate the blog", "1h", "Write the release notes", "12m"], "\(small)")
        let medium = try shown(Self.data, family: "'medium'")
        #expect(medium.prefix(2) == ["2", "Need You"] && medium.last == "+ 2 more · 3 idle", "\(medium)")
        let large = try shown(Self.data, family: "'large'")
        #expect(large.contains("Profile the cold start") && large.last == "+ 3 idle" && !large.contains("Idle one"), "\(large)")
        #expect(try shown("false", family: "'small'").contains("Herdr isn't running"))
    }

    /// In privacy mode a title is the agent's kind: the board drops its title column rather than say it twice.
    @Test func theBoardSaysTheKindOnceInPrivacyMode() throws {
        let json = try String(contentsOf: WeatherTests.fixtures.appending(path: "herdr-snapshot.json"), encoding: .utf8)
        let texts = try shown("require('locky.herdr').parse([==[\(json)]==])", opts: "{ style = 'board', rows = 2 }", privacy: true)
        #expect(texts == ["Agents", "Claude", "Needs you", "", "Claude", "Done", ""], "\(texts)")
    }
}
