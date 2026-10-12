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
if let command = arguments.first, !command.hasPrefix("-") || CLI.commands.contains(command), !["preview", "lock"].contains(command) {
    exit(CLI.run(arguments))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
