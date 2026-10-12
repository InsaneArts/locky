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

    struct WidgetInfo: Identifiable, Hashable, Sendable {
        var id: String { name }
        var name: String
        var description: String?
        var file: URL?
        /// Whether it sits on the theme's card when the theme does not say.
        var card = false
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
    var loaded = false

    func theme(_ id: String) -> ThemeInfo? { themes.first { $0.id == id } }
    func widget(_ name: String) -> WidgetInfo? { widgets.first { $0.name == name } }

    static func load(config: URL) async -> Inspection {
        await background {
            var result = Inspection()
            let path = RuntimePath.standard(config: config)
            let runtime = LuaRuntime(path: path, delegate: .silent)
            runtime.sync {
                try? runtime.boot()
                result.problems = runtime.problemsSoFar
                result.config = (try? runtime.call("config", budget: 1).first) ?? .nil
                result.themes = ((try? runtime.call("theme_infos", budget: 5).first?.array) ?? []).map { info in
                    ThemeInfo(id: info["id"].string ?? "?", name: info["name"].string ?? info["id"].string ?? "?",
                              description: info["description"].string, author: info["author"].string,
                              directory: info["dir"].string.map { URL(fileURLWithPath: $0) },
                              palette: (info["palette"].table ?? [:]).compactMapValues(\.string), error: info["error"].string)
                }
                result.packs = ((try? runtime.call("pack_specs", budget: 1).first?.array) ?? []).map { spec in
                    let name = spec["name"].string ?? "?"
                    let dir = spec["dir"].string.map { URL(fileURLWithPath: $0) }
                    let folder = dir ?? path.packs.appending(path: name)
                    return PackInfo(name: name, src: spec["src"].string, version: spec["version"].string, dir: dir,
                                    fromSettings: spec["from"].string == "settings", alsoInConfig: spec["in_config"].bool ?? false,
                                    folder: folder, installed: FileManager.default.fileExists(atPath: folder.path))
                }
                result.widgets = ((try? runtime.call("widget_catalog", budget: 1).first?.array) ?? []).map { info in
                    WidgetInfo(name: info["name"].string ?? "?", description: info["description"].string,
                               file: info["file"].string.map { URL(fileURLWithPath: $0) }, card: info["card"].bool ?? false)
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
    static func layout(of theme: String, config: URL) async -> Result<ThemeLayout, LuaError> {
        await background {
            let runtime = LuaRuntime(path: .standard(config: config), delegate: .silent)
            defer { runtime.stop() }
            return runtime.sync {
                do {
                    try runtime.boot()
                    let value = try runtime.call("theme_layout", [.string(theme)], budget: 1).first ?? .nil
                    return .success(ThemeLayout(id: theme, name: value["name"].string ?? theme, background: value["background"],
                                                widgets: value["widgets"].array ?? []))
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

/// A theme's own background and widget placements (widget, anchor, offset, size, align, card, display).
struct ThemeLayout: Sendable, Equatable {
    var id: String
    var name: String
    var background: LuaValue
    var widgets: [LuaValue]
}

extension LuaRuntime.Delegate {
    /// For runtimes that only answer questions.
    static let silent = LuaRuntime.Delegate(present: { _, _ in }, failed: { _, _, _ in })
}
