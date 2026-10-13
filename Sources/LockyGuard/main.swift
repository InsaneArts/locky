import Darwin
import GuardCore

// locky-guard PID [SECONDS]: Locky starts it with each lock (see Guard). SECONDS replaces the hang timeout, for
// tests. It has its own name, so `killall Locky` does not end it with Locky.
let arguments = CommandLine.arguments
guard arguments.count >= 2, let parent = pid_t(arguments[1]), parent > 0 else {
    fputs("usage: locky-guard PID [SECONDS]\n", stderr)
    exit(2)
}
let timeout = arguments.count > 2 ? Double(arguments[2]) ?? Guard.timeout : Guard.timeout

// Signals for a terminal or a session do not concern it: only the pipe and Locky's exit do. SIGPIPE too: a
// stderr nobody reads any more must not end it before it locks.
signal(SIGHUP, SIG_IGN)
signal(SIGINT, SIG_IGN)
signal(SIGPIPE, SIG_IGN)

switch Guard.watch(input: 0, parent: parent, timeout: timeout) {
case .release:
    exit(0)
case .lock(let reason):
    fputs("locky-guard: \(reason); locking the Mac\n", stderr)
    exit(SystemLock.engage(reason: reason) ? 0 : 1)
case .hung:
    fputs("locky-guard: no heartbeat for \(timeout) s; locking the Mac and ending Locky\n", stderr)
    // Without the macOS lock, the frozen shield is all that covers the desktop: keep it.
    guard SystemLock.engage(reason: "Locky hung") else { exit(1) }
    kill(parent, SIGKILL)
    exit(0)
}
