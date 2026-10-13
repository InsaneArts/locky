import Foundation

/// One problem from the config as the windows show it: Lua's message with a capital first letter, and the file and line
/// it names when they exist. Lua Config lists them; the failed-theme banner opens one.
struct ConfigProblem: Equatable {
    var message: String
    var file: URL?
    var line: Int?

    /// Reads `LuaError(problem).summary`, then finds its file: an absolute or "~" path that exists, or Lua's shortened
    /// "...…/init.lua", which means `config`'s init.lua. With a file, the "file:line: " prefix leaves the message.
    init(_ problem: String, config: URL) {
        let summary = LuaError(problem).summary
        message = summary.capitalizedFirst
        guard let match = summary.firstMatch(of: /^(.+?\.lua):(\d+):\s*/), let line = Int(match.2) else { return }
        let path = (String(match.1) as NSString).expandingTildeInPath
        if path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) {
            file = URL(fileURLWithPath: path)
        } else if path.hasPrefix("..."), path.hasSuffix("/init.lua") {
            file = config.appending(path: "init.lua")
        } else {
            return
        }
        self.line = line
        message = String(summary[match.range.upperBound...]).capitalizedFirst
    }
}
