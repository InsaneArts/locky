import Foundation
import GuardCore

/// Locky's side of the guard (see Guard): starts locky-guard with a lock, writes it a heartbeat each second from
/// the main run loop, and tells it when the lock ends. If the guard goes away during the lock, `onLost` says so.
@MainActor
final class LockGuard {
    private var input: Int32
    private var heartbeat: Timer?
    private var released = false
    private let onLost: (String) -> Void

    /// locky-guard, beside Locky's executable (in the app bundle and in the SwiftPM build alike).
    static var executable: String? {
        Bundle.main.executableURL.map { $0.deletingLastPathComponent().appending(path: "locky-guard").path }
    }

    /// The guard for this lock; nil when it cannot start.
    init?(onLost: @escaping (String) -> Void) {
        guard let executable = Self.executable, let started = Guard.spawn(executable: executable, parent: getpid()) else { return nil }
        let pid = started.pid
        input = started.input
        self.onLost = onLost
        // A guard that stops reading must not block the main thread.
        _ = fcntl(input, F_SETFL, fcntl(input, F_GETFL) | O_NONBLOCK)
        // The source keeps itself until the guard exits, so the guard is reaped after a release too.
        let exit = DispatchSource.makeProcessSource(identifier: started.pid, eventMask: .exit, queue: .main)
        exit.setEventHandler { [weak self, pid] in
            waitpid(pid, nil, WNOHANG)
            exit.cancel()
            MainActor.assumeIsolated { self?.lost("the guard exited") }
        }
        exit.resume()
        // The main run loop in every mode: when the main thread hangs, the heartbeat stops with it.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.send(Guard.heartbeat) } }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    /// The lock ended with the user let in, or handed over to the macOS lock: the guard exits.
    func release() {
        guard !released else { return }
        send(Guard.unlocked)
        released = true
        stop()
    }

    private func send(_ byte: UInt8) {
        guard input >= 0 else { return }
        var byte = byte
        // EPIPE (SIGPIPE is ignored): the guard is gone. EAGAIN: the pipe is full, which a running guard never lets happen.
        if write(input, &byte, 1) < 0, errno == EPIPE { lost("the guard stopped reading") }
    }

    private func lost(_ reason: String) {
        guard !released else { return }
        released = true
        stop()
        onLost(reason)
    }

    private func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
        if input >= 0 { close(input) }
        input = -1
    }
}
