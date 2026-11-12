import Darwin
import Foundation

/// herdr's coding agents (https://herdr.dev), live from its socket, for every widget that shows them. One connection
/// serves the whole app, and it is open only while a lock or a preview shows such a widget. Events say that something
/// changed; a snapshot after each burst of events says what.
final class HerdrService: @unchecked Sendable {
    /// What widgets get: herdr is not running, or its agents.
    enum State: Equatable, Sendable {
        case offline
        case live(HerdrModel.Agents)

        /// false, or { agents = { ... }, fetched }: locky.herdr shapes it for widgets.
        var lua: LuaValue {
            switch self {
            case .offline: .bool(false)
            case .live(let agents): agents.lua
            }
        }
    }

    typealias Handler = @Sendable (State) -> Void

    static let shared = HerdrService()

    /// The socket to try, asked before each connection: herdr may start after Locky. The argument is true for the
    /// first: only then may it run herdr to ask.
    private let socket: @Sendable (_ first: Bool) -> String?
    /// Seconds between attempts while herdr is away: the last one repeats.
    private let backoff: [Double]
    /// Seconds between snapshots without events, in case an event was missed.
    private let safety: Double
    /// Guards the three below, and wakes `current` when the first state arrives.
    private let lock = NSCondition()
    private var handlers: [UUID: Handler] = [:]
    private var latest: State?
    private var run: Run?

    init(socket: @escaping @Sendable (_ first: Bool) -> String? = HerdrSocket.find, backoff: [Double] = [0.5, 1, 2, 3],
         safety: Double = 60) {
        self.socket = socket
        self.backoff = backoff
        self.safety = safety
    }

    /// Calls `handler` on each change, from the service's thread, until `unsubscribe`. The first subscriber starts the
    /// connection.
    func subscribe(_ handler: @escaping Handler) -> UUID {
        let id = UUID()
        lock.withLock {
            handlers[id] = handler
            guard run == nil else { return }
            let run = Run()
            self.run = run
            let thread = Thread { [self] in loop(run) }
            thread.name = "Locky herdr"
            thread.qualityOfService = .utility
            thread.start()
        }
        return id
    }

    /// The last subscriber stops the connection and its thread.
    func unsubscribe(_ id: UUID) {
        lock.withLock {
            handlers[id] = nil
            guard handlers.isEmpty, let run else { return }
            run.cancel()
            self.run = nil
            latest = nil
        }
    }

    /// The latest state, waiting up to `seconds` for the first one: a lock's first frame shows the agents.
    func current(waiting seconds: Double) -> State? {
        let deadline = Date().addingTimeInterval(seconds)
        return lock.withLock {
            while latest == nil, run != nil, lock.wait(until: deadline) {}
            return latest
        }
    }

    /// True while a connection loop runs: for tests.
    var isRunning: Bool { lock.withLock { run != nil } }

    private func publish(_ state: State, from run: Run) {
        let handlers: [Handler]? = lock.withLock {
            guard self.run === run, !run.isCancelled, latest != state else { return nil }
            latest = state
            lock.broadcast()
            return Array(self.handlers.values)
        }
        guard let handlers else { return }
        for handler in handlers { handler(state) }
    }

    // MARK: The connection

    /// One loop's life: cancelled when the last subscriber leaves. Its pipe wakes the loop from any wait.
    private final class Run: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        let wake: (read: Int32, write: Int32)

        init() {
            var fds: [Int32] = [-1, -1]
            pipe(&fds)
            wake = (fds[0], fds[1])
        }

        deinit {
            close(wake.read)
            close(wake.write)
        }

        var isCancelled: Bool { lock.withLock { cancelled } }

