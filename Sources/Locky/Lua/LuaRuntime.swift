import AppKit
import Foundation
import os

/// Everything Lua for one session (a lock or a preview): one Lua state on one serial queue, and the timers,
/// event handlers, and processes the Lua code started. Each of those belongs to an owner: a widget instance,
/// or 0 for global code. When an owner keeps failing, or runs past its time budget, the runtime stops
/// everything it owns. The lock screen itself never waits for Lua.
final class LuaRuntime: @unchecked Sendable {
    /// What the host hears about. Called on the runtime's queue.
    struct Delegate: Sendable {
        /// A widget's new view, or nil to show nothing.
        var present: @Sendable (_ instance: Int, _ view: Node?) -> Void
        /// A widget failed. `disabled` is true when the runtime stopped it.
        var failed: @Sendable (_ instance: Int, _ message: String, _ disabled: Bool) -> Void
    }

    /// Values the host reads on the main thread and the runtime reports, such as the keyboard layout.
    final class Environment: @unchecked Sendable {
        private let lock = NSLock()
        private var _keyboard: LuaValue = .table([:])
        private var _displays = 1
        private var _wallpaper: String?
        private var _screen = CGSize(width: 1440, height: 900)
        private var _wallpaperColors: [String]?

        var keyboard: LuaValue {
            get { lock.withLock { _keyboard } }
            set { lock.withLock { _keyboard = newValue } }
        }

        var displays: Int {
            get { lock.withLock { _displays } }
            set { lock.withLock { _displays = newValue } }
        }

        /// The main display's desktop picture, as an image file (NSWorkspace needs the main thread).
        var wallpaper: String? {
            get { lock.withLock { _wallpaper } }
            set { lock.withLock { _wallpaper = newValue; _wallpaperColors = nil } }
        }

        /// The main display's size in points (the preview window's, in a preview).
        var screen: CGSize {
            get { lock.withLock { _screen } }
            set { lock.withLock { _screen = newValue } }
        }

        /// Its dominant colors, worked out on first use.
        var wallpaperColors: [String] {
            if let cached = lock.withLock({ _wallpaperColors }) { return cached }
            let colors = wallpaper.map { Wallpaper.colors(of: URL(fileURLWithPath: $0)) } ?? []
            lock.withLock { _wallpaperColors = colors }
            return colors
        }
    }

    /// Seconds each kind of call may run.
    enum Budget {
        static let prelude = 1.0
        static let config = 2.0
        static let pluginScript = 1.0
        static let theme = 1.0
        static let create = 0.1
        static let initialize = 0.5
        static let render = 0.1
        static let callback = 0.1
        static let health = 10.0
    }

    struct Started: Sendable {
        var theme: Theme
        /// Instance ids for theme.widgets, in order; nil where the widget is unknown or failed to start.
        var instances: [Int?]
        var autoUnlock: Double
        /// Errors in init.lua, plugin scripts, or the theme: for the preview and `locky check`.
        var problems: [String]
        /// true or false forces a 24- or 12-hour clock; nil follows the system.
        var hour24: Bool? = nil
        /// Hides the user's name in the password field (Lua hides it in widgets).
        var privacy = false
        /// A line under the password field.
        var message: String? = nil
    }

    let queue = DispatchQueue(label: "com.tornikegomareli.Locky.lua", qos: .userInitiated)
    let environment: Environment
    private let delegate: Delegate
    private(set) var path: RuntimePath
    /// settings.json, read when Lua boots unless the host passes its own (the theme editor's preview does).
    private var settings: Settings?
    private var vm: LuaVM?
    private var entries: [String: LuaRef] = [:]
    private var problems: [String] = []

    private struct ScheduledTimer {
        var source: DispatchSourceTimer
        var callback: LuaRef
        var owner: Int
        var repeats: Bool
        var seconds: Double
        var align: Bool
    }

    private struct Handler {
        var callback: LuaRef
        var owner: Int
    }

    private var timers: [Int: ScheduledTimer] = [:]
    private var handlers: [String: [Handler]] = [:]
    private var processes: [Int: ChildProcess] = [:]
    private var lastID = 0
    private var dirty = Set<Int>()
    private var flushScheduled = false
    private var lastFlush = 0.0
    private var failures: [Int: Int] = [:]
    private var disabled = Set<Int>()
    private let cpu = SystemInfo.CPUMeter()
    private var stopped = false

