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

    /// A process to stand in for Locky, which the guard may kill.
    private func standIn() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        return process
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
        let run = try Run(parent: locky.processIdentifier, timeout: 1)
        defer { close(run.input) }
        #expect(await eventually { run.lines == ["lock: Locky hung"] })
        // The guard killed the frozen Locky.
        locky.waitUntilExit()
        #expect(locky.terminationReason == .uncaughtSignal && locky.terminationStatus == SIGKILL)
        #expect(run.exitStatus() == 0)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: binary)))
    func heartbeatsKeepALockOn() async throws {
        let locky = try standIn()
        defer { locky.terminate() }
        let run = try Run(parent: locky.processIdentifier, timeout: 1)
        for _ in 0..<6 {
            run.send(Guard.heartbeat)
            try await Task.sleep(for: .milliseconds(300))
        }
        #expect(run.lines.isEmpty)
        #expect(locky.isRunning)
        run.send(Guard.unlocked)
        close(run.input)
        #expect(run.exitStatus() == 0)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: binary)))
    func lockyExitingLocks() async throws {
        let locky = try standIn()
        let run = try Run(parent: locky.processIdentifier)
        defer { close(run.input) }
        run.send(Guard.heartbeat)
        locky.terminate()
        #expect(await eventually { run.lines == ["lock: Locky exited"] })
        #expect(run.exitStatus() == 0)
    }
}
#endif
