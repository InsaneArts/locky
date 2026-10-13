import Foundation
import GuardCore
import Testing

/// The guard, which locks the Mac with the macOS lock screen when Locky dies or hangs during a lock. No test
/// locks the Mac: the debug guard writes a line to LOCKY_SYSTEM_LOCK_FILE instead, and nothing here calls
/// SystemLock.engage.
@Suite struct GuardTests {
    @Test func theSystemLockResolves() {
        // Resolved only, never called: calling it locks the Mac.
        #expect(SystemLock.resolve() != nil)
    }

    @Test func heartbeatsKeepItWaiting() {
        var state = Guard.State(timeout: 8, now: 100)
        #expect(state.check(now: 107) == nil)
        #expect(state.received([Guard.heartbeat], now: 107) == nil)
        #expect(state.check(now: 114) == nil)
        #expect(state.deadline == 115)
        #expect(state.check(now: 115) == .hung)
    }

    @Test func theUnlockedByteReleases() {
        var state = Guard.State(timeout: 8, now: 0)
        #expect(state.received([Guard.heartbeat, Guard.unlocked], now: 1) == .release)
    }

}

#if DEBUG
/// The built guard beside the test bundle, run with its test seam. Debug builds only: a release guard ignores the
/// seam and would lock the Mac. One at a time, since each sets the seam's variable for the guard it starts.
@Suite(.serialized) struct GuardProcessTests {
    private static let binary = Bundle(for: Sandbox.self).bundleURL.deletingLastPathComponent().appending(path: "locky-guard").path

    /// A guard for `parent`, with its lock file, and a hang timeout of `timeout` seconds.
    private struct Run {
        let pid: pid_t
        let input: Int32
        let file: URL

        init(parent: pid_t, timeout: Double = 30) throws {
            file = FileManager.default.temporaryDirectory.appending(path: "locky-guard-\(UUID().uuidString)")
            setenv("LOCKY_SYSTEM_LOCK_FILE", file.path, 1)
            let started = try #require(Guard.spawn(executable: GuardProcessTests.binary, parent: parent, arguments: [String(timeout)]))
            pid = started.pid
            input = started.input
        }

        func send(_ byte: UInt8) {
            var byte = byte
            _ = write(input, &byte, 1)
        }

        /// Waits for the guard to exit; its status.
        func exitStatus() -> Int32 {
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            try? FileManager.default.removeItem(at: file)
            return status
        }

        var lines: [String] { ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
    }

    /// A process to stand in for Locky, which the guard may kill: its pid. posix_spawn and waitpid, not Process,
    /// whose waitUntilExit can miss the exit.
    private func standIn() throws -> pid_t {
        var pid: pid_t = 0
        let argv = (["/bin/sleep", "30"] as [String]).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let spawned = posix_spawn(&pid, "/bin/sleep", nil, nil, argv, environ)
        try #require(spawned == 0)
        return pid
    }

    /// Waits for `pid` to exit; its status.
    private func status(_ pid: pid_t) -> Int32 {
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return status
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: binary)))
    func aPipeClosedWithoutUnlockingLocks() async throws {
        let run = try Run(parent: getpid())
        run.send(Guard.heartbeat)
        close(run.input)
        #expect(await eventually { run.lines == ["lock: the pipe from Locky closed"] })
        #expect(run.exitStatus() == 0)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: binary)))
    func unlockingReleases() async throws {
        let run = try Run(parent: getpid())
        run.send(Guard.heartbeat)
        run.send(Guard.unlocked)
        close(run.input)
        #expect(run.exitStatus() == 0)
        #expect(run.lines.isEmpty)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: binary)))
    func aHangLocksAndEndsLocky() async throws {
        let locky = try standIn()
        let run = try Run(parent: locky, timeout: 1)
        defer { close(run.input) }
        #expect(await eventually { run.lines == ["lock: Locky hung"] })
        // The guard killed the frozen Locky.
        #expect(status(locky) & 0x7f == SIGKILL)
        #expect(run.exitStatus() == 0)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: binary)))
    func heartbeatsKeepALockOn() async throws {
        let locky = try standIn()
        defer { kill(locky, SIGKILL); _ = status(locky) }
        // Longer than the timeout, with room for a slow test run.
        let run = try Run(parent: locky, timeout: 3)
        for _ in 0..<20 {
            run.send(Guard.heartbeat)
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(run.lines.isEmpty)
        #expect(waitpid(locky, nil, WNOHANG) == 0)
        run.send(Guard.unlocked)
        close(run.input)
        #expect(run.exitStatus() == 0)
    }

    /// Locky's stderr may be a pipe nobody reads any more (a closed terminal): the guard's note there must not end
    /// it before it locks.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: binary)))
    func aClosedStderrStillLocks() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "locky-guard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        setenv("LOCKY_SYSTEM_LOCK_FILE", file.path, 1)
        var input: [Int32] = [0, 0], output: [Int32] = [0, 0]
        try #require(pipe(&input) == 0 && pipe(&output) == 0)
        close(output[0])
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, input[0], 0)
        posix_spawn_file_actions_adddup2(&actions, output[1], 2)
        posix_spawn_file_actions_addclose(&actions, input[1])
        let argv = ([Self.binary, String(getpid())] as [String]).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        try #require(posix_spawn(&pid, Self.binary, &actions, nil, argv, environ) == 0)
        close(input[0])
        close(output[1])
        close(input[1])
        #expect(status(pid) == 0)
        #expect((try? String(contentsOf: file, encoding: .utf8)) == "lock: the pipe from Locky closed\n")
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: binary)))
    func lockyExitingLocks() async throws {
        let locky = try standIn()
        let run = try Run(parent: locky)
        defer { close(run.input) }
        run.send(Guard.heartbeat)
        kill(locky, SIGKILL)
        _ = status(locky)
        #expect(await eventually { run.lines == ["lock: Locky exited"] })
        #expect(run.exitStatus() == 0)
    }
}
#endif
