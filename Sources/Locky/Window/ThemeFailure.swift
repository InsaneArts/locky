import Foundation

/// The last lock's theme that did not load, and the theme Locky showed instead. The lock records it in
/// UserDefaults ("lastThemeFailure") as JSON: { "theme", "fallback", "message", "date" }.
struct ThemeFailure: Codable, Equatable {
    static let key = "lastThemeFailure"

    var theme: String
    var fallback: String
    var message: String
    /// Seconds since 1970.
    var date: Double
}

extension ThemeFailure {
    /// The record, as Data or as a string of JSON. Anything else is no record.
    static func read(_ defaults: UserDefaults) -> ThemeFailure? {
        guard let data = defaults.data(forKey: key) ?? defaults.string(forKey: key).map({ Data($0.utf8) }) else { return nil }
        return try? JSONDecoder().decode(ThemeFailure.self, from: data)
    }

    /// The record, unless the theme's package or init.lua changed after it: then it no longer says what a lock does.
    static func current(_ defaults: UserDefaults, inspection: Inspection, config: URL) -> ThemeFailure? {
        guard let failure = read(defaults) else { return nil }
        var path = RuntimePath.standard(config: config)
        for pack in inspection.packs where pack.installed { path.insertPackage(pack.folder) }
        var files = [config.appending(path: "init.lua")]
        // themes/<id>.lua's package: the folder that holds themes/.
        if let file = path.findAll("themes", suffix: ".lua").first(where: { $0.name == failure.theme })?.url {
            files.append(file.deletingLastPathComponent().deletingLastPathComponent())
        }
        guard let changed = lastChange(files), changed.timeIntervalSince1970 > failure.date else { return failure }
        return nil
    }

    /// "Tokyo Night failed to load on the last lock; Locky showed Aurora".
    func summary(_ inspection: Inspection) -> String {
        let name = { (id: String) in inspection.theme(id)?.name ?? id }
        return "\(name(theme)) failed to load on the last lock; Locky showed \(name(fallback))"
    }

    /// The newest modification date of the files, and of the files in the folders, among `urls`. settings.json
    /// and hidden files do not count: the window writes settings.json all the time.
    static func lastChange(_ urls: [URL]) -> Date? {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        var newest: Date?
        func note(_ url: URL) {
            guard url.lastPathComponent != "settings.json", let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory != true, let date = values.contentModificationDate else { return }
            newest = max(newest ?? date, date)
        }
        for url in urls {
            note(url)
            // A config folder linked from a dotfiles repo counts as the folder it points at.
            let files = FileManager.default.enumerator(at: url.resolvingSymlinksInPath(), includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
            while let file = files?.nextObject() as? URL { note(file) }
        }
        return newest
    }
}
