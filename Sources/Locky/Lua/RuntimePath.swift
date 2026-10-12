import Foundation

/// Where Locky looks for Lua modules, plugin/ scripts, themes, shaders, and assets, like Neovim's
/// 'runtimepath'. Earlier roots win: the user's config folder, then packages from locky.pack.add, then the
/// built-in runtime, then the built-in theme packages.
struct RuntimePath: Sendable {
    /// The user's folder: init.lua, and the first root.
    var config: URL
    /// Where `locky pack sync` installs packages, one folder each.
    var packs: URL
    var roots: [URL]

    /// The lockfile that pins each package to a commit. It lives with the config, so dotfiles carry it.
    var lockfile: URL { config.appending(path: "locky-pack-lock.json") }

    /// $LOCKY_CONFIG_DIR, $XDG_CONFIG_HOME/locky, or ~/.config/locky. LOCKY_CONFIG_DIR moves only Locky's
    /// folder, so programs that widgets run (herdr, for one) still find their own config.
    static var defaultConfig: URL {
        if let dir = ProcessInfo.processInfo.environment["LOCKY_CONFIG_DIR"], dir.hasPrefix("/") { return URL(fileURLWithPath: dir) }
        return xdg("XDG_CONFIG_HOME", default: ".config").appending(path: "locky")
    }
    /// $XDG_DATA_HOME/locky/pack, or ~/.local/share/locky/pack.
    static var defaultPacks: URL { xdg("XDG_DATA_HOME", default: ".local/share").appending(path: "locky/pack") }

    /// Locky.app's Resources folder. Outside the app (swift test, swift run) it is the source tree's.
    static var resources: URL {
        // For theme and plugin work: run the built app against the source tree, without rebuilding it.
        if let override = ProcessInfo.processInfo.environment["LOCKY_RESOURCES"], override.hasPrefix("/") {
            return URL(fileURLWithPath: override)
        }
        if let bundled = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: bundled.appending(path: "runtime").path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources")
    }

    /// Core modules, core widgets, shaders, and the default theme.
    static var builtInRuntime: URL { resources.appending(path: "runtime") }

    /// The built-in theme packages, one folder each.
    static var builtInPackages: [URL] {
        let folder = resources.appending(path: "packages")
        let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return children.filter(\.hasDirectoryPath).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The path a session starts with. locky.pack.add inserts packages after the config folder.
    static func standard(config: URL = defaultConfig, packs: URL = defaultPacks) -> RuntimePath {
        RuntimePath(config: config, packs: packs, roots: [config, builtInRuntime] + builtInPackages)
    }

    private static func xdg(_ variable: String, default relative: String) -> URL {
        if let value = ProcessInfo.processInfo.environment[variable], value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: relative)
    }

    /// Adds a package after the config folder and the packages added before it.
    mutating func insertPackage(_ url: URL) {
        guard !roots.contains(url) else { return }
        let firstBuiltIn = roots.firstIndex(of: Self.builtInRuntime) ?? roots.endIndex
        roots.insert(url, at: firstBuiltIn)
    }

    /// The first file at `relative` under any root.
    func find(_ relative: String) -> URL? {
        guard Self.isSafe(relative) else { return nil }
        for root in roots {
            let url = root.appending(path: relative)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// lua/<a/b>.lua or lua/<a/b>/init.lua for the module "a.b".
    func findModule(_ name: String) -> URL? {
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || "_-.".contains($0) }) else { return nil }
        let relative = name.replacingOccurrences(of: ".", with: "/")
        for root in roots {
            for candidate in ["lua/\(relative).lua", "lua/\(relative)/init.lua"] {
                let url = root.appending(path: candidate)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    /// Every entry of `folder` across the roots, first root winning per name. A `suffix` that starts with
    /// "/" names a file inside a subfolder, such as "/health.lua"; otherwise it ends a file name, such as ".lua".
    func findAll(_ folder: String, suffix: String) -> [(name: String, url: URL)] {
        guard Self.isSafe(folder) else { return [] }
        var seen = Set<String>()
        var found: [(String, URL)] = []
        for root in roots {
            let directory = root.appending(path: folder)
            let entries = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
            for entry in entries where !entry.hasPrefix(".") {
                let name: String
                let url: URL
                if suffix.hasPrefix("/") {
                    name = entry
                    url = directory.appending(path: entry + suffix)
                } else {
                    guard entry.hasSuffix(suffix), entry.count > suffix.count else { continue }
                    name = String(entry.dropLast(suffix.count))
                    url = directory.appending(path: entry)
                }
                guard !seen.contains(name), FileManager.default.fileExists(atPath: url.path) else { continue }
                seen.insert(name)
                found.append((name, url))
            }
        }
        return found
    }

    /// plugin/*.lua in every root, in path order, then by file name.
    func pluginScripts() -> [URL] {
        roots.flatMap { root -> [URL] in
            let directory = root.appending(path: "plugin")
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return entries.filter { $0.hasSuffix(".lua") && !$0.hasPrefix(".") }.sorted().map { directory.appending(path: $0) }
        }
    }

    /// A relative path that stays inside its root.
    static func isSafe(_ relative: String) -> Bool {
        !relative.hasPrefix("/") && !relative.split(separator: "/").contains("..")
    }
}
