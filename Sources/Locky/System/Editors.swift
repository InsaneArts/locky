import AppKit
import UniformTypeIdentifiers

/// An editor that can open init.lua: a Mac app, or a command that runs in a terminal. `id` is what settings.json's
/// "editor" stores: the app's bundle id, the command's name, or "default" for the app macOS opens .lua files with.
struct Editor: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case app(bundleID: String, url: URL)
        case command(executable: URL)
    }

    var id: String
    var name: String
    var kind: Kind

    /// The app's icon; nil for a command.
    var icon: NSImage? {
        guard case .app(_, let url) = kind else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// A terminal app that runs command editors. `id`, the app's bundle id, is what settings.json's "terminal" stores.
struct Terminal: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var url: URL

    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// Finds the editors and terminals on this Mac, and opens a file in one: at a line where the editor documents a
/// way to take one, and without a line otherwise.
enum Editors {
    /// What opening a file takes. `launch` builds it, and tests check it; `open` carries it out.
    enum Launch: Equatable {
        /// Runs a program with these arguments, without a shell.
        case run(URL, [String])
        /// Opens files with an app.
        case open([URL], app: URL)
        /// Opens a URL with the app that handles its scheme.
        case url(URL)
        /// Starts a new instance of an app with these arguments, as `open -na App --args ...` does.
        case newInstance(app: URL, arguments: [String])
    }

    /// The GUI editors Locky knows, by bundle id, in the order `installed` returns them.
    static let apps = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.exafunction.windsurf",  // Windsurf, now Devin Desktop
        "dev.zed.Zed", "dev.zed.Zed-Preview", "com.sublimetext.4", "com.panic.Nova", "com.barebones.bbedit",
        "com.coteditor.CotEditor", "com.macromates.TextMate", "com.apple.dt.Xcode", "org.vim.MacVim",
        "com.neovide.neovide", "org.gnu.Emacs", "com.apple.TextEdit",
    ]

    /// The editors that run in a terminal: the command, and the name to show.
    static let commands = [("nvim", "Neovim"), ("vim", "Vim"), ("hx", "Helix"), ("micro", "micro"), ("nano", "nano"), ("emacs", "Emacs")]

    /// The terminals Locky can run a command editor in, by bundle id. Each documents a way that needs no Automation
    /// permission; see `terminalLaunch`.
    static let terminals = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
        "com.github.wez.wezterm", "org.alacritty", "dev.warp.Warp-Stable",
    ]

    /// The PATH to search when the login shell gives none: launchd's, with Homebrew's folders.
    static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// The user's login shell.
    static var shell: String { ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh" }

    // MARK: Detection

    /// The editors and terminals on this Mac: the default app for .lua files, the known apps, then the command
    /// editors on the login shell's PATH. Works on a background queue: the login shell can take up to 3 s.
    static func installed() async -> (editors: [Editor], terminals: [Terminal]) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let lookup = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                let lua = UTType(filenameExtension: "lua").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
                let editors = installedApps(lookup: lookup, defaultApp: lua)
                    + installedCommands(path: loginPath(shell: shell) ?? fallbackPath)
                continuation.resume(returning: (editors, installedTerminals(lookup: lookup)))
            }
        }
    }

    /// The app that opens .lua files (as "default"), then the known apps that `lookup` finds.
    static func installedApps(lookup: (String) -> URL?, defaultApp: URL?) -> [Editor] {
        var editors: [Editor] = []
        if let defaultApp, let bundleID = Bundle(url: defaultApp)?.bundleIdentifier {
            editors.append(Editor(id: "default", name: "Default (\(name(defaultApp)))", kind: .app(bundleID: bundleID, url: defaultApp)))
        }
        for bundleID in apps {
            guard let url = lookup(bundleID) else { continue }
            editors.append(Editor(id: bundleID, name: name(url), kind: .app(bundleID: bundleID, url: url)))
        }
        return editors
    }

    /// The command editors on `path`: for each, the first folder that has it, as the shell would pick.
    static func installedCommands(path: String, isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> [Editor] {
        let folders = path.split(separator: ":").filter { $0.hasPrefix("/") }
        return commands.compactMap { command, name in
            guard let found = folders.lazy.map({ "\($0)/\(command)" }).first(where: isExecutable) else { return nil }
            return Editor(id: command, name: name, kind: .command(executable: URL(fileURLWithPath: found)))
        }
    }

    static func installedTerminals(lookup: (String) -> URL?) -> [Terminal] {
        terminals.compactMap { bundleID in lookup(bundleID).map { Terminal(id: bundleID, name: name($0), url: $0) } }
    }

    /// An app's name as its bundle is named: "Devin" for a Windsurf that has been renamed, "Xcode-beta" for a beta.
    private static func name(_ app: URL) -> String {
        app.deletingPathExtension().lastPathComponent
    }

    /// The PATH of the user's login shell. An app opened from Finder gets launchd's short PATH, without Homebrew
    /// or what the shell profile adds. The shell runs /usr/bin/env, so its own syntax plays no part: zsh, bash,
    /// and fish work alike. nil when the shell fails or takes longer than `timeout` seconds.
    static func loginPath(shell: String, timeout: Double = 3) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "/usr/bin/env"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        nonisolated(unsafe) var data = Data()
        let read = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            read.signal()
        }
        // A profile that waits for input or the network is stopped. A program it left running may hold the
        // pipe open after the shell ends; the read gives up on that too.
        guard read.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return lines.last { $0.hasPrefix("PATH=") }.map { String($0.dropFirst(5)) }
    }

    // MARK: Opening

    /// Opens `file` in `editor`. A command editor runs in `terminal`, or in Terminal when it is nil. A failure the
    /// app reports later, after this returns, goes to the log.
    static func open(_ file: URL, line: Int?, editor: Editor, terminal: Terminal?) throws {
        let terminal = terminal ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
            .map { Terminal(id: "com.apple.Terminal", name: "Terminal", url: $0) }
        let failed: @Sendable (String) -> Void = { reason in
            LogFile.shared.write(level: "error", message: "\(editor.name) did not open \(file.lastPathComponent): \(reason)", source: "editor")
        }
        switch try launch(file, line: line, editor: editor, terminal: terminal) {
        case .run(let program, let arguments):
            let process = Process()
            process.executableURL = program
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { if $0.terminationStatus != 0 { failed("\(program.lastPathComponent) exited with \($0.terminationStatus)") } }
            try process.run()
        case .open(let files, let app):
            NSWorkspace.shared.open(files, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { failed(error.localizedDescription) }
            }
        case .url(let url):
            guard NSWorkspace.shared.open(url) else { throw EditorError("No app opens \(url.scheme ?? "") links") }
        case .newInstance(let app, let arguments):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.arguments = arguments
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
                if let error { failed(error.localizedDescription) }
            }
        }
    }

    /// What `open` does. For a command editor it writes the script that runs it (see `script`).
    static func launch(_ file: URL, line: Int?, editor: Editor, terminal: Terminal?) throws -> Launch {
        let line = line.flatMap { $0 > 0 ? $0 : nil }
        switch editor.kind {
        case .app(let bundleID, let app):
            return line.flatMap { lineLaunch(bundleID: bundleID, app: app, file: file, line: $0) } ?? .open([file], app: app)
        case .command(let executable):
            guard let terminal else { throw EditorError("Choose a terminal for \(editor.name)") }
            let command = [executable.path] + arguments(command: executable.lastPathComponent, file: file.path, line: line)
            let script = FileManager.default.temporaryDirectory.appending(path: "locky-\(UUID().uuidString).command")
            let launch = try terminalLaunch(script: script, terminal: terminal)
            let text = Data(self.script(command, directory: file.deletingLastPathComponent()).utf8)
            guard FileManager.default.createFile(atPath: script.path, contents: text, attributes: [.posixPermissions: 0o700]) else {
                throw EditorError("Could not write \(script.path)")
            }
            return launch
        }
    }

    /// How a GUI editor opens a file at a line, as its documentation gives it: the command-line tool in its bundle,
    /// its URL scheme, or arguments to a new instance. nil when it has no documented way, or the tool is missing.
    static func lineLaunch(bundleID: String, app: URL, file: URL, line: Int) -> Launch? {
        let path = file.path
        func tool(_ paths: String..., arguments: [String]) -> Launch? {
            let tools = paths.map { app.appending(path: $0) }
            return tools.first { FileManager.default.isExecutableFile(atPath: $0.path) }.map { .run($0, arguments) }
        }
        // Nova and BBEdit document their URLs without saying how to encode the path. A path that needs no
        // encoding reads the same either way; any other opens without the line.
        func plainURL(_ string: String) -> Launch? {
            path.unicodeScalars.allSatisfy(unreserved.contains) ? URL(string: string).map(Launch.url) : nil
        }
        switch bundleID {
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders":
            // The vscode:// URL asks the user first, so the CLI. Insiders names its CLI code too.
            return tool("Contents/Resources/app/bin/code", arguments: ["--goto", "\(path):\(line)"])
        case "com.todesktop.230313mzl4w4u92":
            return tool("Contents/Resources/app/bin/cursor", arguments: ["--goto", "\(path):\(line)"])
        case "com.exafunction.windsurf":
            // Windsurf 3 is Devin Desktop, with the same bundle id.
            return tool("Contents/Resources/app/bin/windsurf", "Contents/Resources/app/bin/devin-desktop", arguments: ["--goto", "\(path):\(line)"])
        case "dev.zed.Zed", "dev.zed.Zed-Preview":
            return tool("Contents/MacOS/cli", arguments: ["\(path):\(line)"])
        case "com.sublimetext.4":
            return tool("Contents/SharedSupport/bin/subl", arguments: ["\(path):\(line)"])
        case "com.macromates.TextMate":
            return tool("Contents/MacOS/mate", arguments: ["-l", "\(line)", path])
        case "com.apple.dt.Xcode":
            return tool("Contents/Developer/usr/bin/xed", arguments: ["-l", "\(line)", path])
        case "com.panic.Nova":
            return plainURL("nova://open?path=\(path)&line=\(line)")
        case "com.barebones.bbedit":
            return plainURL("x-bbedit://open?url=file://\(path)&line=\(line)")
        case "org.vim.MacVim":
            // MacVim's docs: the url is a file URL, its special characters encoded twice ("%2520" for a space).
            let url = file.absoluteString.addingPercentEncoding(withAllowedCharacters: unreserved.union(CharacterSet(charactersIn: ":")))!
            return URL(string: "mvim://open?url=\(url)&line=\(line)").map(Launch.url)
        case "com.neovide.neovide":
            // Arguments after "--" go to nvim. A new instance starts from launchd, so Neovide finds nvim through the
            // login shell; started as a child of Locky, it would search Locky's short PATH.
            return .newInstance(app: app, arguments: ["--", "+\(line)", path])
        default:
            return nil
        }
    }

    /// URL characters that no decoder changes: ASCII letters and digits, "-._~", and "/".
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")

    /// A command editor's arguments for `file` at `line`, as each documents them.
    static func arguments(command: String, file: String, line: Int?) -> [String] {
        let terminalOnly = command == "emacs" ? ["-nw"] : []
        guard let line else { return terminalOnly + [file] }
        switch command {
        case "nvim", "vim", "nano", "emacs": return terminalOnly + ["+\(line)", file]
        case "hx": return ["\(file):\(line)"]
        case "micro": return [file, "+\(line)"]
        default: return [file]
        }
    }

    /// How `terminal` runs the script, from each terminal's documentation. Terminal, iTerm2, WezTerm, and Warp open
    /// a .command file and run it in the user's shell. Ghostty, kitty, and Alacritty start a new instance that runs
    /// a program, so the script runs through the login shell there, for the PATH the editor was found on. The
    /// script's path, in the temporary folder, has no characters any shell treats specially.
    static func terminalLaunch(script: URL, terminal: Terminal) throws -> Launch {
        let login = [shell, "-l", "-c", script.path]
        switch terminal.id {
        case "com.apple.Terminal", "com.googlecode.iterm2", "com.github.wez.wezterm", "dev.warp.Warp-Stable":
            return .open([script], app: terminal.url)
        case "com.mitchellh.ghostty", "org.alacritty":
            return .newInstance(app: terminal.url, arguments: ["-e"] + login)
        case "net.kovidgoyal.kitty":
            // kitty stays running without windows by default; this instance quits when the editor does.
            return .newInstance(app: terminal.url, arguments: ["-o", "macos_quit_when_last_window_closed=yes"] + login)
        default:
            throw EditorError("Locky cannot run commands in \(terminal.name)")
        }
    }

    /// A /bin/sh script that deletes itself, moves to `directory`, and runs `command`.
    static func script(_ command: [String], directory: URL) -> String {
        """
        #!/bin/sh
        rm -f -- "$0"
        cd -- \(quoted(directory.path)) 2>/dev/null
        exec \(command.map(quoted).joined(separator: " "))

        """
    }

    /// `text` as one shell word in single quotes, where nothing is special: spaces, quotes, "$", and non-ASCII
    /// text stay as they are.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

struct EditorError: LocalizedError {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
