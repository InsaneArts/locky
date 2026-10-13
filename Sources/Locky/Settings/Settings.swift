import Foundation

/// ~/.config/locky/settings.json: what the Locky window changes. Lua applies it before init.lua runs (so the
/// modules init.lua requires already see privacy mode) and again after the plugin scripts, so a key set here
/// wins over init.lua and plugins, and a missing key leaves their value (or the default) in place.
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
        load(file: url(config: config))
    }

    static func load(file url: URL) -> (settings: Settings, problem: String?) {
        let name = LuaError.shortenPaths(url.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // A link to a file that is not there (dotfiles on a volume not mounted yet) is an error, not "no
            // settings": empty settings would replace the last good ones, and a save would replace the link.
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
                return (Settings(), "\(name) links to \(LuaError.shortenPaths(target)), which is not there")
            }
            return (Settings(), nil)
        }
        do {
            // The size of the file a symlink points at, not of the link.
            let size = (try FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)[.size] as? Int) ?? 0
            guard size <= 1 << 20 else { return (Settings(), "\(name) is larger than 1 MB") }
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            guard let table = object as? [String: Any] else { return (Settings(), "\(name) must hold a JSON object") }
            return (Settings(LuaValue(json: table).table ?? [:]), nil)
        } catch {
            return (Settings(), "\(name) is not valid JSON: \(error.localizedDescription)")
        }
    }

    /// Writes the file atomically with sorted keys, so dotfile diffs stay small, and with mode 0600. A symlinked
    /// settings.json (dotfiles managed with stow, for one) keeps its link: the write goes to the file it points at.
    func save(config: URL) throws {
        try save(file: Self.url(config: config))
    }

    func save(file: URL) throws {
        let url = file.resolvingSymlinksInPath()
        try Self.createFolder(url.deletingLastPathComponent())
        let object = try values.mapValues { try $0.jsonObject() }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        // load refuses a larger file, so writing one would leave settings that cannot be read back.
        guard data.count <= 1 << 20 else { throw LuaError("settings.json would grow past 1 MB") }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Creates `folder`, such as the config folder, with mode 0700 when it is not there. A folder that is there
    /// keeps its mode: it is not Locky's.
    static func createFolder(_ folder: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: folder.path) else { return }
        try fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
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

extension Settings {
    /// themes.<theme>.<key>: the window's change to a theme's "background" or "widgets".
    func themeEdit(_ theme: String, _ key: String) -> LuaValue {
        self["themes"][theme][key]
    }

    /// Sets themes.<theme>.<key>, or removes it for nil; a theme left with no changes goes too.
    mutating func setThemeEdit(_ theme: String, _ key: String, _ value: LuaValue?) {
        var themes = self["themes"].table ?? [:]
        var entry = themes[theme]?.table ?? [:]
        entry[key] = value
        themes[theme] = entry.isEmpty ? nil : .table(entry)
        self["themes"] = themes.isEmpty ? .nil : .table(themes)
    }
}
