import Darwin

/// The guard: a second process that locks the Mac with the macOS lock screen if Locky crashes, hangs, or is
/// killed during a lock. Locky writes a heartbeat byte to its stdin each second from the main run loop, and the
/// unlocked byte when the lock ends with the user let in or handed over to the macOS lock.
public enum Guard {
    public static let heartbeat: UInt8 = 0x68  // "h"
    public static let unlocked: UInt8 = 0x75  // "u"
    /// Seconds without a heartbeat that count as a hang.
    public static let timeout = 8.0

    public enum Verdict: Equatable, Sendable {
        /// Locky said the lock ended: nothing to do.
        case release
        /// Locky is gone without saying so: lock the Mac.
        case lock(String)
        /// Locky stopped answering: lock the Mac, then kill Locky, so its frozen shield does not stay over the
        /// desktop after the user unlocks macOS.
        case hung
    }

    /// What the guard heard so far.
    public struct State: Sendable {
        public let timeout: Double
        private var last: Double

        public init(timeout: Double = Guard.timeout, now: Double) {
            self.timeout = timeout
            last = now
        }

        /// Bytes from Locky: .release once the unlocked byte arrives, else nil.
        public mutating func received(_ bytes: some Sequence<UInt8>, now: Double) -> Verdict? {
            if bytes.contains(Guard.unlocked) { return .release }
            last = now
            return nil
        }

        /// .hung once `timeout` seconds passed without a heartbeat.
        public func check(now: Double) -> Verdict? { now - last >= timeout ? .hung : nil }

        /// When the next check is due.
        public var deadline: Double { last + timeout }
    }

    /// Seconds the Mac has been awake: a sleep stops both processes, and must not count as a hang.
    public static func uptime() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9
    }

    /// Watches `input` (the pipe from Locky) and `parent` (Locky's pid) until one of them decides.
    public static func watch(input: Int32, parent: pid_t, timeout: Double = Guard.timeout) -> Verdict {
        let queue = kqueue()
        guard queue >= 0 else { return .lock("kqueue failed") }
        defer { close(queue) }
        var changes = [
            kevent(ident: UInt(input), filter: Int16(EVFILT_READ), flags: UInt16(EV_ADD), fflags: 0, data: 0, udata: nil),
            kevent(ident: UInt(parent), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD), fflags: NOTE_EXIT, data: 0, udata: nil),
        ]
        var state = State(timeout: timeout, now: uptime())
        // Each change on its own: one that fails (Locky already exited) does not keep the other out.
        for index in changes.indices where kevent(queue, &changes[index], 1, nil, 0, nil) < 0 {
            if changes[index].filter == Int16(EVFILT_PROC) { return drain(input, &state) ?? .lock("Locky exited") }
            return .lock("cannot watch the pipe")
        }
        var buffer = [UInt8](repeating: 0, count: 64)
        while true {
            let wait = max(0, state.deadline - uptime())
            var spec = timespec(tv_sec: Int(wait), tv_nsec: Int((wait - wait.rounded(.down)) * 1e9))
            var event = kevent()
            let count = kevent(queue, nil, 0, &event, 1, &spec)
            if count < 0, errno == EINTR { continue }
            if count < 0 { return .lock("kevent failed") }
            if count > 0, event.filter == Int16(EVFILT_PROC) {
                // What Locky wrote before it exited is still in the pipe.
                return drain(input, &state) ?? .lock("Locky exited")
            }
            if count > 0 {
                let read = Darwin.read(input, &buffer, buffer.count)
                if read == 0 { return .lock("the pipe from Locky closed") }
                if read < 0, errno != EINTR, errno != EAGAIN { return .lock("the pipe from Locky failed") }
                if read > 0, let verdict = state.received(buffer[..<read], now: uptime()) { return verdict }
            }
            if let verdict = state.check(now: uptime()) { return verdict }
        }
    }

    /// Reads what is left in the pipe without waiting: .release if it holds the unlocked byte.
    private static func drain(_ input: Int32, _ state: inout State) -> Verdict? {
        _ = fcntl(input, F_SETFL, fcntl(input, F_GETFL) | O_NONBLOCK)
        var buffer = [UInt8](repeating: 0, count: 64)
        while true {
            let read = Darwin.read(input, &buffer, buffer.count)
            guard read > 0 else { return nil }
            if let verdict = state.received(buffer[..<read], now: uptime()) { return verdict }
        }
    }

    /// Starts the guard at `executable` for `parent`, in a session of its own, so a signal to Locky's process
    /// group does not reach it. Returns its pid and the pipe's write end, which no other child inherits.
    public static func spawn(executable: String, parent: pid_t, arguments: [String] = []) -> (pid: pid_t, input: Int32)? {
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else { return nil }
        _ = fcntl(ends[0], F_SETFD, FD_CLOEXEC)
        _ = fcntl(ends[1], F_SETFD, FD_CLOEXEC)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
            close(ends[0])
        }
        // The read end on stdin; stdout and stderr shared; every other descriptor closed.
        posix_spawn_file_actions_adddup2(&actions, ends[0], 0)
        posix_spawn_file_actions_addinherit_np(&actions, 1)
        posix_spawn_file_actions_addinherit_np(&actions, 2)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        let argv = ([executable, String(parent)] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        guard posix_spawn(&pid, executable, &actions, &attributes, argv, environ) == 0 else {
            close(ends[1])
            return nil
        }
        return (pid, ends[1])
    }
}
