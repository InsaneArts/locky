import Darwin
import Foundation
import Testing
@testable import Locky

/// herdr on a temporary Unix socket: answers ping, session.snapshot, and events.subscribe as herdr 0.9 does, and
/// sends events to its subscribers when a test says.
final class FakeHerdrServer: @unchecked Sendable {
    struct Agent {
        var id: String
        var pane: String
        var status: String
        var seq: Int
        var title: String
        var workspace = "w1"
    }

    let path: String
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var agents: [Agent]
    private var subscribers: [Int32] = []
    private var connections: [Int32] = []
    private var rejections = 0
    /// What came in, in order: "snapshot", "subscribe", "ping".
    var log: [String] { lock.withLock { _log } }
    private var _log: [String] = []

    private func record(_ entry: String) { lock.withLock { _log.append(entry) } }

    /// A socket path short enough for sockaddr_un.
    static func temporaryPath() -> String {
        "/tmp/locky-herdr-\(UUID().uuidString.prefix(8)).sock"
    }

    init(path: String = temporaryPath(), agents: [Agent]) throws {
        self.path = path
        self.agents = agents
        try start()
    }

    deinit { stop() }

    /// The next `count` subscriptions fail as when a pane went away.
    func rejectSubscriptions(_ count: Int) { lock.withLock { rejections = count } }

    var subscriberCount: Int { lock.withLock { subscribers.count } }

    /// Changes the agents, then sends `event` for `pane` to every subscriber.
    func change(_ agents: [Agent], event: String = "pane.agent_status_changed", pane: String) {
        let subscribers = lock.withLock {
            self.agents = agents
            return self.subscribers
        }
        let status = agents.first { $0.pane == pane }?.status ?? "idle"
        let line = #"{"event":"\#(event)","data":{"pane_id":"\#(pane)","workspace_id":"w1","agent_status":"\#(status)"}}"# + "\n"
        for fd in subscribers { _ = line.withCString { write(fd, $0, strlen($0)) } }
    }

    func start() throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else { throw POSIXError(.EADDRINUSE) }
        lock.withLock { listener = fd }
        Thread { [self] in
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                var yes: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
                lock.withLock { connections.append(client) }
                Thread { [self] in serve(client) }.start()
            }
        }.start()
    }

    /// Closes the socket and every connection, as herdr does when it quits.
    func stop() {
        let fds = lock.withLock { () -> [Int32] in
            defer { listener = -1; connections = []; subscribers = [] }
            return [listener] + connections
        }
        for fd in fds where fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }
        unlink(path)
    }

    private func snapshot(id: String) -> String {
        let agents = lock.withLock { self.agents }
        let panes = agents.map { #"{"pane_id":"\#($0.pane)","workspace_id":"\#($0.workspace)"}"# }
        let list = agents.map {
            #"{"terminal_id":"\#($0.id)","pane_id":"\#($0.pane)","workspace_id":"\#($0.workspace)","agent":"claude","agent_status":"\#($0.status)","state_change_seq":\#($0.seq),"terminal_title_stripped":"\#($0.title)"}"#
        }
        return #"{"id":"\#(id)","result":{"type":"session_snapshot","snapshot":{"version":"0.9.0","workspaces":[{"workspace_id":"w1","label":"api"}],"panes":[\#(panes.joined(separator: ","))],"agents":[\#(list.joined(separator: ","))]}}}"#
    }

    private func serve(_ fd: Int32) {
        var framer = HerdrSocket.Framer()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0, let frames = try? framer.append(buffer[..<count]) else { return }
            for frame in frames {
                guard let request = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
                      let id = request["id"] as? String, let method = request["method"] as? String else { continue }
                var reply: String
                switch method {
                case "ping":
                    record("ping")
                    reply = #"{"id":"\#(id)","result":{"type":"pong","version":"0.9.0"}}"#
                case "session.snapshot":
                    record("snapshot")
                    reply = snapshot(id: id)
                case "events.subscribe":
                    record("subscribe")
                    let reject = lock.withLock { () -> Bool in
                        defer { rejections = max(0, rejections - 1) }
                        return rejections > 0
                    }
                    if reject {
                        reply = #"{"id":"\#(id):sub:0:locky","error":{"code":"pane_not_found","message":"pane w1:p9 not found"}}"#
                    } else {
                        lock.withLock { subscribers.append(fd) }
                        reply = #"{"id":"\#(id)","result":{"type":"subscription_started"}}"#
                    }
                default:
                    reply = #"{"id":"\#(id)","error":{"code":"unknown_method","message":"no"}}"#
                }
                reply += "\n"
                _ = reply.withCString { write(fd, $0, strlen($0)) }
            }
        }
    }

    /// Marks a subscriber gone when the client closed it: for the test that the service stops.
    func dropClosedSubscribers() {
        lock.withLock {
            subscribers.removeAll { fd in
                var probe = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                guard poll(&probe, 1, 0) > 0 else { return false }
                var byte: UInt8 = 0
                return recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT) == 0
            }
        }
    }
}