    static let log = Logger(subsystem: "com.tornikegomareli.Locky", category: "lua")

    init(path: RuntimePath = .standard(), environment: Environment = Environment(), settings: Settings? = nil, delegate: Delegate) {
        self.path = path
        self.environment = environment
        self.settings = settings
        self.delegate = delegate
    }

    // MARK: Lifecycle

    /// Starts Lua: the core, init.lua, every plugin/ script, the theme, and its widgets. Runs on the queue.
    func start(theme override: String? = nil) async -> Started {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.startOnQueue(themeOverride: override)) }
        }
    }

    private func startOnQueue(themeOverride: String?) -> Started {
        do {
            try boot()
        } catch {
            problems.append("Locky's Lua core failed to start: \(error)")
            // Without Lua, settings.json still says how the lock looks: privacy, the message, the clock.
            let settings = settings ?? Settings.load(config: path.config).settings
            let seconds = settings["auto_unlock"].number.map { $0.isFinite ? min(max($0, 0), 86_400) : 0 } ?? 60
            let message = settings["message"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Started(theme: .fallback, instances: [], autoUnlock: seconds, problems: problems, hour24: settings["hour24"].bool,
                           privacy: settings["privacy"].bool ?? false, message: message?.isEmpty == false ? String(message!.prefix(200)) : nil)
        }
        let config = (try? call("config", budget: Budget.callback).first) ?? .nil
        // Not a number, or infinite: off. Otherwise at most a day; a sleep of an infinite duration traps.
        let autoUnlock = config["auto_unlock"].isNil ? 60 : config["auto_unlock"].number.map { $0.isFinite ? min(max($0, 0), 86_400) : 0 } ?? 0
        // Read before the theme loads: the bare fallback keeps them too.
        let hour24 = config["hour24"].bool, privacy = config["privacy"].bool ?? false
        let trimmed = config["message"].string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let message = trimmed.isEmpty ? nil : String(trimmed.prefix(200))
        let requested = themeOverride ?? config["theme"].string ?? "default"
        var theme = loadTheme(requested)
        if theme == nil, requested != "default" { theme = loadTheme("default") }
        guard let theme else {
            return Started(theme: .fallback, instances: [], autoUnlock: autoUnlock, problems: problems, hour24: hour24, privacy: privacy,
                           message: message)
        }
        var instances: [Int?] = []
        for (offset, placement) in theme.widgets.enumerated() {
            guard placement.known else {
                problems.append("theme \(theme.id): no widget named \"\(placement.widget)\"")
                instances.append(nil)
                continue
            }
            guard let id = (try? call("create", [.int(offset + 1)], budget: Budget.create).first)?.int else {
                instances.append(nil)
                continue
            }
            instances.append(id)
            do {
                try call("init", [.int(id)], budget: Budget.initialize)
            } catch {
                fail(owner: id, error)
            }
            invalidate(id)
        }
        emit("lock")
        return Started(theme: theme, instances: instances, autoUnlock: autoUnlock, problems: problems, hour24: hour24, privacy: privacy,
                       message: message)
    }

    /// Loads the Lua core and runs the user's files, without a theme: for `locky check` and the pack manager.
    /// settings.json's packages load before init.lua, so init.lua can require them. Its values apply before
    /// init.lua too, so the code it runs sees them (privacy above all), and again after the plugin scripts, so
    /// they win over both.
    func boot() throws {
        let vm = try LuaVM()
        self.vm = vm
        let core = RuntimePath.builtInRuntime.appending(path: "lua/locky/_core.lua")
        let source = try String(contentsOf: core, encoding: .utf8)
        let exported = try vm.runPrelude(source, chunkName: "@locky/_core.lua", natives: natives(), budget: Budget.prelude)
        for (name, value) in exported {
            if let ref = value.function { entries[name] = ref }
        }
        if settings == nil {
            let (loaded, problem) = Settings.load(config: path.config)
            if let problem { report(problem) }
            settings = loaded
        }
        let settings = settings ?? Settings()
        if !settings.packs.isEmpty {
            do {
                let failures = try call("settings_packs", [.array(settings.packs)], budget: Budget.callback).first?.array ?? []
                for case .string(let failure) in failures { report("settings.json packs: \(failure)") }
            } catch {
                report("settings.json packs: \(LuaError(String(describing: error)).summary)")
            }
        }
        let reported = applySettings(settings)
        let initFile = path.config.appending(path: "init.lua")
        if FileManager.default.fileExists(atPath: initFile.path) {
            runFile(initFile, budget: Budget.config)
        }
        // Again, so plugin scripts see settings.json's values (privacy) over what init.lua set.
        applySettings(settings, reported: reported)
        for script in path.pluginScripts() {
            runFile(script, budget: Budget.pluginScript)
        }
        applySettings(settings, reported: reported)
    }

    /// Applies settings.json's values and reports each failure not in `reported`. Returns the failures.
    @discardableResult
    private func applySettings(_ settings: Settings, reported: [String] = []) -> [String] {
        var failures: [String]
        do {
            let list = try call("apply_settings", [settings.lua], budget: Budget.callback).first?.array ?? []
            failures = list.compactMap(\.string).map { "settings.json \($0)" }
        } catch {
            failures = ["settings.json: \(LuaError(String(describing: error)).summary)"]
        }
        for failure in failures where !reported.contains(failure) { report(failure) }
        return failures
    }

    /// Ends the session: tells Lua code about it, stops every timer and process, and closes the state.
    func stop() {
        queue.async { [self] in
            guard !stopped else { return }
            emit("unlock")
            stopped = true
            for timer in timers.values { cancel(timer) }
            timers = [:]
            for process in processes.values { process.terminate() }
            processes = [:]
            handlers = [:]
            entries = [:]
            vm = nil
        }
    }

    private var paused = false

    /// Suspends every timer (the display slept) or resumes them; timers started while paused start suspended.
    func setPaused(_ pause: Bool) {
        queue.async { [self] in
            guard pause != paused, !stopped else { return }
            paused = pause
            for timer in timers.values { pause ? timer.source.suspend() : timer.source.resume() }
            if !pause {
                realignOnQueue()
                // Widgets show fresh data at once instead of at their next tick.
                for id in Set(timers.values.map(\.owner)) where id != 0 { invalidate(id) }
            }
        }
    }

    /// Calls `fn` on the queue and waits: for tests and the command line.
    func sync<T>(_ body: () throws -> T) rethrows -> T {
        try queue.sync(execute: body)
    }

    /// Lua memory in bytes, for tests and health. Read on the queue.
    var memoryUsed: Int { vm?.memoryUsed ?? 0 }

    /// Errors so far in init.lua, plugin scripts, and themes. Read on the queue.
    var problemsSoFar: [String] { problems }

    /// Runs Lua source in this state and returns its results. On the queue.
    func evaluate(_ source: String, budget: Double) throws -> [LuaValue] {
        guard let vm else { throw LuaError("Lua is not running") }
        let chunk = try vm.load(source, chunkName: "=eval")
        defer { vm.release(chunk) }
        return try vm.call(chunk, budget: budget)
    }

    // MARK: Calling Lua

    private func runFile(_ url: URL, budget: Double) {
        guard let vm else { return }
        do {
            let chunk = try vm.loadFile(url)
            defer { vm.release(chunk) }
            try vm.call(chunk, budget: budget)
        } catch {
            report(LuaError.shortenPaths(String(describing: error)))
        }
    }

    @discardableResult
    func call(_ entry: String, _ args: [LuaValue] = [], budget: Double) throws -> [LuaValue] {
        guard let vm, let ref = entries[entry] else { throw LuaError("Lua is not running") }
        return try vm.call(ref, args, budget: budget)
    }

    private func loadTheme(_ name: String) -> Theme? {
        do {
            guard let exported = try call("load_theme", [.string(name)], budget: Budget.theme).first else { return nil }
            for case .string(let problem) in exported["problems"].array ?? [] { report(problem) }
            do {
                return try Theme(lua: exported, path: path)
            } catch let error where exported["edited"].bool == true {
                // settings.json's change names something that is not there, such as a shader: like any bad change,
                // it is reported and the theme loads without it. If the theme fails on its own, that error counts.
                guard let original = try call("load_theme", [.string(name), .bool(false)], budget: Budget.theme).first else { return nil }
                let theme = try Theme(lua: original, path: path)
                report("settings.json themes.\(name): \(LuaError.shortenPaths(String(describing: error)))")
                return theme
            }
        } catch {
            report("theme \(name): \(LuaError.shortenPaths(String(describing: error)))")
            return nil
        }
    }

    private func report(_ problem: String) {
        problems.append(problem)
        Self.log.error("\(problem, privacy: .public)")
        LogFile.shared.write(level: "error", message: problem, source: "locky")
    }

    /// Records a failure of `owner`'s code. Three in a row, or one timeout, stop the owner.
    private func fail(owner: Int, _ error: Error) {
        let message = LuaError.shortenPaths(String(describing: error))
        LogFile.shared.write(level: "error", message: message, source: owner == 0 ? "lua" : "widget \(owner)")
        failures[owner, default: 0] += 1
        let timedOut = message.contains("time budget exceeded")
        let stop = owner != 0 && (timedOut || failures[owner, default: 0] >= 3)
        if stop { disable(owner) }
        if owner != 0 { delegate.failed(owner, message, stop) }
    }

    private func succeeded(owner: Int) {
        failures[owner] = nil
    }

    private func disable(_ owner: Int) {
        disabled.insert(owner)
        for (id, timer) in timers where timer.owner == owner {
            cancel(timer)
            vm?.release(timer.callback)
            timers[id] = nil
        }
        for (id, process) in processes where process.owner == owner {
            process.terminate()
            processes[id] = nil
        }
        for (event, list) in handlers {
            handlers[event] = list.filter { handler in
                if handler.owner == owner { vm?.release(handler.callback) }
                return handler.owner != owner
            }
        }
        dirty.remove(owner)
        _ = try? call("dispose", [.int(owner)], budget: Budget.callback)
    }

    /// Calls a Lua callback for `owner`, recording failures.
    private func invoke(_ callback: LuaRef, _ args: [LuaValue] = [], owner: Int) {
        guard let vm, !stopped, !disabled.contains(owner) else { return }
        do {
            try vm.call(callback, args, budget: Budget.callback)
            succeeded(owner: owner)
        } catch {
            fail(owner: owner, error)
        }
    }

    func emit(_ event: String, _ data: LuaValue = .nil) {
        for handler in handlers[event] ?? [] {
            invoke(handler.callback, [data], owner: handler.owner)
        }
    }

    // MARK: Rendering

    private func invalidate(_ id: Int) {
        guard !disabled.contains(id) else { return }
        dirty.insert(id)
        guard !flushScheduled else { return }
        flushScheduled = true
        // At most 30 redraws a second, however often widgets change.
        let wait = max(0, lastFlush + 1.0 / 30 - CACurrentMediaTime())
        queue.asyncAfter(deadline: .now() + wait) { [weak self] in self?.flush() }
    }

    private func flush() {
        flushScheduled = false
        guard !stopped else { return }
        lastFlush = CACurrentMediaTime()
        let ids = dirty.sorted()
        dirty = []
        for id in ids where !stopped && !disabled.contains(id) {
            render(id)
        }
    }

    private func render(_ id: Int) {
        do {
            let result = try call("render", [.int(id)], budget: Budget.render).first ?? .nil
            let view = result.isNil ? nil : try Node(lua: result)
            succeeded(owner: id)
            delegate.present(id, view)
        } catch {
            fail(owner: id, error)
        }
    }

    // MARK: Natives

    private func nextID() -> Int {
        lastID += 1
        return lastID
    }

    private func natives() -> [String: LuaVM.Native] {
        [
            "version": { _ in [.string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")] },
            "home": { _ in [.string(FileManager.default.homeDirectoryForCurrentUser.path)] },

            "log": { call in
                let level = try call.string(1, "level")
                let message = String(try call.string(2, "message").prefix(4000))
                let source = try call.optionalString(3, "source") ?? "lua"
                LogFile.shared.write(level: level, message: message, source: LuaError.shortenPaths(source))
                return []
            },

            // The runtime path.
            "find_module": { [unowned self] call in
                [path.findModule(try call.string(1, "name")).map { .string($0.path) } ?? .nil]
            },
            "find_runtime": { [unowned self] call in
                [path.find(try call.string(1, "path")).map { .string($0.path) } ?? .nil]
            },
            "find_all": { [unowned self] call in
                let found = path.findAll(try call.string(1, "folder"), suffix: try call.string(2, "suffix"))
                return [.array(found.map { .table(["name": .string($0.name), "path": .string($0.url.path)]) })]
            },
            "pack_add": { [unowned self] call in
                let name = try call.string(1, "name")
                let dir = try call.optionalString(2, "dir")
                let url = dir.map { URL(fileURLWithPath: $0) } ?? path.packs.appending(path: name)
                let installed = FileManager.default.fileExists(atPath: url.path)
                if installed { path.insertPackage(url) }
                return [.bool(installed)]
            },

            // Widgets, timers, events, processes.
            "invalidate": { [unowned self] call in
                guard let id = try call.value(1).int else { throw LuaError("invalidate: expected an instance id") }
                invalidate(id)
                return []
            },
            "timer": { [unowned self] call in
                let owner = try call.value(1).int ?? 0
                let seconds = try call.number(2, "seconds")
                let repeats = try call.value(3).bool ?? false
                // Dispatch traps on intervals past about 1.8e10 s; a billion seconds is 31 years.
                guard seconds.isFinite, seconds >= 0, seconds <= 1e9, !repeats || seconds >= 0.05 else {
                    throw LuaError("seconds must be from 0 to 1e9, and at least 0.05 for a repeating timer")
                }
                let callback = try call.function(4, "fn")
                let align = try call.value(5).bool ?? false
                return [.int(startTimer(owner: owner, seconds: seconds, repeats: repeats, align: align, callback: callback))]
            },
            "timer_stop": { [unowned self] call in
                if let id = try call.value(1).int, let timer = timers.removeValue(forKey: id) {
                    cancel(timer)
                    vm?.release(timer.callback)
                }
                return []
            },
            "on": { [unowned self] call in
                let event = try call.string(1, "event")
                let callback = try call.function(2, "fn")
                let owner = try call.value(3).int ?? 0
                handlers[event, default: []].append(Handler(callback: callback, owner: owner))
                return []
            },
            "system": { [unowned self] call in
                let owner = try call.value(1).int ?? 0
                let command = try call.table(2, "cmd").array?.compactMap(\.string) ?? []
                let options = try call.optionalTable(3, "opts") ?? .table([:])
                // A NUL byte in an argument, a variable, or the folder makes Foundation throw an Objective-C
                // exception, which would end the app (and the lock with it).
                let env = options["env"].table ?? [:]
                let texts = command + env.keys + env.values.compactMap(\.string) + [options["cwd"].string].compactMap { $0 }
                if texts.contains(where: { $0.contains("\0") }) {
                    throw LuaError("locky.system: arguments, env, and cwd must not contain a NUL byte")
                }
                let onExit = try call.optionalFunction(4, "on_exit")
                return [.int(startProcess(owner: owner, command: command, options: options, onExit: onExit))]
            },
            "system_kill": { [unowned self] call in
                if let id = try call.value(1).int { processes[id]?.terminate() }
                return []
            },

            // Files and JSON.
            "fs_read": { call in
                let url = Self.expand(try call.string(1, "path"))
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    if let size = attributes[.size] as? Int, size > 16 << 20 { return [.nil, .string("file is larger than 16 MB")] }
                    return [.string(String(decoding: try Data(contentsOf: url), as: UTF8.self))]
                } catch {
                    return [.nil, .string(error.localizedDescription)]
                }
            },
            "fs_exists": { call in
                [.bool(FileManager.default.fileExists(atPath: Self.expand(try call.string(1, "path")).path))]
            },
            // "file", "directory", "other" (a pipe, socket, or device), or nil when nothing is there.
            "fs_kind": { call in
                var info = stat()
                guard stat((try call.string(1, "path") as NSString).expandingTildeInPath, &info) == 0 else { return [.nil] }
                switch info.st_mode & S_IFMT {
                case S_IFREG: return [.string("file")]
                case S_IFDIR: return [.string("directory")]
                default: return [.string("other")]
                }
            },
            "fs_is_dir": { call in
                var directory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: Self.expand(try call.string(1, "path")).path, isDirectory: &directory)
                return [.bool(exists && directory.boolValue)]
            },
            "fs_list": { call in
                do {
                    let names = try FileManager.default.contentsOfDirectory(atPath: Self.expand(try call.string(1, "path")).path)
                    return [.array(names.sorted().map(LuaValue.string))]
                } catch {
                    return [.nil, .string(error.localizedDescription)]
                }
            },
            "json_encode": { call in
                let object = try call.value(1).jsonObject()
                let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
                return [.string(String(decoding: data, as: UTF8.self))]
            },
            "json_decode": { call in
                let text = try call.string(1, "json")
                do {
                    let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
                    return [LuaValue(json: object)]
                } catch {
                    throw LuaError("invalid JSON: \(error.localizedDescription)")
                }
            },

            // The system.
            "sys_battery": { _ in [SystemInfo.battery()] },
            "sys_cpu": { [unowned self] _ in [cpu.read()] },
            "sys_memory": { _ in [SystemInfo.memory()] },
            "sys_uptime": { _ in [SystemInfo.uptime()] },
            "sys_hostname": { _ in [SystemInfo.hostname()] },
            "sys_user": { _ in [SystemInfo.user()] },
            "sys_os": { _ in [SystemInfo.os()] },
            "sys_machine": { _ in [SystemInfo.machine()] },
            "sys_keyboard": { [unowned self] _ in [environment.keyboard] },
            "sys_displays": { [unowned self] _ in [.int(environment.displays)] },
            "sys_wallpaper": { [unowned self] _ in [environment.wallpaper.map(LuaValue.string) ?? .nil] },
            "sys_wallpaper_colors": { [unowned self] _ in [.array(environment.wallpaperColors.map(LuaValue.string))] },
            "sys_screen": { [unowned self] _ in
                let size = environment.screen, scale = Layout.scale(for: size)
                return [.table([
                    "width": .double(size.width), "height": .double(size.height), "scale": .double(scale),
                    // The space themes lay out in: offsets and sizes in these units fill the screen.
                    "layout_width": .double(size.width / scale), "layout_height": .double(size.height / scale),
                ])]
            },
            "now": { _ in [.double(Date().timeIntervalSince1970)] },
            "date_format": { call in
                let template = try call.string(1, "template")
                let time = try call.number(2, "time")
                return [.string(SystemInfo.format(Date(timeIntervalSince1970: time), template))]
            },
            "locale": { _ in [SystemInfo.locale()] },
        ]
    }

    static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    // MARK: Timers

    private func startTimer(owner: Int, seconds: Double, repeats: Bool, align: Bool, callback: LuaRef) -> Int {
        let id = nextID()
        let source = DispatchSource.makeTimerSource(queue: queue)
        let timer = ScheduledTimer(source: source, callback: callback, owner: owner, repeats: repeats, seconds: seconds, align: align)
        schedule(timer)
        source.setEventHandler { [weak self] in self?.fire(id) }
        timers[id] = timer
        if !paused { source.resume() }
        return id
    }

    /// Monotonic deadlines: macOS defers wall-clock timers by many seconds in an app it naps. Monotonic time
    /// stops during system sleep, so aligned timers are scheduled again on wake (realign).
    private func schedule(_ timer: ScheduledTimer) {
        var delay = timer.seconds
        if timer.align, timer.seconds > 0 {
            // The next multiple of `seconds` on the wall clock, such as the start of the next minute.
            let now = Date().timeIntervalSince1970
            delay = (now / timer.seconds).rounded(.down) * timer.seconds + timer.seconds - now + 0.005
        }
        let leeway = DispatchTimeInterval.milliseconds(timer.repeats ? min(250, max(1, Int(timer.seconds * 50))) : 5)
        if timer.repeats {
            timer.source.schedule(deadline: .now() + delay, repeating: timer.seconds, leeway: leeway)
        } else {
            timer.source.schedule(deadline: .now() + delay, leeway: leeway)
        }
    }

    /// Puts aligned timers back on the wall clock's beat after the Mac or its display slept, and runs each
    /// once now: a view tied to the minute would otherwise stay stale until the next boundary.
    func realign() {
        queue.async { [self] in realignOnQueue() }
    }

    private func realignOnQueue() {
        let aligned = timers.filter { $0.value.align && $0.value.repeats }
        for timer in aligned.values { schedule(timer) }
        for id in aligned.keys.sorted() { fire(id) }
    }

    /// A suspended source is only freed once resumed, so a paused timer is resumed right after its cancel.
    private func cancel(_ timer: ScheduledTimer) {
        timer.source.cancel()
        if paused { timer.source.resume() }
    }

    private func fire(_ id: Int) {
        guard let timer = timers[id] else { return }
        if !timer.repeats {
            timers[id] = nil
            cancel(timer)
        }
        invoke(timer.callback, owner: timer.owner)
        if !timer.repeats { vm?.release(timer.callback) }
        // A global repeating timer that keeps failing is stopped on its own.
        if timer.owner == 0, timer.repeats, failures[0, default: 0] >= 3, let stillThere = timers.removeValue(forKey: id) {
            cancel(stillThere)
            vm?.release(stillThere.callback)
            failures[0] = nil
            LogFile.shared.write(level: "error", message: "stopped a timer that failed 3 times in a row", source: "lua")
        }
    }

    // MARK: Processes

    private func startProcess(owner: Int, command: [String], options: LuaValue, onExit: LuaRef?) -> Int {
        let id = nextID()
        let timeout = options["timeout"].number ?? 10
        let process = ChildProcess(
            owner: owner,
            command: command,
            cwd: options["cwd"].string.map(Self.expand),
            environment: (options["env"].table ?? [:]).compactMapValues { $0.string ?? $0.number.map { String($0) } },
            stdin: options["stdin"].string,
            timeout: timeout,
            queue: queue
        ) { [weak self] result in
            guard let self else { return }
            processes[id] = nil
            guard let onExit else { return }
            defer { vm?.release(onExit) }
            invoke(onExit, [result], owner: owner)
        }
        processes[id] = process
        process.start()
        return id
    }
}

