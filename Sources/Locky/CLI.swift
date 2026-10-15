import AppKit
import CLua
import Foundation
import LocalAuthentication
import Metal

/// `Locky <command>`: the command line, in the same binary as the app.
///
///   locky check [--theme NAME] [--widget NAME]   run init.lua, plugins, and a theme; report every error
///   locky health                   check Locky, Lua, plugins, Touch ID, and git, like :checkhealth
///   locky themes | widgets         list what is installed
///   locky render --theme NAME [--widget NAME] --out FILE.png [--size 1440x900] [--appearance light|dark]
///   locky skill install|path       the skill that teaches coding agents to write widgets and themes
///   locky pack list|check|sync|update|clean
///   locky login [on|off]
///   locky preview [--theme NAME] [--size 1440x900] [--behind]
///   locky lock [--theme NAME]
///   locky window [section] [--theme NAME] [--behind]   (the old sections dashboard and widgets still work)
enum CLI {
    static let commands: Set<String> = ["check", "health", "themes", "widgets", "render", "skill", "pack", "login", "help", "--help", "-h", "version", "--version"]

    /// The GUI's options, for `preview`, `lock`, and `window [section]`.
    struct GUILaunch {
        var mode: LockSession.Mode?
        /// `window`: the window or Settings pane to open, the Themes window when the section is missing or unknown.
        @MainActor var window: AppModel.Section? {
            guard arguments.first == "window" else { return nil }
            return arguments.dropFirst().first.flatMap(AppModel.Section.init(argument:)) ?? .themes
        }
        /// `window widgets`: Customize with Add Widget open.
        var opensWidgetGallery: Bool { arguments.first == "window" && arguments.dropFirst().first == "widgets" }
        var theme: String?
        var size: CGSize?
        var behind = false
        private var arguments: [String] = []