        func cancel() {
            lock.withLock { cancelled = true }
            var byte: UInt8 = 1
            _ = write(wake.write, &byte, 1)
        }
    }

    private enum Ending: Error {
        /// No herdr at the socket, or it did not answer.
        case unreachable
        /// The connection ended: herdr quit or restarted.
        case closed
        /// A pane went away between the snapshot and the subscription.
        case paneNotFound
        case cancelled
    }

    private func loop(_ run: Run) {
        var model = HerdrModel()
        var failures = 0
        var found: String?
        while !run.isCancelled {
            // A socket found by asking herdr stays the one to try.
            let path = socket(found == nil && failures == 0) ?? found
            found = path
            do {
                guard let path else { throw Ending.unreachable }
                // Returns when the agents' panes changed: subscribe again, at once.
                try session(at: path, run: run, model: &model)
                failures = 0
                continue
            } catch Ending.paneNotFound {
                if !pause(0.2, run) { return }
                continue
            } catch Ending.unreachable {
                publish(.offline, from: run)
            } catch {
                if case Ending.cancelled = error { return }
            }
            if !pause(backoff[min(failures, backoff.count - 1)], run) { return }
            failures += 1
        }
    }

    /// Waits `seconds`; false when the run was cancelled meanwhile.
    private func pause(_ seconds: Double, _ run: Run) -> Bool {
        var fd = pollfd(fd: run.wake.read, events: Int16(POLLIN), revents: 0)
        _ = poll(&fd, 1, Int32(seconds * 1000))
        return !run.isCancelled
    }

    /// Subscribes, waits for herdr's yes, then takes the snapshot that counts, and follows events until the
    /// connection ends (throws) or the panes change (returns).
    private func session(at path: String, run: Run, model: inout HerdrModel) throws {
        let first = try snapshot(at: path, run: run)
        guard let events = HerdrSocket.connect(path) else { throw Ending.unreachable }
        defer { close(events) }
        let panes = first.paneIDs
        try HerdrSocket.send(HerdrSocket.subscription(panes: panes), to: events)
        var framer = HerdrSocket.Framer()
        // herdr answers the subscription, or names a pane that went away.
        acknowledging: while true {
            guard let frames = try read(events, framer: &framer, run: run, timeout: 2) else { throw Ending.unreachable }
            for frame in frames {
                let envelope = try? HerdrSocket.decode(HerdrSocket.Envelope.self, from: frame)
                if envelope?.error?.code == "pane_not_found" { throw Ending.paneNotFound }
                if envelope?.error != nil { throw Ending.closed }
                if envelope?.result != nil { break acknowledging }
            }
        }
        var current = try snapshot(at: path, run: run)
        _ = model.apply(current, at: Date().timeIntervalSince1970, initial: true)
        publish(.live(model.agents), from: run)
        var lastSnapshot = Date()
        // The first and the last event of a burst of events.
        var burst: (first: Date, last: Date)?
        while true {
            // 50 ms after a burst's last event, or 300 ms after its first; else the safety snapshot.
            let due = burst.map { min($0.last.addingTimeInterval(0.05), $0.first.addingTimeInterval(0.3)) }
                ?? lastSnapshot.addingTimeInterval(safety)
            if due > Date(), let frames = try read(events, framer: &framer, run: run, timeout: due.timeIntervalSinceNow) {
                if frames.contains(where: { (try? HerdrSocket.decode(HerdrSocket.Envelope.self, from: $0))?.event != nil }) {
                    burst = (burst?.first ?? Date(), Date())
                }
                continue
            }
            current = try snapshot(at: path, run: run)
            lastSnapshot = Date()
            // A status that changed in the burst began at its first event.
            if model.apply(current, at: (burst?.first ?? lastSnapshot).timeIntervalSince1970, initial: false) {
                publish(.live(model.agents), from: run)
            }
            burst = nil
            if current.paneIDs != panes { return }
        }
    }

    /// Frames from `fd`, or nil when `timeout` passed first. Throws when the connection ended or the run was cancelled.
    private func read(_ fd: Int32, framer: inout HerdrSocket.Framer, run: Run, timeout: Double) throws -> [Data]? {
        var fds = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0), pollfd(fd: run.wake.read, events: Int16(POLLIN), revents: 0)]
        let ready = poll(&fds, 2, Int32(max(0, timeout * 1000).rounded(.up)))
        if run.isCancelled { throw Ending.cancelled }
        if ready < 0, errno != EINTR { throw Ending.closed }
        guard ready > 0, fds[0].revents != 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: 64 << 10)
        let count = Darwin.read(fd, &buffer, buffer.count)
        guard count > 0 else { throw Ending.closed }
        do {
            return try framer.append(buffer[..<count])
        } catch {
            throw Ending.closed
        }
    }

    /// `session.snapshot` on a connection of its own: a subscribed connection only sends events.
    private func snapshot(at path: String, run: Run) throws -> HerdrSnapshot {
        guard let fd = HerdrSocket.connect(path) else { throw Ending.unreachable }
        defer { close(fd) }
        try HerdrSocket.send(#"{"id":"locky-snapshot","method":"session.snapshot","params":{}}"#, to: fd)
        var framer = HerdrSocket.Framer()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            for frame in try read(fd, framer: &framer, run: run, timeout: deadline.timeIntervalSinceNow) ?? [] {
                guard let reply = try? HerdrSocket.decode(HerdrSocket.SnapshotReply.self, from: frame) else { continue }
                return reply.result.snapshot
            }
        }
        throw Ending.unreachable
    }
}

