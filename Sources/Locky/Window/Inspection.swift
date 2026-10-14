import Foundation

/// What the window knows about the user's Locky, read the way `locky check` reads it: by booting Lua (init.lua,
/// plugin scripts, settings.json) off the main thread. No theme runs and no widget starts.
struct Inspection: Sendable {
    struct ThemeInfo: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var description: String?
        var author: String?
        var directory: URL?
        /// The theme's own colors, before the defaults: for the theme cards.
        var palette: [String: String] = [:]
        /// Why the theme file does not load, if it does not.
        var error: String?
    }

    struct WidgetInfo: Identifiable, Equatable, Sendable {
        var id: String { name }
        var name: String
        var description: String?
        var file: URL?
        /// Whether it sits on the theme's card when the theme does not say.
        var card = false
        /// Its options with init.lua's: what a placement the window adds starts with.
        var opts: [String: LuaValue] = [:]
        /// Its own options, without init.lua's: what kind of value each one takes.
        var defaults: [String: LuaValue] = [:]
        /// The values its options take, for the editor's menus.
        var choices: [String: [String]] = [:]
        /// Apple's families it draws, such as "circular" and "small"; none draws at its own size only.
        var families: [String] = []
    }

    /// A package from locky.pack.add (init.lua) or settings.json's packs (the window).
    struct PackInfo: Identifiable, Hashable, Sendable {
        var id: String { name }
        var name: String
        var src: String?
        var version: String?
        /// A local folder, for a plugin being written.
        var dir: URL?
        /// Added by the window (settings.json), not by init.lua.
        var fromSettings: Bool
        /// Added by both; settings.json's entry wins.
        var alsoInConfig: Bool
        var folder: URL
        var installed: Bool
        /// The commit locky-pack-lock.json pins it to.
        var commit: String?
        /// What the user lets it do: "system" (run programs) and "files" (change files).
        var allow: [String] = []
    }

    var themes: [ThemeInfo] = []
    var widgets: [WidgetInfo] = []
    var packs: [PackInfo] = []
    /// Lua's config with settings.json applied: what a lock uses.
    var config: LuaValue = .nil
    /// The same without settings.json: what init.lua (or the default) says.
    var base: LuaValue = .nil
    /// Errors from settings.json, init.lua, and plugin scripts.
    var problems: [String] = []
    /// Changes when a Lua file or an asset in the config, a plugin, or a theme changes: RuntimePath.fingerprint.
    var sources = 0
    var loaded = false

    func theme(_ id: String) -> ThemeInfo? { themes.first { $0.id == id } }
    func widget(_ name: String) -> WidgetInfo? { widgets.first { $0.name == name } }

    /// `settings` is the app's copy of settings.json, which a lock uses too: while the file has an error, the last
    /// one that read without one.
    static func load(config: URL, settings: Settings) async -> Inspection {
        await background {
            var result = Inspection()
            let path = RuntimePath.standard(config: config)
            let runtime = LuaRuntime(path: path, settings: settings, delegate: .silent)
            runtime.sync {
                try? runtime.boot()
                result.problems = runtime.problemsSoFar
                result.sources = runtime.path.fingerprint()
                result.config = (try? runtime.call("config", budget: 1).first) ?? .nil
                result.themes = ((try? runtime.call("theme_infos", budget: 5).first?.array) ?? []).map { info in
                    ThemeInfo(id: info["id"].string ?? "?", name: info["name"].string ?? info["id"].string ?? "?",
                              description: info["description"].string, author: info["author"].string,
                              directory: info["dir"].string.map { URL(fileURLWithPath: $0) },
                              palette: (info["palette"].table ?? [:]).compactMapValues(\.string), error: info["error"].string)
                }
                let lockfile = try? PackManager.readLockfile(path.lockfile)
                result.packs = ((try? runtime.call("pack_specs", budget: 1).first?.array) ?? []).map { spec in
                    let name = spec["name"].string ?? "?"
                    let dir = spec["dir"].string.map { URL(fileURLWithPath: $0) }
                    let folder = dir ?? path.packs.appending(path: name)
                    return PackInfo(name: name, src: spec["src"].string, version: spec["version"].string, dir: dir,
                                    fromSettings: spec["from"].string == "settings", alsoInConfig: spec["in_config"].bool ?? false,
                                    folder: folder, installed: FileManager.default.fileExists(atPath: folder.path),
                                    commit: dir == nil ? lockfile?.plugins[name]?.rev : nil, allow: spec["allow"].array?.compactMap(\.string) ?? [])
                }
                result.widgets = ((try? runtime.call("widget_catalog", budget: 1).first?.array) ?? []).map { info in
                    WidgetInfo(name: info["name"].string ?? "?", description: info["description"].string,
                               file: info["file"].string.map { URL(fileURLWithPath: $0) }, card: info["card"].bool ?? false,
                               opts: info["opts"].table ?? [:], defaults: info["defaults"].table ?? [:],
                               choices: (info["choices"].table ?? [:]).compactMapValues { $0.array?.compactMap(\.string) },
                               families: info["families"].array?.compactMap(\.string) ?? [])
                }
            }
            runtime.stop()
            let base = LuaRuntime(path: path, settings: Settings(), delegate: .silent)
            base.sync {
                try? base.boot()
                result.base = (try? base.call("config", budget: 1).first) ?? .nil
            }
            base.stop()
            result.loaded = true
            return result
        }
    }

    /// A theme as init.lua and plugins leave it, before the window's changes: what Reset goes back to.
    /// `wallpaper` is the desktop picture, which some themes choose their background by.
    static func layout(of theme: String, config: URL, wallpaper: String?) async -> Result<ThemeLayout, LuaError> {
        await layout(of: theme, path: .standard(config: config), wallpaper: wallpaper)
    }

    static func layout(of theme: String, path: RuntimePath, wallpaper: String?) async -> Result<ThemeLayout, LuaError> {
        await background {
            let environment = LuaRuntime.Environment()
            environment.wallpaper = wallpaper
            let runtime = LuaRuntime(path: path, environment: environment, delegate: .silent)
            defer { runtime.stop() }
            return runtime.sync {
                do {
                    try runtime.boot()
                    let value = try runtime.call("theme_layout", [.string(theme)], budget: 1).first ?? .nil
                    return .success(ThemeLayout(id: theme, name: value["name"].string ?? theme, background: value["background"],
                                                widgets: value["widgets"].array ?? [], auth: value["auth"],
                                                cardStyle: value["card_style"].string ?? "glass"))
                } catch {
                    return .failure(LuaError(LuaError(String(describing: error)).summary))
                }
            }
        }
    }

    private static func background<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: body()) }
        }
    }
}