/// A program started by locky.system: output collected, a timeout enforced, the result reported on `queue`.
final class ChildProcess: @unchecked Sendable {
    let owner: Int
    private let process = Process()
    private let command: [String]
    private let stdin: String?
    private let timeout: Double
    private let queue: DispatchQueue
    private let completion: (LuaValue) -> Void
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var timedOut = false
    private var finished = false
    /// Pipes still open: [stdout, stderr]. Each one is let go once, at EOF or when given up on.
    private var reading = [true, true]
    private var pipes: [Pipe] = []
    private let group = DispatchGroup()
    private static let outputLimit = 4 << 20

    init(owner: Int, command: [String], cwd: URL?, environment: [String: String], stdin: String?, timeout: Double,
         queue: DispatchQueue, completion: @escaping (LuaValue) -> Void) {
        self.owner = owner
        self.command = command
        self.stdin = stdin
        self.timeout = timeout
        self.queue = queue
        self.completion = completion
        var env = ProcessInfo.processInfo.environment
        // Apps opened from Finder get a short PATH; Homebrew's folders hold most tools widgets call.
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" + (env["PATH"].map { ":" + $0 } ?? "")
        for (key, value) in environment { env[key] = value }
        process.environment = env
        if let cwd { process.currentDirectoryURL = cwd }
    }