/// What a service hands its subscriber, collected.
final class States: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [HerdrService.State] = []

    var all: [HerdrService.State] { lock.withLock { list } }
    var last: HerdrService.State? { all.last }
    func add(_ state: HerdrService.State) { lock.withLock { list.append(state) } }

    /// The agents of the last live state.
    var agents: [HerdrModel.Agent] {
        if case .live(let agents) = last { return agents.list }
        return []
    }
}

@Suite struct HerdrSocketTests {
    @Test func framesSplitOnlyAtTheNewlineByte() throws {
        // U+2028 is a line separator to Foundation's line APIs; herdr sends it unescaped inside strings.
        let line = Array(#"{"title":"one two"}"#.replacingOccurrences(of: " ", with: "\u{2028}").utf8) + [0x0A]
        var framer = HerdrSocket.Framer()
        var frames: [Data] = []
        // One byte at a time: a frame may arrive in any number of reads.
        for byte in line + line.prefix(5) { frames += try framer.append([byte]) }
        #expect(frames.count == 1)
        let object = try JSONSerialization.jsonObject(with: frames[0]) as? [String: String]
        #expect(object?["title"] == "one\u{2028}two")
        frames = try framer.append(line.dropFirst(5) + line)
        #expect(frames.count == 2 && frames.allSatisfy { $0 == Data(line.dropLast()) })
    }

    @Test func aFrameOver16MBIsRefused() throws {
        var framer = HerdrSocket.Framer()
        let chunk = [UInt8](repeating: 0x61, count: 1 << 20)
        for _ in 0..<16 { _ = try framer.append(chunk) }
        #expect(throws: HerdrSocket.Framer.TooLarge.self) { try framer.append([0x61]) }
        // Exactly at the limit, a frame passes.
        var exact = HerdrSocket.Framer()
        for _ in 0..<16 { _ = try exact.append(chunk) }
        #expect(try exact.append([0x0A]).first?.count == 16 << 20)
    }

    @Test func theSessionListNamesTheRunningSocket() {
        let json = Data(#"{"sessions":[{"default":false,"name":"b","running":true,"socket_path":"/b.sock"},{"default":true,"name":"default","running":true,"socket_path":"/a.sock"}]}"#.utf8)
        #expect(HerdrSocket.sessionPath(in: json) == "/a.sock")
        let stopped = Data(#"{"sessions":[{"default":true,"running":false,"socket_path":"/a.sock"}]}"#.utf8)
        #expect(HerdrSocket.sessionPath(in: stopped) == nil)
    }

    /// The scrubbed snapshot of a real herdr 0.9 session.
    @Test func readsASnapshot() throws {
        let data = try Data(contentsOf: WeatherTests.fixtures.appending(path: "herdr-snapshot.json"))
        let snapshot = try HerdrSocket.decode(HerdrSocket.SnapshotReply.self, from: data).result.snapshot
        var model = HerdrModel()
        let changed = model.apply(snapshot, at: 1000, initial: true)
        #expect(changed)
        let agents = model.agents.list
        #expect(agents.count == 12 && Set(agents.map(\.id)).count == 12)
        #expect(agents.filter { $0.status == "blocked" }.count == 1 && agents.filter { $0.status == "working" }.count == 3)
        #expect(agents.allSatisfy { $0.changed == nil && $0.seq != nil && $0.workspace != nil })
        #expect(agents.contains { $0.terminalTitle == "Fix the flaky upload\u{2028}test" })
        #expect(snapshot.paneIDs.count == 14)
    }

    @Test func aStatusChangeStartsItsTime() throws {
        func snapshot(_ statuses: [String]) -> HerdrSnapshot {
            HerdrSnapshot(workspaces: [], panes: [], agents: statuses.enumerated().map { i, status in
                HerdrSnapshot.Agent(terminalId: "t\(i)", paneId: "p\(i)", agentStatus: status, agent: "claude")
            })
        }
        var model = HerdrModel()
        _ = model.apply(snapshot(["working", "idle"]), at: 100, initial: true)
        #expect(model.agents.list.map(\.changed) == [nil, nil])
        // The second agent finished; a third appeared. The first keeps its unknown start.
        let finished = model.apply(snapshot(["working", "done", "working"]), at: 160, initial: false)
        #expect(finished)
        #expect(model.agents.list.map(\.changed) == [nil, 160, 160])
        // Nothing changed: no update, and the times stay.
        let same = model.apply(snapshot(["working", "done", "working"]), at: 200, initial: false)
        #expect(!same)
        #expect(model.agents.list.map(\.changed) == [nil, 160, 160])
        // After a reconnect, a change is from a time not known.
        _ = model.apply(snapshot(["working", "done", "idle"]), at: 300, initial: true)
        #expect(model.agents.list.map(\.changed) == [nil, 160, nil])
    }
}

@Suite(.serialized) struct HerdrServiceTests {
    static let agents = [
        FakeHerdrServer.Agent(id: "t1", pane: "w1:p1", status: "working", seq: 5, title: "Write the release notes"),
        FakeHerdrServer.Agent(id: "t2", pane: "w1:p2", status: "idle", seq: 3, title: "Profile the cold start"),
    ]

    private func service(_ path: String) -> HerdrService {
        HerdrService(socket: { _ in path }, backoff: [0.05, 0.1], safety: 60)
    }

    @Test func subscribesThenTakesTheSnapshotThatCounts() async throws {
        let server = try FakeHerdrServer(agents: Self.agents)
        let service = service(server.path), states = States()
        let id = service.subscribe(states.add)
        defer { service.unsubscribe(id) }
        #expect(await eventually { states.agents.count == 2 })
        // The first snapshot names the panes; the one after herdr's yes is the truth.
        #expect(server.log == ["snapshot", "subscribe", "snapshot"])
        #expect(states.agents.map(\.status) == ["working", "idle"] && states.agents[0].workspace == "api")
    }

    @Test func triesAgainWhenAPaneWentAway() async throws {
        let server = try FakeHerdrServer(agents: Self.agents)
        server.rejectSubscriptions(1)
        let service = service(server.path), states = States()
        let id = service.subscribe(states.add)
        defer { service.unsubscribe(id) }
        #expect(await eventually { !states.agents.isEmpty })
        #expect(server.log.filter { $0 == "subscribe" }.count == 2)
    }

    /// A herdr that keeps naming a pane it cannot find gets a few quick tries, then the backoff: not a snapshot and a
    /// subscription five times a second for as long as the lock shows.
    @Test func aPaneThatNeverComesBackGetsTheBackoff() async throws {
        let server = try FakeHerdrServer(agents: Self.agents)
        server.rejectSubscriptions(1000)
        let service = HerdrService(socket: { _ in server.path }, backoff: [1, 2], safety: 60), states = States()
        let id = service.subscribe(states.add)
        defer { service.unsubscribe(id) }
        try await Task.sleep(for: .seconds(2))
        // The first, three quick tries, and one after the first 1 s pause.
        #expect(server.log.filter { $0 == "subscribe" }.count <= 6, "\(server.log.filter { $0 == "subscribe" }.count) subscriptions")
    }

    @Test func aStatusChangeShowsAtOnce() async throws {
        let server = try FakeHerdrServer(agents: Self.agents)
        let service = service(server.path), states = States()
        let id = service.subscribe(states.add)
        defer { service.unsubscribe(id) }
        #expect(await eventually { states.agents.count == 2 })
        var changed = Self.agents
        changed[0].status = "blocked"
        changed[0].seq = 9
        let before = Date().timeIntervalSince1970
        server.change(changed, pane: "w1:p1")
        #expect(await eventually(timeout: 1) { states.agents.first?.status == "blocked" })
        let since = try #require(states.agents.first?.changed)
        #expect(since >= before - 0.01 && since <= Date().timeIntervalSince1970)
        #expect(states.agents[1].changed == nil)
    }

    @Test func aNewPaneMeansANewSubscription() async throws {
        let server = try FakeHerdrServer(agents: Self.agents)
        let service = service(server.path), states = States()
        let id = service.subscribe(states.add)
        defer { service.unsubscribe(id) }
        #expect(await eventually { states.agents.count == 2 })
        server.change(Self.agents + [.init(id: "t3", pane: "w1:p3", status: "working", seq: 10, title: "Port the settings screen")],
                      event: "pane.created", pane: "w1:p3")
        #expect(await eventually { states.agents.count == 3 && server.log.filter { $0 == "subscribe" }.count == 2 })
    }

    @Test func offlineUntilHerdrStartsThenLive() async throws {
        let path = FakeHerdrServer.temporaryPath()
        let service = service(path), states = States()
        let id = service.subscribe(states.add)
        defer { service.unsubscribe(id) }
        #expect(await eventually { states.last == .offline })
        // A lock's first frame does not wait longer than it must.
        #expect(service.current(waiting: 0) == .offline)
        let server = try FakeHerdrServer(path: path, agents: Self.agents)
        #expect(await eventually { states.agents.count == 2 })
        // herdr quits, then starts again: offline, then live.
        server.stop()
        #expect(await eventually { states.last == .offline })
        try server.start()
        #expect(await eventually { states.agents.count == 2 })
        #expect(states.all.filter { $0 == .offline }.count == 2)
    }

    @Test func stopsWhenNoWidgetWatches() async throws {
        let server = try FakeHerdrServer(agents: Self.agents)
        let service = service(server.path), states = States()
        let id = service.subscribe(states.add)
        #expect(await eventually { server.subscriberCount == 1 && !states.agents.isEmpty })
        service.unsubscribe(id)
        #expect(!service.isRunning)
        // The thread closed its connection: nothing listens any more.
        #expect(await eventually { server.dropClosedSubscribers(); return server.subscriberCount == 0 })
        let count = states.all.count
        server.change([], pane: "w1:p1")
        try await Task.sleep(for: .milliseconds(200))
        #expect(states.all.count == count)
    }

    /// A runtime watches while a widget that shows agents runs, and lets go when the session ends.
    @Test func aRuntimeWatchesWhileItsWidgetRuns() async throws {
        let server = try FakeHerdrServer(agents: Self.agents)
        let service = service(server.path)
        let sandbox = try Sandbox()
        try sandbox.write("plugin/probe.lua", """
            local herdr = require("locky.herdr")
            locky.widget.define("probe", {
              init = function(self) herdr.watch(self, function(self, data) self:set({ data = data }) end) end,
              render = function(self)
                local lines = {}
                for _, a in ipairs(self.state.data and self.state.data.agents or {}) do
                  lines[#lines + 1] = locky.ui.text(a.status .. " " .. a.title)
                end
                return locky.ui.vstack(lines)
              end,
            })
            """)
        try sandbox.write("themes/a.lua", "return { widgets = { { 'probe' } } }")
        let recorder = Recorder()
        let environment = LuaRuntime.Environment()
        environment.herdr = service
        let runtime = LuaRuntime(path: sandbox.path(), environment: environment, delegate: recorder.delegate)
        let started = await runtime.start(theme: "a")
        let id = try #require(started.instances.first ?? nil)
        #expect(service.isRunning)
        #expect(await eventually { WidgetText.of(recorder.views[id] ?? nil) == ["working Write the release notes", "idle Profile the cold start"] })
        var changed = Self.agents
        changed[1].status = "blocked"
        server.change(changed, pane: "w1:p2")
        #expect(await eventually(timeout: 1) {
            WidgetText.of(recorder.views[id] ?? nil) == ["blocked Profile the cold start", "working Write the release notes"]
        })
        runtime.stop()
        #expect(await eventually { !service.isRunning })
    }
}
