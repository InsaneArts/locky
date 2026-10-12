import AppKit
import Foundation
import Testing
@testable import Locky

@Suite struct EditorsTests {
    let sandbox: Sandbox
    let file = URL(fileURLWithPath: "/Users/me/.config/locky/init.lua")

    init() throws {
        sandbox = try Sandbox()
    }

    /// A fake app bundle: an Info.plist with `bundleID`, and executable files at `tools`.
    private func makeApp(_ name: String, _ bundleID: String, tools: [String] = []) throws -> URL {
        let app = sandbox.root.appending(path: "\(name).app")
        try FileManager.default.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": bundleID, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appending(path: "Contents/Info.plist"))
        for tool in tools { try executable(app.appending(path: tool), "#!/bin/sh\n") }
        return app
    }

    private func executable(_ url: URL, _ text: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(FileManager.default.createFile(atPath: url.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o755]))
    }

    private func editor(_ name: String, _ bundleID: String, tools: [String] = []) throws -> (Editor, URL) {
        let app = try makeApp(name, bundleID, tools: tools)
        return (Editor(id: bundleID, name: name, kind: .app(bundleID: bundleID, url: app)), app)
    }

    // MARK: Detection

    @Test func findsKnownAppsWithTheDefaultFirst() throws {
        let code = try makeApp("Visual Studio Code", "com.microsoft.VSCode")
        let devin = try makeApp("Devin", "com.exafunction.windsurf")
        let neovide = try makeApp("Neovide", "com.neovide.neovide")
        let found = ["com.microsoft.VSCode": code, "com.exafunction.windsurf": devin, "com.neovide.neovide": neovide]
        let editors = Editors.installedApps(lookup: { found[$0] }, defaultApp: neovide)
        #expect(editors.map(\.id) == ["default", "com.microsoft.VSCode", "com.exafunction.windsurf", "com.neovide.neovide"])
        // Names come from the bundles, so a renamed app shows its new name.
        #expect(editors.map(\.name) == ["Default (Neovide)", "Visual Studio Code", "Devin", "Neovide"])
        #expect(editors[0].kind == .app(bundleID: "com.neovide.neovide", url: neovide))
        #expect(editors[0].icon != nil)
        #expect(Editors.installedApps(lookup: { _ in nil }, defaultApp: nil).isEmpty)
    }

    @Test func findsCommandEditorsOnThePathAsTheShellWould() {
        let present: Set = ["/b/nvim", "/c/nvim", "/c/hx", "/a/emacs", "relative/vim"]
        let editors = Editors.installedCommands(path: "/a:/b:relative:/c", isExecutable: present.contains)
        // The first folder wins, and a relative folder is never searched.
        #expect(editors.map(\.id) == ["nvim", "hx", "emacs"])
        #expect(editors.map(\.name) == ["Neovim", "Helix", "Emacs"])
        #expect(editors[0].kind == .command(executable: URL(fileURLWithPath: "/b/nvim")))
        #expect(editors[0].icon == nil)
    }

    @Test func findsTerminalsByBundleID() throws {
        let ghostty = try makeApp("Ghostty", "com.mitchellh.ghostty")
        let terminal = try makeApp("Terminal", "com.apple.Terminal")
        let found = ["com.mitchellh.ghostty": ghostty, "com.apple.Terminal": terminal]
        let terminals = Editors.installedTerminals(lookup: { found[$0] })
        #expect(terminals == [Terminal(id: "com.apple.Terminal", name: "Terminal", url: terminal),
                              Terminal(id: "com.mitchellh.ghostty", name: "Ghostty", url: ghostty)])
    }

    @Test func loginPathReadsPATHFromTheLoginShell() throws {
        let shell = sandbox.root.appending(path: "fake-shell")
        try executable(shell, """
            #!/bin/sh
            [ "$1 $2 $3" = "-l -c /usr/bin/env" ] || exit 1
            echo "A profile that talks"
            echo "HOME=/Users/me"
            echo "PATH=/opt/homebrew/bin:/usr/bin:/bin"
            """)
        #expect(Editors.loginPath(shell: shell.path) == "/opt/homebrew/bin:/usr/bin:/bin")
        #expect(Editors.loginPath(shell: sandbox.root.appending(path: "no-such-shell").path) == nil)
    }

    @Test func aSlowLoginShellIsStopped() throws {
        let shell = sandbox.root.appending(path: "slow-shell")
        try executable(shell, "#!/bin/sh\nexec sleep 30\n")
        let start = Date()
        #expect(Editors.loginPath(shell: shell.path, timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    /// The real thing: the login shell and LaunchServices. Terminal and TextEdit come with macOS.
    @Test func findsTheSystemsOwnEditorAndTerminal() async {
        let (editors, terminals) = await Editors.installed()
        #expect(editors.contains { $0.id == "com.apple.TextEdit" })
        #expect(terminals.contains { $0.id == "com.apple.Terminal" })
    }

    // MARK: GUI editors

    @Test func guiEditorsTakeTheLineThroughTheirTools() throws {
        // Arguments go to the tool as they are, with no shell, so an awkward path needs no escaping.
        let file = URL(fileURLWithPath: "/tmp/it's a \"$HOME\" `x` é 🙂/init.lua")
        let path = file.path
        let cases: [(String, String, String, [String])] = [
            ("Visual Studio Code", "com.microsoft.VSCode", "Contents/Resources/app/bin/code", ["--goto", "\(path):12"]),
            ("Visual Studio Code - Insiders", "com.microsoft.VSCodeInsiders", "Contents/Resources/app/bin/code", ["--goto", "\(path):12"]),
            ("Cursor", "com.todesktop.230313mzl4w4u92", "Contents/Resources/app/bin/cursor", ["--goto", "\(path):12"]),
            ("Windsurf", "com.exafunction.windsurf", "Contents/Resources/app/bin/windsurf", ["--goto", "\(path):12"]),
            ("Devin", "com.exafunction.windsurf", "Contents/Resources/app/bin/devin-desktop", ["--goto", "\(path):12"]),
            ("Zed", "dev.zed.Zed", "Contents/MacOS/cli", ["\(path):12"]),
            ("Zed Preview", "dev.zed.Zed-Preview", "Contents/MacOS/cli", ["\(path):12"]),
            ("Sublime Text", "com.sublimetext.4", "Contents/SharedSupport/bin/subl", ["\(path):12"]),
            ("TextMate", "com.macromates.TextMate", "Contents/MacOS/mate", ["-l", "12", path]),
            ("Xcode", "com.apple.dt.Xcode", "Contents/Developer/usr/bin/xed", ["-l", "12", path]),
        ]
        for (name, bundleID, tool, arguments) in cases {
            let (editor, app) = try editor(name, bundleID, tools: [tool])
            #expect(try Editors.launch(file, line: 12, editor: editor, terminal: nil) == .run(app.appending(path: tool), arguments), "\(name)")
            // Without a line, or without its tool, the app opens the file as Finder would.
            #expect(try Editors.launch(file, line: nil, editor: editor, terminal: nil) == .open([file], app: app))
            try FileManager.default.removeItem(at: app.appending(path: tool))
            #expect(try Editors.launch(file, line: 12, editor: editor, terminal: nil) == .open([file], app: app), "\(name)")
        }
    }

    @Test func guiEditorsTakeTheLineThroughTheirURLs() throws {
        let (nova, novaApp) = try editor("Nova", "com.panic.Nova")
        #expect(try Editors.launch(file, line: 12, editor: nova, terminal: nil) == .url(URL(string: "nova://open?path=\(file.path)&line=12")!))
        let (bbedit, bbeditApp) = try editor("BBEdit", "com.barebones.bbedit")
        #expect(try Editors.launch(file, line: 12, editor: bbedit, terminal: nil)
            == .url(URL(string: "x-bbedit://open?url=file://\(file.path)&line=12")!))
        // Their docs do not say how to encode a path, so one that needs encoding opens without the line.
        let awkward = URL(fileURLWithPath: "/tmp/my config/init.lua")
        #expect(try Editors.launch(awkward, line: 12, editor: nova, terminal: nil) == .open([awkward], app: novaApp))
        #expect(try Editors.launch(awkward, line: 12, editor: bbedit, terminal: nil) == .open([awkward], app: bbeditApp))

        // MacVim documents encoding twice; this is the example from its :help mvim://.
        let (macvim, _) = try editor("MacVim", "org.vim.MacVim")
        #expect(try Editors.launch(URL(fileURLWithPath: "/tmp/file name?.txt"), line: 20, editor: macvim, terminal: nil)
            == .url(URL(string: "mvim://open?url=file:///tmp/file%2520name%253F.txt&line=20")!))
        let odd = URL(fileURLWithPath: "/tmp/it's & $x é.lua")
        guard case .url(let url) = try Editors.launch(odd, line: 3, editor: macvim, terminal: nil),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let value = items.first(where: { $0.name == "url" })?.value
        else { Issue.record("no mvim URL"); return }
        // Decoded once, as MacVim does, the url value is the file's URL, and "&" did not split it.
        #expect(URL(string: value)?.path == odd.path)
        #expect(items.map(\.name) == ["url", "line"])
    }

    @Test func neovideGetsALineThroughANewInstance() throws {
        let (neovide, app) = try editor("Neovide", "com.neovide.neovide")
        #expect(try Editors.launch(file, line: 12, editor: neovide, terminal: nil) == .newInstance(app: app, arguments: ["--", "+12", file.path]))
        #expect(try Editors.launch(file, line: nil, editor: neovide, terminal: nil) == .open([file], app: app))
    }

    @Test func editorsWithoutADocumentedLineOpenTheFile() throws {
        for (name, bundleID) in [("TextEdit", "com.apple.TextEdit"), ("Emacs", "org.gnu.Emacs"), ("CotEditor", "com.coteditor.CotEditor")] {
            let (editor, app) = try editor(name, bundleID)
            #expect(try Editors.launch(file, line: 12, editor: editor, terminal: nil) == .open([file], app: app))
        }
        // Line 0 or below is no line.
        let (code, app) = try editor("Visual Studio Code", "com.microsoft.VSCode", tools: ["Contents/Resources/app/bin/code"])
        #expect(try Editors.launch(file, line: 0, editor: code, terminal: nil) == .open([file], app: app))
    }

    // MARK: Command editors

    @Test func commandEditorsGetTheLineTheirWay() {
        let path = "/a b/it's.lua"
        #expect(Editors.arguments(command: "nvim", file: path, line: 12) == ["+12", path])
        #expect(Editors.arguments(command: "vim", file: path, line: 12) == ["+12", path])
        #expect(Editors.arguments(command: "nano", file: path, line: 12) == ["+12", path])
        #expect(Editors.arguments(command: "emacs", file: path, line: 12) == ["-nw", "+12", path])
        #expect(Editors.arguments(command: "hx", file: path, line: 12) == ["\(path):12"])
        #expect(Editors.arguments(command: "micro", file: path, line: 12) == [path, "+12"])
        #expect(Editors.arguments(command: "nvim", file: path, line: nil) == [path])
        #expect(Editors.arguments(command: "emacs", file: path, line: nil) == ["-nw", path])
    }

    @Test func eachTerminalGetsTheScriptItsDocumentedWay() throws {
        let nvim = Editor(id: "nvim", name: "Neovim", kind: .command(executable: URL(fileURLWithPath: "/opt/homebrew/bin/nvim")))
        let login = [Editors.shell, "-l", "-c"]
        let cases: [(String, String, [String]?)] = [
            ("Terminal", "com.apple.Terminal", nil),
            ("iTerm", "com.googlecode.iterm2", nil),
            ("WezTerm", "com.github.wez.wezterm", nil),
            ("Warp", "dev.warp.Warp-Stable", nil),
            ("Ghostty", "com.mitchellh.ghostty", ["-e"] + login),
            ("Alacritty", "org.alacritty", ["-e"] + login),
            ("kitty", "net.kovidgoyal.kitty", ["-o", "macos_quit_when_last_window_closed=yes"] + login),
        ]
        for (name, bundleID, prefix) in cases {
            let app = try makeApp(name, bundleID)
            let launch = try Editors.launch(file, line: 12, editor: nvim, terminal: Terminal(id: bundleID, name: name, url: app))
            let script: URL
            switch launch {
            case .open(let files, app: let opener) where prefix == nil && opener == app && files.count == 1:
                script = files[0]
            case .newInstance(app: let opener, arguments: let arguments) where opener == app && Array(arguments.dropLast()) == prefix:
                script = URL(fileURLWithPath: arguments.last!)
            default:
                Issue.record("\(name): \(launch)")
                continue
            }
            #expect(script.deletingLastPathComponent().path == FileManager.default.temporaryDirectory.path)
            #expect(script.pathExtension == "command")
            let attributes = try FileManager.default.attributesOfItem(atPath: script.path)
            #expect(attributes[.posixPermissions] as? Int == 0o700)
            #expect(try String(contentsOf: script, encoding: .utf8) == Editors.script(["/opt/homebrew/bin/nvim", "+12", file.path],
                                                                                         directory: file.deletingLastPathComponent()))
            try FileManager.default.removeItem(at: script)
        }
        let unknown = Terminal(id: "com.example.term", name: "Term", url: sandbox.root)
        #expect(throws: EditorError.self) { try Editors.launch(file, line: 12, editor: nvim, terminal: unknown) }
        #expect(throws: EditorError.self) { try Editors.launch(file, line: 12, editor: nvim, terminal: nil) }
    }

    /// Runs the script as a terminal would, with an editor that records its arguments and working folder.
    @Test func theScriptKeepsAwkwardPathsIntact() throws {
        let folder = sandbox.root.appending(path: "it's a \"$HOME\" `x` \\ $(folder)\nnew line/日本 é 🙂")
        let file = folder.appending(path: "in it's $PATH.lua")
        let editor = folder.appending(path: "fake $editor's")
        let output = sandbox.root.appending(path: "output")
        try executable(editor, """
            #!/bin/sh
            printf '%s\\0' "$(pwd)" "$@" > "$LOCKY_TEST_OUTPUT"
            """)
        let script = sandbox.root.appending(path: "run.command")
        try executable(script, Editors.script([editor.path, "+12", file.path], directory: folder))

        let process = Process()
        process.executableURL = script
        process.environment = ["LOCKY_TEST_OUTPUT": output.path, "PATH": "/usr/bin:/bin"]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let recorded = try String(contentsOf: output, encoding: .utf8).split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        #expect(recorded == [folder.path, "+12", file.path, ""])
        // The script deletes itself.
        #expect(!FileManager.default.fileExists(atPath: script.path))
    }

    @Test func quotingMakesOneShellWord() {
        #expect(Editors.quoted("plain") == "'plain'")
        #expect(Editors.quoted("it's") == #"'it'\''s'"#)
        #expect(Editors.quoted("$HOME `x` \"q\"") == #"'$HOME `x` "q"'"#)
    }
}