/// herdr's agents as the service keeps them, with the time each one's status began when the service saw it change.
struct HerdrModel: Sendable {
    struct Agent: Equatable, Sendable {
        /// The terminal's id: it stays when the pane moves, as the pane's id does not.
        var id: String
        var status: String
        var agent: String?
        var displayAgent: String?
        var name: String?
        var title: String?
        var terminalTitle: String?
        var workspace: String?
        /// herdr's order of status changes.
        var seq: Int?
        /// Seconds since 1970 when this status began; nil when it began before the service connected.
        var changed: Double?

        var lua: LuaValue {
            var table: [String: LuaValue] = ["id": .string(id), "status": .string(status)]
            table["agent"] = agent.map(LuaValue.string)
            table["display_agent"] = displayAgent.map(LuaValue.string)
            table["name"] = name.map(LuaValue.string)
            table["title"] = title.map(LuaValue.string)
            table["terminal_title_stripped"] = terminalTitle.map(LuaValue.string)
            table["workspace"] = workspace.map(LuaValue.string)
            table["state_change_seq"] = seq.map(LuaValue.int)
            table["changed"] = changed.map(LuaValue.double)
            return .table(table)
        }
    }

    struct Agents: Equatable, Sendable {
        var list: [Agent] = []
        /// When the snapshot was taken, in seconds since 1970.
        var fetched: Double = 0

        /// Equal when widgets would show the same: the time of the snapshot does not count.
        static func == (a: Agents, b: Agents) -> Bool { a.list == b.list }

        var lua: LuaValue { .table(["agents": .array(list.map(\.lua)), "fetched": .double(fetched)]) }
    }

    private(set) var agents = Agents()

    /// Takes a snapshot seen at `time`. `initial`: the first after connecting, whose changes came at times not known.
    /// True when an agent changed.
    mutating func apply(_ snapshot: HerdrSnapshot, at time: Double, initial: Bool) -> Bool {
        var labels: [String: String] = [:]
        for workspace in snapshot.workspaces ?? [] { labels[workspace.workspaceId] = workspace.label }
        let before = Dictionary(agents.list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let list = (snapshot.agents ?? []).compactMap { a -> Agent? in
            guard let id = a.terminalId ?? a.paneId else { return nil }
            let status = a.agentStatus ?? "unknown"
            let previous = before[id]
            let changed = previous?.status == status ? previous?.changed : initial ? nil : time
            return Agent(id: id, status: status, agent: a.agent, displayAgent: a.displayAgent, name: a.name, title: a.title,
                         terminalTitle: a.terminalTitleStripped, workspace: a.workspaceId.flatMap { labels[$0] },
                         seq: a.stateChangeSeq, changed: changed)
        }
        let next = Agents(list: list, fetched: time)
        defer { agents = next }
        return next != agents || initial
    }
}

/// The part of herdr's `session.snapshot` the service reads.
struct HerdrSnapshot: Decodable, Sendable {
    struct Workspace: Decodable, Sendable {
        var workspaceId: String
        var label: String?
    }

    struct Pane: Decodable, Sendable {
        var paneId: String
    }

    struct Agent: Decodable, Sendable {
        var terminalId: String?
        var paneId: String?
        var workspaceId: String?
        var agentStatus: String?
        var agent: String?
        var displayAgent: String?
        var name: String?
        var title: String?
        var terminalTitleStripped: String?
        var stateChangeSeq: Int?
    }

    var workspaces: [Workspace]?
    var panes: [Pane]?
    var agents: [Agent]?

