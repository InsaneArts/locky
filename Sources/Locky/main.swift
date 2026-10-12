import AppKit

// Writing to a program that already exited (a widget's stdin, for one) raises SIGPIPE, which would end the
// app and with it the lock. Ignored, the write fails with EPIPE instead and the error is handled.
signal(SIGPIPE, SIG_IGN)

// `run` programs inherit this environment. A Locky started from a herdr pane drops herdr's variables first.
for key in ProcessInfo.processInfo.environment.keys where key.hasPrefix("HERDR_") { unsetenv(key) }

// `locky check`, `locky health`, ...: the command line, without the menu bar app. Any other word is a
// mistyped command and gets the usage, not a second menu bar app. Arguments starting with "-" come from
// macOS or Xcode (such as -NSDocumentRevisionsDebugMode) and start the app.
let arguments = Array(CommandLine.arguments.dropFirst())
if let command = arguments.first, !command.hasPrefix("-") || CLI.commands.contains(command), !["preview", "lock", "window"].contains(command) {
    exit(CLI.run(arguments))
}

// One Locky per user: a second launch (`Locky window settings`, the binary run again) hands its request to the
// one running and quits, instead of a second menu bar icon, auto-lock, and shortcut. A screenshot run
// (--behind) is a tool and runs on its own.
if !arguments.contains("--behind"), let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != getpid() }) {
    DistributedNotificationCenter.default().postNotificationName(AppDelegate.request, object: nil, userInfo: ["arguments": arguments],
                                                                 deliverImmediately: true)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
