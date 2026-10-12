import Foundation

/// ~/.config/locky/settings.json: what the Locky window changes. Lua applies it right after init.lua, so a
/// key set here wins over init.lua, and a missing key leaves init.lua's value (or the default) in place.
/// The app's own settings (the shortcut, auto-lock, power) live here too, so dotfiles carry them. Keys
/// this version does not know stay in the file when the window saves it.
struct Settings: Equatable, Sendable {
    var values: [String: LuaValue]

    init(_ values: [String: LuaValue] = [:]) {
        self.values = values
    }

    static func url(config: URL) -> URL { config.appending(path: "settings.json") }

    /// The keys Lua reads (the rest are the app's). `packs` goes to Lua separately, before init.lua runs.
    static let luaKeys: Set<String> = ["theme", "auto_unlock", "hour24", "privacy", "message", "themes"]

    /// A missing file reads as empty settings. A file that is not a JSON object reads as empty settings and a
    /// problem; the window then shows the problem and leaves the file alone until it is fixed.
    static func load(config: URL) -> (settings: Settings, problem: String?) {
        let url = url(config: config)
        guard FileManager.default.fileExists(atPath: url.path) else { return (Settings(), nil) }
        let name = LuaError.shortenPaths(url.path)
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            guard size <= 1 << 20 else { return (Settings(), "\(name) is larger than 1 MB") }
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            guard let table = object as? [String: Any] else { return (Settings(), "\(name) must hold a JSON object") }
            return (Settings(LuaValue(json: table).table ?? [:]), nil)
        } catch {
            return (Settings(), "\(name) is not valid JSON: \(error.localizedDescription)")
        }
    }

    /// Writes the file atomically with sorted keys, so dotfile diffs stay small. A symlinked settings.json
    /// (dotfiles managed with stow, for one) keeps its link: the write goes to the file it points at.
    func save(config: URL) throws {
        let url = Self.url(config: config).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let object = try values.mapValues { try $0.jsonObject() }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    subscript(key: String) -> LuaValue {
        get { values[key] ?? .nil }
        set {
            if newValue.isNil { values.removeValue(forKey: key) } else { values[key] = newValue }
        }
    }

    /// What Lua's apply_settings reads.
    var lua: LuaValue { .table(values.filter { Self.luaKeys.contains($0.key) }) }

    /// Package specs, as locky.pack.add takes them: "user/repo", a URL, or { src, version, name }.
    var packs: [LuaValue] {
        get { self["packs"].array ?? [] }
        set { self["packs"] = newValue.isEmpty ? .nil : .array(newValue) }
    }
}