extension Inspection {
    /// Themes by the name people read, as every theme list shows them.
    var themesByName: [ThemeInfo] { themes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
}

extension Inspection.WidgetInfo {
    /// Where a widget comes from, by the file that defines it.
    enum Origin: Equatable {
        /// Locky's runtime.
        case locky
        /// A built-in theme package.
        case package
        /// The config folder, or no file: a widget defined from a string of Lua.
        case config
        /// A plugin, by its folder's name: the folder in the pack folder, else (a local plugin) the folder that holds its
        /// plugin/ or lua/ folder. A file in neither gives its short path.
        case plugin(String)
    }

    /// The inspector's source line and Add Widget's groups both follow it. Folders compare with their "/", so a folder
    /// next to the config folder, such as ~/.config/locky-dev, is a plugin of its own.
    var origin: Origin {
        guard let path = file?.path else { return .config }
        if path.hasPrefix(RuntimePath.builtInRuntime.path + "/") { return .locky }
        if path.hasPrefix(RuntimePath.resources.appending(path: "packages").path + "/") { return .package }
        if path.hasPrefix(RuntimePath.defaultConfig.path + "/") { return .config }
        let packs = RuntimePath.defaultPacks.path + "/"
        if path.hasPrefix(packs), let folder = path.dropFirst(packs.count).split(separator: "/").first { return .plugin(String(folder)) }
        let parts = path.split(separator: "/")
        if let index = parts.lastIndex(of: "plugin") ?? parts.lastIndex(of: "lua"), index > 0 { return .plugin(String(parts[index - 1])) }
        return .plugin(LuaError.shortenPaths(path))
    }

    /// Where the widget comes from, for people: nil for Locky's own (the runtime and the built-in packages), "Lua Config"
    /// for the config folder's, else the plugin's folder name.
    var source: String? {
        switch origin {
        case .locky, .package: nil
        case .config: "Lua Config"
        case .plugin(let folder): folder
        }
    }
}

/// A theme's own background and widget placements (widget, anchor, offset, size, align, card, display, and the
/// options before settings.json's), its password field's place, and its card style.
struct ThemeLayout: Sendable, Equatable {
    var id: String
    var name: String
    var background: LuaValue
    var widgets: [LuaValue]
    /// { anchor, offset }.
    var auth: LuaValue = .nil
    /// "glass", "solid", "outline", or "none".
    var cardStyle = "glass"
}

extension LuaRuntime.Delegate {
    /// For runtimes that only answer questions.
    static let silent = LuaRuntime.Delegate(present: { _, _ in }, failed: { _, _, _ in })
}