    var paneIDs: Set<String> { Set((panes ?? []).map(\.paneId)) }
}

/// herdr's socket: newline-delimited JSON over a Unix socket.
enum HerdrSocket {
    /// ~/.config/herdr/herdr.sock, the default session's.
    static func standardPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/herdr/herdr.sock").path
    }

    /// The standard socket when it is there; else, on the first try, herdr's own answer: a session elsewhere.
    @Sendable static func find(first: Bool) -> String? {
        let standard = standardPath()
        if FileManager.default.fileExists(atPath: standard) { return standard }
        return first ? sessionPath() : nil
    }

    /// Where Homebrew and herdr's installer put the program. A GUI app's PATH has none of them.
    static let programs = ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr",
                           FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/herdr").path]

    /// The default running session's socket, from `herdr session list --json`; nil without herdr, or when it does not
    /// answer within 3 seconds: a hung herdr must not hold the thread that watches it.
    static func sessionPath() -> String? {
        guard let program = programs.first(where: FileManager.default.isExecutableFile(atPath:)),
              let data = ProgramOutput.read(program, ["session", "list", "--json"], timeout: 3) else { return nil }
        return sessionPath(in: data)
    }

    /// The socket of the default session if it runs, else of the first running one.
    static func sessionPath(in json: Data) -> String? {
        struct List: Decodable {
            struct Session: Decodable {
                var `default`: Bool?
                var running: Bool?
                var socketPath: String?
            }
            var sessions: [Session]
        }
        guard let list = try? decode(List.self, from: json) else { return nil }
        let running = list.sessions.filter { $0.running == true }
        return (running.first { $0.default == true } ?? running.first)?.socketPath
    }

    /// A connected socket, or nil when nothing listens at `path`.
    static func connect(_ path: String) -> Int32? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    /// Writes `line` and its newline.
    static func send(_ line: String, to fd: Int32) throws {
        let bytes = Array((line + "\n").utf8)
        var sent = 0
        while sent < bytes.count {
            let count = bytes[sent...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            guard count > 0 else { throw POSIXError(.EPIPE) }
            sent += count
        }
    }

    /// Status changes come only per pane; the rest says when the panes changed. pane.updated is left out: it fires each
    /// time a title's spinner turns.
    static func subscription(panes: Set<String>) -> String {
        let kinds = ["pane.created", "pane.closed", "pane.exited", "pane.moved", "pane.agent_detected", "workspace.renamed", "workspace.closed"]
        let list: [[String: String]] = panes.sorted().map { ["type": "pane.agent_status_changed", "pane_id": $0] } + kinds.map { ["type": $0] }
        let request: [String: Any] = ["id": "locky-events", "method": "events.subscribe", "params": ["subscriptions": list]]
        let data = (try? JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Splits the bytes herdr sends into frames at each newline byte (0x0A). Foundation's line APIs also split at U+2028,
    /// which herdr leaves unescaped inside strings, so they are not used.
    struct Framer {
        /// A frame larger than this ends the connection.
        static let limit = 16 << 20
        private var buffer: [UInt8] = []

        struct TooLarge: Error {}

        mutating func append(_ bytes: some Collection<UInt8>) throws(TooLarge) -> [Data] {
            let searched = buffer.count
            buffer.append(contentsOf: bytes)
            var frames: [Data] = []
            var start = 0
            var index = searched
            while let newline = buffer[index...].firstIndex(of: 0x0A) {
                if newline - start > Self.limit { throw TooLarge() }
                if newline > start { frames.append(Data(buffer[start..<newline])) }
                start = newline + 1
                index = start
            }
            buffer.removeFirst(start)
            if buffer.count > Self.limit { throw TooLarge() }
            return frames
        }
    }

    /// Any message: a reply (result or error) or an event.
    struct Envelope: Decodable {
        struct Failure: Decodable {
            var code: String?
        }

        struct Reply: Decodable {
            var type: String?
        }

        var id: String?
        var event: String?
        var error: Failure?
        var result: Reply?
    }

    struct SnapshotReply: Decodable {
        struct Result: Decodable {
            var snapshot: HerdrSnapshot
        }

        var result: Result
    }

    /// herdr's keys are snake_case.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}