        static func parse(_ arguments: [String]) -> GUILaunch {
            var launch = GUILaunch()
            launch.arguments = arguments
            launch.mode = arguments.first == "preview" ? .preview : arguments.first == "lock" ? .lock : nil
            launch.theme = value("--theme", in: arguments)
            // Two positive numbers up to 100,000 only. A request from any process brings its own size: AppKit traps on
            // NaN and raises an exception that quits Locky for a frame past Int32's range.
            if let size = value("--size", in: arguments)?.split(separator: "x").compactMap({ Double($0) }), size.count == 2,
               size.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 100_000 }) {
                launch.size = CGSize(width: size[0], height: size[1])
            }
            launch.behind = arguments.contains("--behind")
            return launch
        }
    }

    static func value(_ flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func run(_ arguments: [String]) -> Int32 {
        switch arguments.first {
        case "check":
            let report = checkReport(theme: value("--theme", in: arguments), widget: value("--widget", in: arguments))
            print(report.text)
            return report.ok ? 0 : 1
        case "health":
            print(healthReport())
            return 0
        case "themes":
            let runtime = booted()
            let names = (try? runtime.sync { try runtime.call("theme_names", budget: 1).first?.array }) ?? []
            for case .string(let name)? in names.map(Optional.some) {
                let theme = try? runtime.sync { try runtime.call("load_theme", [.string(name)], budget: 1).first }
                let title = theme?["name"].string ?? name
                let description = theme?["description"].string.map { " — \($0)" } ?? ""
                print("\(name)\(title == name ? "" : " (\(title))")\(description)")
            }
            runtime.stop()
            return 0
        case "widgets":
            let runtime = booted()
            let names = (try? runtime.sync { try runtime.call("widget_names", budget: 1).first?.array }) ?? []
            print(names.compactMap(\.string).joined(separator: "\n"))
            runtime.stop()
            return 0
        case "pack":
            guard let action = arguments.dropFirst().first.flatMap(PackManager.Action.init(rawValue:)) else {
                print("usage: locky pack list|check|sync|update|clean")
                return 2
            }
            let report = PackManager(path: .standard()).run(action)
            print(report.text)
            return report.ok ? 0 : 1
        case "login":
            let word = arguments.dropFirst().first
            guard word == nil || word == "on" || word == "off" else {
                print("usage: locky login [on|off]")
                return 2
            }
            if let word {
                do {
                    try LoginItem.set(word == "on")
                } catch {
                    print("error: \(error.localizedDescription)")
                    return 1
                }
            }
            switch LoginItem.status {
            case .enabled: print("Locky opens at login.")
            case .requiresApproval: print("Locky's login item waits for approval in System Settings › General › Login Items.")
            case .notRegistered: print("Locky does not open at login.")
            case .unavailable(let message): print(message)
            }
            return 0
        case "skill":
            switch arguments.dropFirst().first {
            case "path":
                print(AgentSkill.bundled.path)
                return 0
            case "install":
                do {
                    for folder in try AgentSkill().install() { print("Installed \(LuaError.shortenPaths(folder.path))") }
                    return 0
                } catch {
                    print("error: \(error.localizedDescription)")
                    return 1
                }
            default:
                print("usage: locky skill install|path")
                return 2
            }
        case "render":
            return MainActor.assumeIsolated { render(arguments) }
        case "version", "--version":
            print("Locky \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"), \(String(cString: locky_lua_release()))")
            return 0
        default:
            print("""
            usage: locky <command>
              check [--theme NAME] [--widget NAME]
                                     run init.lua, plugins, and a theme, and report every error;
                                     --widget checks only that widget, in the theme
              health                 check Locky, Lua, plugins, Touch ID, and git
              themes                 list themes
              widgets                list widgets
              render --theme NAME [--widget NAME] --out FILE.png [--size 1440x900] [--appearance light|dark]
                                     draw a theme's lock screen to a PNG, with privacy mode on;
                                     --widget draws only that widget, in the middle
              skill install          install the agent skill in ~/.claude, ~/.codex, and ~/.agents
              skill path             print the folder of the skill Locky ships
              pack list|check|sync|update|clean
              login [on|off]         open Locky at login, or not
              preview [--theme NAME] [--size 1440x900]
              lock [--theme NAME]
              window [themes|settings|plugins|config|welcome] [--theme NAME] [--size 1240x780]
            Config: \(LuaError.shortenPaths(RuntimePath.defaultConfig.path))/init.lua
            """)
            return arguments.first == nil || ["help", "--help", "-h"].contains(arguments.first!) ? 0 : 2
        }
    }

    /// `locky render`: the theme's lock screen as a PNG, drawn off the screen (Render). It waits on the main run loop,
    /// which the lock screen's views need, for 10 seconds at most.
    @MainActor private static func render(_ arguments: [String]) -> Int32 {
        let appearanceWord = value("--appearance", in: arguments)
        guard let theme = value("--theme", in: arguments), let out = value("--out", in: arguments),
              [nil, "light", "dark"].contains(appearanceWord) else {
            print("usage: locky render --theme NAME [--widget NAME] --out FILE.png [--size 1440x900] [--appearance light|dark]")
            return 2
        }
        let size = GUILaunch.parse(arguments).size ?? CGSize(width: 1440, height: 900)
        let appearance: NSAppearance.Name? = appearanceWord.map { $0 == "light" ? .aqua : .darkAqua }
        // No Dock icon and no menu bar: nothing shows while it draws.
        NSApplication.shared.setActivationPolicy(.prohibited)
        var result: Result<CGImage, any Error>?
        Task {
            do { result = .success(try await Render.image(theme: theme, widget: value("--widget", in: arguments), size: size,
                                                               appearance: appearance)) } catch { result = .failure(error) }
        }
        let deadline = Date().addingTimeInterval(10)
        while result == nil, Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
        switch result {
        case .success(let image)?:
            let url = URL(fileURLWithPath: out)
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil),
                  { CGImageDestinationAddImage(destination, image, nil); return CGImageDestinationFinalize(destination) }() else {
                print("error: cannot write \(LuaError.shortenPaths(url.path))")
                return 1
            }
            print(url.path)
            return 0
        case .failure(let error)?:
            print("error: \(error)")
            return 1
        case nil:
            print("error: theme \(theme) did not draw within 10 seconds")
            return 1
        }
    }

    private static func booted() -> LuaRuntime {
        let runtime = LuaRuntime(delegate: .init(present: { _, _ in }, failed: { _, _, _ in }))
        runtime.sync { try? runtime.boot() }
        return runtime
    }

    /// Starts a full session without windows and collects what goes wrong in the first 1.5 seconds. With `widget`, the
    /// theme (default unless named) holds that widget alone.
    static func checkReport(theme: String?, widget: String? = nil, config: URL = RuntimePath.defaultConfig) -> (ok: Bool, text: String) {
        final class Collector: @unchecked Sendable {
            let lock = NSLock()
            var rendered = Set<Int>()
            var failures: [Int: String] = [:]
        }
        let collector = Collector()
        var settings: Settings?
        let theme = widget == nil ? theme : theme ?? "default"
        if let widget, let theme {
            settings = Settings.load(config: config).settings
            settings?.showOnly(widget, in: theme)
        }
        let runtime = LuaRuntime(path: .standard(config: config), settings: settings, delegate: .init(
            present: { id, _ in collector.lock.withLock { _ = collector.rendered.insert(id) } },
            failed: { id, message, _ in collector.lock.withLock { collector.failures[id] = message } }
        ))
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var started: LuaRuntime.Started?
        Task.detached {
            started = await runtime.start(theme: theme)
            done.signal()
        }
        done.wait()
        Thread.sleep(forTimeInterval: 1.5)
        runtime.sync {}
        runtime.stop()
        guard let started else { return (false, "Lua did not start") }

        var lines = ["Theme: \(started.theme.name) (\(started.theme.id))"]
        let (rendered, failures) = collector.lock.withLock { (collector.rendered, collector.failures) }
        for (offset, placement) in started.theme.widgets.enumerated() {
            let status: String
            if let id = started.instances[offset] {
                status = failures[id].map { "FAILED: \(LuaError($0).summary)" } ?? (rendered.contains(id) ? "ok" : "no view yet")
            } else {
                status = "FAILED: not started"
            }
            lines.append("  \(placement.widget): \(status)")
        }
        var shaderOK = true
        for (layer, transparent) in [(started.theme.background, false), (started.theme.overlay, true)] {
            guard case .shader(let url, _, _, _, _, _, _)? = layer else { continue }
            do {
                guard let device = MTLCreateSystemDefaultDevice() else { throw LuaError("no Metal device") }
                _ = try ShaderView.compile(String(contentsOf: url, encoding: .utf8), device: device, transparent: transparent)
                lines.append("  \(transparent ? "overlay" : "shader") \(url.lastPathComponent): compiles")
            } catch {
                shaderOK = false
                lines.append("ERROR shader \(LuaError.shortenPaths(url.path)): \(error.localizedDescription)")
            }
        }
        for spec in PackManager(path: .standard(config: config)).specs().specs { lines.append("  plugin \(spec.name): \(spec.grants)") }
        for problem in started.problems { lines.append("ERROR \(problem)") }
        let ok = shaderOK && started.problems.isEmpty && failures.isEmpty && !started.instances.contains(nil)
        lines.append(ok ? "No problems." : "Problems found.")
        return (ok, lines.joined(separator: "\n"))
    }

    /// Like Neovim's :checkhealth: Locky's own checks, then every plugin's lua/<name>/health.lua.
    static func healthReport() -> String {
        var lines: [String] = []
        func ok(_ text: String) { lines.append("  OK      \(text)") }
        func warn(_ text: String, _ advice: String? = nil) { lines.append("  WARNING \(text)" + (advice.map { "\n          → \($0)" } ?? "")) }
        func error(_ text: String, _ advice: String? = nil) { lines.append("  ERROR   \(text)" + (advice.map { "\n          → \($0)" } ?? "")) }

        lines.append("locky")
        let os = SystemInfo.os()
        ok("Locky \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") with \(String(cString: locky_lua_release())) on macOS \(os["version"].string ?? "?")")
        let path = RuntimePath.standard()
        let initFile = path.config.appending(path: "init.lua")
        if FileManager.default.fileExists(atPath: initFile.path) { ok("config: \(LuaError.shortenPaths(initFile.path))") }
        else { warn("no init.lua", "Settings › Lua Config creates one with examples") }

        let runtime = LuaRuntime(path: path, delegate: .init(present: { _, _ in }, failed: { _, _, _ in }))
        var pluginSections: LuaValue = .nil
        runtime.sync {
            do {
                try runtime.boot()
                ok("Lua core loaded")
                for problem in runtime.problemsSoFar { error(problem) }
                let config = try? runtime.call("config", budget: 1).first
                let theme = config?["theme"].string ?? "default"
                do {
                    _ = try runtime.call("load_theme", [.string(theme)], budget: 1)
                    ok("theme \"\(theme)\" loads")
                } catch let failure {
                    error("theme \"\(theme)\": \(LuaError(String(describing: failure)).summary)", "run `locky themes` to see the names")
                }
                pluginSections = (try? runtime.call("health", budget: LuaRuntime.Budget.health).first) ?? .nil
            } catch let failure {
                error("Lua core failed: \(failure)")
            }
        }
        runtime.stop()

        if LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) { ok("Touch ID is available") }
        else { warn("Touch ID is not available", "unlock with your password") }

        switch LoginItem.status {
        case .enabled: ok("opens at login")
        case .requiresApproval: warn("the login item waits for approval", "allow Locky in System Settings › General › Login Items")
        case .notRegistered: warn("Locky does not open at login", "Settings › General › Open at login: Locky locks by itself only while it runs")
        case .unavailable(let message): lines.append("  INFO    \(message)")
        }

        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        git.arguments = ["-p"]
        git.standardOutput = FileHandle.nullDevice
        git.standardError = FileHandle.nullDevice
        if (try? git.run()) != nil, { git.waitUntilExit(); return git.terminationStatus == 0 }() { ok("git is installed, for locky pack") }
        else { warn("git is missing", "run `xcode-select --install` before `locky pack sync`") }

        let (specs, _) = PackManager(path: path).specs()
        for spec in specs where spec.dir == nil && !FileManager.default.fileExists(atPath: path.packs.appending(path: spec.name).path) {
            warn("plugin \(spec.name) is not installed", "run `locky pack sync`")
        }
        for spec in specs { lines.append("  INFO    plugin \(spec.name): \(spec.grants)") }

        for section in pluginSections["sections"].array ?? [] {
            lines.append("")
            lines.append(section["name"].string ?? "?")
            for item in section["items"].array ?? [] {
                let message = item["message"].string ?? ""
                let advice = item["advice"].string
                switch item["kind"].string {
                case "ok": ok(message)
                case "warn": warn(message, advice)
                case "error": error(message, advice)
                default: lines.append("  INFO    \(message)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Creates ~/.config/locky/init.lua with examples, and a .luarc.json that gives lua-language-server
    /// Locky's types. Each only once.
    static func ensureConfig() {
        let fm = FileManager.default
        let config = RuntimePath.defaultConfig
        try? Settings.createFolder(config)
        try? fm.createDirectory(at: config.appending(path: "lua"), withIntermediateDirectories: true)
        let file = config.appending(path: "init.lua")
        if !fm.fileExists(atPath: file.path) {
            try? fm.copyItem(at: RuntimePath.resources.appending(path: "init.lua.example"), to: file)
        }
        let luarc = config.appending(path: ".luarc.json")
        let types = RuntimePath.builtInRuntime.appending(path: "types").path
        // Write it when missing, and again when it points at a Locky.app that has since moved.
        let current = (try? JSONSerialization.jsonObject(with: Data(contentsOf: luarc)) as? [String: Any])?["workspace.library"] as? [String]
        if !fm.fileExists(atPath: luarc.path) || (current?.allSatisfy { !fm.fileExists(atPath: $0) } ?? false) {
            let settings: [String: Any] = [
                "$schema": "https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json",
                "runtime.version": "Lua 5.5",
                "workspace.library": [types],
                "diagnostics.globals": ["locky"],
            ]
            if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                try? data.write(to: luarc)
            }
        }
    }
}