    func start() {
        guard let program = command.first, let executable = Self.resolve(program, path: process.environment?["PATH"] ?? "") else {
            report(code: 127, signal: 0, error: "command not found: \(command.first ?? "")")
            return
        }
        process.executableURL = executable
        process.arguments = Array(command.dropFirst())
        let out = Pipe(), err = Pipe(), input = Pipe()
        pipes = [out, err]
        process.standardOutput = out
        process.standardError = err
        process.standardInput = stdin == nil ? FileHandle.nullDevice : input
        for (index, pipe) in pipes.enumerated() {
            group.enter()
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    self?.stopReading(index)
                    return
                }
                self?.append(chunk, error: index == 1)
            }
        }
        group.enter()
        process.terminationHandler = { [weak self, group] _ in
            // A program that started a background child may leave its pipes open after it exits: the result
            // comes half a second later at most, instead of when that child ends.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                self?.stopReading(0)
                self?.stopReading(1)
            }
            group.leave()
        }
        do {
            try process.run()
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            report(code: 126, signal: 0, error: "cannot run \(program): \(error.localizedDescription)")
            return
        }
        if let stdin {
            let handle = input.fileHandleForWriting
            DispatchQueue.global().async {
                try? handle.write(contentsOf: Data(stdin.utf8))
                try? handle.close()
            }
        }
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, process.isRunning else { return }
            lock.withLock { timedOut = true }
            terminate()
        }
        // Holds this object until the program exits, so its result is reported (and its callback
        // released) even after the runtime dropped it.
        group.notify(queue: queue) { [self] in
            let code = Int(process.terminationStatus)
            let signal = process.terminationReason == .uncaughtSignal ? code : 0
            report(code: process.terminationReason == .uncaughtSignal ? 128 + code : code, signal: signal, error: nil)
        }
    }

    /// Stops reading pipe `index` (0 stdout, 1 stderr) and lets the result go on, once.
    private func stopReading(_ index: Int) {
        let wasReading = lock.withLock { () -> Bool in
            defer { reading[index] = false }
            return reading[index]
        }
        guard wasReading else { return }
        pipes[index].fileHandleForReading.readabilityHandler = nil
        group.leave()
    }

    /// SIGTERM, then SIGKILL two seconds later.
    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        // The Process, not this object, is kept for the kill: the runtime may drop this object right away.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private func append(_ chunk: Data, error: Bool) {
        lock.withLock {
            if error {
                if stderr.count < Self.outputLimit { stderr.append(chunk.prefix(Self.outputLimit - stderr.count)) }
            } else if stdout.count < Self.outputLimit {
                stdout.append(chunk.prefix(Self.outputLimit - stdout.count))
            }
        }
    }

    private func report(code: Int, signal: Int, error: String?) {
        let (out, err, timedOut) = lock.withLock { (stdout, stderr, self.timedOut) }
        let done = lock.withLock { () -> Bool in
            defer { finished = true }
            return finished
        }
        guard !done else { return }
        let result: LuaValue = .table([
            "code": .int(code),
            "signal": .int(signal),
            "stdout": .string(String(decoding: out, as: UTF8.self)),
            "stderr": .string(error ?? String(decoding: err, as: UTF8.self)),
            "timed_out": .bool(timedOut),
        ])
        queue.async { self.completion(result) }
    }

    private static func resolve(_ program: String, path: String) -> URL? {
        if program.contains("/") {
            let url = LuaRuntime.expand(program)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appending(path: program)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

/// ~/Library/Logs/Locky/locky.log: what plugins print and every error, kept under 2 MB.
final class LogFile: @unchecked Sendable {
    static let shared = LogFile()
    private let lock = NSLock()
    /// Locky.app logs to ~/Library/Logs; tests and other hosts log to a temporary folder.
    private let url: URL = Bundle.main.bundleIdentifier == "com.tornikegomareli.Locky"
        ? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Locky/locky.log")
        : FileManager.default.temporaryDirectory.appending(path: "locky-test-logs/locky.log")
    private var handle: FileHandle?
    /// The last messages, for the preview and `locky health`.
    private(set) var recent: [String] = []

    func write(level: String, message: String, source: String) {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.colon))
        let line = "\(stamp) [\(level)] \(source): \(message)\n"
        lock.withLock {
            recent.append(line)
            if recent.count > 200 { recent.removeFirst(recent.count - 200) }
            if handle == nil { open() }
            try? handle?.write(contentsOf: Data(line.utf8))
        }
    }

    private func open() {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? Int, size > 2 << 20 {
            try? fm.removeItem(at: url.deletingPathExtension().appendingPathExtension("old.log"))
            try? fm.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension("old.log"))
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }
}
