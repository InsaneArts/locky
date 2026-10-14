import Foundation

/// One problem from the config as the windows show it: Lua's message with a capital first letter, and the file and line
/// it names when they exist. Lua Config lists them; the failed-theme banner opens one.
struct ConfigProblem: Equatable {
    var message: String
    var file: URL?
    var line: Int?

    /// Reads `LuaError(problem).summary`, then finds its file: an absolute or "~" path that exists, or a path Lua
    /// shortened from the front: "...…/init.lua" means `config`'s init.lua, and any other the file in `config` or the
    /// plugins' folder whose path ends so, such as a theme in themes/. With a file, the "file:line: " prefix leaves the
    /// message.
    init(_ problem: String, config: URL) {
        let summary = LuaError(problem).summary
        message = summary.capitalizedFirst
        guard let match = summary.firstMatch(of: /^(.+?\.lua):(\d+):\s*/), let line = Int(match.2) else { return }
        let path = (String(match.1) as NSString).expandingTildeInPath
        if path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) {
            file = URL(fileURLWithPath: path)
        } else if path.hasPrefix("..."), path.hasSuffix("/init.lua") {
            file = config.appending(path: "init.lua")
        } else if path.hasPrefix("..."), let found = Self.file(endingWith: String(path.dropFirst(3)), in: [config, RuntimePath.defaultPacks]) {
            file = found
        } else {
            return
        }
        self.line = line
        message = String(summary[match.range.upperBound...]).capitalizedFirst
    }

    /// The message, then the file's name and the line on a line of their own when they are known: as Customize and
    /// the gallery's tile show a theme that does not load.
    var described: String {
        guard let file, let line else { return message }
        return "\(message)\n\(file.lastPathComponent), line \(line)"
    }

    /// The file in one of `folders` whose whole path ends with `tail`. Lua cuts a chunk name inside a folder's name,
    /// so the tail's first part may be half a name: each shorter tail is tried below each folder.
    private static func file(endingWith tail: String, in folders: [URL]) -> URL? {
        let parts = tail.split(separator: "/")
        for start in parts.indices {
            let relative = parts[start...].joined(separator: "/")
            for folder in folders {
                let candidate = folder.appending(path: relative)
                if candidate.path.hasSuffix(tail), FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }
}
